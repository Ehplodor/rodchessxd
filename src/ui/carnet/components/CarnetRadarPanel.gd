class_name CarnetRadarPanel
extends Control
## CarnetRadarPanel.gd — T3 : radar des compétences (dimensions × skill 0-100).
## Repli en barres horizontales si l'espace est trop étroit (< 360 px) ou < 3 axes.

const MIN_RADAR_WIDTH := 360.0

var _points: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(0, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

## `dimensions` : Array de { label, skill, confiance }.
func set_dimensions(dimensions: Array) -> void:
	_points = dimensions
	queue_redraw()

func dimension_count() -> int:
	return _points.size()

## Géométrie pure et testable : positions des sommets du polygone (skill 0-100).
static func radar_points(dimensions: Array, center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := dimensions.size()
	if n == 0:
		return out
	for i in range(n):
		var angle := -PI / 2.0 + TAU * float(i) / float(n)
		var skill := clampf(float(dimensions[i].get("skill", 0.0)) / 100.0, 0.0, 1.0)
		out.append(center + Vector2(cos(angle), sin(angle)) * radius * skill)
	return out

func _draw() -> void:
	if _points.size() < 3 or size.x < MIN_RADAR_WIDTH:
		_draw_bars()
		return

	var font := ThemeDB.fallback_font
	var font_sz := 12
	var center := Vector2(size.x * 0.5, size.y * 0.5)

	# Mesure des largeurs pour adapter le rayon au conteneur réel
	var max_text_w := 30.0
	if font != null:
		for dim in _points:
			var full_text := "%s (%d)" % [str(dim.get("label", "")), int(dim.get("skill", 0))]
			var tw := font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
			max_text_w = maxf(max_text_w, tw)

	var margin_x := clampf(max_text_w + 6.0, 36.0, size.x * 0.30)
	var margin_y := float(font_sz * 2.0)
	var radius := minf(size.x * 0.5 - margin_x, size.y * 0.5 - margin_y)
	radius = clampf(radius, 30.0, 90.0)
	var n := _points.size()

	# 1. Anneaux concentriques polygonaux (25 %, 50 %, 75 %, 100 %)
	var grid_col := Color(DesignTokens.BORDER.r, DesignTokens.BORDER.g, DesignTokens.BORDER.b, 0.55)
	for lvl in [0.25, 0.50, 0.75, 1.0]:
		var r_lvl: float = radius * lvl
		var ring_pts := PackedVector2Array()
		for i in range(n):
			var angle := -PI / 2.0 + TAU * float(i) / float(n)
			ring_pts.append(center + Vector2(cos(angle), sin(angle)) * r_lvl)
		for i in range(n):
			draw_line(ring_pts[i], ring_pts[(i + 1) % n], grid_col, 1.0)

	# Repères chiffrés sur l'axe vertical haut
	if font != null:
		for lvl in [0.50, 1.0]:
			var y_pt: float = center.y - radius * float(lvl)
			draw_string(font, Vector2(center.x + 3.0, y_pt + 4.0), "%d" % int(lvl * 100),
					HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(8, font_sz - 2), DesignTokens.TEXT_MUTED)

	# 2. Axes radiaux
	for i in range(n):
		var angle := -PI / 2.0 + TAU * float(i) / float(n)
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(center, center + dir * radius, grid_col, 1.0)

	# 3. Surface de compétence du joueur
	var poly := radar_points(_points, center, radius)
	var fill := PackedVector2Array(poly)
	if fill.size() >= 3:
		draw_colored_polygon(fill, Color(DesignTokens.ACCENT.r, DesignTokens.ACCENT.g, DesignTokens.ACCENT.b, 0.28))
		for i in range(poly.size()):
			draw_line(poly[i], poly[(i + 1) % poly.size()], DesignTokens.ACCENT, 2.5)
			draw_circle(poly[i], 3.5, DesignTokens.ACCENT)
			draw_circle(poly[i], 1.8, Color.WHITE)

	# 4. Libellés des compétences autour du périmètre
	if font != null:
		for i in range(n):
			var angle := -PI / 2.0 + TAU * float(i) / float(n)
			var dir := Vector2(cos(angle), sin(angle))
			var label_pos := center + dir * (radius + 8.0)

			var dim = _points[i]
			var label_text := str(dim.get("label", ""))
			var skill_val := int(dim.get("skill", 0))
			var full_text := "%s (%d)" % [label_text, skill_val]

			var text_w := font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
			var draw_pos := label_pos

			if dir.x > 0.2:
				draw_pos.y += font_sz * 0.35
			elif dir.x < -0.2:
				draw_pos.x -= text_w
				draw_pos.y += font_sz * 0.35
			else:
				draw_pos.x -= text_w * 0.5
				if dir.y < 0:
					draw_pos.y -= 2.0
				else:
					draw_pos.y += font_sz

			# Protection absolue anti-débordement
			draw_pos.x = clampf(draw_pos.x, 2.0, size.x - text_w - 2.0)
			draw_pos.y = clampf(draw_pos.y, float(font_sz), size.y - 4.0)

			draw_string(font, draw_pos, full_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, DesignTokens.TEXT_SECONDARY)

func _draw_bars() -> void:
	var font := ThemeDB.fallback_font
	var y := 4.0
	var row_h := 30.0
	for dim in _points:
		var label := str(dim.get("label", ""))
		var skill := clampf(float(dim.get("skill", 0.0)), 0.0, 100.0)
		var w := maxf(1.0, size.x - 4.0)
		draw_rect(Rect2(2, y, w, 12.0), DesignTokens.SURFACE_ELEVATED, true)
		draw_rect(Rect2(2, y, w * skill / 100.0, 12.0), DesignTokens.ACCENT, true)
		if font != null:
			var txt := "%s : %d / 100" % [label, int(skill)]
			draw_string(font, Vector2(4, y + 25.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(DesignTokens.FONT_CAPTION), DesignTokens.TEXT_MUTED)
		y += row_h
