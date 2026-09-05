class_name EvalBar2D
extends Control
## EvalBar2D.gd - Barre verticale d'évaluation dynamique en temps réel avec interpolation fluide

var current_ratio: float = 0.5 # 0.5 = égalité (0 cp), 1.0 = Blancs gagnants, 0.0 = Noirs gagnants
var target_ratio: float = 0.5
var display_score_text: String = "0.0"

var score_label: Label
var tween: Tween

func _ready() -> void:
	custom_minimum_size = Vector2(28, 120)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	score_label = Label.new()
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 10)
	score_label.add_theme_color_override("font_color", Color("#0f172a"))
	add_child(score_label)
	
	if EngineManager != null:
		EngineManager.evaluation_updated.connect(_on_engine_eval)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_label_position()
		queue_redraw()

func _update_label_position() -> void:
	if score_label:
		score_label.size = Vector2(size.x, 20)
		var y_pos = clampf((1.0 - current_ratio) * size.y - 10, 4, size.y - 24)
		score_label.position = Vector2(0, y_pos)

func _draw() -> void:
	var w = size.x
	var h = size.y
	
	# Fond noir (avantage Noirs)
	draw_rect(Rect2(0, 0, w, h), Color("#0f172a"))
	
	# Remplissage blanc (avantage Blancs depuis le haut)
	var white_height = h * current_ratio
	draw_rect(Rect2(0, 0, w, white_height), Color("#f8fafc"))
	
	# Ligne médiane de parité
	draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color("#38bdf888"), 1.5)
	
	# Bordure subtile
	draw_rect(Rect2(0, 0, w, h), Color("#334155"), false, 1.0)

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
		# 0 cp = 0.5, +400 cp (+4 pions) = ~0.85, -400 cp = ~0.15
		var win_chance = 1.0 / (1.0 + pow(10.0, -score_cp / 400.0))
		target_ratio = clampf(win_chance, 0.04, 0.96)
		
		var pawns = score_cp / 100.0
		display_score_text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns

	if score_label:
		score_label.text = display_score_text
		# Texte noir sur fond blanc, ou blanc sur fond noir selon où il se trouve
		if current_ratio > 0.5:
			score_label.add_theme_color_override("font_color", Color("#0f172a"))
		else:
			score_label.add_theme_color_override("font_color", Color("#f8fafc"))

	# Animation fluide de la jauge
	if tween and tween.is_valid():
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "current_ratio", target_ratio, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_callback(queue_redraw)
	tween.parallel().tween_callback(_update_label_position)
