class_name ChessGame
extends RefCounted
## ChessGame.gd - Moteur de règles d'échecs complet avec gestion FEN, PGN, coups légaux et historique

signal board_changed
signal move_made(move: ChessMove)
signal game_over(result: String, reason: String)

const INITIAL_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

var board: Array = [] # 64 cases (0=a1, 7=h1, 56=a8, 63=h8)
var active_color: int = ChessPiece.PieceColor.WHITE

# Droits au roque
var castle_k_white: bool = true
var castle_q_white: bool = true
var castle_k_black: bool = true
var castle_q_black: bool = true

var en_passant_sq: int = -1
var halfmove_clock: int = 0
var fullmove_number: int = 1
var white_king_sq: int = 4
var black_king_sq: int = 60

# Historique pour navigation et annulation
var move_history: Array[ChessMove] = []
var state_history: Array[Dictionary] = []
var history_index: int = -1

# Métadonnées PGN
var pgn_headers: Dictionary = {
	"Event": "RodChessXD Game",
	"Site": "Mobile",
	"Date": "????.??.??",
	"Round": "1",
	"White": "Player 1",
	"Black": "Player 2",
	"Result": "*"
}

func _init(initial_fen: String = INITIAL_FEN) -> void:
	reset_board()
	load_fen(initial_fen)

func reset_board() -> void:
	board.clear()
	board.resize(64)
	for i in range(64):
		board[i] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}
	active_color = ChessPiece.PieceColor.WHITE
	castle_k_white = true
	castle_q_white = true
	castle_k_black = true
	castle_q_black = true
	en_passant_sq = -1
	halfmove_clock = 0
	fullmove_number = 1
	white_king_sq = 4
	black_king_sq = 60
	move_history.clear()
	state_history.clear()
	history_index = -1

func get_piece(sq: int) -> Dictionary:
	if sq < 0 or sq >= 64:
		return {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}
	return board[sq]

func set_piece(sq: int, type: int, color: int) -> void:
	if sq >= 0 and sq < 64:
		board[sq] = {"type": type, "color": color}

# --- CHARGEMENT & EXPORT FEN ---

func load_fen(fen: String) -> bool:
	var parts = fen.strip_edges().split(" ")
	if parts.size() < 1:
		return false
	
	reset_board()
	var ranks = parts[0].split("/")
	if ranks.size() != 8:
		return false
	
	for r in range(8):
		var rank_idx = 7 - r # Dans le FEN, la 1re rangée est la 8e (index 7)
		var file_idx = 0
		var rank_str = ranks[r]
		for i in range(rank_str.length()):
			var c = rank_str[i]
			if c.is_valid_int():
				file_idx += c.to_int()
			else:
				var piece_info = ChessPiece.from_char(c)
				var sq = rank_idx * 8 + file_idx
				set_piece(sq, piece_info.type, piece_info.color)
				file_idx += 1

	if parts.size() > 1:
		active_color = ChessPiece.PieceColor.WHITE if parts[1] == "w" else ChessPiece.PieceColor.BLACK
	
	if parts.size() > 2:
		var c_str = parts[2]
		castle_k_white = "K" in c_str
		castle_q_white = "Q" in c_str
		castle_k_black = "k" in c_str
		castle_q_black = "q" in c_str
	
	if parts.size() > 3:
		en_passant_sq = ChessMove.coord_to_square(parts[3]) if parts[3] != "-" else -1
	
	if parts.size() > 4:
		halfmove_clock = parts[4].to_int()
	if parts.size() > 5:
		fullmove_number = parts[5].to_int()

	white_king_sq = _find_king_square(ChessPiece.PieceColor.WHITE)
	black_king_sq = _find_king_square(ChessPiece.PieceColor.BLACK)
	save_state_snapshot()
	board_changed.emit()
	return true

func get_fen() -> String:
	var fen = ""
	for r in range(7, -1, -1):
		var empty_count = 0
		for f in range(8):
			var sq = r * 8 + f
			var piece = board[sq]
			if piece.type == ChessPiece.Type.NONE:
				empty_count += 1
			else:
				if empty_count > 0:
					fen += str(empty_count)
					empty_count = 0
				fen += ChessPiece.to_char(piece.type, piece.color)
		if empty_count > 0:
			fen += str(empty_count)
		if r > 0:
			fen += "/"
	
	fen += " " + ("w" if active_color == ChessPiece.PieceColor.WHITE else "b") + " "
	
	var castling = ""
	if castle_k_white: castling += "K"
	if castle_q_white: castling += "Q"
	if castle_k_black: castling += "k"
	if castle_q_black: castling += "q"
	fen += (castling if castling != "" else "-") + " "
	
	fen += (ChessMove.square_to_coord(en_passant_sq) if en_passant_sq != -1 else "-") + " "
	fen += str(halfmove_clock) + " " + str(fullmove_number)
	return fen

# --- SNAPSHOT & GESTION D'ÉTAT ---

func save_state_snapshot() -> void:
	var packed := PackedByteArray()
	packed.resize(64)
	for i in range(64):
		var p: Dictionary = board[i]
		packed[i] = (int(p.color) << 4) | int(p.type)
	var state = {
		"packed_board": packed,
		"active_color": active_color,
		"castle_k_white": castle_k_white,
		"castle_q_white": castle_q_white,
		"castle_k_black": castle_k_black,
		"castle_q_black": castle_q_black,
		"en_passant_sq": en_passant_sq,
		"halfmove_clock": halfmove_clock,
		"fullmove_number": fullmove_number,
		"white_king_sq": white_king_sq,
		"black_king_sq": black_king_sq
	}
	state_history.append(state)
	history_index = state_history.size() - 1

func restore_state(index: int) -> bool:
	if index < 0 or index >= state_history.size():
		return false
	var state = state_history[index]
	if state.has("packed_board"):
		var packed: PackedByteArray = state["packed_board"]
		for i in range(64):
			var b = packed[i]
			board[i]["color"] = b >> 4
			board[i]["type"] = b & 0x0F
	elif state.has("board"):
		board = state["board"].duplicate(true)
	active_color = state["active_color"]
	castle_k_white = state["castle_k_white"]
	castle_q_white = state["castle_q_white"]
	castle_k_black = state["castle_k_black"]
	castle_q_black = state["castle_q_black"]
	en_passant_sq = state["en_passant_sq"]
	halfmove_clock = state["halfmove_clock"]
	fullmove_number = state["fullmove_number"]
	white_king_sq = state.get("white_king_sq", _find_king_square(ChessPiece.PieceColor.WHITE))
	black_king_sq = state.get("black_king_sq", _find_king_square(ChessPiece.PieceColor.BLACK))
	history_index = index
	board_changed.emit()
	return true

# --- GÉNÉRATION DES COUPS LÉGAUX ---

func get_legal_moves(for_color: int = -1) -> Array[ChessMove]:
	if for_color == -1:
		for_color = active_color
	var pseudo_moves = _generate_pseudo_legal_moves(for_color)
	var legal_moves: Array[ChessMove] = []
	for m in pseudo_moves:
		if _is_move_legal(m, for_color):
			_annotate_move(m)
			legal_moves.append(m)
	return legal_moves

func get_legal_moves_for_square(sq: int) -> Array[ChessMove]:
	var result: Array[ChessMove] = []
	var piece = get_piece(sq)
	if piece.color != active_color:
		return result
	for m in get_legal_moves(active_color):
		if m.from_sq == sq:
			result.append(m)
	return result

func _generate_pseudo_legal_moves(color: int) -> Array[ChessMove]:
	var moves: Array[ChessMove] = []
	for sq in range(64):
		var piece = board[sq]
		if piece.color != color:
			continue
		match piece.type:
			ChessPiece.Type.PAWN:
				_gen_pawn_moves(sq, color, moves)
			ChessPiece.Type.KNIGHT:
				_gen_knight_moves(sq, color, moves)
			ChessPiece.Type.BISHOP:
				_gen_sliding_moves(sq, color, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)], moves)
			ChessPiece.Type.ROOK:
				_gen_sliding_moves(sq, color, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], moves)
			ChessPiece.Type.QUEEN:
				_gen_sliding_moves(sq, color, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], moves)
			ChessPiece.Type.KING:
				_gen_king_moves(sq, color, moves)
	return moves

func _gen_pawn_moves(sq: int, color: int, moves: Array[ChessMove]) -> void:
	var f = sq % 8
	var r = sq / 8
	var dir = 1 if color == ChessPiece.PieceColor.WHITE else -1
	var start_rank = 1 if color == ChessPiece.PieceColor.WHITE else 6
	var prom_rank = 7 if color == ChessPiece.PieceColor.WHITE else 0
	
	# Avance simple
	var next_r = r + dir
	if next_r >= 0 and next_r <= 7:
		var target_sq = next_r * 8 + f
		if board[target_sq].type == ChessPiece.Type.NONE:
			if next_r == prom_rank:
				for prom in [ChessPiece.Type.QUEEN, ChessPiece.Type.ROOK, ChessPiece.Type.BISHOP, ChessPiece.Type.KNIGHT]:
					var m = ChessMove.new(sq, target_sq, ChessPiece.Type.PAWN, color)
					m.promotion = prom
					moves.append(m)
			else:
				moves.append(ChessMove.new(sq, target_sq, ChessPiece.Type.PAWN, color))
			
			# Avance double depuis rangée de départ
			if r == start_rank:
				var double_sq = (r + dir * 2) * 8 + f
				if board[double_sq].type == ChessPiece.Type.NONE:
					moves.append(ChessMove.new(sq, double_sq, ChessPiece.Type.PAWN, color))
	
	# Prises en diagonale
	for df in [-1, 1]:
		var target_f = f + df
		if target_f >= 0 and target_f <= 7 and next_r >= 0 and next_r <= 7:
			var target_sq = next_r * 8 + target_f
			var target_piece = board[target_sq]
			if target_piece.type != ChessPiece.Type.NONE and target_piece.color != color:
				if next_r == prom_rank:
					for prom in [ChessPiece.Type.QUEEN, ChessPiece.Type.ROOK, ChessPiece.Type.BISHOP, ChessPiece.Type.KNIGHT]:
						var m = ChessMove.new(sq, target_sq, ChessPiece.Type.PAWN, color)
						m.captured_piece = target_piece.type
						m.promotion = prom
						moves.append(m)
				else:
					var m = ChessMove.new(sq, target_sq, ChessPiece.Type.PAWN, color)
					m.captured_piece = target_piece.type
					moves.append(m)
			elif target_sq == en_passant_sq: # Prise en passant
				var m = ChessMove.new(sq, target_sq, ChessPiece.Type.PAWN, color)
				m.is_en_passant = true
				m.captured_piece = ChessPiece.Type.PAWN
				moves.append(m)

func _gen_knight_moves(sq: int, color: int, moves: Array[ChessMove]) -> void:
	var f = sq % 8
	var r = sq / 8
	var deltas = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
	]
	for d in deltas:
		var nf = f + d.x
		var nr = r + d.y
		if nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7:
			var tsq = nr * 8 + nf
			var tpiece = board[tsq]
			if tpiece.type == ChessPiece.Type.NONE or tpiece.color != color:
				var m = ChessMove.new(sq, tsq, ChessPiece.Type.KNIGHT, color)
				m.captured_piece = tpiece.type
				moves.append(m)

func _gen_sliding_moves(sq: int, color: int, dirs: Array[Vector2i], moves: Array[ChessMove]) -> void:
	var f = sq % 8
	var r = sq / 8
	var piece_type = board[sq].type
	for d in dirs:
		var cur_f = f + d.x
		var cur_r = r + d.y
		while cur_f >= 0 and cur_f <= 7 and cur_r >= 0 and cur_r <= 7:
			var tsq = cur_r * 8 + cur_f
			var tpiece = board[tsq]
			if tpiece.type == ChessPiece.Type.NONE:
				moves.append(ChessMove.new(sq, tsq, piece_type, color))
			else:
				if tpiece.color != color:
					var m = ChessMove.new(sq, tsq, piece_type, color)
					m.captured_piece = tpiece.type
					moves.append(m)
				break
			cur_f += d.x
			cur_r += d.y

func _gen_king_moves(sq: int, color: int, moves: Array[ChessMove]) -> void:
	var f = sq % 8
	var r = sq / 8
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0:
				continue
			var nf = f + df
			var nr = r + dr
			if nf >= 0 and nf <= 7 and nr >= 0 and nr <= 7:
				var tsq = nr * 8 + nf
				var tpiece = board[tsq]
				if tpiece.type == ChessPiece.Type.NONE or tpiece.color != color:
					var m = ChessMove.new(sq, tsq, ChessPiece.Type.KING, color)
					m.captured_piece = tpiece.type
					moves.append(m)
	
	# Roque (Castling)
	if not is_in_check(color):
		var base_rank = 0 if color == ChessPiece.PieceColor.WHITE else 7
		if r == base_rank and f == 4:
			# Petit roque (Kingside)
			var can_k = castle_k_white if color == ChessPiece.PieceColor.WHITE else castle_k_black
			if can_k and board[base_rank * 8 + 5].type == ChessPiece.Type.NONE and board[base_rank * 8 + 6].type == ChessPiece.Type.NONE:
				if not is_square_attacked(base_rank * 8 + 5, 1 - color) and not is_square_attacked(base_rank * 8 + 6, 1 - color):
					var m = ChessMove.new(sq, base_rank * 8 + 6, ChessPiece.Type.KING, color)
					m.is_castling = true
					moves.append(m)
			
			# Grand roque (Queenside)
			var can_q = castle_q_white if color == ChessPiece.PieceColor.WHITE else castle_q_black
			if can_q and board[base_rank * 8 + 1].type == ChessPiece.Type.NONE and board[base_rank * 8 + 2].type == ChessPiece.Type.NONE and board[base_rank * 8 + 3].type == ChessPiece.Type.NONE:
				if not is_square_attacked(base_rank * 8 + 3, 1 - color) and not is_square_attacked(base_rank * 8 + 2, 1 - color):
					var m = ChessMove.new(sq, base_rank * 8 + 2, ChessPiece.Type.KING, color)
					m.is_castling = true
					moves.append(m)

func is_square_attacked(sq: int, by_color: int) -> bool:
	var f = sq % 8
	var r = sq / 8
	
	# Attaque par pion
	var pawn_dir = 1 if by_color == ChessPiece.PieceColor.WHITE else -1
	var pawn_r = r - pawn_dir
	if pawn_r >= 0 and pawn_r <= 7:
		for df in [-1, 1]:
			var pf = f + df
			if pf >= 0 and pf <= 7:
				var psq = pawn_r * 8 + pf
				var p = board[psq]
				if p.type == ChessPiece.Type.PAWN and p.color == by_color:
					return true

	# Attaque par cavalier
	var knight_deltas = [
		Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
		Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)
	]
	for d in knight_deltas:
		var kf = f + d.x
		var kr = r + d.y
		if kf >= 0 and kf <= 7 and kr >= 0 and kr <= 7:
			var p = board[kr * 8 + kf]
			if p.type == ChessPiece.Type.KNIGHT and p.color == by_color:
				return true

	# Attaque diagonale (Fou / Dame)
	for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var cf = f + d.x
		var cr = r + d.y
		while cf >= 0 and cf <= 7 and cr >= 0 and cr <= 7:
			var p = board[cr * 8 + cf]
			if p.type != ChessPiece.Type.NONE:
				if p.color == by_color and (p.type == ChessPiece.Type.BISHOP or p.type == ChessPiece.Type.QUEEN):
					return true
				break
			cf += d.x
			cr += d.y

	# Attaque orthogonale (Tour / Dame)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cf = f + d.x
		var cr = r + d.y
		while cf >= 0 and cf <= 7 and cr >= 0 and cr <= 7:
			var p = board[cr * 8 + cf]
			if p.type != ChessPiece.Type.NONE:
				if p.color == by_color and (p.type == ChessPiece.Type.ROOK or p.type == ChessPiece.Type.QUEEN):
					return true
				break
			cf += d.x
			cr += d.y

	# Attaque par Roi
	for df in [-1, 0, 1]:
		for dr in [-1, 0, 1]:
			if df == 0 and dr == 0: continue
			var kf = f + df
			var kr = r + dr
			if kf >= 0 and kf <= 7 and kr >= 0 and kr <= 7:
				var p = board[kr * 8 + kf]
				if p.type == ChessPiece.Type.KING and p.color == by_color:
					return true

	return false

func _find_king_square(color: int) -> int:
	for i in range(64):
		var p: Dictionary = board[i]
		if p.type == ChessPiece.Type.KING and p.color == color:
			return i
	return -1

func is_in_check(color: int) -> bool:
	var king_sq = white_king_sq if color == ChessPiece.PieceColor.WHITE else black_king_sq
	if king_sq < 0 or king_sq >= 64 or board[king_sq].type != ChessPiece.Type.KING or board[king_sq].color != color:
		king_sq = _find_king_square(color)
		if color == ChessPiece.PieceColor.WHITE:
			white_king_sq = king_sq
		else:
			black_king_sq = king_sq
	if king_sq == -1:
		return false
	return is_square_attacked(king_sq, 1 - color)

func _is_move_legal(move: ChessMove, color: int) -> bool:
	# Simulation du coup
	var orig_from = board[move.from_sq]
	var orig_to = board[move.to_sq]
	var orig_ep_pawn = null
	var ep_captured_sq = -1
	
	var saved_king_sq = white_king_sq if color == ChessPiece.PieceColor.WHITE else black_king_sq
	if move.piece == ChessPiece.Type.KING:
		if color == ChessPiece.PieceColor.WHITE:
			white_king_sq = move.to_sq
		else:
			black_king_sq = move.to_sq

	board[move.to_sq] = orig_from
	board[move.from_sq] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}
	
	if move.is_en_passant:
		var dir = 1 if color == ChessPiece.PieceColor.WHITE else -1
		ep_captured_sq = move.to_sq - (dir * 8)
		orig_ep_pawn = board[ep_captured_sq]
		board[ep_captured_sq] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	var in_check = is_in_check(color)

	# Restauration
	board[move.from_sq] = orig_from
	board[move.to_sq] = orig_to
	if move.is_en_passant and ep_captured_sq != -1:
		board[ep_captured_sq] = orig_ep_pawn
	if move.piece == ChessPiece.Type.KING:
		if color == ChessPiece.PieceColor.WHITE:
			white_king_sq = saved_king_sq
		else:
			black_king_sq = saved_king_sq

	return not in_check

## Sortie précoce O(1) : vrai dès qu'au moins UN coup légal existe.
## Évite la génération complète de tous les coups pseudo-légaux et leurs calculs de SAN.
func has_any_legal_move(for_color: int = -1) -> bool:
	if for_color == -1:
		for_color = active_color
	for sq in range(64):
		var piece: Dictionary = board[sq]
		if piece.color != for_color:
			continue
		var moves: Array[ChessMove] = []
		match piece.type:
			ChessPiece.Type.PAWN:
				_gen_pawn_moves(sq, for_color, moves)
			ChessPiece.Type.KNIGHT:
				_gen_knight_moves(sq, for_color, moves)
			ChessPiece.Type.BISHOP:
				_gen_sliding_moves(sq, for_color, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)], moves)
			ChessPiece.Type.ROOK:
				_gen_sliding_moves(sq, for_color, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], moves)
			ChessPiece.Type.QUEEN:
				_gen_sliding_moves(sq, for_color, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)], moves)
			ChessPiece.Type.KING:
				_gen_king_moves(sq, for_color, moves)
		for m in moves:
			if _is_move_legal(m, for_color):
				return true
	return false

func _annotate_move(m: ChessMove) -> void:
	if m.is_castling:
		m.san = "O-O" if (m.to_sq % 8 == 6) else "O-O-O"
		return
	
	var res = ""
	if m.piece != ChessPiece.Type.PAWN:
		res += ChessPiece.SYMBOLS_WHITE[m.piece]
	
	if m.captured_piece != ChessPiece.Type.NONE or m.is_en_passant:
		if m.piece == ChessPiece.Type.PAWN:
			res += ChessMove.square_to_coord(m.from_sq)[0]
		res += "x"
	
	res += ChessMove.square_to_coord(m.to_sq)
	
	if m.promotion != ChessPiece.Type.NONE:
		res += "=" + ChessPiece.SYMBOLS_WHITE[m.promotion]
	
	m.san = res

# --- EXÉCUTION D'UN COUP ---

func make_move(move: ChessMove) -> bool:
	var piece = board[move.from_sq]
	if piece.type == ChessPiece.Type.NONE or piece.color != active_color:
		return false

	# Exécution sur le plateau
	board[move.to_sq] = piece
	board[move.from_sq] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	# Gestion promotion
	if move.promotion != ChessPiece.Type.NONE:
		board[move.to_sq].type = move.promotion

	# Gestion en passant
	if move.is_en_passant:
		var dir = 1 if active_color == ChessPiece.PieceColor.WHITE else -1
		var ep_sq = move.to_sq - (dir * 8)
		board[ep_sq] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	# Gestion roque (déplacement de la tour)
	if move.is_castling:
		var base_rank = 0 if active_color == ChessPiece.PieceColor.WHITE else 7
		if move.to_sq % 8 == 6: # Petit roque
			board[base_rank * 8 + 5] = board[base_rank * 8 + 7]
			board[base_rank * 8 + 7] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}
		elif move.to_sq % 8 == 2: # Grand roque
			board[base_rank * 8 + 3] = board[base_rank * 8 + 0]
			board[base_rank * 8 + 0] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	# Mise à jour des droits au roque et position des rois
	if piece.type == ChessPiece.Type.KING:
		if active_color == ChessPiece.PieceColor.WHITE:
			white_king_sq = move.to_sq
			castle_k_white = false
			castle_q_white = false
		else:
			black_king_sq = move.to_sq
			castle_k_black = false
			castle_q_black = false
	elif piece.type == ChessPiece.Type.ROOK:
		if move.from_sq == 0: castle_q_white = false
		elif move.from_sq == 7: castle_k_white = false
		elif move.from_sq == 56: castle_q_black = false
		elif move.from_sq == 63: castle_k_black = false

	# En passant target
	if piece.type == ChessPiece.Type.PAWN and abs(move.to_sq - move.from_sq) == 16:
		var dir = 1 if active_color == ChessPiece.PieceColor.WHITE else -1
		en_passant_sq = move.from_sq + (dir * 8)
	else:
		en_passant_sq = -1

	# Demi-coups (règle des 50 coups)
	if piece.type == ChessPiece.Type.PAWN or move.captured_piece != ChessPiece.Type.NONE:
		halfmove_clock = 0
	else:
		halfmove_clock += 1

	if active_color == ChessPiece.PieceColor.BLACK:
		fullmove_number += 1

	# Changement de joueur
	active_color = 1 - active_color
	
	# Échec / Mat ? (sortie précoce O(1) via has_any_legal_move)
	var opp_in_check = is_in_check(active_color)
	var opp_has_moves = has_any_legal_move(active_color)
	if opp_in_check:
		if not opp_has_moves:
			move.is_checkmate = true
			if not move.san.ends_with("#"):
				move.san += "#"
		else:
			move.is_check = true
			if not move.san.ends_with("+") and not move.san.ends_with("#"):
				move.san += "+"

	# Historique : si on joue un coup depuis une position antérieure (variante), tronquer proprement
	if history_index < state_history.size() - 1:
		move_history = move_history.slice(0, history_index)
		state_history = state_history.slice(0, history_index + 1)
	
	move_history.append(move)
	save_state_snapshot()
	
	move_made.emit(move)
	board_changed.emit()

	if not opp_has_moves:
		if opp_in_check:
			var winner = "Blancs" if active_color == ChessPiece.PieceColor.BLACK else "Noirs"
			game_over.emit(winner + " gagnent", "Échec et mat")
		else:
			game_over.emit("Partie nulle", "Pat")

	return true

func is_game_over() -> bool:
	return not has_any_legal_move(active_color)

# --- PARSING PGN ---

func load_pgn(pgn: String) -> bool:
	reset_board()
	var lines = pgn.split("\n")
	var move_text = ""
	
	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.begins_with("[") and trimmed.ends_with("]"):
			var content = trimmed.substr(1, trimmed.length() - 2)
			var space_idx = content.find(" ")
			if space_idx != -1:
				var key = content.substr(0, space_idx)
				var val = content.substr(space_idx + 1).replace('"', '')
				pgn_headers[key] = val
		else:
			move_text += " " + trimmed
	
	# Initialiser le plateau avec la position initiale (ou le tag FEN si présent)
	if pgn_headers.has("FEN"):
		load_fen(pgn_headers["FEN"])
	else:
		load_fen(INITIAL_FEN)

	_apply_pgn_moves(move_text)

	board_changed.emit()
	return true

## Vrai dès qu'un token de résultat PGN a été rencontré (arrête l'application des coups).
var _pgn_result_seen: bool = false

## T2.4 — Applique les coups d'un texte PGN en capturant les annotations d'horloge
## `{[%clk H:MM:SS]}` attachées au coup précédent. Ignore commentaires et variantes.
func _apply_pgn_moves(text: String) -> void:
	_pgn_result_seen = false
	var i := 0
	var n := text.length()
	var buf := ""
	while i < n:
		var c := text[i]
		if c == "{":
			_flush_pgn_token(buf)
			buf = ""
			var end := text.find("}", i)
			if end == -1:
				end = n - 1
			_apply_clock_comment(text.substr(i, end - i + 1))
			i = end + 1
			continue
		if c == "(":
			_flush_pgn_token(buf)
			buf = ""
			var depth := 1
			i += 1
			while i < n and depth > 0:
				if text[i] == "(":
					depth += 1
				elif text[i] == ")":
					depth -= 1
				i += 1
			continue
		if c == " " or c == "\n" or c == "\t" or c == "\r":
			_flush_pgn_token(buf)
			buf = ""
			i += 1
			continue
		buf += c
		i += 1
	_flush_pgn_token(buf)

func _flush_pgn_token(raw: String) -> void:
	# Régression corrigée : ne plus appliquer de coups après le token de résultat
	# (un PGN multi-parties verrait sinon la 2e partie se superposer à la 1re).
	# Le résultat est testé AVANT `_clean_pgn_token`, qui amputerait « 1-0 » en « -0 ».
	if _pgn_result_seen:
		return
	var raw_tok := raw.strip_edges()
	if raw_tok in ["1-0", "0-1", "1/2-1/2", "*"]:
		pgn_headers["Result"] = raw_tok
		_pgn_result_seen = true
		return
	var token := _clean_pgn_token(raw_tok)
	if token == "":
		return
	if token.begins_with("$") or token.begins_with(";"):
		return
	var found_move := _find_matching_move(token)
	if found_move:
		make_move(found_move)

func _clean_pgn_token(raw: String) -> String:
	var tok := raw.strip_edges()
	while tok.length() > 0 and (tok[0].is_valid_int() or tok[0] == '.'):
		tok = tok.substr(1)
	tok = tok.replace("+", "").replace("#", "").replace("!", "").replace("?", "")
	return tok

## Extrait le temps restant d'un commentaire `{[%clk 0:05:30]}` et l'attache au dernier coup.
func _apply_clock_comment(comment: String) -> void:
	var idx := comment.find("%clk")
	if idx == -1 or move_history.is_empty():
		return
	var rest := comment.substr(idx + 4).strip_edges()
	var end := rest.find("]")
	if end != -1:
		rest = rest.substr(0, end)
	rest = rest.strip_edges()
	if rest == "":
		return
	var parts := rest.split(":")
	var seconds := 0.0
	if parts.size() == 3:
		seconds = float(parts[0].to_int()) * 3600.0 + float(parts[1].to_int()) * 60.0 + float(parts[2].to_float())
	elif parts.size() == 2:
		seconds = float(parts[0].to_int()) * 60.0 + float(parts[1].to_float())
	else:
		seconds = float(rest.to_float())
	move_history[move_history.size() - 1].clock_sec = seconds

func _find_matching_move(token: String) -> ChessMove:
	var legal = get_legal_moves(active_color)
	
	# 1. Correspondance exacte SAN ou UCI (avec ou sans promotion)
	for m in legal:
		var clean_san = m.san.replace("+", "").replace("#", "")
		if clean_san == token or m.uci == token:
			return m

	# Correspondance UCI directe (ex: e2e4, c3e3, e7e8q)
	if token.length() >= 4:
		var uci_from = ChessMove.coord_to_square(token.substr(0, 2))
		var uci_to = ChessMove.coord_to_square(token.substr(2, 2))
		if uci_from != -1 and uci_to != -1:
			var prom_char = token.substr(4, 1).to_lower() if token.length() >= 5 else ""
			for m in legal:
				if m.from_sq == uci_from and m.to_sq == uci_to:
					if prom_char != "":
						var prom_type = ChessPiece.Type.QUEEN
						match prom_char:
							"q": prom_type = ChessPiece.Type.QUEEN
							"r": prom_type = ChessPiece.Type.ROOK
							"b": prom_type = ChessPiece.Type.BISHOP
							"n": prom_type = ChessPiece.Type.KNIGHT
						if m.promotion == prom_type:
							return m
					else:
						return m

	# 2. Roque
	if token in ["O-O", "0-0"]:
		for m in legal:
			if m.is_castling and (m.to_sq % 8 == 6):
				return m
	elif token in ["O-O-O", "0-0-0"]:
		for m in legal:
			if m.is_castling and (m.to_sq % 8 == 2):
				return m

	# 3. Parsing sémantique du coup SAN avec gestion des désambiguïsations
	# ex: R4f2, Rad1, Nbd7, exd5, e8=Q, f8Q, e8=N, etc.
	var clean = token.replace("x", "")
	var expected_prom = ChessPiece.Type.NONE
	if "=" in clean:
		var eq_idx = clean.find("=")
		if eq_idx < clean.length() - 1:
			var prom_char = clean.substr(eq_idx + 1, 1).to_upper()
			match prom_char:
				"Q": expected_prom = ChessPiece.Type.QUEEN
				"R": expected_prom = ChessPiece.Type.ROOK
				"B": expected_prom = ChessPiece.Type.BISHOP
				"N": expected_prom = ChessPiece.Type.KNIGHT
		clean = clean.replace("=", "")

	if clean.length() < 2:
		return null

	var dest_coord = clean.substr(clean.length() - 2, 2)
	var dest_sq = ChessMove.coord_to_square(dest_coord)
	if dest_sq == -1:
		# Promotion sans égal : ex "h1Q" -> dest "h1", prom "Q"
		if clean.length() >= 3 and clean[-1].to_upper() in ["Q", "R", "B", "N"]:
			var prom_char = clean[-1].to_upper()
			match prom_char:
				"Q": expected_prom = ChessPiece.Type.QUEEN
				"R": expected_prom = ChessPiece.Type.ROOK
				"B": expected_prom = ChessPiece.Type.BISHOP
				"N": expected_prom = ChessPiece.Type.KNIGHT
			dest_coord = clean.substr(clean.length() - 3, 2)
			dest_sq = ChessMove.coord_to_square(dest_coord)
			clean = clean.substr(0, clean.length() - 1)

	if dest_sq == -1:
		return null

	var piece_type = ChessPiece.Type.PAWN
	var start_idx = 0
	if clean[0] in ["N", "B", "R", "Q", "K"]:
		piece_type = ChessPiece.from_char(clean[0]).type
		start_idx = 1

	var disambig_hint = clean.substr(start_idx, clean.length() - start_idx - 2)

	for m in legal:
		if m.to_sq == dest_sq and m.piece == piece_type:
			if expected_prom != ChessPiece.Type.NONE and m.promotion != expected_prom:
				continue
			if disambig_hint == "":
				return m
			var from_coord = ChessMove.square_to_coord(m.from_sq)
			if disambig_hint.length() == 1:
				if disambig_hint[0] == from_coord[0] or disambig_hint[0] == from_coord[1]:
					return m
			elif disambig_hint == from_coord:
				return m

	return null

## Export PGN. `include_annotations` ajoute les NAG de qualité, les commentaires du
## coach/du joueur et les annotations d'horloge (T2.2), compatibles Lichess/Chess.com.
func export_pgn(include_annotations: bool = false) -> String:
	var pgn = ""
	for k in pgn_headers.keys():
		pgn += '[%s "%s"]\n' % [k, pgn_headers[k]]
	pgn += "\n"

	for i in range(move_history.size()):
		var m := move_history[i]
		if i % 2 == 0:
			pgn += str((i / 2) + 1) + ". "
		pgn += m.san
		if include_annotations:
			var nag := quality_nag(m.quality)
			if nag != "":
				pgn += " " + nag
			var comment := m.coach_explanation.strip_edges()
			if m.clock_sec >= 0.0:
				var clk := _format_clock_annotation(m.clock_sec)
				comment = ("%s [%%clk %s]" % [comment, clk]) if comment != "" else ("[%%clk %s]" % clk)
			if comment != "":
				pgn += " {%s}" % comment
		pgn += " "

	pgn += pgn_headers.get("Result", "*")
	return pgn

## NAG standard pour une qualité de coup.
static func quality_nag(q: int) -> String:
	match q:
		ChessMove.Quality.BRILLIANT: return "$3"
		ChessMove.Quality.GREAT: return "$1"
		ChessMove.Quality.INACCURACY: return "$6"
		ChessMove.Quality.MISTAKE: return "$2"
		ChessMove.Quality.BLUNDER: return "$4"
		ChessMove.Quality.MISS: return "$4"
		_: return ""

static func _format_clock_annotation(total_sec: float) -> String:
	var s := int(maxf(0.0, total_sec))
	return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]

# --- INTERPRÉTATION ALGORITHMIQUE NATURELLE DES COUPS & ACTIONS ÉCHIQUÉENNES ---

## Recherche un coup légal à partir d'une chaîne SAN ou UCI (ex: "Nf3", "c3e3", "O-O", "e7e8q")
func find_move(token: String) -> ChessMove:
	return _find_matching_move(token.strip_edges())

## Nom français de base d'une pièce
static func get_piece_name_fr(type: int) -> String:
	match type:
		ChessPiece.Type.PAWN: return "Pion"
		ChessPiece.Type.KNIGHT: return "Cavalier"
		ChessPiece.Type.BISHOP: return "Fou"
		ChessPiece.Type.ROOK: return "Tour"
		ChessPiece.Type.QUEEN: return "Dame"
		ChessPiece.Type.KING: return "Roi"
	return "Pièce"

## Indique si le nom de la pièce est féminin en français (Tour, Dame)
static func is_piece_feminine(type: int) -> bool:
	return (type == ChessPiece.Type.ROOK or type == ChessPiece.Type.QUEEN)

## Retourne le nom qualifié avec couleur et article optionnel
## ex: "Dame blanche", "la Tour noire", "le Cavalier blanc"
static func get_colored_piece_name_fr(type: int, color: int, with_article: bool = false) -> String:
	var name = get_piece_name_fr(type)
	var is_fem = is_piece_feminine(type)
	var col_adj = ""
	var article = ""
	
	if color == ChessPiece.PieceColor.WHITE:
		col_adj = "blanche" if is_fem else "blanc"
		article = "la " if is_fem else "le "
	else:
		col_adj = "noire" if is_fem else "noir"
		article = "la " if is_fem else "le "
	
	if with_article:
		return article + name + " " + col_adj
	else:
		return name + " " + col_adj

## Traduit un coup en action humaine parfaitement explicite sans ambiguïté
## ex: "Dame blanche en c3 prend la Tour noire en e3", "Petit roque des Blancs"
func describe_move_natural(move: ChessMove) -> String:
	if not move:
		return ""

	var col_name = "Blancs" if move.color == ChessPiece.PieceColor.WHITE else "Noirs"
	var col_adj = "blanc" if move.color == ChessPiece.PieceColor.WHITE else "noir"
	var opp_col_adj = "noir" if move.color == ChessPiece.PieceColor.WHITE else "blanc"
	var from_c = ChessMove.square_to_coord(move.from_sq)
	var to_c = ChessMove.square_to_coord(move.to_sq)

	# 1. Roque
	if move.is_castling:
		if move.to_sq % 8 == 6:
			var k_sq = "g1" if move.color == ChessPiece.PieceColor.WHITE else "g8"
			var r_sq = "f1" if move.color == ChessPiece.PieceColor.WHITE else "f8"
			return "Petit roque des %s (Roi en %s, Tour en %s)" % [col_name, k_sq, r_sq]
		else:
			var k_sq = "c1" if move.color == ChessPiece.PieceColor.WHITE else "c8"
			var r_sq = "d1" if move.color == ChessPiece.PieceColor.WHITE else "d8"
			return "Grand roque des %s (Roi en %s, Tour en %s)" % [col_name, k_sq, r_sq]

	# 2. Prise en passant
	if move.is_en_passant:
		var dir = 1 if move.color == ChessPiece.PieceColor.WHITE else -1
		var cap_sq_c = ChessMove.square_to_coord(move.to_sq - (dir * 8))
		return "Pion %s en %s prend en passant le Pion %s en %s (arrive en %s)" % [col_adj, from_c, opp_col_adj, cap_sq_c, to_c]

	# 3. Promotion
	if move.promotion != ChessPiece.Type.NONE:
		var prom_str = get_piece_name_fr(move.promotion)
		var base_str = ""
		if move.captured_piece != ChessPiece.Type.NONE:
			var opp_piece = get_colored_piece_name_fr(move.captured_piece, 1 - move.color, true)
			base_str = "Pion %s en %s prend %s en %s et est promu en %s" % [col_adj, from_c, opp_piece, to_c, prom_str]
		else:
			base_str = "Pion %s en %s avance en %s et est promu en %s" % [col_adj, from_c, to_c, prom_str]
		
		if move.is_checkmate: base_str += " (# Échec et mat !)"
		elif move.is_check: base_str += " (+ Échec au Roi)"
		return base_str

	# 4. Prise classique
	if move.captured_piece != ChessPiece.Type.NONE:
		var attacker = get_colored_piece_name_fr(move.piece, move.color, false)
		var victim = get_colored_piece_name_fr(move.captured_piece, 1 - move.color, true)
		var text = "%s en %s prend %s en %s" % [attacker, from_c, victim, to_c]
		if move.is_checkmate: text += " (# Échec et mat !)"
		elif move.is_check: text += " (+ Échec au Roi)"
		return text

	# 5. Déplacement sans prise
	if move.piece == ChessPiece.Type.PAWN:
		var text = "Pion %s avance de %s en %s" % [col_adj, from_c, to_c]
		if move.is_checkmate: text += " (# Échec et mat !)"
		elif move.is_check: text += " (+ Échec au Roi)"
		return text
	else:
		var piece_str = get_colored_piece_name_fr(move.piece, move.color, false)
		var text = "%s se déplace de %s en %s" % [piece_str, from_c, to_c]
		if move.is_checkmate: text += " (# Échec et mat !)"
		elif move.is_check: text += " (+ Échec au Roi)"
		return text

## Décrit en langage naturel clair un coup à partir d'un FEN (sans LLM)
static func describe_move_from_fen(fen: String, move_str: String) -> String:
	if move_str == "":
		return ""
	var game = ChessGame.new(fen)
	var m = game.find_move(move_str)
	if m:
		return game.describe_move_natural(m)
	return move_str

## Décode séquentiellement la variante PV de Stockfish coup par coup en français naturel
static func format_pv_natural_text(fen: String, pv_moves: Array, max_moves: int = 5) -> String:
	if pv_moves.is_empty():
		return "Aucune variante calculée."

	var sim_game = ChessGame.new(fen)
	var lines: PackedStringArray = []
	var count = mini(pv_moves.size(), max_moves)

	for i in range(count):
		var token = str(pv_moves[i]).strip_edges()
		if token == "":
			continue
		var m = sim_game.find_move(token)
		if not m:
			lines.append("  %d. %s" % [i + 1, token])
			continue

		var icon = "⚪" if m.color == ChessPiece.PieceColor.WHITE else "⚫"
		var col_name = "Blancs" if m.color == ChessPiece.PieceColor.WHITE else "Noirs"
		var desc = sim_game.describe_move_natural(m)
		lines.append("  %d. %s %s : %s (%s)" % [i + 1, icon, col_name, desc, m.san])
		sim_game.make_move(m)

	return "\n".join(lines)

## Convertit une notation algébrique SAN internationale (K, Q, R, B, N) en notation française officielle (R, D, T, F, C).
static func san_to_french(san: String) -> String:
	if san == "" or san.begins_with("O-O"):
		return san
	var out := ""
	var i := 0
	var len_s := san.length()
	while i < len_s:
		var ch := san[i]
		if i == 0 and ch in ["K", "Q", "R", "B", "N"]:
			match ch:
				"K": out += "R"
				"Q": out += "D"
				"R": out += "T"
				"B": out += "F"
				"N": out += "C"
		elif ch == "=" and i + 1 < len_s:
			out += "="
			i += 1
			var prom_ch := san[i]
			match prom_ch:
				"Q": out += "D"
				"R": out += "T"
				"B": out += "F"
				"N": out += "C"
				_: out += prom_ch
		else:
			out += ch
		i += 1
	return out
