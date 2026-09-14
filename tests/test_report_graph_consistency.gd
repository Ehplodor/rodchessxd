extends SceneTree

## test_report_graph_consistency.gd
## Vérifie que le graphe d'avantage affiche EXACTEMENT les mêmes coups remarquables que
## le rapport d'analyse (gaffes = BLUNDER + MISS, erreurs, imprécisions, brillants, coups uniques),
## à l'issue d'une analyse complète de partie.

func _init() -> void:
	print("\n[TEST] --- Cohérence rapport d'analyse <-> graphe d'avantage ---")

	# --- Partie 1 : couverture des marqueurs du graphe (unitaire, déterministe) ---
	var remarkable := {
		"BRILLIANT": ChessMove.Quality.BRILLIANT,
		"GREAT": ChessMove.Quality.GREAT,
		"INACCURACY": ChessMove.Quality.INACCURACY,
		"MISTAKE": ChessMove.Quality.MISTAKE,
		"BLUNDER": ChessMove.Quality.BLUNDER,
		"MISS": ChessMove.Quality.MISS
	}
	for name in remarkable:
		var marker = AdvantageGraph2D.notable_marker_for(remarkable[name])
		assert(not marker.is_empty(), "Le graphe doit afficher un marqueur pour %s (rapport le compte)" % name)
		print("  ✅ Marqueur présent pour %s (rayon %.1f)" % [name, float(marker["radius"])])
	var normal := {
		"NONE": ChessMove.Quality.NONE,
		"BEST": ChessMove.Quality.BEST,
		"EXCELLENT": ChessMove.Quality.EXCELLENT,
		"GOOD": ChessMove.Quality.GOOD
	}
	for name in normal:
		assert(AdvantageGraph2D.notable_marker_for(normal[name]).is_empty(),
				"%s ne doit pas produire de marqueur (coup non remarquable)" % name)
	print("  ✅ Aucun marqueur parasite pour les qualités normales (NONE/BEST/EXCELLENT/GOOD).")

	# --- Partie 2 : analyse complète et comparaison rapport <-> graphe ---
	await create_timer(0.1).timeout
	var main_node = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main_node)
	await create_timer(0.2).timeout

	var gc = root.get_node_or_null("GameController")
	# Partie réelle RLFRRR - jayd6788 : grosse erreur noire « 32...e4 » (occasion de gain
	# gâchée, win% ~87) qui doit apparaître dans le rapport ET sur le graphe.
	var movetext := "1. d4 e6 2. e4 Nf6 3. Nc3 Nc6 4. Bd3 Nxd4 5. a4 Bc5 6. Be3 e5 7. Nf3 Nxf3+ 8. gxf3 Bb4 9. Bd2 d6 10. Bb5+ Kf8 11. Rg1 Bh3 12. Bf1 Bxf1 13. Rxf1 Qd7 14. Ne2 Nh5 15. Rg1 Qh3 16. Rg3 Qxh2 17. Bxb4 Nxg3 18. fxg3 Qh1+ 19. Kd2 Qxf3 20. Ra3 Qxe4 21. Re3 Qxb4+ 22. c3 Qxb2+ 23. Qc2 Qb6 24. Rf3 f6 25. g4 Rd8 26. g5 d5 27. gxf6 gxf6 28. Qf5 Qb2+ 29. Ke3 d4+ 30. Kd3 dxc3+ 31. Ke3 Qd2+ 32. Kf2 e4 33. Qxf6+ Kg8 34. Qf7#"
	assert(gc.load_pgn(movetext), "Le PGN doit être chargé.")

	print("  Lancement de l'analyse complète (%d demi-coups)..." % gc.game.move_history.size())
	main_node._on_btn_analyze_game_pressed()
	var report: Dictionary = await main_node.analyzer.analysis_finished
	await create_timer(0.2).timeout

	var evals: Array = main_node.advantage_graph.evaluations
	assert(evals.size() == gc.game.move_history.size(),
			"Le graphe doit contenir un point par demi-coup (graphe=%d, partie=%d)" % [
				evals.size(), gc.game.move_history.size()])

	# Comptage des qualités réellement présentes dans le graphe.
	var graph_counts := {
		"brilliant": 0, "great": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0
	}
	for ev in evals:
		var q: int = int(ev.get("quality", ChessMove.Quality.NONE))
		# Toute qualité remarquable DOIT être marquable sur le graphe (régression gaffe manquée).
		if q != ChessMove.Quality.NONE:
			assert(not AdvantageGraph2D.notable_marker_for(q).is_empty() or q in [
				ChessMove.Quality.BEST, ChessMove.Quality.EXCELLENT, ChessMove.Quality.GOOD
			], "Qualité remarquable %d sans marqueur de graphe" % q)
		match q:
			ChessMove.Quality.BRILLIANT: graph_counts["brilliant"] += 1
			ChessMove.Quality.GREAT: graph_counts["great"] += 1
			ChessMove.Quality.INACCURACY: graph_counts["inaccuracy"] += 1
			ChessMove.Quality.MISTAKE: graph_counts["mistake"] += 1
			ChessMove.Quality.BLUNDER: graph_counts["blunder"] += 1
			ChessMove.Quality.MISS: graph_counts["miss"] += 1

	# Le rapport agrège les stats des deux camps : elles doivent correspondre au graphe.
	var report_counts := {
		"brilliant": 0, "great": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0
	}
	for key in ["white_stats", "black_stats"]:
		var s: Dictionary = report.get(key, {})
		for cat in report_counts.keys():
			report_counts[cat] += int(s.get(cat, 0))

	for cat in report_counts.keys():
		assert(graph_counts[cat] == report_counts[cat],
				"Incohérence rapport/graphe pour %s : rapport=%d, graphe=%d" % [
					cat, report_counts[cat], graph_counts[cat]])
	print("  ✅ Distribution identique rapport/graphe : %s" % str(graph_counts))

	# Cas précis : 32...e4 (ply 63) doit être un coup à problème ET marquable sur le graphe.
	var e4_ev: Dictionary = evals[63]
	var e4_q: int = int(e4_ev.get("quality", ChessMove.Quality.NONE))
	assert(MoveQualityService.group(e4_q) == 3,
			"32...e4 doit être une gaffe/occasion manquée (groupe 3), qualité=%d" % e4_q)
	assert(float(e4_ev.get("winpct_loss", 0.0)) >= 30.0,
			"32...e4 doit présenter une chute de win%% importante (%.1f)" % float(e4_ev.get("winpct_loss", 0.0)))
	assert(not AdvantageGraph2D.notable_marker_for(e4_q).is_empty(),
			"32...e4 doit afficher un marqueur sur le graphe")
	var swing_plies: Array = []
	for s in report.get("biggest_swings", []):
		swing_plies.append(int(s.get("ply", -1)))
	assert(swing_plies.has(63), "32...e4 doit figurer dans les moments clés du rapport")
	print("  ✅ 32...e4 (ply 63) : gaffe/occasion manquée (%.1f%% win) marquée graphe + rapport" % float(e4_ev.get("winpct_loss", 0.0)))

	# Gaffes agrégées (rapport) = BLUNDER + MISS (graphe).
	var gaffes_report: int = report_counts["blunder"] + report_counts["miss"]
	var gaffes_graph: int = graph_counts["blunder"] + graph_counts["miss"]
	print("  ✅ Gaffes rapport=%d == gaffes graphe=%d (dont misses désormais affichées)" % [
		gaffes_report, gaffes_graph])
	assert(gaffes_report == gaffes_graph, "Les gaffes du rapport et du graphe doivent coïncider")
	assert(gaffes_report >= 1, "La partie doit produire au moins une gaffe dans le rapport et le graphe")

	print("\n🎉 COHÉRENCE RAPPORT / GRAPHE VALIDÉE À 100% !\n")
	main_node.queue_free()
	quit(0)
