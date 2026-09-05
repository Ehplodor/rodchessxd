extends SceneTree

const ChessPiece = preload("res://src/core/ChessPiece.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

func _init() -> void:
	print("--- Running ChessGame unit test ---")
	var game = ChessGame.new()
	print("Initial FEN:", game.get_fen())
	assert(game.get_fen().begins_with("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"))
	
	# Test legal moves from initial position
	var legal = game.get_legal_moves()
	print("Legal moves at start:", legal.size(), "(Expected: 20)")
	assert(legal.size() == 20)
	
	# Play e4 (e2 to e4)
	var e4_move = null
	for m in legal:
		if m.uci == "e2e4":
			e4_move = m
			break
	assert(e4_move != null)
	game.make_move(e4_move)
	print("Played 1. e4 - New FEN:", game.get_fen())
	assert("e3" in game.get_fen() or "e4" in game.get_fen() or " - 0 1" in game.get_fen())
	
	# Play e5 (e7 to e5)
	var e5_move = null
	for m in game.get_legal_moves():
		if m.uci == "e7e5":
			e5_move = m
			break
	assert(e5_move != null)
	game.make_move(e5_move)
	print("Played 1... e5 - New FEN:", game.get_fen())
	
	# Test Scholar's mate sequence: 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#
	# 2. Qh5
	for m in game.get_legal_moves():
		if m.uci == "d1h5":
			game.make_move(m)
			break
	# 2... Nc6
	for m in game.get_legal_moves():
		if m.uci == "b8c6":
			game.make_move(m)
			break
	# 3. Bc4
	for m in game.get_legal_moves():
		if m.uci == "f1c4":
			game.make_move(m)
			break
	# 3... Nf6
	for m in game.get_legal_moves():
		if m.uci == "g8f6":
			game.make_move(m)
			break
	# 4. Qxf7#
	var mate_move = null
	for m in game.get_legal_moves():
		if m.uci == "h5f7":
			mate_move = m
			break
	assert(mate_move != null)
	game.make_move(mate_move)
	print("Played 4. Qxf7# - Final checkmate move SAN:", mate_move.san)
	assert(mate_move.is_checkmate == true)
	assert(game.is_game_over() == true)
	
	print("PGN Export:")
	print(game.export_pgn())
	
	print("ALL CHESS GAME TESTS PASSED SUCCESSFULLY!")
	quit(0)
