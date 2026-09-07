extends SceneTree

func _init() -> void:
	print("--- Running Test for Last Move & Turn Indicators ---")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.1).timeout

	var board = main_node.get_node("VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard")
	var player_top_row = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerTop")
	var player_bottom_row = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerBottom")
	var player_name_top = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerNameTop")
	var player_name_bottom = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerNameBottom")
	var badge_top_label = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop/TurnBadgeLabelTop")
	var badge_bottom_label = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom/TurnBadgeLabelBottom")
	var badge_top = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop")
	var badge_bottom = main_node.get_node("VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom")

	# 1. Vérification de la visibilité des bandeaux au départ
	assert(player_top_row.visible, "PlayerTopRow must be visible by default")
	assert(player_bottom_row.visible, "PlayerBottomRow must be visible by default")
	assert(player_name_bottom.text == "Blancs", "Bottom player should default to 'Blancs'")
	assert(player_name_top.text == "Noirs", "Top player should default to 'Noirs'")
	print("Step 1: Player rows default visibility and names OK: Top='%s', Bottom='%s'" % [player_name_top.text, player_name_bottom.text])

	# 2. Vérification de l'indicateur au trait de départ (Blancs ont le trait)
	assert(badge_bottom.visible, "Bottom badge should be visible (White's turn)")
	assert(badge_bottom_label.text == "⭐ Au trait", "Bottom player must have '⭐ Au trait'")
	assert(not badge_top.visible, "Top player should not have a badge at start")
	print("Step 2: Turn indicator at initial position OK: White has '⭐ Au trait'")

	# 3. Vérification du calque flèche (ArrowOverlay) sur l'échiquier
	assert(board.arrow_overlay != null, "board must have an arrow_overlay")
	assert(board.arrow_overlay.z_index == 5, "arrow_overlay must have z_index 5")
	assert(board.last_move_from == -1, "No last move at start")
	print("Step 3: ArrowOverlay initialized cleanly on ChessBoard2D (z_index=5).")

	# 4. Jouer le coup 1. e4 (e2 -> e4, 12 -> 28)
	var gc = root.get_node("GameController")
	var move_e4_success = gc.try_play_move(12, 28)
	assert(move_e4_success, "1. e4 move should succeed")
	await create_timer(0.05).timeout

	# Vérifier l'état de l'échiquier après 1. e4
	assert(board.last_move_from == 12, "last_move_from must be 12 (e2)")
	assert(board.last_move_to == 28, "last_move_to must be 28 (e4)")

	# Vérifier les bandeaux joueurs : Blancs ont joué e4, Noirs sont au trait
	assert(badge_top.visible, "Top player (Black) must now be active")
	assert(badge_top_label.text == "⭐ Au trait", "Top player (Black) must show '⭐ Au trait'")
	assert(badge_bottom.visible, "Bottom player (White) must show last move")
	assert(badge_bottom_label.text == "Dernier coup : e4", "Bottom player must show 'Dernier coup : e4', got: " + badge_bottom_label.text)
	print("Step 4: Move 1. e4 verified: White shows 'Dernier coup : e4', Black shows '⭐ Au trait', Board arrow e2->e4.")

	# 5. Jouer le coup 1... e5 (e7 -> e5, 52 -> 36)
	var move_e5_success = gc.try_play_move(52, 36)
	assert(move_e5_success, "1... e5 move should succeed")
	await create_timer(0.05).timeout

	assert(board.last_move_from == 52, "last_move_from must be 52 (e7)")
	assert(board.last_move_to == 36, "last_move_to must be 36 (e5)")
	assert(badge_bottom.visible and badge_bottom_label.text == "⭐ Au trait", "White must show '⭐ Au trait'")
	assert(badge_top.visible and badge_top_label.text == "Dernier coup : e5", "Black must show 'Dernier coup : e5'")
	print("Step 5: Move 1... e5 verified: Black shows 'Dernier coup : e5', White shows '⭐ Au trait', Board arrow e7->e5.")

	# 6. Navigation arrière (retour à 1. e4)
	gc.go_previous_move()
	await create_timer(0.05).timeout

	assert(board.last_move_from == 12, "last_move_from after back navigation must be 12 (e2)")
	assert(board.last_move_to == 28, "last_move_to after back navigation must be 28 (e4)")
	assert(badge_top_label.text == "⭐ Au trait", "Black must be active after back navigation")
	assert(badge_bottom_label.text == "Dernier coup : e4", "White must show 'Dernier coup : e4'")
	print("Step 6: Back navigation verified: board and turn badges reverted cleanly.")

	# 7. Navigation au début (position initiale)
	gc.go_first_move()
	await create_timer(0.05).timeout

	assert(board.last_move_from == -1, "No last move at start after go_first_move")
	assert(badge_bottom_label.text == "⭐ Au trait", "White must be active at start")
	assert(not badge_top.visible, "Black badge should be hidden at start")
	print("Step 7: Start navigation verified: initial state restored.")

	main_node.queue_free()
	print("ALL LAST MOVE & TURN VISUAL TESTS PASSED SUCCESSFULLY!")
	quit(0)
