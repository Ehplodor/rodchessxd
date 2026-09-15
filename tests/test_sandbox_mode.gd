extends SceneTree

func _init() -> void:
	print("\n=== Test Mode Sandbox / TimeFreeze & Engine Line Play ===")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.3).timeout
	
	var gc = root.get_node_or_null("GameController")
	assert(gc != null, "GameController doit exister")
	
	# Charger une partie test
	var initial_pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5"
	gc.load_pgn(initial_pgn, "test_game_123")
	await create_timer(0.2).timeout
	
	var saved_fen_before = gc.game.get_fen()
	var saved_ply_before = gc.current_ply_index
	var saved_game_id_before = gc.current_game_id
	print("Partie originale chargée:")
	print("  FEN = %s" % saved_fen_before)
	print("  Ply = %d" % saved_ply_before)
	print("  Game ID = %s" % saved_game_id_before)
	
	assert(main_node.btn_toggle_sandbox != null, "Le bouton BtnToggleSandbox doit exister")
	assert(main_node.btn_toggle_sandbox.text == "⏸ Test", "Libellé initial du bouton doit être '⏸ Test'")
	assert(main_node.is_sandbox_mode == false, "Le mode sandbox doit être inactif au départ")
	
	# 1. Cliquer sur une ligne moteur pour jouer un coup (ex: 4. d3 / d2d3 ou c2c3)
	print("\n--- 1. Clic sur ligne moteur pour jouer d2d3 ---")
	main_node._on_engine_line_selected(1, ["d2d3", "Nf6"], "d2d3")
	await create_timer(0.2).timeout
	
	assert(main_node.is_sandbox_mode == true, "Le mode sandbox doit être activé après clic sur ligne moteur")
	assert(main_node.btn_toggle_sandbox.text == "⏯ Reprendre", "Le bouton doit indiquer '⏯ Reprendre'")
	assert(gc.game.get_fen() != saved_fen_before, "La position doit avoir changé sur l'échiquier")
	assert(gc.current_ply_index == saved_ply_before + 1, "Le coup doit avoir été joué (ply incrémenté)")
	assert(main_node._sandbox_saved_game_id == saved_game_id_before, "Le game_id de la partie originale doit être préservé dans la sauvegarde")
	print("  Coup joué avec succès en mode sandbox! FEN = %s" % gc.game.get_fen())
	
	# 2. Jouer un second coup de test en sandbox (ex: Nf6 / g8f6)
	print("\n--- 2. Jouer un second coup en mode sandbox ---")
	var move2 = gc.game.find_move("g8f6")
	assert(move2 != null, "g8f6 doit être un coup légal")
	gc.try_play_move(move2.from_sq, move2.to_sq)
	await create_timer(0.1).timeout
	print("  Deuxième coup joué! Ply = %d, FEN = %s" % [gc.current_ply_index, gc.game.get_fen()])
	
	# 3. Quitter le mode sandbox en cliquant sur le bouton Reprendre
	print("\n--- 3. Clic sur BtnToggleSandbox pour quitter le mode Test ---")
	main_node._on_btn_toggle_sandbox_pressed()
	await create_timer(0.2).timeout
	
	assert(main_node.is_sandbox_mode == false, "Le mode sandbox doit être désactivé")
	assert(main_node.btn_toggle_sandbox.text == "⏸ Test", "Le bouton doit revenir à '⏸ Test'")
	assert(gc.current_game_id == saved_game_id_before, "Le Game ID original doit être restauré: %s vs %s" % [gc.current_game_id, saved_game_id_before])
	assert(gc.current_ply_index == saved_ply_before, "Le ply original doit être restauré: %d vs %d" % [gc.current_ply_index, saved_ply_before])
	assert(gc.game.get_fen() == saved_fen_before, "La position FEN originale doit être exactement restaurée")
	print("  Position originale restaurée avec succès! FEN = %s" % gc.game.get_fen())
	
	# 4. Activer manuellement le mode Test via le bouton, puis quitter
	print("\n--- 4. Bascule manuelle du bouton Test ---")
	main_node._on_btn_toggle_sandbox_pressed()
	assert(main_node.is_sandbox_mode == true, "Le mode sandbox doit être activé")
	assert(main_node.btn_toggle_sandbox.text == "⏯ Reprendre")
	
	main_node._on_btn_toggle_sandbox_pressed()
	assert(main_node.is_sandbox_mode == false, "Le mode sandbox doit être désactivé")
	assert(main_node.btn_toggle_sandbox.text == "⏸ Test")
	assert(gc.game.get_fen() == saved_fen_before, "La position reste intacte")
	
	print("\n=== TOUS LES TESTS DU MODE TEST / SANDBOX SONT VALIDÉS AVEC SUCCÈS! ===\n")
	quit(0)
