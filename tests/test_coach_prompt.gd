extends SceneTree
## test_coach_prompt.gd - Tests unitaires du générateur de prompts échiquéens anti-hallucination

const AICoachScript = preload("res://src/ai/AICoach.gd")
const SettingsManagerScript = preload("res://src/core/SettingsManager.gd")

func _init() -> void:
	print("--- Running AICoach Prompt Engineering Unit Tests ---")
	await create_timer(0.2).timeout

	var sm = SettingsManagerScript.new()
	sm.name = "SettingsManager"
	root.add_child(sm)

	var coach = AICoachScript.new()
	root.add_child(coach)

	# 1. Test Position Initiale (Ouverture, Matériel égal)
	var fen_initial = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	var prompt_data = coach.build_prompt_data(
		fen_initial,
		"e4",
		25,
		"e7e5",
		["e7e5", "g1f3", "b8c6"],
		"",
		{"quality": 1, "cp_loss": 0, "move_number": 1}
	)

	assert(prompt_data.has("system") and prompt_data.has("user") and prompt_data.has("full_text"))
	print("[1/4] Test structure de prompt réussie !")

	# Vérification des règles d'or anti-hallucination
	assert("ANTI-HALLUCINATION" in prompt_data.system)
	assert("VÉRITÉ TERRAIN STRICTE" in prompt_data.system)
	assert("Stockfish" in prompt_data.system)
	assert("Diagnostic" in prompt_data.system)
	assert("Analyse & Réfutation" in prompt_data.system)
	assert("Plan conseillé" in prompt_data.system)
	print("[2/4] Vérification des règles d'or et rubriques Markdown réussie !")

	# Vérification du contenu utilisateur
	assert("Stockfish 18" in prompt_data.user)
	assert("Ouverture" in prompt_data.user)
	assert("Égalité matérielle" in prompt_data.user)
	assert("Meilleur coup (★)" in prompt_data.user)
	assert("e7e5" in prompt_data.user)
	print("[3/4] Fiche technique de position complète et exacte !")

	# 2. Test Détection de Gaffe & Réfutation (Milieu de jeu)
	var fen_blunder = "r1bqkb1r/pppp1ppp/2n5/4p3/2B1n3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"
	var blunder_prompt = coach.build_prompt_data(
		fen_blunder,
		"Cxe4??",
		-280,
		"c4f7",
		["c4f7", "e8f7", "f3e5"],
		"Pourquoi ce coup est-il une gaffe ?",
		{"quality": 8, "cp_loss": 280, "move_number": 4, "is_check": false}
	)

	assert("Gaffe critique (??)" in blunder_prompt.user)
	assert("Perte majeure de 2.80 pions" in blunder_prompt.user)
	assert("Pourquoi ce coup est-il une gaffe ?" in blunder_prompt.user)
	print("[4/4] Détection de gaffe, perte chiffrée et question spécifique validées !")

	# 3. Test Personnalités
	sm.set_setting("coach_personality", "blunder_hunter")
	var hunter_prompt = coach.build_prompt_data(fen_blunder, "Cxe4", -280, "c4f7", [], "", {"personality": "blunder_hunter"})
	assert("incisif" in hunter_prompt.system)

	sm.set_setting("coach_personality", "kids_simple")
	var kids_prompt = coach.build_prompt_data(fen_blunder, "Cxe4", -280, "c4f7", [], "", {"personality": "kids_simple"})
	assert("métaphores visuelles" in kids_prompt.system)

	# Rétablir mentor par défaut
	sm.set_setting("coach_personality", "mentor")

	print("\nExtrait du prompt généré :")
	print("--- SYSTEM PROMPT (Extrait) ---")
	print(prompt_data.system.substr(0, 300) + "...")
	print("\n--- USER PROMPT (Extrait) ---")
	print(prompt_data.user)

	print("\n>>> TOUS LES TESTS PROMPT ENGINEERING ONT RÉUSSI AVEC SUCCÈS ! <<<")
	quit(0)
