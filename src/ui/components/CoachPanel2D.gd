class_name CoachPanel2D
extends PanelContainer
## CoachPanel2D.gd - Panneau de coaching IA contextuel par coup.
## Affiche uniquement les conversations associées au coup sélectionné.
## Tuiles de prompts directes au-dessus, liste classique et flexible de conversations
## avec icône de lecture "📖 Lire" ouvrant une fenêtre de lecture superposée dédiée (CoachReadingModal).

const CoachReadingModalScript = preload("res://src/ui/components/CoachReadingModal.gd")

const PROMPTS := [
	["💡 Pourquoi ce coup ?", "Explique dans un langage naturel, fluide et vivant pourquoi le coup joué est bon ou mauvais et comment mon camp doit réagir.", "why"],
	["🎯 Quel est mon plan ?", "Explique de vive voix avec des mots simples et naturels quel est le plan stratégique principal pour mon camp dans cette position.", "plan"],
	["🧗 Remonter la pente", "Mon camp est en difficulté ou cherche à renverser la tendance. En tant que coach bienveillant et stratège, aide-moi à remonter la pente dans un style direct, motivant et naturel : donne-moi des principes de défense active, de contre-attaque et de résilience psychologique, et indique les déséquilibres à exploiter, SANS me dévoiler directement le coup exact à jouer.", "comeback"],
	["⚠️ Menaces contre moi ?", "Explique clairement et de manière vivante quelles sont les menaces tactiques immédiates dirigées contre mon camp.", "threats"],
	["⚔️ Réfutation tactique", "Raconte la réfutation tactique coup par coup dans un langage naturel pour sanctionner l'adversaire.", "refutation"],
	["🛡️ Sécurité de mon Roi", "Décris naturellement la sécurité de mon roi, les dangers qui pèsent sur son abri et comment parer les attaques.", "king_safety"],
	["👶 Explique simplement", "Explique la situation comme une histoire vivante, avec des mots très simples, imagés et naturels pour joueur débutant.", "simple"]
]

var move_badge_label: Label
var model_badge_btn: Button
var status_label: Label
var btn_history: Button
var persp_buttons: Dictionary = {}
var voice_buttons: Dictionary = {}

var prompt_grid: GridContainer
var conv_scroll: ScrollContainer
var conv_list_vbox: VBoxContainer

var active_perspective: String = "white"
var active_voice_gender: String = "female"
var is_thinking: bool = false
var thinking_start_time: float = 0.0
var active_query_title: String = ""
var active_query_ply: int = -1

var last_error_message: String = ""
var last_error_ply: int = -1

var current_ply_index: int = -1
var thinking_card_lbl: Label = null

func _ready() -> void:
	custom_minimum_size = Vector2(0, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
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
				_populate_conversation_buttons()
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
		active_voice_gender = sm.get_setting("coach_voice_gender", "female")
		sm.settings_changed.connect(func(k, _v):
			if k == "active_model_id" or k == "ai_provider":
				_update_model_badge()
			elif k == "app_theme_mode":
				_refresh_theme_styles()
			elif k == "coach_voice_gender":
				active_voice_gender = str(_v)
				_update_voice_buttons_style()
		)
	_update_model_badge()
	refresh_for_current_ply()
	set_process(false)

func _process(_delta: float) -> void:
	if is_thinking:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - thinking_start_time
		var step_short = "Réflexion"
		var step_long = "Réflexion en cours"
		if elapsed < 1.2:
			step_short = "Évaluation"
			step_long = "1/4 Évaluation tactique de la position"
		elif elapsed < 2.8:
			step_short = "Calcul variantes"
			step_long = "2/4 Analyse des variantes et menaces"
		elif elapsed < 5.5:
			step_short = "Appel OpenRouter"
			step_long = "3/4 Consultation du modèle OpenRouter"
		else:
			step_short = "Synthèse Coach"
			step_long = "4/4 Synthèse pédagogique du Coach"

		status_label.text = "⏳ %s... (%.1fs)" % [step_short, elapsed]
		if thinking_card_lbl and is_instance_valid(thinking_card_lbl):
			thinking_card_lbl.text = "⏳ [%s] %s\n• %s (%.1fs)" % [
				_perspective_badge_char(active_perspective),
				active_query_title,
				step_long,
				elapsed
			]
	else:
		set_process(false)

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
	bg_style.content_margin_left = 8
	bg_style.content_margin_top = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg_style)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# --- 1. EN-TÊTE : Coup ciblé, Statut, Historique global ---
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header)

	move_badge_label = Label.new()
	move_badge_label.text = "♟️ Position"
	move_badge_label.clip_text = true
	move_badge_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	move_badge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_badge_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	move_badge_label.add_theme_color_override("font_color", DesignTokens.ACCENT)
	header.add_child(move_badge_label)

	status_label = Label.new()
	status_label.text = "Prêt"
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	header.add_child(status_label)

	btn_history = Button.new()
	btn_history.text = "📜"
	btn_history.tooltip_text = "Consulter toutes les analyses archivées de la partie"
	btn_history.custom_minimum_size = Vector2(40, DesignTokens.TOUCH_DENSE)
	btn_history.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_history.pressed.connect(_open_history_modal)
	header.add_child(btn_history)

	# --- 1b. SÉLECTEUR DE MODÈLE IA DÉDIÉ (Proéminent, responsive et toujours visible) ---
	var model_row = HBoxContainer.new()
	model_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(model_row)

	var model_lbl = Label.new()
	model_lbl.text = "Modèle IA :"
	model_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	model_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	model_row.add_child(model_lbl)

	model_badge_btn = Button.new()
	model_badge_btn.text = "⚡ Modèle"
	model_badge_btn.clip_text = true
	model_badge_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	model_badge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_badge_btn.tooltip_text = "Changer de modèle IA (Cloud gratuit, SLM local, Clés API)"
	model_badge_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	model_badge_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var model_btn_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(10, 4))
	model_badge_btn.add_theme_stylebox_override("normal", model_btn_style)
	model_badge_btn.pressed.connect(_open_model_hub)
	model_row.add_child(model_badge_btn)

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
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b.pressed.connect(func():
			_set_perspective(p)
		)
		persp_buttons[p] = b
		persp_row.add_child(b)
	_update_perspective_buttons_style()

	# --- 2b. CHOIX DE LA VOIX DU COACH (Synthèse T2S) ---
	var voice_row = HBoxContainer.new()
	voice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_theme_constant_override("separation", 6)
	main_vbox.add_child(voice_row)

	var v_lbl = Label.new()
	v_lbl.text = "Voix Coach :"
	v_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	v_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	voice_row.add_child(v_lbl)

	for vg in ["female", "male"]:
		var vb = Button.new()
		vb.text = "👩 Féminine" if vg == "female" else "👨 Masculine"
		vb.clip_text = true
		vb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		vb.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		vb.pressed.connect(func():
			_set_voice_gender(vg)
		)
		voice_buttons[vg] = vb
		voice_row.add_child(vb)
	_update_voice_buttons_style()

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
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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

	# --- 4. SÉPARATEUR & TITRE DE LA LISTE DES CONVERSATIONS ---
	var conv_header = Label.new()
	conv_header.text = "💬 Analyses & Conseils pour ce coup :"
	conv_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	conv_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	main_vbox.add_child(conv_header)

	# --- 5. LISTE FLEXIBLE DE CONVERSATIONS (SCROLLABLE) ---
	conv_scroll = ScrollContainer.new()
	conv_scroll.custom_minimum_size = Vector2(0, 120)
	conv_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(conv_scroll)
	main_vbox.add_child(conv_scroll)

	conv_list_vbox = VBoxContainer.new()
	conv_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv_list_vbox.add_theme_constant_override("separation", 6)
	conv_scroll.add_child(conv_list_vbox)

func _refresh_theme_styles() -> void:
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
	bg_style.content_margin_left = 8
	bg_style.content_margin_top = 8
	bg_style.content_margin_right = 8
	bg_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", bg_style)

	if move_badge_label:
		move_badge_label.add_theme_color_override("font_color", DesignTokens.ACCENT)
	if status_label:
		status_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	if model_badge_btn:
		var model_btn_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.BORDER, 1, Vector2(10, 4))
		model_badge_btn.add_theme_stylebox_override("normal", model_btn_style)
		model_badge_btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

	_update_perspective_buttons_style()
	_update_voice_buttons_style()
	_populate_conversation_buttons()

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

func _set_voice_gender(vg: String) -> void:
	active_voice_gender = vg
	var sm = _get_settings_manager()
	if sm:
		sm.set_setting("coach_voice_gender", vg)
	_update_voice_buttons_style()

func _update_voice_buttons_style() -> void:
	for vg in voice_buttons.keys():
		var b: Button = voice_buttons[vg]
		if b == null:
			continue
		if vg == active_voice_gender:
			b.add_theme_color_override("font_color", DesignTokens.ACCENT)
			var active_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					DesignTokens.ACCENT, 1, Vector2(6, 2))
			b.add_theme_stylebox_override("normal", active_s)
		else:
			b.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			var normal_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					Color.TRANSPARENT, 0, Vector2(6, 2))
			b.add_theme_stylebox_override("normal", normal_s)

func _update_model_badge() -> void:
	if not model_badge_btn:
		return
	var sm = _get_settings_manager()
	var active_id = sm.get_setting("active_model_id", "openrouter/free") if sm else "openrouter/free"
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

func _open_reading_modal(note: Dictionary) -> void:
	var modal = CoachReadingModalScript.new(note)
	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(modal)
	else:
		add_child(modal)
		modal.popup_centered()

func _open_error_modal(error_msg: String) -> void:
	var modal = CoachReadingModalScript.new({}, true, error_msg)
	var main = find_parent("Main")
	if main and main.has_method("_open_modal"):
		main._open_modal(modal)
	else:
		add_child(modal)
		modal.popup_centered()

func _open_history_modal() -> void:
	var modal = Window.new()
	modal.title = "📜 Toutes les Analyses de la Partie"
	DesignTokens.adapt_modal_size(modal, 410, 560)
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
					DesignTokens.BORDER, 1, Vector2(8, 6))
			card.add_theme_stylebox_override("panel", c_style)

			var c_vbox = VBoxContainer.new()
			c_vbox.add_theme_constant_override("separation", 4)
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
			c_head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			c_vbox.add_child(c_head)

			var q_lbl = Label.new()
			q_lbl.text = "Q: %s" % note.get("user_question", "")
			q_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			q_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			q_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			c_vbox.add_child(q_lbl)

			var btn_read = Button.new()
			btn_read.text = "📖 Lire l'analyse dans la fenêtre dédiée"
			btn_read.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
			btn_read.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			var captured_note = note
			btn_read.pressed.connect(func():
				modal.queue_free()
				_open_reading_modal(captured_note)
			)
			c_vbox.add_child(btn_read)

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
		var info: Dictionary = gc.game.ply_info(current_ply_index)
		var move_num: int = info["move_number"]
		var is_white: bool = info["is_white"]
		var dots = "." if is_white else "..."
		move_title = "Coup %d%s %s" % [move_num, dots, m.san]
	
	if move_badge_label:
		move_badge_label.text = "♟️ " + move_title

	# Récupération des conversations associées à ce coup
	_populate_conversation_buttons()

func _populate_conversation_buttons() -> void:
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

	# 1. Si une réflexion est en cours pour ce coup, afficher un indicateur visuel
	if is_thinking and active_query_ply == current_ply_index:
		var thinking_card = PanelContainer.new()
		thinking_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.WARNING, 1, Vector2(8, 6))
		thinking_card.add_theme_stylebox_override("panel", t_style)
		
		thinking_card_lbl = Label.new()
		thinking_card_lbl.text = "⏳ [%s] %s • Réflexion en cours..." % [_perspective_badge_char(active_perspective), active_query_title]
		thinking_card_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		thinking_card_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		thinking_card_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		thinking_card_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		thinking_card.add_child(thinking_card_lbl)
		conv_list_vbox.add_child(thinking_card)
	else:
		thinking_card_lbl = null

	# 2. Si une erreur est survenue pour ce coup, afficher une bannière explicative avec bouton d'aide
	if last_error_ply == current_ply_index and last_error_message != "":
		var err_card = PanelContainer.new()
		err_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var e_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.DANGER, 1, Vector2(8, 6))
		err_card.add_theme_stylebox_override("panel", e_style)

		var err_hbox = HBoxContainer.new()
		err_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		err_hbox.add_theme_constant_override("separation", 6)
		err_card.add_child(err_hbox)

		var e_lbl = Label.new()
		e_lbl.text = "⚠️ Erreur IA"
		e_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		e_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		e_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		err_hbox.add_child(e_lbl)

		var btn_err_detail = Button.new()
		btn_err_detail.text = "🔍 Diagnostic"
		btn_err_detail.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn_err_detail.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn_err_detail.pressed.connect(func():
			_open_error_modal(last_error_message)
		)
		err_hbox.add_child(btn_err_detail)

		var btn_err_hub = Button.new()
		btn_err_hub.text = "🔑 Clé / Hub"
		btn_err_hub.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn_err_hub.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn_err_hub.pressed.connect(_open_model_hub)
		err_hbox.add_child(btn_err_hub)

		conv_list_vbox.add_child(err_card)

	# 3. État vide
	if current_plies_notes.is_empty() and not (is_thinking and active_query_ply == current_ply_index):
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune analyse pour ce coup.\nTouchez une tuile ci-dessus pour lancer le coach !"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		conv_list_vbox.add_child(empty_lbl)
		return

	# 4. Liste classique de conversations avec icône de lecture dédiée
	var row_normal := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 6))
	var row_hover := row_normal.duplicate() as StyleBoxFlat
	row_hover.bg_color = DesignTokens.BTN_BG_HOVER
	row_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE

	for idx in range(current_plies_notes.size()):
		var note = current_plies_notes[idx]
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 50)
		card.add_theme_stylebox_override("panel", row_normal)

		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		card.add_child(hbox)

		# Pastille de perspective
		var p_badge_lbl = Label.new()
		p_badge_lbl.text = _perspective_badge_char(note.get("perspective", "white"))
		p_badge_lbl.custom_minimum_size = Vector2(22, 0)
		p_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p_badge_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		hbox.add_child(p_badge_lbl)

		# Textes Titre + Modèle / Extrait (sécurisés contre tout débordement)
		var text_vbox = VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_vbox.add_theme_constant_override("separation", 2)
		hbox.add_child(text_vbox)

		var q_title = note.get("user_question", "Conseil")
		var title_lbl = Label.new()
		title_lbl.text = q_title
		title_lbl.clip_text = true
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		text_vbox.add_child(title_lbl)

		var model_name = note.get("model_id", "Modèle")
		var resp_full = note.get("response_text", "")
		var clean_resp = resp_full.replace("\n", " ").replace("#", "").replace("*", "").strip_edges()
		var sub_lbl = Label.new()
		sub_lbl.text = "%s • %s" % [model_name, clean_resp]
		sub_lbl.clip_text = true
		sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
		sub_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		text_vbox.add_child(sub_lbl)

		# Bouton dédié "📖 Lire"
		var btn_read = Button.new()
		btn_read.text = "📖 Lire"
		btn_read.tooltip_text = "Ouvrir l'analyse dans la fenêtre de lecture dédiée"
		btn_read.custom_minimum_size = Vector2(72, DesignTokens.TOUCH_DENSE)
		btn_read.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)

		var captured_note = note
		btn_read.pressed.connect(func():
			_open_reading_modal(captured_note)
		)
		hbox.add_child(btn_read)

		# Clic sur la carte entière pour ouvrir la modal
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_reading_modal(captured_note)
		)

		conv_list_vbox.add_child(card)

func _execute_prompt(label_text: String, query_text: String, prompt_type: String) -> void:
	if is_thinking:
		return

	active_query_title = label_text
	active_query_ply = current_ply_index

	var sm = _get_settings_manager()
	var prov = sm.get_setting("ai_provider", "openrouter") if sm else "openrouter"
	var active_model = sm.get_setting("active_model_id", "openrouter/free") if sm else "openrouter/free"
	var openrouter_key = sm.get_setting("api_key_openrouter", "") if sm else ""
	var is_free = active_model.begins_with("openrouter/free") or active_model.ends_with(":free") or active_model == "local"
	if prov != "local_slm" and not is_free and openrouter_key.strip_edges() == "":
		_open_error_modal("Une clé API OpenRouter est requise pour utiliser ce modèle (%s).\n\nCliquez ci-dessous pour configurer votre clé dans le Hub des Modèles, ou choisissez un modèle avec le badge Gratuit 🆓." % active_model)
		return

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
		var ply_info: Dictionary = game.ply_info(current_ply_index)
		extra_context["move_number"] = ply_info["move_number"]
		extra_context["ply_index"] = current_ply_index
		extra_context["last_move_color"] = "white" if ply_info["is_white"] else "black"
		extra_context["is_check"] = m.is_check
		extra_context["is_checkmate"] = m.is_checkmate
		extra_context["motifs"] = m.motifs
		extra_context["is_theory"] = m.is_theory
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
	set_process(true)
	thinking_start_time = Time.get_ticks_msec() / 1000.0
	status_label.text = "⏳ Réflexion..."
	status_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	_populate_conversation_buttons()

func _on_thinking_started() -> void:
	_begin_thinking()

func _on_response_received(_response: String) -> void:
	is_thinking = false
	set_process(false)
	status_label.text = "Prêt"
	status_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_populate_conversation_buttons()

func _on_response_with_meta(_response: String, cost_label: String, elapsed_sec: float) -> void:
	is_thinking = false
	set_process(false)
	last_error_message = ""
	last_error_ply = -1
	status_label.text = "Prêt (%.1fs • %s)" % [elapsed_sec, cost_label]
	status_label.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_populate_conversation_buttons()

	# Ne pas ouvrir la modale si la requête provient des raccourcis plateau avec restitution vocale
	var ac = _get_ai_coach()
	if ac and ac.last_query_context.get("extra_context", {}).get("request_audio", false):
		return

	# Ouverture automatique de la fenêtre de lecture superposée pour une consultation optimale
	var dm = _get_database_manager()
	var gc = _get_game_controller()
	if dm and gc and gc.current_game_id != "":
		var game_record = dm.get_game(gc.current_game_id)
		var notes = game_record.get("coach_analyses", [])
		for i in range(notes.size() - 1, -1, -1):
			if notes[i].get("ply_index", -999) == current_ply_index:
				_open_reading_modal(notes[i])
				break

func _on_error(error_msg: String) -> void:
	is_thinking = false
	set_process(false)
	last_error_message = error_msg
	last_error_ply = current_ply_index
	status_label.text = "Erreur (cliquez pour voir)"
	status_label.add_theme_color_override("font_color", DesignTokens.DANGER)
	_populate_conversation_buttons()

	# Ne pas ouvrir la modale si la requête provient des raccourcis plateau (Main.gd s'en charge déjà)
	var ac = _get_ai_coach()
	if ac and ac.last_query_context.get("extra_context", {}).get("request_audio", false):
		return

	_open_error_modal(error_msg)
