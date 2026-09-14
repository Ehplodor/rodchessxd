extends SceneTree

func _init() -> void:
	print("--- Test de chargement d'une partie archivée depuis la Bibliothèque ---")
	await create_timer(0.1).timeout

	var dm = root.get_node_or_null("DatabaseManager")
	assert(dm != null, "DatabaseManager doit être présent")

	# 1. Créer une partie archivée avec des analyses au format JSON (tableaux non typés comme lus du disque)
	var pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6"
	var gid = dm.record_pgn_game(pgn, "test_lib")

	# Simuler l'ajout d'une analyse moteur
	var raw_evals: Array = [
		{"ply": 0, "score_cp": 20, "quality": 1},
		{"ply": 1, "score_cp": 25, "quality": 1},
		{"ply": 2, "score_cp": 30, "quality": 1}
	]
	dm.add_engine_analysis(gid, {
		"engine_name": "Stockfish 18",
		"depth": 10,
		"white_accuracy": 95.0,
		"black_accuracy": 92.0,
		"white_estimated_elo": 2000,
		"black_estimated_elo": 1850,
		"evaluations": raw_evals
	})

	# 2. Instancier la scène Main
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.1).timeout

	# 3. Ouvrir LibraryModal et déclencher le chargement
	var lib_modal = load("res://src/ui/components/LibraryModal.gd").new()
	main_node.add_child(lib_modal)
	await create_timer(0.05).timeout

	print("Chargement de la partie via LibraryModal._load_game...")
	lib_modal._load_game(gid)
	await create_timer(0.1).timeout

	# 4. Vérifier que la courbe d'avantage a bien reçu les évaluations sans erreur de type
	var evs = main_node.advantage_graph.evaluations
	assert(evs.size() == 3, "Le graphe doit contenir les 3 évaluations chargées (trouvé: %d)" % evs.size())
	print("✓ Graphe d'avantage alimenté sans aucune erreur de type : %d points" % evs.size())

	# 5. Vérifier que les analyses enregistrées sont bien présentes
	var stored = main_node.advantage_graph.stored_analyses
	assert(stored.size() >= 1, "Les analyses enregistrées doivent être transmises au graphe")
	print("✓ Analyses moteur enregistrées synchronisées avec succès !")

	# 6. Vérifier la restauration de la qualité des coups dans GameController et MoveList2D
	var gc = root.get_node_or_null("GameController")
	assert(gc != null, "GameController doit être présent")
	assert(gc.game.move_history[0].quality == 1, "Le ply 0 doit avoir la qualité 1 (BEST)")
	assert(gc.game.move_history[1].quality == 1, "Le ply 1 doit avoir la qualité 1 (BEST)")
	assert(gc.game.move_history[2].quality == 1, "Le ply 2 doit avoir la qualité 1 (BEST)")
	print("✓ Qualités des coups restaurées sur GameController.game.move_history !")

	assert(main_node.move_list != null, "MoveList2D doit être présent")
	assert(not main_node.move_list._analysis_report.is_empty(), "MoveList2D doit posséder le rapport d'analyse")
	assert(main_node.move_list.move_buttons.size() >= 3, "Les boutons de coups doivent être construits")
	var btn0_text = main_node.move_list.move_buttons[0].text
	var badge = ChessMove.quality_to_symbol(ChessMove.Quality.BEST)
	assert(badge in btn0_text, "Le bouton du coup 1 doit afficher le badge de qualité (texte: %s)" % btn0_text)
	print("✓ Badge de qualité (%s) affiché dans MoveList2D : %s !" % [badge, btn0_text])

	# Nettoyage
	dm.delete_game(gid)
	print("\n>>> TEST CHARGEMENT BIBLIOTHÈQUE & RESTAURATION QUALITÉS RÉUSSI À 100% ! <<<")
	quit(0)
