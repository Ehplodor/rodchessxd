class_name CarnetMotifCard
extends PanelContainer
## CarnetMotifCard.gd — T3 : carte d'un motif (faiblesse/force) avec score visuel et explications.
## Ne dépend que d'un dictionnaire de motif (CarnetLedger) et d'un texte de détail.

signal activated(motif: Dictionary)

var _title: Label
var _desc: Label
var _meta: Label
var _bar: ProgressBar
var _motif: Dictionary = {}

func _init() -> void:
	add_theme_stylebox_override("panel", DesignTokens.card())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_child(box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	box.add_child(header_row)

	_title = Label.new()
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	header_row.add_child(_title)

	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_desc.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	box.add_child(_desc)

	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 8
	box.add_child(_bar)

	_meta = Label.new()
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta.clip_text = true
	_meta.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_meta.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	box.add_child(_meta)

	gui_input.connect(_on_gui_input)

func set_motif(motif: Dictionary, tendance: String = "") -> void:
	_motif = motif
	var famille := str(motif.get("famille", ""))
	var cle := str(motif.get("cle", ""))
	_title.text = str(motif.get("libelle", "%s / %s" % [famille, cle]))

	var desc_text := CarnetLedger.motif_description(famille, cle)
	if desc_text != "":
		_desc.text = desc_text
		_desc.visible = true
	else:
		_desc.text = ""
		_desc.visible = false

	var score_val := float(motif.get("score", 0.0))
	_bar.value = score_val
	var polarite := str(motif.get("polarite", ""))
	var fill := StyleBoxFlat.new()
	fill.bg_color = _polarite_color(polarite)
	_bar.add_theme_stylebox_override("fill", fill)

	var trend := tendance if tendance != "" else str(motif.get("tendance", ""))
	_update_meta(polarite, int(motif.get("n", 0)), int(score_val), trend)

func _update_meta(polarite: String, n: int, score: int, trend: String) -> void:
	var prefix := "Impact"
	if polarite == "positif":
		prefix = "Maîtrise"
	elif polarite == "curieux":
		prefix = "Intérêt"

	var trend_str := ""
	match trend:
		"en_amelioration": trend_str = " · ↗ En amélioration"
		"en_aggravation": trend_str = " · ↘ En hausse récente"
		"stable": trend_str = " · ➔ Stable"
		"indetermine", "": trend_str = ""
		_: trend_str = " · %s" % trend

	_meta.text = "%s : %d / 100 · %d fois détecté%s" % [prefix, score, n, trend_str]

func _polarite_color(polarite: String) -> Color:
	match polarite:
		"positif": return DesignTokens.SUCCESS
		"curieux": return DesignTokens.ACCENT
	return DesignTokens.WARNING

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(_motif)
	elif event is InputEventScreenTouch and event.pressed:
		activated.emit(_motif)

func title_text() -> String:
	return _title.text

func score_value() -> float:
	return _bar.value

