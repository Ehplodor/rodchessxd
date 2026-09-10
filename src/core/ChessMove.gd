class_name ChessMove
extends RefCounted
## ChessMove.gd - Représentation complète d'un coup d'échecs avec métriques d'analyse

enum Quality {
	NONE = 0,
	BEST = 1,
	BRILLIANT = 2,
	GREAT = 3,
	EXCELLENT = 4,
	GOOD = 5,
	INACCURACY = 6,
	MISTAKE = 7,
	BLUNDER = 8,
	MISS = 9
}

var from_sq: int = -1 # 0 à 63 (0=a1, 63=h8)
var to_sq: int = -1
var piece: int = ChessPiece.Type.NONE
var color: int = ChessPiece.PieceColor.NONE
var captured_piece: int = ChessPiece.Type.NONE
var promotion: int = ChessPiece.Type.NONE

var is_castling: bool = false
var is_en_passant: bool = false
var is_check: bool = false
var is_checkmate: bool = false

var san: String = ""
var uci: String = ""

# Métriques d'analyse moteur
var eval_before_cp: int = 0
var eval_after_cp: int = 0
var eval_mate_in: int = 0
var best_move_uci: String = ""
var centipawn_loss: int = 0
var winpct_loss: float = 0.0
var quality: Quality = Quality.NONE
var is_theory: bool = false
var motifs: Array = []
var coach_explanation: String = ""
## Horloge restante après le coup (secondes), issue des annotations PGN [%clk] (T2.4).
var clock_sec: float = -1.0

func _init(p_from: int = -1, p_to: int = -1, p_piece: int = ChessPiece.Type.NONE, p_color: int = ChessPiece.PieceColor.NONE) -> void:
	from_sq = p_from
	to_sq = p_to
	piece = p_piece
	color = p_color
	if p_from >= 0 and p_to >= 0:
		uci = square_to_coord(p_from) + square_to_coord(p_to)

static func square_to_coord(sq: int) -> String:
	if sq < 0 or sq > 63:
		return ""
	var file_idx = sq % 8
	var rank_idx = sq / 8
	var file_char = char("a".unicode_at(0) + file_idx)
	var rank_char = str(rank_idx + 1)
	return file_char + rank_char

static func coord_to_square(coord: String) -> int:
	if coord.length() < 2:
		return -1
	var file_idx = coord.unicode_at(0) - "a".unicode_at(0)
	var rank_idx = coord.unicode_at(1) - "1".unicode_at(0)
	if file_idx < 0 or file_idx > 7 or rank_idx < 0 or rank_idx > 7:
		return -1
	return rank_idx * 8 + file_idx

static func quality_to_symbol(q: Quality) -> String:
	match q:
		Quality.BRILLIANT: return "!!"
		Quality.GREAT: return "!"
		Quality.BEST: return "★"
		Quality.EXCELLENT: return "✓+"
		Quality.GOOD: return "✓"
		Quality.INACCURACY: return "?!"
		Quality.MISTAKE: return "?"
		Quality.BLUNDER: return "??"
		Quality.MISS: return "X"
	return ""

static func quality_to_color(q: Quality) -> Color:
	match q:
		Quality.BRILLIANT: return Color("#10b981") # Turquoise brillant
		Quality.GREAT: return Color("#3b82f6") # Bleu franc
		Quality.BEST: return Color("#22c55e") # Vert vif
		Quality.EXCELLENT: return Color("#84cc16") # Vert clair
		Quality.GOOD: return Color("#94a3b8") # Gris discret
		Quality.INACCURACY: return Color("#eab308") # Jaune
		Quality.MISTAKE: return Color("#f97316") # Orange
		Quality.BLUNDER: return Color("#ef4444") # Rouge vif
		Quality.MISS: return Color("#ec4899") # Rose foncé
	return Color("#64748b")
