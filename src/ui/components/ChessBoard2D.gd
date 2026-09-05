class_name ChessBoard2D
extends Control
## ChessBoard2D.gd - Affichage et interaction tactile 2D haute qualité avec animations fluides, coordonnées intégrées et effets visuels

signal square_clicked(sq: int)

# Thèmes de couleurs d'échiquier modernisés
const THEMES := {
	"dark_modern": {
		"light": Color("#334155"), # Ardoise clair
		"dark": Color("#1e293b"),  # Ardoise sombre
		"selected": Color("#38bdf855"), # Bleu ciel translucide
		"selected_border": Color("#38bdf8"),
		"legal_dot": Color("#38bdf8bb"),
		"last_move": Color("#eab3083d"),
		"last_move_border": Color("#eab30888"),
		"check": Color("#ef444499"),
		"best_move_arrow": Color("#10b981"),
		"best_move_arrow_secondary": Color("#06b6d4")
	},
	"emerald": {
		"light": Color("#f1f5f9"),
		"dark": Color("#059669"),
		"selected": Color("#fbbf2455"),
		"selected_border": Color("#fbbf24"),
		"legal_dot": Color("#10b981cc"),
		"last_move": Color("#fbbf243d"),
		"last_move_border": Color("#fbbf2488"),
		"check": Color("#ef444499"),
		"best_move_arrow": Color("#3b82f6"),
		"best_move_arrow_secondary": Color("#6366f1")
	},
	"wood": {
		"light": Color("#f0d9b5"),
		"dark": Color("#b58863"),
		"selected": Color("#60a5fa55"),
		"selected_border": Color("#3b82f6"),
		"legal_dot": Color("#22c55ecc"),
		"last_move": Color("#f59e0b3d"),
		"last_move_border": Color("#f59e0b88"),
		"check": Color("#ef444499"),
		"best_move_arrow": Color("#10b981"),
		"best_move_arrow_secondary": Color("#14b8a6")
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
var check_pulse_timer: float = 0.0

var best_move_arrow_from: int = -1
var best_move_arrow_to: int = -1

# Système d'animations fluides
var active_tweens: Array[Tween] = []
var ghost_sprites: Array[TextureRect] = []
var move_anim_duration: float = 0.18

func _get_game_controller() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		return tree.root.get_node("GameController")
	return null

func _get_settings_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _get_engine_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		return tree.root.get_node("EngineManager")
	return null

func _ready() -> void:
	custom_minimum_size = Vector2(350, 350)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)
	
	_preload_piece_textures()
	_update_dimensions()
	_create_piece_nodes()
	
	var gc = _get_game_controller()
	if gc:
		gc.position_changed.connect(_on_position_changed)
		gc.game_reset.connect(_on_game_reset)
		gc.move_navigated.connect(_on_move_navigated)
		gc.square_selected.connect(_on_square_selected)
		gc.square_deselected.connect(_on_square_deselected)
		gc.move_made.connect(_on_move_made)
	
	var eng = _get_engine_manager()
	if eng != null:
		eng.evaluation_updated.connect(_on_engine_eval)

func _process(delta: float) -> void:
	if in_check_sq != -1:
		check_pulse_timer += delta * 5.0
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_dimensions()
		reset_board_visuals()

func _update_dimensions() -> void:
	var side = min(size.x, size.y)
	if side < 100:
		side = 350
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
	drag_texture_rect.z_index = 20
	add_child(drag_texture_rect)

func _get_square_screen_pos(sq: int) -> Vector2:
	var f = sq % 8
	var r = sq / 8
	var flipped = false
	var gc = _get_game_controller()
	if gc:
		flipped = gc.board_flipped
	var disp_f = (7 - f) if flipped else f
	var disp_r = r if flipped else (7 - r)
	return Vector2(disp_f * square_size, disp_r * square_size)

func _clear_active_tweens() -> void:
	for t in active_tweens:
		if t and t.is_valid():
			t.kill()
	active_tweens.clear()

func _clear_ghost_sprites() -> void:
	for g in ghost_sprites:
		if is_instance_valid(g):
			g.queue_free()
	ghost_sprites.clear()
	
	# Nettoyage de sécurité préventif : toute TextureRect orpheline est éliminée
	var sprite_nodes = piece_sprites.values()
	for child in get_children():
		if child is TextureRect and child != drag_texture_rect and not (child in sprite_nodes):
			child.queue_free()

## Réinitialisation graphique complète et propre du plateau (efface toutes les pièces, annule les tweens, purge les résidus)
func reset_board_visuals() -> void:
	_clear_active_tweens()
	_clear_ghost_sprites()
	
	dragged_sq = -1
	if drag_texture_rect:
		drag_texture_rect.visible = false
	
	best_move_arrow_from = -1
	best_move_arrow_to = -1
	
	var gc = _get_game_controller()
	if gc and gc.current_ply_index >= 0 and gc.current_ply_index < gc.game.move_history.size():
		var m = gc.game.move_history[gc.current_ply_index]
		last_move_from = m.from_sq
		last_move_to = m.to_sq
	else:
		last_move_from = -1
		last_move_to = -1
	
	# 1. Remise à zéro complète et absolue de toutes les cases
	for sq in range(64):
		var tr: TextureRect = piece_sprites.get(sq, null)
		if tr:
			tr.position = _get_square_screen_pos(sq)
			tr.size = Vector2(square_size, square_size)
			tr.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
			tr.scale = Vector2.ONE
			tr.modulate = Color.WHITE
			tr.z_index = 1
			tr.texture = null
			tr.visible = false
	
	# 2. Ré-attribution stricte des pièces actuellement présentes sur l'échiquier
	if gc and gc.game:
		for sq in range(64):
			var piece = gc.game.get_piece(sq)
			if piece.type != ChessPiece.Type.NONE:
				var tr: TextureRect = piece_sprites.get(sq, null)
				if tr:
					var key = Vector2i(piece.type, piece.color)
					tr.texture = piece_textures.get(key, null)
					tr.visible = true
	
	_check_king_status()
	queue_redraw()

func _update_piece_positions() -> void:
	reset_board_visuals()

# --- SYSTÈME D'ANIMATION DE COUPS ---

func _animate_move(move: ChessMove) -> void:
	_clear_active_tweens()
	
	var moving_sprite: TextureRect = piece_sprites.get(move.from_sq, null)
	if not moving_sprite:
		reset_board_visuals()
		return
	
	if moving_sprite.texture == null and move.piece != ChessPiece.Type.NONE:
		var key = Vector2i(move.piece, move.color)
		moving_sprite.texture = piece_textures.get(key, null)
	
	var start_pos = _get_square_screen_pos(move.from_sq)
	var end_pos = _get_square_screen_pos(move.to_sq)
	
	moving_sprite.position = start_pos
	moving_sprite.size = Vector2(square_size, square_size)
	moving_sprite.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	moving_sprite.z_index = 10
	
	# 1. Effet de disparition/capture (Ghost Sprite)
	if move.captured_piece != ChessPiece.Type.NONE:
		var cap_sq = move.to_sq
		if move.is_en_passant:
			cap_sq = move.to_sq - 8 if move.color == ChessPiece.PieceColor.WHITE else move.to_sq + 8
		
		_spawn_capture_ghost(cap_sq, move.captured_piece, move.color)
	
	# 2. Animation simultanée de la Tour lors du roque
	if move.is_castling:
		_animate_castling_rook(move)
	
	# 3. Tween de déplacement fluide de la pièce avec légère élévation physique
	var tween = create_tween()
	active_tweens.append(tween)
	
	# Élévation (scale up puis down)
	tween.set_parallel(true)
	tween.tween_property(moving_sprite, "scale", Vector2(1.10, 1.10), move_anim_duration * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(moving_sprite, "position", end_pos, move_anim_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property(moving_sprite, "scale", Vector2.ONE, move_anim_duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween.chain().tween_callback(func():
		moving_sprite.z_index = 1
		reset_board_visuals()
	)

func _spawn_capture_ghost(sq: int, cap_type: int, attacker_color: int) -> void:
	var cap_color = ChessPiece.PieceColor.BLACK if attacker_color == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	var key = Vector2i(cap_type, cap_color)
	var tex = piece_textures.get(key, null)
	if not tex:
		return
	
	var ghost = TextureRect.new()
	ghost.texture = tex
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = Vector2(square_size, square_size)
	ghost.position = _get_square_screen_pos(sq)
	ghost.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	ghost.z_index = 5
	add_child(ghost)
	ghost_sprites.append(ghost)
	
	var g_tween = create_tween()
	active_tweens.append(g_tween)
	g_tween.set_parallel(true)
	g_tween.tween_property(ghost, "scale", Vector2(0.2, 0.2), move_anim_duration * 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	g_tween.tween_property(ghost, "modulate:a", 0.0, move_anim_duration * 1.1)
	g_tween.chain().tween_callback(func():
		if is_instance_valid(ghost):
			ghost_sprites.erase(ghost)
			ghost.queue_free()
	)

func _animate_castling_rook(move: ChessMove) -> void:
	var rook_from: int = -1
	var rook_to: int = -1
	
	if move.from_sq == 4 and move.to_sq == 6: # Blancs petit roque (e1g1)
		rook_from = 7; rook_to = 5
	elif move.from_sq == 4 and move.to_sq == 2: # Blancs grand roque (e1c1)
		rook_from = 0; rook_to = 3
	elif move.from_sq == 60 and move.to_sq == 62: # Noirs petit roque (e8g8)
		rook_from = 63; rook_to = 61
	elif move.from_sq == 60 and move.to_sq == 58: # Noirs grand roque (e8c8)
		rook_from = 56; rook_to = 59
	
	if rook_from != -1 and rook_from in piece_sprites:
		var rook_sprite: TextureRect = piece_sprites[rook_from]
		var r_end_pos = _get_square_screen_pos(rook_to)
		rook_sprite.z_index = 8
		var r_tween = create_tween()
		active_tweens.append(r_tween)
		r_tween.tween_property(rook_sprite, "position", r_end_pos, move_anim_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		r_tween.chain().tween_callback(func():
			rook_sprite.z_index = 1
		)

# --- RENDU VISUEL ---

func _draw() -> void:
	var theme_name = "dark_modern"
	var sm = _get_settings_manager()
	if sm:
		theme_name = sm.get_setting("board_theme", "dark_modern")
	var theme = THEMES.get(theme_name, THEMES["dark_modern"])
	
	var flipped = false
	var gc = _get_game_controller()
	if gc:
		flipped = gc.board_flipped
	
	var font = ThemeDB.fallback_font
	var coord_font_size = int(clampf(square_size * 0.22, 10.0, 16.0))

	# 1. Tracé des 64 cases & décorations
	for r in range(8):
		for f in range(8):
			var disp_f = (7 - f) if flipped else f
			var disp_r = r if flipped else (7 - r)
			var sq = r * 8 + f
			
			var is_light = ((r + f) % 2 != 0)
			var base_col = theme["light"] if is_light else theme["dark"]
			var rect = Rect2(disp_f * square_size, disp_r * square_size, square_size, square_size)
			
			# Case de base
			draw_rect(rect, base_col)

			# Dernier coup surbrillance avec contour subtil
			if sq == last_move_from or sq == last_move_to:
				draw_rect(rect, theme["last_move"])
				draw_rect(rect, theme.get("last_move_border", Color("#f59e0b88")), false, 1.5)

			# Case sélectionnée avec aura
			if gc and sq == gc.selected_square:
				draw_rect(rect, theme["selected"])
				draw_rect(rect, theme.get("selected_border", Color("#38bdf8")), false, 2.0)

			# Roi en échec avec pulsation dynamique
			if sq == in_check_sq:
				var pulse = (sin(check_pulse_timer) + 1.0) * 0.5
				var check_col = Color(theme["check"].r, theme["check"].g, theme["check"].b, 0.45 + 0.35 * pulse)
				draw_rect(rect, check_col)
				draw_rect(rect, Color(1.0, 0.2, 0.2, 0.85 + 0.15 * pulse), false, 2.5)

			# Coordonnées intégrées au plateau (Files a-h et Rangs 1-8)
			# Chiffres des rangs affichés sur la colonne de gauche (disp_f == 0)
			if disp_f == 0:
				var rank_num = str(r + 1)
				var text_col = theme["dark"] if is_light else theme["light"]
				text_col.a = 0.85
				var text_pos = rect.position + Vector2(4, coord_font_size + 2)
				draw_string(font, text_pos, rank_num, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size, text_col)

			# Lettres des colonnes affichées sur la rangée du bas (disp_r == 7)
			if disp_r == 7:
				var file_char = char(97 + f) # 'a' à 'h'
				var text_col = theme["dark"] if is_light else theme["light"]
				text_col.a = 0.85
				var text_pos = rect.position + Vector2(square_size - coord_font_size - 3, square_size - 4)
				draw_string(font, text_pos, file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size, text_col)

			# Points de destination légale
			if gc and sq in gc.legal_destinations:
				var center = rect.position + rect.size * 0.5
				var piece_on_target = gc.game.get_piece(sq) if gc.game else null
				if piece_on_target and piece_on_target.type != ChessPiece.Type.NONE:
					# Anneau de capture précis et moderne
					draw_arc(center, square_size * 0.42, 0, TAU, 36, Color(0, 0, 0, 0.25), 5.0) # Ombre
					draw_arc(center, square_size * 0.42, 0, TAU, 36, theme["legal_dot"], 3.5)
				else:
					# Point de déplacement antialiassé
					draw_circle(center, square_size * 0.17, Color(0, 0, 0, 0.2)) # Ombre
					draw_circle(center, square_size * 0.16, theme["legal_dot"])

	# 2. Flèche tactique moderne pour le coup suggéré par l'analyse
	if best_move_arrow_from != -1 and best_move_arrow_to != -1:
		_draw_modern_move_arrow(best_move_arrow_from, best_move_arrow_to, theme)

func _draw_modern_move_arrow(from_sq: int, to_sq: int, theme: Dictionary) -> void:
	var start_pos = _get_square_screen_pos(from_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	var end_pos = _get_square_screen_pos(to_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	var dir = (end_pos - start_pos).normalized()
	var dist = start_pos.distance_to(end_pos)
	if dist < 1.0:
		return
	
	var arrow_color: Color = theme.get("best_move_arrow", Color("#10b981"))
	var shaft_width: float = clampf(square_size * 0.16, 6.0, 12.0)
	var head_length: float = clampf(square_size * 0.40, 18.0, 30.0)
	var head_width: float = clampf(square_size * 0.48, 22.0, 36.0)
	
	var shaft_end = end_pos - dir * (head_length * 0.85)
	var perp = Vector2(-dir.y, dir.x)
	
	# 1. Ombre portée pour contraste maximal sur tous les thèmes
	var shadow_offset = Vector2(2, 2)
	draw_circle(start_pos + shadow_offset, shaft_width * 0.8, Color(0, 0, 0, 0.35))
	draw_line(start_pos + shadow_offset, shaft_end + shadow_offset, Color(0, 0, 0, 0.35), shaft_width + 3.0, true)
	var shadow_p1 = end_pos + shadow_offset
	var shadow_p2 = shaft_end + shadow_offset + perp * (head_width * 0.5)
	var shadow_p3 = shaft_end + shadow_offset - perp * (head_width * 0.5)
	draw_colored_polygon(PackedVector2Array([shadow_p1, shadow_p2, shadow_p3]), Color(0, 0, 0, 0.35))
	
	# 2. Base circulaire
	draw_circle(start_pos, shaft_width * 0.7, arrow_color)
	
	# 3. Ligne de tige principale
	draw_line(start_pos, shaft_end, arrow_color, shaft_width, true)
	
	# 4. Tête de flèche aérodynamique
	var p1 = end_pos
	var p2 = shaft_end + perp * (head_width * 0.5)
	var p3 = shaft_end - perp * (head_width * 0.5)
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), arrow_color)

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
	
	var gc = _get_game_controller()
	if not gc or not gc.game:
		return
	
	var piece = gc.game.get_piece(sq)
	if piece.type != ChessPiece.Type.NONE and piece.color == gc.game.active_color:
		dragged_sq = sq
		var key = Vector2i(piece.type, piece.color)
		drag_texture_rect.texture = piece_textures.get(key, null)
		drag_texture_rect.size = Vector2(square_size * 1.08, square_size * 1.08) # Léger grossissement au toucher
		drag_texture_rect.position = pos - Vector2(square_size * 0.54, square_size * 0.54)
		drag_offset = Vector2(square_size * 0.54, square_size * 0.54)
		drag_texture_rect.visible = true
		if sq in piece_sprites:
			piece_sprites[sq].visible = false

	gc.select_square(sq)
	queue_redraw()

func _handle_release(to_sq: int, _pos: Vector2) -> void:
	var gc = _get_game_controller()
	if dragged_sq != -1:
		if to_sq != -1 and to_sq != dragged_sq and gc:
			gc.try_play_move(dragged_sq, to_sq)
		
		drag_texture_rect.visible = false
		if dragged_sq in piece_sprites:
			piece_sprites[dragged_sq].visible = true
		dragged_sq = -1
		reset_board_visuals()

func _pos_to_square(pos: Vector2) -> int:
	if pos.x < 0 or pos.x >= board_size or pos.y < 0 or pos.y >= board_size:
		return -1
	var f = int(pos.x / square_size)
	var r = int(pos.y / square_size)
	var flipped = false
	var gc = _get_game_controller()
	if gc:
		flipped = gc.board_flipped
	var actual_f = (7 - f) if flipped else f
	var actual_r = r if flipped else (7 - r)
	return actual_r * 8 + actual_f

# --- SIGNAUX & MISES À JOUR ---

func _on_game_reset() -> void:
	reset_board_visuals()

func _on_move_navigated(_ply_idx: int) -> void:
	reset_board_visuals()

func _on_position_changed() -> void:
	reset_board_visuals()

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
	_animate_move(move)
	queue_redraw()

func _check_king_status() -> void:
	in_check_sq = -1
	var gc = _get_game_controller()
	if gc and gc.game and gc.game.is_in_check(gc.game.active_color):
		for i in range(64):
			var p = gc.game.get_piece(i)
			if p.type == ChessPiece.Type.KING and p.color == gc.game.active_color:
				in_check_sq = i
				break
	set_process(in_check_sq != -1)

func _on_engine_eval(_score_cp: int, _mate_in: int, _depth: int, best_move: String, _pv: Array, _multipv: Array) -> void:
	if best_move.length() >= 4:
		best_move_arrow_from = ChessMove.coord_to_square(best_move.substr(0, 2))
		best_move_arrow_to = ChessMove.coord_to_square(best_move.substr(2, 2))
		queue_redraw()

