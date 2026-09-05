extends SceneTree

func _init() -> void:
	print("--- Test d'intégration de l'affichage du Graphe et de l'Analyse ---")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	await create_timer(0.2).timeout
	
	# Charger une partie PGN de test
	var pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6"
	var gc = root.get_node("GameController")
	var success = gc.load_pgn(pgn)
	assert(success, "Le PGN doit être chargé")
	print("Partie PGN chargée : %d demi-coups." % gc.game.move_history.size())

	# Basculer initialement sur l'onglet Coach (1) pour vérifier le basculement automatique vers le Graphe (0)
	main_node.bottom_tabs.current_tab = 1

	# Lancer l'analyse
	print("Lancement de l'analyse globale de partie...")
	main_node._on_btn_analyze_game_pressed()
	
	# Attendre le signal de fin d'analyse
	await main_node.analyzer.analysis_finished
	await create_timer(0.3).timeout

	# 1. Vérifier que l'onglet actif a bien basculé sur le Graphe
	assert(main_node.bottom_tabs.current_tab == 0, "L'onglet actif doit être l'onglet Graphe (0)")
	print("✓ Onglet Graphe activé automatiquement :", main_node.bottom_tabs.get_tab_title(0))

	# 2. Vérifier que la courbe d'avantage a reçu les points
	var evals = main_node.advantage_graph.evaluations
	assert(evals.size() == 10, "Le graphe doit contenir 10 points d'évaluation (trouvé: %d)" % evals.size())
	print("✓ Points de la courbe d'avantage : %d points enregistrés" % evals.size())

	# 3. Vérifier le texte et la cohérence de l'estimation ELO
	var stats = main_node.stats_label.text
	print("✓ Rapport affiché :", stats)
	assert("Est." in stats and "ELO" in stats, "Les stats doivent contenir l'estimation ELO")
	assert(main_node.analyzer.white_estimated_elo < 2000, "Une partie courte de 5 coups d'ouverture ne doit PAS donner 2800 ELO !")
	print("✓ ELO estimé Blancs réaliste : %d ELO (amorti pour partie courte)" % main_node.analyzer.white_estimated_elo)

	# 4. Tester l'agrandissement de la vue du graphe
	main_node.advantage_graph._toggle_expand()
	assert(main_node.advantage_graph.is_expanded == true, "Le graphe doit être agrandi")
	assert(main_node.advantage_graph.custom_minimum_size.y == 180.0, "La hauteur agrandie doit être 180px")
	print("✓ Mode d'agrandissement haute précision (180px) testé avec succès !")

	main_node.advantage_graph._toggle_expand()
	assert(main_node.advantage_graph.is_expanded == false, "Le graphe doit revenir à 90px")
	print("✓ Mode compact (90px) restauré avec succès !")

	print("\n>>> TEST INTÉGRATION GRAPHE & ELO VALIDÉ À 100% ! <<<")
	quit(0)
