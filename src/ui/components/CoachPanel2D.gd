class_name CoachPanel2D
extends PanelContainer
## CoachPanel2D.gd - Interface interactive de coaching IA en langage naturel
## Intégré avec le sélecteur de perspective (Blancs/Noirs/Neutre), le Hub des Modèles et l'Historique local

var response_label: RichTextLabel
var quick_actions_box: HBoxContainer
var question_input: LineEdit
var send_button: Button
var status_label: Label
var model_badge_btn: Button

var btn_persp_white: Button
var btn_persp_black: Button
var btn_persp_neutral: Button
var btn_history: Button

var active_perspective: String = "white"
var is_thinking: bool = false
var thinking_start_time: float = 0.0

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
	_update_perspective_buttons()

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

func _setup_ui() -> void:
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color("#0f172a")
	bg_style.border_width_left = 1
	bg_style.border_width_top = 1
	bg_style.border_width_right = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color("#1e293b")
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
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# 1. En-tête Coach avec Badge Modèle Cliquable & Statut
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var title = Label.new()
	title.text = "🤖 Coach IA"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("#38bdf8"))
	header.add_child(title)

	model_badge_btn = Button.new()
	model_badge_btn.text = "⚡ Modèle"
	model_badge_btn.tooltip_text = "Cliquer pour ouvrir le Hub des Modèles IA (Changer de modèle, tester les clés, SLM local)"
	model_badge_btn.custom_minimum_size = Vector2(0, 24)
	model_badge_btn.add_theme_font_size_override("font_size", 9)
	model_badge_btn.pressed.connect(_open_model_hub)
	header.add_child(model_badge_btn)

	status_label = Label.new()
	status_label.text = "Prêt"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("#64748b"))
	header.add_child(status_label)

	# 2. Barre de Sélection de la Perspective & Historique local
	var sub_bar = HBoxContainer.new()
	sub_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_bar.add_theme_constant_override("separation", 4)
	vbox.add_child(sub_bar)

	var lbl_vue = Label.new()
	lbl_vue.text = "Vue :"
	lbl_vue.add_theme_font_size_override("font_size", 9)
	lbl_vue.add_theme_color_override("font_color", Color("#94a3b8"))
	sub_bar.add_child(lbl_vue)

	btn_persp_white = Button.new()
	btn_persp_white.text = "⚪ Blancs"
	btn_persp_white.custom_minimum_size = Vector2(58, 22)
	btn_persp_white.add_theme_font_size_override("font_size", 9)
	btn_persp_white.pressed.connect(func(): _set_perspective("white"))
	sub_bar.add_child(btn_persp_white)

	btn_persp_black = Button.new()
	btn_persp_black.text = "⚫ Noirs"
	btn_persp_black.custom_minimum_size = Vector2(58, 22)
	btn_persp_black.add_theme_font_size_override("font_size", 9)
	btn_persp_black.pressed.connect(func(): _set_perspective("black"))
	sub_bar.add_child(btn_persp_black)

	btn_persp_neutral = Button.new()
	btn_persp_neutral.text = "⚖️ Neutre"
	btn_persp_neutral.custom_minimum_size = Vector2(58, 22)
	btn_persp_neutral.add_theme_font_size_override("font_size", 9)
	btn_persp_neutral.pressed.connect(func(): _set_perspective("neutral"))
	sub_bar.add_child(btn_persp_neutral)

	var sub_spacer = Control.new()
	sub_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_bar.add_child(sub_spacer)

	btn_history = Button.new()
	btn_history.text = "📜 Historique"
	btn_history.tooltip_text = "Consulter toutes les analyses et conseils archivés pour cette partie"
	btn_history.custom_minimum_size = Vector2(0, 22)
	btn_history.add_theme_font_size_override("font_size", 9)
	btn_history.pressed.connect(_open_history_modal)
	sub_bar.add_child(btn_history)

	# 3. Zone de texte de la réponse du Coach
	response_label = RichTextLabel.new()
	response_label.bbcode_enabled = true
	response_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_label.custom_minimum_size = Vector2(0, 65)
	response_label.text = "[color=#94a3b8]Sélectionnez votre perspective ci-dessus (⚪ Blancs ou ⚫ Noirs), puis posez une question ou cliquez sur une action rapide.[/color]"
	vbox.add_child(response_label)

	# 4. Puces d'actions rapides avec défilement horizontal tactile
	var scroll_chips = ScrollContainer.new()
	scroll_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_chips.custom_minimum_size = Vector2(0, 28)
	scroll_chips.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_chips.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll_chips)

	quick_actions_box = HBoxContainer.new()
	quick_actions_box.add_theme_constant_override("separation", 6)
	scroll_chips.add_child(quick_actions_box)

	_add_quick_chip("💡 Pourquoi ce coup ?", "Explique pourquoi le coup joué est bon ou mauvais et comment mon camp doit réagir.")
	_add_quick_chip("🎯 Quel est mon plan ?", "Quel est le plan stratégique principal pour mon camp dans cette position ?")
	_add_quick_chip("⚠️ Menaces contre moi ?", "Quelles sont les menaces tactiques immédiates dirigées contre mon camp ?")
	_add_quick_chip("⚔️ Réfutation tactique", "Montre la réfutation tactique coup par coup pour sanctionner l'adversaire.")
	_add_quick_chip("🛡️ Sécurité de mon Roi", "Analyse la sécurité de mon roi et comment parer les attaques.")
	_add_quick_chip("👶 Explique simplement", "Explique la situation avec des mots simples et concrets pour joueur débutant.")

	# 5. Ligne de saisie de question libre
	var input_row = HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	question_input = LineEdit.new()
	question_input.placeholder_text = "Posez votre question au coach..."
	question_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_input.text_submitted.connect(_on_submit_question)
	input_row.add_child(question_input)

	send_button = Button.new()
	send_button.text = "Envoyer"
	send_button.custom_minimum_size = Vector2(65, 30)
	send_button.add_theme_font_size_override("font_size", 11)
	send_button.pressed.connect(func(): _on_submit_question(question_input.text))
	input_row.add_child(send_button)

func _set_perspective(p: String) -> void:
	active_perspective = p
	SettingsManager.set_setting("coach_perspective", p)
	_update_perspective_buttons()

func _update_perspective_buttons() -> void:
	if not btn_persp_white:
		return
	
	var normal_color = Color("#475569")
	var active_color = Color("#0284c7")

	btn_persp_white.modulate = active_color if active_perspective == "white" else normal_color
	btn_persp_black.modulate = active_color if active_perspective == "black" else normal_color
	btn_persp_neutral.modulate = active_color if active_perspective == "neutral" else normal_color

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
	vbox.add_theme_constant_override("separation", 8)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	panel.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "Analyses & Conseils archivés pour cette partie :"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	vbox.add_child(lbl)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
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
		empty_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
		list_box.add_child(empty_lbl)
	else:
		for note in notes:
			var card = PanelContainer.new()
			var c_style = StyleBoxFlat.new()
			c_style.bg_color = Color("#1e293b")
			c_style.corner_radius_top_left = 6
			c_style.corner_radius_top_right = 6
			c_style.corner_radius_bottom_left = 6
			c_style.corner_radius_bottom_right = 6
			c_style.content_margin_left = 8
			c_style.content_margin_top = 6
			c_style.content_margin_right = 8
			c_style.content_margin_bottom = 6
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
			c_head.add_theme_font_size_override("font_size", 10)
			c_head.add_theme_color_override("font_color", Color("#fbbf24"))
			c_vbox.add_child(c_head)

			var q_lbl = Label.new()
			q_lbl.text = "Q: %s" % note.get("user_question", "")
			q_lbl.add_theme_font_size_override("font_size", 10)
			q_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
			c_vbox.add_child(q_lbl)

			var resp_txt = RichTextLabel.new()
			resp_txt.bbcode_enabled = true
			resp_txt.fit_content = true
			resp_txt.text = _format_markdown_to_bbcode(note.get("response_text", ""))
			c_vbox.add_child(resp_txt)

			list_box.add_child(card)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, 32)
	btn_close.pressed.connect(modal.queue_free)
	vbox.add_child(btn_close)

	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(modal)
	else:
		add_child(modal)
		modal.popup_centered()

func _add_quick_chip(label_text: String, question: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(func(): _send_coach_query(question))
	quick_actions_box.add_child(btn)

func _on_submit_question(query: String) -> void:
	var trimmed = query.strip_edges()
	if trimmed == "":
		return
	question_input.clear()
	_send_coach_query(trimmed)

func _send_coach_query(user_question: String) -> void:
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

func _on_thinking_started() -> void:
	is_thinking = true
	thinking_start_time = Time.get_ticks_msec() / 1000.0
	status_label.text = "⏳ Réflexion en cours..."
	status_label.add_theme_color_override("font_color", Color("#fbbf24"))
	response_label.text = "[color=#fbbf24]⏳ Analyse en cours avec Stockfish et le Coach IA (point de vue : %s)...[/color]" % ("Blancs" if active_perspective == "white" else ("Noirs" if active_perspective == "black" else "Neutre"))

func _on_response_received(response: String) -> void:
	is_thinking = false
	var formatted = _format_markdown_to_bbcode(response)
	response_label.text = formatted

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

func _on_response_with_meta(_response: String, cost_label: String, elapsed_sec: float) -> void:
	is_thinking = false
	status_label.text = "Prêt (%.1fs • %s)" % [elapsed_sec, cost_label]
	status_label.add_theme_color_override("font_color", Color("#22c55e"))

func _on_error(error_msg: String) -> void:
	is_thinking = false
	status_label.text = "Erreur"
	status_label.add_theme_color_override("font_color", Color("#ef4444"))
	response_label.text = "[color=#ef4444]⚠️ " + error_msg + "[/color]"
