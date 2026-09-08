class_name ChessBoard2D
extends Control
## ChessBoard2D.gd - Affichage et interaction tactile 2D haute définition avec animations fluides, glissement physique et thèmes modernes

const _PromotionModal = preload("res://src/ui/components/PromotionModal.gd")

signal square_clicked(sq: int)

# Palettes de couleurs raffinées, contemporaines et contrastées
const THEMES := {
	"emerald": {
		"name": "Émeraude Tournoi",
		"light": Color("#ebecd0"), # Ivoire lumineux
		"dark": Color("#739552"),  # Vert tournoi standard international
		"selected": Color(0.97, 0.92, 0.35, 0.40),
		"selected_border": Color("#eab308"),
		"legal_dot": Color(0.12, 0.16, 0.22, 0.35),
		"legal_ring": Color(0.92, 0.28, 0.28, 0.88),
		"legal_hover": Color(0.97, 0.92, 0.35, 0.25),
		"last_move": Color("#f7ec5935"),
		"last_move_from": Color("#fef08a38"),
		"last_move_to": Color("#facc1550"),
		"last_move_border": Color("#ca8a0488"),
		"last_move_arrow": Color("#ef4444ee"),
		"check": Color("#ef444488"),
		"check_border": Color("#dc2626"),
		"best_move_arrow": Color("#0284c7"),
		"best_move_arrow_secondary": Color("#38bdf8")
	},
	"slate_modern": {
		"name": "Ardoise Studio",
		"light": Color("#f1f5f9"), # Blanc pur glacé
		"dark": Color("#64748b"),  # Ardoise douce et fine
		"selected": Color(0.22, 0.74, 0.97, 0.35),
		"selected_border": Color("#0ea5e9"),
		"legal_dot": Color(0.08, 0.12, 0.18, 0.35),
		"legal_ring": Color(0.96, 0.30, 0.30, 0.88),
		"legal_hover": Color(0.22, 0.74, 0.97, 0.25),
		"last_move": Color("#38bdf82b"),
		"last_move_from": Color("#bae6fd38"),
		"last_move_to": Color("#38bdf850"),
		"last_move_border": Color("#0284c788"),
		"last_move_arrow": Color("#f43f5eee"),
		"check": Color("#ef444488"),
		"check_border": Color("#dc2626"),
		"best_move_arrow": Color("#10b981"),
		"best_move_arrow_secondary": Color("#06b6d4")
	},
	"wood_luxury": {
		"name": "Bois Précieux",
		"light": Color("#f0d9b5"), # Érable naturel
		"dark": Color("#b58863"),  # Noyer chaud
		"selected": Color(0.38, 0.65, 0.98, 0.35),
		"selected_border": Color("#3b82f6"),
		"legal_dot": Color(0.15, 0.12, 0.10, 0.35),
		"legal_ring": Color(0.92, 0.25, 0.25, 0.88),
		"legal_hover": Color(0.38, 0.65, 0.98, 0.25),
		"last_move": Color("#f59e0b35"),
		"last_move_from": Color("#fde68a38"),
		"last_move_to": Color("#f59e0b50"),
		"last_move_border": Color("#d9770688"),
		"last_move_arrow": Color("#dc2626ee"),
		"check": Color("#ef444488"),
		"check_border": Color("#dc2626"),
		"best_move_arrow": Color("#10b981"),
		"best_move_arrow_secondary": Color("#14b8a6")
	}
}

var board_size: float = 400.0
var square_size: float = 50.0

var piece_sprites: Dictionary = {} # sq -> TextureRect
var piece_textures: Dictionary = {}

var hovered_sq: int = -1
var press_sq: int = -1
var press_pos: Vector2 = Vector2.ZERO
var is_pointer_down: bool = false
var last_touch_timestamp: int = -999999
var last_mouse_timestamp: int = -999999

# Rétrocompatibilité pour les suites de tests et scripts appelants
var dragged_sq: int:
	get: return press_sq
	set(val): press_sq = val
var drag_texture_rect: TextureRect:
	get: return flying_piece

var last_move_from: int = -1
var last_move_to: int = -1
var in_check_sq: int = -1
var check_pulse_timer: float = 0.0

var best_move_arrow_from: int = -1
var best_move_arrow_to: int = -1
var best_move_arrow_depth: int = 0
var show_move_hints: bool = true
## Drapeau piloté par Main.gd pour empêcher _on_engine_eval d'écraser les flèches pendant l'analyse complète
var analysis_in_progress: bool = false

## Calcule une couleur vive et lumineuse sur un dégradé arc-en-ciel selon la profondeur (1 à 20+)
## Profondeur faible (~1-6) : Rouge / Orange / Jaune
## Profondeur moyenne (~7-13) : Vert lime / Émeraude / Cyan
## Profondeur élevée (~14-22+) : Bleu électrique / Indigo / Violet magenta éclatant
static func get_depth_rainbow_color(depth: int) -> Color:
	if depth <= 0:
		return Color("#0284c7")
	# Calibrage : progression de 0.0 (prof. 1) à 1.0 (prof. 20)
	var t = clampf(float(depth - 1) / 19.0, 0.0, 1.0)
	# Déroulé spectral HSV : rouge (0.00) -> orange (0.08) -> jaune (0.15) -> vert (0.33) -> cyan (0.50) -> bleu (0.62) -> magenta (0.83)
	var hue = t * 0.83
	return Color.from_hsv(hue, 0.88, 0.98)

# Système d'animations et effets visuels
class CaptureBurstFX extends Control:
	var center: Vector2 = Vector2.ZERO
	var radius_max: float = 40.0
	var ring_progress: float = 0.0
	var spark_progress: float = 0.0
	var ring_color: Color = Color("#fcd34d")
	var sparks: Array[Dictionary] = []
	
	func _init(p_center: Vector2, p_square_size: float, p_color: Color = Color("#fcd34d")) -> void:
		center = p_center
		radius_max = p_square_size * 0.70
		ring_color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 25
		set_process(true)
		
		var spark_colors = [
			Color("#fbbf24"), # Or brillant
			Color("#f59e0b"), # Ambre chaud
			Color("#ffffff"), # Flash blanc éclatant
			Color("#fed7aa")  # Doré doux
		]
		for i in range(8):
			var angle = (TAU * i / 8.0) + randf_range(-0.25, 0.25)
			var spd = randf_range(0.75, 1.25)
			var sz = randf_range(2.5, 4.2)
			var col = spark_colors[i % spark_colors.size()]
			sparks.append({
				"angle": angle,
				"speed": spd,
				"size": sz,
				"color": col
			})
	
	func _process(_delta: float) -> void:
		queue_redraw()
	
	func _draw() -> void:
		# 1. Onde de choc circulaire
		if ring_progress > 0.0 and ring_progress < 1.0:
			var r = lerpf(radius_max * 0.15, radius_max, ease(ring_progress, 0.35))
			var alpha = 1.0 - ring_progress
			var stroke = lerpf(3.4, 0.6, ring_progress)
			var col = ring_color
			col.a = alpha * 0.90
			draw_arc(center, r, 0, TAU, 36, col, stroke)
			
			# Flash central doux au départ
			if ring_progress < 0.35:
				var flash_col = Color.WHITE
				flash_col.a = (1.0 - (ring_progress / 0.35)) * 0.45
				draw_circle(center, r * 0.5, flash_col)
		
		# 2. Micro-étincelles radiales géométriques
		if spark_progress > 0.0 and spark_progress < 1.0:
			var t = ease(spark_progress, 0.25)
			var alpha = 1.0 - spark_progress
			for sp in sparks:
				var dist = radius_max * sp["speed"] * t
				var p = center + Vector2(cos(sp["angle"]), sin(sp["angle"])) * dist
				var sz = sp["size"] * (1.0 - spark_progress * 0.75)
				var c: Color = sp["color"]
				c.a = alpha * 0.95
				draw_circle(p, sz, c)

# Calque indépendant pour flèches tactiques et de déplacement (z_index=5 au-dessus des pièces)
class ArrowOverlay extends Control:
	var board: ChessBoard2D = null
	
	func _draw() -> void:
		if board:
			board._draw_arrows_on_layer(self)

var active_tweens: Array[Tween] = []
var ghost_sprites: Array[TextureRect] = []
var fx_layer: Control = null
var arrow_overlay: ArrowOverlay = null
var flying_piece: TextureRect = null
var move_anim_duration: float = 0.28
var is_animating_move: bool = false
var displayed_ply_index: int = -1
var _last_flipped_state := false

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
	custom_minimum_size = Vector2(240, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	
	_preload_piece_textures()
	_update_dimensions()
	_create_piece_nodes()
	
	var gc = _get_game_controller()
	if gc:
		displayed_ply_index = gc.current_ply_index
		_last_flipped_state = gc.board_flipped
		gc.move_navigated.connect(_on_move_navigated)
		gc.move_made.connect(_on_move_made)
		gc.position_changed.connect(_on_position_changed)
		gc.game_reset.connect(_on_game_reset)
		gc.square_selected.connect(_on_square_selected)
		gc.square_deselected.connect(_on_square_deselected)
	
	var eng = _get_engine_manager()
	if eng != null:
		eng.evaluation_updated.connect(_on_engine_eval)
	
	var sm = _get_settings_manager()
	if sm != null:
		show_move_hints = sm.get_setting("show_move_hints", true)
		sm.settings_changed.connect(func(key, val):
			if key == "show_move_hints":
				show_move_hints = bool(val)
				_redraw_board_and_overlays()
		)
	
	reset_board_visuals()

func _process(delta: float) -> void:
	if in_check_sq != -1:
		check_pulse_timer += delta * 4.5
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_dimensions()
		if not is_animating_move:
			reset_board_visuals()
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered_sq = -1
		_redraw_board_and_overlays()

func _update_dimensions() -> void:
	var side = min(size.x, size.y)
	if side < 100:
		side = 240
	board_size = side
	square_size = board_size / 8.0
	custom_minimum_size = Vector2(240, 240)
	if arrow_overlay:
		arrow_overlay.size = Vector2(board_size, board_size)
		arrow_overlay.position = Vector2.ZERO
	if fx_layer:
		fx_layer.size = Vector2(board_size, board_size)
		fx_layer.position = Vector2.ZERO

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
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(tr)
		piece_sprites[sq] = tr
	
	# Calque de rendu des flèches tactiques et historiques (z_index=5 au-dessus des pièces statiques)
	arrow_overlay = ArrowOverlay.new()
	arrow_overlay.name = "ArrowOverlay"
	arrow_overlay.board = self
	arrow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_overlay.z_index = 5
	arrow_overlay.size = Vector2(board_size, board_size)
	arrow_overlay.position = Vector2.ZERO
	add_child(arrow_overlay)

	# Node dédié au vol d'animation des pièces (au-dessus du plateau, fluide et stable)
	flying_piece = TextureRect.new()
	flying_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flying_piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flying_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying_piece.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flying_piece.visible = false
	flying_piece.z_index = 32
	add_child(flying_piece)

	# Calque d'effets visuels prioritaires au-dessus des pièces
	fx_layer = Control.new()
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.z_index = 25
	add_child(fx_layer)

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
			if g.get_parent():
				g.get_parent().remove_child(g)
			g.queue_free()
	ghost_sprites.clear()
	
	if is_instance_valid(fx_layer):
		for child in fx_layer.get_children():
			fx_layer.remove_child(child)
			child.queue_free()
	
	var sprite_nodes = piece_sprites.values()
	for child in get_children():
		if child is TextureRect and child != flying_piece and not (child in sprite_nodes):
			remove_child(child)
			child.queue_free()

## Réinitialisation graphique complète et propre du plateau
func reset_board_visuals(preserve_best_move: bool = false) -> void:
	_clear_active_tweens()
	_clear_ghost_sprites()
	is_animating_move = false
	
	if flying_piece:
		flying_piece.visible = false
	
	if not preserve_best_move:
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
	
	# Remise à zéro complète et absolue de toutes les cases
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
	
	# Ré-attribution stricte des pièces actuellement présentes sur l'échiquier
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

# --- SYSTÈME D'ANIMATION PHYSIQUE & EFFETS DE CAPTURE ---

func _animate_move(move: ChessMove) -> void:
	_clear_active_tweens()
	is_animating_move = true
	_clear_ghost_sprites()
	
	var start_pos = _get_square_screen_pos(move.from_sq)
	var end_pos = _get_square_screen_pos(move.to_sq)
	
	# Texture de la pièce en mouvement
	var key = Vector2i(move.piece, move.color)
	var tex = piece_textures.get(key, null)
	if not tex and move.from_sq in piece_sprites:
		tex = piece_sprites[move.from_sq].texture
	
	# Masquer immédiatement les sprites stationnaires du départ et de l'arrivée
	if move.from_sq in piece_sprites:
		piece_sprites[move.from_sq].visible = false
	if move.to_sq in piece_sprites:
		piece_sprites[move.to_sq].visible = false
	
	# Animation du déplacement depuis la case d'origine
	var from_pos = start_pos
	
	# Déclenchement de l'explosion vibrante de capture
	if move.captured_piece != ChessPiece.Type.NONE:
		var cap_sq = move.to_sq
		if move.is_en_passant:
			cap_sq = move.to_sq - 8 if move.color == ChessPiece.PieceColor.WHITE else move.to_sq + 8
		_spawn_capture_fx(cap_sq, move.captured_piece, move.color)
	
	# Animation simultanée du Roque
	if move.is_castling:
		_animate_castling_rook(move)
	
	# Préparation de flying_piece (au premier plan z_index=32)
	flying_piece.texture = tex
	flying_piece.size = Vector2(square_size, square_size)
	flying_piece.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	flying_piece.position = from_pos
	flying_piece.scale = Vector2.ONE
	flying_piece.modulate = Color.WHITE
	flying_piece.visible = true
	
	var anim_time = move_anim_duration
	
	# 1. Glissement spatial fluide vers la destination
	var tween_pos = create_tween()
	active_tweens.append(tween_pos)
	tween_pos.tween_property(flying_piece, "position", end_pos, anim_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 2. Élévation physique en transit (arche de vol) et atterrissage élastique amorti
	var tween_scale = create_tween()
	active_tweens.append(tween_scale)
	tween_scale.tween_property(flying_piece, "scale", Vector2(1.14, 1.14), anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, anim_time * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2(1.05, 0.95), 0.04)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, 0.06)
	
	tween_pos.chain().tween_callback(func():
		is_animating_move = false
		flying_piece.visible = false
		var gctl = _get_game_controller()
		if gctl:
			displayed_ply_index = gctl.current_ply_index
		reset_board_visuals(true)
	)

## Animation fluide vers l'avant lors de la navigation dans l'historique (+1 demi-coup)
func _animate_navigation_forward(move: ChessMove) -> void:
	_clear_active_tweens()
	is_animating_move = true
	_clear_ghost_sprites()
	
	last_move_from = move.from_sq
	last_move_to = move.to_sq
	
	var start_pos = _get_square_screen_pos(move.from_sq)
	var end_pos = _get_square_screen_pos(move.to_sq)
	
	var key = Vector2i(move.piece, move.color)
	var tex = piece_textures.get(key, null)
	
	# Masquer le départ et l'arrivée sur l'échiquier sous-jacent
	if move.from_sq in piece_sprites:
		piece_sprites[move.from_sq].visible = false
	if move.to_sq in piece_sprites:
		piece_sprites[move.to_sq].visible = false
	
	# Effet d'explosion vibrante de capture
	if move.captured_piece != ChessPiece.Type.NONE:
		var cap_sq = move.to_sq
		if move.is_en_passant:
			cap_sq = move.to_sq - 8 if move.color == ChessPiece.PieceColor.WHITE else move.to_sq + 8
		_spawn_capture_fx(cap_sq, move.captured_piece, move.color)
	
	if move.is_castling:
		_animate_castling_rook(move)
	
	flying_piece.texture = tex
	flying_piece.size = Vector2(square_size, square_size)
	flying_piece.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	flying_piece.position = start_pos
	flying_piece.scale = Vector2.ONE
	flying_piece.modulate = Color.WHITE
	flying_piece.visible = true
	
	var anim_time = move_anim_duration
	
	var tween_pos = create_tween()
	active_tweens.append(tween_pos)
	tween_pos.tween_property(flying_piece, "position", end_pos, anim_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var tween_scale = create_tween()
	active_tweens.append(tween_scale)
	tween_scale.tween_property(flying_piece, "scale", Vector2(1.14, 1.14), anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, anim_time * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2(1.04, 0.96), 0.04)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, 0.06)
	
	tween_pos.chain().tween_callback(func():
		is_animating_move = false
		flying_piece.visible = false
		var gctl = _get_game_controller()
		if gctl:
			displayed_ply_index = gctl.current_ply_index
		reset_board_visuals(true)
	)
	queue_redraw()

## Animation fluide vers l'arrière lors de la navigation dans l'historique (-1 demi-coup)
func _animate_navigation_backward(move: ChessMove) -> void:
	_clear_active_tweens()
	is_animating_move = true
	_clear_ghost_sprites()
	
	var start_pos = _get_square_screen_pos(move.to_sq)
	var end_pos = _get_square_screen_pos(move.from_sq)
	
	var key = Vector2i(move.piece, move.color)
	var tex = piece_textures.get(key, null)
	
	if move.from_sq in piece_sprites:
		piece_sprites[move.from_sq].visible = false
	if move.to_sq in piece_sprites:
		piece_sprites[move.to_sq].visible = false
	
	# Réapparition en fondu doux de la pièce capturée qui revient à la vie
	if move.captured_piece != ChessPiece.Type.NONE and move.to_sq in piece_sprites:
		var cap_sprite: TextureRect = piece_sprites[move.to_sq]
		var cap_key = Vector2i(move.captured_piece, 1 - move.color)
		cap_sprite.texture = piece_textures.get(cap_key, null)
		cap_sprite.position = start_pos
		cap_sprite.modulate.a = 0.0
		cap_sprite.scale = Vector2(0.5, 0.5)
		cap_sprite.visible = true
		var cap_tween = create_tween()
		active_tweens.append(cap_tween)
		cap_tween.set_parallel(true)
		cap_tween.tween_property(cap_sprite, "modulate:a", 1.0, move_anim_duration * 0.8)
		cap_tween.tween_property(cap_sprite, "scale", Vector2.ONE, move_anim_duration * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if move.is_castling:
		_animate_reverse_castling_rook(move)
	
	flying_piece.texture = tex
	flying_piece.size = Vector2(square_size, square_size)
	flying_piece.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	flying_piece.position = start_pos
	flying_piece.scale = Vector2.ONE
	flying_piece.modulate = Color.WHITE
	flying_piece.visible = true
	
	var anim_time = move_anim_duration * 0.85
	
	var tween_pos = create_tween()
	active_tweens.append(tween_pos)
	tween_pos.tween_property(flying_piece, "position", end_pos, anim_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	var tween_scale = create_tween()
	active_tweens.append(tween_scale)
	tween_scale.tween_property(flying_piece, "scale", Vector2(1.10, 1.10), anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, anim_time * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	tween_pos.chain().tween_callback(func():
		is_animating_move = false
		flying_piece.visible = false
		var gctl = _get_game_controller()
		if gctl:
			displayed_ply_index = gctl.current_ply_index
		reset_board_visuals()
	)
	queue_redraw()

## Effet d'explosion vibrante, onde de choc et micro-étincelles lors d'une capture
func _spawn_capture_fx(sq: int, cap_type: int, attacker_color: int) -> void:
	var target_center = _get_square_screen_pos(sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	# 1. Onde de choc et micro-étincelles sur fx_layer
	if is_instance_valid(fx_layer):
		var fx = CaptureBurstFX.new(target_center, square_size, Color("#f59e0b"))
		fx_layer.add_child(fx)
		
		var fx_tween = create_tween()
		active_tweens.append(fx_tween)
		fx_tween.set_parallel(true)
		fx_tween.tween_property(fx, "ring_progress", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fx_tween.tween_property(fx, "spark_progress", 1.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fx_tween.chain().tween_callback(func():
			if is_instance_valid(fx):
				if fx.get_parent():
					fx.get_parent().remove_child(fx)
				fx.queue_free()
		)
	
	# 2. Pièce capturée avec vibration tactile d'impact et dissipation douce
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
	var origin_pos = _get_square_screen_pos(sq)
	ghost.position = origin_pos
	ghost.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	ghost.z_index = 8
	add_child(ghost)
	ghost_sprites.append(ghost)
	
	# Sursaut lumineux à l'impact
	ghost.modulate = Color(1.35, 1.25, 1.0, 1.0)
	
	# Animation combinée séquentielle du fantôme : vibration rapide puis dissipation
	var ghost_tween = create_tween()
	active_tweens.append(ghost_tween)
	
	# Étape 1 : Vibration tactile (4 secousses de 0.025s)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(3.5, -2.0), 0.025)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(-3.0, 2.5), 0.025)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(2.0, 1.0), 0.025)
	ghost_tween.tween_property(ghost, "position", origin_pos, 0.025)
	
	# Étape 2 : Dissipation élégante (pop puis rétrécissement et envolée)
	ghost_tween.tween_property(ghost, "scale", Vector2(1.15, 1.15), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var diss_tween = create_tween()
	active_tweens.append(diss_tween)
	diss_tween.set_parallel(true)
	diss_tween.tween_property(ghost, "scale", Vector2(0.35, 0.35), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	diss_tween.tween_property(ghost, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	diss_tween.tween_property(ghost, "position:y", origin_pos.y - 10.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	diss_tween.chain().tween_callback(func():
		if is_instance_valid(ghost):
			ghost_sprites.erase(ghost)
			if ghost.get_parent():
				ghost.get_parent().remove_child(ghost)
			ghost.queue_free()
	)

func _animate_castling_rook(move: ChessMove) -> void:
	var rook_from: int = -1
	var rook_to: int = -1
	
	if move.from_sq == 4 and move.to_sq == 6:
		rook_from = 7; rook_to = 5
	elif move.from_sq == 4 and move.to_sq == 2:
		rook_from = 0; rook_to = 3
	elif move.from_sq == 60 and move.to_sq == 62:
		rook_from = 63; rook_to = 61
	elif move.from_sq == 60 and move.to_sq == 58:
		rook_from = 56; rook_to = 59
	
	if rook_from != -1 and rook_from in piece_sprites:
		var rook_sprite: TextureRect = piece_sprites[rook_from]
		var r_end_pos = _get_square_screen_pos(rook_to)
		rook_sprite.z_index = 18
		var r_tween = create_tween()
		active_tweens.append(r_tween)
		r_tween.tween_property(rook_sprite, "position", r_end_pos, move_anim_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		r_tween.chain().tween_callback(func():
			rook_sprite.z_index = 1
		)

func _animate_reverse_castling_rook(move: ChessMove) -> void:
	var rook_from: int = -1
	var rook_to: int = -1
	
	if move.from_sq == 4 and move.to_sq == 6:
		rook_from = 7; rook_to = 5
	elif move.from_sq == 4 and move.to_sq == 2:
		rook_from = 0; rook_to = 3
	elif move.from_sq == 60 and move.to_sq == 62:
		rook_from = 63; rook_to = 61
	elif move.from_sq == 60 and move.to_sq == 58:
		rook_from = 56; rook_to = 59
	
	if rook_from != -1 and rook_to in piece_sprites:
		var rook_sprite: TextureRect = piece_sprites[rook_to]
		var r_end_pos = _get_square_screen_pos(rook_from)
		rook_sprite.z_index = 18
		var r_tween = create_tween()
		active_tweens.append(r_tween)
		r_tween.tween_property(rook_sprite, "position", r_end_pos, move_anim_duration * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		r_tween.chain().tween_callback(func():
			rook_sprite.z_index = 1
		)

# --- RENDU VISUEL RAFFINÉ & MODERNE ---

func _get_active_theme() -> Dictionary:
	var theme_name = "emerald"
	var sm = _get_settings_manager()
	if sm:
		theme_name = sm.get_setting("board_theme", "emerald")
	return THEMES.get(theme_name, THEMES["emerald"])

func _draw() -> void:
	var theme = _get_active_theme()
	
	var flipped = false
	var gc = _get_game_controller()
	if gc:
		flipped = gc.board_flipped
	
	var font = ThemeDB.fallback_font
	var coord_font_size = int(clampf(square_size * 0.20, 10.0, 20.0))
	var coord_pad = clampf(square_size * 0.05, 3.0, 7.0)

	# 1. Tracé des 64 cases
	for r in range(8):
		for f in range(8):
			var disp_f = (7 - f) if flipped else f
			var disp_r = r if flipped else (7 - r)
			var sq = r * 8 + f
			
			var is_light = ((r + f) % 2 != 0)
			var base_col = theme["light"] if is_light else theme["dark"]
			var rect = Rect2(disp_f * square_size, disp_r * square_size, square_size, square_size)
			
			# Case de fond
			draw_rect(rect, base_col)

			# Dernier coup : différenciation visuelle case de départ et case d'arrivée
			if sq == last_move_from:
				var from_col = theme.get("last_move_from", theme.get("last_move", Color("#fef08a38")))
				draw_rect(rect, from_col)
				var b_w = clampf(square_size * 0.025, 1.0, 2.8)
				draw_rect(rect, theme.get("last_move_border", Color("#ca8a0488")), false, b_w)
			elif sq == last_move_to:
				var to_col = theme.get("last_move_to", theme.get("last_move", Color("#facc1550")))
				draw_rect(rect, to_col)
				var b_w = clampf(square_size * 0.035, 1.5, 3.8)
				draw_rect(rect, theme.get("last_move_border", Color("#ca8a0488")), false, b_w)

			# Case sélectionnée avec fond lumineux chaleureux (sous la pièce)
			if gc and sq == gc.selected_square:
				draw_rect(rect, theme["selected"])
				var b_w = clampf(square_size * 0.035, 1.5, 3.8)
				draw_rect(rect, theme.get("selected_border", Color("#eab308")), false, b_w)

			# Surbrillance subtile au survol d'une case de destination autorisée
			if show_move_hints and gc and gc.selected_square != -1 and sq == hovered_sq and sq in gc.legal_destinations:
				var hov_col = theme.get("legal_hover", Color(1.0, 1.0, 1.0, 0.22))
				draw_rect(rect, hov_col)

			# Roi en échec avec pulsation rougeoyante fine
			if sq == in_check_sq:
				var pulse = (sin(check_pulse_timer) + 1.0) * 0.5
				draw_rect(rect, Color(0.95, 0.2, 0.2, 0.30 + 0.25 * pulse))
				var b_w = clampf(square_size * 0.035, 1.5, 3.8)
				draw_rect(rect, Color(0.9, 0.1, 0.1, 0.85), false, b_w)

			# Coordonnées discrètes et élégantes intégrées aux cases
			if disp_f == 0:
				var rank_num = str(r + 1)
				var text_col = theme["dark"] if is_light else theme["light"]
				text_col.a = 0.72
				var text_pos = rect.position + Vector2(coord_pad, coord_font_size + coord_pad)
				draw_string(font, text_pos, rank_num, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size, text_col)

			if disp_r == 7:
				var file_char = char(97 + f)
				var text_col = theme["dark"] if is_light else theme["light"]
				text_col.a = 0.72
				var text_pos = rect.position + Vector2(square_size - coord_font_size - coord_pad, square_size - coord_pad)
				draw_string(font, text_pos, file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size, text_col)

			# Points de déplacement & anneaux de capture (rendus si pas d'arrow_overlay)
			if show_move_hints and not arrow_overlay and gc and sq in gc.legal_destinations:
				var center = rect.position + rect.size * 0.5
				var piece_on_target = gc.game.get_piece(sq) if gc.game else null
				if piece_on_target and piece_on_target.type != ChessPiece.Type.NONE:
					var ring_w = clampf(square_size * 0.05, 2.0, 5.0)
					draw_arc(center, square_size * 0.43, 0, TAU, 48, theme["legal_ring"], ring_w)
				else:
					draw_circle(center, square_size * 0.16, theme["legal_dot"])

	# 2. Contour fin du plateau
	var outer_b_w = clampf(board_size * 0.003, 1.0, 2.5)
	draw_rect(Rect2(0, 0, board_size, board_size), Color(0.1, 0.15, 0.2, 0.25), false, outer_b_w)

	# 3. Flèches déléguées à arrow_overlay (z_index=5) ou dessinées directement en fallback
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	else:
		_draw_arrows_on_layer(self)

func _draw_arrows_on_layer(ci: CanvasItem) -> void:
	var theme = _get_active_theme()
	var gc = _get_game_controller()

	# 1. Mise en valeur de la sélection et cibles légales (z_index=5 au-dessus des pièces)
	if gc:
		if gc.selected_square != -1:
			var sel_pos = _get_square_screen_pos(gc.selected_square)
			var sel_rect = Rect2(sel_pos, Vector2(square_size, square_size))
			# Bordure nette au premier plan encadrant la pièce sélectionnée
			ci.draw_rect(sel_rect, theme.get("selected_border", Color("#0ea5e9")), false, 2.5)

		if show_move_hints:
			for sq in gc.legal_destinations:
				var center = _get_square_screen_pos(sq) + Vector2(square_size * 0.5, square_size * 0.5)
				var piece_on_target = gc.game.get_piece(sq) if gc.game else null
				if piece_on_target and piece_on_target.type != ChessPiece.Type.NONE:
					# Anneau de capture bien visible au-dessus de la pièce ennemie prenable
					var ring_col = theme.get("legal_ring", Color(0.92, 0.28, 0.28, 0.88))
					ci.draw_arc(center + Vector2(1.0, 1.0), square_size * 0.43, 0, TAU, 48, Color(0, 0, 0, 0.35), 3.5)
					ci.draw_arc(center, square_size * 0.43, 0, TAU, 48, ring_col, 3.5)
				else:
					# Disque discret et lisible pour case vide
					var dot_col = theme.get("legal_dot", Color(0.12, 0.16, 0.22, 0.35))
					ci.draw_circle(center, square_size * 0.16, dot_col)

	# 2. Flèche fine rouge carmin en pointillés du dernier coup joué
	if last_move_from != -1 and last_move_to != -1 and not is_animating_move:
		_draw_last_move_arrow(last_move_from, last_move_to, theme, ci)
	
	# 3. Flèche tactique moderne pour l'analyse Stockfish (meilleur coup)
	if show_move_hints and best_move_arrow_from != -1 and best_move_arrow_to != -1:
		_draw_modern_move_arrow(best_move_arrow_from, best_move_arrow_to, theme, ci)

func _draw_last_move_arrow(from_sq: int, to_sq: int, theme: Dictionary, ci: CanvasItem = null) -> void:
	var canvas: CanvasItem = ci if ci != null else self
	var start_pos = _get_square_screen_pos(from_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	var end_pos = _get_square_screen_pos(to_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	var dir = (end_pos - start_pos).normalized()
	var dist = start_pos.distance_to(end_pos)
	if dist < 1.0:
		return
	
	var arrow_color: Color = theme.get("last_move_arrow", Color("#ef4444ee"))
	var shadow_color: Color = Color(0, 0, 0, 0.35)
	
	# Flèche fine, élégante et distincte de l'évaluation Stockfish ("rouge et fine, en pointillés")
	var shaft_width: float = clampf(square_size * 0.06, 2.5, 6.5)
	var head_length: float = clampf(square_size * 0.24, 10.0, 26.0)
	var head_width: float = clampf(square_size * 0.26, 11.0, 28.0)
	var dash_len: float = clampf(square_size * 0.10, 4.0, 11.0)
	
	var shaft_end = end_pos - dir * (head_length * 0.8)
	var perp = Vector2(-dir.y, dir.x)
	var shadow_offset = Vector2(clampf(square_size * 0.02, 1.2, 2.5), clampf(square_size * 0.02, 1.2, 2.5))
	
	# Disque discret d'origine sur la case de départ
	var start_disc_r = shaft_width * 1.35
	canvas.draw_circle(start_pos + shadow_offset, start_disc_r, shadow_color)
	canvas.draw_circle(start_pos, start_disc_r, arrow_color)
	
	# Fût en pointillés fins
	canvas.draw_dashed_line(start_pos + shadow_offset, shaft_end + shadow_offset, shadow_color, shaft_width, dash_len, true, true)
	canvas.draw_dashed_line(start_pos, shaft_end, arrow_color, shaft_width, dash_len, true, true)
	
	# Tête de flèche fine et pointue sur la case d'arrivée
	var p1 = end_pos
	var p2 = shaft_end + perp * (head_width * 0.5)
	var p3 = shaft_end - perp * (head_width * 0.5)
	
	canvas.draw_colored_polygon(PackedVector2Array([p1 + shadow_offset, p2 + shadow_offset, p3 + shadow_offset]), shadow_color)
	canvas.draw_colored_polygon(PackedVector2Array([p1, p2, p3]), arrow_color)
	canvas.draw_polyline(PackedVector2Array([p2, p1, p3]), Color(1.0, 1.0, 1.0, 0.45), 1.0, true)

func _draw_modern_move_arrow(from_sq: int, to_sq: int, theme: Dictionary, ci: CanvasItem = null) -> void:
	var canvas: CanvasItem = ci if ci != null else self
	var start_pos = _get_square_screen_pos(from_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	var end_pos = _get_square_screen_pos(to_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	var dir = (end_pos - start_pos).normalized()
	var dist = start_pos.distance_to(end_pos)
	if dist < 1.0:
		return
	
	# Gradient arc-en-ciel dynamique selon la profondeur atteinte
	var arrow_color: Color
	if best_move_arrow_depth > 0:
		arrow_color = get_depth_rainbow_color(best_move_arrow_depth)
	else:
		arrow_color = theme.get("best_move_arrow", Color("#0284c7"))

	var shaft_width: float = clampf(square_size * 0.12, 5.0, 14.0)
	var head_length: float = clampf(square_size * 0.35, 15.0, 36.0)
	var head_width: float = clampf(square_size * 0.40, 18.0, 42.0)
	
	var shaft_end = end_pos - dir * (head_length * 0.85)
	var perp = Vector2(-dir.y, dir.x)
	
	# Ombre portée fine
	var shadow_offset = Vector2(clampf(square_size * 0.025, 1.5, 3.0), clampf(square_size * 0.025, 1.5, 3.0))
	canvas.draw_line(start_pos + shadow_offset, shaft_end + shadow_offset, Color(0, 0, 0, 0.25), shaft_width + 2.0, true)
	var shadow_p1 = end_pos + shadow_offset
	var shadow_p2 = shaft_end + shadow_offset + perp * (head_width * 0.5)
	var shadow_p3 = shaft_end + shadow_offset - perp * (head_width * 0.5)
	canvas.draw_colored_polygon(PackedVector2Array([shadow_p1, shadow_p2, shadow_p3]), Color(0, 0, 0, 0.25))
	
	# Corps & Tête avec contour subtil pour lisibilité maximale
	canvas.draw_circle(start_pos, shaft_width * 0.65, arrow_color)
	canvas.draw_line(start_pos, shaft_end, arrow_color, shaft_width, true)
	var p1 = end_pos
	var p2 = shaft_end + perp * (head_width * 0.5)
	var p3 = shaft_end - perp * (head_width * 0.5)
	canvas.draw_colored_polygon(PackedVector2Array([p1, p2, p3]), arrow_color)
	# Filet lumineux blanc discret pour faire ressortir la flèche sur les cases sombres ou claires
	canvas.draw_polyline(PackedVector2Array([p2, p1, p3]), Color(1.0, 1.0, 1.0, 0.45), 1.2, true)

# --- GESTION TACTILE & SOURIS (Clic pour sélectionner, Clic pour déplacer) ---

func _redraw_board_and_overlays() -> void:
	if arrow_overlay:
		arrow_overlay.size = Vector2(board_size, board_size)
		arrow_overlay.position = Vector2.ZERO
		arrow_overlay.queue_redraw()
	queue_redraw()

func _resolve_local_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.position
	return get_local_mouse_position()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# Ignorer les événements tactiles émulés automatiquement suite à un clic souris
		if Time.get_ticks_msec() - last_mouse_timestamp < 350:
			return
		last_touch_timestamp = Time.get_ticks_msec()
		var local_pos = _resolve_local_pos(event)
		var sq = _pos_to_square(local_pos)
		if event.pressed:
			is_pointer_down = true
			press_sq = sq
			press_pos = local_pos
			_handle_pointer_press(sq, local_pos)
		else:
			if is_pointer_down:
				_handle_pointer_release(sq, local_pos)
				is_pointer_down = false
				press_sq = -1
	elif event is InputEventScreenDrag:
		last_touch_timestamp = Time.get_ticks_msec()
	elif event is InputEventMouseButton:
		# Ignorer les événements souris émulés automatiquement suite à un événement tactile
		if Time.get_ticks_msec() - last_touch_timestamp < 350:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			last_mouse_timestamp = Time.get_ticks_msec()
			var local_pos = _resolve_local_pos(event)
			var sq = _pos_to_square(local_pos)
			if event.pressed:
				is_pointer_down = true
				press_sq = sq
				press_pos = local_pos
				_handle_pointer_press(sq, local_pos)
			else:
				if is_pointer_down:
					_handle_pointer_release(sq, local_pos)
					is_pointer_down = false
					press_sq = -1
	elif event is InputEventMouseMotion:
		if Time.get_ticks_msec() - last_touch_timestamp < 350:
			return
		var local_pos = _resolve_local_pos(event)
		var sq = _pos_to_square(local_pos)
		if sq != hovered_sq:
			hovered_sq = sq
			_redraw_board_and_overlays()

func _handle_pointer_press(sq: int, _pos: Vector2) -> void:
	if is_animating_move:
		return
	
	var gc = _get_game_controller()
	if not gc or not gc.game:
		return
	
	if sq == -1:
		if gc.selected_square != -1:
			gc.deselect_square()
			_redraw_board_and_overlays()
		return
	
	# Gestion du coup manuel :
	# Si une pièce est sélectionnée et qu'on clique sur une destination légale :
	if gc.selected_square != -1 and sq in gc.legal_destinations:
		var from_sq = gc.selected_square
		if gc.is_promotion_move(from_sq, sq):
			_show_promotion_dialog(from_sq, sq)
		else:
			gc.try_play_move(from_sq, sq)
		emit_signal("square_clicked", sq)
		_redraw_board_and_overlays()
		return

	# Appel du GameController centralisé :
	# - Re-clic sur la même pièce -> désélectionne (gc.select_square vérifie selected_square == sq)
	# - Clic sur une autre pièce de la même couleur -> change la sélection sur cette pièce
	# - Clic sur une case non autorisée ou vide -> désélectionne
	gc.select_square(sq)
	emit_signal("square_clicked", sq)
	_redraw_board_and_overlays()

func _handle_pointer_release(to_sq: int, pos: Vector2) -> void:
	if is_animating_move:
		return
	
	var gc = _get_game_controller()
	if not gc or not gc.game:
		return
	
	# Gestion du glissé volontaire d'une case de départ vers une case d'arrivée distincte
	if press_sq != -1 and to_sq != -1 and to_sq != press_sq:
		var dist = pos.distance_to(press_pos)
		if dist > square_size * 0.35:
			if gc.selected_square == press_sq and to_sq in gc.legal_destinations:
				if gc.is_promotion_move(press_sq, to_sq):
					_show_promotion_dialog(press_sq, to_sq)
				else:
					gc.try_play_move(press_sq, to_sq)
				_redraw_board_and_overlays()
			# Si relâché ailleurs : ne pas désélectionner, préserve la sélection pour le clic suivant !
	# Si release sur la même case (simple clic/tap) : ne rien faire, la pièce reste sélectionnée !

func _show_promotion_dialog(from_sq: int, to_sq: int) -> void:
	var gc = _get_game_controller()
	if not gc or not gc.game:
		return
	var piece = gc.game.get_piece(from_sq)
	var modal = _PromotionModal.new(piece.color)
	modal.piece_selected.connect(func(chosen_type: int):
		gc.try_play_move(from_sq, to_sq, chosen_type)
		_redraw_board_and_overlays()
	)
	modal.canceled.connect(func():
		gc.deselect_square()
		_redraw_board_and_overlays()
	)
	add_child(modal)
	modal.popup_centered(modal.size)

# Alias de rétrocompatibilité pour les suites de tests
func _handle_press(sq: int, pos: Vector2) -> void:
	press_sq = sq
	press_pos = pos
	_handle_pointer_press(sq, pos)

func _handle_release(to_sq: int, pos: Vector2) -> void:
	_handle_pointer_release(to_sq, pos)
	press_sq = -1

func _pos_to_square(pos: Vector2) -> int:
	if pos.x < 0.0 or pos.x >= board_size or pos.y < 0.0 or pos.y >= board_size:
		return -1
	var f = clampi(int(pos.x / square_size), 0, 7)
	var r = clampi(int(pos.y / square_size), 0, 7)
	var flipped = false
	var gc = _get_game_controller()
	if gc:
		flipped = gc.board_flipped
	var actual_f = (7 - f) if flipped else f
	var actual_r = r if flipped else (7 - r)
	return actual_r * 8 + actual_f

# --- SIGNAUX & MISES À JOUR ---

func _on_game_reset() -> void:
	displayed_ply_index = -1
	reset_board_visuals()

## Journalisation nav (M8) : observable depuis le beta pour diagnostiquer M2.
func _nav_log(msg: String) -> void:
	var t := get_tree()
	if t and t.root and t.root.has_node("AppLogger"):
		t.root.get_node("AppLogger").log("NAV", msg)

func _on_move_navigated(target_ply: int) -> void:
	_nav_log("board ply=%d disp=%d anim=%s" % [
		target_ply, displayed_ply_index, str(is_animating_move)])
	var gc = _get_game_controller()
	if not gc or not gc.game:
		displayed_ply_index = target_ply
		reset_board_visuals()
		return
	
	var total_moves = gc.game.move_history.size()
	
	# 1. Avance d'un demi-coup (+1 ply) : véritable glissement vers l'avant avec FX capture
	if target_ply == displayed_ply_index + 1 and target_ply >= 0 and target_ply < total_moves:
		var move = gc.game.move_history[target_ply]
		displayed_ply_index = target_ply
		last_move_from = move.from_sq
		last_move_to = move.to_sq
		_animate_navigation_forward(move)
		return
	# 2. Recul d'un demi-coup (-1 ply) : véritable glissement inverse vers l'arrière
	elif target_ply == displayed_ply_index - 1 and displayed_ply_index >= 0 and displayed_ply_index < total_moves:
		var move = gc.game.move_history[displayed_ply_index]
		displayed_ply_index = target_ply
		if target_ply >= 0 and target_ply < total_moves:
			var prev_m = gc.game.move_history[target_ply]
			last_move_from = prev_m.from_sq
			last_move_to = prev_m.to_sq
		else:
			last_move_from = -1
			last_move_to = -1
		_animate_navigation_backward(move)
		return
	
	# 3. Saut distant ou réinitialisation : mise à jour nette
	displayed_ply_index = target_ply
	reset_board_visuals()

func _on_position_changed() -> void:
	var gc = _get_game_controller()
	var flipped := bool(gc.board_flipped) if gc else false
	if flipped != _last_flipped_state:
		_last_flipped_state = flipped
		# Retournement pendant une animation : annuler proprement (M2 / D2).
		if is_animating_move:
			_clear_active_tweens()
			is_animating_move = false
	elif is_animating_move:
		return
	if gc:
		displayed_ply_index = gc.current_ply_index
	reset_board_visuals()

func _on_square_selected(_sq: int, _moves: Array) -> void:
	_redraw_board_and_overlays()

func _on_square_deselected() -> void:
	_redraw_board_and_overlays()

func _on_move_made(move: ChessMove) -> void:
	var gc = _get_game_controller()
	if gc:
		displayed_ply_index = gc.current_ply_index
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

func _on_engine_eval(_score_cp: int, _mate_in: int, depth: int, best_move: String, _pv: Array, _multipv: Array) -> void:
	# Pendant l'analyse complète, les flèches sont pilotées par _on_ply_analyzed dans Main.gd.
	# On ne touche pas aux flèches ici pour éviter la désynchronisation avec la position affichée.
	if analysis_in_progress:
		return
	best_move_arrow_depth = depth
	if best_move.length() >= 4:
		best_move_arrow_from = ChessMove.coord_to_square(best_move.substr(0, 2))
		best_move_arrow_to = ChessMove.coord_to_square(best_move.substr(2, 2))
	else:
		best_move_arrow_from = -1
		best_move_arrow_to = -1
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()


