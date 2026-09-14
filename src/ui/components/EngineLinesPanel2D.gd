class_name EngineLinesPanel2D
extends VBoxContainer
## EngineLinesPanel2D.gd - Panneau repliable des N meilleures lignes moteur (MultiPV, T1.1).
## Cliquer une ligne émet `line_selected` pour prévisualiser le coup sur l'échiquier.

signal line_selected(rank: int, pv: Array, best_move: String)

var _header_btn: Button
var _rows_box: VBoxContainer
var _collapsed := false
var _lines: Array = []
var _engine_name := "Moteur"
var _depth := 0
var _row_buttons: Array[Button] = []
var _row_data: Array[Dictionary] = []
var _san_cache: Dictionary = {}

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

	# Pré-création d'un pool fixe de 5 boutons réutilisables (zéro queue_free à l'évaluation)
	for idx in range(5):
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.visible = false
		var btn_idx = idx
		btn.pressed.connect(func():
			_on_row_pressed(btn_idx)
		)
		_rows_box.add_child(btn)
		_row_buttons.append(btn)
		_row_data.append({})

	_update_header()

func _on_row_pressed(idx: int) -> void:
	if idx < 0 or idx >= _row_data.size():
		return
	var data: Dictionary = _row_data[idx]
	if data.is_empty():
		return
	line_selected.emit(int(data.get("rank", idx + 1)), data.get("pv", []), str(data.get("best_move", "")))

## Vrai si le panneau est replié (permet à l'appelant d'éviter tout travail inutile).
func is_collapsed() -> bool:
	return _collapsed

func set_lines(lines: Array, engine_name: String = "", depth: int = 0) -> void:
	_lines = lines
	if engine_name != "":
		_engine_name = engine_name
	_depth = depth
	# Ne rien reconstruire tant que le panneau est replié (perf : appelé à chaque info moteur).
	if not _collapsed:
		_rebuild()
	_update_header()

func _toggle() -> void:
	_collapsed = not _collapsed
	_rows_box.visible = not _collapsed
	if not _collapsed:
		_rebuild()
	_update_header()

func _update_header() -> void:
	if _header_btn == null:
		return
	var arrow := "▸" if _collapsed else "▾"
	_header_btn.text = "%s Lignes moteur (%d) — %s d%d" % [arrow, _lines.size(), _engine_name, _depth]

func _rebuild() -> void:
	if _rows_box == null:
		return
	var count = mini(_lines.size(), _row_buttons.size())
	for i in range(count):
		var line: Dictionary = _lines[i]
		var pv: Array = line.get("pv", [])
		if pv.is_empty():
			_row_buttons[i].visible = false
			_row_data[i] = {}
			continue
		var eval_str := EvalFormatter.format_cp_mate(int(line.get("score_cp", 0)), int(line.get("mate_in", 0)))
		var san_line := _pv_to_san(str(line.get("fen", "")), pv)
		var btn = _row_buttons[i]
		btn.text = "%d.  %s   %s" % [i + 1, eval_str, san_line]
		btn.tooltip_text = "%s\n%s" % [eval_str, san_line]
		btn.visible = true
		_row_data[i] = {
			"rank": i + 1,
			"pv": pv,
			"best_move": str(line.get("best_move", ""))
		}

	# Masquer les boutons du pool non utilisés
	for i in range(count, _row_buttons.size()):
		_row_buttons[i].visible = false
		_row_data[i] = {}

func _pv_to_san(fen: String, pv: Array) -> String:
	if fen == "" or pv.is_empty():
		return " ".join(pv)
	var cache_key = fen + "|" + " ".join(pv.slice(0, 8))
	if _san_cache.has(cache_key):
		return _san_cache[cache_key]
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
	var res = " ".join(sans)
	if _san_cache.size() > 200:
		_san_cache.clear()
	_san_cache[cache_key] = res
	return res
