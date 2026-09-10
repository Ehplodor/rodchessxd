class_name CarnetRadarPanel
extends Control
## CarnetRadarPanel.gd — T3 : radar des compétences (dimensions × skill 0-100).
## Repli en barres horizontales si l'espace est trop étroit (< 360 px) ou < 3 axes.

const MIN_RADAR_WIDTH := 360.0

var _points: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(0, 220)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	var radius := minf(size.x, size.y) * 0.38
	var n := _points.size()
	# Toile de fond (axes + anneaux).
	for i in range(n):
		var angle := -PI / 2.0 + TAU * float(i) / float(n)
		draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius,
				DesignTokens.BORDER, 1.0)
	var poly := radar_points(_points, center, radius)
	var fill := PackedVector2Array(poly)
	if fill.size() >= 3:
		draw_colored_polygon(fill, Color(DesignTokens.ACCENT, 0.25))
		for i in range(poly.size()):
			draw_line(poly[i], poly[(i + 1) % poly.size()], DesignTokens.ACCENT, 2.0)

func _draw_bars() -> void:
	var font := ThemeDB.fallback_font
	var y := 4.0
	var row_h := 26.0
	for dim in _points:
		var label := str(dim.get("label", ""))
		var skill := clampf(float(dim.get("skill", 0.0)), 0.0, 100.0)
		var w := maxf(1.0, size.x - 4.0)
		draw_rect(Rect2(2, y, w, 12.0), DesignTokens.SURFACE_ELEVATED, true)
		draw_rect(Rect2(2, y, w * skill / 100.0, 12.0), DesignTokens.ACCENT, true)
		if font != null:
			draw_string(font, Vector2(4, y + 24.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
					int(DesignTokens.FONT_CAPTION), DesignTokens.TEXT_MUTED)
		y += row_h
