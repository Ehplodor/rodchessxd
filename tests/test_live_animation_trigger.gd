extends SceneTree

func _init() -> void:
	print("--- Diagnostic live animation trigger ---")
	await create_timer(0.2).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_instance = main_scene.instantiate()
	root.add_child(main_instance)
	await process_frame
	await process_frame
	
	var board = main_instance.get_node("VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard") as ChessBoard2D
	assert(board != null, "ChessBoard must exist")
	print("Board found: size=", board.size, " square_size=", board.square_size)
	print("Initial active tweens: ", board.active_tweens.size())
	
	var gc = root.get_node_or_null("GameController")
	if not gc:
		var gc_script = load("res://src/core/GameController.gd")
		gc = gc_script.new()
		root.add_child(gc)
	
	# Test 1: Simuler un clic e2 puis e4
	# e2 est sq 12, e4 est sq 28
	var pos_e2 = board._get_square_screen_pos(12) + Vector2(25, 25)
	var pos_e4 = board._get_square_screen_pos(28) + Vector2(25, 25)
	
	print("\n--- Test 1: Tap e2 then Tap e4 ---")
	# Press e2
	board._handle_press(12, pos_e2)
	print("After press e2: selected_square=", gc.selected_square, " dragged_sq=", board.dragged_sq)
	# Release e2
	board._handle_release(12, pos_e2)
	print("After release e2: selected_square=", gc.selected_square, " is_animating=", board.is_animating_move)
	
	# Press e4
	board._handle_press(28, pos_e4)
	print("After press e4: is_animating=", board.is_animating_move, " active_tweens=", board.active_tweens.size())
	# Release e4
	board._handle_release(28, pos_e4)
	print("After release e4: is_animating=", board.is_animating_move, " active_tweens=", board.active_tweens.size())
	
	# Observons pendant 10 frames
	for frame in range(10):
		await process_frame
		var moving_sprite = board.piece_sprites.get(12, null)
		var pos = moving_sprite.position if moving_sprite else Vector2.ZERO
		var scale = moving_sprite.scale if moving_sprite else Vector2.ZERO
		print("Frame %d: is_animating=%s, tweens=%d, sprite_pos=%s, sprite_scale=%s" % [frame, board.is_animating_move, board.active_tweens.size(), pos, scale])
	
	# Test 2: Navigation précédente / suivante
	print("\n--- Test 2: Naviguer en arrière puis en avant ---")
	gc.go_previous_move()
	print("After go_previous_move: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	for frame in range(5):
		await process_frame
		print("Back Frame %d: is_animating=%s, tweens=%d" % [frame, board.is_animating_move, board.active_tweens.size()])
		
	gc.go_next_move()
	print("After go_next_move: is_animating=", board.is_animating_move, " tweens=", board.active_tweens.size())
	for frame in range(5):
		await process_frame
		print("Forward Frame %d: is_animating=%s, tweens=%d" % [frame, board.is_animating_move, board.active_tweens.size()])
		
	main_instance.queue_free()
	print("Diagnostic terminé.")
	quit(0)
