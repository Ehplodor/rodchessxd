extends SceneTree

func _init() -> void:
	print("[TEST] --- Validation de l'Analyse d'une Partie se terminant par Échec et Mat ---")
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

	# Construction du Coup du Berger (Scholar's Mate) : 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
	var game = ChessGame.new()
	game.load_fen(ChessGame.INITIAL_FEN)

	var pgn = "1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#"
	var loaded = game.load_pgn(pgn)
	assert(loaded, "Le PGN du Coup du Berger doit se charger avec succès")
	assert(game.move_history.size() == 7, "Il doit y avoir exactement 7 demi-coups (plies)")

	var last_move: ChessMove = game.move_history[6]
	print("Dernier coup de la partie : %s (mat=%s)" % [last_move.san, last_move.is_checkmate])
	assert(last_move.san.ends_with("#") or last_move.is_checkmate, "Le 7e coup doit être le mat")

	var analyzer = GameAnalyzer.new()
	analyzer.engine_manager = eng

	var analyzed_plies = []
	analyzer.ply_analyzed.connect(func(ply, rec, _stats):
		analyzed_plies.append(rec)
		print("  -> Coup %d (%s) analysé : score=%d, best=%s, qualité=%s" % [
			ply, rec.get("san", ""), rec.get("score_cp", 0), rec.get("best_move", ""), rec.get("quality", -1)
		])
	)

	print("\n--- Test 1 : Analyse asynchrone (Web / non-bloquante) du Coup du Berger ---")
	var report_async = await analyzer.start_game_analysis_async(game, 10, {"mode": "depth"})

	assert(not report_async.has("error"), "L'analyse ne doit pas échouer : %s" % report_async.get("error", ""))
	assert(report_async["evaluations"].size() == 7, "L'analyse doit contenir EXACTEMENT 7 coups (y compris le mat)")
	assert(analyzed_plies.size() == 7, "Le signal ply_analyzed doit avoir été émis 7 fois")

	var mate_record_async: Dictionary = report_async["evaluations"][6]
	assert(mate_record_async["score_cp"] == 10000, "Le score du mat blanc doit être +10000")
	print("  -> Coup du mat validé : score_cp=%d, qualité=%d" % [mate_record_async["score_cp"], mate_record_async["quality"]])

	print("\n--- Test 2 : Analyse synchrone (Desktop) du Coup du Berger ---")
	analyzed_plies.clear()
	var report_sync = analyzer.start_game_analysis(game, 10, {"mode": "depth"})
	assert(not report_sync.has("error"), "L'analyse synchrone ne doit pas échouer")
	assert(report_sync["evaluations"].size() == 7, "L'analyse synchrone doit aussi évaluer les 7 coups")
	var mate_record_sync: Dictionary = report_sync["evaluations"][6]
	assert(mate_record_sync["score_cp"] == 10000, "Le score du mat blanc doit être +10000")
	print("  -> Analyse synchrone validée : 7/7 coups évalués sans blocage")

	print("\n🎉 VALIDATION DE L'ANALYSE AVEC ÉCHEC ET MAT RÉUSSIE AVEC SUCCÈS (100% OK) !")
	quit(0)
