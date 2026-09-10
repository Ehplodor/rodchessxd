class_name TacticalMotifDetector
extends RefCounted
## TacticalMotifDetector.gd - Détection heuristique de motifs tactiques sur un coup joué.
## Fournit au coach des FAITS vérifiés (évite que le LLM « invente » les motifs, cf. T1.4).
## Approche légère : aucune recherche, uniquement des cartes d'attaques sur la position.

## Retourne une liste de motifs (français) parmi : Prise, Promotion, Échec, Mat,
## Mat du couloir, Attaque à la découverte, Fourchette, Fourchette royale, Pièce non protégée.
static func detect(fen_before: String, played_uci: String, _pv: Array = []) -> Array:
	var motifs: Array = []
	if fen_before == "" or played_uci == "":
		return motifs
	var game := ChessGame.new()
	if not game.load_fen(fen_before):
		return motifs
	var played: ChessMove = game.find_move(played_uci)
	if played == null:
		return motifs

	var mover: int = played.color
	if mover == ChessPiece.PieceColor.NONE:
		mover = game.active_color
	var opponent: int = ChessPiece.PieceColor.BLACK if mover == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	var moved_piece := {"type": played.piece, "color": mover}
	var dst: int = played.to_sq

	game.make_move(played)
	var enemy_king_sq := _find_king(game, opponent)
	var gives_check := game.is_in_check(opponent)
	var is_mate := gives_check and game.get_legal_moves(opponent).is_empty()

	if played.captured_piece != ChessPiece.Type.NONE:
		motifs.append("Prise")
	if played.promotion != ChessPiece.Type.NONE:
		motifs.append("Promotion")

	var attacks := _piece_attacks(game, dst, moved_piece)
	var forked_pieces := 0
	var fork_targets_king := false
	for sq in attacks:
		var p: Dictionary = game.board[sq]
		if int(p.get("color", ChessPiece.PieceColor.NONE)) != opponent:
			continue
		var t := int(p.get("type", ChessPiece.Type.NONE))
		if t == ChessPiece.Type.KING:
			fork_targets_king = true
		elif t != ChessPiece.Type.NONE:
			forked_pieces += 1

	if is_mate:
		motifs.append("Mat")
		if _is_back_rank_mate(game, enemy_king_sq, played):
			motifs.append("Mat du couloir")
	elif gives_check:
		motifs.append("Échec")
		if not attacks.has(enemy_king_sq):
			motifs.append("Attaque à la découverte")

	if fork_targets_king and forked_pieces >= 1:
		motifs.append("Fourchette royale")
	elif forked_pieces >= 2:
		motifs.append("Fourchette")

	# Pièce avancée attaquée par l'adversaire et non défendue : indice de sacrifice.
	if game.is_square_attacked(dst, opponent) and not game.is_square_attacked(dst, mover):
		motifs.append("Pièce non protégée")

	return motifs

static func _find_king(game: ChessGame, color: int) -> int:
	for sq in range(64):
		var p: Dictionary = game.board[sq]
		if int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.KING \
				and int(p.get("color", ChessPiece.PieceColor.NONE)) == color:
			return sq
	return -1

static func _is_back_rank_mate(game: ChessGame, king_sq: int, played: ChessMove) -> bool:
	if king_sq < 0:
		return false
	var rank := int(king_sq / 8)
	var king_color := int(game.board[king_sq].get("color", ChessPiece.PieceColor.NONE))
	var home_rank := 0 if king_color == ChessPiece.PieceColor.BLACK else 7
	if rank != home_rank:
		return false
	return played.piece == ChessPiece.Type.ROOK or played.piece == ChessPiece.Type.QUEEN

## Cartes d'attaques d'une pièce depuis `from_sq` sur le plateau courant.
static func _piece_attacks(game: ChessGame, from_sq: int, piece: Dictionary) -> Array:
	var out: Array = []
	if from_sq < 0 or from_sq > 63:
		return out
	var color := int(piece.get("color", ChessPiece.PieceColor.NONE))
	var type := int(piece.get("type", ChessPiece.Type.NONE))
	var f := from_sq % 8
	var r := int(from_sq / 8)

	match type:
		ChessPiece.Type.PAWN:
			var dd := 1 if color == ChessPiece.PieceColor.WHITE else -1
			for df in [-1, 1]:
				var nf: int = f + int(df)
				var nr: int = r + dd
				if nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
					out.append(nr * 8 + nf)
		ChessPiece.Type.KNIGHT:
			for o in [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]:
				var nf: int = f + int(o[0])
				var nr: int = r + int(o[1])
				if nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
					out.append(nr * 8 + nf)
		ChessPiece.Type.KING:
			for df in [-1, 0, 1]:
				for dr in [-1, 0, 1]:
					if df == 0 and dr == 0:
						continue
					var nf: int = f + int(df)
					var nr: int = r + int(dr)
					if nf >= 0 and nf < 8 and nr >= 0 and nr < 8:
						out.append(nr * 8 + nf)
		_:
			var dirs: Array = []
			if type == ChessPiece.Type.BISHOP or type == ChessPiece.Type.QUEEN:
				dirs.append_array([[1, 1], [1, -1], [-1, 1], [-1, -1]])
			if type == ChessPiece.Type.ROOK or type == ChessPiece.Type.QUEEN:
				dirs.append_array([[1, 0], [-1, 0], [0, 1], [0, -1]])
			for d in dirs:
				var nf: int = f
				var nr: int = r
				while true:
					nf += int(d[0])
					nr += int(d[1])
					if nf < 0 or nf > 7 or nr < 0 or nr > 7:
						break
					out.append(nr * 8 + nf)
					if int(game.board[nr * 8 + nf].get("type", ChessPiece.Type.NONE)) != ChessPiece.Type.NONE:
						break
	return out
