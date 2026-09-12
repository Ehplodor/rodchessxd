class_name CarnetPresenter
extends RefCounted
## CarnetPresenter.gd — Couche T1 de l'UI LeCarnet : état de présentation et médiation
## entre le domaine (CarnetProfiles/Store/Trainer/BatchRunner) et les vues.
##
## Aucun widget ici : uniquement de l'état, des signaux et du formatage FR. Les vues
## (T2) s'abonnent et appellent ces méthodes ; les composants (T3) ne consomment que
## des données brutes. Testable sans scène (voir tests/test_carnet_presenter.gd).

signal profiles_changed
signal sync_changed
signal carnet_changed
signal plan_changed
signal batch_progress(done: int, total: int, game_id: String)
signal batch_state(state: String)
signal session_changed
signal session_finished(summary: Dictionary)
signal error(message: String)
signal profile_updated(profile_id: String)
signal game_list_changed
signal toast_requested(msg: String, is_success: bool)
signal bulk_import_progress(phase: String, current: int, total: int)

## Profil actif et données de contexte.
var profile_id := ""
var profiles: Array = []
var sync: Dictionary = {}
var ledger: Dictionary = {}
var plan: Dictionary = {}
var batch: CarnetBatchRunner = null
var session: Dictionary = {}

var _analyzer: Callable = Callable()
var _engine_free: Callable = Callable()
var _chesscom_service: ChessComService = null
var _chesscom_profile_name: String = ""
var _chesscom_batch_depth: int = 14
var _chesscom_batch_mode: String = "dynamic"

# ── Profils (L1) ─────────────────────────────────────────────────────────────────

func refresh_profiles() -> void:
	# `active_id()` crée le profil par défaut si nécessaire : à appeler avant `list()`.
	profile_id = CarnetProfiles.active_id()
	profiles = CarnetProfiles.list()
	profiles_changed.emit()

func select_profile(id: String) -> void:
	if CarnetProfiles.get_profile(id).is_empty():
		return
	CarnetProfiles.set_active(id)
	profile_id = id
	sync = {}
	ledger = {}
	plan = {}
	session = {}
	profiles_changed.emit()

func create_profile(name: String, source: String = "local", player_keys: Array = []) -> String:
	var id := CarnetProfiles.create(name, source, player_keys)
	refresh_profiles()
	select_profile(id)
	return id

func delete_profile(id: String) -> void:
	CarnetProfiles.delete(id)
	if profile_id == id:
		refresh_profiles()
	else:
		profiles = CarnetProfiles.list()
		profiles_changed.emit()

func add_player_key(key: String) -> void:
	if profile_id == "":
		return
	CarnetProfiles.add_player_key(profile_id, key)
	refresh_profiles()

func rename_profile(profile_id: String, new_name: String) -> void:
	if new_name.strip_edges() == "":
		return
	CarnetProfiles.update(profile_id, {"name": new_name.strip_edges()})
	profile_updated.emit(profile_id)
	refresh_profiles()

func remove_player_key(profile_id: String, key: String) -> void:
	var profile := CarnetProfiles.get_profile(profile_id)
	if profile.is_empty():
		return
	var keys: Array = profile.get("player_keys", [])
	keys = keys.filter(func(k): return str(k) != key)
	CarnetProfiles.update(profile_id, {"player_keys": keys})
	profile_updated.emit(profile_id)
	refresh_profiles()
	refresh_sync()

func get_profile_games(profile_id: String) -> Array:
	_ensure_profile()
	var profile := CarnetProfiles.get_profile(profile_id)
	if profile.is_empty():
		return []
	var matches := CarnetProfiles.match_games(profile)
	var sync := CarnetStore.sync_status(profile_id)
	var entries: Dictionary = CarnetStore._load_sync(profile_id).get("entries", {})

	var status_lookup: Dictionary = {}
	for item in sync.get("known", []):
		status_lookup[str(item.get("game_id", ""))] = {"reason": str(item.get("reason", "up_to_date")), "status": "up_to_date"}
	for item in sync.get("pending", []):
		status_lookup[str(item.get("game_id", ""))] = {"reason": str(item.get("reason", "never_atomized")), "status": "pending"}
	for item in sync.get("stale", []):
		status_lookup[str(item.get("game_id", ""))] = {"reason": str(item.get("reason", "")), "status": "stale"}

	var db := _db()
	var index_by_id := {}
	if db != null:
		for summary in db.games_index:
			if summary is Dictionary:
				index_by_id[str(summary.get("id", ""))] = summary

	var out: Array = []
	for match in matches:
		var gid := str(match.get("game_id", ""))
		var entry: Dictionary = entries.get(gid, {})
		var perspective := str(entry.get("perspective", ""))
		var info: Dictionary = status_lookup.get(gid, {"reason": "never_atomized", "status": "pending"})
		var summary: Dictionary = index_by_id.get(gid, {})
		out.append({
			"game_id": gid,
			"perspective": perspective,
			"title": str(summary.get("title", match.get("title", ""))),
			"white_name": str(summary.get("white_name", "")),
			"black_name": str(summary.get("black_name", "")),
			"date": str(summary.get("date", "")),
			"status": str(info.get("status", "pending")),
			"reason": str(info.get("reason", "never_atomized")),
		})
	return out

func reanalyze_game(game_id: String, profile_id: String, options: Dictionary = {}) -> void:
	_ensure_profile()
	start_batch([game_id], options)

func remove_game_from_profile(game_id: String, profile_id: String) -> void:
	CarnetStore.remove_game(game_id, profile_id)
	sync_changed.emit()
	carnet_changed.emit()
	plan_changed.emit()
	game_list_changed.emit()

func import_pgn_to_profile(pgn_text: String, profile_id: String) -> Dictionary:
	var db := _db()
	if db == null:
		return {"game_id": "", "matched_keys": [], "new_keys": []}
	var game_id := str(db.record_pgn_game(pgn_text, "pgn_import", "", true))
	if game_id == "":
		return {"game_id": "", "matched_keys": [], "new_keys": []}
	var profile := CarnetProfiles.get_profile(profile_id)
	var keys: Array = profile.get("player_keys", [])
	var white_name := ""
	var black_name := ""
	var game: Dictionary = db.get_game(game_id)
	if not game.is_empty():
		white_name = str(game.get("white_name", "")).strip_edges().to_lower()
		black_name = str(game.get("black_name", "")).strip_edges().to_lower()
	var matched_keys: Array = []
	var new_keys: Array = []
	for name in [white_name, black_name]:
		if name != "":
			var norm := DatabaseManagerClass.normalize_player_key(name)
			if norm in keys:
				matched_keys.append(norm)
			else:
				new_keys.append(norm)
	return {"game_id": game_id, "matched_keys": matched_keys, "new_keys": new_keys}

func cycle_game_perspective(game_id: String) -> void:
	_ensure_profile()
	var sync := CarnetStore._load_sync(profile_id)
	var entries: Dictionary = sync.get("entries", {})
	var entry: Dictionary = entries.get(game_id, {})
	var current := str(entry.get("perspective", ""))
	var next_perspective := ""
	match current:
		"": next_perspective = "white"
		"white": next_perspective = "black"
		"black": next_perspective = ""
	CarnetStore.update_game_perspective(game_id, next_perspective, profile_id)
	sync_changed.emit()
	carnet_changed.emit()
	plan_changed.emit()
	game_list_changed.emit()

func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DatabaseManager")
	return null

# ── Synchronisation & carnets (L2/L3) ────────────────────────────────────────────

func refresh_sync() -> Dictionary:
	_ensure_profile()
	sync = CarnetStore.sync_status(profile_id)
	sync_changed.emit()
	return sync

func refresh_carnet(today_iso: String = "") -> Dictionary:
	_ensure_profile()
	ledger = CarnetStore.compile(today_iso, -1, profile_id)
	carnet_changed.emit()
	return ledger

func refresh_plan(today_iso: String = "") -> Dictionary:
	_ensure_profile()
	var result := CarnetStore.refresh_plan(today_iso, {}, profile_id)
	ledger = result.get("ledger", ledger)
	plan = result.get("plan", {})
	plan_changed.emit()
	return plan

# ── Traitement par lot (L2) ──────────────────────────────────────────────────────

func set_analyzer(analyzer: Callable) -> void:
	_analyzer = analyzer

## Fournisseur `() -> bool` : vrai si le moteur est libre pour le lot (éval live).
func set_engine_free_provider(provider: Callable) -> void:
	_engine_free = provider

func start_batch(game_ids: Array = [], options: Dictionary = {}) -> void:
	_ensure_profile()
	batch = CarnetBatchRunner.new()
	if _analyzer.is_valid():
		batch.analyzer = _analyzer
	else:
		# Repli : analyseur moteur par défaut (desktop), sinon le lot échouerait partout.
		batch.analyzer = CarnetBatchRunner.default_analyzer(
				int(options.get("depth", 14)), str(options.get("mode", "dynamic")))
	if _engine_free.is_valid():
		batch.engine_free = _engine_free
	batch.configure(profile_id, game_ids, options)
	batch.progress.connect(func(done, total, gid): batch_progress.emit(done, total, gid))
	batch.game_processed.connect(func(_gid, ok, msg):
		if not ok:
			error.emit(msg if msg != "" else "Échec d'analyse d'une partie."))
	batch.error.connect(func(msg): error.emit(msg))
	batch.start()
	batch_state.emit(batch.state)

## Traite une partie. Retourne true tant qu'il reste du travail (à appeler depuis `_process`).
func poll_batch() -> bool:
	if batch == null:
		return false
	batch.step()
	batch_state.emit(batch.state)
	if batch.state == "running":
		return true
	if batch.state == "done":
		refresh_sync()
	return false

func pause_batch() -> void:
	if batch != null:
		batch.pause()
		batch_state.emit(batch.state)

func resume_batch() -> void:
	if batch != null:
		batch.resume()
		batch_state.emit(batch.state)

func cancel_batch() -> void:
	if batch != null:
		batch.cancel()
		batch_state.emit(batch.state)
		batch = null

func is_batching() -> bool:
	return batch != null and batch.state == "running"

# ── Import bulk Chess.com (Phase F) ──────────────────────────────────────────────

func cancel_bulk_import() -> void:
	if _chesscom_service != null and is_instance_valid(_chesscom_service):
		_chesscom_service.cancel()
	cancel_batch()
	_cleanup_chesscom_service()

func bulk_import_chesscom(username: String, profile_name: String = "", options: Dictionary = {}) -> void:
	if _chesscom_service != null and is_instance_valid(_chesscom_service):
		_cleanup_chesscom_service()

	var max_months := int(options.get("max_months", 12))
	var max_games := int(options.get("max_games", 500))
	_chesscom_batch_depth = int(options.get("depth", 14))
	_chesscom_batch_mode = str(options.get("mode", "dynamic"))

	var name := profile_name.strip_edges()
	if name == "":
		name = "Chess.com • %s" % username.strip_edges()
	_chesscom_profile_name = name

	var pid := create_profile(name, "chess_com", [username.strip_edges()])
	if pid == "":
		error.emit("Impossible de créer le carnet Chess.com.")
		return

	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		error.emit("Scène introuvable pour initialiser le service Chess.com.")
		return

	_chesscom_service = ChessComService.new()
	tree.root.add_child(_chesscom_service)

	_chesscom_service.games_fetched.connect(_on_chesscom_games_fetched)
	_chesscom_service.fetch_error.connect(_on_chesscom_fetch_error)
	_chesscom_service.progress_fetched.connect(_on_chesscom_progress)

	bulk_import_progress.emit("fetching", 0, max_months)
	_chesscom_service.fetch_all_player_games(username, max_months, max_games)

func _on_chesscom_games_fetched(games: Array[Dictionary]) -> void:
	if _chesscom_service == null:
		return

	bulk_import_progress.emit("importing", 0, games.size())

	var db := _db()
	if db == null:
		error.emit("Base de données indisponible.")
		_cleanup_chesscom_service()
		return

	var game_ids: Array = []
	for i in range(games.size()):
		var g := games[i]
		var gid: String = db.record_chesscom_game(g)
		if gid != "":
			game_ids.append(gid)
		bulk_import_progress.emit("importing", i + 1, games.size())

	_cleanup_chesscom_service()

	if game_ids.is_empty():
		toast_requested.emit("Aucune partie importée pour le carnet '%s'." % _chesscom_profile_name, false)
		return

	bulk_import_progress.emit("analyzing", 0, game_ids.size())

	var batch_options := {
		"depth": _chesscom_batch_depth,
		"mode": _chesscom_batch_mode,
		"newest_first": true
	}
	start_batch(game_ids, batch_options)

	toast_requested.emit("Carnet '%s' créé avec %d parties — analyse en cours..." % [_chesscom_profile_name, game_ids.size()], true)

func _on_chesscom_fetch_error(err_msg: String, _diag: Dictionary) -> void:
	error.emit(err_msg)
	_cleanup_chesscom_service()

func _on_chesscom_progress(current: int, total: int, _count: int) -> void:
	bulk_import_progress.emit("fetching", current, total)

func _cleanup_chesscom_service() -> void:
	if _chesscom_service != null and is_instance_valid(_chesscom_service):
		_chesscom_service.cancel()
		if _chesscom_service.get_parent():
			_chesscom_service.get_parent().remove_child(_chesscom_service)
		_chesscom_service.queue_free()
		_chesscom_service = null

# ── Session de drills (L3) ───────────────────────────────────────────────────────

func start_plan_session() -> void:
	start_session(plan.get("drills", []))

## Démarre une séance sur une liste de drills explicite (testable sans plan).
func start_session(drills: Array) -> void:
	session = {
		"drills": drills.duplicate(),
		"index": 0,
		"correct": 0,
		"wrong": 0,
		"graded": 0,
		"phase": "running" if not drills.is_empty() else "done",
		"answered": false,
		"revealed": false,
		"last_result": {},
	}
	session_changed.emit()

func current_drill() -> Dictionary:
	if session.is_empty():
		return {}
	var drills: Array = session.get("drills", [])
	var idx := int(session.get("index", 0))
	if idx < 0 or idx >= drills.size():
		return {}
	var drill = drills[idx]
	return drill if drill is Dictionary else {}

func session_index() -> int:
	return int(session.get("index", 0))

func session_size() -> int:
	return (session.get("drills", []) as Array).size()

func is_session_done() -> bool:
	return session.is_empty() or str(session.get("phase", "")) == "done"

## Termine la séance (retour au plan).
func end_session() -> void:
	session = {}
	session_changed.emit()

## Propose un coup. Retourne { correct, expected, played, revealed }.
func answer(played_uci: String) -> Dictionary:
	if is_session_done():
		return {}
	if bool(session.get("answered", false)):
		return session.get("last_result", {})
	var drill := current_drill()
	if drill.is_empty():
		return {}
	var expected := str(drill.get("reponse_uci", ""))
	var correct := played_uci != "" and played_uci == expected
	if correct:
		session["correct"] = int(session.get("correct", 0)) + 1
	else:
		session["wrong"] = int(session.get("wrong", 0)) + 1
	session["answered"] = true
	session["revealed"] = not correct
	var result := {"correct": correct, "expected": expected, "played": played_uci, "revealed": not correct}
	session["last_result"] = result
	session_changed.emit()
	return result

## Révèle la solution d'un drill sans alternative (aucun QCM possible) : autorise la notation.
func reveal() -> Dictionary:
	if is_session_done() or bool(session.get("answered", false)):
		return {}
	var drill := current_drill()
	if drill.is_empty():
		return {}
	session["answered"] = true
	session["revealed"] = true
	var result := {
		"correct": false,
		"expected": str(drill.get("reponse_uci", "")),
		"played": "",
		"revealed": true,
		"gave_up": true,
	}
	session["last_result"] = result
	session_changed.emit()
	return result

## Note SM-2 (0-5) du drill courant puis passage au suivant.
func grade(note: int) -> bool:
	if is_session_done() or not bool(session.get("answered", false)):
		return false
	var drill := current_drill()
	if drill.is_empty():
		return false
	CarnetStore.record_review(str(drill.get("drill_id", "")), note, "", profile_id)
	session["graded"] = int(session.get("graded", 0)) + 1
	_advance()
	return true

## Passe au drill suivant sans noter.
func skip() -> void:
	if is_session_done():
		return
	_advance()

func _advance() -> void:
	session["index"] = int(session.get("index", 0)) + 1
	session["answered"] = false
	session["revealed"] = false
	session["last_result"] = {}
	if int(session["index"]) >= session_size():
		session["phase"] = "done"
	session_changed.emit()
	if str(session["phase"]) == "done":
		session_finished.emit(session_summary())

func session_summary() -> Dictionary:
	var total := session_size()
	var correct := int(session.get("correct", 0))
	var done := int(session.get("graded", 0))
	return {
		"total": total,
		"correct": correct,
		"wrong": int(session.get("wrong", 0)),
		"graded": done,
		"accuracy": (float(correct) / float(maxi(1, correct + int(session.get("wrong", 0))))) * 100.0,
		"phase": str(session.get("phase", "")),
	}

# ── Formatage FR (partagé vues/composants) ───────────────────────────────────────

func active_profile_name() -> String:
	var p := CarnetProfiles.get_profile(profile_id)
	return str(p.get("name", "Mon carnet")) if not p.is_empty() else "Mon carnet"

func sync_label() -> String:
	if sync.is_empty():
		return "—"
	var to_process: Array = sync.get("to_process", [])
	if to_process.is_empty():
		return "%d parties · à jour" % int(sync.get("total", 0))
	return "%d parties · %d à traiter" % [int(sync.get("total", 0)), to_process.size()]

func plan_objective() -> String:
	if bool(plan.get("est_jour_repos", false)):
		return "Jour de repos — rien à réviser."
	return str(plan.get("objectif", "Aucun objectif"))

static func reason_label(reason: String) -> String:
	match reason:
		"never_atomized": return "jamais traitée"
		"no_analysis": return "sans analyse moteur"
		"analysis_outdated": return "analyse à rafraîchir"
		"atoms_outdated": return "carnet à recalculer"
		"up_to_date": return "à jour"
	return reason

static func drill_type_label(type: String) -> String:
	match type:
		"trouve_le_coup": return "Trouve le meilleur coup"
		"choix_binaire": return "Lequel des deux ?"
		"trouve_la_brillance": return "Trouve la brillance"
		"résous_le_mystère": return "Résous le mystère"
	return type

static func grade_label(note: int) -> String:
	match note:
		1: return "Raté"
		3: return "Difficile"
		4: return "Bien"
		5: return "Facile"
	return "?"

## Options QCM d'un drill : le bon coup et le piège (coup réellement joué), en SAN.
## Permet une session v1 utilisable sans plateau ; le runner « board » viendra ensuite.
func drill_options(drill: Dictionary) -> Array:
	var fen := str(drill.get("position", ""))
	var best := str(drill.get("reponse_uci", ""))
	var trap := str(drill.get("piege_uci", ""))
	var opts: Array = []
	if best != "":
		opts.append({"uci": best, "san": uci_to_san(fen, best), "correct": true})
	if trap != "" and trap != best:
		opts.append({"uci": trap, "san": uci_to_san(fen, trap), "correct": false})
	return opts

## Convertit un coup UCI en SAN lisible depuis la position (repli : UCI brut).
static func uci_to_san(fen: String, uci: String) -> String:
	if fen == "" or uci == "":
		return uci
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return uci
	var move := game.find_move(uci)
	return move.san if move != null else uci

# ── Interne ──────────────────────────────────────────────────────────────────────

func _ensure_profile() -> void:
	if profile_id == "":
		profile_id = CarnetProfiles.active_id()
