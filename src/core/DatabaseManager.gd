class_name DatabaseManagerClass
extends Node
## DatabaseManager.gd - Gestionnaire de persistance locale de RodChessXD
## Sauvegarde exhaustive de toutes les parties (PGN, Chess.com, OCR, jeu libre)
## et archivage multi-analyses (moteurs d'échecs et coachs LLM)

signal game_saved(game_id: String)
signal game_deleted(game_id: String)
signal analysis_added(game_id: String, analysis_type: String)

const BASE_DIR = "user://library"
const GAMES_DIR = "user://library/games"
const INDEX_FILE = "user://library/games_index.json"
## LeCarnet (§4.12-4.13) : un dossier par profil joueur (atomes, sync, trainer).
const CARNETS_DIR = "user://library/carnets"
const PROFILES_DIR = "user://library/carnets/profiles"

var games_index: Array[Dictionary] = []

func _ready() -> void:
	_ensure_directories()
	_load_index()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_PREDELETE:
		if not games_index.is_empty():
			_save_index()
		sync_to_storage()

func _ensure_directories() -> void:
	var da = DirAccess.open("user://")
	if da:
		if not da.dir_exists("library"):
			da.make_dir("library")
		if not da.dir_exists("library/games"):
			da.make_dir("library/games")
		if not da.dir_exists("library/carnets"):
			da.make_dir("library/carnets")
		if not da.dir_exists("library/carnets/profiles"):
			da.make_dir("library/carnets/profiles")

func _load_index() -> void:
	games_index.clear()
	var loaded_ok := false
	if FileAccess.file_exists(INDEX_FILE):
		var f = FileAccess.open(INDEX_FILE, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f = null
			var json = JSON.parse_string(txt)
			if json is Array:
				for item in json:
					if item is Dictionary:
						games_index.append(item)
				loaded_ok = true

	# Récupération automatique 1 : si l'index principal est corrompu ou vide, tenter le .bak
	if (not loaded_ok or games_index.is_empty()) and FileAccess.file_exists(INDEX_FILE + ".bak"):
		var f_bak = FileAccess.open(INDEX_FILE + ".bak", FileAccess.READ)
		if f_bak:
			var txt_bak = f_bak.get_as_text()
			f_bak = null
			var json_bak = JSON.parse_string(txt_bak)
			if json_bak is Array and not json_bak.is_empty():
				games_index.clear()
				for item in json_bak:
					if item is Dictionary:
						games_index.append(item)
				loaded_ok = true
				print("DatabaseManager: Index principal restauré depuis %s.bak (%d parties)." % [INDEX_FILE, games_index.size()])
				_save_index()

	# Récupération automatique 2 : si aucun index n'a pu être chargé mais que des fichiers de parties existent, reconstruire l'index
	if not loaded_ok or games_index.is_empty():
		_rebuild_index_from_disk()

	_sort_index_by_date()

func _rebuild_index_from_disk() -> void:
	var da = DirAccess.open(GAMES_DIR)
	if not da:
		return
	da.list_dir_begin()
	var fname = da.get_next()
	var count = 0
	while fname != "":
		if not da.current_is_dir() and fname.ends_with(".json"):
			var gid = fname.get_basename()
			var game_data = get_game(gid)
			if not game_data.is_empty():
				_update_index_entry(game_data)
				count += 1
		fname = da.get_next()
	da.list_dir_end()
	if count > 0:
		print("DatabaseManager: Index des parties reconstruit depuis le disque (%d parties trouvées)." % count)
		_save_index()

func _save_index() -> void:
	_sort_index_by_date()
	save_json_atomic(INDEX_FILE, games_index)

func _sort_index_by_date() -> void:
	games_index.sort_custom(func(a, b):
		return a.get("last_modified", 0) > b.get("last_modified", 0)
	)

## Enregistre ou met à jour une partie complète
func save_game(game_data: Dictionary) -> String:
	_ensure_directories()
	var game_id = game_data.get("id", "")
	if game_id == "":
		game_id = _generate_game_id()
		game_data["id"] = game_id

	var now = int(Time.get_unix_time_from_system())
	game_data["last_modified"] = now

	# Écriture atomique du fichier individuel
	var path = "%s/%s.json" % [GAMES_DIR, game_id]
	save_json_atomic(path, game_data)

	# Mise à jour de l'index
	_update_index_entry(game_data)
	_save_index()
	game_saved.emit(game_id)
	return game_id

## Enregistre un lot de parties en une seule passe I/O (index écrit une seule fois)
func save_games_batch(games_list: Array[Dictionary]) -> Array[String]:
	_ensure_directories()
	var saved_ids: Array[String] = []
	var now = int(Time.get_unix_time_from_system())

	for game_data in games_list:
		var game_id = game_data.get("id", "")
		if game_id == "":
			game_id = _generate_game_id()
			game_data["id"] = game_id

		game_data["last_modified"] = now
		var path = "%s/%s.json" % [GAMES_DIR, game_id]
		save_json_atomic(path, game_data)
		_update_index_entry(game_data)
		saved_ids.append(game_id)
		game_saved.emit(game_id)

	_save_index()
	return saved_ids

## Récupère le dossier complet d'une partie
func get_game(game_id: String) -> Dictionary:
	var path = "%s/%s.json" % [GAMES_DIR, game_id]
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return {}
	var json = JSON.parse_string(f.get_as_text())
	return json if json is Dictionary else {}

## Liste tous les résumés de parties de l'index (recherche & filtres optionnels)
func list_games(search_query: String = "", filter_source: String = "all") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var q = search_query.strip_edges().to_lower()

	for item in games_index:
		if filter_source != "all" and item.get("source", "") != filter_source:
			continue
		
		if q != "":
			var title = item.get("title", "").to_lower()
			var white = item.get("white_name", "").to_lower()
			var black = item.get("black_name", "").to_lower()
			var date_str = item.get("date", "").to_lower()
			var event_str = item.get("event", "").to_lower()
			if not (q in title or q in white or q in black or q in date_str or q in event_str):
				continue

		result.append(item)
	return result

## Supprime une partie, ses analyses et ses traces dans tous les carnets (§4.12).
func delete_game(game_id: String) -> bool:
	var path = "%s/%s.json" % [GAMES_DIR, game_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	
	for i in range(games_index.size() - 1, -1, -1):
		if games_index[i].get("id", "") == game_id:
			games_index.remove_at(i)
			break
	
	_purge_carnet_game(game_id)
	_save_index()
	game_deleted.emit(game_id)
	return true

## Retire les atomes et l'entrée de synchronisation d'une partie dans TOUS les profils.
## Évite qu'un carnet continue de consommer une partie supprimée de la bibliothèque.
func _purge_carnet_game(game_id: String) -> void:
	if game_id == "":
		return
	var da := DirAccess.open(PROFILES_DIR)
	if da == null:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry != "." and entry != ".." and da.current_is_dir():
			var base := "%s/%s" % [PROFILES_DIR, entry]
			remove_file("%s/atoms/%s.json" % [base, game_id])
			var sync := load_json("%s/sync.json" % base)
			var entries = sync.get("entries", null)
			if entries is Dictionary and entries.has(game_id):
				entries.erase(game_id)
				sync["entries"] = entries
				save_json_atomic("%s/sync.json" % base, sync)
		entry = da.get_next()
	da.list_dir_end()

## Ajoute une analyse moteur (Stockfish, etc.) sans écraser les précédentes
func add_engine_analysis(game_id: String, analysis_data: Dictionary) -> void:
	if game_id == "":
		return
	var game_data = get_game(game_id)
	if game_data.is_empty():
		return

	if not game_data.has("engine_analyses"):
		game_data["engine_analyses"] = []

	var now = int(Time.get_unix_time_from_system())
	analysis_data["id"] = "ea_%d" % now
	analysis_data["timestamp"] = now
	analysis_data["date_str"] = Time.get_datetime_string_from_system(false, true)

	game_data["engine_analyses"].append(analysis_data)
	# Statut/version au niveau partie : sert au calcul de fraîcheur du Carnet (§4.12).
	game_data["analysis_status"] = "done"
	game_data["analysis_version"] = int(analysis_data.get("schema_version", analysis_data.get("depth", 0)))
	game_data["last_analysis_at"] = now
	save_game(game_data)
	analysis_added.emit(game_id, "engine")

## Ajoute une explication/note du coach IA pour cette partie
func add_coach_analysis(game_id: String, coach_data: Dictionary) -> void:
	if game_id == "":
		return
	var game_data = get_game(game_id)
	if game_data.is_empty():
		return

	if not game_data.has("coach_analyses"):
		game_data["coach_analyses"] = []

	var now = int(Time.get_unix_time_from_system())
	coach_data["id"] = "ca_%d" % now
	coach_data["timestamp"] = now
	coach_data["date_str"] = Time.get_datetime_string_from_system(false, true)

	game_data["coach_analyses"].append(coach_data)
	save_game(game_data)
	analysis_added.emit(game_id, "coach")

## Crée ou met à jour une partie importée via PGN.
## `external_id` : identifiant stable de la partie (URL Chess.com, uuid, etc.) ; s'il est
## vide, il est dérivé du contenu (joueurs/date/résultat/coups) pour dédoublonner les
## réimports. `dedupe = false` force la création d'une nouvelle entrée (jeu libre).
func record_pgn_game(pgn_text: String, source: String = "pgn_import", external_id: String = "", dedupe: bool = true) -> String:
	var dummy_game = ChessGame.new()
	var success = dummy_game.load_pgn(pgn_text)
	if not success:
		return ""

	var w_name = dummy_game.pgn_headers.get("White", "Joueur Blanc")
	var b_name = dummy_game.pgn_headers.get("Black", "Joueur Noir")
	var w_elo = int(dummy_game.pgn_headers.get("WhiteElo", "0"))
	var b_elo = int(dummy_game.pgn_headers.get("BlackElo", "0"))
	var date_val = dummy_game.pgn_headers.get("Date", Time.get_date_string_from_system())
	var res = dummy_game.pgn_headers.get("Result", "*")
	var event_val = dummy_game.pgn_headers.get("Event", "Partie Importée")
	var eco = dummy_game.pgn_headers.get("ECO", "")

	if external_id == "":
		external_id = _compute_external_id(dummy_game)
	if dedupe:
		var existing := find_game_by_external_id(external_id)
		if existing != "":
			return existing

	var moves_arr: Array[Dictionary] = []
	for i in range(dummy_game.move_history.size()):
		var m = dummy_game.move_history[i]
		moves_arr.append({
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": (i % 2 == 0),
			"san": m.san,
			"uci": m.uci
		})

	var game_data = {
		"title": "%s vs %s" % [w_name, b_name],
		"white_name": w_name,
		"black_name": b_name,
		"white_elo": w_elo,
		"black_elo": b_elo,
		"event": event_val,
		"date": date_val,
		"result": res,
		"eco": eco,
		"source": source,
		"external_id": external_id,
		"player_keys": _player_keys_for(w_name, b_name),
		"analysis_status": "none",
		"analysis_version": 0,
		"initial_fen": ChessGame.INITIAL_FEN,
		"pgn_text": pgn_text,
		"moves": moves_arr,
		"engine_analyses": [],
		"coach_analyses": []
	}
	return save_game(game_data)

## Crée ou met à jour une partie importée depuis Chess.com
func record_chesscom_game(game_info: Dictionary) -> String:
	var pgn = game_info.get("pgn", "")
	var w_user = game_info.get("white_user", "Blancs")
	var b_user = game_info.get("black_user", "Noirs")
	var w_rat = game_info.get("white_rating", 0)
	var b_rat = game_info.get("black_rating", 0)
	var cadence = game_info.get("time_class", "partie")
	var res = game_info.get("user_result", "draw")
	var external_id = str(game_info.get("url", game_info.get("uuid", "")))

	var game_id = record_pgn_game(pgn, "chess_com", external_id, true)
	if game_id != "":
		var data = get_game(game_id)
		data["title"] = "⚪ %s (%d) vs ⚫ %s (%d)" % [w_user, w_rat, b_user, b_rat]
		data["white_name"] = w_user
		data["black_name"] = b_user
		data["white_elo"] = w_rat
		data["black_elo"] = b_rat
		data["event"] = "Chess.com (%s)" % cadence.capitalize()
		data["result_label"] = res
		var keys: Array = data.get("player_keys", [])
		for extra in _player_keys_for(w_user, b_user, str(game_info.get("account", ""))):
			if not keys.has(extra):
				keys.append(extra)
		data["player_keys"] = keys
		save_game(data)
	return game_id

## Enregistre la position active de l'échiquier (ex: après scan OCR ou jeu manuel)
func record_active_game(game: ChessGame, title_override: String = "", source: String = "manual_play") -> String:
	var pgn = game.export_pgn()
	var w_name = game.pgn_headers.get("White", "Joueur 1")
	var b_name = game.pgn_headers.get("Black", "Joueur 2")
	var title = title_override if title_override != "" else ("%s vs %s" % [w_name, b_name])

	var moves_arr: Array[Dictionary] = []
	for i in range(game.move_history.size()):
		var m = game.move_history[i]
		moves_arr.append({
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": (i % 2 == 0),
			"san": m.san,
			"uci": m.uci,
			"quality": m.quality,
			"loss_cp": m.centipawn_loss
		})

	var game_data = {
		"title": title,
		"white_name": w_name,
		"black_name": b_name,
		"white_elo": int(game.pgn_headers.get("WhiteElo", "0")),
		"black_elo": int(game.pgn_headers.get("BlackElo", "0")),
		"event": game.pgn_headers.get("Event", "RodChessXD Game"),
		"date": Time.get_date_string_from_system(),
		"result": game.pgn_headers.get("Result", "*"),
		"source": source,
		"external_id": _compute_external_id(game),
		"player_keys": _player_keys_for(w_name, b_name),
		"analysis_status": "none",
		"analysis_version": 0,
		"initial_fen": ChessGame.INITIAL_FEN,
		"pgn_text": pgn,
		"moves": moves_arr,
		"engine_analyses": [],
		"coach_analyses": []
	}
	return save_game(game_data)

# --- OUTILS INTERNES ---

func _generate_game_id() -> String:
	var dt = Time.get_datetime_dict_from_system()
	var rand_val = randi() % 10000
	return "game_%04d%02d%02d_%02d%02d%02d_%04d" % [
		dt["year"], dt["month"], dt["day"],
		dt["hour"], dt["minute"], dt["second"],
		rand_val
	]

func _update_index_entry(game_data: Dictionary) -> void:
	var gid = game_data["id"]
	var summary = {
		"id": gid,
		"title": game_data.get("title", "Partie"),
		"white_name": game_data.get("white_name", ""),
		"black_name": game_data.get("black_name", ""),
		"white_elo": game_data.get("white_elo", 0),
		"black_elo": game_data.get("black_elo", 0),
		"date": game_data.get("date", ""),
		"result": game_data.get("result", "*"),
		"eco": game_data.get("eco", ""),
		"source": game_data.get("source", "pgn_import"),
		"external_id": game_data.get("external_id", ""),
		"player_keys": game_data.get("player_keys", []),
		"analysis_status": game_data.get("analysis_status", "none"),
		"analysis_version": game_data.get("analysis_version", 0),
		"moves_count": game_data.get("moves", []).size(),
		"engine_analyses_count": game_data.get("engine_analyses", []).size(),
		"coach_analyses_count": game_data.get("coach_analyses", []).size(),
		"last_modified": game_data.get("last_modified", 0)
	}

	var found = false
	for i in range(games_index.size()):
		if games_index[i].get("id", "") == gid:
			games_index[i] = summary
			found = true
			break

	if not found:
		games_index.append(summary)

# --- IDENTITÉ DES PARTIES & INDEXATION (§ imports / LeCarnet) ---

## Identifiant stable dérivé du contenu (joueurs/date/résultat/coups) : dédoublonne les
## réimports quand la source ne fournit pas d'identifiant externe.
func _compute_external_id(game: ChessGame) -> String:
	var moves := PackedStringArray()
	for m in game.move_history:
		moves.append(m.uci)
	var key := "%s|%s|%s|%s|%s" % [
		str(game.pgn_headers.get("White", "")),
		str(game.pgn_headers.get("Black", "")),
		str(game.pgn_headers.get("Date", "")),
		str(game.pgn_headers.get("Result", "*")),
		",".join(moves),
	]
	return HashUtil.sha1_hex(key)

func find_game_by_external_id(external_id: String) -> String:
	if external_id == "":
		return ""
	for item in games_index:
		if str(item.get("external_id", "")) == external_id:
			return str(item.get("id", ""))
	return ""

## Clés joueur normalisées d'une partie (blancs, noirs, compte source optionnel).
func _player_keys_for(white_name: String, black_name: String, account: String = "") -> Array:
	var keys: Array = []
	for raw in [white_name, black_name, account]:
		var k := normalize_player_key(str(raw))
		if k != "" and not keys.has(k):
			keys.append(k)
	return keys

## Normalise un nom pour le rattachement aux profils ; renvoie "" pour les placeholders.
static func normalize_player_key(name: String) -> String:
	var k := name.strip_edges().to_lower()
	while k.contains("  "):
		k = k.replace("  ", " ")
	var placeholders := ["", "?", "joueur blanc", "joueur noir", "joueur 1", "joueur 2",
			"blancs", "noirs", "player 1", "player 2", "player 3", "player 4"]
	return "" if k in placeholders else k

# --- UTILITAIRES JSON ATOMIQUES (réutilisés par LeCarnet multi-profils) ---

## Synchronise le système de fichiers virtuel vers le stockage persistant de l'hôte (IndexedDB sur Web / WASM).
static func sync_filesystem() -> void:
	if OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge"):
		JavaScriptBridge.force_fs_sync()

func sync_to_storage() -> void:
	sync_filesystem()

func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		sync_filesystem()

static func ensure_dir_for(path: String) -> void:
	var base := path.get_base_dir()
	if base != "" and not DirAccess.dir_exists_absolute(base):
		DirAccess.make_dir_recursive_absolute(base)

## Écriture atomique : `.tmp` puis renommage, avec rotation en `.bak` et repli en écriture
## directe si le FS ne supporte pas le rename écrasant (WASM/IDBFS).
## Prend en charge Dictionary et Array (Variant).
func save_json_atomic(path: String, data: Variant) -> void:
	ensure_dir_for(path)
	var text := JSON.stringify(data, "  ")
	var tmp := path + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_direct_write(path, text)
		sync_filesystem()
		return
	f.store_string(text)
	f.flush()
	f = null
	if FileAccess.file_exists(path + ".bak"):
		DirAccess.remove_absolute(path + ".bak")
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	var err: int = DirAccess.rename_absolute(tmp, path)
	if err != OK or not FileAccess.file_exists(path):
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
		_direct_write(path, text)
	sync_filesystem()

func _direct_write(path: String, text: String) -> void:
	ensure_dir_for(path)
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.flush()
		f = null

## Charge un JSON. Renvoie {} s'il est absent ; préserve un fichier corrompu
## (`<path>.corrupt_*`) au lieu de l'écraser silencieusement.
func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f = null
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return json.data
	_preserve_corrupt_file(path)
	return {}

func _preserve_corrupt_file(path: String) -> void:
	var stamp = Time.get_datetime_string_from_system(false, true) \
			.replace(":", "-").replace(" ", "_")
	var target := "%s.corrupt_%s" % [path, stamp]
	var err: int = DirAccess.rename_absolute(path, target)
	if err == OK and FileAccess.file_exists(target):
		return
	var src = FileAccess.open(path, FileAccess.READ)
	if src == null:
		return
	var content := src.get_as_text()
	src = null
	var dst = FileAccess.open(target, FileAccess.WRITE)
	if dst == null:
		return
	dst.store_string(content)
	dst.flush()
	dst = null
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(path)
