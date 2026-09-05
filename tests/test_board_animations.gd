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
	
	# 2. Test square coordinate mapping
	var pos_a1 = board._get_square_screen_pos(0) # a1: rank 0, file 0 (bottom-left when not flipped)
	print("Square a1 screen pos: ", pos_a1)
	assert(pos_a1 == Vector2(0, 350), "a1 position should be (0, 350) with board_size 400 and square 50")
	
	var pos_e4 = board._get_square_screen_pos(28) # e4: rank 3, file 4
	print("Square e4 screen pos: ", pos_e4)
	assert(pos_e4 == Vector2(200, 200), "e4 position should be (200, 200)")
	
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
	board.check_pulse_timer = 1.5
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
	
	# 7. Test capture ghost animation
	var cap_move = ChessMove.new()
	cap_move.from_sq = 28 # e4
	cap_move.to_sq = 35   # d5
	cap_move.piece = ChessPiece.Type.PAWN
	cap_move.color = ChessPiece.PieceColor.WHITE
	cap_move.captured_piece = ChessPiece.Type.PAWN
	board._animate_move(cap_move)
	print("Capture ghost animation verified.")
	
	board.queue_free()
	eval_bar.queue_free()
	print("ALL BOARD ANIMATION & GRAPHICS CORE CHECKS PASSED!")
	quit(0)

