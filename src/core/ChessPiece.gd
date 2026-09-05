class_name ChessPiece
extends RefCounted
## ChessPiece.gd - Définition des types et constantes de pièces d'échecs

enum PieceColor {
	WHITE = 0,
	BLACK = 1,
	NONE = -1
}

enum Type {
	PAWN = 1,
	KNIGHT = 2,
	BISHOP = 3,
	ROOK = 4,
	QUEEN = 5,
	KING = 6,
	NONE = 0
}

const SYMBOLS_WHITE := {
	Type.PAWN: "P",
	Type.KNIGHT: "N",
	Type.BISHOP: "B",
	Type.ROOK: "R",
	Type.QUEEN: "Q",
	Type.KING: "K"
}

const SYMBOLS_BLACK := {
	Type.PAWN: "p",
	Type.KNIGHT: "n",
	Type.BISHOP: "b",
	Type.ROOK: "r",
	Type.QUEEN: "q",
	Type.KING: "k"
}

const VALUES := {
	Type.PAWN: 100,
	Type.KNIGHT: 320,
	Type.BISHOP: 330,
	Type.ROOK: 500,
	Type.QUEEN: 900,
	Type.KING: 20000,
	Type.NONE: 0
}

static func from_char(c: String) -> Dictionary:
	var col = PieceColor.WHITE if c == c.to_upper() else PieceColor.BLACK
	var t = Type.NONE
	match c.to_upper():
		"P": t = Type.PAWN
		"N": t = Type.KNIGHT
		"B": t = Type.BISHOP
		"R": t = Type.ROOK
		"Q": t = Type.QUEEN
		"K": t = Type.KING
	return {"color": col, "type": t}

static func to_char(type: Type, color: PieceColor) -> String:
	if type == Type.NONE or color == PieceColor.NONE:
		return ""
	if color == PieceColor.WHITE:
		return SYMBOLS_WHITE.get(type, "")
	return SYMBOLS_BLACK.get(type, "")

static func asset_path(type: Type, color: PieceColor) -> String:
	var prefix = "w" if color == PieceColor.WHITE else "b"
	var letter = SYMBOLS_WHITE.get(type, "")
	if letter == "":
		return ""
	return "res://assets/pieces/%s%s.svg" % [prefix, letter]
