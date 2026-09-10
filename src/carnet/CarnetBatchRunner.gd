class_name CarnetBatchRunner
extends RefCounted
## CarnetBatchRunner.gd — traitement par lot, local et reprisable, pour « remplir » un
## carnet à partir des parties d'un joueur déjà importées.
##
## Pipeline par partie : ANALYSE (moteur, si nécessaire) → ATOMISATION (GDScript pur)
## → ingestion dans le profil. Un seul moteur partagé : `engine_free` permet de mettre
## le lot en pause quand l'utilisateur a besoin du moteur (éval live).
##
## Le runner est volontairement un simple pilote `step()` :
## - testable sans moteur via `analyzer` injecté ;
## - pilotable par un fil (desktop) ou par `request_idle`/`process_frame` (Web).

signal progress(done: int, total: int, game_id: String)
signal game_processed(game_id: String, ok: bool, error: String)
signal finished(processed: int, failed: int)
signal error(message: String)

var profile_id := ""
var queue: Array = []
var cursor := 0
var state := "idle" # idle | running | paused | done | cancelled | failed
var options := {}
var processed := 0
var failed := 0
var last_error := ""

## Callable `(game: Dictionary) -> Dictionary` renvoyant un rapport d'analyse moteur.
## Vide ⇒ le runner suppose l'analyse déjà présente sur la partie.
var analyzer: Callable = Callable()
## Callable `() -> bool` : vrai si le lot peut utiliser le moteur maintenant.
var engine_free: Callable = Callable()

static func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DatabaseManager")
	return null

static func _job_path(profile_id: String) -> String:
	return "%s/profiles/%s/batch.json" % [DatabaseManagerClass.CARNETS_DIR, profile_id]

## Prépare la file d'un profil. `game_ids` vide ⇒ delta `sync_status` (pending + stale).
func configure(p_profile_id: String, game_ids: Array = [], p_options: Dictionary = {}) -> void:
	profile_id = p_profile_id
	options = p_options.duplicate(true)
	if game_ids.is_empty():
		var status := CarnetStore.sync_status(profile_id)
		var ids: Array = []
		var force: Dictionary = {}
		for item in status.get("to_process", []):
			if item is Dictionary:
				var item_id := str(item.get("game_id", ""))
				ids.append(item_id)
				var reason := str(item.get("reason", ""))
				if reason == "no_analysis" or reason == "analysis_outdated":
					force[item_id] = true
		game_ids = ids
		options["force_analysis_ids"] = force
	if not (options.get("force_analysis_ids", {}) is Dictionary):
		options["force_analysis_ids"] = {}
	if bool(options.get("newest_first", true)):
		game_ids = _sorted_by_date(game_ids, true)
	queue = game_ids
	cursor = int(options.get("cursor", 0))
	processed = 0
	failed = 0
	state = "idle"
	_build_perspectives()

## Construit la carte game_id -> perspective depuis le rattachement au profil.
func _build_perspectives() -> void:
	var existing = options.get("perspectives", {})
	if existing is Dictionary and not existing.is_empty():
		return
	var profile := CarnetProfiles.get_profile(profile_id)
	var map := {}
	for m in CarnetProfiles.match_games(profile):
		map[str(m.get("game_id", ""))] = str(m.get("perspective", ""))
	options["perspectives"] = map

func _sorted_by_date(ids: Array, newest_first: bool) -> Array:
	var db := _db()
	if db == null:
		return ids
	var index_by_id := {}
	for summary in db.games_index:
		if summary is Dictionary:
			index_by_id[str(summary.get("id", ""))] = summary
	var entries: Array = []
	for gid in ids:
		var summary: Dictionary = index_by_id.get(str(gid), {})
		entries.append({"id": str(gid), "date": str(summary.get("date", ""))})
	entries.sort_custom(func(a, b):
		return str(a["date"]) > str(b["date"]) if newest_first else str(a["date"]) < str(b["date"])
	)
	var out: Array = []
	for e in entries:
		out.append(e["id"])
	return out

func start() -> void:
	state = "running"
	save_job()

func pause() -> void:
	if state == "running":
		state = "paused"
		save_job()

func resume() -> void:
	if state == "paused":
		state = "running"

func cancel() -> void:
	state = "cancelled"
	clear_job()

# ── Traitement ───────────────────────────────────────────────────────────────────

## Traite la partie courante. Retourne un résumé ; `state` porte l'issue globale.
func step() -> Dictionary:
	if state != "running":
		return {"state": state, "done": true}
	if engine_free.is_valid() and not bool(engine_free.call()):
		state = "paused"
		return {"state": "paused", "reason": "engine_busy"}
	if cursor >= queue.size():
		return _finalize()

	var gid := str(queue[cursor])
	var db := _db()
	if db == null:
		last_error = "DatabaseManager indisponible"
		state = "failed"
		error.emit(last_error)
		return {"state": "failed", "error": last_error}

	var game: Dictionary = db.get_game(gid)
	if game.is_empty():
		_record_failure(gid, "partie introuvable")
		return {"ok": false, "game_id": gid, "error": "partie introuvable"}

	# Phase 1 — analyse moteur (uniquement si nécessaire).
	if _needs_analysis(gid, game):
		if not analyzer.is_valid():
			_record_failure(gid, "aucun analyseur fourni")
			return {"ok": false, "game_id": gid, "error": "analyzer_missing"}
		var report = analyzer.call(game)
		if not (report is Dictionary) or report.is_empty() or report.has("error"):
			var msg := "échec d'analyse" if not (report is Dictionary) else str(report.get("error", "échec d'analyse"))
			_record_failure(gid, msg)
			return {"ok": false, "game_id": gid, "error": msg}
		db.add_engine_analysis(gid, report)
		game = db.get_game(gid)

	# Phase 2 — atomisation (déterministe, sans moteur).
	var analysis := _latest_analysis(game)
	var perspective := str(options.get("perspectives", {}).get(gid, ""))
	var atoms := CarnetEvents.annotate_game(game, analysis, {
		"couleur_joueur": perspective,
		"mode_analyse": bool(options.get("mode_analyse", false)),
	})
	CarnetStore.ingest_game(gid, atoms, {
		"date_iso": str(game.get("date", "")),
		"perspective": perspective,
		"analysis_version": int(game.get("analysis_version", 0)),
	}, profile_id)

	cursor += 1
	processed += 1
	save_job()
	game_processed.emit(gid, true, "")
	progress.emit(processed, queue.size(), gid)
	if cursor >= queue.size():
		return _finalize()
	return {"ok": true, "game_id": gid, "atoms": atoms.size()}

## Pilote le lot jusqu'à complétion, pause ou `max_games`.
func run(max_games: int = -1) -> void:
	start()
	var count := 0
	while state == "running":
		var res := step()
		if state != "running":
			break
		count += 1
		if max_games > 0 and count >= max_games:
			break

func _needs_analysis(game_id: String, game: Dictionary) -> bool:
	if bool(options.get("force_analysis", false)):
		return true
	var forced: Dictionary = options.get("force_analysis_ids", {})
	if forced is Dictionary and forced.has(game_id):
		return true
	if str(game.get("analysis_status", "none")) != "done":
		return true
	var analyses = game.get("engine_analyses", [])
	return not (analyses is Array) or analyses.is_empty()

func _latest_analysis(game: Dictionary) -> Dictionary:
	var analyses: Array = game.get("engine_analyses", []) if game.get("engine_analyses", []) is Array else []
	return analyses[-1] if not analyses.is_empty() else {"evaluations": [], "opening": {}, "theory_plies": 0}

func _record_failure(game_id: String, message: String) -> void:
	last_error = message
	failed += 1
	cursor += 1
	save_job()
	game_processed.emit(game_id, false, message)
	progress.emit(processed, queue.size(), game_id)

func _finalize() -> Dictionary:
	state = "done"
	clear_job()
	finished.emit(processed, failed)
	return {"state": "done", "done": true, "processed": processed, "failed": failed}

# ── Persistance / reprise ────────────────────────────────────────────────────────

func save_job() -> void:
	var db := _db()
	if db == null or profile_id == "":
		return
	db.save_json_atomic(_job_path(profile_id), {
		"schema_version": CarnetConfig.CARNET_SCHEMA_VERSION,
		"profile_id": profile_id,
		"queue": queue,
		"cursor": cursor,
		"state": state,
		"options": options,
		"processed": processed,
		"failed": failed,
		"updated_at": int(Time.get_unix_time_from_system()),
	})

## Recharge un lot interrompu pour un profil (le cas échéant).
static func load_job(profile_id: String) -> Dictionary:
	var db := _db()
	if db == null:
		return {}
	return db.load_json(_job_path(profile_id))

static func clear_job_for(profile_id: String) -> void:
	var db := _db()
	if db != null:
		db.remove_file(_job_path(profile_id))

func clear_job() -> void:
	CarnetBatchRunner.clear_job_for(profile_id)

## Analyseur moteur par défaut (desktop) : reconstruit la partie et lance `GameAnalyzer`.
## Le PGN peut être absent (jeu libre/OCR) : on rejoue alors la liste de coups stockée.
static func default_analyzer(depth: int = 14, mode: String = "dynamic") -> Callable:
	return func(game: Dictionary) -> Dictionary:
		var cg = ChessGame.new()
		var pgn := str(game.get("pgn_text", ""))
		var ok := pgn != "" and cg.load_pgn(pgn)
		if not ok:
			cg.load_fen(str(game.get("initial_fen", ChessGame.INITIAL_FEN)))
			for mv in game.get("moves", []):
				if not (mv is Dictionary):
					continue
				var m = cg.find_move(str(mv.get("uci", "")))
				if m != null:
					cg.make_move(m)
		if cg.move_history.is_empty():
			return {"error": "partie_vide"}
		var analyzer := GameAnalyzer.new()
		return analyzer.start_game_analysis(cg, depth, {"mode": mode})
