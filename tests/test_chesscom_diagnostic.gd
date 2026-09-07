extends SceneTree
## test_chesscom_diagnostic.gd - Tests unitaires de l'algorithme de diagnostic d'erreur réseau

const ChessComService = preload("res://src/network/ChessComService.gd")

func _init() -> void:
	print("--- Running ChessComService Diagnostic Algorithm Tests ---")
	
	# Test 1: Android HTTP 0 (CANT_CONNECT - Permission / Pare-feu EMUI)
	var d1 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_CANT_CONNECT, 0, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 1 (Android CANT_CONNECT): ", d1["title"])
	assert(d1["is_android"] == true)
	assert(d1["response_code"] == 0)
	assert(d1["result_name"] == "RESULT_CANT_CONNECT")
	assert(d1["title"].contains("Android"))
	assert(d1["probable_cause"].contains("android.permission.INTERNET"))
	assert(d1["probable_cause"].contains("Huawei"))
	assert(d1["recommendations"].size() >= 2)
	assert(d1["formatted_report"].contains("RAPPORT DE DIAGNOSTIC RÉSEAU"))

	# Test 2: Desktop HTTP 0 (CANT_CONNECT - Pare-feu local)
	var d2 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_CANT_CONNECT, 0, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", false)
	print("Test 2 (Desktop CANT_CONNECT): ", d2["title"])
	assert(d2["is_android"] == false)
	assert(d2["probable_cause"].contains("pare-feu local"))

	# Test 3: TLS Handshake error (Certificat SSL obsolète)
	var d3 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 3 (TLS Handshake): ", d3["title"])
	assert(d3["title"].contains("SSL/TLS"))
	assert(d3["probable_cause"].contains("racine obsolète"))
	assert(d3["probable_cause"].contains("Google Trust Services"))

	# Test 4: DNS Resolution failure
	var d4 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_CANT_RESOLVE, 0, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 4 (DNS failure): ", d4["title"])
	assert(d4["title"].contains("DNS"))
	assert(d4["probable_cause"].contains("converti en adresse IP"))

	# Test 5: Timeout
	var d5 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_TIMEOUT, 0, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 5 (Timeout): ", d5["title"])
	assert(d5["title"].contains("Timeout"))

	# Test 6: HTTP 404 (Joueur introuvable)
	var d6 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_SUCCESS, 404, "https://api.chess.com/pub/player/joueurinconnu999/games/archives", "joueurinconnu999", true)
	print("Test 6 (HTTP 404): ", d6["title"])
	assert(d6["title"].contains("404"))
	assert(d6["probable_cause"].contains("joueurinconnu999"))

	# Test 7: HTTP 403 (Cloudflare / Blocage anti-bot)
	var d7 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_SUCCESS, 403, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 7 (HTTP 403): ", d7["title"])
	assert(d7["title"].contains("403"))
	assert(d7["probable_cause"].contains("Cloudflare"))

	# Test 8: HTTP 429 (Rate limiting)
	var d8 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_SUCCESS, 429, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 8 (HTTP 429): ", d8["title"])
	assert(d8["title"].contains("429"))
	assert(d8["probable_cause"].contains("quota"))

	# Test 9: HTTP 503 (Serveur en panne)
	var d9 = ChessComService.diagnose_request_error(HTTPRequest.RESULT_SUCCESS, 503, "https://api.chess.com/pub/player/hikaru/games/archives", "hikaru", true)
	print("Test 9 (HTTP 503): ", d9["title"])
	assert(d9["title"].contains("503"))
	assert(d9["probable_cause"].contains("incident technique"))

	print("\nALL 9 DIAGNOSTIC ALGORITHM TESTS PASSED 100% SUCCESSFULLY!")
	quit(0)
