extends SceneTree

func _init() -> void:
	print("--- Running Board Animations and Graphics Test ---")
	await create_timer(0.1).timeout
	
	var chess_board_script = load("res://src/ui/components/ChessBoard2D.gd")
	var eval_bar_script = load("res://src/ui/components/EvalBar2D.gd")
	
	# 1. Test ChessBoard2D instantiation & layout
	var board = chess_board_script.new()
	board.size = Vector2(400, 400)
	root.add_child(board)
	board._update_dimensions()
	
	assert(board.board_size == 400.0, "Board size should be 400")
	assert(board.square_size == 50.0, "Square size should be 50")
	print("Board dimensions verified: size=%.1f, square=%.1f" % [board.board_size, board.square_size])
	
	# 2. Test square coordinate mapping (non-flipped & flipped)
	var gc = board._get_game_controller()
	if gc:
		gc.board_flipped = false
	var pos_a1_white = board._get_square_screen_pos(0)
	print("Square a1 (White view): ", pos_a1_white)
	assert(pos_a1_white == Vector2(0, 350), "a1 position should be (0, 350) in White view")
	
	if gc:
		gc.board_flipped = true
	var pos_a1_black = board._get_square_screen_pos(0)
	print("Square a1 (Black view): ", pos_a1_black)
	assert(pos_a1_black == Vector2(350, 0), "a1 position should be (350, 0) in Black view")
	
	if gc:
		gc.board_flipped = false
	
	# 3. Test animated move call
	var move = ChessMove.new()
	move.from_sq = 12 # e2
	move.to_sq = 28   # e4
	move.piece = ChessPiece.Type.PAWN
	move.color = ChessPiece.PieceColor.WHITE
	board._animate_move(move)
	assert(board.active_tweens.size() > 0, "An active tween should be registered for move glide")
	print("Move animation registered successfully with %d tweens." % board.active_tweens.size())
	
	# 4. Test EvalBar2D
	var eval_bar = eval_bar_script.new()
	eval_bar.size = Vector2(24, 400)
	root.add_child(eval_bar)
	eval_bar._on_engine_eval(150, 0, 15, "e2e4", [], [])
	assert(eval_bar.display_score_text == "+1.5", "Display score text should be +1.5")
	print("EvalBar score verified: %s, target_ratio: %.3f" % [eval_bar.display_score_text, eval_bar.target_ratio])
	eval_bar.queue_redraw()
	
	# 5. Test board with check & arrow
	board.in_check_sq = 4 # King on e1
	board.check_layer.timer = 1.5
	board.check_layer.set_process(true)
	board.best_move_arrow_from = 12 # e2
	board.best_move_arrow_to = 28   # e4
	board.queue_redraw()
	await process_frame
	print("Board queue_redraw with check & arrow executed without errors.")
	
	# 6. Test castling animation (e1g1)
	var castle_move = ChessMove.new()
	castle_move.from_sq = 4
	castle_move.to_sq = 6
	castle_move.piece = ChessPiece.Type.KING
	castle_move.color = ChessPiece.PieceColor.WHITE
	castle_move.is_castling = true
	board._animate_move(castle_move)
	assert(board.active_tweens.size() >= 2, "Castling should animate both King and Rook (tweens >= 2)")
	print("Castling animation verified with %d tweens." % board.active_tweens.size())
	
	# 7. Test capture explosion and vibration FX
	var cap_move = ChessMove.new()
	cap_move.from_sq = 28 # e4
	cap_move.to_sq = 35   # d5
	cap_move.piece = ChessPiece.Type.PAWN
	cap_move.color = ChessPiece.PieceColor.WHITE
	cap_move.captured_piece = ChessPiece.Type.PAWN
	board._animate_move(cap_move)
	assert(board.fx_layer != null, "fx_layer should exist on board")
	assert(board.fx_layer.get_child_count() > 0, "fx_layer should have active CaptureBurstFX")
	assert(board.ghost_sprites.size() > 0, "A ghost piece should be vibrating/dissipating")
	print("Capture explosion & vibration FX verified: fx_layer childs=%d, ghosts=%d." % [board.fx_layer.get_child_count(), board.ghost_sprites.size()])
	
	# 8. Test History Navigation Animations (Forward & Backward)
	var nav_move = ChessMove.new()
	nav_move.from_sq = 12 # e2
	nav_move.to_sq = 28   # e4
	nav_move.piece = ChessPiece.Type.PAWN
	nav_move.color = ChessPiece.PieceColor.WHITE
	
	board._animate_navigation_forward(nav_move)
	assert(board.is_animating_move, "Navigation forward should set is_animating_move = true")
	assert(board.active_tweens.size() > 0, "Navigation forward should register active tweens")
	print("History navigation forward animation verified.")
	
	board._animate_navigation_backward(nav_move)
	assert(board.is_animating_move, "Navigation backward should set is_animating_move = true")
	assert(board.active_tweens.size() > 0, "Navigation backward should register active tweens")
	print("History navigation backward reverse-glide animation verified.")
	
	# 9. Test PGN loading and clean reset of all pieces and FX
	if gc:
		var pgn = "1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O d6"
		gc.load_pgn(pgn)
		# Après chargement, aucun tween actif, aucun sprite fantôme et calque FX vide
		assert(board.active_tweens.size() == 0, "No active tweens after PGN load")
		assert(board.ghost_sprites.size() == 0, "No ghost sprites after PGN load")
		assert(board.fx_layer.get_child_count() == 0, "fx_layer must have 0 children after reset")
		print("PGN loaded cleanly: board visuals completely reset, zero orphaned ghosts, clean fx_layer.")
	
	board.queue_free()
	eval_bar.queue_free()
	print("ALL BOARD ANIMATION & GRAPHICS CORE CHECKS PASSED!")
	quit(0)

