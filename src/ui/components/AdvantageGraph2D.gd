class_name AdvantageGraph2D
extends Control
## AdvantageGraph2D.gd - Graphe vectoriel interactif de la courbe d'avantage avec axes, HUD et zoom

signal move_scrubbed(ply_index: int)

var evaluations: Array = []
var active_ply: int = -1

var max_eval_cp: float = 500.0 # Plafond visuel à ±5 pions
var is_expanded: bool = false
var btn_expand: Button
var stored_analyses: Array = []
var current_analysis_idx: int = 0
var btn_switch_analysis: Button

func _ready() -> void:
	custom_minimum_size = Vector2(250, 90)
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameController.move_navigated.connect(_on_move_navigated)

	_setup_expand_button()

func _setup_expand_button() -> void:
	btn_expand = Button.new()
	btn_expand.text = "📐 Agrandir"
	btn_expand.tooltip_text = "Agrandir / Réduire la vue détaillée du graphe"
	btn_expand.add_theme_font_size_override("font_size", 9)
	btn_expand.custom_minimum_size = Vector2(68, 22)
	btn_expand.pressed.connect(_toggle_expand)
	add_child(btn_expand)

	btn_switch_analysis = Button.new()
	btn_switch_analysis.visible = false
	btn_switch_analysis.add_theme_font_size_override("font_size", 9)
	btn_switch_analysis.custom_minimum_size = Vector2(0, 22)
	btn_switch_analysis.tooltip_text = "Cliquer pour basculer entre les différentes analyses de moteurs enregistrées"
	btn_switch_analysis.pressed.connect(_cycle_analysis)
	add_child(btn_switch_analysis)

	_update_button_positions()

func _toggle_expand() -> void:
	is_expanded = not is_expanded
	var new_h = 180.0 if is_expanded else 90.0
	custom_minimum_size = Vector2(250, new_h)
	if get_parent() is Control:
		get_parent().custom_minimum_size = Vector2(0, new_h)
	btn_expand.text = "📐 Réduire" if is_expanded else "📐 Agrandir"
	_update_button_positions()
	queue_redraw()

func _update_button_positions() -> void:
	var right_cursor = size.x - 6
	if btn_expand:
		btn_expand.position = Vector2(right_cursor - btn_expand.size.x, 6)
		right_cursor -= (btn_expand.size.x + 6)
	if btn_switch_analysis and btn_switch_analysis.visible:
		btn_switch_analysis.position = Vector2(right_cursor - btn_switch_analysis.size.x, 6)

func update_stored_analyses(analyses: Array) -> void:
	stored_analyses = analyses
	if stored_analyses.size() > 1:
		current_analysis_idx = stored_analyses.size() - 1
		_show_switch_analysis_button()
	else:
		if btn_switch_analysis:
			btn_switch_analysis.visible = false
	_update_button_positions()

func _show_switch_analysis_button() -> void:
	if not btn_switch_analysis:
		return
	btn_switch_analysis.visible = true
	var cur = stored_analyses[current_analysis_idx]
	var eng = cur.get("engine_name", "Stockfish")
	var d = cur.get("depth", 10)
	btn_switch_analysis.text = "⚡ %s (d%d) [%d/%d]" % [eng, d, current_analysis_idx + 1, stored_analyses.size()]
	btn_switch_analysis.reset_size()
	_update_button_positions()

func _cycle_analysis() -> void:
	if stored_analyses.is_empty():
		return
	current_analysis_idx = (current_analysis_idx + 1) % stored_analyses.size()
	var cur = stored_analyses[current_analysis_idx]
	set_evaluations(cur.get("evaluations", []))
	_show_switch_analysis_button()
	var main = find_parent("Main")
	if main and main.stats_label:
		var w_acc = cur.get("white_accuracy", 0.0)
		var b_acc = cur.get("black_accuracy", 0.0)
		var w_elo = cur.get("white_estimated_elo", 1500)
		var b_elo = cur.get("black_estimated_elo", 1500)
		main.stats_label.text = "⚪ Blancs: %.1f%% (Est. %d ELO)  |  ⚫ Noirs: %.1f%% (Est. %d ELO)" % [w_acc, w_elo, b_acc, b_elo]

func set_evaluations(eval_data: Array) -> void:
	evaluations.clear()
	for item in eval_data:
		if item is Dictionary:
			evaluations.append(item)
	if not evaluations.is_empty() and (active_ply < 0 or active_ply >= evaluations.size()):
		active_ply = evaluations.size() - 1
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_button_positions()
		queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y

	var left_margin = 32.0
	var right_margin = 12.0
	var top_margin = 10.0
	var bottom_margin = 10.0

	var graph_w = maxf(10.0, w - left_margin - right_margin)
	var graph_h = maxf(10.0, h - top_margin - bottom_margin)
	var mid_y = top_margin + graph_h * 0.5

	# 1. Fond sombre élégant
	draw_rect(Rect2(0, 0, w, h), Color("#090e1a"), true)
	draw_rect(Rect2(0, 0, w, h), Color("#1e293b"), false, 1.0)

	# 2. Échelle Y et lignes repères (+3.0, 0.0, -3.0)
	var scale_y = (graph_h * 0.44) / max_eval_cp
	var plus3_y = mid_y - (300.0 * scale_y)
	var minus3_y = mid_y + (300.0 * scale_y)

	var default_font = ThemeDB.fallback_font
	var font_size = 8

	# Ligne +3 pions (Avantage Blancs)
	draw_line(Vector2(left_margin, plus3_y), Vector2(w - right_margin, plus3_y), Color("#33415555"), 1.0)
	draw_string(default_font, Vector2(4, plus3_y + 3), "+3.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#94a3b8"))

	# Ligne 0.0 (Parité / Égalité)
	draw_line(Vector2(left_margin, mid_y), Vector2(w - right_margin, mid_y), Color("#38bdf866"), 1.5)
	draw_string(default_font, Vector2(6, mid_y + 3), " 0.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#38bdf8"))

	# Ligne -3 pions (Avantage Noirs)
	draw_line(Vector2(left_margin, minus3_y), Vector2(w - right_margin, minus3_y), Color("#33415555"), 1.0)
	draw_string(default_font, Vector2(4, minus3_y + 3), "-3.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#94a3b8"))

	# 3. État sans données : Affichage explicite du mode d'emploi
	var total_points = evaluations.size()
	if total_points < 2:
		var msg1 = "📈 Courbe d'Avantage Stockfish"
		var msg2 = "Cliquez sur '🔍 Analyser Partie' pour tracer l'évaluation coup par coup"
		draw_string(default_font, Vector2(w * 0.5 - 90, mid_y - 4), msg1, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color("#cbd5e1"))
		draw_string(default_font, Vector2(w * 0.5 - 145, mid_y + 14), msg2, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color("#64748b"))
		return

	# 4. Calcul des coordonnées des points
	var step_x = graph_w / float(total_points - 1)
	var points = PackedVector2Array()

	for i in range(total_points):
		var record = evaluations[i]
		var score_cp = clampf(record.get("score_cp", 0), -max_eval_cp, max_eval_cp)
		var px = left_margin + i * step_x
		var py = mid_y - (score_cp * scale_y)
		points.append(Vector2(px, py))

	# 5. Polygones de remplissage (gradient Blanc au-dessus, Noir en-dessous)
	var fill_white = PackedVector2Array([Vector2(left_margin, mid_y)])
	for p in points:
		fill_white.append(Vector2(p.x, min(p.y, mid_y)))
	fill_white.append(Vector2(left_margin + graph_w, mid_y))
	draw_colored_polygon(fill_white, Color("#f8fafc22"))

	var fill_black = PackedVector2Array([Vector2(left_margin, mid_y)])
	for p in points:
		fill_black.append(Vector2(p.x, max(p.y, mid_y)))
	fill_black.append(Vector2(left_margin + graph_w, mid_y))
	draw_colored_polygon(fill_black, Color("#00000055"))

	# 6. Tracé de la courbe principale
	draw_polyline(points, Color("#38bdf8"), 2.2, true)

	# 7. Pastilles pour les coups marquants
	for i in range(total_points):
		var record = evaluations[i]
		var quality = record.get("quality", ChessMove.Quality.NONE)
		var pt = points[i]

		if quality == ChessMove.Quality.BLUNDER:
			draw_circle(pt, 4.5, Color("#ef4444"))
			draw_arc(pt, 4.5, 0, TAU, 16, Color("#ffffff"), 1.0)
		elif quality == ChessMove.Quality.MISTAKE:
			draw_circle(pt, 3.5, Color("#f97316"))
		elif quality == ChessMove.Quality.BRILLIANT:
			draw_circle(pt, 5.0, Color("#10b981"))
			draw_arc(pt, 5.0, 0, TAU, 16, Color("#ffffff"), 1.2)

	# 8. Curseur actif & Tooltip HUD interactif
	if active_ply >= 0 and active_ply < points.size():
		var cursor_pt = points[active_ply]
		draw_line(Vector2(cursor_pt.x, top_margin), Vector2(cursor_pt.x, h - bottom_margin), Color("#facc15aa"), 1.8)
		draw_circle(cursor_pt, 5.0, Color("#facc15"))
		draw_arc(cursor_pt, 5.0, 0, TAU, 16, Color("#090e1a"), 1.5)

		# Badges d'information dynamique sur le coup sélectionné
		var rec = evaluations[active_ply]
		var score_cp = rec.get("score_cp", 0)
		var pawns_val = score_cp / 100.0
		var eval_str = ("+%.1f" if pawns_val >= 0 else "%.1f") % pawns_val
		var move_num = rec.get("move_number", 1)
		var san = rec.get("san", "")
		var is_w = rec.get("is_white", true)
		var qual = rec.get("quality", ChessMove.Quality.NONE)
		var badge_sym = ChessMove.quality_to_symbol(qual)
		
		var ply_label = ("%d. %s" if is_w else "%d... %s") % [move_num, san]
		if badge_sym != "":
			ply_label += " " + badge_sym
		var hud_text = "%s  (%s)" % [ply_label, eval_str]

		# Dessin du badge HUD
		var badge_w = 110.0
		var badge_h = 20.0
		var badge_x = clampf(cursor_pt.x - badge_w * 0.5, left_margin + 2, w - right_margin - badge_w - 2)
		var badge_y = cursor_pt.y - 28.0
		if badge_y < top_margin + 2:
			badge_y = cursor_pt.y + 12.0

		var badge_rect = Rect2(badge_x, badge_y, badge_w, badge_h)
		draw_rect(badge_rect, Color("#0f172aee"), true)
		draw_rect(badge_rect, Color("#38bdf888"), false, 1.0)
		draw_string(default_font, Vector2(badge_x + 6, badge_y + 14), hud_text, HORIZONTAL_ALIGNMENT_CENTER, int(badge_w - 12), 10, Color("#f8fafc"))

# --- SCRUBBING TACTILE & NAVIGATION ---

func _gui_input(event: InputEvent) -> void:
	if evaluations.is_empty():
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_scrub_to_pos(event.position.x)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_scrub_to_pos(event.position.x)
	elif event is InputEventScreenTouch and event.pressed:
		_scrub_to_pos(event.position.x)
	elif event is InputEventScreenDrag:
		_scrub_to_pos(event.position.x)

func _scrub_to_pos(pos_x: float) -> void:
	var total_points = evaluations.size()
	if total_points == 0:
		return

	var left_margin = 32.0
	var right_margin = 12.0
	var graph_w = maxf(1.0, size.x - left_margin - right_margin)
	
	var ratio = clampf((pos_x - left_margin) / graph_w, 0.0, 1.0)
	var target_ply = int(round(ratio * (total_points - 1)))

	if target_ply != active_ply:
		active_ply = target_ply
		queue_redraw()
		move_scrubbed.emit(target_ply)
		GameController.navigate_to_ply(target_ply)

func _on_move_navigated(move_idx: int) -> void:
	active_ply = move_idx
	queue_redraw()

