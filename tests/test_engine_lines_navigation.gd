extends SceneTree

func _init() -> void:
	print("\n=== Test de mise à jour des lignes moteur lors de la navigation ===")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.3).timeout
	
	var em = root.get_node_or_null("EngineManager")
	assert(em != null, "EngineManager doit exister")
	if not em.is_engine_running:
		await em.engine_ready
	
	em.evaluation_updated.connect(func(score_cp, mate_in, depth, best_move, pv, multipv):
		var line_fen = ""
		if multipv.size() > 0:
			line_fen = multipv[0].get("fen", "")
		print(">> EVAL EMITTED: depth=%d, score=%d, best=%s, multipv_count=%d, fen=%s" % [depth, score_cp, best_move, multipv.size(), line_fen])
	)
	
	var gc = root.get_node_or_null("GameController")
	assert(gc != null, "GameController doit exister")
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6")
	await create_timer(0.2).timeout
	
	print("Partie chargée. Ply actuel: %d" % gc.current_ply_index)
	print("FEN actuelle: %s" % gc.game.get_fen())
	
	# Attendre que l'évaluation Live se fasse sur la position finale (ply 5 : 3... a6)
	print("Attente de l'évaluation Live sur le dernier coup...")
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			break
	
	print("Lignes panneau après chargement: %d lignes, depth=%d" % [main_node.engine_lines_panel._lines.size(), main_node.engine_lines_panel._depth])
	if main_node.engine_lines_panel._lines.size() > 0:
		var line0 = main_node.engine_lines_panel._lines[0]
		print("Ligne 0: fen=%s, score_cp=%s, best_move=%s, pv=%s" % [line0.get("fen"), line0.get("score_cp"), line0.get("best_move"), line0.get("pv")])
		print("Texte bouton row 0: %s" % main_node.engine_lines_panel._row_buttons[0].text)
	
	# Naviguer en arrière avec btn_prev (doit passer à ply 4 : 3. Bb5, trait aux Noirs)
	print("\n--- Test Navigation Arrière (BtnPrev -> ply 4) ---")
	main_node._on_btn_prev_pressed()
	print("Nouveau ply: %d, active_color=%s (trait aux %s)" % [
		gc.current_ply_index,
		gc.game.active_color,
		"Blancs" if gc.game.active_color == ChessPiece.PieceColor.WHITE else "Noirs"
	])
	print("FEN attendue: %s" % gc.game.get_fen())
	
	# Observer comment le panneau se met à jour
	var lines_updated_for_ply4 = false
	var expected_fen_ply4 = gc.game.get_fen()
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			var cur_line_fen = str(main_node.engine_lines_panel._lines[0].get("fen", ""))
			if cur_line_fen == expected_fen_ply4:
				lines_updated_for_ply4 = true
				break
	
	print("Lignes mises à jour pour ply 4: %s" % str(lines_updated_for_ply4))
	if main_node.engine_lines_panel._lines.size() > 0:
		var line0 = main_node.engine_lines_panel._lines[0]
		print("Ligne 0 ply 4: fen=%s, score_cp=%s, best_move=%s, pv=%s" % [line0.get("fen"), line0.get("score_cp"), line0.get("best_move"), line0.get("pv")])
		print("Texte bouton row 0: %s" % main_node.engine_lines_panel._row_buttons[0].text)
	
	# Naviguer encore en arrière (BtnPrev -> ply 3 : 2... Nc6, trait aux Blancs)
	print("\n--- Test Navigation Arrière (BtnPrev -> ply 3) ---")
	main_node._on_btn_prev_pressed()
	print("Nouveau ply: %d, active_color=%s (trait aux %s)" % [
		gc.current_ply_index,
		gc.game.active_color,
		"Blancs" if gc.game.active_color == ChessPiece.PieceColor.WHITE else "Noirs"
	])
	print("FEN attendue: %s" % gc.game.get_fen())
	
	var lines_updated_for_ply3 = false
	var expected_fen_ply3 = gc.game.get_fen()
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			var cur_line_fen = str(main_node.engine_lines_panel._lines[0].get("fen", ""))
			if cur_line_fen == expected_fen_ply3:
				lines_updated_for_ply3 = true
				break
	
	print("Lignes mises à jour pour ply 3: %s" % str(lines_updated_for_ply3))
	if main_node.engine_lines_panel._lines.size() > 0:
		var line0 = main_node.engine_lines_panel._lines[0]
		print("Ligne 0 ply 3: fen=%s, score_cp=%s, best_move=%s, pv=%s" % [line0.get("fen"), line0.get("score_cp"), line0.get("best_move"), line0.get("pv")])
		print("Texte bouton row 0: %s" % main_node.engine_lines_panel._row_buttons[0].text)

	# Maintenant avancer (BtnNext -> ply 4 puis ply 5)
	print("\n--- Test Navigation Avant (BtnNext -> ply 4) ---")
	main_node._on_btn_next_pressed()
	print("Nouveau ply: %d, FEN: %s" % [gc.current_ply_index, gc.game.get_fen()])
	var lines_updated_forward = false
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			var cur_line_fen = str(main_node.engine_lines_panel._lines[0].get("fen", ""))
			if cur_line_fen == expected_fen_ply4:
				lines_updated_forward = true
				break
	assert(lines_updated_for_ply4, "Les lignes moteur doivent être mises à jour pour ply 4 (trait aux Noirs)")
	assert(lines_updated_for_ply3, "Les lignes moteur doivent être mises à jour pour ply 3 (trait aux Blancs)")
	assert(lines_updated_forward, "Les lignes moteur doivent être mises à jour vers l'avant (ply 4)")

	# Test BtnFirst (début de partie, ply -1)
	print("\n--- Test Navigation Début (BtnFirst -> ply -1) ---")
	main_node._on_btn_first_pressed()
	assert(gc.current_ply_index == -1, "Doit être au ply -1")
	var expected_initial_fen = ChessGame.INITIAL_FEN
	var lines_updated_initial = false
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			var cur_line_fen = str(main_node.engine_lines_panel._lines[0].get("fen", ""))
			if cur_line_fen == expected_initial_fen:
				lines_updated_initial = true
				break
	print("Lignes mises à jour pour position initiale: %s" % str(lines_updated_initial))
	assert(lines_updated_initial, "Les lignes moteur doivent être mises à jour pour la position initiale")
	print("Texte bouton initial: %s" % main_node.engine_lines_panel._row_buttons[0].text)

	# Test BtnLast (fin de partie, ply 5)
	print("\n--- Test Navigation Fin (BtnLast -> ply 5) ---")
	var expected_fen_ply5 = "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"
	main_node._on_btn_last_pressed()
	assert(gc.current_ply_index == 5, "Doit être au ply 5")
	var lines_updated_last = false
	for _wait in range(30):
		await create_timer(0.1).timeout
		if main_node.engine_lines_panel._lines.size() > 0:
			var cur_line_fen = str(main_node.engine_lines_panel._lines[0].get("fen", ""))
			if cur_line_fen == expected_fen_ply5:
				lines_updated_last = true
				break
	print("Lignes mises à jour pour position finale: %s" % str(lines_updated_last))
	assert(lines_updated_last, "Les lignes moteur doivent être mises à jour pour la position finale")
	print("Texte bouton dernier coup: %s" % main_node.engine_lines_panel._row_buttons[0].text)

	print("\n🎉 TOUS LES TESTS DE NAVIGATION ET LIGNES MOTEUR SONT VALIDÉS AVEC SUCCÈS !")
	main_node.queue_free()
	quit(0)
