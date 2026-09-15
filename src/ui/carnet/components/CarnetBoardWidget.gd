class_name CarnetBoardWidget
extends Control
## CarnetBoardWidget.gd — Échiquier 2D autonome et compact pour LeCarnet.
##
## Indépendant de GameController : affiche n'importe quelle position FEN,
## avec orientation adaptée au camp du joueur, surbrillance du dernier coup adverse,
## et flèches pédagogiques (meilleur coup vs piège).

signal move_attempted(uci: String)

const THEME_LIGHT := Color("#ebecd0")
const THEME_DARK := Color("#739552")
const HIGHLIGHT_LAST_MOVE := Color(0.98, 0.90, 0.35, 0.38)
const HIGHLIGHT_SELECTED := Color(0.22, 0.74, 0.97, 0.40)
const HIGHLIGHT_BEST := Color(0.16, 0.75, 0.40, 0.45)
const HIGHLIGHT_MISTAKE := Color(0.92, 0.28, 0.28, 0.45)

var fen := ""
var board_flipped := false
var last_move_from := -1
var last_move_to := -1
var best_move_from := -1
var best_move_to := -1
var mistake_move_from := -1
var mistake_move_to := -1

var _square_size := 38.0
var _piece_sprites: Dictionary = {} # sq -> TextureRect
var _piece_textures: Dictionary = {}
var _game: ChessGame = null
var _selected_sq := -1

func _init() -> void:
	# Dimensions par défaut adaptées au viewport mobile (450px logique) tout en restant
	# compact et sans déborder des marges (280x280 = 8 x 35px).
	custom_minimum_size = Vector2(280, 280)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	_preload_piece_textures()
	_create_piece_nodes()
	_game = ChessGame.new()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()

func _preload_piece_textures() -> void:
	for color in [ChessPiece.PieceColor.WHITE, ChessPiece.PieceColor.BLACK]:
		for type in [ChessPiece.Type.PAWN, ChessPiece.Type.KNIGHT, ChessPiece.Type.BISHOP,
				ChessPiece.Type.ROOK, ChessPiece.Type.QUEEN, ChessPiece.Type.KING]:
			var path := ChessPiece.asset_path(type, color)
			if ResourceLoader.exists(path):
				_piece_textures[Vector2i(type, color)] = load(path)

func _create_piece_nodes() -> void:
	for sq in range(64):
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.visible = false
		add_child(tr)
		_piece_sprites[sq] = tr

func load_position(p_fen: String, p_flipped: bool = false, p_last_move_uci: String = "") -> void:
	fen = p_fen
	board_flipped = p_flipped
	_selected_sq = -1
	best_move_from = -1
	best_move_to = -1
	mistake_move_from = -1
	mistake_move_to = -1

	if p_last_move_uci.length() >= 4:
		last_move_from = ChessMove.coord_to_square(p_last_move_uci.substr(0, 2))
		last_move_to = ChessMove.coord_to_square(p_last_move_uci.substr(2, 2))
	else:
		last_move_from = -1
		last_move_to = -1

	if fen != "":
		_game.load_fen(fen)
	_update_pieces()
	queue_redraw()

func show_solution(best_uci: String, mistake_uci: String = "") -> void:
	if best_uci.length() >= 4:
		best_move_from = ChessMove.coord_to_square(best_uci.substr(0, 2))
		best_move_to = ChessMove.coord_to_square(best_uci.substr(2, 2))
	if mistake_uci.length() >= 4:
		mistake_move_from = ChessMove.coord_to_square(mistake_uci.substr(0, 2))
		mistake_move_to = ChessMove.coord_to_square(mistake_uci.substr(2, 2))
	queue_redraw()

func _update_layout() -> void:
	var side := minf(size.x, size.y)
	if side < 160.0:
		side = custom_minimum_size.x if custom_minimum_size.x >= 160.0 else 280.0
	_square_size = maxf(24.0, floorf(side / 8.0))
	var exact_side := _square_size * 8.0
	if custom_minimum_size != Vector2(exact_side, exact_side):
		custom_minimum_size = Vector2(exact_side, exact_side)
	_update_pieces()
	queue_redraw()

func _get_square_pos(sq: int) -> Vector2:
	var f := sq % 8
	var r := int(sq / 8)
	var disp_f := (7 - f) if board_flipped else f
	var disp_r := r if board_flipped else (7 - r)
	var offset_x := (size.x - _square_size * 8.0) * 0.5
	var offset_y := (size.y - _square_size * 8.0) * 0.5
	return Vector2(offset_x + disp_f * _square_size, offset_y + disp_r * _square_size)

func _get_square_at(pos: Vector2) -> int:
	var offset_x := (size.x - _square_size * 8.0) * 0.5
	var offset_y := (size.y - _square_size * 8.0) * 0.5
	var rel_x := pos.x - offset_x
	var rel_y := pos.y - offset_y
	if rel_x < 0.0 or rel_y < 0.0 or rel_x >= _square_size * 8.0 or rel_y >= _square_size * 8.0:
		return -1
	var disp_f := int(rel_x / _square_size)
	var disp_r := int(rel_y / _square_size)
	var f := (7 - disp_f) if board_flipped else disp_f
	var r := disp_r if board_flipped else (7 - disp_r)
	return r * 8 + f

func _update_pieces() -> void:
	if _game == null:
		return
	for sq in range(64):
		var tr: TextureRect = _piece_sprites.get(sq, null)
		if tr == null:
			continue
		var pos := _get_square_pos(sq)
		tr.position = pos
		tr.size = Vector2(_square_size, _square_size)

		var piece = _game.get_piece(sq)
		if piece != null and int(piece.type) != ChessPiece.Type.NONE:
			var key := Vector2i(int(piece.type), int(piece.color))
			tr.texture = _piece_textures.get(key, null)
			tr.visible = true
		else:
			tr.texture = null
			tr.visible = false

func _draw() -> void:
	var offset_x := (size.x - _square_size * 8.0) * 0.5
	var offset_y := (size.y - _square_size * 8.0) * 0.5

	# 1. Fond des 64 cases
	for r in range(8):
		for f in range(8):
			var is_light := (r + f) % 2 == 1
			var col := THEME_LIGHT if is_light else THEME_DARK
			var rect := Rect2(offset_x + f * _square_size, offset_y + r * _square_size, _square_size, _square_size)
			draw_rect(rect, col, true)

	# 2. Surbrillances de coups
	if last_move_from >= 0:
		_draw_square_highlight(last_move_from, HIGHLIGHT_LAST_MOVE)
	if last_move_to >= 0:
		_draw_square_highlight(last_move_to, HIGHLIGHT_LAST_MOVE)

	if best_move_to >= 0:
		_draw_square_highlight(best_move_to, HIGHLIGHT_BEST)
	if mistake_move_to >= 0:
		_draw_square_highlight(mistake_move_to, HIGHLIGHT_MISTAKE)

	if _selected_sq >= 0:
		_draw_square_highlight(_selected_sq, HIGHLIGHT_SELECTED)

	# 3. Coordonnées légères sur les bords
	var font := ThemeDB.fallback_font
	if font != null:
		var font_sz := maxi(9, int(_square_size * 0.24))
		for f in range(8):
			var file_char := char(97 + ((7 - f) if board_flipped else f))
			var is_light_bottom := (7 + f) % 2 == 1
			var text_col := THEME_DARK if is_light_bottom else THEME_LIGHT
			var pos := Vector2(offset_x + f * _square_size + 2.0, offset_y + 8.0 * _square_size - 3.0)
			draw_string(font, pos, file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, text_col)
		for r in range(8):
			var rank_char := str((r + 1) if board_flipped else (8 - r))
			var is_light_left := r % 2 == 1
			var text_col := THEME_DARK if is_light_left else THEME_LIGHT
			var pos := Vector2(offset_x + 2.0, offset_y + r * _square_size + font_sz + 1.0)
			draw_string(font, pos, rank_char, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, text_col)

	# 4. Flèches de résolution
	if best_move_from >= 0 and best_move_to >= 0:
		_draw_arrow(best_move_from, best_move_to, Color("#22c55e"))
	if mistake_move_from >= 0 and mistake_move_to >= 0:
		_draw_arrow(mistake_move_from, mistake_move_to, Color("#ef4444"))

func _draw_square_highlight(sq: int, color: Color) -> void:
	var pos := _get_square_pos(sq)
	draw_rect(Rect2(pos.x, pos.y, _square_size, _square_size), color, true)

func _draw_arrow(from_sq: int, to_sq: int, color: Color) -> void:
	var start := _get_square_pos(from_sq) + Vector2(_square_size * 0.5, _square_size * 0.5)
	var end := _get_square_pos(to_sq) + Vector2(_square_size * 0.5, _square_size * 0.5)
	var dir := (end - start).normalized()
	var width := maxf(3.0, _square_size * 0.10)
	var head_len := maxf(8.0, _square_size * 0.28)
	var head_base := end - dir * head_len

	draw_line(start, head_base, color, width, true)
	var perp := Vector2(-dir.y, dir.x) * (head_len * 0.6)
	var triangle := PackedVector2Array([end, head_base + perp, head_base - perp])
	draw_colored_polygon(triangle, color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var sq := _get_square_at(event.position)
		if sq >= 0:
			_handle_square_click(sq)
	elif event is InputEventScreenTouch and event.pressed:
		var sq := _get_square_at(event.position)
		if sq >= 0:
			_handle_square_click(sq)

func _handle_square_click(sq: int) -> void:
	if _selected_sq == -1:
		var p = _game.get_piece(sq) if _game else null
		if p != null and int(p.type) != ChessPiece.Type.NONE:
			_selected_sq = sq
			queue_redraw()
	else:
		if sq != _selected_sq:
			var uci := "%s%s" % [ChessMove.square_to_coord(_selected_sq), ChessMove.square_to_coord(sq)]
			move_attempted.emit(uci)
		_selected_sq = -1
		queue_redraw()
