class_name CoachReadingModal
extends Window
## CoachReadingModal.gd - Fenêtre modale confortable pour la lecture des analyses du Coach IA
## Permet une lecture immersive en plein écran ou superposée, avec copie rapide et fermeture.

var note_data: Dictionary = {}
var is_error_mode: bool = false
var error_message: String = ""

func _init(p_note: Dictionary = {}, p_is_error: bool = false, p_error_msg: String = "") -> void:
	note_data = p_note
	is_error_mode = p_is_error
	error_message = p_error_msg

func _ready() -> void:
	_configure_window()
	_setup_ui()

func _configure_window() -> void:
	exclusive = true
	close_requested.connect(queue_free)

	if is_error_mode:
		title = "⚠️ Diagnostic Erreur Coach IA"
	else:
		var move_san = note_data.get("move_san", "")
		if move_san != "":
			title = "🎓 Conseil du Coach • Coup %s" % move_san
		else:
			title = "🎓 Conseil du Coach"

	var vis = get_viewport().get_visible_rect().size if get_viewport() else Vector2(400, 700)
	var target_w = int(clampf(vis.x * 0.94, 280.0, 430.0)) if vis.x > 0 else 390
	var target_h = int(clampf(vis.y * 0.90, 380.0, 700.0)) if vis.y > 0 else 600
	size = Vector2i(target_w, target_h)

func _setup_ui() -> void:
	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 10))
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 8
	root_vbox.offset_top = 8
	root_vbox.offset_right = -8
	root_vbox.offset_bottom = -8
	root_vbox.add_theme_constant_override("separation", 8)
	bg_panel.add_child(root_vbox)

	# --- 1. EN-TÊTE DE LA CONVERSATION ---
	var header_card = PanelContainer.new()
	header_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	header_card.add_theme_stylebox_override("panel", h_style)
	root_vbox.add_child(header_card)

	var header_vbox = VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_theme_constant_override("separation", 4)
	header_card.add_child(header_vbox)

	if is_error_mode:
		var err_title = Label.new()
		err_title.text = "⚠️ Échec de la requête vers le modèle IA"
		err_title.add_theme_font_size_override("font_size", DesignTokens.FONT_SUBTITLE)
		err_title.add_theme_color_override("font_color", DesignTokens.DANGER)
		header_vbox.add_child(err_title)

		var err_sub = Label.new()
		err_sub.text = "Explication détaillée et suggestions pour rétablir la connexion :"
		err_sub.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		err_sub.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		header_vbox.add_child(err_sub)
	else:
		var meta_row = HBoxContainer.new()
		meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_row.add_theme_constant_override("separation", 8)
		header_vbox.add_child(meta_row)

		var p_code = note_data.get("perspective", "white")
		var p_label = "⚪ Blancs"
		if p_code == "black":
			p_label = "⚫ Noirs"
		elif p_code == "neutral":
			p_label = "⚖️ Neutre"

		var p_lbl = Label.new()
		p_lbl.text = p_label
		p_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		p_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		meta_row.add_child(p_lbl)

		var move_san = note_data.get("move_san", "")
		if move_san != "":
			var m_lbl = Label.new()
			m_lbl.text = "• Coup %s" % move_san
			m_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
			m_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
			meta_row.add_child(m_lbl)

		var model_lbl = Label.new()
		var elapsed = note_data.get("elapsed_sec", 0.0)
		var cost_lbl = note_data.get("cost_label", "")
		var model_id = note_data.get("model_id", "Modèle")
		model_lbl.text = "⚡ %s (%.1fs)" % [model_id, elapsed]
		if cost_lbl != "":
			model_lbl.text += " • %s" % cost_lbl
		model_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		model_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		model_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		model_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		model_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		meta_row.add_child(model_lbl)

		var q_text = note_data.get("user_question", "")
		if q_text != "":
			var q_lbl = Label.new()
			q_lbl.text = "💬 Question : %s" % q_text
			q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			q_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			q_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
			header_vbox.add_child(q_lbl)

	# --- 2. ZONE DE LECTURE PRINCIPALE (SCROLLABLE & TOUCH) ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(scroll)
	root_vbox.add_child(scroll)

	var text_lbl = RichTextLabel.new()
	text_lbl.bbcode_enabled = true
	text_lbl.fit_content = true
	text_lbl.scroll_active = false
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)

	if is_error_mode:
		var err_bbcode = "[color=%s][b]⚠️ Diagnostic de l'erreur du Coach IA :[/b][/color]\n\n" % DesignTokens.DANGER.to_html()
		err_bbcode += "[color=%s]%s[/color]\n\n" % [Color("#fca5a5").to_html(), bbcode_escape(error_message)]
		err_bbcode += "[color=%s][i]💡 Conseils pratiques :\n" % DesignTokens.TEXT_MUTED.to_html()
		err_bbcode += "• Si le message indique un dépassement de quota (HTTP 429), patientez 5 à 10 secondes.\n"
		err_bbcode += "• Vous pouvez changer de modèle à tout moment en cliquant sur le badge ⚡ en haut.\n"
		err_bbcode += "• Vous pouvez vérifier ou saisir une clé API valide dans les Réglages ⚙️.[/i][/color]"
		text_lbl.text = err_bbcode
	else:
		var raw_response = note_data.get("response_text", "")
		text_lbl.text = format_markdown_to_bbcode(raw_response)

	scroll.add_child(text_lbl)

	# --- 3. BARRE D'ACTIONS INFÉRIEURE ---
	var actions_row = HBoxContainer.new()
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(actions_row)

	if not is_error_mode:
		var btn_copy = Button.new()
		btn_copy.text = "📋 Copier l'analyse"
		btn_copy.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
		btn_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_copy.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		btn_copy.pressed.connect(func():
			var raw_txt = note_data.get("response_text", "")
			if raw_txt != "":
				DisplayServer.clipboard_set(raw_txt)
				btn_copy.text = "✅ Copié !"
				var t = create_tween()
				t.tween_interval(1.5)
				t.tween_callback(func():
					if is_instance_valid(btn_copy):
						btn_copy.text = "📋 Copier l'analyse"
				)
		)
		actions_row.add_child(btn_copy)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(queue_free)
	actions_row.add_child(btn_close)

static func bbcode_escape(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")

static func format_markdown_to_bbcode(md: String) -> String:
	var text = md
	var regex_b = RegEx.new()
	regex_b.compile("\\*\\*(.*?)\\*\\*")
	text = regex_b.sub(text, "[b]$1[/b]", true)

	var regex_h = RegEx.new()
	regex_h.compile("(?m)^###?\\s+(.+)$")
	text = regex_h.sub(text, "[b][color=#38bdf8]$1[/color][/b]", true)

	text = text.replace("\n- ", "\n [color=#38bdf8]•[/color] ")
	text = text.replace("\n* ", "\n [color=#38bdf8]•[/color] ")
	return text
