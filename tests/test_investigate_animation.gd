extends SceneTree

func _init() -> void:
	print("--- INVESTIGATION DU DÉCLENCHEMENT DE L'ANIMATION ---")
	await create_timer(0.2).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_instance = main_scene.instantiate()
	root.add_child(main_instance)
	await process_frame
	await process_frame
	
	var board = main_instance.get_node("VBox/CenterArea/BoardContainer/ChessBoard") as ChessBoard2D
	var gc = root.get_node("GameController")
	
	print("[DEBUG] Board node: ", board)
	print("[DEBUG] GameController: ", gc)
	print("[DEBUG] Signals connected to gc.move_made: ", gc.move_made.get_connections().size())
	for conn in gc.move_made.get_connections():
		print("  -> conn: ", conn["callable"])
	print("[DEBUG] Signals connected to gc.move_navigated: ", gc.move_navigated.get_connections().size())
	for conn in gc.move_navigated.get_connections():
		print("  -> conn: ", conn["callable"])
	print("[DEBUG] Signals connected to gc.position_changed: ", gc.position_changed.get_connections().size())
	for conn in gc.position_changed.get_connections():
		print("  -> conn: ", conn["callable"])
		
	# Test 1: Coup joué par try_play_move (e2 -> e4)
	print("\n--- TEST 1: try_play_move(12, 28) ---")
	var success = gc.try_play_move(12, 28)
	print("try_play_move result: ", success)
	print("is_animating_move immediately after: ", board.is_animating_move)
	print("active_tweens count: ", board.active_tweens.size())
	
	# Test 2: Coup joué par try_play_move (e7 -> e5)
	print("\n--- TEST 2: try_play_move(52, 36) ---")
	# Attendre la fin du premier coup (0.3s)
	await create_timer(0.35).timeout
	print("Before move 2: is_animating_move=", board.is_animating_move)
	var success2 = gc.try_play_move(52, 36)
	print("move 2 result: ", success2)
	print("is_animating_move immediately after move 2: ", board.is_animating_move)
	print("active_tweens count: ", board.active_tweens.size())
	
	# Attendre la fin du coup 2
	await create_timer(0.35).timeout
	
	# Test 3: Navigation arrière (go_previous_move)
	print("\n--- TEST 3: gc.go_previous_move() ---")
	print("Current ply: ", gc.current_ply_index, " board.displayed_ply: ", board.displayed_ply_index)
	gc.go_previous_move()
	print("After go_previous_move: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	
	# Attendre
	await create_timer(0.35).timeout
	
	# Test 4: Navigation avant (go_next_move)
	print("\n--- TEST 4: gc.go_next_move() ---")
	print("Current ply: ", gc.current_ply_index, " board.displayed_ply: ", board.displayed_ply_index)
	gc.go_next_move()
	print("After go_next_move: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	
	# Attendre
	await create_timer(0.35).timeout
	
	# Test 5: Simuler le drag & drop comme un vrai utilisateur
	print("\n--- TEST 5: Simulation Drag & Drop (g1 -> f3, sq 6 -> 21) ---")
	var p_from = board._get_square_screen_pos(6) + Vector2(20, 20)
	var p_to = board._get_square_screen_pos(21) + Vector2(20, 20)
	
	# Mouse down sur g1
	var ev_down = InputEventMouseButton.new()
	ev_down.button_index = MOUSE_BUTTON_LEFT
	ev_down.pressed = true
	ev_down.position = p_from
	board._gui_input(ev_down)
	print("After mouse down g1: dragged_sq=", board.dragged_sq)
	
	# Mouse move vers f3
	var ev_move = InputEventMouseMotion.new()
	ev_move.position = p_to
	board._gui_input(ev_move)
	print("After mouse move to f3: drag_texture_rect.pos=", board.drag_texture_rect.position)
	
	# Mouse up sur f3
	var ev_up = InputEventMouseButton.new()
	ev_up.button_index = MOUSE_BUTTON_LEFT
	ev_up.pressed = false
	ev_up.position = p_to
	board._gui_input(ev_up)
	print("After mouse up f3: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	
	await create_timer(0.35).timeout
	
	# Test 6: Simuler un vrai TAP-to-move (Black plays d7 -> d5, sq 51 -> 35)
	print("\n--- TEST 6: Real Tap-to-Move (d7 -> d5, sq 51 -> 35) ---")
	var p_d7 = board._get_square_screen_pos(51) + Vector2(20, 20)
	var p_d5 = board._get_square_screen_pos(35) + Vector2(20, 20)
	
	# Tap d7 (down then up on d7)
	var ev_d7_down = InputEventMouseButton.new()
	ev_d7_down.button_index = MOUSE_BUTTON_LEFT
	ev_d7_down.pressed = true
	ev_d7_down.position = p_d7
	board._gui_input(ev_d7_down)
	print("After tap d7 down: selected_square=", gc.selected_square, " dragged_sq=", board.dragged_sq)
	
	var ev_d7_up = InputEventMouseButton.new()
	ev_d7_up.button_index = MOUSE_BUTTON_LEFT
	ev_d7_up.pressed = false
	ev_d7_up.position = p_d7
	board._gui_input(ev_d7_up)
	print("After tap d7 up: selected_square=", gc.selected_square, " dragged_sq=", board.dragged_sq, " is_animating=", board.is_animating_move)
	
	# Tap d5 (down then up on d5)
	var ev_d5_down = InputEventMouseButton.new()
	ev_d5_down.button_index = MOUSE_BUTTON_LEFT
	ev_d5_down.pressed = true
	ev_d5_down.position = p_d5
	board._gui_input(ev_d5_down)
	print("After tap d5 down: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	
	var ev_d5_up = InputEventMouseButton.new()
	ev_d5_up.button_index = MOUSE_BUTTON_LEFT
	ev_d5_up.pressed = false
	ev_d5_up.position = p_d5
	board._gui_input(ev_d5_up)
	print("After tap d5 up: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	
	await create_timer(0.35).timeout
	
	# Test 7: Simuler une CAPTURE réelle par tap (White e4 prend d5, sq 28 -> 35)
	print("\n--- TEST 7: Real Capture by Tap (e4 takes d5, sq 28 -> 35) ---")
	var p_e4 = board._get_square_screen_pos(28) + Vector2(20, 20)
	
	# Tap e4
	var ev_e4_down = InputEventMouseButton.new()
	ev_e4_down.button_index = MOUSE_BUTTON_LEFT
	ev_e4_down.pressed = true
	ev_e4_down.position = p_e4
	board._gui_input(ev_e4_down)
	
	var ev_e4_up = InputEventMouseButton.new()
	ev_e4_up.button_index = MOUSE_BUTTON_LEFT
	ev_e4_up.pressed = false
	ev_e4_up.position = p_e4
	board._gui_input(ev_e4_up)
	print("After tap e4: selected_square=", gc.selected_square)
	
	# Tap d5 (capture Black pawn on d5!)
	board._gui_input(ev_d5_down)
	print("After tap d5 down (CAPTURE): is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size(), " fx_children=", board.fx_layer.get_child_count())
	board._gui_input(ev_d5_up)
	print("After tap d5 up (CAPTURE): is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	print("\nFin de l'investigation.")
	quit(0)
