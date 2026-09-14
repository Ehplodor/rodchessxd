extends SceneTree

## test_budget_async.gd — Valide le chemin asynchrone (Web) du mode à budget.

func _init() -> void:
	print("\n[TEST] Mode budget asynchrone (chemin Web)")
	await create_timer(0.2).timeout
	var main_node = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main_node)
	await create_timer(0.2).timeout
	var gc = root.get_node_or_null("GameController")
	gc.load_pgn("1. d4 e6 2. e4 Nf6 3. Nc3 Nc6 4. Bd3 Nxd4 5. a4 Bc5 6. Be3 e5 7. Nf3 Nxf3+ 8. gxf3 Bb4 9. Bd2 d6 10. Bb5+ Kf8 11. Rg1 Bh3 12. Bf1 Bxf1 13. Rxf1 Qd7 14. Ne2 Nh5 15. Rg1 Qh3 16. Rg3 Qxh2 17. Bxb4 Nxg3 18. fxg3 Qh1+ 19. Kd2 Qxf3 20. Ra3 Qxe4 21. Re3 Qxb4+ 22. c3 Qxb2+ 23. Qc2 Qb6 24. Rf3 f6 25. g4 Rd8 26. g5 d5 27. gxf6 gxf6 28. Qf5 Qb2+ 29. Ke3 d4+ 30. Kd3 dxc3+ 31. Ke3 Qd2+ 32. Kf2 e4 33. Qxf6+ Kg8 34. Qf7#")
	var analyzer = main_node.analyzer
	analyzer.engine_manager = root.get_node_or_null("EngineManager")
	var t0 = Time.get_ticks_msec()
	var rep: Dictionary = await analyzer.start_game_analysis_async(gc.game, 14, {
		"mode": "budget", "base_depth": 8, "deep_depth": 14,
		"max_deep": 6, "min_criticality": 12.0, "deep_movetime_ms": 250,
		"wait_for_display": false
	})
	var dt = Time.get_ticks_msec() - t0
	var evs: Array = rep.get("evaluations", [])
	print("  Analyse async terminée en %d ms, %d évaluations" % [dt, evs.size()])
	assert(evs.size() == gc.game.move_history.size(), "un point par demi-coup")
	assert(not rep.has("error"), "pas d'erreur")
	# La gaffe 32...e4 (ply 63) doit être détectée et remontée dans les moments clés.
	var q63 := int(evs[63].get("quality", 0))
	var swings: Array = rep.get("biggest_swings", [])
	var found := false
	for s in swings:
		if int(s.get("ply", -1)) == 63:
			found = true
	print("  32...e4 qualité=%s, win%%=%.1f (groupe %d) ; dans moments clés=%s" % [
		ChessMove.quality_to_symbol(q63), float(evs[63].get("winpct_loss", 0.0)),
		MoveQualityService.group(q63), str(found)])
	assert(MoveQualityService.group(q63) == 3, "32...e4 doit rester une gaffe/occasion manquée")
	assert(found, "32...e4 doit figurer dans biggest_swings")
	print("  ✅ Chemin async budget OK\n")
	main_node.queue_free()
	quit(0)
