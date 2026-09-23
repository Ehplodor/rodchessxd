class_name EvalBar2D
extends Control
## EvalBar2D.gd - Barre verticale d'évaluation (avantage Blancs en bas, Noirs en haut),
## interpolée en douceur. Le score s'affiche DANS la zone du camp qui mène (bas si
## Blancs, haut si Noirs) : il reste toujours lisible, quel que soit le ratio.

const MoveQualityService = preload("res://src/ui/components/MoveQualityService.gd")

## Plancher/plafond visuel : une petite zone du camp perdant reste visible hors mat.
const RATIO_CLAMP := 0.04
const TWEEN_SEC := 0.22

var current_ratio: float = 0.5 # 0.5 = égalité, 1.0 = Blancs gagnants, 0.0 = Noirs gagnants
var target_ratio: float = 0.5
var display_score_text: String = "0.0"

var score_label: Label
var tween: Tween

var _sb_black := StyleBoxFlat.new()
var _sb_white := StyleBoxFlat.new()
var _sb_border := StyleBoxFlat.new()

func _ready() -> void:
	# Hauteur libre : la barre est accolée au plateau et suit exactement sa hauteur
	# (offsets posés par ChessBoard2D._position_eval_bar) — aucun minimum vertical.
	custom_minimum_size = Vector2(20, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(score_label)
	_refresh_styles()

	# Pas d'abonnement direct à EngineManager.evaluation_updated : Main est l'unique
	# source (évaluation stockée du coup affiché, sinon Live). Un second écrivain
	# afficherait des évaluations Live périmées par-dessus l'analyse (ex. « -M1 » après mat).
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.settings_changed.connect(func(key, _val):
			if key == "app_theme_mode":
				_refresh_styles()
		)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_styles()

## (Re)construit les StyleBox une fois par changement de taille/thème, pas à chaque image.
func _refresh_styles() -> void:
	var radius := int(minf(size.x * 0.5, float(DesignTokens.RADIUS_SMALL)))
	_sb_black.bg_color = DesignTokens.col("SIDE_BLACK")
	_sb_black.set_corner_radius_all(radius)
	_sb_white.bg_color = DesignTokens.col("SIDE_WHITE")
	_sb_border.draw_center = false
	_sb_border.border_color = DesignTokens.BORDER
	_sb_border.set_border_width_all(1)
	_sb_border.set_corner_radius_all(radius)
	_update_label()
	queue_redraw()

func _update_label() -> void:
	if score_label == null:
		return
	var f_size := int(clampf(size.x * 0.36, 9.0, float(DesignTokens.FONT_MICRO)))
	var white_leads := target_ratio >= 0.5
	score_label.add_theme_font_size_override("font_size", f_size)
	score_label.add_theme_color_override("font_color",
			DesignTokens.col("SIDE_BLACK") if white_leads else DesignTokens.col("SIDE_WHITE"))
	score_label.size = Vector2(size.x, f_size + 6)
	var pad := 3.0
	score_label.position = Vector2(0, size.y - score_label.size.y - pad if white_leads else pad)
	score_label.text = display_score_text

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or h <= 0:
		return
	var full_rect := Rect2(0, 0, w, h)
	draw_style_box(_sb_black, full_rect)

	# Zone Blancs depuis le bas : coins bas toujours arrondis, coins hauts seulement
	# quand la zone atteint le sommet (sinon la jonction serait « pincée »).
	var white_h := h * current_ratio
	if white_h > 0.5:
		var radius := _sb_border.corner_radius_top_left
		var top_r := int(clampf(white_h - (h - radius), 0.0, float(radius)))
		_sb_white.corner_radius_bottom_left = radius
		_sb_white.corner_radius_bottom_right = radius
		_sb_white.corner_radius_top_left = top_r
		_sb_white.corner_radius_top_right = top_r
		draw_style_box(_sb_white, Rect2(0, h - white_h, w, white_h))

	# Repère d'égalité.
	var mid_y := h * 0.5
	draw_line(Vector2(2, mid_y), Vector2(w - 2, mid_y), DesignTokens.ACCENT, DesignTokens.STROKE_THIN, true)
	draw_style_box(_sb_border, full_rect)

func set_score(score_cp: int, mate_in: int = 0) -> void:
	_on_engine_eval(score_cp, mate_in, 0, "", [], [])

func set_score_cp(score_cp: int, mate_in: int = 0) -> void:
	_on_engine_eval(score_cp, mate_in, 0, "", [], [])

func _on_engine_eval(score_cp: int, mate_in: int, _depth: int, _best_move: String, _pv: Array, _multipv: Array) -> void:
	# T0.1 — Formatage centralisé (gère les archives v1 : score ±10000 sans mate_in).
	if EvalFormatter.is_mate(score_cp, mate_in):
		var white_mates := mate_in > 0 if mate_in != 0 else score_cp > 0
		target_ratio = 1.0 if white_mates else 0.0
	else:
		# Même courbe de gain que le graphe, la qualité des coups et CHESS-CLIFF.
		target_ratio = clampf(MoveQualityService.win_percentage(score_cp) / 100.0, RATIO_CLAMP, 1.0 - RATIO_CLAMP)
	display_score_text = EvalFormatter.format_cp_mate(score_cp, mate_in)
	_update_label()

	if tween and tween.is_valid():
		tween.kill()
	tween = create_tween()
	tween.tween_method(func(val: float):
		current_ratio = val
		queue_redraw()
	, current_ratio, target_ratio, TWEEN_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
