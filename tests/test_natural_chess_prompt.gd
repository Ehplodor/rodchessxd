extends SceneTree
## test_natural_chess_prompt.gd - Test unitaire de la traduction algorithmique naturelle des coups d'échecs

const ChessGameScript = preload("res://src/core/ChessGame.gd")
const AICoachScript = preload("res://src/ai/AICoach.gd")

func _init() -> void:
	print("--- Test Unitaire : Interprétation Algorithmique Naturelle des Coups ---")
	await create_timer(0.1).timeout

	# 1. Test des déplacements standards depuis la position initiale
	var init_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	var e4_desc = ChessGameScript.describe_move_from_fen(init_fen, "e2e4")
	print("e2e4 : ", e4_desc)
	assert(e4_desc == "Pion blanc avance de e2 en e4", "e2e4 doit être décrit comme une avance de pion blanc")

	var nf3_desc = ChessGameScript.describe_move_from_fen(init_fen, "g1f3")
	print("g1f3 : ", nf3_desc)
	assert(nf3_desc == "Cavalier blanc se déplace de g1 en f3", "g1f3 doit être décrit comme un déplacement de cavalier")

	# 2. Test d'une prise majeure (Dame en c3 prend Tour en e3)
	# FEN avec Dame blanche en c3 et Tour noire en e3
	var capture_fen = "r3k2r/pppp1ppp/8/8/8/2Q1r3/PP3PPP/R3K2R w KQkq - 0 1"
	var cap_desc = ChessGameScript.describe_move_from_fen(capture_fen, "c3e3")
	print("c3e3 (Dame prend Tour) : ", cap_desc)
	assert(cap_desc.contains("Dame blanche en c3 prend la Tour noire en e3"), "c3e3 doit décrire explicitement Dame prend Tour")

	# 3. Test du roque
	var castling_fen = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1"
	var o_o_desc = ChessGameScript.describe_move_from_fen(castling_fen, "e1g1")
	print("e1g1 (Petit roque) : ", o_o_desc)
	assert(o_o_desc.begins_with("Petit roque des Blancs"), "e1g1 doit être décrit comme petit roque des Blancs")

	var o_o_o_desc = ChessGameScript.describe_move_from_fen(castling_fen, "e1c1")
	print("e1c1 (Grand roque) : ", o_o_o_desc)
	assert(o_o_o_desc.begins_with("Grand roque des Blancs"), "e1c1 doit être décrit comme grand roque des Blancs")

	# 4. Test de promotion (Roi noir en d8 pour que e8 soit libre)
	var prom_fen = "3k4/4P3/8/8/8/8/8/4K3 w - - 0 1"
	var prom_desc = ChessGameScript.describe_move_from_fen(prom_fen, "e7e8q")
	print("e7e8q (Promotion) : ", prom_desc)
	assert(prom_desc.contains("est promu en Dame"), "e7e8q doit mentionner la promotion en Dame")

	# 5. Test de la variante PV complète décodée séquentiellement
	var pv_fen = "r3r1k1/ppp2ppp/8/8/8/2Q1r3/PP3PPP/4R1K1 w - - 0 1"
	var pv_moves = ["c3e3", "e8e3", "e1e3", "g8f8"]
	var pv_text = ChessGameScript.format_pv_natural_text(pv_fen, pv_moves, 4)
	print("\nVariante PV séquentielle décodée :\n", pv_text)
	assert(pv_text.contains("Dame blanche en c3 prend la Tour noire en e3"), "Le coup 1 doit être Dame prend Tour")
	assert(pv_text.contains("Tour noire en e8 prend la Dame blanche en e3"), "Le coup 2 doit être la reprise de la Dame")

	# 6. Test du générateur de prompt pour le Coach IA
	print("\nVérification de l'intégration dans AICoach.build_prompt_data...")
	var coach = AICoachScript.new()
	root.add_child(coach)

	var extra = {
		"perspective": "white",
		"last_move_color": "white",
		"last_move_natural": "Dame blanche en c3 prend la Tour noire en e3"
	}
	var prompt_data = coach.build_prompt_data(
		pv_fen,
		"Dxe3",
		250,
		"e1e3",
		["e1e3", "g8f8"],
		"Pourquoi ce coup ?",
		extra
	)

	var user_p = prompt_data.get("user", "")
	print("\nExtrait du prompt utilisateur généré :\n", user_p)
	assert(user_p.contains("Dxe3 (Dame blanche en c3 prend la Tour noire en e3 - joué par les Blancs)"), "Le prompt doit intégrer l'action naturelle du dernier coup")
	assert(user_p.contains("`e1e3` (Tour blanche en e1 prend la Tour noire en e3)"), "Le prompt doit décoder le meilleur coup de Stockfish")
	assert(user_p.contains("Tour blanche en e1 prend la Tour noire en e3"), "La variante PV doit être décodée coup par coup")

	coach.queue_free()
	print("\n>>> TOUS LES TESTS D'INTERPRÉTATION NATURELLE ONT RÉUSSI AVEC SUCCÈS ! <<<")
	quit(0)
