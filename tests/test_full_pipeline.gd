extends SceneTree
## test_full_pipeline.gd - Test d'intégration de bout en bout de RodChessXD

const ChessPiece = preload("res://src/core/ChessPiece.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")
const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")
const ChessOCR = preload("res://src/vision/ChessOCR.gd")

func _init() -> void:
	print("==================================================")
	print("🚀 LANCEMENT DU TEST D'INTÉGRATION COMPLET RODCHESSXD")
	print("==================================================")
	
	await create_timer(0.2).timeout
	
	# 1. TEST CORE CHESS & COUPS COMPLEXES
	print("\n[1/4] Test du moteur de règles & roque...")
	var game = ChessGame.new()
	# Partie avec roque : 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O
	assert(game.make_move(_find_move(game, "e2e4")))
	assert(game.make_move(_find_move(game, "e7e5")))
	assert(game.make_move(_find_move(game, "g1f3")))
	assert(game.make_move(_find_move(game, "b8c6")))
	assert(game.make_move(_find_move(game, "f1c4")))
	assert(game.make_move(_find_move(game, "f8c5")))
	
	var castle_move = _find_move(game, "e1g1")
	assert(castle_move != null)
	assert(castle_move.is_castling == true)
	game.make_move(castle_move)
	print("Petit roque Blancs exécuté avec succès : SAN =", castle_move.san)
	assert(castle_move.san == "O-O")
	print("PGN en cours :", game.export_pgn())
	
	# 2. TEST ANALYSEUR DE PARTIE & MÉTRIQUES ELO
	print("\n[2/4] Test de l'analyseur de partie (GameAnalyzer)...")
	var analyzer = GameAnalyzer.new()
	var report = analyzer.start_game_analysis(game, 10)
	
	print("Rapport d'analyse généré :")
	print(" - Précision Blancs : %.1f%%" % report["white_accuracy"])
	print(" - Précision Noirs : %.1f%%" % report["black_accuracy"])
	print(" - ELO estimé Blancs : %d" % report["white_estimated_elo"])
	print(" - ELO estimé Noirs : %d" % report["black_estimated_elo"])
	print(" - Nombre de coups évalués : %d" % report["evaluations"].size())
	
	assert(report["evaluations"].size() == 7)
	assert(report["white_accuracy"] > 50.0)
	assert(report["white_estimated_elo"] >= 1000)

	# 3. TEST MODULE DE VISION & CHESS OCR
	print("\n[3/4] Test du module de vision & reconnaissance FEN...")
	var test_img = Image.create(400, 400, false, Image.FORMAT_RGB8)
	# Dessine un échiquier 8x8 synthétique
	var sq_size = 50
	for r in range(8):
		for f in range(8):
			var is_light = ((r + f) % 2 == 0)
			var col = Color(0.85, 0.85, 0.85) if is_light else Color(0.25, 0.25, 0.25)
			for py in range(r * sq_size, (r + 1) * sq_size):
				for px in range(f * sq_size, (f + 1) * sq_size):
					test_img.set_pixel(px, py, col)
	
	var detected_rect = ChessOCR.detect_board_rect(test_img)
	print("Rectangle d'échiquier détecté :", detected_rect)
	assert(detected_rect.size.x == 400 and detected_rect.size.y == 400)
	
	var recognized_fen = ChessOCR.recognize_board_fen(test_img, detected_rect, true)
	print("FEN reconnu sur échiquier vide :", recognized_fen)
	assert(recognized_fen.begins_with("8/8/8/8/8/8/8/8"))

	# 4. TEST DU CONSTRUCTEUR DE PROMPT COACH IA
	print("\n[4/4] Test du générateur de prompt pour le Coach IA...")
	var coach_script = load("res://src/ai/AICoach.gd")
	var coach_instance = coach_script.new()
	var test_prompt = coach_instance.build_chess_prompt(
		game.get_fen(),
		"O-O",
		45,
		"g8f6",
		["g8f6", "d2d3", "d7d6"],
		"Pourquoi roquer ici ?"
	)
	print("Extrait du prompt généré pour le LLM/SLM :")
	print(test_prompt.substr(0, 320) + "...")
	assert("Stockfish" in test_prompt)
	assert("O-O" in test_prompt)
	assert("Pourquoi roquer ici ?" in test_prompt)

	print("\n==================================================")
	print("🎉 TOUS LES TESTS D'INTÉGRATION ONT RÉUSSI AVEC SUCCÈS !")
	print("==================================================")
	quit(0)

func _find_move(game: ChessGame, uci: String) -> ChessMove:
	for m in game.get_legal_moves():
		if m.uci == uci:
			return m
	return null
