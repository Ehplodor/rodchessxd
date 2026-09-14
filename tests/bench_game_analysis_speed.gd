extends SceneTree

func _init() -> void:
	print("==================================================")
	print("--- BENCHMARK ANALYSE DE PARTIE (40 DEMI-COUPS) ---")
	print("==================================================")
	
	await create_timer(0.2).timeout
	
	var manager = root.get_node_or_null("EngineManager")
	if not manager:
		var em_script = load("res://src/engine/EngineManager.gd")
		manager = em_script.new()
		root.add_child(manager)
		manager.start_engine()
	
	if not manager.is_engine_available():
		await manager.engine_ready
	
	var game = ChessGame.new()
	# Partie espagnole complète (40 demi-coups / 20 coups)
	var moves_uci = [
		"e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6",
		"e1g1", "f8e7", "f1e1", "b7b5", "a4b3", "d7d6", "c2c3", "e8g8",
		"h2h3", "c6b8", "d2d4", "b8d7", "b1d2", "c8b7", "b3c2", "f8e8",
		"d2f1", "e7f8", "f1g3", "g7g6", "c1g5", "h7h6", "g5d2", "f8g7",
		"d1c1", "g8h7", "a2a4", "c7c5", "d4d5", "c5c4", "b2b4", "c4b3"
	]
	
	for uci in moves_uci:
		var legal = game.get_legal_moves()
		var found: ChessMove = null
		for m in legal:
			if m.uci == uci:
				found = m
				break
		if found:
			game.make_move(found)
		else:
			print("Coup non trouvé : ", uci)
			break
	
	print("Partie préparée : %d demi-coups." % game.move_history.size())
	
	var analyzer_script = load("res://src/engine/GameAnalyzer.gd")
	var analyzer = analyzer_script.new()
	analyzer.engine_manager = manager
	
	var t0 = Time.get_ticks_msec()
	print("Lancement de l'analyse en mode 'dynamic' (base 0.08s, max 0.25s)...")
	var report = analyzer.start_game_analysis(game, 14, {
		"mode": "dynamic",
		"dynamic_base": 0.08,
		"dynamic_max": 0.25,
		"wait_for_display": false
	})
	var total_ms = Time.get_ticks_msec() - t0
	var plies = game.move_history.size()
	var ms_per_ply = float(total_ms) / float(plies)
	
	print("\n--- RÉSULTATS ANALYSE RAPIDE ---")
	print("  - Total demi-coups : %d" % plies)
	print("  - Temps total      : %d ms (%.2f s)" % [total_ms, float(total_ms) / 1000.0])
	print("  - Temps par coup   : %.1f ms" % ms_per_ply)
	print("  - ACPL Blancs      : %.1f | ACPL Noirs : %.1f" % [report.get("white_acpl", 0), report.get("black_acpl", 0)])
	print("  - Précision Blancs : %.1f%% | Noirs : %.1f%%" % [report.get("white_accuracy", 0), report.get("black_accuracy", 0)])
	
	if ms_per_ply <= 120.0:
		print("  ✅ SUCCÈS TOTAL : Analyse ultra-rapide (%.1f ms/coup <= 120 ms) !" % ms_per_ply)
	else:
		print("  ⚠️ Temps moyen par coup : %.1f ms" % ms_per_ply)
	
	print("==================================================")
	quit(0)
