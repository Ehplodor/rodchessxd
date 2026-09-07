extends SceneTree

func _init() -> void:
	print("[TEST] Validation des modes d'analyse, des intervalles de confiance et de l'animation en direct...")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.3).timeout

	var sm = root.get_node_or_null("SettingsManager")
	var gc = root.get_node_or_null("GameController")
	assert(sm != null, "SettingsManager doit être accessible dans l'arborescence")
	assert(gc != null, "GameController doit être accessible dans l'arborescence")

	# --- 1. Test des calculs statistiques (p-value, étoiles, test bilatéral de Welch) ---
	print("  -> Test 1: Calculs statistiques & biostatistiques...")
	var p_null = GameAnalyzer._calculate_normal_p_value(0.0)
	assert(abs(p_null - 1.0) < 0.01, "z=0 doit donner p ≈ 1.0")

	var p_05 = GameAnalyzer._calculate_normal_p_value(1.96)
	assert(abs(p_05 - 0.05) < 0.01, "z=1.96 doit donner p ≈ 0.05")

	var p_01 = GameAnalyzer._calculate_normal_p_value(2.576)
	assert(abs(p_01 - 0.01) < 0.005, "z=2.58 doit donner p ≈ 0.01")

	var p_001 = GameAnalyzer._calculate_normal_p_value(3.291)
	assert(abs(p_001 - 0.001) < 0.001, "z=3.29 doit donner p ≈ 0.001")

	assert(GameAnalyzer._p_value_to_stars(0.0005) == "***", "p=0.0005 doit afficher ***")
	assert(GameAnalyzer._p_value_to_stars(0.005) == "**", "p=0.005 doit afficher **")
	assert(GameAnalyzer._p_value_to_stars(0.03) == "*", "p=0.03 doit afficher *")
	assert(GameAnalyzer._p_value_to_stars(0.15) == "ns", "p=0.15 doit afficher ns")

	var analyzer = GameAnalyzer.new()
	var w_stat = {"elo": 1900, "ci_margin": 60, "se": 30.6}
	var b_stat = {"elo": 1650, "ci_margin": 70, "se": 35.7}
	var comp = analyzer._perform_elo_comparison_test(w_stat, b_stat)

	assert(comp["diff_elo"] == 250, "Différence ELO attendue: 250")
	assert(comp["is_significant"] == true, "250 points d'écart doivent être hautement significatifs")
	assert(comp["stars"] == "***", "Pour 250 ELO d'écart, on attend ***")
	print("    ✅ P-values, seuils alphas et étoiles scientifiques validés (%s, p=%.5f)." % [comp["stars"], comp["p_value"]])

	# --- 2. Test des paramètres d'analyse (SettingsManager) ---
	print("  -> Test 2: Paramètres des modes d'analyse...")
	sm.set_setting("analysis_mode", "dynamic")
	sm.set_setting("analysis_time_per_move", 0.35)
	sm.set_setting("analysis_dynamic_base", 0.15)
	sm.set_setting("analysis_dynamic_max", 0.85)

	assert(sm.get_setting("analysis_mode") == "dynamic", "Mode d'analyse doit être dynamic")
	assert(abs(sm.get_setting("analysis_time_per_move") - 0.35) < 0.001, "Temps par coup doit être 0.35s")
	assert(abs(sm.get_setting("analysis_dynamic_base") - 0.15) < 0.001, "Temps base doit être 0.15s")
	assert(abs(sm.get_setting("analysis_dynamic_max") - 0.85) < 0.001, "Temps max doit être 0.85s")
	print("    ✅ Sauvegarde et lecture des paramètres des modes d'analyse validées.")

	# --- 3. Test de la construction live de la courbe d'avantage (AdvantageGraph2D) ---
	print("  -> Test 3: Tracé live du graphe d'avantage et intervalles de confiance...")
	var graph = main_node.advantage_graph
	assert(graph != null, "AdvantageGraph doit exister sur main_node")
	graph.prepare_live_analysis(6)

	assert(graph.evaluations.size() == 6, "Le graphe préparé doit contenir 6 plies neutres")
	assert(graph.evaluations[0]["is_placeholder"] == true, "Les points initiaux doivent être des placeholders")
	assert(graph.evaluations[0]["ci_margin"] == 140.0, "L'incertitude initiale doit être large (±140 cp)")

	# Mise à jour live du premier coup
	var rec0 = {
		"ply": 0,
		"move_number": 1,
		"is_white": true,
		"san": "e4",
		"uci": "e2e4",
		"score_cp": 35,
		"ci_margin": 25.0,
		"best_move": "e7e5",
		"quality": ChessMove.Quality.EXCELLENT
	}
	graph.update_live_ply(0, rec0)
	assert(graph.evaluations[0]["is_placeholder"] == false, "Le ply 0 n'est plus un placeholder")
	assert(graph.evaluations[0]["score_cp"] == 35, "Score cp mis à jour à +35")
	assert(graph.evaluations[0]["ci_margin"] == 25.0, "Marge IC mise à jour à ±25 cp")
	assert(graph.active_ply == 0, "Le curseur actif doit être sur le ply 0")
	print("    ✅ Construction dynamique de la courbe et rétrécissement du halo d'incertitude validés.")

	# --- 4. Test de l'animation en direct sur Main (Échiquier, flèches, libellés joueurs) ---
	print("  -> Test 4: Intégration scène Main, synchronisation échiquier et flèches...")
	# Charger une mini partie de 2 coups : 1. e4 e5
	gc.load_pgn("1. e4 e5")
	assert(gc.game.move_history.size() == 2, "La partie doit comporter 2 demi-coups")

	# Simuler l'analyse live du premier coup (ply 0 : 1. e4)
	main_node.analyzer.is_analyzing = true
	var ply0_rec = {
		"ply": 0,
		"move_number": 1,
		"is_white": true,
		"san": "e4",
		"uci": "e2e4",
		"score_cp": 28,
		"ci_margin": 22.0,
		"best_move": "e7e5",
		"quality": ChessMove.Quality.EXCELLENT,
		"depth": 14
	}
	main_node._on_ply_analyzed(0, ply0_rec, {})

	assert(gc.current_ply_index == 0, "GameController doit être positionné sur le ply 0")
	assert(main_node.chess_board.last_move_from == ChessMove.coord_to_square("e2"), "Flèche dernier coup départ e2")
	assert(main_node.chess_board.last_move_to == ChessMove.coord_to_square("e4"), "Flèche dernier coup arrivée e4")
	assert(main_node.chess_board.best_move_arrow_from == ChessMove.coord_to_square("e7"), "Flèche Stockfish départ e7")
	assert(main_node.chess_board.best_move_arrow_to == ChessMove.coord_to_square("e5"), "Flèche Stockfish arrivée e5")
	assert(main_node.stats_label.text.contains("1. e4"), "StatsLabel doit afficher le coup en direct")
	assert(main_node.stats_label.text.contains("±0.2"), "StatsLabel doit afficher l'intervalle de confiance en direct")
	print("    ✅ Flèche rouge pointillée du coup joué et flèche cyan Stockfish synchronisées en direct.")

	# Simuler l'analyse terminée avec rapport statistique
	var dummy_report = {
		"white_accuracy": 92.4,
		"black_accuracy": 81.2,
		"white_estimated_elo": 1820,
		"black_estimated_elo": 1690,
		"white_elo_ci": 55,
		"black_elo_ci": 62,
		"elo_comparison": {
			"diff_elo": 130,
			"t_stat": 2.21,
			"p_value": 0.027,
			"stars": "*",
			"is_significant": true,
			"description": "Différence significative (p < 0.05 *)"
		},
		"white_acpl": 18.5,
		"black_acpl": 36.2,
		"white_stats": {},
		"black_stats": {},
		"evaluations": [ply0_rec]
	}
	main_node._on_analysis_finished(dummy_report)

	assert(main_node.stats_grid.visible == true, "La grille 2x2 stats_grid doit être visible après analyse")
	assert(main_node.label_white_stats.text.contains("92.4%") and main_node.label_white_stats.text.contains("1820 ±55 ELO"), "L1C1 Blancs doit contenir la précision 92.4% et l'ELO 1820 ±55")
	assert(main_node.label_black_stats.text.contains("81.2%") and main_node.label_black_stats.text.contains("1690 ±62 ELO"), "L2C1 Noirs doit contenir la précision 81.2% et l'ELO 1690 ±62")
	assert(main_node.label_delta.text == "Δ +130 ELO", "Cellule droite doit afficher le delta ELO centré")
	assert(main_node.label_pvalue.text.contains("p=0.027") and main_node.label_pvalue.text.contains("*"), "Cellule droite doit afficher la p-value et les étoiles")
	print("    ✅ Grille statistique 2x2 validée (Blancs: %s | Noirs: %s | Delta: %s %s)" % [
		main_node.label_white_stats.text,
		main_node.label_black_stats.text,
		main_node.label_delta.text,
		main_node.label_pvalue.text
	])

	# --- 5. Test du bouton STOP durant l'analyse et du bouton Live ---
	print("  -> Test 5: Validation du bouton STOP et du bouton ⚡ Live...")
	assert(main_node.btn_analyze_game.text == "🔍 Analyser", "Le bouton doit être sur 'Analyser' hors analyse")
	assert(main_node.btn_toggle_live.text == "⚡ Live", "Le bouton Live doit être actif par défaut")
	
	main_node._on_btn_toggle_live_pressed()
	assert(main_node.live_eval_enabled == false, "Live doit être désactivé après un clic")
	assert(main_node.btn_toggle_live.text == "⚡ Off", "Le libellé doit être '⚡ Off'")
	
	main_node._on_btn_toggle_live_pressed()
	assert(main_node.live_eval_enabled == true, "Live doit être réactivé après un deuxième clic")
	assert(main_node.btn_toggle_live.text == "⚡ Live", "Le libellé doit revenir à '⚡ Live'")

	# Démarrage de l'analyse : libellé doit passer à ⏹ STOP
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O")
	sm.set_setting("analysis_time_per_move", 1.0)
	main_node._on_btn_analyze_game_pressed()
	assert(main_node.btn_analyze_game.text == "⏹ STOP", "Le bouton doit afficher '⏹ STOP' pendant l'analyse")
	assert(main_node.btn_toggle_live.disabled == true, "Le bouton Live doit être désactivé pendant l'analyse")

	# Clic sur STOP : interruption sans perte des données acquises
	main_node._on_btn_analyze_game_pressed()
	assert(main_node.btn_analyze_game.text == "🔍 Analyser", "Le bouton doit revenir à 'Analyser'")
	assert(main_node.btn_toggle_live.disabled == false, "Le bouton Live doit être réactivé après l'arrêt")
	print("    ✅ Transitions d'état du bouton STOP et du toggle ⚡ Live validées.")

	if main_node.analysis_thread and main_node.analysis_thread.is_started():
		main_node.analysis_thread.wait_to_finish()
	main_node.queue_free()
	print("\n🎉 TOUS LES TESTS STATISTIQUES, LIVE SF19 & D'ANIMATION EN DIRECT SONT VALIDÉS AVEC SUCCÈS !")
	quit(0)

