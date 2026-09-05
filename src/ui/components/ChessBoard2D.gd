class_name ChessBoard2D
extends Control
## ChessBoard2D.gd - Affichage et interaction tactile 2D de l'échiquier avec surbrillances et flèches

signal square_clicked(sq: int)

# Thèmes de couleurs d'échiquier
const THEMES := {
	"dark_modern": {
		"light": Color("#334155"), # Ardoise clair
		"dark": Color("#1e293b"),  # Ardoise sombre
		"selected": Color("#38bdf888"), # Bleu ciel translucide
		"legal_dot": Color("#38bdf8aa"),
		"last_move": Color("#eab30844"),
		"check": Color("#ef4444aa"),
		"best_move_arrow": Color("#22c55ecc")
	},
	"emerald": {
		"light": Color("#e2e8f0"),
		"dark": Color("#059669"),
		"selected": Color("#fbbf2488"),
		"legal_dot": Color("#10b981aa"),
		"last_move": Color("#fbbf2444"),
		"check": Color("#ef4444aa"),
		"best_move_arrow": Color("#3b82f6cc")
	},
	"wood": {
		"light": Color("#f0d9b5"),
		"dark": Color("#b58863"),
		"selected": Color("#60a5fa88"),
		"legal_dot": Color("#22c55eaa"),
		"last_move": Color("#f59e0b44"),
		"check": Color("#ef4444aa"),
		"best_move_arrow": Color("#10b981cc")
	}
}

var board_size: float = 400.0
var square_size: float = 50.0

var piece_sprites: Dictionary = {} # sq -> TextureRect
var piece_textures: Dictionary = {}

var hovered_sq: int = -1
var dragged_sq: int = -1
var drag_texture_rect: TextureRect = null
var drag_offset: Vector2 = Vector2.ZERO

var last_move_from: int = -1
var last_move_to: int = -1
var in_check_sq: int = -1

var best_move_arrow_from: int = -1
var best_move_arrow_to: int = -1

func _ready() -> void:
	custom_minimum_size = Vector2(360, 360)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_preload_piece_textures()
	_update_dimensions()
	_create_piece_nodes()
	
	GameController.position_changed.connect(_on_position_changed)
	GameController.square_selected.connect(_on_square_selected)
	GameController.square_deselected.connect(_on_square_deselected)
	GameController.move_made.connect(_on_move_made)
	
	if EngineManager != null:
		EngineManager.evaluation_updated.connect(_on_engine_eval)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_dimensions()
		_update_piece_positions()
		queue_redraw()

func _update_dimensions() -> void:
	var side = min(size.x, size.y)
	if side < 100:
		side = 360
	board_size = side
	square_size = board_size / 8.0

func _preload_piece_textures() -> void:
	var colors = [ChessPiece.PieceColor.WHITE, ChessPiece.PieceColor.BLACK]
	var types = [
		ChessPiece.Type.PAWN, ChessPiece.Type.KNIGHT, ChessPiece.Type.BISHOP,
		ChessPiece.Type.ROOK, ChessPiece.Type.QUEEN, ChessPiece.Type.KING
	]
	for c in colors:
		for t in types:
			var path = ChessPiece.asset_path(t, c)
			if ResourceLoader.exists(path):
				piece_textures[Vector2i(t, c)] = load(path)

func _create_piece_nodes() -> void:
	for sq in range(64):
		var tr = TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		piece_sprites[sq] = tr
	
	# Node flottant pour le drag & drop
	drag_texture_rect = TextureRect.new()
	drag_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drag_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_texture_rect.visible = false
	drag_texture_rect.z_index = 10
	add_child(drag_texture_rect)

func _update_piece_positions() -> void:
	var flipped = GameController.board_flipped
	for sq in range(64):
		var tr = piece_sprites.get(sq, null)
		if not tr:
			continue
		
		var f = sq % 8
		var r = sq / 8
		var disp_f = (7 - f) if flipped else f
		var disp_r = r if flipped else (7 - r)
		
		tr.position = Vector2(disp_f * square_size, disp_r * square_size)
		tr.size = Vector2(square_size, square_size)
		
		var piece = GameController.game.get_piece(sq)
		if piece.type != ChessPiece.Type.NONE and sq != dragged_sq:
			var key = Vector2i(piece.type, piece.color)
			tr.texture = piece_textures.get(key, null)
			tr.visible = true
		else:
			tr.texture = null
			tr.visible = false

func _draw() -> void:
	var theme_name = SettingsManager.get_setting("board_theme", "dark_modern")
	var theme = THEMES.get(theme_name, THEMES["dark_modern"])
	var flipped = GameController.board_flipped

	# 1. Tracé des 64 cases
	for r in range(8):
		for f in range(8):
			var disp_f = (7 - f) if flipped else f
			var disp_r = r if flipped else (7 - r)
			var sq = r * 8 + f
			
			var is_light = ((r + f) % 2 != 0)
			var col = theme["light"] if is_light else theme["dark"]
			
			var rect = Rect2(disp_f * square_size, disp_r * square_size, square_size, square_size)
			draw_rect(rect, col)

			# Dernier coup surbrillance
			if sq == last_move_from or sq == last_move_to:
				draw_rect(rect, theme["last_move"])

			# Case sélectionnée
			if sq == GameController.selected_square:
				draw_rect(rect, theme["selected"])

			# Roi en échec
			if sq == in_check_sq:
				draw_rect(rect, theme["check"])

			# Points de destination légale
			if sq in GameController.legal_destinations:
				var center = rect.position + rect.size * 0.5
				var piece_on_target = GameController.game.get_piece(sq)
				if piece_on_target.type != ChessPiece.Type.NONE:
					# Anneau de capture
					draw_arc(center, square_size * 0.4, 0, TAU, 32, theme["legal_dot"], 3.5)
				else:
					# Point doux
					draw_circle(center, square_size * 0.18, theme["legal_dot"])

	# 2. Flèche du meilleur coup calculé par Stockfish
	if best_move_arrow_from != -1 and best_move_arrow_to != -1:
		_draw_move_arrow(best_move_arrow_from, best_move_arrow_to, theme["best_move_arrow"], flipped)

func _draw_move_arrow(from_sq: int, to_sq: int, arrow_color: Color, flipped: bool) -> void:
	var f1 = from_sq % 8
	var r1 = from_sq / 8
	var f2 = to_sq % 8
	var r2 = to_sq / 8
	
	var df1 = (7 - f1) if flipped else f1
	var dr1 = r1 if flipped else (7 - r1)
	var df2 = (7 - f2) if flipped else f2
	var dr2 = r2 if flipped else (7 - r2)

	var start_pos = Vector2(df1 * square_size + square_size * 0.5, dr1 * square_size + square_size * 0.5)
	var end_pos = Vector2(df2 * square_size + square_size * 0.5, dr2 * square_size + square_size * 0.5)
	
	var dir = (end_pos - start_pos).normalized()
	var shaft_end = end_pos - dir * (square_size * 0.3)

	# Ligne principale
	draw_line(start_pos, shaft_end, arrow_color, 4.0, true)

	# Tête de flèche
	var perp = Vector2(-dir.y, dir.x)
	var arrow_p1 = end_pos
	var arrow_p2 = shaft_end + perp * (square_size * 0.2)
	var arrow_p3 = shaft_end - perp * (square_size * 0.2)
	
	var points = PackedVector2Array([arrow_p1, arrow_p2, arrow_p3])
	draw_colored_polygon(points, arrow_color)

# --- GESTION TACTILE & SOURIS ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var sq = _pos_to_square(event.position)
			if event.pressed:
				_handle_press(sq, event.position)
			else:
				_handle_release(sq, event.position)
	elif event is InputEventMouseMotion:
		if dragged_sq != -1:
			drag_texture_rect.position = event.position - drag_offset
	elif event is InputEventScreenTouch:
		var sq = _pos_to_square(event.position)
		if event.pressed:
			_handle_press(sq, event.position)
		else:
			_handle_release(sq, event.position)
	elif event is InputEventScreenDrag:
		if dragged_sq != -1:
			drag_texture_rect.position = event.position - drag_offset

func _handle_press(sq: int, pos: Vector2) -> void:
	if sq == -1:
		return
	
	var piece = GameController.game.get_piece(sq)
	if piece.type != ChessPiece.Type.NONE and piece.color == GameController.game.active_color:
		dragged_sq = sq
		var key = Vector2i(piece.type, piece.color)
		drag_texture_rect.texture = piece_textures.get(key, null)
		drag_texture_rect.size = Vector2(square_size, square_size)
		drag_texture_rect.position = pos - Vector2(square_size * 0.5, square_size * 0.5)
		drag_offset = Vector2(square_size * 0.5, square_size * 0.5)
		drag_texture_rect.visible = true
		piece_sprites[sq].visible = false

	GameController.select_square(sq)
	queue_redraw()

func _handle_release(to_sq: int, _pos: Vector2) -> void:
	if dragged_sq != -1:
		if to_sq != -1 and to_sq != dragged_sq:
			GameController.try_play_move(dragged_sq, to_sq)
		
		drag_texture_rect.visible = false
		if dragged_sq in piece_sprites:
			piece_sprites[dragged_sq].visible = true
		dragged_sq = -1
		_update_piece_positions()
		queue_redraw()

func _pos_to_square(pos: Vector2) -> int:
	if pos.x < 0 or pos.x >= board_size or pos.y < 0 or pos.y >= board_size:
		return -1
	var f = int(pos.x / square_size)
	var r = int(pos.y / square_size)
	var flipped = GameController.board_flipped
	var actual_f = (7 - f) if flipped else f
	var actual_r = r if flipped else (7 - r)
	return actual_r * 8 + actual_f

# --- SIGNAUX & MISES À JOUR ---

func _on_position_changed() -> void:
	_check_king_status()
	_update_piece_positions()
	queue_redraw()

func _on_square_selected(_sq: int, _moves: Array) -> void:
	queue_redraw()

func _on_square_deselected() -> void:
	queue_redraw()

func _on_move_made(move: ChessMove) -> void:
	last_move_from = move.from_sq
	last_move_to = move.to_sq
	best_move_arrow_from = -1
	best_move_arrow_to = -1
	_check_king_status()
	_update_piece_positions()
	queue_redraw()

func _check_king_status() -> void:
	in_check_sq = -1
	var game = GameController.game
	if game and game.is_in_check(game.active_color):
		for i in range(64):
			var p = game.get_piece(i)
			if p.type == ChessPiece.Type.KING and p.color == game.active_color:
				in_check_sq = i
				break

func _on_engine_eval(_score_cp: int, _mate_in: int, _depth: int, best_move: String, _pv: Array, _multipv: Array) -> void:
	if best_move.length() >= 4:
		best_move_arrow_from = ChessMove.coord_to_square(best_move.substr(0, 2))
		best_move_arrow_to = ChessMove.coord_to_square(best_move.substr(2, 2))
		queue_redraw()
