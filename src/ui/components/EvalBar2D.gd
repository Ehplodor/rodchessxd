class_name EvalBar2D
extends Control
## EvalBar2D.gd - Barre verticale d'évaluation dynamique en temps réel avec design moderne arrondi et interpolation fluide

var current_ratio: float = 0.5 # 0.5 = égalité (0 cp), 1.0 = Blancs gagnants, 0.0 = Noirs gagnants
var target_ratio: float = 0.5
var display_score_text: String = "0.0"

var score_label: Label
var tween: Tween

# Styles visuels modernes
const BG_DARK := Color("#090d16")
const FG_LIGHT := Color("#f8fafc")
const PARITY_COLOR := Color("#38bdf8")
const BORDER_COLOR := Color("#334155")

func _ready() -> void:
	custom_minimum_size = Vector2(20, 80)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# M1 : barre étroite (≤ 20 px) — police plafonnée à 12 px
	score_label.add_theme_font_size_override("font_size", 12)
	score_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	add_child(score_label)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_label_position()
		queue_redraw()

func _update_label_position() -> void:
	if score_label:
		score_label.size = Vector2(size.x, 18)
		# Positionner le badge près de la démarcation
		var y_pos = clampf((1.0 - current_ratio) * size.y - 9, 2, size.y - 20)
		score_label.position = Vector2(0, y_pos)

func _draw() -> void:
	var w = size.x
	var h = size.y
	if w <= 0 or h <= 0:
		return
	
	var radius = min(w * 0.5, 6.0)
	var full_rect = Rect2(0, 0, w, h)
	
	# 1. Fond sombre arrondi (avantage Noirs)
	var dark_style = StyleBoxFlat.new()
	dark_style.bg_color = BG_DARK
	dark_style.corner_radius_top_left = int(radius)
	dark_style.corner_radius_top_right = int(radius)
	dark_style.corner_radius_bottom_left = int(radius)
	dark_style.corner_radius_bottom_right = int(radius)
	draw_style_box(dark_style, full_rect)
	
	# 2. Remplissage clair (avantage Blancs depuis le bas vers le haut)
	# ratio 1.0 => tout blanc, ratio 0.0 => tout noir
	var white_height = h * current_ratio
	if white_height > 1.0:
		var white_rect = Rect2(0, h - white_height, w, white_height)
		var white_style = StyleBoxFlat.new()
		white_style.bg_color = FG_LIGHT
		white_style.corner_radius_bottom_left = int(radius)
		white_style.corner_radius_bottom_right = int(radius)
		# Si blanc dépasse la moitié ou le haut, arrondir le haut aussi
		if current_ratio > 0.96:
			white_style.corner_radius_top_left = int(radius)
			white_style.corner_radius_top_right = int(radius)
		draw_style_box(white_style, white_rect)
	
	# 3. Ligne médiane de parité (0.0 cp) avec lueur néon cyan
	var mid_y = h * 0.5
	draw_line(Vector2(2, mid_y), Vector2(w - 2, mid_y), PARITY_COLOR, 1.5)
	
	# 4. Contour élégant semi-transparent
	var border_style = StyleBoxFlat.new()
	border_style.draw_center = false
	border_style.border_color = BORDER_COLOR
	border_style.set_border_width_all(1)
	border_style.corner_radius_top_left = int(radius)
	border_style.corner_radius_top_right = int(radius)
	border_style.corner_radius_bottom_left = int(radius)
	border_style.corner_radius_bottom_right = int(radius)
	draw_style_box(border_style, full_rect)

func set_score(score_cp: int, mate_in: int = 0) -> void:
	_on_engine_eval(score_cp, mate_in, 0, "", [], [])

func set_score_cp(score_cp: int, mate_in: int = 0) -> void:
	_on_engine_eval(score_cp, mate_in, 0, "", [], [])

func _on_engine_eval(score_cp: int, mate_in: int, _depth: int, _best_move: String, _pv: Array, _multipv: Array) -> void:
	if mate_in != 0:
		if mate_in > 0:
			target_ratio = 1.0
			display_score_text = "M%d" % mate_in
		else:
			target_ratio = 0.0
			display_score_text = "-M%d" % abs(mate_in)
	else:
		# Formule sigmoïde de conversion centipions -> ratio visuel 0.0 à 1.0
		var win_chance = 1.0 / (1.0 + pow(10.0, -score_cp / 400.0))
		target_ratio = clampf(win_chance, 0.04, 0.96)
		
		var pawns = score_cp / 100.0
		display_score_text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns

	if score_label:
		score_label.text = display_score_text
		# Texte sombre sur fond clair, ou blanc sur fond sombre selon la position du badge
		if target_ratio > 0.5:
			score_label.add_theme_color_override("font_color", Color("#090d16"))
		else:
			score_label.add_theme_color_override("font_color", Color("#f8fafc"))

	# Animation fluide de la jauge à 60 FPS
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_method(func(val: float):
		current_ratio = val
		_update_label_position()
		queue_redraw()
	, current_ratio, target_ratio, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


