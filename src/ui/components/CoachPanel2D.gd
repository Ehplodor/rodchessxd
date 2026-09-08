class_name CoachPanel2D
extends PanelContainer
## CoachPanel2D.gd - Panneau de coaching IA contextuel par coup.
## Affiche uniquement les conversations associées au coup sélectionné.
## Tuiles de prompts directes au-dessus, piste de conversations cliquables
## sous forme de boutons 2 lignes, et suppression du champ de saisie libre.

const PROMPTS := [
	["💡 Pourquoi ce coup ?", "Explique pourquoi le coup joué est bon ou mauvais et comment mon camp doit réagir.", "why"],
	["🎯 Quel est mon plan ?", "Quel est le plan stratégique principal pour mon camp dans cette position ?", "plan"],
	["🧗 Remonter la pente", "Mon camp est en difficulté ou cherche à renverser la tendance. En tant que coach bienveillant et stratège, aide-moi à remonter la pente : donne-moi des principes de défense active, de contre-attaque et de résilience psychologique, et indique les déséquilibres à exploiter, SANS me dévoiler directement le coup exact à jouer.", "comeback"],
	["⚠️ Menaces contre moi ?", "Quelles sont les menaces tactiques immédiates dirigées contre mon camp ?", "threats"],
	["⚔️ Réfutation tactique", "Montre la réfutation tactique coup par coup pour sanctionner l'adversaire.", "refutation"],
	["🛡️ Sécurité de mon Roi", "Analyse la sécurité de mon roi et comment parer les attaques.", "king_safety"],
	["👶 Explique simplement", "Explique la situation avec des mots simples et concrets pour joueur débutant.", "simple"]
]

var move_badge_label: Label
var model_badge_btn: Button
var status_label: Label
var btn_history: Button
var persp_buttons: Dictionary = {}

var prompt_grid: GridContainer
var conv_scroll: ScrollContainer
var conv_list_vbox: VBoxContainer
var response_scroll: ScrollContainer
var response_label: RichTextLabel
var response_card: PanelContainer

var active_perspective: String = "white"
var is_thinking: bool = false
var thinking_start_time: float = 0.0
var active_query_title: String = ""
var active_query_ply: int = -1

var current_ply_index: int = -1
var selected_note_index: int = -1

func _ready() -> void:
	custom_minimum_size = Vector2(280, 220)
	_load_saved_perspective()
	_setup_ui()

	var ac = _get_ai_coach()
	if ac:
		ac.coach_thinking_started.connect(_on_thinking_started)
		ac.coach_response_received.connect(_on_response_received)
		ac.coach_response_with_meta.connect(_on_response_with_meta)
		ac.coach_error.connect(_on_error)

	var dm = _get_database_manager()
	if dm:
		dm.analysis_added.connect(func(_gid, type):
			if type == "coach":
				_populate_conversation_buttons(not is_thinking)
		)

	var gc = _get_game_controller()
	if gc:
		current_ply_index = gc.current_ply_index
		gc.move_navigated.connect(func(ply):
			current_ply_index = ply
			refresh_for_current_ply()
		)
		gc.position_changed.connect(func():
			if gc:
				current_ply_index = gc.current_ply_index
			refresh_for_current_ply()
		)

	var sm = _get_settings_manager()
	if sm:
		sm.settings_changed.connect(func(k, _v):
			if k == "active_model_id" or k == "ai_provider":
				_update_model_badge()
		)
	_update_model_badge()
	refresh_for_current_ply()

func _process(_delta: float) -> void:
	if is_thinking:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - thinking_start_time
		status_label.text = "⏳ Réflexion... (%.1fs)" % elapsed

func _get_game_controller() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		return tree.root.get_node("GameController")
	return null

func _get_settings_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _get_database_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("DatabaseManager"):
		return tree.root.get_node("DatabaseManager")
	return null

func _get_engine_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		return tree.root.get_node("EngineManager")
	return null

func _get_ai_coach() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("AICoach"):
		return tree.root.get_node("AICoach")
	return null

func _get_model_catalog() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("ModelCatalog"):
		return tree.root.get_node("ModelCatalog")
	return null

func _load_saved_perspective() -> void:
	var sm = _get_settings_manager()
	var saved = sm.get_setting("coach_perspective", "") if sm else ""
	if saved in ["white", "black", "neutral"]:
		active_perspective = saved
	else:
		var gc = _get_game_controller()
		active_perspective = "black" if (gc and gc.board_flipped) else "white"

func _perspective_badge_char(p: String) -> String:
	match p:
		"black": return "⚫"
		"neutral": return "⚖️"
	return "⚪"

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
	bg_style.content_margin_left = 10
	bg_style.content_margin_top = 8
	bg_style.content_margin_right = 10
	bg_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg_style)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# --- 1. EN-TÊTE : Coup ciblé, Modèle, Statut, Historique global ---
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header)

	move_badge_label = Label.new()
	move_badge_label.text = "♟️ Position"
	move_badge_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	move_badge_label.add_theme_color_override("font_color", DesignTokens.ACCENT)
	header.add_child(move_badge_label)

	model_badge_btn = Button.new()
	model_badge_btn.text = "⚡ Modèle"
	model_badge_btn.tooltip_text = "Changer de modèle IA (Cloud gratuit, SLM local, Clés API)"
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
	btn_history.tooltip_text = "Consulter toutes les analyses archivées de la partie"
	btn_history.custom_minimum_size = Vector2(48, DesignTokens.TOUCH_DENSE)
	btn_history.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_history.pressed.connect(_open_history_modal)
	header.add_child(btn_history)

	# --- 2. CHOIX DU POINT DE VUE (PERSPECTIVE) ---
	var persp_row = HBoxContainer.new()
	persp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	persp_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(persp_row)

	var p_lbl = Label.new()
	p_lbl.text = "Point de vue :"
	p_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	p_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	persp_row.add_child(p_lbl)

	for p in ["white", "black", "neutral"]:
		var b = Button.new()
		b.text = _perspective_label(p)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b.pressed.connect(func():
			_set_perspective(p)
		)
		persp_buttons[p] = b
		persp_row.add_child(b)
	_update_perspective_buttons_style()

	# --- 3. TUILES DE PROMPTS DIRECTES ---
	var prompt_section_lbl = Label.new()
	prompt_section_lbl.text = "💡 Actions rapides du Coach :"
	prompt_section_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	prompt_section_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	main_vbox.add_child(prompt_section_lbl)

	prompt_grid = GridContainer.new()
	prompt_grid.columns = 2
	prompt_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prompt_grid.add_theme_constant_override("h_separation", 6)
	prompt_grid.add_theme_constant_override("v_separation", 6)
	main_vbox.add_child(prompt_grid)

	var normal_tile := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 4))
	var hover_tile := normal_tile.duplicate() as StyleBoxFlat
	hover_tile.bg_color = DesignTokens.BTN_BG_HOVER
	hover_tile.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var pressed_tile := normal_tile.duplicate() as StyleBoxFlat
	pressed_tile.bg_color = DesignTokens.BTN_BG_PRESSED
	pressed_tile.border_color = DesignTokens.BTN_BORDER_ACTIVE

	for item in PROMPTS:
		var p_label: String = item[0]
		var p_query: String = item[1]
		var p_type: String = item[2]

		var btn = Button.new()
		btn.text = p_label
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 42)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.add_theme_stylebox_override("normal", normal_tile)
		btn.add_theme_stylebox_override("hover", hover_tile)
		btn.add_theme_stylebox_override("pressed", pressed_tile)
		
		# Couleurs thématiques spéciales pour prompts phares
		if p_type == "comeback":
			btn.add_theme_color_override("font_color", Color("#fbbf24")) # Ambre éclatant
		elif p_type == "why":
			btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
		else:
			btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

		btn.pressed.connect(func():
			_execute_prompt(p_label, p_query, p_type)
		)
		prompt_grid.add_child(btn)

	# --- 4. SÉPARATEUR & TITRE DE LA PISTE DE CONVERSATIONS ---
	var conv_header = Label.new()
	conv_header.text = "💬 Conversations associées à ce coup :"
	conv_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	conv_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	main_vbox.add_child(conv_header)

	# --- 5. PISTE DE CONVERSATIONS (LISTE DE BOUTONS CLIQUABLES) ---
	conv_scroll = ScrollContainer.new()
	conv_scroll.custom_minimum_size = Vector2(0, 110)
	conv_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(conv_scroll)
	main_vbox.add_child(conv_scroll)

	conv_list_vbox = VBoxContainer.new()
	conv_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv_list_vbox.add_theme_constant_override("separation", 4)
	conv_scroll.add_child(conv_list_vbox)

	# --- 6. ZONE DE LECTURE DÉTAILLÉE DE LA CONVERSATION SÉLECTIONNÉE ---
	response_card = PanelContainer.new()
	response_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_card.custom_minimum_size = Vector2(0, 120)
	var card_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	response_card.add_theme_stylebox_override("panel", card_style)
	main_vbox.add_child(response_card)

	response_scroll = ScrollContainer.new()
	response_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	response_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(response_scroll)
	response_card.add_child(response_scroll)

	response_label = RichTextLabel.new()
	response_label.bbcode_enabled = true
	response_label.fit_content = true
	response_label.scroll_active = false
	response_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	response_label.text = "[color=%s]Sélectionnez une conversation ci-dessus ou touchez une tuile pour consulter le coach.[/color]" % DesignTokens.TEXT_MUTED.to_html()
	response_scroll.add_child(response_label)

func _update_perspective_buttons_style() -> void:
	for p in persp_buttons.keys():
		var b: Button = persp_buttons[p]
		if b == null:
			continue
		if p == active_perspective:
			b.add_theme_color_override("font_color", DesignTokens.ACCENT)
			var active_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					DesignTokens.ACCENT, 1, Vector2(6, 2))
			b.add_theme_stylebox_override("normal", active_s)
		else:
			b.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			var normal_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					Color.TRANSPARENT, 0, Vector2(6, 2))
			b.add_theme_stylebox_override("normal", normal_s)

func _set_perspective(p: String) -> void:
	active_perspective = p
	var sm = _get_settings_manager()
	if sm:
		sm.set_setting("coach_perspective", p)
	_update_perspective_buttons_style()

func _update_model_badge() -> void:
	if not model_badge_btn:
		return
	var sm = _get_settings_manager()
	var active_id = sm.get_setting("active_model_id", "z-ai/glm-5.3-flash:free") if sm else "z-ai/glm-5.3-flash:free"
	var mc = _get_model_catalog()
	var model_info = mc.find_model_by_id(active_id) if mc else {}
	var name_short = model_info.get("name", active_id)
	if name_short.length() > 14:
		name_short = name_short.substr(0, 12) + ".."

	var prefix = "⚡"
	var modality = model_info.get("modality", 0)
	if modality == 2:
		prefix = "💻"
	elif modality == 1:
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
	modal.title = "📜 Toutes les Analyses de la Partie"
	modal.size = Vector2i(400, 500)
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
	lbl.text = "Analyses & Conseils archivés pour toute la partie :"
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(lbl)

	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	scroll.add_child(list_box)

	var dm = _get_database_manager()
	var gc = _get_game_controller()
	var notes: Array = []
	if dm and gc and gc.current_game_id != "":
		var game_record = dm.get_game(gc.current_game_id)
		notes = game_record.get("coach_analyses", [])

	if notes.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune analyse archivée pour l'instant.\nUtilisez les tuiles de prompts pour obtenir des conseils !"
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
			var p_badge = _perspective_badge_char(note.get("perspective", "white"))
			c_head.text = "%s Coup %s (%s) • %s" % [
				p_badge,
				note.get("move_san", ""),
				note.get("model_id", "Modèle"),
				note.get("date_str", "")
			]
			c_head.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			c_head.add_theme_color_override("font_color", DesignTokens.WARNING)
			c_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c_vbox.add_child(c_head)

			var q_lbl = Label.new()
			q_lbl.text = "Q: %s" % note.get("user_question", "")
			q_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			q_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

## Rafraîchit l'affichage pour le demi-coup sélectionné
func refresh_for_current_ply() -> void:
	var gc = _get_game_controller()
	if gc:
		current_ply_index = gc.current_ply_index
	
	# Mise à jour du libellé du coup dans l'en-tête
	var move_title = "Position initiale"
	if gc and gc.game and current_ply_index >= 0 and current_ply_index < gc.game.move_history.size():
		var m = gc.game.move_history[current_ply_index]
		var move_num = (current_ply_index / 2) + 1
		var is_white = (current_ply_index % 2 == 0)
		var dots = "." if is_white else "..."
		move_title = "Coup %d%s %s" % [move_num, dots, m.san]
	
	if move_badge_label:
		move_badge_label.text = "♟️ " + move_title

	# Récupération des conversations associées à ce coup
	_populate_conversation_buttons(true)

func _populate_conversation_buttons(select_latest: bool = true) -> void:
	if conv_list_vbox == null:
		return
	for c in conv_list_vbox.get_children():
		c.queue_free()

	var dm = _get_database_manager()
	var gc = _get_game_controller()
	var current_plies_notes: Array = []

	if dm and gc:
		var gid = gc.get_or_create_game_id()
		if gid != "":
			var game_record = dm.get_game(gid)
			var all_notes = game_record.get("coach_analyses", [])
			for n in all_notes:
				if n.get("ply_index", -999) == current_ply_index:
					current_plies_notes.append(n)

	# Si une réflexion est en cours pour ce coup, afficher un bouton de chargement
	if is_thinking and active_query_ply == current_ply_index:
		var thinking_card = PanelContainer.new()
		var t_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.WARNING, 1, Vector2(10, 6))
		thinking_card.add_theme_stylebox_override("panel", t_style)
		
		var t_lbl = Label.new()
		t_lbl.text = "⏳ [%s] %s • Réflexion en cours..." % [_perspective_badge_char(active_perspective), active_query_title]
		t_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		t_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		thinking_card.add_child(t_lbl)
		conv_list_vbox.add_child(thinking_card)

	if current_plies_notes.is_empty() and not (is_thinking and active_query_ply == current_ply_index):
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune analyse pour ce coup.\nTouchez une tuile ci-dessus pour lancer le coach !"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		conv_list_vbox.add_child(empty_lbl)
		if select_latest:
			response_label.text = "[color=%s]Touchez une tuile ci-dessus pour obtenir un conseil pour ce coup.[/color]" % DesignTokens.TEXT_MUTED.to_html()
		return

	# Créer un bouton pour chaque conversation de ce coup
	var btn_normal := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 6))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	for idx in range(current_plies_notes.size()):
		var note = current_plies_notes[idx]
		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 52)
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)

		var p_badge = _perspective_badge_char(note.get("perspective", "white"))
		var model_name = note.get("model_id", "")
		if model_name.length() > 16:
			model_name = model_name.substr(0, 14) + ".."

		var q_title = note.get("user_question", "Conseil")
		if q_title.length() > 30:
			q_title = q_title.substr(0, 28) + "…"

		# Extraction des premiers mots de la réponse
		var resp_full = note.get("response_text", "")
		var clean_resp = resp_full.replace("\n", " ").replace("#", "").replace("*", "").strip_edges()
		var words = clean_resp.split(" ", false)
		var excerpt_words: Array[String] = []
		for w_idx in range(mini(10, words.size())):
			excerpt_words.append(words[w_idx])
		var excerpt = " ".join(excerpt_words)
		if words.size() > 10:
			excerpt += "…"

		# Texte sur deux lignes
		btn.text = "%s %s  •  %s\n%s" % [p_badge, q_title, model_name, excerpt]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

		var captured_note = note
		btn.pressed.connect(func():
			_show_note_detail(captured_note)
		)
		conv_list_vbox.add_child(btn)

	# Afficher par défaut la dernière conversation seulement si demandé
	if select_latest and not current_plies_notes.is_empty() and not is_thinking:
		_show_note_detail(current_plies_notes.back())

func _show_note_detail(note: Dictionary) -> void:
	if response_label == null:
		return
	var p_badge = _perspective_label(note.get("perspective", "white"))
	var model_name = note.get("model_id", "Modèle")
	var elapsed = note.get("elapsed_sec", 0.0)
	var date_str = note.get("date_str", "")
	var q_text = note.get("user_question", "")
	var ans = note.get("response_text", "")

	var meta_header = "[color=%s][b]%s[/b] • Modèle : %s (%.1fs) • %s[/color]\n[color=%s]Prompt : %s[/color]\n\n" % [
		DesignTokens.ACCENT.to_html(),
		p_badge,
		model_name,
		elapsed,
		date_str,
		DesignTokens.TEXT_MUTED.to_html(),
		_bbcode_escape(q_text)
	]

	var body = _format_markdown_to_bbcode(ans)
	response_label.text = meta_header + body
	if response_scroll:
		response_scroll.scroll_vertical = 0

func _execute_prompt(label_text: String, query_text: String, prompt_type: String) -> void:
	if is_thinking:
		return

	active_query_title = label_text
	active_query_ply = current_ply_index

	var gc = _get_game_controller()
	var game = gc.game if gc else null
	if game == null:
		return
	if gc:
		gc.get_or_create_game_id()

	var fen = game.get_fen()
	var last_move_san = ""
	var extra_context = {
		"perspective": active_perspective,
		"prompt_type": prompt_type
	}

	if current_ply_index >= 0 and current_ply_index < game.move_history.size():
		var m = game.move_history[current_ply_index]
		last_move_san = m.san
		extra_context["last_move_natural"] = game.describe_move_natural(m)
		extra_context["last_move_uci"] = m.uci
		extra_context["quality"] = m.quality
		extra_context["cp_loss"] = m.centipawn_loss
		extra_context["move_number"] = (current_ply_index / 2) + 1
		extra_context["ply_index"] = current_ply_index
		extra_context["last_move_color"] = "white" if (current_ply_index % 2 == 0) else "black"
		extra_context["is_check"] = m.is_check
		extra_context["is_checkmate"] = m.is_checkmate
	else:
		extra_context["move_number"] = 1
		extra_context["ply_index"] = -1

	var eng = _get_engine_manager()
	var eval_cp = eng.eval_score_cp if eng else 0
	var best_move = eng.best_move_uci if eng else ""
	var pv = eng.pv_line if eng else []

	_begin_thinking()
	var ac = _get_ai_coach()
	if ac:
		ac.ask_coach(fen, last_move_san, eval_cp, best_move, pv, query_text, extra_context)

func _begin_thinking() -> void:
	is_thinking = true
	thinking_start_time = Time.get_ticks_msec() / 1000.0
	status_label.text = "⏳ Réflexion..."
	status_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	response_label.text = "[color=%s]⏳ Réflexion du coach en cours pour : %s (Point de vue : %s)...[/color]" % [
		DesignTokens.WARNING.to_html(),
		active_query_title,
		_perspective_label(active_perspective)
	]
	_populate_conversation_buttons(false)

func _on_thinking_started() -> void:
	_begin_thinking()

func _on_response_received(response: String) -> void:
	is_thinking = false
	status_label.text = "Prêt"
	status_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_populate_conversation_buttons(true)

func _on_response_with_meta(_response: String, cost_label: String, elapsed_sec: float) -> void:
	is_thinking = false
	status_label.text = "Prêt (%.1fs • %s)" % [elapsed_sec, cost_label]
	status_label.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_populate_conversation_buttons(true)

func _on_error(error_msg: String) -> void:
	is_thinking = false
	status_label.text = "Erreur (détails ci-dessous)"
	status_label.add_theme_color_override("font_color", DesignTokens.DANGER)
	var err_bbcode = "[color=%s][b]⚠️ Diagnostic de l'erreur du Coach IA :[/b][/color]\n\n[color=%s]%s[/color]\n\n[color=%s][i]💡 Conseils pratiques :\n• Si le fournisseur indique une cadence trop rapide (quota / 429), patientez quelques secondes avant de relancer.\n• Vous pouvez changer de modèle à tout moment en cliquant sur le badge du modèle en haut (⚡).\n• Vous pouvez vérifier ou changer votre clé API dans les Paramètres (⚙️).[/i][/color]" % [
		DesignTokens.DANGER.to_html(),
		Color("#fca5a5").to_html(),
		_bbcode_escape(error_msg),
		DesignTokens.TEXT_MUTED.to_html()
	]
	response_label.text = err_bbcode
	if response_scroll:
		response_scroll.scroll_vertical = 0
	_populate_conversation_buttons(false)

func _bbcode_escape(s: String) -> String:
	return s.replace("[", "[lb]").replace("]", "[rb]")

func _format_markdown_to_bbcode(md: String) -> String:
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
