class_name SettingsModal
extends Window
## SettingsModal.gd - Fenêtre modale des paramètres de l'application et des clés IA

var _init_threads: int = 2
var _init_hash: int = 32
var _init_live_depth: int = 16
var _init_analysis_depth: int = 18

func _ready() -> void:
	title = "Paramètres & Clés IA"
	size = Vector2i(410, 620)
	exclusive = true
	close_requested.connect(_on_save_and_close)
	_init_threads = SettingsManager.get_setting("engine_threads", 2)
	_init_hash = SettingsManager.get_setting("engine_hash_mb", 32)
	var def_live = 12 if (OS.has_feature("android") or OS.has_feature("ios")) else 16
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	_init_live_depth = SettingsManager.get_setting("engine_depth", def_live)
	_init_analysis_depth = SettingsManager.get_setting("analysis_depth", def_anal)
	_setup_ui()

func _setup_ui() -> void:
	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 10
	root_vbox.offset_top = 10
	root_vbox.offset_right = -10
	root_vbox.offset_bottom = -10
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# --- SECTION MOTEUR ---
	_add_section_header(vbox, "⚡ Moteur d'Échecs Stockfish")

	# Threads
	var threads_row = HBoxContainer.new()
	threads_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var threads_lbl = Label.new()
	threads_lbl.text = "Cœurs CPU alloués (Threads) :"
	threads_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	threads_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threads_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	threads_row.add_child(threads_lbl)

	var threads_spin = SpinBox.new()
	threads_spin.min_value = 1
	threads_spin.max_value = 8
	threads_spin.value = SettingsManager.get_setting("engine_threads", 2)
	threads_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_threads", int(val)))
	threads_spin.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	threads_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	threads_row.add_child(threads_spin)
	vbox.add_child(threads_row)

	# Profondeur Live (Échiquier)
	var def_live = 12 if (OS.has_feature("android") or OS.has_feature("ios")) else 16
	var live_depth_row = HBoxContainer.new()
	live_depth_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var live_depth_lbl = Label.new()
	live_depth_lbl.text = "Profondeur en direct (Live) :"
	live_depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_depth_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live_depth_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	live_depth_row.add_child(live_depth_lbl)

	var live_depth_spin = SpinBox.new()
	live_depth_spin.min_value = 8
	live_depth_spin.max_value = 24
	live_depth_spin.value = SettingsManager.get_setting("engine_depth", def_live)
	live_depth_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_depth", int(val)))
	live_depth_spin.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	live_depth_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	live_depth_row.add_child(live_depth_spin)
	vbox.add_child(live_depth_row)

	# Profondeur Analyse Globale (Bilan de partie)
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var anal_depth_row = HBoxContainer.new()
	anal_depth_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var anal_depth_lbl = Label.new()
	anal_depth_lbl.text = "Profondeur analyse de partie (Bilan) :"
	anal_depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anal_depth_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anal_depth_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	anal_depth_row.add_child(anal_depth_lbl)

	var anal_depth_spin = SpinBox.new()
	anal_depth_spin.min_value = 10
	anal_depth_spin.max_value = 26
	anal_depth_spin.value = SettingsManager.get_setting("analysis_depth", def_anal)
	anal_depth_spin.value_changed.connect(func(val): SettingsManager.set_setting("analysis_depth", int(val)))
	anal_depth_spin.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	anal_depth_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	anal_depth_row.add_child(anal_depth_spin)
	vbox.add_child(anal_depth_row)

	# Mémoire (Hash) — Stockfish
	var hash_row = HBoxContainer.new()
	hash_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hash_lbl = Label.new()
	hash_lbl.text = "Mémoire de transposition (Hash Mo) :"
	hash_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hash_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hash_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	hash_row.add_child(hash_lbl)

	var hash_spin = SpinBox.new()
	hash_spin.min_value = 16
	hash_spin.max_value = 2048
	hash_spin.step = 16
	hash_spin.value = SettingsManager.get_setting("engine_hash_mb", 32)
	hash_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_hash_mb", int(val)))
	hash_spin.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	hash_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	hash_row.add_child(hash_spin)
	vbox.add_child(hash_row)

	var param_note = Label.new()
	param_note.text = "Comment ajuster vitesse vs profondeur ?\n• Profondeur Live : évaluation instantanée coup par coup sur l'échiquier (rapide, sans coupure moteur).\n• Profondeur Bilan : analyse approfondie de toute la partie (précision, gaffes, ELO).\n• Threads & Hash : nombre de cœurs CPU et mémoire cache (redémarre le moteur si modifié)."
	param_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	param_note.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	param_note.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(param_note)

	_add_section_header(vbox, "🤖 Intelligence Artificielle & Coach")

	var hub_btn = Button.new()
	hub_btn.text = "⚡ Gérer les Modèles IA & Coûts en direct..."
	hub_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	hub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	hub_btn.pressed.connect(func():
		hide()
		var hub = ModelHubModal.new()
		var p = get_parent()
		if p:
			p.add_child(hub)
		else:
			get_tree().root.add_child(hub)
		hub.popup_centered()
		hub.close_requested.connect(func():
			if is_instance_valid(self):
				show()
		)
	)
	vbox.add_child(hub_btn)

	# Fournisseur IA
	var prov_lbl = Label.new()
	prov_lbl.text = "Mode de Coach IA :"
	prov_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(prov_lbl)

	var prov_opt = OptionButton.new()
	prov_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prov_opt.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	prov_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	prov_opt.add_item("Cloud Gratuit (OpenRouter / Gemini)", 0)
	prov_opt.add_item("SLM Local (Ollama hors-ligne)", 1)
	prov_opt.add_item("Clés API Directes (OpenAI / DeepSeek / Claude)", 2)
	
	var cur_prov = SettingsManager.get_setting("ai_provider", "free_cloud")
	match cur_prov:
		"free_cloud": prov_opt.selected = 0
		"local_slm": prov_opt.selected = 1
		"api_key": prov_opt.selected = 2
	
	prov_opt.item_selected.connect(func(idx):
		match idx:
			0: SettingsManager.set_setting("ai_provider", "free_cloud")
			1: SettingsManager.set_setting("ai_provider", "local_slm")
			2: SettingsManager.set_setting("ai_provider", "api_key")
	)
	vbox.add_child(prov_opt)

	# Personnalité
	var pers_lbl = Label.new()
	pers_lbl.text = "Personnalité du Coach :"
	pers_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(pers_lbl)

	var pers_opt = OptionButton.new()
	pers_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pers_opt.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	pers_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	pers_opt.add_item("Grand-Maître Mentor (Équilibré)", 0)
	pers_opt.add_item("Chasseur de Gaffes (Tactique & Direct)", 1)
	pers_opt.add_item("Pédagogue Débutant / Enfant (Simple)", 2)
	
	var cur_pers = SettingsManager.get_setting("coach_personality", "mentor")
	match cur_pers:
		"mentor": pers_opt.selected = 0
		"blunder_hunter": pers_opt.selected = 1
		"kids_simple": pers_opt.selected = 2
	
	pers_opt.item_selected.connect(func(idx):
		match idx:
			0: SettingsManager.set_setting("coach_personality", "mentor")
			1: SettingsManager.set_setting("coach_personality", "blunder_hunter")
			2: SettingsManager.set_setting("coach_personality", "kids_simple")
	)
	vbox.add_child(pers_opt)

	# Clés API
	_add_api_key_field(vbox, "Clé OpenRouter (Modèles gratuits & économiques) :", "api_key_openrouter")
	_add_api_key_field(vbox, "Clé Google Gemini (Gratuite / Payante) :", "api_key_gemini")
	_add_api_key_field(vbox, "Clé Groq Cloud (Gratuite) :", "api_key_groq")
	_add_api_key_field(vbox, "Clé DeepSeek (V4 Flash / R1) :", "api_key_deepseek")
	_add_api_key_field(vbox, "Clé OpenAI (GPT-4o) :", "api_key_openai")
	_add_api_key_field(vbox, "Clé Anthropic (Claude 3.5) :", "api_key_anthropic")

	# --- SECTION APPARENCE & AUDIO ---
	_add_section_header(vbox, "🎨 Thème & Sons")

	var theme_lbl = Label.new()
	theme_lbl.text = "Thème de l'échiquier :"
	theme_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(theme_lbl)

	var theme_opt = OptionButton.new()
	theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_opt.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	theme_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	theme_opt.add_item("Dark Modern (Ardoise & Néon)", 0)
	theme_opt.add_item("Émeraude (Lichess Classique)", 1)
	theme_opt.add_item("Bois Naturel (Tournoi)", 2)

	var cur_theme = SettingsManager.get_setting("board_theme", "dark_modern")
	match cur_theme:
		"dark_modern": theme_opt.selected = 0
		"emerald": theme_opt.selected = 1
		"wood": theme_opt.selected = 2

	theme_opt.item_selected.connect(func(idx):
		match idx:
			0: SettingsManager.set_setting("board_theme", "dark_modern")
			1: SettingsManager.set_setting("board_theme", "emerald")
			2: SettingsManager.set_setting("board_theme", "wood")
	)
	vbox.add_child(theme_opt)

	# Son
	var sound_check = CheckButton.new()
	sound_check.text = "Effets sonores activés"
	sound_check.button_pressed = SettingsManager.get_setting("sound_enabled", true)
	sound_check.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	sound_check.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	sound_check.toggled.connect(func(val): SettingsManager.set_setting("sound_enabled", val))
	vbox.add_child(sound_check)

	# --- SECTION À PROPOS & LOGS (M8 / observabilité beta) ---
	_add_section_header(vbox, "🛠️ À propos & Logs")

	var about_lbl = Label.new()
	about_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	about_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	about_lbl.text = _app_info_text()
	vbox.add_child(about_lbl)

	var export_btn = Button.new()
	export_btn.text = "📤 Exporter les logs"
	export_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	export_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	export_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	export_btn.pressed.connect(func():
		var export_feedback = Label.new()
		export_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		export_feedback.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		export_feedback.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		export_feedback.text = _export_logs()
		vbox.add_child(export_feedback)
	)
	vbox.add_child(export_btn)

	# Pied de fenêtre fixe : Bouton "Fermer & Enregistrer" TOUJOURS visible sans scroller
	var bottom_bar = MarginContainer.new()
	bottom_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_theme_constant_override("margin_top", 4)
	bottom_bar.add_theme_constant_override("margin_bottom", 2)
	root_vbox.add_child(bottom_bar)

	var btn_close = Button.new()
	btn_close.text = "💾 Fermer & Enregistrer"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	var close_style = DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL, DesignTokens.PRIMARY_BORDER, 1)
	btn_close.add_theme_stylebox_override("normal", close_style)
	btn_close.add_theme_color_override("font_color", DesignTokens.ON_PRIMARY)
	btn_close.pressed.connect(_on_save_and_close)
	bottom_bar.add_child(btn_close)

func _on_save_and_close() -> void:
	SettingsManager.save_settings()
	var new_threads = SettingsManager.get_setting("engine_threads", 2)
	var new_hash = SettingsManager.get_setting("engine_hash_mb", 32)
	var new_live_depth = SettingsManager.get_setting("engine_depth", _init_live_depth)

	var tree = get_tree()
	if tree and tree.root and tree.root.has_node("EngineManager"):
		var em = tree.root.get_node("EngineManager")
		var startup_changed = (new_threads != _init_threads or new_hash != _init_hash)
		var live_depth_changed = (new_live_depth != _init_live_depth)

		if startup_changed:
			print("SettingsModal: Threads ou Hash modifiés -> redémarrage du moteur.")
			if em.has_method("apply_engine_settings"):
				em.apply_engine_settings()
			elif em.has_method("restart_engine"):
				em.restart_engine()
		elif live_depth_changed:
			print("SettingsModal: Profondeur live modifiée -> réévaluation sans redémarrage moteur.")
			var gc = tree.root.get_node_or_null("GameController")
			if gc and gc.game and em.is_engine_running:
				em.evaluate_position(gc.game.get_fen())
		else:
			print("SettingsModal: Aucun paramètre moteur modifié -> moteur conservé en fonctionnement.")
	queue_free()

func _app_logger() -> Node:
	var t := get_tree()
	if t and t.root and t.root.has_node("AppLogger"):
		return t.root.get_node("AppLogger")
	return null

func _app_info_text() -> String:
	var l = _app_logger()
	if l and l.has_method("info_line"):
		return l.info_line()
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	return "RodChessXD v%s — %s (%s)" % [ver, OS.get_name(), OS.get_processor_name()]

func _export_logs() -> String:
	var l = _app_logger()
	if l and l.has_method("export_logs"):
		var path: String = l.export_logs()
		if path != "":
			DisplayServer.clipboard_set(path)
			return "Logs : %s\n(chemin copié dans le presse-papiers)" % path
	return "Logger indisponible (hors application)."

func _add_section_header(parent: Node, title_text: String) -> void:
	var lbl = Label.new()
	lbl.text = title_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	parent.add_child(lbl)

func _add_api_key_field(parent: Node, label_text: String, setting_key: String) -> void:
	var row = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	row.add_child(lbl)

	var edit_box = HBoxContainer.new()
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.add_theme_constant_override("separation", 4)
	row.add_child(edit_box)

	var input = LineEdit.new()
	input.secret = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = DesignTokens.TOUCH_MIN
	input.text = SettingsManager.get_setting(setting_key, "")
	input.placeholder_text = "sk-..."
	input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	input.text_changed.connect(func(new_text): SettingsManager.set_setting(setting_key, new_text.strip_edges()))
	edit_box.add_child(input)

	var show_btn = Button.new()
	show_btn.text = "👁️"
	show_btn.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_MIN) # M1 : bouton icône
	show_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	show_btn.pressed.connect(func(): input.secret = not input.secret)
	edit_box.add_child(show_btn)

	parent.add_child(row)
