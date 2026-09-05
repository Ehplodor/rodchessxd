class_name ChessComService
extends Node
## ChessComService.gd - Service d'interrogation de l'API publique Chess.com pour récupérer les parties d'un joueur

signal games_fetched(games: Array[Dictionary])
signal fetch_error(error_message: String)

var http_client: HTTPRequest
var current_username: String = ""
var target_max_games: int = 50

func _ready() -> void:
	_ensure_http_client()

func _ensure_http_client() -> void:
	if not is_instance_valid(http_client):
		http_client = HTTPRequest.new()
		add_child(http_client)
		http_client.request_completed.connect(_on_request_completed)

## Récupère les parties les plus récentes d'un joueur Chess.com
func fetch_player_games(username: String, max_games: int = 50) -> void:
	if not is_inside_tree():
		await tree_entered
	if not is_node_ready():
		await ready

	_ensure_http_client()

	current_username = username.strip_edges().to_lower()
	target_max_games = max_games

	if current_username == "":
		fetch_error.emit("Veuillez saisir un pseudo Chess.com valide.")
		return

	# Étape 1 : Récupérer la liste des archives mensuelles du joueur
	var archives_url = "https://api.chess.com/pub/player/%s/games/archives" % current_username
	var headers = ["User-Agent: RodChessXD-ChessAnalysisApp/1.0"]
	
	var err = http_client.request(archives_url, headers)
	if err != OK:
		fetch_error.emit("Impossible de contacter le serveur Chess.com.")

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 404:
		fetch_error.emit("Joueur Chess.com introuvable ('%s')." % current_username)
		return
	elif response_code != 200:
		fetch_error.emit("Erreur Chess.com (Code HTTP %d)." % response_code)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json:
		fetch_error.emit("Réponse invalide reçue de Chess.com.")
		return

	# Cas 1 : Réponse de la liste des archives
	if json.has("archives"):
		var archives = json["archives"]
		if archives.is_empty():
			fetch_error.emit("Aucune partie trouvée pour ce joueur.")
			return

		# Prendre l'archive la plus récente (dernier mois joué)
		var latest_archive_url = archives[archives.size() - 1]
		var headers = ["User-Agent: RodChessXD-ChessAnalysisApp/1.0"]
		var err = http_client.request(latest_archive_url, headers)
		if err != OK:
			fetch_error.emit("Erreur lors de la récupération des parties du dernier mois.")
		return

	# Cas 2 : Réponse des parties d'un mois spécifique
	if json.has("games"):
		var raw_games = json["games"]
		var parsed_games: Array[Dictionary] = []

		# Trier du plus récent au plus ancien
		for i in range(raw_games.size() - 1, -1, -1):
			var g = raw_games[i]
			var pgn = g.get("pgn", "")
			if pgn == "":
				continue

			var white_info = g.get("white", {})
			var black_info = g.get("black", {})
			
			var white_user = white_info.get("username", "Inconnu")
			var black_user = black_info.get("username", "Inconnu")
			var white_rating = white_info.get("rating", 0)
			var black_rating = black_info.get("rating", 0)
			var white_result = white_info.get("result", "")
			var black_result = black_info.get("result", "")

			var time_class = g.get("time_class", "inconnu")
			var time_control = g.get("time_control", "")
			var end_time = g.get("end_time", 0)
			
			var is_current_white = (white_user.to_lower() == current_username)
			var user_result = "win" if (is_current_white and white_result == "win") or (not is_current_white and black_result == "win") else "loss"
			if white_result in ["agreed", "repetition", "stalemate", "timevsinsufficient", "insufficient"] or black_result in ["agreed", "repetition", "stalemate", "timevsinsufficient", "insufficient"]:
				user_result = "draw"

			parsed_games.append({
				"url": g.get("url", ""),
				"pgn": pgn,
				"white_user": white_user,
				"black_user": black_user,
				"white_rating": white_rating,
				"black_rating": black_rating,
				"time_class": time_class,
				"time_control": time_control,
				"end_time": end_time,
				"user_result": user_result,
				"rules": g.get("rules", "chess")
			})

			if parsed_games.size() >= target_max_games:
				break

		games_fetched.emit(parsed_games)
