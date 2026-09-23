class_name ChessBoard2D
extends Control
## ChessBoard2D.gd - Affichage et interaction tactile 2D haute définition avec animations fluides, glissement physique et thèmes modernes

const _PromotionModal = preload("res://src/ui/components/PromotionModal.gd")

# Garde-fou minimal (simple sécurité) : le plateau est borné par ses bandeaux et
# doit pouvoir rétrécir pour tenir dans l'espace disponible (aucun minimum 240px).
const MIN_BOARD_SIDE := 48.0

## Espace entre la barre d'évaluation et le bord gauche du plateau (groupe accolé).
const EVAL_BAR_GAP := 6.0

# Accélération des animations pendant l'analyse automatisée : les mouvements restent
# pleinement visibles (glissement + rebond d'échelle + capture), mais à durée réduite
# pour ne pas immobiliser le thread d'analyse. 0,5 => 0,14 s par coup au lieu de 0,28 s.
const ANALYSIS_FAST_ANIM_SCALE := 0.5

signal square_clicked(sq: int)
signal navigation_forward_completed(ply_idx: int)

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

## Barre d'évaluation sœur (EvalBar) accolée au bord gauche du plateau, si présente.
var eval_bar_ref: Control = null

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

var best_move_arrow_from: int = -1
var best_move_arrow_to: int = -1
var best_move_arrow_depth: int = 0
## FEN associé à la flèche courante : un rafraîchissement graphique ne doit pas
## effacer une flèche encore valable pour la position affichée.
var best_move_arrow_fen: String = ""
var engine_lines_arrows: Array[Dictionary] = []
var show_move_hints: bool = true

# T2.1 — Annotations utilisateur (flèches clic droit / Maj+glisser, cercles par clic simple).
signal user_annotations_changed
var user_arrows: Array = []
var user_circles: Array = []
var _ann_from: int = -1

# Aperçu temporaire (ex. CHESS-CLIFF « Super Live ») : affiche une position
# arbitraire SANS jamais altérer la partie réelle (historique des coups, courbe,
# liste des coups et analyses restent intacts).
var preview_fen: String = ""
var _preview_game: ChessGame = null
var _preview_banner: Button = null

# Calque « Rayons X » CHESS-CLIFF : meilleur coup + appât + cases-mines, dessiné
# sans jamais toucher l'état de la partie.
var cliff_overlay: Dictionary = {}
var _cliff_label: Label = null

## Calcule une couleur vive et lumineuse sur un dégradé arc-en-ciel selon la profondeur (1 à 20+)
## Profondeur faible (~1-6) : Rouge / Orange / Jaune
## Profondeur moyenne (~7-13) : Vert lime / Émeraude / Cyan
## Profondeur élevée (~14-22+) : Bleu électrique / Indigo / Violet magenta éclatant
static func get_depth_rainbow_color(depth: int) -> Color:
	if depth <= 0:
		return Color("#0284c7")
	# Calibrage : progression de 0.0 (prof. 1) à 1.0 (prof. 20)
	var t = clampf(float(depth - 1) / 19.0, 0.0, 1.0)
	# Déroulé HSV orange (0.08) → vert → cyan → bleu → violet (0.78). Le rouge est
	# volontairement exclu : il désigne la flèche du dernier coup joué.
	var hue = 0.08 + t * 0.70
	return Color.from_hsv(hue, 0.85, 0.97)

# Système d'animations et effets visuels
class CaptureBurstFX extends Control:
	var center: Vector2 = Vector2.ZERO
	var radius_max: float = 40.0
	var ring_progress: float = 0.0:
		set(v):
			ring_progress = v
			queue_redraw()
	var spark_progress: float = 0.0:
		set(v):
			spark_progress = v
			queue_redraw()
	var ring_color: Color = Color("#fcd34d")
	var sparks: Array[Dictionary] = []
	
	func _init(p_center: Vector2, p_square_size: float, p_color: Color = Color("#fcd34d")) -> void:
		center = p_center
		radius_max = p_square_size * 0.70
		ring_color = p_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 25
		
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
	
	func _draw() -> void:
		# 1. Onde de choc circulaire
		if ring_progress > 0.0 and ring_progress < 1.0:
			var r = lerpf(radius_max * 0.15, radius_max, ease(ring_progress, 0.35))
			var alpha = 1.0 - ring_progress
			var stroke = lerpf(3.4, 0.6, ring_progress)
			var col = ring_color
			col.a = alpha * 0.90
			draw_arc(center, r, 0, TAU, DesignTokens.arc_segments(r), col, stroke, true)
			
			# Flash central doux au départ
			if ring_progress < 0.35:
				var flash_col = Color.WHITE
				flash_col.a = (1.0 - (ring_progress / 0.35)) * 0.45
				draw_circle(center, r * 0.5, flash_col, true, -1.0, true)
		
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
				draw_circle(p, sz, c, true, -1.0, true)

# Calque de pulsation du roi en échec : seule cette case se redessine à chaque image,
# le plateau complet n'est plus repeint en continu pendant un échec.
class CheckPulseLayer extends Control:
	var board: ChessBoard2D = null
	var timer: float = 0.0

	func _process(delta: float) -> void:
		timer += delta * 4.5
		queue_redraw()

	func _draw() -> void:
		if board == null or board.in_check_sq < 0:
			return
		var rect := Rect2(board._get_square_screen_pos(board.in_check_sq), Vector2.ONE * board.square_size)
		var pulse := (sin(timer) + 1.0) * 0.5
		draw_rect(rect, Color(DesignTokens.CHECK_GLOW, 0.30 + 0.25 * pulse))
		board._outline_rect(self, rect, DesignTokens.CHECK_BORDER, clampf(board.square_size * 0.035, 1.5, 3.8))

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
var check_layer: CheckPulseLayer = null
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
	custom_minimum_size = Vector2(MIN_BOARD_SIDE, MIN_BOARD_SIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_preload_piece_textures()
	eval_bar_ref = get_parent().get_node_or_null("EvalBar") as Control
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
			elif key == "board_theme":
				_redraw_board_and_overlays()
		)

	var host := get_parent()
	if host is Control and not (host as Control).resized.is_connected(_on_host_resized):
		(host as Control).resized.connect(_on_host_resized)

	reset_board_visuals()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_dimensions()
		if not is_animating_move:
			reset_board_visuals()
	elif what == NOTIFICATION_MOUSE_EXIT:
		hovered_sq = -1
		_redraw_board_and_overlays()

func _update_dimensions() -> void:
	# Zone = BoardContainer, la région strictement entre les bandeaux joueurs.
	# Le plateau est un carré : il vise la pleine largeur de la zone et plafonne à
	# la hauteur disponible. La barre d'évaluation (EvalBar) est accolée à sa gauche
	# et l'ensemble « barre + plateau » est centré horizontalement dans la zone,
	# si bien qu'aucun espace mort n'apparaît le long du plateau.
	var p := get_parent() as Control
	var avail := Vector2(size.x, size.y)
	if p != null and p.size.x > 0.0 and p.size.y > 0.0:
		avail = p.size
	var bar_w := 0.0
	if eval_bar_ref != null and is_instance_valid(eval_bar_ref) and eval_bar_ref.visible:
		bar_w = maxf(0.0, eval_bar_ref.custom_minimum_size.x)
	var group_extra := EVAL_BAR_GAP + bar_w if bar_w > 0.0 else 0.0
	var side = minf(avail.y, avail.x - group_extra)
	if side < MIN_BOARD_SIDE:
		side = MIN_BOARD_SIDE
	board_size = side
	square_size = board_size / 8.0
	_reposition_cliff_label()
	_reposition_preview_banner()
	if arrow_overlay:
		arrow_overlay.size = Vector2(board_size, board_size)
		arrow_overlay.position = Vector2.ZERO
	if fx_layer:
		fx_layer.size = Vector2(board_size, board_size)
		fx_layer.position = Vector2.ZERO
	# Centre le groupe « barre + plateau » dans sa zone (contrôle ancré plein rect).
	if p != null and p.size.x > 0.0 and p.size.y > 0.0:
		var group_w := board_size + group_extra
		var left_pad := (avail.x - group_w) * 0.5 + group_extra
		var half_y := (avail.y - board_size) * 0.5
		offset_left = left_pad
		offset_top = half_y
		offset_right = -(avail.x - left_pad - board_size)
		offset_bottom = -half_y
		_position_eval_bar(p.size.x, left_pad, group_extra > 0.0, half_y)

## Accole la barre d'évaluation au bord gauche du plateau, à sa hauteur exacte.
## NB : parent_width est requis car offset_right/offset_bottom sont relatifs aux
## anchors droit/bas (plein rect), pas au bord gauche du conteneur.
func _position_eval_bar(parent_w: float, board_left: float, has_bar: bool, half_y: float) -> void:
	if eval_bar_ref == null or not is_instance_valid(eval_bar_ref):
		return
	if not has_bar:
		return
	eval_bar_ref.offset_left = board_left - EVAL_BAR_GAP - eval_bar_ref.custom_minimum_size.x
	eval_bar_ref.offset_right = board_left - EVAL_BAR_GAP - parent_w
	eval_bar_ref.offset_top = half_y
	eval_bar_ref.offset_bottom = -half_y

## Recalcule la taille du plateau quand son conteneur (BoardContainer) change de
## dimensions : c'est là qu'est fixée la vraie place entre les bandeaux joueurs.
func _on_host_resized() -> void:
	if not is_inside_tree():
		return
	_update_dimensions()
	if not is_animating_move:
		reset_board_visuals()

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
	# Ajouté avant les pièces : la pulsation d'échec reste sous le roi.
	check_layer = CheckPulseLayer.new()
	check_layer.board = self
	check_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	check_layer.size = Vector2(board_size, board_size)
	check_layer.set_process(false)
	add_child(check_layer)

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

## Vrai lorsqu'une position d'aperçu (Cliff) est affichée à la place de la partie.
func is_previewing() -> bool:
	return preview_fen != ""

## Affiche une position d'aperçu sans toucher à GameController.game (donc sans
## effacer l'historique des coups). Utilisé par CHESS-CLIFF « Super Live ».
func set_preview_fen(fen: String) -> void:
	if fen == "":
		clear_preview_fen()
		return
	preview_fen = fen
	if _preview_game == null:
		_preview_game = ChessGame.new()
	_preview_game.load_fen(fen)
	last_move_from = -1
	last_move_to = -1
	_update_preview_banner()
	reset_board_visuals()
	queue_redraw()

## Quitte l'aperçu et réaffiche la position réelle de la partie.
func clear_preview_fen() -> void:
	if preview_fen == "":
		return
	preview_fen = ""
	_update_preview_banner()
	reset_board_visuals()
	queue_redraw()

## Met à jour le bandeau flottant d'aperçu variante
func _update_preview_banner() -> void:
	if not is_instance_valid(_preview_banner):
		if not is_previewing():
			return
		_preview_banner = Button.new()
		_preview_banner.z_index = 45
		_preview_banner.mouse_filter = Control.MOUSE_FILTER_STOP
		_preview_banner.text = "👁️ Aperçu variante · Touchez pour quitter"
		_preview_banner.add_theme_font_size_override("font_size", 11)
		_preview_banner.add_theme_color_override("font_color", Color("#f5f3ff"))
		_preview_banner.add_theme_color_override("font_hover_color", Color.WHITE)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.10, 0.07, 0.18, 0.94)
		sb.border_color = Color("#c084fc")
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(12)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		_preview_banner.add_theme_stylebox_override("normal", sb)
		_preview_banner.add_theme_stylebox_override("hover", sb)
		_preview_banner.add_theme_stylebox_override("pressed", sb)
		_preview_banner.pressed.connect(func():
			clear_preview_fen()
			clear_cliff_overlay()
		)
		add_child(_preview_banner)

	if not is_previewing():
		_preview_banner.visible = false
		_reposition_cliff_label()
		return

	_preview_banner.visible = true
	_reposition_preview_banner()
	_reposition_cliff_label()

func _reposition_preview_banner() -> void:
	if is_instance_valid(_preview_banner) and _preview_banner.visible:
		_preview_banner.reset_size()
		_preview_banner.position = Vector2(maxf(4.0, (board_size - _preview_banner.size.x) * 0.5), 4.0)

## Active/désactive le calque Rayons X CHESS-CLIFF.
func set_cliff_overlay(data: Dictionary) -> void:
	cliff_overlay = data.duplicate(true)
	_update_cliff_label()
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()

func clear_cliff_overlay() -> void:
	if cliff_overlay.is_empty():
		return
	cliff_overlay = {}
	_update_cliff_label()
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()

func is_cliff_overlay_active() -> bool:
	return not cliff_overlay.is_empty()

func _update_cliff_label() -> void:
	if not is_instance_valid(_cliff_label):
		if cliff_overlay.is_empty():
			return
		_cliff_label = Label.new()
		_cliff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cliff_label.z_index = 40
		_cliff_label.add_theme_font_size_override("font_size", 12)
		_cliff_label.add_theme_color_override("font_color", Color("#e9d5ff"))
		add_child(_cliff_label)
	if cliff_overlay.is_empty():
		_cliff_label.visible = false
		return
	_cliff_label.text = str(cliff_overlay.get("label", ""))
	_cliff_label.visible = _cliff_label.text != ""
	_cliff_label.reset_size()
	_reposition_cliff_label()

## Réaligne le bandeau Rayons X après un changement de taille du plateau.
func _reposition_cliff_label() -> void:
	if is_instance_valid(_cliff_label) and _cliff_label.visible:
		var top_y := 30.0 if (is_instance_valid(_preview_banner) and _preview_banner.visible) else 4.0
		_cliff_label.position = Vector2(maxf(4.0, (board_size - _cliff_label.size.x) * 0.5), top_y)

## Réinitialisation graphique complète et propre du plateau
func reset_board_visuals(preserve_best_move: bool = false) -> void:
	_clear_active_tweens()
	_clear_ghost_sprites()
	is_animating_move = false
	
	if flying_piece:
		flying_piece.visible = false

	var gc = _get_game_controller()
	var src_game: ChessGame = null
	if is_previewing():
		src_game = _preview_game
	elif gc and gc.game:
		src_game = gc.game

	if not preserve_best_move:
		var current_fen: String = src_game.get_fen() if src_game else ""
		if best_move_arrow_fen != current_fen:
			best_move_arrow_from = -1
			best_move_arrow_to = -1
			best_move_arrow_fen = ""
			engine_lines_arrows.clear()

	if not is_previewing() and gc and src_game \
			and gc.current_ply_index >= 0 and gc.current_ply_index < src_game.move_history.size():
		var m = src_game.move_history[gc.current_ply_index]
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

	# Ré-attribution stricte des pièces de la source affichée (aperçu ou partie)
	if src_game:
		for sq in range(64):
			var piece = src_game.get_piece(sq)
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

## Animation fluide vers l'avant lors de la navigation dans l'historique (+1 demi-coup).
## `fast_analysis_mode` : animations accélérées (mais pleinement fonctionnelles) pendant
## l'analyse automatisée, afin de ne pas immobiliser le thread d'analyse.
func _animate_navigation_forward(move: ChessMove, fast_analysis_mode: bool = false) -> void:
	_clear_active_tweens()
	is_animating_move = true
	_clear_ghost_sprites()
	
	last_move_from = move.from_sq
	last_move_to = move.to_sq
	var anim_scale := ANALYSIS_FAST_ANIM_SCALE if fast_analysis_mode else 1.0
	
	var start_pos = _get_square_screen_pos(move.from_sq)
	var end_pos = _get_square_screen_pos(move.to_sq)
	
	var key = Vector2i(move.piece, move.color)
	var tex = piece_textures.get(key, null)
	
	# Masquer le départ et l'arrivée sur l'échiquier sous-jacent
	if move.from_sq in piece_sprites:
		piece_sprites[move.from_sq].visible = false
	if move.to_sq in piece_sprites:
		piece_sprites[move.to_sq].visible = false
	
	# Effet d'explosion vibrante de capture (accéléré en analyse)
	if move.captured_piece != ChessPiece.Type.NONE:
		var cap_sq = move.to_sq
		if move.is_en_passant:
			cap_sq = move.to_sq - 8 if move.color == ChessPiece.PieceColor.WHITE else move.to_sq + 8
		_spawn_capture_fx(cap_sq, move.captured_piece, move.color, anim_scale)
	
	if move.is_castling:
		_animate_castling_rook(move, anim_scale)
	
	flying_piece.texture = tex
	flying_piece.size = Vector2(square_size, square_size)
	flying_piece.pivot_offset = Vector2(square_size * 0.5, square_size * 0.5)
	flying_piece.position = start_pos
	flying_piece.scale = Vector2.ONE
	flying_piece.modulate = Color.WHITE
	flying_piece.visible = true
	
	var anim_time = move_anim_duration * anim_scale
	
	var tween_pos = create_tween()
	active_tweens.append(tween_pos)
	tween_pos.tween_property(flying_piece, "position", end_pos, anim_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Glissement vertical léger et rebond d'atterrissage (accéléré en analyse)
	var tween_scale = create_tween()
	active_tweens.append(tween_scale)
	tween_scale.tween_property(flying_piece, "scale", Vector2(1.14, 1.14), anim_time * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, anim_time * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2(1.04, 0.96), 0.04 * anim_scale)
	tween_scale.chain().tween_property(flying_piece, "scale", Vector2.ONE, 0.06 * anim_scale)
	
	tween_pos.chain().tween_callback(func():
		is_animating_move = false
		flying_piece.visible = false
		var gctl = _get_game_controller()
		if gctl:
			displayed_ply_index = gctl.current_ply_index
		reset_board_visuals(true)
		navigation_forward_completed.emit(displayed_ply_index)
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

## Effet d'explosion vibrante, onde de choc et micro-étincelles lors d'une capture.
## `time_scale` accélère l'ensemble des durées (analyse automatisée).
func _spawn_capture_fx(sq: int, cap_type: int, attacker_color: int, time_scale: float = 1.0) -> void:
	var target_center = _get_square_screen_pos(sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	# 1. Onde de choc et micro-étincelles sur fx_layer
	if is_instance_valid(fx_layer):
		var fx = CaptureBurstFX.new(target_center, square_size, Color("#f59e0b"))
		fx_layer.add_child(fx)
		
		var fx_tween = create_tween()
		active_tweens.append(fx_tween)
		fx_tween.set_parallel(true)
		fx_tween.tween_property(fx, "ring_progress", 1.0, 0.32 * time_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fx_tween.tween_property(fx, "spark_progress", 1.0, 0.36 * time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	
	# Étape 1 : Vibration tactile (4 secousses)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(3.5, -2.0), 0.025 * time_scale)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(-3.0, 2.5), 0.025 * time_scale)
	ghost_tween.tween_property(ghost, "position", origin_pos + Vector2(2.0, 1.0), 0.025 * time_scale)
	ghost_tween.tween_property(ghost, "position", origin_pos, 0.025 * time_scale)
	
	# Étape 2 : Dissipation élégante (pop puis rétrécissement et envolée)
	ghost_tween.tween_property(ghost, "scale", Vector2(1.15, 1.15), 0.06 * time_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	var diss_tween = create_tween()
	active_tweens.append(diss_tween)
	diss_tween.set_parallel(true)
	diss_tween.tween_property(ghost, "scale", Vector2(0.35, 0.35), 0.22 * time_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	diss_tween.tween_property(ghost, "modulate:a", 0.0, 0.24 * time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	diss_tween.tween_property(ghost, "position:y", origin_pos.y - 10.0, 0.24 * time_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	diss_tween.chain().tween_callback(func():
		if is_instance_valid(ghost):
			ghost_sprites.erase(ghost)
			if ghost.get_parent():
				ghost.get_parent().remove_child(ghost)
			ghost.queue_free()
	)

func _animate_castling_rook(move: ChessMove, time_scale: float = 1.0) -> void:
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
		r_tween.tween_property(rook_sprite, "position", r_end_pos, move_anim_duration * time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	# Tolérer les anciennes valeurs renommées (bug historique : clés inconnues → repli emerald)
	if theme_name == "dark_modern":
		theme_name = "slate_modern"
	elif theme_name == "wood":
		theme_name = "wood_luxury"
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
				draw_rect(rect, theme["last_move_from"])
				_outline_rect(self, rect, theme["last_move_border"], clampf(square_size * 0.025, 1.0, 2.8))
			elif sq == last_move_to:
				draw_rect(rect, theme["last_move_to"])
				_outline_rect(self, rect, theme["last_move_border"], clampf(square_size * 0.035, 1.5, 3.8))

			# Case sélectionnée avec fond lumineux chaleureux (sous la pièce)
			if gc and not is_previewing() and sq == gc.selected_square:
				draw_rect(rect, theme["selected"])
				_outline_rect(self, rect, theme["selected_border"], clampf(square_size * 0.035, 1.5, 3.8))

			# Surbrillance subtile au survol d'une case de destination autorisée
			if show_move_hints and not is_previewing() and gc and gc.selected_square != -1 and sq == hovered_sq and sq in gc.legal_destinations:
				draw_rect(rect, theme["legal_hover"])
			# (La pulsation du roi en échec est rendue par check_layer.)

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
				var file_w := font.get_string_size(file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size).x
				var text_pos = rect.position + Vector2(square_size - file_w - coord_pad, square_size - coord_pad)
				draw_string(font, text_pos, file_char, HORIZONTAL_ALIGNMENT_LEFT, -1, coord_font_size, text_col)

			# Points de déplacement & anneaux de capture (rendus si pas d'arrow_overlay)
			if show_move_hints and not is_previewing() and not arrow_overlay and gc and sq in gc.legal_destinations:
				var center = rect.position + rect.size * 0.5
				var piece_on_target = gc.game.get_piece(sq) if gc.game else null
				if piece_on_target and piece_on_target.type != ChessPiece.Type.NONE:
					var ring_w = clampf(square_size * 0.05, 2.0, 5.0)
					var ring_r := square_size * 0.43
					draw_arc(center, ring_r, 0, TAU, DesignTokens.arc_segments(ring_r), theme["legal_ring"], ring_w, true)
				else:
					draw_circle(center, square_size * 0.16, theme["legal_dot"], true, -1.0, true)

	# 2. Contour fin du plateau
	_outline_rect(self, Rect2(0, 0, board_size, board_size), Color(0.1, 0.15, 0.2, 0.25), clampf(board_size * 0.003, 1.0, 2.5))

	# 3. Flèches déléguées à arrow_overlay (z_index=5) ou dessinées directement en fallback
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	else:
		_draw_arrows_on_layer(self)

func _draw_arrows_on_layer(ci: CanvasItem) -> void:
	var theme = _get_active_theme()
	var gc = _get_game_controller()

	# 1. Mise en valeur de la sélection et cibles légales (z_index=5 au-dessus des pièces)
	if gc and not is_previewing():
		if gc.selected_square != -1:
			var sel_pos = _get_square_screen_pos(gc.selected_square)
			var sel_rect = Rect2(sel_pos, Vector2(square_size, square_size))
			# Bordure nette au premier plan encadrant la pièce sélectionnée
			_outline_rect(ci, sel_rect, theme["selected_border"], 2.5)

		if show_move_hints:
			for sq in gc.legal_destinations:
				var center = _get_square_screen_pos(sq) + Vector2(square_size * 0.5, square_size * 0.5)
				var piece_on_target = gc.game.get_piece(sq) if gc.game else null
				if piece_on_target and piece_on_target.type != ChessPiece.Type.NONE:
					# Anneau de capture bien visible au-dessus de la pièce ennemie prenable
					var ring_r := square_size * 0.43
					var seg := DesignTokens.arc_segments(ring_r)
					ci.draw_arc(center + Vector2(1.0, 1.0), ring_r, 0, TAU, seg, Color(0, 0, 0, 0.35), 3.5, true)
					ci.draw_arc(center, ring_r, 0, TAU, seg, theme["legal_ring"], 3.5, true)
				else:
					# Disque discret et lisible pour case vide
					ci.draw_circle(center, square_size * 0.16, theme["legal_dot"], true, -1.0, true)

	# 2. Flèche fine rouge carmin en pointillés du dernier coup joué
	if last_move_from != -1 and last_move_to != -1 and not is_animating_move:
		_draw_last_move_arrow(last_move_from, last_move_to, theme, ci)
	
	# 3. Flèches tactiques modernes pour l'analyse Stockfish (masquées si le calque Cliff est actif)
	if show_move_hints and cliff_overlay.is_empty():
		if not engine_lines_arrows.is_empty():
			var total_lines = engine_lines_arrows.size()
			# On dessine les flèches du rang le plus élevé vers le rang 1 pour que le #1 apparaisse au premier plan
			for idx in range(engine_lines_arrows.size() - 1, -1, -1):
				var arr: Dictionary = engine_lines_arrows[idx]
				var from_sq: int = int(arr.get("from", -1))
				var to_sq: int = int(arr.get("to", -1))
				var rank: int = int(arr.get("rank", idx + 1))
				var badge_num := rank if total_lines > 1 else 0
				_draw_modern_move_arrow(from_sq, to_sq, theme, ci, badge_num, rank)
		elif best_move_arrow_from != -1 and best_move_arrow_to != -1:
			_draw_modern_move_arrow(best_move_arrow_from, best_move_arrow_to, theme, ci)

	# 4. T2.1 — Annotations utilisateur (persistées avec la partie).
	for a in user_arrows:
		_draw_user_arrow(int(a.get("from", -1)), int(a.get("to", -1)), ci)
	for sq in user_circles:
		var center = _get_square_screen_pos(int(sq)) + Vector2(square_size * 0.5, square_size * 0.5)
		var circ_r := square_size * 0.42
		ci.draw_arc(center, circ_r, 0, TAU, DesignTokens.arc_segments(circ_r), DesignTokens.USER_MARK, 3.0, true)

	# 5. Rayons X CHESS-CLIFF : cases-mines, coup le plus séduisant, meilleur coup.
	if not cliff_overlay.is_empty():
		_draw_cliff_overlay(ci)

## Dessine le calque Rayons X (non destructif).
func _draw_cliff_overlay(ci: CanvasItem) -> void:
	# 1. Cases empoisonnées (Chute critique / Coup unique vital) :
	# Croix rouge carmin stylisée sur chaque case fatale pour matérialiser le gouffre
	for sq in cliff_overlay.get("poisoned_squares", []):
		var sq_idx := int(sq)
		if sq_idx < 0 or sq_idx >= 64:
			continue
		var p := _get_square_screen_pos(sq_idx)
		var cross_col := DesignTokens.CLIFF_POISON
		ci.draw_rect(Rect2(p + Vector2(2, 2), Vector2(square_size - 4.0, square_size - 4.0)), Color(cross_col, 0.18))
		var m_pad := square_size * 0.30
		ci.draw_line(p + Vector2(m_pad, m_pad), p + Vector2(square_size - m_pad, square_size - m_pad), cross_col, 2.5, true)
		ci.draw_line(p + Vector2(square_size - m_pad, m_pad), p + Vector2(m_pad, square_size - m_pad), cross_col, 2.5, true)

	# 2. Cases-mines : cadre ambre sur la bordure de case (n'occulte pas la pièce)
	# + point discret en coin, opacité proportionnelle au poids du piège.
	for mine in cliff_overlay.get("mines", []):
		var sq := int(mine.get("sq", -1))
		if sq < 0 or sq >= 64:
			continue
		var w := clampf(float(mine.get("weight", 0.5)), 0.0, 1.0)
		var pos = _get_square_screen_pos(sq)
		var col := Color(DesignTokens.CLIFF_MINE, 0.30 + 0.55 * w)
		_outline_rect(ci, Rect2(pos, Vector2.ONE * square_size), col, 2.5)
		ci.draw_circle(pos + Vector2(square_size * 0.16, square_size * 0.16), square_size * 0.06, col, true, -1.0, true)

	# 3. Flèches moteur (meilleur coup + appât) : respectent l'option « aides de coups ».
	if show_move_hints:
		var best_uci := str(cliff_overlay.get("best_uci", ""))
		var bait_uci := str(cliff_overlay.get("bait_uci", ""))
		var is_vital := bool(cliff_overlay.get("is_vital", false))
		var nature := int(cliff_overlay.get("move_nature", -1))

		if bait_uci.length() >= 4 and bait_uci != best_uci:
			_draw_cliff_arrow(bait_uci, DesignTokens.CLIFF_BAIT, 0.85, true, ci)
		if best_uci.length() >= 4:
			var key := CliffTypes.MoveNature.VITAL if is_vital else nature
			var arrow_col: Color = DesignTokens.NATURE_ARROW.get(key, DesignTokens.NATURE_ARROW[CliffTypes.MoveNature.SAFE])
			_draw_cliff_arrow(best_uci, arrow_col, 1.15 if is_vital else 1.1, false, ci)

func _draw_cliff_arrow(uci: String, color: Color, width_scale: float, dashed: bool, ci: CanvasItem) -> void:
	var from_sq := ChessMove.coord_to_square(uci.substr(0, 2))
	var to_sq := ChessMove.coord_to_square(uci.substr(2, 2))
	if from_sq < 0 or to_sq < 0:
		return
	_draw_arrow(ci, _square_center(from_sq), _square_center(to_sq), color, {
		"shaft": clampf(square_size * 0.08, 4.0, 11.0) * width_scale,
		"head_len": clampf(square_size * 0.28, 12.0, 30.0),
		"head_w": clampf(square_size * 0.32, 14.0, 34.0),
		"dashed": dashed,
	})

func _square_center(sq: int) -> Vector2:
	return _get_square_screen_pos(sq) + Vector2(square_size * 0.5, square_size * 0.5)

## Contour de rectangle tracé À L'INTÉRIEUR du rectangle (un contour Godot est
## centré sur le bord : sans décalage il déborderait sur les cases voisines).
func _outline_rect(ci: CanvasItem, rect: Rect2, color: Color, width: float) -> void:
	ci.draw_rect(rect.grow(-width * 0.5), color, false, width)

## Primitive unique de flèche (fût + tête triangulaire), options :
## shaft, head_len, head_w (px) ; dashed ; shadow (décalage px, 0 = aucune) ;
## origin_disc (rayon du disque de départ, 0 = aucun) ; rim (filet clair sur la tête).
func _draw_arrow(ci: CanvasItem, start: Vector2, end: Vector2, color: Color, o: Dictionary) -> void:
	if start.distance_to(end) < 1.0:
		return
	var dir := (end - start).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var shaft: float = o.get("shaft", 6.0)
	var head_len: float = o.get("head_len", 20.0)
	var head_w: float = o.get("head_w", 22.0)
	var shaft_end := end - dir * (head_len * 0.85)
	var head := PackedVector2Array([end, shaft_end + perp * (head_w * 0.5), shaft_end - perp * (head_w * 0.5)])
	var dash: float = clampf(square_size * 0.10, 4.0, 11.0)
	var disc: float = o.get("origin_disc", 0.0)
	var passes: Array = []
	var sh: float = o.get("shadow", 0.0)
	if sh > 0.0:
		passes.append([Vector2(sh, sh), Color(0, 0, 0, 0.30)])
	passes.append([Vector2.ZERO, color])
	for pass_def in passes:
		var off: Vector2 = pass_def[0]
		var c: Color = pass_def[1]
		if disc > 0.0:
			ci.draw_circle(start + off, disc, c, true, -1.0, true)
		if o.get("dashed", false):
			ci.draw_dashed_line(start + off, shaft_end + off, c, shaft, dash, true, true)
		else:
			ci.draw_line(start + off, shaft_end + off, c, shaft, true)
		var moved := PackedVector2Array()
		for pt in head:
			moved.append(pt + off)
		ci.draw_colored_polygon(moved, c)
	if o.get("rim", false):
		ci.draw_polyline(PackedVector2Array([head[1], head[0], head[2]]), Color(1, 1, 1, 0.45), 1.2, true)

## T2.1 — Ajoute/retire une annotation (flèche, ou cercle si départ == arrivée).
func _annotate(from_sq: int, to_sq: int) -> void:
	if from_sq == -1:
		return
	if to_sq == from_sq or to_sq == -1:
		var idx = user_circles.find(from_sq)
		if idx != -1:
			user_circles.remove_at(idx)
		else:
			user_circles.append(from_sq)
	else:
		var found_idx := -1
		for i in range(user_arrows.size()):
			var a = user_arrows[i]
			if int(a.get("from", -1)) == from_sq and int(a.get("to", -1)) == to_sq:
				found_idx = i
				break
		if found_idx != -1:
			user_arrows.remove_at(found_idx)
		else:
			user_arrows.append({"from": from_sq, "to": to_sq})
	user_annotations_changed.emit()
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()

func _draw_user_arrow(from_sq: int, to_sq: int, ci: CanvasItem) -> void:
	if from_sq < 0 or to_sq < 0:
		return
	_draw_arrow(ci, _square_center(from_sq), _square_center(to_sq), DesignTokens.USER_MARK, {
		"shaft": clampf(square_size * 0.08, 3.0, 8.0),
		"head_len": clampf(square_size * 0.26, 11.0, 26.0),
		"head_w": clampf(square_size * 0.30, 13.0, 30.0),
	})

## T2.1 — Sérialise / restaure les annotations (persistance dans le JSON de partie).
func get_user_annotations() -> Dictionary:
	return {"arrows": user_arrows.duplicate(true), "circles": user_circles.duplicate()}

func set_user_annotations(data: Dictionary) -> void:
	user_arrows = (data.get("arrows", []) as Array).duplicate(true)
	user_circles = (data.get("circles", []) as Array).duplicate()
	_redraw_board_and_overlays()

func clear_user_annotations() -> void:
	user_arrows.clear()
	user_circles.clear()
	_redraw_board_and_overlays()
	user_annotations_changed.emit()

func _draw_last_move_arrow(from_sq: int, to_sq: int, theme: Dictionary, ci: CanvasItem = null) -> void:
	# Flèche fine en pointillés, distincte de la flèche moteur pleine.
	var shaft := clampf(square_size * 0.06, 2.5, 6.5)
	_draw_arrow(ci if ci != null else self, _square_center(from_sq), _square_center(to_sq), theme["last_move_arrow"], {
		"shaft": shaft,
		"head_len": clampf(square_size * 0.24, 10.0, 26.0),
		"head_w": clampf(square_size * 0.26, 11.0, 28.0),
		"dashed": true,
		"shadow": clampf(square_size * 0.02, 1.2, 2.5),
		"origin_disc": shaft * 1.35,
		"rim": true,
	})

func _draw_modern_move_arrow(from_sq: int, to_sq: int, theme: Dictionary, ci: CanvasItem = null, rank_num: int = 0, rank_order: int = 1) -> void:
	var canvas: CanvasItem = ci if ci != null else self
	var start_pos = _get_square_screen_pos(from_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	var end_pos = _get_square_screen_pos(to_sq) + Vector2(square_size * 0.5, square_size * 0.5)
	
	if start_pos.distance_to(end_pos) < 1.0:
		return

	# Gradient arc-en-ciel dynamique selon la profondeur atteinte
	var arrow_color: Color
	if best_move_arrow_depth > 0:
		arrow_color = get_depth_rainbow_color(best_move_arrow_depth)
	else:
		arrow_color = theme.get("best_move_arrow", Color("#0284c7"))

	# Si c'est une ligne secondaire (rank > 1), on module légèrement la couleur pour la hiérarchie visuelle
	if rank_order == 2:
		arrow_color = theme.get("best_move_arrow_secondary", Color.from_hsv(fposmod(arrow_color.h + 0.08, 1.0), 0.75, 0.95))
		arrow_color.a = 0.88
	elif rank_order > 2:
		arrow_color = Color.from_hsv(fposmod(arrow_color.h + 0.16 * (rank_order - 1), 1.0), 0.70, 0.90)
		arrow_color.a = 0.80

	var shaft_width: float = clampf(square_size * 0.12, 5.0, 14.0)
	_draw_arrow(canvas, start_pos, end_pos, arrow_color, {
		"shaft": shaft_width,
		"head_len": clampf(square_size * 0.35, 15.0, 36.0),
		"head_w": clampf(square_size * 0.40, 18.0, 42.0),
		"shadow": clampf(square_size * 0.025, 1.5, 3.0),
		"origin_disc": shaft_width * 0.65,
		"rim": true,
	})

	# Numéro indicatif subtil mais évident à 3/4 de la distance (1/4 du bout de la flèche)
	if rank_num > 0:
		var badge_pos = start_pos.lerp(end_pos, 0.75)
		var badge_radius = clampf(shaft_width * 1.05, 7.0, 14.0)
		var font: Font = ThemeDB.fallback_font
		var num_str := str(rank_num)
		var font_size = int(clampf(badge_radius * 1.45, 10.0, 18.0))
		
		# Disque de fond (fond noir semi-opaque élégant + liseré blanc/or fin)
		canvas.draw_circle(badge_pos + Vector2(0.5, 0.5), badge_radius + 1.2, Color(1.0, 1.0, 1.0, 0.85), true, -1.0, true)
		canvas.draw_circle(badge_pos, badge_radius, Color(0.08, 0.10, 0.15, 0.95), true, -1.0, true)
		
		if font:
			var str_size = font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = badge_pos + Vector2(-str_size.x * 0.5, font_size * 0.36)
			# Numéro en blanc pur très net et contrasté au centre du badge noir
			canvas.draw_string(font, text_pos, num_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.97, 1.0, 1.0))

# --- GESTION TACTILE & SOURIS (Clic pour sélectionner, Clic pour déplacer) ---

func _redraw_board_and_overlays() -> void:
	if check_layer:
		check_layer.size = Vector2(board_size, board_size)
	if arrow_overlay:
		arrow_overlay.size = Vector2(board_size, board_size)
		arrow_overlay.position = Vector2.ZERO
		arrow_overlay.queue_redraw()
	queue_redraw()

func _resolve_local_pos(event: InputEvent) -> Vector2:
	# Le viewport transforme déjà la position des événements souris ET tactiles
	# dans le repère local du contrôle avant d'appeler _gui_input (cf. Godot
	# Viewport::_gui_input_event). event.position est donc toujours local ici :
	# aucun besoin de deviner l'espace de coordonnées, ce qui évite de mal
	# interpréter un contact lorsque le plateau est décalé (défilement, barre d'éval).
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
		# T2.1 — Annotations : clic droit ou Maj+clic gauche.
		if event.button_index == MOUSE_BUTTON_RIGHT or (event.button_index == MOUSE_BUTTON_LEFT and event.shift_pressed):
			var ann_sq := _pos_to_square(_resolve_local_pos(event))
			if event.pressed:
				_ann_from = ann_sq
			else:
				_annotate(_ann_from, ann_sq)
				_ann_from = -1
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
	# Toute interaction réelle sur l'échiquier sort de l'aperçu Cliff.
	if is_previewing():
		clear_preview_fen()
	if is_cliff_overlay_active():
		clear_cliff_overlay()
	
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
	preview_fen = ""
	cliff_overlay = {}
	_update_cliff_label()
	displayed_ply_index = -1
	reset_board_visuals()

## Journalisation nav (M8) : observable depuis le beta pour diagnostiquer M2.
func _nav_log(msg: String) -> void:
	var t := get_tree()
	if t and t.root and t.root.has_node("AppLogger"):
		t.root.get_node("AppLogger").log("NAV", msg)

func _on_move_navigated(target_ply: int) -> void:
	preview_fen = ""
	cliff_overlay = {}
	_update_cliff_label()
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
	preview_fen = ""
	if not cliff_overlay.is_empty():
		cliff_overlay = {}
		_update_cliff_label()
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
	preview_fen = ""
	if not cliff_overlay.is_empty():
		cliff_overlay = {}
		_update_cliff_label()
	var gc = _get_game_controller()
	if gc:
		displayed_ply_index = gc.current_ply_index
	last_move_from = move.from_sq
	last_move_to = move.to_sq
	best_move_arrow_from = -1
	best_move_arrow_to = -1
	best_move_arrow_fen = ""
	engine_lines_arrows.clear()
	_check_king_status()
	_animate_move(move)
	queue_redraw()

func _check_king_status() -> void:
	in_check_sq = -1
	var game: ChessGame = null
	if is_previewing():
		game = _preview_game
	else:
		var gc = _get_game_controller()
		game = gc.game if gc and gc.game else null
	if game and game.is_in_check(game.active_color):
		for i in range(64):
			var p = game.get_piece(i)
			if p.type == ChessPiece.Type.KING and p.color == game.active_color:
				in_check_sq = i
				break
	if check_layer:
		check_layer.size = Vector2(board_size, board_size)
		check_layer.set_process(in_check_sq != -1)
		check_layer.visible = in_check_sq != -1
		check_layer.queue_redraw()

func _on_engine_eval(_score_cp: int, _mate_in: int, depth: int, best_move: String, _pv: Array, multipv: Array) -> void:
	if not multipv.is_empty():
		set_engine_lines_arrows(multipv, depth)
	else:
		set_best_move_arrow(best_move, depth)

## Définit la flèche du meilleur coup en mémorisant le FEN associé, afin qu'un simple
## rafraîchissement du plateau ne l'efface pas (correctif flèches Live).
func set_best_move_arrow(uci: String, depth: int = 0) -> void:
	best_move_arrow_depth = depth
	var gc = _get_game_controller()
	var fen: String = preview_fen if is_previewing() else (gc.game.get_fen() if gc and gc.game else "")
	engine_lines_arrows.clear()
	if uci.length() >= 4:
		best_move_arrow_from = ChessMove.coord_to_square(uci.substr(0, 2))
		best_move_arrow_to = ChessMove.coord_to_square(uci.substr(2, 2))
		best_move_arrow_fen = fen
	else:
		best_move_arrow_from = -1
		best_move_arrow_to = -1
		best_move_arrow_fen = ""
	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()

## Définit les flèches pour toutes les lignes MultiPV proposées par le moteur.
## Chaque flèche correspond au premier coup de la ligne et porte un numéro d'ordre subtil.
func set_engine_lines_arrows(multipv_lines: Array, depth: int = 0) -> void:
	best_move_arrow_depth = depth
	var gc = _get_game_controller()
	var fen: String = preview_fen if is_previewing() else (gc.game.get_fen() if gc and gc.game else "")
	engine_lines_arrows.clear()
	best_move_arrow_from = -1
	best_move_arrow_to = -1
	best_move_arrow_fen = fen

	for line in multipv_lines:
		var rank: int = int(line.get("rank", engine_lines_arrows.size() + 1))
		var move_uci: String = str(line.get("best_move", ""))
		if move_uci == "":
			var pv: Array = line.get("pv", [])
			if not pv.is_empty():
				move_uci = str(pv[0])
		if move_uci.length() >= 4:
			var f_sq := ChessMove.coord_to_square(move_uci.substr(0, 2))
			var t_sq := ChessMove.coord_to_square(move_uci.substr(2, 2))
			if f_sq >= 0 and f_sq < 64 and t_sq >= 0 and t_sq < 64:
				engine_lines_arrows.append({
					"from": f_sq,
					"to": t_sq,
					"rank": rank,
					"uci": move_uci
				})
				if rank == 1 and best_move_arrow_from == -1:
					best_move_arrow_from = f_sq
					best_move_arrow_to = t_sq

	if arrow_overlay:
		arrow_overlay.queue_redraw()
	queue_redraw()


