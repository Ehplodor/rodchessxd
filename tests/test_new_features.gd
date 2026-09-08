extends SceneTree
## test_new_features.gd - Test des nouvelles fonctionnalités :
## 1. Export PGN & Modal
## 2. Reset de l'échiquier (GameController.reset_to_initial)
## 3. Paramètre des aides visuelles (show_move_hints)
## 4. Prompt Coach "Remonter la pente" (sans spoiler le coup exact)
## 5. Détection échec et mat / fin de partie
## 6. Présentation 3 colonnes et résumé dans MoveList2D
## 7. Structure de CoachPanel2D (tuiles en haut, pas de champ texte perso)

const ChessGameScript = preload("res://src/core/ChessGame.gd")
const ChessPieceScript = preload("res://src/core/ChessPiece.gd")
const GameControllerScript = preload("res://src/core/GameController.gd")
const SettingsManagerScript = preload("res://src/core/SettingsManager.gd")
const AICoachScript = preload("res://src/ai/AICoach.gd")
const PGNModalScript = preload("res://src/ui/components/PGNModal.gd")
const MoveList2DScript = preload("res://src/ui/components/MoveList2D.gd")
const CoachPanel2DScript = preload("res://src/ui/components/CoachPanel2D.gd")

func _init() -> void:
	print("[TEST] --- Démarrage des tests des nouvelles fonctionnalités ---")
	await create_timer(0.1).timeout

	# 1. Test SettingsManager : paramètre 'show_move_hints'
	print("\n[TEST 1] SettingsManager show_move_hints...")
	var sm = SettingsManagerScript.new()
	sm.name = "SettingsManager"
	root.add_child(sm)
	
	var default_hints = sm.get_setting("show_move_hints", true)
	assert(default_hints == true, "show_move_hints devrait être true par défaut")
	sm.set_setting("show_move_hints", false)
	assert(sm.get_setting("show_move_hints", true) == false, "show_move_hints devrait être false après modification")
	sm.set_setting("show_move_hints", true)
	print("  -> SettingsManager show_move_hints : OK ✓")

	# 2. Test GameController reset_to_initial & PGN export
	print("\n[TEST 2] GameController reset_to_initial & PGN export...")
	var gc = root.get_node_or_null("GameController")
	if gc == null:
		gc = GameControllerScript.new()
		gc.name = "GameController"
		root.add_child(gc)
	var game = gc.game

	gc.reset_to_initial()
	var pgn_initial = game.export_pgn()
	assert(pgn_initial.contains("[FEN ") or pgn_initial.contains("[Result"), "Export PGN initial invalide")

	# Charger des coups via PGN : 1. e4 e5 2. Nf3
	assert(gc.load_pgn("1. e4 e5 2. Nf3"), "Chargement PGN '1. e4 e5 2. Nf3' doit réussir")
	assert(game.move_history.size() == 3, "Il devrait y avoir 3 demi-coups dans l'historique")

	var pgn_moves = game.export_pgn()
	assert(pgn_moves.contains("1. e4 e5 2. Nf3"), "PGN exporté devrait contenir '1. e4 e5 2. Nf3' : %s" % pgn_moves)
	print("  -> PGN export : OK ✓ (%s)" % pgn_moves.strip_edges())

	# Test PGNModal export mode
	var pgn_modal = PGNModalScript.new()
	root.add_child(pgn_modal)
	pgn_modal.set_export_mode(pgn_moves)
	assert(pgn_modal.pgn_text_edit.text == pgn_moves, "PGNModal pgn_text_edit devrait contenir le PGN exporté")
	assert(pgn_modal.pgn_text_edit.editable == false, "PGNModal pgn_text_edit devrait être en lecture seule lors de l'export")
	pgn_modal.queue_free()
	print("  -> PGNModal mode export : OK ✓")

	# Test Reset de l'échiquier
	gc.reset_to_initial()
	assert(game.move_history.is_empty(), "move_history devrait être vide après reset_to_initial")
	assert(gc.current_ply_index == -1, "current_ply_index devrait valoir -1 après reset")
	assert(game.active_color == ChessPieceScript.PieceColor.WHITE, "Au trait devrait être les Blancs après reset")
	print("  -> GameController.reset_to_initial : OK ✓")

	# 3. Test Détection Échec et mat (Mat du Berger / Scholar's Mate)
	print("\n[TEST 3] Détection Échec et mat...")
	# 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#
	var mate_game = ChessGameScript.new()
	mate_game.load_fen("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")
	assert(mate_game.active_color == ChessPieceScript.PieceColor.BLACK, "Les noirs doivent être au trait")
	var is_in_chk = mate_game.is_in_check(ChessPieceScript.PieceColor.BLACK)
	assert(is_in_chk == true, "Le roi noir doit être en échec")
	var black_legal = mate_game.get_legal_moves(ChessPieceScript.PieceColor.BLACK)
	assert(black_legal.is_empty(), "Les noirs ne doivent avoir aucun coup légal (Mat)")
	print("  -> Mat du Berger détecté avec succès (is_in_check=true, legal_moves=0) : OK ✓")

	# 4. Test AICoach : Prompt "Remonter la pente" (sans spoiler)
	print("\n[TEST 4] AICoach Prompt 'Remonter la pente'...")
	var coach = AICoachScript.new()
	coach.name = "AICoach"
	root.add_child(coach)

	var prompt_data = coach.build_prompt_data(
		"r1bqkb1r/pppp1ppp/2n5/4p3/2B1n3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4",
		"Cxe4",
		-250,
		"c4f7",
		["c4f7", "e8f7", "f3e5"],
		"Comment remonter la pente dans cette position difficile sans me donner la solution directe ?",
		{"quality": 8, "cp_loss": 250, "move_number": 4}
	)

	assert(prompt_data.system.contains("REMONTER LA PENTE"), "Le prompt système doit mentionner le rôle Remonter la pente")
	assert(prompt_data.system.contains("SANS SPOILER"), "Le prompt système doit interdire de spoiler le coup exact")
	assert(prompt_data.system.contains("Défense active et contre-jeu"), "Le plan conseillé doit inviter au contre-jeu")
	print("  -> Directive anti-spoiler 'Remonter la pente' validée : OK ✓")

	# 5. Test MoveList2D : Table 3 colonnes et carte résumé
	print("\n[TEST 5] MoveList2D présentation 3 colonnes et résumé...")
	var move_list = MoveList2DScript.new()
	root.add_child(move_list)

	var mock_report = {
		"white_accuracy": 88.4,
		"black_accuracy": 72.1,
		"white_estimated_elo": 1820,
		"black_estimated_elo": 1540,
		"white_elo_ci": 45,
		"black_elo_ci": 60,
		"white_acpl": 22.5,
		"black_acpl": 54.0,
		"elo_comparison": {
			"diff_elo": 280,
			"p_value": 0.002,
			"stars": "**"
		},
		"white_stats": {
			"best": 12, "excellent": 5, "good": 3, "inaccuracy": 1, "mistake": 0, "blunder": 0
		},
		"black_stats": {
			"best": 8, "excellent": 3, "good": 2, "inaccuracy": 3, "mistake": 2, "blunder": 1
		},
		"evaluations": []
	}

	move_list.set_analysis_report(mock_report)
	assert(not move_list._analysis_report.is_empty(), "move_list devrait avoir un rapport d'analyse")
	assert(move_list.container.get_child_count() >= 4, "move_list.container devrait contenir la table 3 colonnes, la carte résumé, l'en-tête et les filtres")
	print("  -> MoveList2D stats 3 colonnes & résumé : OK ✓")
	move_list.queue_free()

	# 6. Test CoachPanel2D : Tuiles de prompt visibles en haut, absence de question_input
	print("\n[TEST 6] CoachPanel2D structure (prompts en haut, pas d'input personnalisé)...")
	var coach_panel = CoachPanel2DScript.new()
	root.add_child(coach_panel)

	assert(coach_panel.prompt_grid != null, "prompt_grid devrait exister")
	assert(coach_panel.prompt_grid.get_child_count() == 7, "Il devrait y avoir 7 tuiles de prompts (dont 'Remonter la pente')")
	assert(coach_panel.get_node_or_null("Layout/InputRow/QuestionInput") == null, "QuestionInput ne doit plus exister")
	assert(coach_panel.get_node_or_null("Layout/InputRow/BtnSend") == null, "BtnSend ne doit plus exister")
	assert(coach_panel.conv_scroll != null, "conv_scroll doit exister pour les boutons de conversation")
	print("  -> CoachPanel2D structure conforme : OK ✓")
	coach_panel.queue_free()

	print("\n[TEST] ================================================================")
	print("[TEST] TOUS LES TESTS DES NOUVELLES FONCTIONNALITÉS ONT RÉUSSI (100% OK) !")
	print("[TEST] ================================================================\n")
	quit(0)
