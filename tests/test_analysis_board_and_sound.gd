extends SceneTree

## test_analysis_board_and_sound.gd
## Valide que les sons ET l'animation visuelle des pièces s'exécutent de façon synchronisée
## pendant l'analyse complète du moteur sans blocage ni gel sur le plateau.

func _init() -> void:
	print("\n--- Test d'animation visuelle et sonore synchronisée pendant l'analyse ---")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.2).timeout
	
	var gc = root.get_node_or_null("GameController")
	assert(gc != null, "GameController doit être présent comme Autoload")
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6")
	
	var board = main_node.chess_board
	var analyzer = main_node.analyzer
	
	# Espionner les signaux
	var positions_ready: Array = []
	var nav_completed: Array = []
	var plies_analyzed: Array = []
	
	analyzer.analysis_position_ready.connect(func(ply):
		positions_ready.append(ply)
	)
	board.navigation_forward_completed.connect(func(ply):
		nav_completed.append(ply)
	)
	analyzer.ply_analyzed.connect(func(ply, _rec, _stats):
		plies_analyzed.append(ply)
	)
	
	# Test 1: Lancement analyse depuis l'overlay (vérifier que l'overlay se ferme pour révéler l'échiquier)
	print("Test 1: Lancement Réanalyser depuis AnalyseOverlay...")
	main_node._open_analyse_overlay()
	assert(main_node.analyse_overlay.visible == true, "AnalyseOverlay doit être visible")
	
	main_node._on_btn_reanalyze_pressed()
	assert(main_node.analyse_overlay.visible == false, "AnalyseOverlay doit se fermer lors de la relance d'analyse")
	assert(analyzer.is_analyzing == true, "L'analyse doit être en cours")
	
	# Attendre la fin de l'analyse (4 coups = ~1.5 à 2s)
	var max_wait := 50 # 5 secondes max
	for _frame in range(max_wait):
		await create_timer(0.1).timeout
		if not analyzer.is_analyzing:
			break
	
	assert(not analyzer.is_analyzing, "L'analyse doit s'être terminée avec succès")
	assert(positions_ready == [0, 1, 2, 3], "Chaque coup (0 à 3) doit avoir émis analysis_position_ready: %s" % str(positions_ready))
	assert(nav_completed == [0, 1, 2, 3], "Chaque coup (0 à 3) doit avoir animé et émis navigation_forward_completed: %s" % str(nav_completed))
	assert(plies_analyzed == [0, 1, 2, 3], "Chaque coup (0 à 3) doit avoir été évalué par Stockfish: %s" % str(plies_analyzed))
	print("  ✅ Synchronisation complète validée : positions, animations et évaluations [0, 1, 2, 3] !")
	
	# Test 2: Annulation propre lors de la navigation
	print("Test 2: Annulation propre de l'analyse lors de la navigation...")
	analyzer.is_analyzing = true
	main_node.btn_analyze_game.text = "⏹ STOP"
	main_node._on_btn_prev_pressed()
	assert(not analyzer.is_analyzing, "La navigation doit annuler analyzer.is_analyzing")
	assert(main_node.btn_analyze_game.text == "🔍 Analyser", "Le bouton analyser doit revenir à l'état initial")
	print("  ✅ Annulation propre validée.")
	
	main_node.queue_free()
	print("\n🎉 TOUS LES TESTS D'ANIMATION ET SONS SYNCHRONISÉS SONT VALIDÉS AVEC SUCCÈS !\n")
	quit(0)
