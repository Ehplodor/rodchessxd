class_name AdvantageGraph2D
extends Control
## AdvantageGraph2D.gd - Graphe vectoriel interactif de la courbe d'avantage avec scrubbing tactile

signal move_scrubbed(ply_index: int)

var evaluations: Array[Dictionary] = []
var active_ply: int = -1

var max_eval_cp: float = 600.0 # Plafond visuel à ±6 pions

func _ready() -> void:
	custom_minimum_size = Vector2(250, 60)
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameController.move_navigated.connect(_on_move_navigated)

func set_evaluations(eval_data: Array[Dictionary]) -> void:
	evaluations = eval_data
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y
	var mid_y = h * 0.5

	# 1. Fond sombre élégant
	draw_rect(Rect2(0, 0, w, h), Color("#0f172a"), true)
	draw_rect(Rect2(0, 0, w, h), Color("#1e293b"), false, 1.0)

	# 2. Ligne médiane (0.0 égalité)
	draw_line(Vector2(0, mid_y), Vector2(w, mid_y), Color("#334155"), 1.5)

	# Lignes secondaires de repère (±3 pions)
	var scale_y = (h * 0.45) / max_eval_cp
	var plus3_y = mid_y - (300.0 * scale_y)
	var minus3_y = mid_y + (300.0 * scale_y)
	draw_line(Vector2(0, plus3_y), Vector2(w, plus3_y), Color("#1e293b88"), 1.0)
	draw_line(Vector2(0, minus3_y), Vector2(w, minus3_y), Color("#1e293b88"), 1.0)

	var total_points = evaluations.size()
	if total_points < 2:
		return

	var step_x = w / float(total_points - 1)
	var points = PackedVector2Array()

	# 3. Calcul des coordonnées des points
	for i in range(total_points):
		var record = evaluations[i]
		var score_cp = clampf(record.get("score_cp", 0), -max_eval_cp, max_eval_cp)
		var px = i * step_x
		var py = mid_y - (score_cp * scale_y)
		points.append(Vector2(px, py))

	# 4. Tracé du polygone de remplissage (gradient blanc au-dessus, noir en dessous)
	var fill_points_white = PackedVector2Array([Vector2(0, mid_y)])
	for p in points:
		fill_points_white.append(Vector2(p.x, min(p.y, mid_y)))
	fill_points_white.append(Vector2(w, mid_y))
	draw_colored_polygon(fill_points_white, Color("#f8fafc22"))

	var fill_points_black = PackedVector2Array([Vector2(0, mid_y)])
	for p in points:
		fill_points_black.append(Vector2(p.x, max(p.y, mid_y)))
	fill_points_black.append(Vector2(w, mid_y))
	draw_colored_polygon(fill_points_black, Color("#00000044"))

	# 5. Tracé de la courbe principale
	draw_polyline(points, Color("#38bdf8"), 2.5, true)

	# 6. Pastilles colorées pour les coups marquants (gaffes, erreurs, coups brillants)
	for i in range(total_points):
		var record = evaluations[i]
		var quality = record.get("quality", ChessMove.Quality.NONE)
		var pt = points[i]

		if quality == ChessMove.Quality.BLUNDER:
			draw_circle(pt, 5.0, Color("#ef4444"))
			draw_arc(pt, 5.0, 0, TAU, 16, Color("#ffffff"), 1.0)
		elif quality == ChessMove.Quality.MISTAKE:
			draw_circle(pt, 4.0, Color("#f97316"))
		elif quality == ChessMove.Quality.BRILLIANT:
			draw_circle(pt, 5.0, Color("#10b981"))
			draw_arc(pt, 5.0, 0, TAU, 16, Color("#ffffff"), 1.0)

	# 7. Curseur de position active (ply en cours de visualisation)
	if active_ply >= 0 and active_ply < points.size():
		var cursor_pt = points[active_ply]
		draw_line(Vector2(cursor_pt.x, 0), Vector2(cursor_pt.x, h), Color("#facc15aa"), 2.0)
		draw_circle(cursor_pt, 6.0, Color("#facc15"))
		draw_arc(cursor_pt, 6.0, 0, TAU, 16, Color("#0f172a"), 2.0)

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
	
	var ratio = clampf(pos_x / size.x, 0.0, 1.0)
	var target_ply = int(round(ratio * (total_points - 1)))
	
	if target_ply != active_ply:
		active_ply = target_ply
		queue_redraw()
		move_scrubbed.emit(target_ply)
		GameController.navigate_to_ply(target_ply)

func _on_move_navigated(move_idx: int) -> void:
	active_ply = move_idx
	queue_redraw()
