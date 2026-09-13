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
var is_busy: bool = false
var active_analyzer: RefCounted = null

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
		if active_analyzer != null and active_analyzer.has_method("cancel_analysis"):
			active_analyzer.cancel_analysis()
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root and tree.root.has_node("EngineManager"):
			tree.root.get_node("EngineManager").stop_evaluation()
		save_job()

func resume() -> void:
	if state == "paused":
		state = "running"

func cancel() -> void:
	state = "cancelled"
	is_busy = false
	if active_analyzer != null and active_analyzer.has_method("cancel_analysis"):
		active_analyzer.cancel_analysis()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		tree.root.get_node("EngineManager").stop_evaluation()
	clear_job()

# ── Traitement ───────────────────────────────────────────────────────────────────

## Traite la partie courante. Retourne un résumé ; `state` porte l'issue globale.
func step() -> Dictionary:
	if is_busy:
		return {"state": state, "busy": true}
	if state != "running":
		return {"state": state, "done": true}
	if engine_free.is_valid() and not bool(engine_free.call()):
		state = "paused"
		return {"state": "paused", "reason": "engine_busy"}
	if cursor >= queue.size():
		return _finalize()

	is_busy = true
	var gid := str(queue[cursor])
	var db := _db()
	if db == null:
		is_busy = false
		last_error = "DatabaseManager indisponible"
		state = "failed"
		error.emit(last_error)
		return {"state": "failed", "error": last_error}

	var game: Dictionary = db.get_game(gid)
	if game.is_empty():
		print("[Carnet] [Mise à jour Lot] [%d/%d] Partie %s introuvable dans la base." % [cursor + 1, queue.size(), gid])
		_record_failure(gid, "partie introuvable")
		is_busy = false
		return {"ok": false, "game_id": gid, "error": "partie introuvable"}

	var white_name := str(game.get("white_name", "?"))
	var black_name := str(game.get("black_name", "?"))
	print("[Carnet] [Mise à jour Lot] [%d/%d] Début traitement partie %s (%s vs %s)" % [
		cursor + 1, queue.size(), gid, white_name, black_name
	])

	# Phase 1 — analyse moteur (uniquement si nécessaire).
	if _needs_analysis(gid, game):
		var engine_name := _get_active_engine_name()
		print("[Carnet]   -> Analyse moteur %s requise..." % engine_name)
		if not analyzer.is_valid():
			print("[Carnet]   -> Échec : aucun analyseur moteur fourni.")
			_record_failure(gid, "aucun analyseur fourni")
			is_busy = false
			return {"ok": false, "game_id": gid, "error": "analyzer_missing"}
		var report = await analyzer.call(game)
		if state != "running":
			is_busy = false
			return {"state": state, "interrupted": true}
		if not (report is Dictionary) or report.is_empty() or report.has("error"):
			var msg := "échec d'analyse" if not (report is Dictionary) else str(report.get("error", "échec d'analyse"))
			print("[Carnet]   -> Échec analyse moteur partie %s : %s" % [gid, msg])
			_record_failure(gid, msg)
			is_busy = false
			return {"ok": false, "game_id": gid, "error": msg}
		db.add_engine_analysis(gid, report)
		game = db.get_game(gid)
		print("[Carnet]   -> Analyse moteur enregistrée avec succès.")

	# Phase 2 — atomisation (déterministe, sans moteur).
	print("[Carnet]   -> Extraction algorithmique des atomes...")
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
	print("[Carnet]   -> Partie %s synchronisée (%d atomes créés)." % [gid, atoms.size()])

	cursor += 1
	processed += 1
	save_job()
	game_processed.emit(gid, true, "")
	progress.emit(processed, queue.size(), gid)
	is_busy = false
	if cursor >= queue.size():
		return _finalize()
	return {"ok": true, "game_id": gid, "atoms": atoms.size()}

## Pilote le lot jusqu'à complétion, pause ou `max_games`.
func run(max_games: int = -1) -> void:
	start()
	var count := 0
	while state == "running":
		var res := await step()
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
	print("[Carnet] [Mise à jour Lot] Terminé : %d partie(s) traitée(s), %d échec(s)." % [processed, failed])
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

static func _get_active_engine_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		var em = tree.root.get_node("EngineManager")
		if em.has_method("get_engine_display_name"):
			return em.get_engine_display_name()
	return "Stockfish"

## Analyseur moteur par défaut : reconstruit la partie et lance `GameAnalyzer`.
## Le PGN peut être absent (jeu libre/OCR) : on rejoue alors la liste de coups stockée.
static func default_analyzer(depth: int = -1, mode: String = "", on_ply: Callable = Callable(), custom_options: Dictionary = {}, on_depth: Callable = Callable(), runner: CarnetBatchRunner = null) -> Callable:
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
		var speed_cfg: Dictionary = CarnetConfig.get_analysis_speed_config()
		var eff_depth: int = depth if depth > 0 else int(speed_cfg.get("depth", 8))
		var eff_mode: String = mode if mode != "" else "dynamic"
		var opts: Dictionary = {
			"mode": eff_mode,
			"dynamic_base": float(custom_options.get("dynamic_base", speed_cfg.get("dynamic_base", 0.05))),
			"dynamic_max": float(custom_options.get("dynamic_max", speed_cfg.get("dynamic_max", 0.20))),
			"time_per_move": float(custom_options.get("time_per_move", speed_cfg.get("time_per_move", 0.08))),
		}
		for k in custom_options:
			opts[k] = custom_options[k]
		var label: String = str(speed_cfg.get("label", "⚡ Rapide"))
		var engine_name := _get_active_engine_name()
		print("[Carnet]   [Moteur %s] Config: %s (Prof. %d, base %.2fs, max %.2fs)" % [
			engine_name, label, eff_depth, opts["dynamic_base"], opts["dynamic_max"]
		])
		var analyzer := GameAnalyzer.new()
		if runner != null:
			runner.active_analyzer = analyzer
		analyzer.progress_updated.connect(func(ply: int, total: int):
			var pct := (float(ply) / maxi(1, total)) * 100.0
			print("[Carnet]   [Moteur %s] Coup %d/%d (%.0f%%)" % [engine_name, ply, total, pct])
			if on_ply.is_valid():
				on_ply.call(ply, total)
		)

		var tree := Engine.get_main_loop() as SceneTree
		var em: Node = null
		var eval_conn: Callable = Callable()
		if on_depth.is_valid() and tree and tree.root and tree.root.has_node("EngineManager"):
			em = tree.root.get_node("EngineManager")
			eval_conn = func(_score, _mate, d, _best, _pv, _multi):
				on_depth.call(d, eff_depth)
			em.evaluation_updated.connect(eval_conn)

		var report := await analyzer.start_game_analysis_async(cg, eff_depth, opts)

		if em != null and eval_conn.is_valid() and em.evaluation_updated.is_connected(eval_conn):
			em.evaluation_updated.disconnect(eval_conn)
		if runner != null and runner.active_analyzer == analyzer:
			runner.active_analyzer = null

		if report is Dictionary:
			report["depth"] = eff_depth
			report["engine_name"] = engine_name
			report["analysis_speed"] = label
		var evals: Array = report.get("evaluations", []) if report.get("evaluations", []) is Array else []
		print("[Carnet]   [Moteur %s] Évaluations terminées (%d coups analysés)." % [engine_name, evals.size()])
		return report
