extends SceneTree

func _init() -> void:
	print("--- Test DatabaseManager (Persistance locale & Multi-Analyses) ---")
	await create_timer(0.05).timeout

	var dm = root.get_node_or_null("DatabaseManager")
	assert(dm != null, "DatabaseManager doit être chargé en autoload")

	# 1. Tester l'enregistrement d'une partie PGN
	var pgn = """[Event "Championnat du Monde"]
[Site "Dubaï"]
[Date "2021.11.26"]
[White "Carlsen, Magnus"]
[Black "Nepomniachtchi, Ian"]
[Result "1-0"]
[WhiteElo "2855"]
[BlackElo "2782"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6 1-0"""

	var game_id = dm.record_pgn_game(pgn, "pgn_test")
	assert(game_id != "", "Le game_id généré ne doit pas être vide")
	print("✓ Partie PGN enregistrée avec ID :", game_id)

	# 2. Vérifier la lecture de la partie
	var loaded = dm.get_game(game_id)
	assert(loaded.size() > 0, "La partie doit être récupérée depuis le disque")
	assert(loaded["white_name"] == "Carlsen, Magnus", "Le nom des blancs doit être Carlsen")
	assert(loaded["white_elo"] == 2855, "L'élo des blancs doit être 2855")
	assert(loaded["moves"].size() == 10, "Il doit y avoir 10 demi-coups enregistrés")
	print("✓ Données de la partie vérifiées avec succès.")

	# 3. Ajouter une première analyse moteur (Stockfish depth 10)
	var analysis_1 = {
		"engine_name": "Stockfish 18",
		"depth": 10,
		"white_accuracy": 94.5,
		"black_accuracy": 89.2,
		"white_estimated_elo": 2200,
		"black_estimated_elo": 1900,
		"white_acpl": 16.2,
		"black_acpl": 28.4,
		"evaluations": [{"ply": 0, "score_cp": 20}, {"ply": 1, "score_cp": 25}]
	}
	dm.add_engine_analysis(game_id, analysis_1)

	# 4. Ajouter une DEUXIÈME analyse moteur (ex: Stockfish depth 16)
	var analysis_2 = {
		"engine_name": "Stockfish 18 Deep",
		"depth": 16,
		"white_accuracy": 96.1,
		"black_accuracy": 90.0,
		"white_estimated_elo": 2400,
		"black_estimated_elo": 2050,
		"white_acpl": 12.0,
		"black_acpl": 22.0,
		"evaluations": [{"ply": 0, "score_cp": 22}, {"ply": 1, "score_cp": 28}]
	}
	dm.add_engine_analysis(game_id, analysis_2)

	# Vérifier que les DEUX analyses moteur sont bien conservées sans écrasement
	var reloaded = dm.get_game(game_id)
	var engine_analyses = reloaded.get("engine_analyses", [])
	assert(engine_analyses.size() == 2, "La partie doit contenir EXACTEMENT 2 analyses moteur sans écrasement (trouvé: %d)" % engine_analyses.size())
	assert(engine_analyses[0]["depth"] == 10, "La 1ère analyse doit avoir depth 10")
	assert(engine_analyses[1]["depth"] == 16, "La 2ème analyse doit avoir depth 16")
	print("✓ Multi-analyses moteur validées : 2 analyses conservées avec succès !")

	# 5. Ajouter une analyse de coach LLM
	var coach_entry_1 = {
		"ply_index": 2,
		"move_san": "Nf3",
		"perspective": "white",
		"model_id": "z-ai/glm-5.3-flash:free",
		"provider": "openrouter",
		"user_question": "Pourquoi Nf3 ?",
		"response_text": "Nf3 développe une pièce mineure vers le centre et attaque le pion e5.",
		"elapsed_sec": 2.1,
		"cost_label": "Gratuit"
	}
	dm.add_coach_analysis(game_id, coach_entry_1)

	var coach_entry_2 = {
		"ply_index": 2,
		"move_san": "Nf3",
		"perspective": "white",
		"model_id": "google/gemini-2.0-flash",
		"provider": "gemini",
		"user_question": "Une autre vision ?",
		"response_text": "Excellent coup préparant le petit roque et contrôlant d4.",
		"elapsed_sec": 0.4,
		"cost_label": "Gratuit"
	}
	dm.add_coach_analysis(game_id, coach_entry_2)

	reloaded = dm.get_game(game_id)
	var coach_analyses = reloaded.get("coach_analyses", [])
	assert(coach_analyses.size() == 2, "La partie doit contenir 2 notes de coachs différents (trouvé: %d)" % coach_analyses.size())
	assert(coach_analyses[0]["model_id"] == "z-ai/glm-5.3-flash:free", "1er coach vérifié")
	assert(coach_analyses[1]["model_id"] == "google/gemini-2.0-flash", "2e coach vérifié")
	print("✓ Multi-coachs validés : 2 réponses archivées pour la position !")

	# 6. Tester la recherche et le listing
	var list_all = dm.list_games()
	assert(list_all.size() >= 1, "La liste doit contenir au moins 1 partie")
	var item = list_all[0]
	assert(item["engine_analyses_count"] == 2, "L'index doit refléter 2 analyses moteur")
	assert(item["coach_analyses_count"] == 2, "L'index doit refléter 2 analyses coach")

	var search_carlsen = dm.list_games("Carlsen")
	assert(search_carlsen.size() >= 1, "La recherche 'Carlsen' doit trouver la partie")

	var search_empty = dm.list_games("NomInexistant12345")
	assert(search_empty.size() == 0, "Une recherche inexistante doit retourner 0 résultat")
	print("✓ Recherche et filtres de la bibliothèque validés !")

	# 7. Tester la suppression
	var del_ok = dm.delete_game(game_id)
	assert(del_ok, "La suppression doit réussir")
	assert(dm.get_game(game_id).is_empty(), "La partie supprimée ne doit plus exister")
	print("✓ Suppression de partie validée !")

	print("\n>>> TEST DATABASE MANAGER RÉUSSI À 100% ! <<<")
	quit(0)
