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

var games_index: Array[Dictionary] = []

func _ready() -> void:
	_ensure_directories()
	_load_index()

func _ensure_directories() -> void:
	var da = DirAccess.open("user://")
	if da:
		if not da.dir_exists("library"):
			da.make_dir("library")
		if not da.dir_exists("library/games"):
			da.make_dir("library/games")

func _load_index() -> void:
	games_index.clear()
	if FileAccess.file_exists(INDEX_FILE):
		var f = FileAccess.open(INDEX_FILE, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			var json = JSON.parse_string(txt)
			if json is Array:
				for item in json:
					if item is Dictionary:
						games_index.append(item)
	_sort_index_by_date()

func _save_index() -> void:
	_sort_index_by_date()
	var f = FileAccess.open(INDEX_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(games_index, "  "))

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

	# Écriture du fichier individuel
	var path = "%s/%s.json" % [GAMES_DIR, game_id]
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(game_data, "  "))

	# Mise à jour de l'index
	_update_index_entry(game_data)
	_save_index()
	game_saved.emit(game_id)
	return game_id

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

## Supprime une partie et ses analyses associées
func delete_game(game_id: String) -> bool:
	var path = "%s/%s.json" % [GAMES_DIR, game_id]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	
	for i in range(games_index.size() - 1, -1, -1):
		if games_index[i].get("id", "") == game_id:
			games_index.remove_at(i)
			break
	
	_save_index()
	game_deleted.emit(game_id)
	return true

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

## Crée ou met à jour une partie importée via PGN
func record_pgn_game(pgn_text: String, source: String = "pgn_import") -> String:
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

	var game_id = record_pgn_game(pgn, "chess_com")
	if game_id != "":
		var data = get_game(game_id)
		data["title"] = "⚪ %s (%d) vs ⚫ %s (%d)" % [w_user, w_rat, b_user, b_rat]
		data["white_name"] = w_user
		data["black_name"] = b_user
		data["white_elo"] = w_rat
		data["black_elo"] = b_rat
		data["event"] = "Chess.com (%s)" % cadence.capitalize()
		data["result_label"] = res
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
		"source": game_data.get("source", "pgn_import"),
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
