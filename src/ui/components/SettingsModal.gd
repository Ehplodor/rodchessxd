class_name SettingsModal
extends Window
## SettingsModal.gd - Fenêtre modale des paramètres de l'application et des clés IA

func _ready() -> void:
	title = "Paramètres & Clés IA"
	size = Vector2i(410, 620)
	exclusive = true
	close_requested.connect(queue_free)
	_setup_ui()

func _setup_ui() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 10
	scroll.offset_top = 10
	scroll.offset_right = -10
	scroll.offset_bottom = -10
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

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
	threads_lbl.add_theme_font_size_override("font_size", 11)
	threads_row.add_child(threads_lbl)

	var threads_spin = SpinBox.new()
	threads_spin.min_value = 1
	threads_spin.max_value = 8
	threads_spin.value = SettingsManager.get_setting("engine_threads", 2)
	threads_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_threads", int(val)))
	threads_row.add_child(threads_spin)
	vbox.add_child(threads_row)

	# Profondeur
	var depth_row = HBoxContainer.new()
	depth_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var depth_lbl = Label.new()
	depth_lbl.text = "Profondeur cible (Depth) :"
	depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	depth_lbl.add_theme_font_size_override("font_size", 11)
	depth_row.add_child(depth_lbl)

	var depth_spin = SpinBox.new()
	depth_spin.min_value = 10
	depth_spin.max_value = 30
	depth_spin.value = SettingsManager.get_setting("engine_depth", 18)
	depth_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_depth", int(val)))
	depth_row.add_child(depth_spin)
	vbox.add_child(depth_row)

	_add_section_header(vbox, "🤖 Intelligence Artificielle & Coach")

	var hub_btn = Button.new()
	hub_btn.text = "⚡ Gérer les Modèles IA & Coûts en direct..."
	hub_btn.custom_minimum_size = Vector2(0, 36)
	hub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_btn.add_theme_font_size_override("font_size", 11)
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
	prov_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(prov_lbl)

	var prov_opt = OptionButton.new()
	prov_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	pers_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(pers_lbl)

	var pers_opt = OptionButton.new()
	pers_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	theme_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(theme_lbl)

	var theme_opt = OptionButton.new()
	theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	sound_check.toggled.connect(func(val): SettingsManager.set_setting("sound_enabled", val))
	vbox.add_child(sound_check)

	# Bouton Fermer
	var btn_close = Button.new()
	btn_close.text = "Fermer & Enregistrer"
	btn_close.custom_minimum_size = Vector2(0, 40)
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _add_section_header(parent: Node, title_text: String) -> void:
	var lbl = Label.new()
	lbl.text = title_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	parent.add_child(lbl)

func _add_api_key_field(parent: Node, label_text: String, setting_key: String) -> void:
	var row = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	row.add_child(lbl)

	var edit_box = HBoxContainer.new()
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.add_theme_constant_override("separation", 4)
	row.add_child(edit_box)

	var input = LineEdit.new()
	input.secret = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text = SettingsManager.get_setting(setting_key, "")
	input.placeholder_text = "sk-..."
	input.add_theme_font_size_override("font_size", 10)
	input.text_changed.connect(func(new_text): SettingsManager.set_setting(setting_key, new_text.strip_edges()))
	edit_box.add_child(input)

	var show_btn = Button.new()
	show_btn.text = "👁️"
	show_btn.pressed.connect(func(): input.secret = not input.secret)
	edit_box.add_child(show_btn)

	parent.add_child(row)
