extends SceneTree

func _init() -> void:
	print("--- Running Manual Moves Interaction Test ---")
	await create_timer(0.1).timeout
	
	var chess_board_script = load("res://src/ui/components/ChessBoard2D.gd")
	var board = chess_board_script.new() as ChessBoard2D
	board.size = Vector2(400, 400)
	root.add_child(board)
	board._update_dimensions()
	
	var gc = board._get_game_controller()
	assert(gc != null, "GameController singleton must exist")
	gc.reset_to_initial()
	board.reset_board_visuals()
	
	# Initial position: E2 is sq 12 (file 4, rank 1)
	var e2 = 12
	var e3 = 20
	var e4 = 28
	var d2 = 11
	var h5 = 39
	
	# Helper to simulate a mouse click at square
	var click_square = func(sq: int):
		var pos = board._get_square_screen_pos(sq) + Vector2(board.square_size * 0.5, board.square_size * 0.5)
		var press_event = InputEventMouseButton.new()
		press_event.button_index = MOUSE_BUTTON_LEFT
		press_event.pressed = true
		press_event.position = pos
		board._gui_input(press_event)
		
		var release_event = InputEventMouseButton.new()
		release_event.button_index = MOUSE_BUTTON_LEFT
		release_event.pressed = false
		release_event.position = pos
		board._gui_input(release_event)
	
	# 1. Test Click 1 to select piece E2
	print("Step 1: Clicking E2 to select...")
	click_square.call(e2)
	assert(gc.selected_square == e2, "E2 must be selected")
	assert(e3 in gc.legal_destinations, "E3 must be in legal destinations")
	assert(e4 in gc.legal_destinations, "E4 must be in legal destinations")
	assert(board.piece_sprites[e2].visible == true, "Piece on E2 must REMAIN VISIBLE (in place, no detaching!)")
	print("  PASS: E2 selected, legal destinations visible, piece in place.")
	
	# 2. Test Re-click on same piece E2 to deselect
	print("Step 2: Clicking E2 again to deselect...")
	click_square.call(e2)
	assert(gc.selected_square == -1, "E2 must be deselected")
	assert(gc.legal_destinations.is_empty(), "Legal destinations must be empty")
	assert(board.piece_sprites[e2].visible == true, "Piece on E2 remains visible")
	print("  PASS: Re-clicking same piece deselected cleanly.")
	
	# 3. Test Click E2, then Click D2 (friendly piece) -> switch selection
	print("Step 3: Clicking E2 then D2 to switch selection...")
	click_square.call(e2)
	assert(gc.selected_square == e2)
	click_square.call(d2)
	assert(gc.selected_square == d2, "Selection must switch to D2")
	assert(19 in gc.legal_destinations, "D3 must be legal")
	assert(27 in gc.legal_destinations, "D4 must be legal")
	assert(board.piece_sprites[e2].visible == true, "E2 sprite remains visible")
	assert(board.piece_sprites[d2].visible == true, "D2 sprite remains visible")
	print("  PASS: Switched selection to another friendly piece cleanly.")
	
	# 4. Test Click on invalid square (H5) -> deselects
	print("Step 4: Clicking invalid empty square H5...")
	click_square.call(h5)
	assert(gc.selected_square == -1, "Invalid square must deselect")
	assert(gc.legal_destinations.is_empty())
	print("  PASS: Invalid square click deselected.")
	
	# 5. Test Click 1 on E2, then Click 2 on E4 -> Move is executed!
	print("Step 5: Clicking E2 then clicking E4 to play move...")
	click_square.call(e2)
	assert(gc.selected_square == e2)
	click_square.call(e4)
	assert(gc.selected_square == -1, "Selection should be cleared after move")
	assert(gc.game.move_history.size() == 1, "Move history should have 1 move")
	assert(gc.game.move_history[0].from_sq == e2 and gc.game.move_history[0].to_sq == e4, "Move should be E2-E4")
	assert(gc.game.active_color == ChessPiece.PieceColor.BLACK, "Active color should now be Black")
	print("  PASS: E2-E4 executed and recorded in history!")
	
	# Wait for move animation tween to finish
	await create_timer(0.35).timeout
	assert(not board.is_animating_move, "Move animation should be finished")
	assert(board.piece_sprites[e4].visible == true, "E4 piece should be visible after landing")
	assert(board.last_move_from == e2 and board.last_move_to == e4, "Last move markers set")
	print("  PASS: Move animation finished, visuals settled.")
	
	# 6. Test Black's turn: E7 (52) to E5 (36)
	var e7 = 52
	var e5 = 36
	print("Step 6: Black plays E7 to E5...")
	click_square.call(e7)
	assert(gc.selected_square == e7, "E7 selected for Black")
	assert(e5 in gc.legal_destinations, "E5 is legal destination for E7")
	click_square.call(e5)
	assert(gc.game.move_history.size() == 2, "Move history should have 2 moves")
	assert(gc.game.active_color == ChessPiece.PieceColor.WHITE, "Active color back to White")
	print("  PASS: Black move E7-E5 executed cleanly.")
	
	await create_timer(0.35).timeout
	
	# 7. Test Capture move: White plays D2-D4 (11->27), Black plays E5xD4 (36->27)
	var d4 = 27
	print("Step 7: White plays D2 to D4...")
	click_square.call(d2)
	click_square.call(d4)
	assert(gc.game.move_history.size() == 3)
	await create_timer(0.35).timeout
	
	print("Step 8: Black plays E5 x D4 (Capture!)...")
	click_square.call(e5)
	assert(d4 in gc.legal_destinations, "D4 must be a legal capture destination for Black pawn on E5")
	click_square.call(d4)
	assert(gc.game.move_history.size() == 4)
	var cap_move = gc.game.move_history[3]
	assert(cap_move.captured_piece == ChessPiece.Type.PAWN, "Captured piece should be Pawn")
	print("  PASS: Capture move E5xD4 executed with capture data!")
	
	await create_timer(0.35).timeout
	
	# 8. Test swipe/drag move: White plays Knight G1 (sq 6) to F3 (sq 21)
	var g1 = 6
	var f3 = 21
	print("Step 9: Testing swipe gesture from G1 to F3...")
	var pos_g1 = board._get_square_screen_pos(g1) + Vector2(board.square_size * 0.5, board.square_size * 0.5)
	var pos_f3 = board._get_square_screen_pos(f3) + Vector2(board.square_size * 0.5, board.square_size * 0.5)
	
	var drag_press = InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_LEFT
	drag_press.pressed = true
	drag_press.position = pos_g1
	board._gui_input(drag_press)
	
	assert(gc.selected_square == g1, "G1 selected on press")
	
	var drag_release = InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_LEFT
	drag_release.pressed = false
	drag_release.position = pos_f3
	board._gui_input(drag_release)
	
	assert(gc.game.move_history.size() == 5, "Move history should have 5 moves after swipe")
	assert(gc.game.move_history[4].from_sq == g1 and gc.game.move_history[4].to_sq == f3)
	print("  PASS: Swipe gesture G1-F3 successfully executed as well.")
	
	await create_timer(0.35).timeout
	
	print("\nALL MANUAL MOVES & TAP INTERACTION TESTS PASSED CLEANLY!")
	quit(0)
