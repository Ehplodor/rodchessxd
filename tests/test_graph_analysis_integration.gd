extends SceneTree

## test_graph_analysis_integration.gd
## Valide l'intégration Graphe + Analyse sur l'architecture actuelle (overlays) :
## après analyse complète, la courbe d'avantage est alimentée et l'ELO estimé reste réaliste.

func _init() -> void:
	print("--- Test d'intégration de l'affichage du Graphe et de l'Analyse ---")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)

	await create_timer(0.3).timeout

	# Charger une partie PGN de test
	var pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6"
	var gc = root.get_node("GameController")
	var success = gc.load_pgn(pgn)
	assert(success, "Le PGN doit être chargé")
	print("Partie PGN chargée : %d demi-coups." % gc.game.move_history.size())

	# Lancer l'analyse globale de partie
	print("Lancement de l'analyse globale de partie...")
	main_node._on_btn_analyze_game_pressed()

	# Attente active de la fin d'analyse (thread dédié sur Desktop)
	var waited := 0
	while main_node.analyzer.is_analyzing and waited < 100:
		await create_timer(0.1).timeout
		waited += 1
	assert(not main_node.analyzer.is_analyzing, "L'analyse doit s'être terminée avec succès")
	await create_timer(0.3).timeout

	# 1. Vérifier que la courbe d'avantage a reçu les points
	var evals = main_node.advantage_graph.evaluations
	assert(evals.size() == 10, "Le graphe doit contenir 10 points d'évaluation (trouvé: %d)" % evals.size())
	print("✓ Points de la courbe d'avantage : %d points enregistrés" % evals.size())

	# 2. Vérifier la cohérence de l'estimation ELO
	assert(main_node.analyzer.white_estimated_elo < 2000, "Une partie courte de 5 coups d'ouverture ne doit PAS donner 2800 ELO !")
	print("✓ ELO estimé Blancs réaliste : %d ELO (amorti pour partie courte)" % main_node.analyzer.white_estimated_elo)

	# 3. Vérifier que l'analyse a bien produit les métriques attendues
	assert(main_node.analyzer.move_evaluations.size() == 10, "10 coups doivent avoir été évalués")
	print("✓ Métriques d'analyse cohérentes : précision ⚪ %.1f %% / ⚫ %.1f %%" % [
			main_node.analyzer.white_accuracy, main_node.analyzer.black_accuracy])

	print("\n>>> TEST INTÉGRATION GRAPHE & ELO VALIDÉ À 100% ! <<<")
	quit(0)
