class_name ChessComService
extends Node
## ChessComService.gd - Service d'interrogation de l'API publique Chess.com pour récupérer les parties d'un joueur

signal games_fetched(games: Array[Dictionary])
signal fetch_error(error_message: String, diagnostic: Dictionary)

const RESULT_NAMES: Dictionary = {
	HTTPRequest.RESULT_SUCCESS: "RESULT_SUCCESS",
	HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "RESULT_CHUNKED_BODY_SIZE_MISMATCH",
	HTTPRequest.RESULT_CANT_CONNECT: "RESULT_CANT_CONNECT",
	HTTPRequest.RESULT_CANT_RESOLVE: "RESULT_CANT_RESOLVE",
	HTTPRequest.RESULT_CONNECTION_ERROR: "RESULT_CONNECTION_ERROR",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "RESULT_TLS_HANDSHAKE_ERROR",
	HTTPRequest.RESULT_NO_RESPONSE: "RESULT_NO_RESPONSE",
	HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "RESULT_BODY_SIZE_LIMIT_EXCEEDED",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "RESULT_BODY_DECOMPRESS_FAILED",
	HTTPRequest.RESULT_REQUEST_FAILED: "RESULT_REQUEST_FAILED",
	HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "RESULT_DOWNLOAD_FILE_CANT_OPEN",
	HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "RESULT_DOWNLOAD_FILE_WRITE_ERROR",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "RESULT_REDIRECT_LIMIT_REACHED",
	HTTPRequest.RESULT_TIMEOUT: "RESULT_TIMEOUT"
}

var http_client: HTTPRequest
var current_username: String = ""
var target_max_games: int = 50
var _current_request_url: String = ""

func _ready() -> void:
	_ensure_http_client()

func _ensure_http_client() -> void:
	if not is_instance_valid(http_client):
		http_client = HTTPRequest.new()
		add_child(http_client)
		http_client.request_completed.connect(_on_request_completed)

## Algorithme de diagnostic structuré d'erreur réseau pour Chess.com
static func diagnose_request_error(result: int, response_code: int, url: String, username: String = "", is_android_override: Variant = null) -> Dictionary:
	var on_android: bool = bool(is_android_override) if is_android_override != null else OS.has_feature("android")
	var result_name = RESULT_NAMES.get(result, "RESULT_UNKNOWN (%d)" % result)
	
	var title := ""
	var summary := ""
	var probable_cause := ""
	var recommendations: Array[String] = []
	
	# Branche 1 : Échec au niveau socket / transport (HTTP 0 ou CANT_CONNECT / CONNECTION_ERROR)
	if response_code == 0 or result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR]:
		if result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			title = "Échec de sécurité SSL/TLS (Certificat rejeté)"
			summary = "Erreur de négociation TLS sécurisée avec api.chess.com."
			probable_cause = "La connexion chiffrée HTTPS avec Chess.com n'a pas pu être validée.\n\nCauses algorithmiques les plus probables :\n1. Magasin de certificats racine obsolète : Sur les versions antérieures d'Android (ex: Android 8 ou 9 sans mises à jour Google Play récentes), l'autorité de certification moderne de Chess.com (Google Trust Services GTS Root R1) peut ne pas figurer dans le trousseau système.\n2. Horloge ou date système décalée : Un décalage de la date/heure rend le certificat SSL invalide.\n3. Réseau Wi-Fi avec portail captif bloquant le flux chiffré."
			recommendations.append("Vérifiez que la date et l'heure de votre appareil sont réglées en mode automatique.")
			recommendations.append("Essayez de basculer de connexion (passer du Wi-Fi à la 4G/5G ou inversement).")
			recommendations.append("Ouvrez un navigateur pour vérifier si votre réseau Wi-Fi nécessite une connexion via portail.")
		elif result == HTTPRequest.RESULT_CANT_RESOLVE:
			title = "Résolution DNS impossible (Serveur introuvable)"
			summary = "Impossible de résoudre le nom de domaine api.chess.com."
			probable_cause = "Le nom de domaine 'api.chess.com' n'a pas pu être converti en adresse IP par votre connexion.\n\nCauses probables :\n1. Connexion réseau absente ou instable.\n2. Serveur DNS de votre box Wi-Fi ou opérateur mobile défaillant ou filtrant le domaine."
			recommendations.append("Vérifiez que votre connexion Internet est active en ouvrant une page web.")
			recommendations.append("Désactivez tout VPN, adblocker ou proxy actif sur le téléphone.")
			recommendations.append("Redémarrez le Wi-Fi ou basculez en données mobiles.")
		elif result == HTTPRequest.RESULT_TIMEOUT:
			title = "Délai de connexion dépassé (Timeout)"
			summary = "Le serveur Chess.com n'a pas répondu à temps."
			probable_cause = "La requête a expiré sans réponse de Chess.com. Cela indique une latence réseau extrême, une connexion très instable ou un ralentissement temporaire des serveurs de Chess.com."
			recommendations.append("Vérifiez la qualité et la stabilité de votre réseau Internet.")
			recommendations.append("Réessayez dans quelques secondes.")
		else:
			# RESULT_CANT_CONNECT ou autre code avec HTTP 0
			if on_android:
				title = "Connexion refusée par le système Android (Code HTTP 0)"
				summary = "Le système a refusé l'ouverture de socket réseau vers Chess.com."
				probable_cause = "Aucun échange réseau n'a pu débuter. Le système Android a bloqué la création de la socket avant même d'émettre le moindre octet.\n\nCauses algorithmiques les plus probables :\n1. Permission réseau Android manquante : L'application installée ne possède pas 'android.permission.INTERNET' dans son manifeste, ou a été mise à jour sans désinstallation propre de la version précédente.\n2. Gestionnaire d'économie d'énergie / Pare-feu constructeur (fréquent sur Huawei EMUI, Xiaomi MIUI, etc.) : Les autorisations de données mobiles ou Wi-Fi en arrière-plan sont parfois bloquées pour les applications installées hors Play Store.\n3. Appareil en mode Avion ou hors couverture réseau."
				recommendations.append("Vérifiez vos paramètres Android : Paramètres > Applications > RodChessXD > Consommation des données > Vérifier que 'Wi-Fi' et 'Données mobiles' sont bien autorisés.")
				recommendations.append("Désinstallez complètement l'application RodChessXD du téléphone avant d'installer la nouvelle version de l'APK.")
				recommendations.append("Vérifiez que la connexion Internet fonctionne dans votre navigateur mobile.")
			else:
				title = "Connexion impossible (Code HTTP 0)"
				summary = "Impossible de joindre le serveur Chess.com."
				probable_cause = "La connexion socket n'a pas pu aboutir. Votre pare-feu local, antivirus ou proxy bloque peut-être les connexions sortantes de l'application, ou Chess.com est inaccessible."
				recommendations.append("Vérifiez votre connexion Internet.")
				recommendations.append("Vérifiez si un pare-feu ou un VPN bloque les requêtes de l'application.")
	elif response_code == 404:
		title = "Joueur Chess.com introuvable (Code HTTP 404)"
		summary = "Le pseudo '%s' n'existe pas sur Chess.com." % username
		probable_cause = "L'API officielle de Chess.com indique qu'aucun compte ne correspond au pseudo '%s'. Le compte est peut-être mal orthographié, a changé de pseudo, ou a été fermé/banni." % username
		recommendations.append("Vérifiez l'orthographe exacte du pseudo (évitez les espaces ou caractères spéciaux).")
		recommendations.append("Vérifiez que le profil existe bien dans votre navigateur sur chess.com/member/%s." % username)
	elif response_code == 403:
		title = "Accès refusé par Chess.com (Code HTTP 403)"
		summary = "La requête a été rejetée par la protection de Chess.com."
		probable_cause = "Le serveur ou la protection Cloudflare de Chess.com a rejeté la requête. Cela se produit si l'adresse IP est temporairement sous surveillance anti-bot ou si le réseau est suspecté de requêtes automatisées."
		recommendations.append("Désactivez tout VPN ou proxy actif.")
		recommendations.append("Patientez quelques minutes avant de renouveler la recherche.")
	elif response_code == 429:
		title = "Limite de requêtes atteinte (Code HTTP 429)"
		summary = "Trop de requêtes envoyées vers l'API Chess.com."
		probable_cause = "Chess.com impose un quota de requêtes par minute (Rate Limiting). Le quota pour votre adresse IP a été atteint."
		recommendations.append("Patientez 1 à 2 minutes avant de relancer l'import.")
	elif response_code >= 500:
		title = "Serveur Chess.com indisponible (Code HTTP %d)" % response_code
		summary = "Dysfonctionnement temporaire des serveurs de Chess.com."
		probable_cause = "Les serveurs de Chess.com rencontrent un incident technique ou une surcharge momentanée (erreur %d)." % response_code
		recommendations.append("Réessayez dans quelques minutes.")
		recommendations.append("Consultez l'état des serveurs sur chess.com.")
	else:
		title = "Erreur inattendue de Chess.com (Code HTTP %d)" % response_code
		summary = "Code HTTP %d inattendu retourné par l'API Chess.com." % response_code
		probable_cause = "Le serveur a retourné un statut inhabituel (%d)." % response_code
		recommendations.append("Vérifiez l'état de votre connexion et réessayez.")

	var now_str = Time.get_datetime_string_from_system(false, true)
	var os_desc = "%s (%s)" % [OS.get_name(), Engine.get_architecture_name()]
	
	var report := "=== RAPPORT DE DIAGNOSTIC RÉSEAU RODCHESSXD ===\n"
	report += "Horodatage : %s\n" % now_str
	report += "Système : %s\n" % os_desc
	report += "Plateforme mobile : %s\n" % ("Oui (Android)" if on_android else "Non")
	report += "Cible : %s\n" % url
	report += "Pseudo interrogé : %s\n" % (username if username != "" else "N/A")
	report += "Code HTTP reçu : %d\n" % response_code
	report += "Résultat moteur Godot : %s (%d)\n" % [result_name, result]
	report += "\n[CAUSE PROBABLE]\n%s\n" % probable_cause
	report += "\n[PISTES DE RÉSOLUTION CONSEILLÉES]\n"
	for rec in recommendations:
		report += "• %s\n" % rec
	report += "==============================================="

	return {
		"summary": summary,
		"title": title,
		"result_code": result,
		"result_name": result_name,
		"response_code": response_code,
		"url": url,
		"username": username,
		"os_name": OS.get_name(),
		"is_android": on_android,
		"probable_cause": probable_cause,
		"recommendations": recommendations,
		"formatted_report": report
	}

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
		var diag = {
			"summary": "Pseudo vide.",
			"title": "Pseudo manquant",
			"result_code": HTTPRequest.RESULT_REQUEST_FAILED,
			"result_name": "RESULT_REQUEST_FAILED",
			"response_code": 0,
			"url": "",
			"username": "",
			"os_name": OS.get_name(),
			"is_android": OS.has_feature("android"),
			"probable_cause": "Aucun pseudo Chess.com n'a été saisi dans le champ de recherche.",
			"recommendations": ["Veuillez saisir un pseudo de joueur Chess.com valide (ex: hikaru, magnuscarlsen)."],
			"formatted_report": "Erreur : Veuillez saisir un pseudo Chess.com valide."
		}
		fetch_error.emit("Veuillez saisir un pseudo Chess.com valide.", diag)
		return

	# Étape 1 : Récupérer la liste des archives mensuelles du joueur
	var archives_url = "https://api.chess.com/pub/player/%s/games/archives" % current_username
	_current_request_url = archives_url
	var headers = ["User-Agent: RodChessXD-ChessAnalysisApp/1.0"]
	
	var err = http_client.request(archives_url, headers)
	if err != OK:
		var diag = diagnose_request_error(HTTPRequest.RESULT_CANT_CONNECT, 0, archives_url, current_username)
		fetch_error.emit(diag["summary"], diag)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 404:
		var diag = diagnose_request_error(result, response_code, _current_request_url, current_username)
		fetch_error.emit(diag["summary"], diag)
		return
	elif result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var diag = diagnose_request_error(result, response_code, _current_request_url, current_username)
		fetch_error.emit(diag["summary"], diag)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json:
		var diag = diagnose_request_error(result, response_code, _current_request_url, current_username)
		diag["title"] = "Réponse invalide reçue de Chess.com"
		diag["summary"] = "Données JSON corrompues ou incomplètes reçues de Chess.com."
		diag["probable_cause"] = "Le serveur a répondu, mais le contenu n'a pas pu être décodé en JSON valide."
		fetch_error.emit(diag["summary"], diag)
		return

	# Cas 1 : Réponse de la liste des archives
	if json.has("archives"):
		var archives = json["archives"]
		if archives.is_empty():
			var diag = diagnose_request_error(result, response_code, _current_request_url, current_username)
			diag["title"] = "Aucune partie trouvée"
			diag["summary"] = "Aucune partie répertoriée pour '%s'." % current_username
			diag["probable_cause"] = "Le joueur existe sur Chess.com mais ne possède aucune archive mensuelle de parties enregistrée."
			diag["recommendations"] = ["Vérifiez que ce joueur a joué des parties publiques sur Chess.com."]
			fetch_error.emit(diag["summary"], diag)
			return

		# Prendre l'archive la plus récente (dernier mois joué)
		var latest_archive_url = archives[archives.size() - 1]
		_current_request_url = latest_archive_url
		var headers = ["User-Agent: RodChessXD-ChessAnalysisApp/1.0"]
		var err = http_client.request(latest_archive_url, headers)
		if err != OK:
			var diag = diagnose_request_error(HTTPRequest.RESULT_CANT_CONNECT, 0, latest_archive_url, current_username)
			fetch_error.emit("Erreur lors de la récupération des parties du dernier mois.", diag)
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
