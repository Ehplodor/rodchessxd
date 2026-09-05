extends SceneTree

func _init() -> void:
	print("--- Test de la Perspective et des Prompts du Coach IA ---")
	await create_timer(0.05).timeout

	var coach = root.get_node("AICoach")
	assert(coach != null, "AICoach doit être chargé")

	var fen_after_1e4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	
	# Test 1 : Perspective BLANCS après 1. e4 (le trait est aux Noirs, mais le joueur veut le conseil Blancs !)
	var prompt_white = coach.build_prompt_data(
		fen_after_1e4,
		"e4",
		25,
		"e7e5",
		["e7e5", "g1f3", "b8c6"],
		"",
		{
			"perspective": "white",
			"ply_index": 0,
			"move_number": 1,
			"last_move_color": "white"
		}
	)

	var sys_w = prompt_white["system"]
	var usr_w = prompt_white["user"]

	assert("JOUEUR AVEC LES BLANCS" in sys_w, "L'instruction système doit cibler les Blancs")
	assert("DU POINT DE VUE DES BLANCS" in sys_w, "Le point de vue doit être explicitement Blancs")
	assert("Blancs (⚪)" in usr_w, "La fiche technique doit demander de conseiller les Blancs")
	assert("e4 (joué par les Blancs)" in usr_w, "Le dernier coup doit mentionner qu'il a été joué par les Blancs")
	assert("Trait actuel au jeu** : Noirs" in usr_w, "Le trait au jeu doit être clair")
	print("✓ Test 1 Réussi : Perspective Blancs parfaitement orientée (même avec trait aux Noirs) !")

	# Test 2 : Perspective NOIRS (le joueur joue les Noirs et veut savoir comment répondre à 1. e4)
	var prompt_black = coach.build_prompt_data(
		fen_after_1e4,
		"e4",
		25,
		"e7e5",
		["e7e5", "g1f3", "b8c6"],
		"",
		{
			"perspective": "black",
			"ply_index": 0,
			"move_number": 1,
			"last_move_color": "white"
		}
	)

	var sys_b = prompt_black["system"]
	var usr_b = prompt_black["user"]

	assert("JOUEUR AVEC LES NOIRS" in sys_b, "L'instruction système doit cibler les Noirs")
	assert("DU POINT DE VUE DES NOIRS" in sys_b, "Le point de vue doit être explicitement Noirs")
	assert("Noirs (⚫)" in usr_b, "La fiche technique doit demander de conseiller les Noirs")
	assert("comment les Noirs doivent réfuter les Blancs" in sys_b, "Doit guider la défense et la réplique des Noirs")
	print("✓ Test 2 Réussi : Perspective Noirs rigoureusement formulée pour conseiller le joueur Noir !")

	# Test 3 : Perspective NEUTRE (arbitre / commentateur impartial)
	var prompt_neutral = coach.build_prompt_data(
		fen_after_1e4,
		"e4",
		25,
		"e7e5",
		["e7e5"],
		"",
		{"perspective": "neutral"}
	)
	assert("analyste impartial et objectif" in prompt_neutral["system"], "Doit adopter un ton impartial")
	print("✓ Test 3 Réussi : Mode Arbitre / Neutre validé !")

	print("\n>>> TEST PERSPECTIVE & PROMPTS COACH IA RÉUSSI À 100% ! <<<")
	quit(0)
