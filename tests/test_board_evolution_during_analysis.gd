extends SceneTree

func _init() -> void:
	print("\n[TEST] --- Validation complète de l'évolution visuelle du plateau pendant l'analyse ---")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.5).timeout

	var gc = root.get_node_or_null("GameController")
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6")
	assert(gc.game.move_history.size() == 4, "La partie doit comporter 4 demi-coups")
	print("Partie chargée : 4 demi-coups (1. e4 e5 2. Nf3 Nc6).")
	
	var analyzer: GameAnalyzer = main_node.get("analyzer")
	assert(analyzer != null, "Analyzer doit exister sur main_node")

	var positions_ready: Array[int] = []
	var plies_analyzed: Array[int] = []
	var board_plies_during_ready: Array[int] = []

	analyzer.analysis_position_ready.connect(func(ply):
		positions_ready.append(ply)
		# Vérifier que Main.gd a bien mis à jour le contrôleur de jeu et l'échiquier
		board_plies_during_ready.append(gc.current_ply_index)
		print("  -> analysis_position_ready ply %d (échiquier positionné sur ply %d)" % [ply, gc.current_ply_index])
	)

	analyzer.ply_analyzed.connect(func(ply, rec, _stats):
		plies_analyzed.append(ply)
		print("  -> ply_analyzed ply %d (score=%d, best=%s)" % [ply, rec.get("score_cp", 0), rec.get("best_move", "")])
	)

	# --- Test 1 : Analyse séquentielle Desktop (start_game_analysis) ---
	print("\n--- Test 1 : Chemin Desktop / Android (start_game_analysis) ---")
	positions_ready.clear()
	plies_analyzed.clear()
	board_plies_during_ready.clear()
	
	analyzer.is_analyzing = true
	var desktop_options = {
		"mode": "depth",
		"wait_for_display": true
	}
	
	# Lancer dans un vrai Thread pour reproduire exactement l'architecture Desktop
	var th = Thread.new()
	th.start(func():
		return analyzer.start_game_analysis(gc.game, 6, desktop_options)
	)
	
	# Attendre que le thread termine en traitant les frames du SceneTree
	while th.is_alive():
		await process_frame
	var _rep_desktop = th.wait_to_finish()

	# Laisser le temps aux signaux call_deferred de se propager
	for _frame in range(5):
		await process_frame

	print("\nValidation Test 1 (Desktop) :")
	print("  positions_ready : %s" % str(positions_ready))
	print("  plies_analyzed  : %s" % str(plies_analyzed))
	print("  board_plies_during_ready : %s" % str(board_plies_during_ready))
	
	assert(positions_ready == [0, 1, 2, 3], "Tous les 4 demi-coups doivent avoir émis analysis_position_ready")
	assert(plies_analyzed == [0, 1, 2, 3], "Tous les 4 demi-coups doivent avoir émis ply_analyzed")
	assert(board_plies_during_ready == [0, 1, 2, 3], "L'échiquier doit avancer rigoureusement à chaque coup")
	print("  ✅ Test 1 Desktop : Évolution visuelle synchronisée 100% validée.")

	# --- Test 2 : Analyse séquentielle Web / WASM (start_game_analysis_async) ---
	print("\n--- Test 2 : Chemin Web / Wasm (start_game_analysis_async) ---")
	positions_ready.clear()
	plies_analyzed.clear()
	board_plies_during_ready.clear()

	analyzer.is_analyzing = true
	var web_options = {
		"mode": "depth",
		"wait_for_display": true
	}

	var _rep_web = await analyzer.start_game_analysis_async(gc.game, 6, web_options)

	for _frame in range(5):
		await process_frame

	print("\nValidation Test 2 (Web) :")
	print("  positions_ready : %s" % str(positions_ready))
	print("  plies_analyzed  : %s" % str(plies_analyzed))
	print("  board_plies_during_ready : %s" % str(board_plies_during_ready))

	assert(positions_ready == [0, 1, 2, 3], "Tous les 4 demi-coups Web doivent émettre analysis_position_ready")
	assert(plies_analyzed == [0, 1, 2, 3], "Tous les 4 demi-coups Web doivent émettre ply_analyzed")
	assert(board_plies_during_ready == [0, 1, 2, 3], "L'échiquier Web doit avancer à chaque coup")
	print("  ✅ Test 2 Web : Évolution visuelle synchronisée 100% validée.")

	main_node.queue_free()
	print("\n🎉 TOUTES LES VALIDATIONS D'ÉVOLUTION DU PLATEAU SONT RÉUSSIES !")
	quit(0)
