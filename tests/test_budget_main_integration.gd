extends SceneTree

## test_budget_main_integration.gd — Mode budget via Main, avec synchronisation d'affichage.

func _init() -> void:
	print("\n[TEST] Intégration mode budget via Main (wait_for_display=true)")
	await create_timer(0.2).timeout
	var sm = root.get_node_or_null("SettingsManager")
	sm.set_setting("analysis_mode", "budget")
	var main_node = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main_node)
	await create_timer(0.2).timeout
	var gc = root.get_node_or_null("GameController")
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Bxc6 dxc6")
	var board = main_node.chess_board
	var analyzer = main_node.analyzer
	var nav: Array = []
	board.navigation_forward_completed.connect(func(ply): nav.append(ply))
	var positions: Array = []
	analyzer.analysis_position_ready.connect(func(ply): positions.append(ply))

	main_node._on_btn_analyze_game_pressed()
	var report: Dictionary = await analyzer.analysis_finished
	await create_timer(0.2).timeout

	print("  Analyse terminée : analysing=%s, positions=%s, nav=%s" % [
		str(analyzer.is_analyzing), str(positions), str(nav)])
	assert(not analyzer.is_analyzing, "l'analyse doit être terminée")
	assert(report.get("evaluations", []).size() == 8, "8 évaluations attendues")
	assert(positions == [0, 1, 2, 3, 4, 5, 6, 7], "toutes les positions affichées")
	assert(nav == [0, 1, 2, 3, 4, 5, 6, 7], "toutes les animations complétées")
	assert(main_node.advantage_graph.evaluations.size() == 8, "graphe synchronisé")
	print("  ✅ Mode budget via Main OK (animation + rapport + graphe)\n")
	main_node.queue_free()
	quit(0)
