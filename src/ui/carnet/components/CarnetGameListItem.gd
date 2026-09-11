class_name CarnetGameListItem
extends HBoxContainer
## CarnetGameListItem.gd — T3 : ligne de partie dans la liste Sync (titre, date, perspective, statut, actions).

signal reanalyze_requested(game_id: String)
signal perspective_cycle_requested(game_id: String)
signal remove_requested(game_id: String)

var _game_id := ""
var _game_data: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	add_theme_constant_override("separation", DesignTokens.SPACE_S)

func set_game(game_data: Dictionary) -> void:
	_game_data = game_data
	_game_id = str(game_data.get("game_id", ""))

	# Clear and rebuild
	for child in get_children():
		child.queue_free()

	var title = str(game_data.get("title", ""))
	if title == "":
		var white = str(game_data.get("white_name", ""))
		var black = str(game_data.get("black_name", ""))
		title = "%s vs %s" % [white, black]
	if title.length() > 40:
		title = title.substr(0, 37) + "…"

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	add_child(title_lbl)

	var date_str = str(game_data.get("date", ""))
	if date_str != "" and date_str.length() >= 10:
		date_str = date_str.substr(0, 10)
	var date_lbl = Label.new()
	date_lbl.text = date_str
	date_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	date_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	date_lbl.custom_minimum_size.x = 80.0
	add_child(date_lbl)

	var perspective := str(game_data.get("perspective", ""))
	var perspective_text := "⟳"
	var perspective_color := DesignTokens.ACCENT
	match perspective:
		"white":
			perspective_text = "⚪"
			perspective_color = DesignTokens.TEXT_PRIMARY
		"black":
			perspective_text = "⚫"
			perspective_color = DesignTokens.TEXT_PRIMARY
	var perspective_btn = Button.new()
	perspective_btn.text = perspective_text
	perspective_btn.tooltip_text = "Perspective: %s (clic pour changer)" % (_perspective_label(perspective))
	perspective_btn.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	perspective_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	perspective_btn.add_theme_color_override("font_color", perspective_color)
	perspective_btn.flat = true
	perspective_btn.pressed.connect(func(): perspective_cycle_requested.emit(_game_id))
	add_child(perspective_btn)

	var status := str(game_data.get("status", "up_to_date"))
	var status_text := ""
	var status_color := DesignTokens.TEXT_MUTED
	match status:
		"pending":
			status_text = "⏳"
			status_color = DesignTokens.WARNING
		"stale":
			status_text = "⚠"
			status_color = DesignTokens.WARNING
		"up_to_date":
			status_text = "✓"
			status_color = DesignTokens.SUCCESS
	var status_btn = Button.new()
	status_btn.text = status_text
	status_btn.tooltip_text = "Statut: %s (%s)" % [status, CarnetPresenter.reason_label(str(game_data.get("reason", "")))]
	status_btn.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	status_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	status_btn.add_theme_color_override("font_color", status_color)
	status_btn.flat = true
	status_btn.disabled = true
	add_child(status_btn)

	var actions_box = HBoxContainer.new()
	actions_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_child(actions_box)

	var btn_reanalyze = Button.new()
	btn_reanalyze.text = "⟳"
	btn_reanalyze.tooltip_text = "Réanalyser cette partie"
	btn_reanalyze.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	btn_reanalyze.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_reanalyze.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_reanalyze.flat = true
	btn_reanalyze.pressed.connect(func(): reanalyze_requested.emit(_game_id))
	actions_box.add_child(btn_reanalyze)

	var btn_perspective = Button.new()
	btn_perspective.text = "↻"
	btn_perspective.tooltip_text = "Forcer perspective (cycle auto/blanc/noir)"
	btn_perspective.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	btn_perspective.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_perspective.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_perspective.flat = true
	btn_perspective.pressed.connect(func(): perspective_cycle_requested.emit(_game_id))
	actions_box.add_child(btn_perspective)

	var btn_remove = Button.new()
	btn_remove.text = "🗑"
	btn_remove.tooltip_text = "Retirer du carnet"
	btn_remove.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	btn_remove.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_remove.add_theme_color_override("font_color", DesignTokens.DANGER)
	btn_remove.flat = true
	btn_remove.pressed.connect(func(): remove_requested.emit(_game_id))
	actions_box.add_child(btn_remove)

func _perspective_label(perspective: String) -> String:
	match perspective:
		"white": return "Blancs"
		"black": return "Noirs"
	return "Auto"