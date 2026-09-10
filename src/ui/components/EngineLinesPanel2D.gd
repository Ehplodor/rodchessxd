class_name EngineLinesPanel2D
extends VBoxContainer
## EngineLinesPanel2D.gd - Panneau repliable des N meilleures lignes moteur (MultiPV, T1.1).
## Cliquer une ligne émet `line_selected` pour prévisualiser le coup sur l'échiquier.

signal line_selected(rank: int, pv: Array, best_move: String)

const MAX_DISPLAY := 3

var _header_btn: Button
var _rows_box: VBoxContainer
var _collapsed := false
var _lines: Array = []
var _engine_name := "Moteur"
var _depth := 0

func _ready() -> void:
	add_theme_constant_override("separation", 2)
	_header_btn = Button.new()
	_header_btn.flat = true
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header_btn.clip_text = true
	_header_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	_header_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_header_btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	_header_btn.pressed.connect(_toggle)
	add_child(_header_btn)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	add_child(_rows_box)
	_update_header()

func set_lines(lines: Array, engine_name: String = "", depth: int = 0) -> void:
	_lines = lines
	if engine_name != "":
		_engine_name = engine_name
	_depth = depth
	_rebuild()
	_update_header()

func _toggle() -> void:
	_collapsed = not _collapsed
	_rows_box.visible = not _collapsed
	_update_header()

func _update_header() -> void:
	if _header_btn == null:
		return
	var arrow := "▸" if _collapsed else "▾"
	_header_btn.text = "%s Lignes moteur (%d) — %s d%d" % [arrow, mini(_lines.size(), MAX_DISPLAY), _engine_name, _depth]

func _rebuild() -> void:
	if _rows_box == null:
		return
	for c in _rows_box.get_children():
		c.queue_free()
	var shown := 0
	for i in range(_lines.size()):
		if shown >= MAX_DISPLAY:
			break
		var line: Dictionary = _lines[i]
		var pv: Array = line.get("pv", [])
		if pv.is_empty():
			continue
		shown += 1
		var eval_str := EvalFormatter.format_cp_mate(int(line.get("score_cp", 0)), int(line.get("mate_in", 0)))
		var san_line := _pv_to_san(str(line.get("fen", "")), pv)
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.text = "%d.  %s   %s" % [i + 1, eval_str, san_line]
		btn.tooltip_text = "%s\n%s" % [eval_str, san_line]
		var rank := i + 1
		btn.pressed.connect(func():
			line_selected.emit(rank, pv, str(line.get("best_move", "")))
		)
		_rows_box.add_child(btn)

func _pv_to_san(fen: String, pv: Array) -> String:
	if fen == "" or pv.is_empty():
		return " ".join(pv)
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return " ".join(pv)
	var sans: Array = []
	var limit := mini(pv.size(), 8)
	for k in range(limit):
		var mv := game.find_move(str(pv[k]))
		if mv == null:
			break
		sans.append(mv.san)
		game.make_move(mv)
	return " ".join(sans)
