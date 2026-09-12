class_name CarnetMotifCard
extends PanelContainer
## CarnetMotifCard.gd — T3 : carte d'un motif (faiblesse/force) avec score visuel.
## Ne dépend que d'un dictionnaire de motif (CarnetLedger) et d'un texte de détail.

signal activated(motif: Dictionary)

var _title: Label
var _meta: Label
var _bar: ProgressBar
var _motif: Dictionary = {}

func _init() -> void:
	add_theme_stylebox_override("panel", DesignTokens.card())
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_child(box)

	_title = Label.new()
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	box.add_child(_title)

	_bar = ProgressBar.new()
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
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
	_title.text = str(motif.get("libelle", "%s / %s" % [motif.get("famille", ""), motif.get("cle", "")]))
	_bar.value = float(motif.get("score", 0.0))
	var polarite := str(motif.get("polarite", ""))
	var fill := StyleBoxFlat.new()
	fill.bg_color = _polarite_color(polarite)
	_bar.add_theme_stylebox_override("fill", fill)
	var trend := tendance if tendance != "" else str(motif.get("tendance", ""))
	_tendance_label(trend)

func _tendance_label(trend: String) -> void:
	var suffix := ""
	match trend:
		"en_amelioration": suffix = " · en amélioration"
		"en_aggravation": suffix = " · en aggravation"
		"stable": suffix = " · stable"
		"indetermine", "": suffix = ""
		_: suffix = " · %s" % trend
	_meta.text = "%d occurrences · score %d%s" % [int(_motif.get("n", 0)), int(_motif.get("score", 0.0)), suffix]

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
