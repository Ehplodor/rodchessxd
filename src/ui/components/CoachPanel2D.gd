class_name CoachPanel2D
extends PanelContainer
## CoachPanel2D.gd - Conversation de coaching IA en langage naturel (chat).
## Retours test mobile (M1) : zone de conversation étendue, prompts accessibles
## via tuiles (💡) avec choix de perspective intégré, défilement tactile.

const PROMPTS := [
	["💡 Pourquoi\nce coup ?", "Explique pourquoi le coup joué est bon ou mauvais et comment mon camp doit réagir."],
	["🎯 Quel est\nmon plan ?", "Quel est le plan stratégique principal pour mon camp dans cette position ?"],
	["⚠️ Menaces\ncontre moi ?", "Quelles sont les menaces tactiques immédiates dirigées contre mon camp ?"],
	["⚔️ Réfutation\ntactique", "Montre la réfutation tactique coup par coup pour sanctionner l'adversaire."],
	["🛡️ Sécurité\nde mon Roi", "Analyse la sécurité de mon roi et comment parer les attaques."],
	["👶 Explique\nsimplement", "Explique la situation avec des mots simples et concrets pour joueur débutant."]
]
const TRANSCRIPT_CAP := 40

var response_label: RichTextLabel
var question_input: LineEdit
var send_button: Button
var status_label: Label
var model_badge_btn: Button
var btn_history: Button
var btn_prompts: Button

var active_perspective: String = "white"
var is_thinking: bool = false
var thinking_start_time: float = 0.0
var _transcript: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(280, 180)
	_load_saved_perspective()
	_setup_ui()

	AICoach.coach_thinking_started.connect(_on_thinking_started)
	AICoach.coach_response_received.connect(_on_response_received)
	AICoach.coach_response_with_meta.connect(_on_response_with_meta)
	AICoach.coach_error.connect(_on_error)

	SettingsManager.settings_changed.connect(func(k, _v):
		if k == "active_model_id" or k == "ai_provider":
			_update_model_badge()
	)
	_update_model_badge()

func _process(_delta: float) -> void:
	if is_thinking:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - thinking_start_time
		status_label.text = "⏳ Réflexion... (%.1fs)" % elapsed

func _load_saved_perspective() -> void:
	var saved = SettingsManager.get_setting("coach_perspective", "")
	if saved in ["white", "black", "neutral"]:
		active_perspective = saved
	else:
		active_perspective = "black" if GameController.board_flipped else "white"

func _perspective_label(p: String) -> String:
	match p:
		"black": return "⚫ Noirs"
		"neutral": return "⚖️ Neutre"
	return "⚪ Blancs"

func _setup_ui() -> void:
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = DesignTokens.SURFACE
	bg_style.border_width_left = 1
	bg_style.border_width_top = 1
	bg_style.border_width_right = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = DesignTokens.SURFACE_ELEVATED
	bg_style.corner_radius_top_left = 12
	bg_style.corner_radius_top_right = 12
	bg_style.corner_radius_bottom_left = 12
	bg_style.corner_radius_bottom_right = 12
	bg_style.content_margin_left = 12
	bg_style.content_margin_top = 8
	bg_style.content_margin_right = 12
	bg_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_child(vbox)

	# 1. En-tête : titre, badge modèle cliquable, statut, historique
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "🤖 Coach IA"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title.add_theme_color_override("font_color", DesignTokens.ACCENT)
	header.add_child(title)

	model_badge_btn = Button.new()
	model_badge_btn.text = "⚡ Modèle"
	model_badge_btn.tooltip_text = "Cliquer pour ouvrir le Hub des Modèles IA (Changer de modèle, tester les clés, SLM local)"
	model_badge_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	model_badge_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	model_badge_btn.pressed.connect(_open_model_hub)
	header.add_child(model_badge_btn)

	status_label = Label.new()
	status_label.text = "Prêt"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	header.add_child(status_label)

	btn_history = Button.new()
	btn_history.text = "📜"
	btn_history.tooltip_text = "Consulter toutes les analyses et conseils archivés pour cette partie"
	btn_history.custom_minimum_size = Vector2(56, DesignTokens.TOUCH_DENSE)
	btn_history.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_history.pressed.connect(_open_history_modal)
	header.add_child(btn_history)

	# 2. Zone de conversation (prend tout l'espace disponible)
	var conv_panel = PanelContainer.new()
	conv_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var conv_style := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			Color.TRANSPARENT, 0, Vector2(12, 10))
	conv_panel.add_theme_stylebox_override("panel", conv_style)
	vbox.add_child(conv_panel)

	response_label = RichTextLabel.new()
	response_label.bbcode_enabled = true
	response_label.scroll_active = true
	response_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_label.custom_minimum_size = Vector2(0, 150)
	response_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	DesignTokens.touch_scroll(response_label)
	response_label.text = "[color=%s]Posez une question libre ci-dessous, ou ouvrez 💡 Prompts pour des actions rapides.\nLe contexte (position, évaluation, dernier coup joué) est envoyé automatiquement à chaque question.[/color]" % DesignTokens.TEXT_MUTED.to_html()
	conv_panel.add_child(response_label)

	# 3. Ligne de saisie : question libre + bouton Prompts (💡) + Envoyer
	var input_row = HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	vbox.add_child(input_row)

	question_input = LineEdit.new()
	question_input.placeholder_text = "Votre question au coach..."
	question_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_input.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	question_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	question_input.text_submitted.connect(_on_submit_question)
	input_row.add_child(question_input)

	btn_prompts = Button.new()
	btn_prompts.text = "💡"
	btn_prompts.tooltip_text = "Prompts rapides du coach et choix du point de vue (perspective)"
	btn_prompts.custom_minimum_size = Vector2(60, DesignTokens.TOUCH_MIN)
	btn_prompts.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_prompts.pressed.connect(_open_prompt_modal)
	input_row.add_child(btn_prompts)

	send_button = Button.new()
	send_button.text = "Envoyer"
	send_button.custom_minimum_size = Vector2(110, DesignTokens.TOUCH_MIN)
	send_button.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	send_button.pressed.connect(func(): _on_submit_question(question_input.text))
	input_row.add_child(send_button)

# --- FENÊTRE « PROMPTS » (tuiles + perspective, non scrollable) ---

func _open_prompt_modal() -> void:
	var modal = Window.new()
	modal.title = "💡 Prompts du Coach"
	modal.size = Vector2i(400, 520)
	modal.exclusive = true
	modal.close_requested.connect(modal.queue_free)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",
			DesignTokens.flat(DesignTokens.BG_DEEP, 0, Color.TRANSPARENT, 0, Vector2.ZERO))
	modal.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "Point de vue & Prompts rapides"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title)

	# Perspective : segment étalé
	var persp_row = HBoxContainer.new()
	persp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	persp_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	vbox.add_child(persp_row)

	var persp_btns := {}
	for p in ["white", "black", "neutral"]:
		var b = Button.new()
		b.text = _perspective_label(p)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b.pressed.connect(func():
			_set_perspective(p)
			_tint_perspective_buttons(persp_btns)
		)
		persp_btns[p] = b
		persp_row.add_child(b)
	_tint_perspective_buttons(persp_btns)

	var hint = Label.new()
	hint.text = "Le contexte de la partie est envoyé automatiquement avec chaque prompt."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	hint.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(hint)

	# Tuiles d'actions rapides (grille fixe 2 colonnes, non scrollable)
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_S)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_S)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	var normal_tile := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(10, 6))
	var hover_tile := normal_tile.duplicate() as StyleBoxFlat
	hover_tile.bg_color = DesignTokens.BTN_BG_HOVER
	hover_tile.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var pressed_tile := normal_tile.duplicate() as StyleBoxFlat
	pressed_tile.bg_color = DesignTokens.BTN_BG_PRESSED
	pressed_tile.border_color = DesignTokens.BTN_BORDER_ACTIVE

	for prompt in PROMPTS:
		var tile = Button.new()
		tile.text = prompt[0]
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size = Vector2(0, 64)
		tile.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		tile.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		tile.add_theme_stylebox_override("normal", normal_tile)
		tile.add_theme_stylebox_override("hover", hover_tile)
		tile.add_theme_stylebox_override("pressed", pressed_tile)
		var q: String = prompt[1]
		tile.pressed.connect(func():
			modal.queue_free()
			_send_coach_query(q)
		)
		grid.add_child(tile)

	# Tuile « prompt personnalisé » sur toute la largeur
	var custom_tile = Button.new()
	custom_tile.text = "✏️ Prompt personnalisé…"
	custom_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_tile.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	custom_tile.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	custom_tile.add_theme_color_override("font_color", DesignTokens.ACCENT)
	custom_tile.add_theme_stylebox_override("normal", normal_tile)
	custom_tile.add_theme_stylebox_override("hover", hover_tile)
	custom_tile.add_theme_stylebox_override("pressed", pressed_tile)
	custom_tile.pressed.connect(func():
		modal.queue_free()
		question_input.grab_focus()
	)
	vbox.add_child(custom_tile)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(modal.queue_free)
	vbox.add_child(btn_close)

	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(modal)
	else:
		add_child(modal)
		modal.popup_centered()

func _tint_perspective_buttons(persp_btns: Dictionary) -> void:
	for p in ["white", "black", "neutral"]:
		var b: Button = persp_btns.get(p)
		if b:
			b.modulate = DesignTokens.ACCENT if active_perspective == p else DesignTokens.TEXT_MUTED

func _set_perspective(p: String) -> void:
	active_perspective = p
	SettingsManager.set_setting("coach_perspective", p)

func _update_model_badge() -> void:
	if not model_badge_btn:
		return
	var active_id = SettingsManager.get_setting("active_model_id", "z-ai/glm-5.3-flash:free")
	var model_info = ModelCatalog.find_model_by_id(active_id)
	var name_short = model_info.get("name", active_id)
	if name_short.length() > 14:
		name_short = name_short.substr(0, 12) + ".."

	var prefix = "⚡"
	if model_info.get("modality", 0) == ModelCatalog.Modality.LOCAL_SLM:
		prefix = "💻"
	elif model_info.get("modality", 0) == ModelCatalog.Modality.API_PAID:
		prefix = "🔑"

	model_badge_btn.text = "%s %s" % [prefix, name_short]

func _open_model_hub() -> void:
	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(ModelHubModal.new())
	else:
		var modal = ModelHubModal.new()
		add_child(modal)
		modal.popup_centered()

func _open_history_modal() -> void:
	var modal = Window.new()
	modal.title = "📜 Historique des Conseils du Coach"
	modal.size = Vector2i(400, 480)
	modal.exclusive = true
	modal.close_requested.connect(modal.queue_free)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	panel.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "Analyses & Conseils archivés pour cette partie :"
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(lbl)

	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	scroll.add_child(list_box)

	var tree = Engine.get_main_loop() as SceneTree
	var dm = tree.root.get_node_or_null("DatabaseManager")
	var notes = []
	if dm and GameController.current_game_id != "":
		var game_record = dm.get_game(GameController.current_game_id)
		notes = game_record.get("coach_analyses", [])

	if notes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune analyse de coach archivée pour l'instant.\nPosez des questions au coach pour conserver ses explications !"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		list_box.add_child(empty_lbl)
	else:
		for note in notes:
			var card = PanelContainer.new()
			var c_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					Color.TRANSPARENT, 0, Vector2(8, 6))
			card.add_theme_stylebox_override("panel", c_style)

			var c_vbox = VBoxContainer.new()
			c_vbox.add_theme_constant_override("separation", 3)
			card.add_child(c_vbox)

			var c_head = Label.new()
			var p_badge = "⚪" if note.get("perspective", "") == "white" else ("⚫" if note.get("perspective", "") == "black" else "⚖️")
			c_head.text = "%s Coup %s (%s) • %s" % [
				p_badge,
				note.get("move_san", ""),
				note.get("model_id", "Modèle"),
				note.get("date_str", "")
			]
			c_head.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			c_head.add_theme_color_override("font_color", DesignTokens.WARNING)
			c_vbox.add_child(c_head)

			var q_lbl = Label.new()
			q_lbl.text = "Q: %s" % note.get("user_question", "")
			q_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			q_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			c_vbox.add_child(q_lbl)

			var resp_txt = RichTextLabel.new()
			resp_txt.bbcode_enabled = true
			resp_txt.fit_content = true
			resp_txt.text = _format_markdown_to_bbcode(note.get("response_text", ""))
			c_vbox.add_child(resp_txt)

			list_box.add_child(card)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(modal.queue_free)
	vbox.add_child(btn_close)

	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(modal)
	else:
		add_child(modal)
		modal.popup_centered()

# --- ENVOI & TRANSCRIPTION DE LA CONVERSATION ---

func _on_submit_question(query: String) -> void:
	var trimmed = query.strip_edges()
	if trimmed == "":
		return
	question_input.clear()
	_send_coach_query(trimmed)

func _send_coach_query(user_question: String) -> void:
	_append_line("user", user_question)
	_begin_thinking()

	var game = GameController.game
	var fen = game.get_fen()

	var last_move_san = ""
	var cur_ply = GameController.current_ply_index
	var extra_context = {
		"perspective": active_perspective
	}

	if cur_ply >= 0 and cur_ply < game.move_history.size():
		var m = game.move_history[cur_ply]
		last_move_san = m.san
		extra_context["last_move_natural"] = game.describe_move_natural(m)
		extra_context["last_move_uci"] = m.uci
		extra_context["quality"] = m.quality
		extra_context["cp_loss"] = m.centipawn_loss
		extra_context["move_number"] = (cur_ply / 2) + 1
		extra_context["ply_index"] = cur_ply
		extra_context["last_move_color"] = "white" if (cur_ply % 2 == 0) else "black"
		extra_context["is_check"] = m.is_check
		extra_context["is_checkmate"] = m.is_checkmate
	else:
		extra_context["move_number"] = (game.move_history.size() / 2) + 1

	var eval_cp = EngineManager.eval_score_cp if EngineManager else 0
	var best_move = EngineManager.best_move_uci if EngineManager else ""
	var pv = EngineManager.pv_line if EngineManager else []

	AICoach.ask_coach(fen, last_move_san, eval_cp, best_move, pv, user_question, extra_context)

func _begin_thinking() -> void:
	is_thinking = true
	thinking_start_time = Time.get_ticks_msec() / 1000.0
	status_label.text = "⏳ Réflexion en cours..."
	status_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	_refresh_transcript()

func _append_line(role: String, text: String) -> void:
	var entry := {"role": role, "text": text, "bbcode": ""}
	match role:
		"user":
			entry["bbcode"] = "[color=%s]👤 %s[/color]" % [DesignTokens.TEXT_SECONDARY.to_html(), _bbcode_escape(text)]
		"error":
			entry["bbcode"] = "[color=%s]⚠️ %s[/color]" % [DesignTokens.DANGER.to_html(), text]
		_:
			entry["bbcode"] = _format_markdown_to_bbcode(text)
	_transcript.append(entry)
	while _transcript.size() > TRANSCRIPT_CAP:
		_transcript.remove_at(0)
	_refresh_transcript()

func _refresh_transcript() -> void:
	if _transcript.is_empty():
		return
	var parts := PackedStringArray()
	for line in _transcript:
		parts.append(line["bbcode"])
	if is_thinking:
		parts.append("[color=%s]⏳ Analyse en cours (point de vue : %s)...[/color]"
				% [DesignTokens.WARNING.to_html(), _perspective_label(active_perspective)])
	response_label.text = "\n\n".join(parts)
	response_label.call_deferred("scroll_to_line", response_label.get_line_count() + 8)

func _bbcode_escape(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")

func _format_markdown_to_bbcode(md: String) -> String:
	var text = md
	# Bold **text** -> [b]text[/b]
	var regex_b = RegEx.new()
	regex_b.compile("\\*\\*(.*?)\\*\\*")
	text = regex_b.sub(text, "[b]$1[/b]", true)

	# Headings ### Heading -> [b][color=#38bdf8]Heading[/color][/b]
	var regex_h = RegEx.new()
	regex_h.compile("(?m)^###?\\s+(.+)$")
	text = regex_h.sub(text, "[b][color=#38bdf8]$1[/color][/b]", true)

	# Bullet points
	text = text.replace("\n- ", "\n [color=#38bdf8]•[/color] ")
	text = text.replace("\n* ", "\n [color=#38bdf8]•[/color] ")
	return text

func _on_thinking_started() -> void:
	_begin_thinking()

func _on_response_received(response: String) -> void:
	is_thinking = false
	_append_line("coach", response)

func _on_response_with_meta(_response: String, cost_label: String, elapsed_sec: float) -> void:
	is_thinking = false
	status_label.text = "Prêt (%.1fs • %s)" % [elapsed_sec, cost_label]
	status_label.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_refresh_transcript()

func _on_error(error_msg: String) -> void:
	is_thinking = false
	_append_line("error", error_msg)
	status_label.text = "Erreur"
	status_label.add_theme_color_override("font_color", DesignTokens.DANGER)
