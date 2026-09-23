class_name CoachReadingModal
extends Window
## CoachReadingModal.gd - Fenêtre modale confortable pour la lecture des analyses du Coach IA
## Permet une lecture immersive, affichage du raisonnement (Reasoning/Thinking) et rendu progressif.

var note_data: Dictionary = {}
var is_error_mode: bool = false
var error_message: String = ""

var text_lbl: RichTextLabel
var btn_skip: Button
var _full_raw_text: String = ""
var _is_animating: bool = false
var _chars_shown: int = 0

func _init(p_note: Dictionary = {}, p_is_error: bool = false, p_error_msg: String = "") -> void:
	note_data = p_note
	is_error_mode = p_is_error
	error_message = p_error_msg

func _ready() -> void:
	_configure_window()
	_setup_ui()
	set_process(false)
	if not is_error_mode:
		var raw_resp = note_data.get("response_text", "")
		_start_progressive_reveal(raw_resp)

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
	DesignTokens.adapt_modal_size(self, 410, 680)

func _setup_ui() -> void:
	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 10))
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 10
	root_vbox.offset_top = 10
	root_vbox.offset_right = -10
	root_vbox.offset_bottom = -10
	root_vbox.clip_contents = true
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
		err_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		err_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		err_title.add_theme_color_override("font_color", DesignTokens.DANGER)
		header_vbox.add_child(err_title)

		var err_sub = Label.new()
		err_sub.text = "Explication détaillée et suggestions pour rétablir la connexion :"
		err_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		err_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		var elapsed = float(note_data.get("elapsed_sec", 0.0))
		var cost_lbl = str(note_data.get("cost_label", ""))
		var model_id = str(note_data.get("model_id", "Modèle"))
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

	# --- 2. ACCORDÉON DE RAISONNEMENT (REASONING / THINKING) ---
	var raw_reasoning = str(note_data.get("reasoning_text", "")).strip_edges()
	if raw_reasoning != "":
		var reasoning_card = PanelContainer.new()
		reasoning_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r_style = DesignTokens.flat(DesignTokens.BG_DEEP, DesignTokens.RADIUS_SMALL,
				Color("#6366f1"), 1, Vector2(8, 6))
		reasoning_card.add_theme_stylebox_override("panel", r_style)
		root_vbox.add_child(reasoning_card)

		var r_vbox = VBoxContainer.new()
		r_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_vbox.add_theme_constant_override("separation", 4)
		reasoning_card.add_child(r_vbox)

		var r_btn = Button.new()
		r_btn.text = "🧠 Voir la réflexion interne du modèle (Reasoning)"
		r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		r_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		r_btn.add_theme_color_override("font_color", Color("#c7d2fe"))
		r_vbox.add_child(r_btn)

		var r_scroll = ScrollContainer.new()
		r_scroll.custom_minimum_size = Vector2(0, 110)
		r_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		r_scroll.visible = false
		DesignTokens.touch_scroll(r_scroll)
		r_vbox.add_child(r_scroll)

		var r_lbl = RichTextLabel.new()
		r_lbl.bbcode_enabled = true
		r_lbl.fit_content = true
		r_lbl.scroll_active = false
		r_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
		r_lbl.text = "[color=#cbd5e1][i]%s[/i][/color]" % bbcode_escape(raw_reasoning)
		r_scroll.add_child(r_lbl)

		r_btn.pressed.connect(func():
			r_scroll.visible = not r_scroll.visible
			if r_scroll.visible:
				r_btn.text = "🧠 Masquer la réflexion interne du modèle"
			else:
				r_btn.text = "🧠 Voir la réflexion interne du modèle (Reasoning)"
		)

	# --- 3. ZONE DE LECTURE PRINCIPALE (SCROLLABLE & TOUCH) ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	DesignTokens.touch_scroll(scroll)
	root_vbox.add_child(scroll)

	text_lbl = RichTextLabel.new()
	text_lbl.bbcode_enabled = true
	text_lbl.fit_content = true
	text_lbl.scroll_active = false
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)

	if is_error_mode:
		var err_bbcode = "[color=%s][b]⚠️ Diagnostic de l'erreur du Coach IA :[/b][/color]\n\n" % DesignTokens.DANGER.to_html()
		err_bbcode += "[color=%s]%s[/color]\n\n" % [Color("#fca5a5").to_html(), bbcode_escape(error_message)]
		err_bbcode += "[color=%s][i]💡 Conseils pratiques :\n" % DesignTokens.TEXT_MUTED.to_html()
		err_bbcode += "• Si le message indique un quota dépassé (HTTP 429), patientez 5 à 10 secondes.\n"
		err_bbcode += "• Vérifiez ou saisissez votre clé OpenRouter universelle en haut du Coach.\n"
		err_bbcode += "• Vous pouvez basculer en 1 clic sur un modèle gratuit (:free) ou local.[/i][/color]"
		text_lbl.text = err_bbcode

	scroll.add_child(text_lbl)

	# --- 4. BARRE D'ACTIONS INFÉRIEURE ---
	var actions_row = HBoxContainer.new()
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(actions_row)

	btn_skip = Button.new()
	btn_skip.text = "⏩ Tout afficher"
	btn_skip.visible = false
	btn_skip.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_skip.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_skip.pressed.connect(_finish_progressive_reveal)
	actions_row.add_child(btn_skip)

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
	if is_error_mode:
		var btn_hub = Button.new()
		btn_hub.text = "🔑 Hub & Clé OpenRouter"
		btn_hub.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
		btn_hub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_hub.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		var hub_style = DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL, DesignTokens.PRIMARY_BORDER, 1)
		btn_hub.add_theme_stylebox_override("normal", hub_style)
		btn_hub.add_theme_color_override("font_color", DesignTokens.ON_PRIMARY)
		btn_hub.pressed.connect(func():
			queue_free()
			var tree = Engine.get_main_loop() as SceneTree
			if tree and tree.root:
				var main = tree.root.get_node_or_null("Main")
				if main and main.has_method("_open_modal"):
					main._open_modal(ModelHubModal.new())
				else:
					var m = ModelHubModal.new()
					tree.root.add_child(m)
					m.popup_centered()
		)
		actions_row.add_child(btn_hub)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(queue_free)
	actions_row.add_child(btn_close)

func _start_progressive_reveal(raw_text: String) -> void:
	_full_raw_text = raw_text
	if is_error_mode or raw_text.length() < 60:
		text_lbl.text = format_markdown_to_bbcode(raw_text)
		return
	# Balisage analysé une seule fois : la révélation ne fait qu'avancer visible_characters,
	# sans re-parser le BBCode ni faire sauter la mise en page à chaque image.
	text_lbl.text = format_markdown_to_bbcode(raw_text)
	text_lbl.visible_characters = 0
	_is_animating = true
	_chars_shown = 0
	if btn_skip:
		btn_skip.visible = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _is_animating:
		set_process(false)
		return
	_chars_shown += 16
	if _chars_shown >= text_lbl.get_total_character_count():
		_finish_progressive_reveal()
	else:
		text_lbl.visible_characters = _chars_shown

func _finish_progressive_reveal() -> void:
	_is_animating = false
	set_process(false)
	text_lbl.visible_characters = -1
	if btn_skip:
		btn_skip.visible = false

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
