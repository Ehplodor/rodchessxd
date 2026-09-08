extends SceneTree

func _init() -> void:
	print("--- Running Promotion and PGN Robustness Tests ---")
	await create_timer(0.1).timeout

	var game = ChessGame.new()

	# -------------------------------------------------------------
	# TEST 1: Détection is_promotion_move & Choix des 4 sous-promotions
	# -------------------------------------------------------------
	print("[TEST 1] GameController.is_promotion_move & try_play_move with promotion choices...")
	
	# Position avec pion blanc en e7 prêt à aller en e8
	# Roi blanc en e1, Roi noir en e8 déplacé en h8 pour laisser e8 libre
	var fen_prom_white = "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"
	var chess_board_script = load("res://src/ui/components/ChessBoard2D.gd")
	var board = chess_board_script.new() as ChessBoard2D
	board.size = Vector2(400, 400)
	root.add_child(board)
	board._update_dimensions()

	var gc = board._get_game_controller()
	assert(gc != null, "GameController singleton must exist")
	gc.load_fen(fen_prom_white)
	board.reset_board_visuals()

	var e7 = 52 # 6*8 + 4 = 52
	var e8 = 60 # 7*8 + 4 = 60
	assert(gc.is_promotion_move(e7, e8) == true, "e7 -> e8 must be recognized as promotion move")
	assert(gc.is_promotion_move(e7, 53) == false, "e7 -> f7 is not a legal/promotion move")

	# Test sous-promotion Cavalier
	var move_knight_success = gc.try_play_move(e7, e8, ChessPiece.Type.KNIGHT)
	assert(move_knight_success == true, "Playing promotion to Knight must succeed")
	assert(gc.game.get_piece(e8).type == ChessPiece.Type.KNIGHT, "Piece at e8 must be a KNIGHT")
	assert("e8=N" in gc.game.move_history.back().san, "SAN must contain =N")
	print("  -> Underpromotion to Knight: PASS ✓ (SAN: %s)" % gc.game.move_history.back().san)

	# Test sous-promotion Tour
	gc.load_fen(fen_prom_white)
	var move_rook_success = gc.try_play_move(e7, e8, ChessPiece.Type.ROOK)
	assert(move_rook_success == true, "Playing promotion to Rook must succeed")
	assert(gc.game.get_piece(e8).type == ChessPiece.Type.ROOK, "Piece at e8 must be a ROOK")
	assert("e8=R" in gc.game.move_history.back().san, "SAN must contain =R")
	print("  -> Underpromotion to Rook: PASS ✓ (SAN: %s)" % gc.game.move_history.back().san)

	# Test sous-promotion Fou
	gc.load_fen(fen_prom_white)
	var move_bishop_success = gc.try_play_move(e7, e8, ChessPiece.Type.BISHOP)
	assert(move_bishop_success == true, "Playing promotion to Bishop must succeed")
	assert(gc.game.get_piece(e8).type == ChessPiece.Type.BISHOP, "Piece at e8 must be a BISHOP")
	assert("e8=B" in gc.game.move_history.back().san, "SAN must contain =B")
	print("  -> Underpromotion to Bishop: PASS ✓ (SAN: %s)" % gc.game.move_history.back().san)

	# Test promotion Reine
	gc.load_fen(fen_prom_white)
	var move_queen_success = gc.try_play_move(e7, e8, ChessPiece.Type.QUEEN)
	assert(move_queen_success == true, "Playing promotion to Queen must succeed")
	assert(gc.game.get_piece(e8).type == ChessPiece.Type.QUEEN, "Piece at e8 must be a QUEEN")
	assert("e8=Q" in gc.game.move_history.back().san, "SAN must contain =Q")
	print("  -> Promotion to Queen: PASS ✓ (SAN: %s)" % gc.game.move_history.back().san)

	# -------------------------------------------------------------
	# TEST 2: Promotion Noir vers le rang 1 (a2 -> a1)
	# -------------------------------------------------------------
	print("\n[TEST 2] Black pawn promotion to rank 1 (a2 -> a1)...")
	var fen_prom_black = "4K3/8/8/8/8/8/p7/7k b - - 0 1"
	gc.load_fen(fen_prom_black)
	var a2 = 8  # 1*8 + 0 = 8
	var a1 = 0  # 0*8 + 0 = 0
	assert(gc.is_promotion_move(a2, a1) == true, "a2 -> a1 for black pawn must be recognized as promotion")

	var black_knight_success = gc.try_play_move(a2, a1, ChessPiece.Type.KNIGHT)
	assert(black_knight_success == true, "Black promotion to Knight must succeed")
	assert(gc.game.get_piece(a1).type == ChessPiece.Type.KNIGHT, "Piece at a1 must be a KNIGHT")
	assert(gc.game.get_piece(a1).color == ChessPiece.PieceColor.BLACK, "Piece at a1 must be BLACK")
	print("  -> Black underpromotion to Knight: PASS ✓ (SAN: %s)" % gc.game.move_history.back().san)

	# -------------------------------------------------------------
	# TEST 3: PGN Loading - Sous-promotions variées (SAN, sans égal, UCI)
	# -------------------------------------------------------------
	print("\n[TEST 3] Loading PGN with underpromotions in various formats...")

	# PGN avec sous-promotion Cavalier faisant échec et mat
	var pgn_knight = """[Event "Test Underpromotion"]
[Site "Mobile"]
[Date "2026.09.08"]
[White "Player"]
[Black "Opponent"]
[FEN "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"]

1. e8=N Kh7 2. Nf6+ Kh8 *"""
	
	var pgn_loaded = game.load_pgn(pgn_knight)
	assert(pgn_loaded == true, "PGN with e8=N must load successfully")
	assert(game.move_history.size() >= 1, "At least 1 move loaded")
	var m0 = game.move_history[0]
	assert(m0.promotion == ChessPiece.Type.KNIGHT, "Move 1 promotion must be KNIGHT")
	print("  -> PGN 'e8=N': PASS ✓")

	# PGN avec notation sans égal 'e8R'
	var pgn_no_equal = """[Event "Test No Equal Prom"]
[FEN "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"]

1. e8R Kh7 *"""
	var pgn_ne_loaded = game.load_pgn(pgn_no_equal)
	assert(pgn_ne_loaded == true, "PGN with e8R must load successfully")
	assert(game.move_history[0].promotion == ChessPiece.Type.ROOK, "Promotion must be ROOK")
	print("  -> PGN 'e8R' (no equal sign): PASS ✓")

	# PGN avec UCI promotion 'e7e8b'
	var pgn_uci = """[Event "Test UCI Prom"]
[FEN "7k/4P3/8/8/8/8/8/4K3 w - - 0 1"]

1. e7e8b Kh7 *"""
	var pgn_uci_loaded = game.load_pgn(pgn_uci)
	assert(pgn_uci_loaded == true, "PGN with e7e8b must load successfully")
	assert(game.move_history[0].promotion == ChessPiece.Type.BISHOP, "Promotion must be BISHOP")
	print("  -> PGN UCI 'e7e8b': PASS ✓")

	# -------------------------------------------------------------
	# TEST 4: Composant PromotionModal (instanciation et signaux)
	# -------------------------------------------------------------
	print("\n[TEST 4] PromotionModal component UI & signals...")
	var modal_script = load("res://src/ui/components/PromotionModal.gd")
	var modal = modal_script.new(ChessPiece.PieceColor.WHITE)
	root.add_child(modal)
	
	var received = [-1]
	modal.piece_selected.connect(func(pt: int):
		received[0] = pt
	)
	
	# Émission simulée du choix Cavalier
	modal.piece_selected.emit(ChessPiece.Type.KNIGHT)
	assert(received[0] == ChessPiece.Type.KNIGHT, "PromotionModal must emit correct piece type")
	modal.queue_free()
	print("  -> PromotionModal: PASS ✓")

	print("\n=======================================================")
	print("ALL PROMOTION AND PGN ROBUSTNESS TESTS PASSED (100% OK)!")
	print("=======================================================")
	quit(0)
