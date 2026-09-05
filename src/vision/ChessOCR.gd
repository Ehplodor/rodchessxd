class_name ChessOCR
extends RefCounted
## ChessOCR.gd - Détection et reconnaissance de positions d'échecs à partir d'une image PNG

signal ocr_completed(fen: String, confidence: float)
signal ocr_error(error_msg: String)

static func load_image(filepath: String) -> Image:
	var img = Image.new()
	var err = img.load(filepath)
	if err != OK:
		return null
	return img

## Détecte le rectangle englobant de l'échiquier 8x8 dans l'image
static func detect_board_rect(img: Image) -> Rect2i:
	var w = img.get_width()
	var h = img.get_height()
	
	# Dans une capture d'écran mobile standard (ex. Chess.com / Lichess),
	# l'échiquier est un carré centré occupant généralement toute la largeur ou une grande partie centrale.
	if abs(w - h) < 10:
		# Image déjà recadrée sur l'échiquier
		return Rect2i(0, 0, w, h)
	elif w < h:
		# Mode portrait : l'échiquier a souvent une largeur égale à w et est centré verticalement
		var side = w
		var start_y = (h - side) / 2
		return Rect2i(0, start_y, side, side)
	else:
		# Mode paysage : l'échiquier a une hauteur égale à h et est centré horizontalement
		var side = h
		var start_x = (w - side) / 2
		return Rect2i(start_x, 0, side, side)

## Analyse les 64 cases d'un échiquier et génère un FEN
static func recognize_board_fen(img: Image, board_rect: Rect2i, white_at_bottom: bool = true) -> String:
	var square_w = board_rect.size.x / 8
	var square_h = board_rect.size.y / 8
	
	var board_state: Array = []
	board_state.resize(64)
	for i in range(64):
		board_state[i] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	for r in range(8):
		for f in range(8):
			var file_idx = f if white_at_bottom else (7 - f)
			var rank_idx = (7 - r) if white_at_bottom else r
			var sq = rank_idx * 8 + file_idx

			var sq_x = board_rect.position.x + (f * square_w)
			var sq_y = board_rect.position.y + (r * square_h)
			
			var piece_info = _classify_square(img, sq_x, sq_y, square_w, square_h)
			board_state[sq] = piece_info

	return _board_state_to_fen(board_state, white_at_bottom)

## Analyse les pixels d'une case pour déterminer la présence, la couleur et le type de pièce
static func _classify_square(img: Image, x: int, y: int, w: int, h: int) -> Dictionary:
	var margin_x = w / 6
	var margin_y = h / 6
	var inner_w = w - (margin_x * 2)
	var inner_h = h - (margin_y * 2)
	
	if inner_w <= 0 or inner_h <= 0:
		return {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	# Échantillonnage de la couleur du fond (sur les 4 coins de la case)
	var corner_colors = [
		img.get_pixel(x + 2, y + 2),
		img.get_pixel(x + w - 3, y + 2),
		img.get_pixel(x + 2, y + h - 3),
		img.get_pixel(x + w - 3, y + h - 3)
	]
	var bg_lum = 0.0
	for c in corner_colors:
		bg_lum += c.get_luminance()
	bg_lum /= 4.0

	# Mesure de variance et contraste au centre de la case
	var center_samples = 0
	var diff_sum = 0.0
	var bright_count = 0
	var dark_count = 0

	for sy in range(y + margin_y, y + margin_y + inner_h, 2):
		for sx in range(x + margin_x, x + margin_x + inner_w, 2):
			var p = img.get_pixel(sx, sy)
			var lum = p.get_luminance()
			var diff = abs(lum - bg_lum)
			diff_sum += diff
			center_samples += 1
			
			if lum > 0.65:
				bright_count += 1
			elif lum < 0.35:
				dark_count += 1

	var avg_diff = diff_sum / maxi(1, center_samples)
	
	# Si la différence par rapport au fond est très faible -> Case vide
	if avg_diff < 0.12:
		return {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

	# Détermination de la couleur de la pièce
	var piece_color = ChessPiece.PieceColor.WHITE if bright_count > dark_count else ChessPiece.PieceColor.BLACK

	# Heuristique d'estimation du type de pièce basée sur la hauteur et la densité
	var piece_type = _estimate_piece_type(img, x + margin_x, y + margin_y, inner_w, inner_h, bg_lum)
	return {"type": piece_type, "color": piece_color}

static func _estimate_piece_type(img: Image, x: int, y: int, w: int, h: int, bg_lum: float) -> ChessPiece.Type:
	# Détection de la répartition verticale des pixels actifs (haut, milieu, bas)
	var top_active = 0
	var mid_active = 0
	var bot_active = 0

	var h3 = h / 3
	for sy in range(y, y + h, 2):
		var row_rel = sy - y
		for sx in range(x, x + w, 2):
			var p = img.get_pixel(sx, sy)
			if abs(p.get_luminance() - bg_lum) > 0.15:
				if row_rel < h3:
					top_active += 1
				elif row_rel < h3 * 2:
					mid_active += 1
				else:
					bot_active += 1

	var total_active = top_active + mid_active + bot_active
	if total_active < 15:
		return ChessPiece.Type.PAWN

	var top_ratio = float(top_active) / total_active
	var bot_ratio = float(bot_active) / total_active

	# Classification par silhouettes
	if top_ratio > 0.32:
		# Pièce lourde ou couronnée (Dame ou Tour)
		return ChessPiece.Type.QUEEN if total_active > 70 else ChessPiece.Type.ROOK
	elif bot_ratio > 0.55:
		# Base large avec petite tête -> Pion
		return ChessPiece.Type.PAWN
	elif top_ratio > 0.22 and top_ratio <= 0.32:
		# Tête haute avec croix ou pointe -> Roi ou Fou
		return ChessPiece.Type.KING if total_active > 65 else ChessPiece.Type.BISHOP
	else:
		# Asymétrique / moyen -> Cavalier
		return ChessPiece.Type.KNIGHT

static func _board_state_to_fen(board_state: Array, _white_at_bottom: bool) -> String:
	var fen = ""
	for r in range(7, -1, -1):
		var empty_count = 0
		for f in range(8):
			var sq = r * 8 + f
			var piece = board_state[sq]
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

	fen += " w KQkq - 0 1"
	return fen
