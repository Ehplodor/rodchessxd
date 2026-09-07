extends SceneTree

func _init() -> void:
	print("--- Verifying Fix for Double Event and Touch Coordinates ---")
	await create_timer(0.2).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_instance = main_scene.instantiate()
	root.add_child(main_instance)
	
	await create_timer(0.2).timeout
	
	var board = main_instance.get_node("VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard") as ChessBoard2D
	var gc = main_instance.get_node("/root/GameController")
	gc.reset_to_initial()
	
	var e2 = 12
	var e4 = 28
	var pos_e2_local = board._get_square_screen_pos(e2) + Vector2(board.square_size * 0.5, board.square_size * 0.5)
	var pos_e2_global = board.global_position + pos_e2_local
	var pos_e4_local = board._get_square_screen_pos(e4) + Vector2(board.square_size * 0.5, board.square_size * 0.5)
	var pos_e4_global = board.global_position + pos_e4_local
	
	print("Pos E2 local: ", pos_e2_local, " global: ", pos_e2_global)
	print("Pos E4 local: ", pos_e4_local, " global: ", pos_e4_global)
	
	# Simulate Godot's mobile input sequence on E2:
	# 1. ScreenTouch pressed (with global pos)
	var touch_down = InputEventScreenTouch.new()
	touch_down.pressed = true
	touch_down.position = pos_e2_global
	
	# 2. MouseButton pressed (emulated, with local pos)
	var mouse_down = InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.pressed = true
	mouse_down.position = pos_e2_local
	
	# 3. ScreenTouch released
	var touch_up = InputEventScreenTouch.new()
	touch_up.pressed = false
	touch_up.position = pos_e2_global
	
	# 4. MouseButton released
	var mouse_up = InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.pressed = false
	mouse_up.position = pos_e2_local
	
	print("\nSimulating Tap on E2 with touch + emulated mouse events...")
	board._gui_input(touch_down)
	board._gui_input(mouse_down)
	board._gui_input(touch_up)
	board._gui_input(mouse_up)
	
	print("Result after E2 tap sequence: gc.selected_square = ", gc.selected_square)
	
	# Now simulate Tap on E4 (legal move)
	var touch_down_e4 = InputEventScreenTouch.new()
	touch_down_e4.pressed = true
	touch_down_e4.position = pos_e4_global
	
	var mouse_down_e4 = InputEventMouseButton.new()
	mouse_down_e4.button_index = MOUSE_BUTTON_LEFT
	mouse_down_e4.pressed = true
	mouse_down_e4.position = pos_e4_local
	
	var touch_up_e4 = InputEventScreenTouch.new()
	touch_up_e4.pressed = false
	touch_up_e4.position = pos_e4_global
	
	var mouse_up_e4 = InputEventMouseButton.new()
	mouse_up_e4.button_index = MOUSE_BUTTON_LEFT
	mouse_up_e4.pressed = false
	mouse_up_e4.position = pos_e4_local
	
	print("\nSimulating Tap on E4 with touch + emulated mouse events...")
	board._gui_input(touch_down_e4)
	board._gui_input(mouse_down_e4)
	board._gui_input(touch_up_e4)
	board._gui_input(mouse_up_e4)
	
	assert(gc.game.move_history.size() == 1, "Move must be recorded")
	var move = gc.game.move_history[0]
	print("Move played: from=", move.from_sq, " to=", move.to_sq, " san=", move.san)
	assert(move.from_sq == e2 and move.to_sq == e4, "Move must be e2->e4")
	print("\nALL MOBILE INPUT SEQUENCE CHECKS PASSED WITH FLYING COLORS!")
	main_instance.queue_free()
	quit(0)
