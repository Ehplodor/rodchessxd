class_name CoachPanel2D
extends PanelContainer
## CoachPanel2D.gd - Interface interactive de coaching IA en langage naturel
## Intégré avec le Hub des Modèles pour afficher le modèle actif et le coût en direct

var response_label: RichTextLabel
var quick_actions_box: HBoxContainer
var question_input: LineEdit
var send_button: Button
var status_label: Label
var model_badge_btn: Button

func _ready() -> void:
	custom_minimum_size = Vector2(300, 230)
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
	bg_style.content_margin_top = 10
	bg_style.content_margin_right = 12
	bg_style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", bg_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# 1. En-tête Coach avec Badge Modèle Cliquable
	var header = HBoxContainer.new()
	vbox.add_child(header)

	var title = Label.new()
	title.text = "🤖 Coach IA"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color("#38bdf8"))
	header.add_child(title)

	model_badge_btn = Button.new()
	model_badge_btn.text = "⚡ Modèle"
	model_badge_btn.tooltip_text = "Cliquer pour ouvrir le Hub des Modèles IA (Changer de modèle, tester les clés, SLM local)"
	model_badge_btn.add_theme_font_size_override("font_size", 10)
	model_badge_btn.pressed.connect(_open_model_hub)
	header.add_child(model_badge_btn)

	status_label = Label.new()
	status_label.text = "Prêt"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color("#64748b"))
	header.add_child(status_label)

	# 2. Zone de texte de la réponse du Coach
	response_label = RichTextLabel.new()
	response_label.bbcode_enabled = true
	response_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_label.custom_minimum_size = Vector2(0, 100)
	response_label.text = "[color=#94a3b8]Posez une question ou cliquez sur une action rapide pour recevoir les conseils du coach sur la position active.[/color]"
	vbox.add_child(response_label)

	# 3. Puces d'actions rapides avec défilement horizontal tactile
	var scroll_chips = ScrollContainer.new()
	scroll_chips.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_chips.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll_chips)

	quick_actions_box = HBoxContainer.new()
	quick_actions_box.add_theme_constant_override("separation", 6)
	scroll_chips.add_child(quick_actions_box)

	_add_quick_chip("💡 Pourquoi ce coup ?", "Explique pourquoi le coup joué est bon ou mauvais.")
	_add_quick_chip("🎯 Quel est le plan ?", "Quel est le plan stratégique principal pour le camp au trait ?")
	_add_quick_chip("⚠️ Menaces ?", "Quelles sont les menaces tactiques immédiates dans cette position ?")
	_add_quick_chip("⚔️ Réfutation", "Montre la réfutation tactique coup par coup si l'adversaire tente une attaque.")
	_add_quick_chip("🛡️ Sécurité Roi", "Analyse la sécurité des rois et les risques d'attaque.")
	_add_quick_chip("👶 Débutant", "Explique la situation avec des mots simples pour débutant.")

	# 4. Ligne de saisie de question libre
	var input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	question_input = LineEdit.new()
	question_input.placeholder_text = "Posez votre question au coach..."
	question_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_input.text_submitted.connect(_on_submit_question)
	input_row.add_child(question_input)

	send_button = Button.new()
	send_button.text = "Envoyer"
	send_button.pressed.connect(func(): _on_submit_question(question_input.text))
	input_row.add_child(send_button)

func _update_model_badge() -> void:
	if not model_badge_btn:
		return
	var active_id = SettingsManager.get_setting("active_model_id", "z-ai/glm-5.3-flash:free")
	var model_info = ModelCatalog.find_model_by_id(active_id)
	var name_short = model_info.get("name", active_id)
	if name_short.length() > 22:
		name_short = name_short.substr(0, 20) + "..."
	
	var prefix = "⚡"
	if model_info.get("modality", 0) == ModelCatalog.Modality.LOCAL_SLM:
		prefix = "💻"
	elif model_info.get("modality", 0) == ModelCatalog.Modality.API_PAID:
		prefix = "🔑"

	model_badge_btn.text = "%s %s" % [prefix, name_short]

func _open_model_hub() -> void:
	var modal = ModelHubModal.new()
	get_tree().root.add_child(modal)
	modal.popup_centered()

func _add_quick_chip(label_text: String, question: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 11)
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
	var extra_context = {}
	if cur_ply >= 0 and cur_ply < game.move_history.size():
		var m = game.move_history[cur_ply]
		last_move_san = m.san
		extra_context["quality"] = m.quality
		extra_context["cp_loss"] = m.centipawn_loss
		extra_context["move_number"] = (cur_ply / 2) + 1
		extra_context["is_check"] = m.is_check
		extra_context["is_checkmate"] = m.is_checkmate
	else:
		extra_context["move_number"] = (game.move_history.size() / 2) + 1

	var eval_cp = EngineManager.eval_score_cp if EngineManager else 0
	var best_move = EngineManager.best_move_uci if EngineManager else ""
	var pv = EngineManager.pv_line if EngineManager else []

	AICoach.ask_coach(fen, last_move_san, eval_cp, best_move, pv, user_question, extra_context)

func _on_thinking_started() -> void:
	status_label.text = "Réflexion..."
	status_label.add_theme_color_override("font_color", Color("#fbbf24"))
	response_label.text = "[color=#fbbf24]⏳ Analyse en cours avec les calculs de Stockfish...[/color]"

func _on_response_received(response: String) -> void:
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
	status_label.text = "Prêt (%.1fs • %s)" % [elapsed_sec, cost_label]
	status_label.add_theme_color_override("font_color", Color("#22c55e"))

func _on_error(error_msg: String) -> void:
	status_label.text = "Erreur"
	status_label.add_theme_color_override("font_color", Color("#ef4444"))
	response_label.text = "[color=#ef4444]⚠️ " + error_msg + "[/color]"
