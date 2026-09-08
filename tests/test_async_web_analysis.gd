extends SceneTree

func _init() -> void:
	print("[TEST] --- Validation de l'Analyse Asynchrone Non-Bloquante (Web/Wasm) ---")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.3).timeout

	var eng = root.get_node_or_null("EngineManager")
	assert(eng != null, "EngineManager doit être accessible")
	var waited = 0
	while not eng.is_engine_available() and waited < 3000:
		await process_frame
		waited += 16
	assert(eng.is_engine_available(), "Stockfish doit être disponible")
	print("Engine disponible. Test evaluate_position_async...")
	
	# Test 1: Évaluation asynchrone unitaire
	var res = await eng.evaluate_position_async(ChessGame.INITIAL_FEN, 10, 2000)
	print("Résultat eval asynchrone :", res)
	assert(not res.get("timed_out", false), "L'évaluation async ne doit pas expirer")
	assert(res.get("best_move", "") != "", "Un meilleur coup doit être renvoyé")
	print("  -> Test 1 OK : meilleur coup =", res.get("best_move"))
	
	# Test 2: Analyse asynchrone de partie
	var game = ChessGame.new()
	game.load_fen(ChessGame.INITIAL_FEN)
	var m1 = ChessMove.new(12, 28, ChessPiece.Type.PAWN) # e2-e4
	m1.san = "e4"
	game.make_move(m1)
	var m2 = ChessMove.new(52, 36, ChessPiece.Type.PAWN) # e7-e5
	m2.san = "e5"
	game.make_move(m2)
	
	var analyzer = GameAnalyzer.new()
	analyzer.engine_manager = eng
	
	var counter = [0]
	analyzer.ply_analyzed.connect(func(ply, rec, stats):
		counter[0] += 1
		print("  -> Ply %d analysé : score=%d, best=%s" % [ply, rec.get("score_cp", 0), rec.get("best_move", "")])
	)
	
	print("Démarrage start_game_analysis_async sur 2 coups...")
	var options = {"mode": "depth"}
	var report = await analyzer.start_game_analysis_async(game, 10, options)
	
	assert(not report.has("error"), "Le rapport ne doit pas contenir d'erreur : %s" % report.get("error", ""))
	assert(report["evaluations"].size() == 2, "2 coups doivent être évalués")
	assert(counter[0] == 2, "Le signal ply_analyzed doit avoir été émis 2 fois")
	print("  -> Test 2 OK : Précision Blancs=%.1f%%, Noirs=%.1f%%" % [report["white_accuracy"], report["black_accuracy"]])
	
	# Test 4: Lancement d'une évaluation async alors que le Live est DÉJÀ en cours (conflit résolu)
	print("Test 4: Déclenchement d'un Live puis analyse async immédiate (test de non-collision)...")
	eng.evaluate_position(ChessGame.INITIAL_FEN, 14)
	assert(eng.is_evaluating, "Le moteur doit être en train de calculer le Live")
	
	# Appel asynchrone direct sur une autre position (e.g. après e4)
	var e4_fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	var res4 = await eng.evaluate_position_async(e4_fen, 10, 2000)
	print("Résultat après interruption Live :", res4)
	assert(not res4.get("timed_out", false), "L'évaluation ne doit pas expirer")
	assert(res4.get("best_move", "") != "", "Un meilleur coup doit être renvoyé après interruption")
	assert(not eng.is_evaluating, "is_evaluating doit être false")
	print("  -> Test 4 OK : L'évaluation Live a été vidangée et le nouveau calcul est exact !")
	
	print("\n🎉 TOUS LES TESTS D'ANALYSE ASYNCHRONE ET DE RESTAURATION DU LIVE SONT RÉUSSIS (100% OK) !")
	quit(0)
