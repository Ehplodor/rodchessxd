class_name SettingsModal
extends Window
## SettingsModal.gd - Fenêtre modale des paramètres de l'application et des clés IA

var _init_threads: int = 2
var _init_hash: int = 32
var _init_live_depth: int = 16
var _init_analysis_depth: int = 18

func _ready() -> void:
	title = "Paramètres & Clés IA"
	var screen_w = 450.0
	var screen_h = 800.0
	var tree = Engine.get_main_loop() as SceneTree
	DesignTokens.adapt_modal_size(self, 400, 680)
	exclusive = true
	close_requested.connect(_on_save_and_close)
	_init_threads = SettingsManager.get_setting("engine_threads", SettingsManager.get_default_engine_threads())
	_init_hash = SettingsManager.get_setting("engine_hash_mb", SettingsManager.get_default_engine_hash())
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
	root_vbox.clip_contents = true
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	root_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.clip_contents = true
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# --- SECTION MOTEUR ---
	_add_section_header(vbox, "⚡ Moteur d'Échecs Stockfish")

	# Threads
	var threads_row = HBoxContainer.new()
	threads_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var threads_lbl = Label.new()
	threads_lbl.text = "Cœurs CPU (Threads) :"
	threads_lbl.custom_minimum_size = Vector2(50, 0)
	threads_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	threads_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threads_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	threads_row.add_child(threads_lbl)

	var threads_spin = SpinBox.new()
	threads_spin.min_value = 1
	threads_spin.max_value = maxi(8, OS.get_processor_count())
	threads_spin.value = SettingsManager.get_setting("engine_threads", SettingsManager.get_default_engine_threads())
	threads_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_threads", int(val)))
	threads_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	threads_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if threads_spin.get_line_edit():
		threads_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	threads_row.add_child(threads_spin)
	vbox.add_child(threads_row)

	# Profondeur Live (Échiquier)
	var def_live = 12 if (OS.has_feature("android") or OS.has_feature("ios")) else 16
	var live_depth_row = HBoxContainer.new()
	live_depth_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var live_depth_lbl = Label.new()
	live_depth_lbl.text = "Profondeur en direct (Live) :"
	live_depth_lbl.custom_minimum_size = Vector2(50, 0)
	live_depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	live_depth_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live_depth_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	live_depth_row.add_child(live_depth_lbl)

	var live_depth_spin = SpinBox.new()
	live_depth_spin.min_value = 8
	live_depth_spin.max_value = 24
	live_depth_spin.value = SettingsManager.get_setting("engine_depth", def_live)
	live_depth_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_depth", int(val)))
	live_depth_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	live_depth_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if live_depth_spin.get_line_edit():
		live_depth_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	live_depth_row.add_child(live_depth_spin)
	vbox.add_child(live_depth_row)

	# Mode d'Analyse de Partie
	var mode_card = PanelContainer.new()
	mode_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_card.clip_contents = true
	var mode_card_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM, DesignTokens.BORDER, 1, Vector2(10, 8))
	mode_card.add_theme_stylebox_override("panel", mode_card_style)
	
	var mode_card_vbox = VBoxContainer.new()
	mode_card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_card_vbox.clip_contents = true
	mode_card_vbox.add_theme_constant_override("separation", 8)
	mode_card.add_child(mode_card_vbox)

	var mode_lbl = Label.new()
	mode_lbl.text = "Mode d'analyse de partie :"
	mode_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	mode_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	mode_card_vbox.add_child(mode_lbl)

	var mode_opt = OptionButton.new()
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	mode_opt.fit_to_longest_item = false
	mode_opt.clip_text = true
	mode_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	mode_opt.add_item("⚡ Dynamique adaptatif", 0)
	mode_opt.add_item("⏱️ Temps fixe", 1)
	mode_opt.add_item("🎯 Profondeur fixe", 2)
	mode_opt.add_item("🚀 Budget (rapide)", 3)

	var cur_mode = SettingsManager.get_setting("analysis_mode", "budget")
	match cur_mode:
		"dynamic": mode_opt.selected = 0
		"time": mode_opt.selected = 1
		"depth": mode_opt.selected = 2
		"budget": mode_opt.selected = 3
		_: mode_opt.selected = 3
	mode_card_vbox.add_child(mode_opt)

	# --- 1. Paramètres Mode Dynamique ---
	var dyn_header = Label.new()
	dyn_header.text = "⚡ Paramètres Mode Dynamique :"
	dyn_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dyn_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	dyn_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	mode_card_vbox.add_child(dyn_header)

	var dyn_base_row = HBoxContainer.new()
	dyn_base_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dyn_base_lbl = Label.new()
	dyn_base_lbl.text = "• Temps base par coup (s) :"
	dyn_base_lbl.custom_minimum_size = Vector2(50, 0)
	dyn_base_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dyn_base_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dyn_base_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	dyn_base_row.add_child(dyn_base_lbl)

	var dyn_base_spin = SpinBox.new()
	dyn_base_spin.min_value = 0.05
	dyn_base_spin.max_value = 0.50
	dyn_base_spin.step = 0.05
	dyn_base_spin.value = SettingsManager.get_setting("analysis_dynamic_base", 0.15)
	dyn_base_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	dyn_base_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if dyn_base_spin.get_line_edit():
		dyn_base_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	dyn_base_spin.value_changed.connect(func(val): SettingsManager.set_setting("analysis_dynamic_base", float(val)))
	dyn_base_row.add_child(dyn_base_spin)
	mode_card_vbox.add_child(dyn_base_row)

	var dyn_max_row = HBoxContainer.new()
	dyn_max_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dyn_max_lbl = Label.new()
	dyn_max_lbl.text = "• Temps max critiques (s) :"
	dyn_max_lbl.custom_minimum_size = Vector2(50, 0)
	dyn_max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dyn_max_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dyn_max_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	dyn_max_row.add_child(dyn_max_lbl)

	var dyn_max_spin = SpinBox.new()
	dyn_max_spin.min_value = 0.20
	dyn_max_spin.max_value = 3.00
	dyn_max_spin.step = 0.10
	dyn_max_spin.value = SettingsManager.get_setting("analysis_dynamic_max", 0.80)
	dyn_max_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	dyn_max_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if dyn_max_spin.get_line_edit():
		dyn_max_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	dyn_max_spin.value_changed.connect(func(val): SettingsManager.set_setting("analysis_dynamic_max", float(val)))
	dyn_max_row.add_child(dyn_max_spin)
	mode_card_vbox.add_child(dyn_max_row)

	# --- 2. Paramètre Mode Temps fixe ---
	var time_header = Label.new()
	time_header.text = "⏱️ Paramètre Mode Temps fixe :"
	time_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	time_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	time_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	mode_card_vbox.add_child(time_header)

	var time_row = HBoxContainer.new()
	time_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var time_lbl = Label.new()
	time_lbl.text = "• Temps par coup (s) :"
	time_lbl.custom_minimum_size = Vector2(50, 0)
	time_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	time_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	time_row.add_child(time_lbl)

	var time_spin = SpinBox.new()
	time_spin.min_value = 0.10
	time_spin.max_value = 3.00
	time_spin.step = 0.05
	time_spin.value = SettingsManager.get_setting("analysis_time_per_move", 0.30)
	time_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	time_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if time_spin.get_line_edit():
		time_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_spin.value_changed.connect(func(val): SettingsManager.set_setting("analysis_time_per_move", float(val)))
	time_row.add_child(time_spin)
	mode_card_vbox.add_child(time_row)

	# --- 3. Paramètre Mode Profondeur fixe ---
	var depth_header = Label.new()
	depth_header.text = "🎯 Paramètre Mode Profondeur fixe :"
	depth_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	depth_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	depth_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	mode_card_vbox.add_child(depth_header)

	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var anal_depth_row = HBoxContainer.new()
	anal_depth_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var anal_depth_lbl = Label.new()
	anal_depth_lbl.text = "• Profondeur fixe (Bilan) :"
	anal_depth_lbl.custom_minimum_size = Vector2(50, 0)
	anal_depth_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anal_depth_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anal_depth_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	anal_depth_row.add_child(anal_depth_lbl)

	var anal_depth_spin = SpinBox.new()
	anal_depth_spin.min_value = 10
	anal_depth_spin.max_value = 26
	anal_depth_spin.value = SettingsManager.get_setting("analysis_depth", def_anal)
	anal_depth_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	anal_depth_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if anal_depth_spin.get_line_edit():
		anal_depth_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	anal_depth_spin.value_changed.connect(func(val): SettingsManager.set_setting("analysis_depth", int(val)))
	anal_depth_row.add_child(anal_depth_spin)
	mode_card_vbox.add_child(anal_depth_row)

	# --- 4. Paramètres Mode Budget (passe A large + passe B profonde sur les coups critiques) ---
	var budget_header = Label.new()
	budget_header.text = "🚀 Paramètres Mode Budget (rapide) :"
	budget_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	budget_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	budget_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	mode_card_vbox.add_child(budget_header)

	var budget_base_spin = _make_setting_spin("• Profondeur passe A (tous) :", "analysis_budget_base_depth", 8, 4, 16, 1, true)
	mode_card_vbox.add_child(budget_base_spin)
	var budget_deep_spin = _make_setting_spin("• Profondeur passe B (critiques) :", "analysis_budget_deep_depth", 14, 8, 24, 1, true)
	mode_card_vbox.add_child(budget_deep_spin)
	var budget_max_spin = _make_setting_spin("• Coups approfondis (max) :", "analysis_budget_max_deep", 6, 0, 20, 1, true)
	mode_card_vbox.add_child(budget_max_spin)

	mode_opt.item_selected.connect(func(idx):
		match idx:
			0: SettingsManager.set_setting("analysis_mode", "dynamic")
			1: SettingsManager.set_setting("analysis_mode", "time")
			2: SettingsManager.set_setting("analysis_mode", "depth")
			3: SettingsManager.set_setting("analysis_mode", "budget")
	)

	vbox.add_child(mode_card)

	# Mémoire (Hash) — Stockfish
	var hash_row = HBoxContainer.new()
	hash_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hash_lbl = Label.new()
	hash_lbl.text = "Mémoire cache (Hash Mo) :"
	hash_lbl.custom_minimum_size = Vector2(50, 0)
	hash_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hash_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hash_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	hash_row.add_child(hash_lbl)

	var hash_spin = SpinBox.new()
	hash_spin.min_value = 16
	hash_spin.max_value = 4096
	hash_spin.step = 16
	hash_spin.value = SettingsManager.get_setting("engine_hash_mb", SettingsManager.get_default_engine_hash())
	hash_spin.value_changed.connect(func(val): SettingsManager.set_setting("engine_hash_mb", int(val)))
	hash_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	hash_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if hash_spin.get_line_edit():
		hash_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	hash_row.add_child(hash_spin)
	vbox.add_child(hash_row)

	# T1.1 — Nombre de lignes moteur (MultiPV)
	var mpv_row = HBoxContainer.new()
	mpv_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mpv_lbl = Label.new()
	mpv_lbl.text = "Lignes d'analyse (MultiPV) :"
	mpv_lbl.custom_minimum_size = Vector2(50, 0)
	mpv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mpv_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mpv_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	mpv_row.add_child(mpv_lbl)

	var mpv_spin = SpinBox.new()
	mpv_spin.min_value = 1
	mpv_spin.max_value = 5
	mpv_spin.step = 1
	mpv_spin.value = SettingsManager.get_setting("engine_multipv", 1)
	mpv_spin.value_changed.connect(func(val):
		SettingsManager.set_setting("engine_multipv", int(val))
		if EngineManager != null and EngineManager.has_method("set_multipv"):
			EngineManager.set_multipv(int(val))
	)
	mpv_spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	mpv_spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if mpv_spin.get_line_edit():
		mpv_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	mpv_row.add_child(mpv_spin)
	vbox.add_child(mpv_row)

	# Vitesse d'analyse du Carnet (traitement par lot et synchronisations)
	var carnet_speed_row = HBoxContainer.new()
	carnet_speed_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var carnet_speed_lbl = Label.new()
	carnet_speed_lbl.text = "Vitesse moteur Carnet :"
	carnet_speed_lbl.tooltip_text = "Vitesse du moteur pour le traitement par lot et les recalculs de LeCarnet"
	carnet_speed_lbl.custom_minimum_size = Vector2(50, 0)
	carnet_speed_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carnet_speed_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	carnet_speed_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	carnet_speed_row.add_child(carnet_speed_lbl)

	var carnet_speed_opt = OptionButton.new()
	carnet_speed_opt.custom_minimum_size = Vector2(160, DesignTokens.TOUCH_MIN)
	carnet_speed_opt.fit_to_longest_item = false
	carnet_speed_opt.clip_text = true
	carnet_speed_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	carnet_speed_opt.add_item("⚡ Rapide (~2s)", 0)
	carnet_speed_opt.add_item("⚖️ Standard (~6s)", 1)
	carnet_speed_opt.add_item("🎯 Approfondie (~20s)", 2)
	var cur_speed = SettingsManager.get_setting("carnet_analysis_speed", "fast")
	match cur_speed:
		"fast": carnet_speed_opt.selected = 0
		"balanced": carnet_speed_opt.selected = 1
		"deep": carnet_speed_opt.selected = 2
		_: carnet_speed_opt.selected = 0
	carnet_speed_opt.item_selected.connect(func(idx):
		match idx:
			0: SettingsManager.set_setting("carnet_analysis_speed", "fast")
			1: SettingsManager.set_setting("carnet_analysis_speed", "balanced")
			2: SettingsManager.set_setting("carnet_analysis_speed", "deep")
	)
	carnet_speed_row.add_child(carnet_speed_opt)
	vbox.add_child(carnet_speed_row)

	var param_note = Label.new()
	param_note.text = "Comment ajuster vitesse vs profondeur ?\n• Vitesse moteur Carnet : ajuste la profondeur et le temps de calcul pour les imports et mises à jour de lot (Rapide = ~2s/partie, Standard = ~6s/partie, Approfondie = ~20s/partie).\n• Mode Dynamique : vitesse maximale sur les coups évidents (0.15s) et approfondissement automatique sur les coups critiques.\n• Mode Temps fixe : durée garantie par demi-coup (0.1s à 3.0s).\n• Mode Profondeur : analyse à profondeur UCI fixe.\n• Intervalles de confiance (IC 95%) : calculés statistiquement sur les évaluations et les ELO avec test de Welch (*, **, ***).\n• Threads & Hash : nombre de cœurs CPU et mémoire cache (redémarre le moteur si modifié)."
	param_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	param_note.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	param_note.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(param_note)

	_add_section_header(vbox, "🤖 Intelligence Artificielle & Coach (OpenRouter)")

	var hub_btn = Button.new()
	hub_btn.text = "🌟 Explorer le Hub des Modèles IA..."
	hub_btn.clip_text = true
	hub_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	hub_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hub_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	var hub_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL, DesignTokens.ACCENT, 1)
	hub_btn.add_theme_stylebox_override("normal", hub_style)
	hub_btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
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
	prov_lbl.text = "Fournisseur de Modèles :"
	prov_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prov_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(prov_lbl)

	var prov_opt = OptionButton.new()
	prov_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prov_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	prov_opt.fit_to_longest_item = false
	prov_opt.clip_text = true
	prov_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	prov_opt.add_item("OpenRouter (Cloud / BYOK universel)", 0)
	prov_opt.add_item("SLM Local (Ollama / Hors-ligne)", 1)
	
	var cur_prov = SettingsManager.get_setting("ai_provider", "openrouter")
	if cur_prov == "local_slm":
		prov_opt.selected = 1
	else:
		prov_opt.selected = 0
	
	prov_opt.item_selected.connect(func(idx):
		if idx == 1:
			SettingsManager.set_setting("ai_provider", "local_slm")
		else:
			SettingsManager.set_setting("ai_provider", "openrouter")
	)
	vbox.add_child(prov_opt)

	# Personnalité
	var pers_lbl = Label.new()
	pers_lbl.text = "Personnalité du Coach :"
	pers_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pers_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(pers_lbl)

	var pers_opt = OptionButton.new()
	pers_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pers_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	pers_opt.fit_to_longest_item = false
	pers_opt.clip_text = true
	pers_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	pers_opt.add_item("Grand-Maître Mentor", 0)
	pers_opt.add_item("Chasseur de Gaffes", 1)
	pers_opt.add_item("Pédagogue Débutant", 2)
	
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

	# Moteur de Synthèse Vocale (TTS)
	var tts_lbl = Label.new()
	tts_lbl.text = "Moteur Vocal (TTS) :"
	tts_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tts_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(tts_lbl)

	var tts_opt = OptionButton.new()
	tts_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tts_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	tts_opt.fit_to_longest_item = false
	tts_opt.clip_text = true
	tts_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	tts_opt.add_item("🔊 Local Système (100% Hors-ligne, 0 ms ⚡)", 0)
	tts_opt.add_item("⚡ Deepgram Flux TTS (Cloud OpenRouter 🆓)", 1)

	var cur_tts = SettingsManager.get_setting("coach_tts_model", "local_system")
	tts_opt.selected = 1 if cur_tts.contains("flux-tts") else 0

	tts_opt.item_selected.connect(func(idx):
		if idx == 1:
			SettingsManager.set_setting("coach_tts_model", "deepgram/flux-tts:free")
		else:
			SettingsManager.set_setting("coach_tts_model", "local_system")
	)
	vbox.add_child(tts_opt)

	# Voix du Coach IA (Synthèse vocale T2S OpenRouter)
	var voice_lbl = Label.new()
	voice_lbl.text = "Voix du Coach IA (Synthèse vocale) :"
	voice_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	voice_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(voice_lbl)

	var voice_opt = OptionButton.new()
	voice_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	voice_opt.fit_to_longest_item = false
	voice_opt.clip_text = true
	voice_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	voice_opt.add_item("👩 Féminine (Elise)", 0)
	voice_opt.add_item("👨 Masculine (Marcelo)", 1)

	var cur_voice = SettingsManager.get_setting("coach_voice_gender", "female")
	voice_opt.selected = 1 if cur_voice == "male" else 0

	voice_opt.item_selected.connect(func(idx):
		var chosen_voice = "male" if idx == 1 else "female"
		SettingsManager.set_setting("coach_voice_gender", chosen_voice)
	)
	vbox.add_child(voice_opt)

	# Clé API OpenRouter avec test live et lien direct
	_add_openrouter_key_section(vbox)

	# --- SECTION APPARENCE & AUDIO ---
	_add_section_header(vbox, "🎨 Thème & Sons")

	# Mode d'interface Clair / Obscur
	var app_theme_lbl = Label.new()
	app_theme_lbl.text = "Thème de l'application :"
	app_theme_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app_theme_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(app_theme_lbl)

	var app_theme_opt = OptionButton.new()
	app_theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_theme_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	app_theme_opt.fit_to_longest_item = false
	app_theme_opt.clip_text = true
	app_theme_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	app_theme_opt.add_item("🌙 Sombre (Dark)", 0)
	app_theme_opt.add_item("☀️ Clair (Light)", 1)

	var cur_app_theme = SettingsManager.get_setting("app_theme_mode", "dark")
	app_theme_opt.selected = 1 if cur_app_theme == "light" else 0

	app_theme_opt.item_selected.connect(func(idx):
		var chosen_mode = "light" if idx == 1 else "dark"
		SettingsManager.set_setting("app_theme_mode", chosen_mode)
		DesignTokens.apply_theme_mode(chosen_mode)
	)
	vbox.add_child(app_theme_opt)

	var theme_lbl = Label.new()
	theme_lbl.text = "Thème de l'échiquier :"
	theme_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	theme_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(theme_lbl)

	var theme_opt = OptionButton.new()
	theme_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_opt.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	theme_opt.fit_to_longest_item = false
	theme_opt.clip_text = true
	theme_opt.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	theme_opt.add_item("Ardoise Studio (Dark)", 0)
	theme_opt.add_item("Émeraude Tournoi", 1)
	theme_opt.add_item("Bois Précieux", 2)

	var cur_theme = SettingsManager.get_setting("board_theme", "emerald")
	match cur_theme:
		"dark_modern", "slate_modern": theme_opt.selected = 0
		"emerald": theme_opt.selected = 1
		"wood", "wood_luxury": theme_opt.selected = 2

	theme_opt.item_selected.connect(func(idx):
		var theme_key = "slate_modern" if idx == 0 else ("emerald" if idx == 1 else "wood_luxury")
		SettingsManager.set_setting("board_theme", theme_key)
	)
	vbox.add_child(theme_opt)

	# Son
	var sound_check = CheckButton.new()
	sound_check.text = "Effets sonores activés"
	sound_check.clip_text = true
	sound_check.button_pressed = SettingsManager.get_setting("sound_enabled", true)
	sound_check.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	sound_check.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	sound_check.toggled.connect(func(val): SettingsManager.set_setting("sound_enabled", val))
	vbox.add_child(sound_check)

	# Aides visuelles aux coups
	var hints_check = CheckButton.new()
	hints_check.text = "Aides de coups (points et flèches)"
	hints_check.clip_text = true
	hints_check.button_pressed = SettingsManager.get_setting("show_move_hints", true)
	hints_check.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	hints_check.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	hints_check.toggled.connect(func(val): SettingsManager.set_setting("show_move_hints", val))
	vbox.add_child(hints_check)

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
	export_btn.clip_text = true
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
	btn_close.clip_text = true
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
	var new_threads = SettingsManager.get_setting("engine_threads", SettingsManager.get_default_engine_threads())
	var new_hash = SettingsManager.get_setting("engine_hash_mb", SettingsManager.get_default_engine_hash())
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

## Sauvegarde d'une clé API sans écraser une valeur existante par un champ vide
## (important sur mobile : une perte de focus ne doit jamais effacer la clé).
func _persist_api_key(key: String, raw: String) -> void:
	var v := raw.strip_edges()
	if v == "" and str(SettingsManager.get_setting(key, "")) != "":
		return
	SettingsManager.set_setting(key, v)

func _add_openrouter_key_section(parent: Node) -> void:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	card.add_theme_stylebox_override("panel", c_style)

	var v_box = VBoxContainer.new()
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_box.add_theme_constant_override("separation", 6)
	card.add_child(v_box)

	var lbl = Label.new()
	lbl.text = "Clé API OpenRouter (BYOK universel) :"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	v_box.add_child(lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = "Une seule clé donne accès à tous les modèles IA (DeepSeek R1, Claude 3.7, GPT-4o, modèles gratuits et économiques)."
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	desc_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	v_box.add_child(desc_lbl)

	var edit_box = HBoxContainer.new()
	edit_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_box.add_theme_constant_override("separation", 4)
	v_box.add_child(edit_box)

	var input = LineEdit.new()
	input.secret = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(50, DesignTokens.TOUCH_MIN)
	input.text = SettingsManager.get_setting("api_key_openrouter", "")
	input.placeholder_text = "sk-or-v1-..."
	input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	input.text_changed.connect(func(t): _persist_api_key("api_key_openrouter", t))
	input.text_submitted.connect(func(_t): _persist_api_key("api_key_openrouter", input.text))
	input.focus_exited.connect(func(): _persist_api_key("api_key_openrouter", input.text))
	edit_box.add_child(input)

	var show_btn = Button.new()
	show_btn.text = "👁️"
	show_btn.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_MIN)
	show_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	show_btn.pressed.connect(func(): input.secret = not input.secret)
	edit_box.add_child(show_btn)

	var test_feedback_lbl = Label.new()
	test_feedback_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	test_feedback_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	test_feedback_lbl.visible = false
	v_box.add_child(test_feedback_lbl)

	var actions_row = HBoxContainer.new()
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_theme_constant_override("separation", 6)
	v_box.add_child(actions_row)

	var btn_test = Button.new()
	btn_test.text = "🔍 Tester la clé"
	btn_test.clip_text = true
	btn_test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_test.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_test.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn_test.pressed.connect(func():
		var k = input.text.strip_edges()
		if k == "":
			test_feedback_lbl.text = "⚠️ Saisissez une clé avant de tester."
			test_feedback_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
			test_feedback_lbl.visible = true
			return
		test_feedback_lbl.text = "⏳ Vérification de la clé auprès d'OpenRouter..."
		test_feedback_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		test_feedback_lbl.visible = true

		var tree = Engine.get_main_loop() as SceneTree
		var mc = tree.root.get_node_or_null("ModelCatalog") if tree and tree.root else null
		if mc and mc.has_method("test_openrouter_key"):
			var cb: Callable
			cb = func(is_valid: bool, data: Dictionary, err: String):
				if not is_instance_valid(test_feedback_lbl):
					return
				if is_valid:
					var usage = data.get("usage", 0.0)
					var limit = data.get("limit", 0.0)
					var is_free = data.get("is_free_tier", false)
					if limit > 0.0:
						var rem = maxf(0.0, limit - usage)
						test_feedback_lbl.text = "✅ Clé active ! Solde : $%.2f (Utilisé : $%.2f)" % [rem, usage]
					elif is_free:
						test_feedback_lbl.text = "✅ Clé valide (Tier gratuit OpenRouter)"
					else:
						test_feedback_lbl.text = "✅ Clé active et reconnue"
					test_feedback_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
				else:
					test_feedback_lbl.text = "❌ Clé invalide : %s" % (err if err != "" else "Erreur d'authentification")
					test_feedback_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
			mc.key_test_completed.connect(cb, CONNECT_ONE_SHOT)
			mc.test_openrouter_key(k)
		else:
			test_feedback_lbl.text = "⚠️ Catalogue indisponible pour le test immédiat."
			test_feedback_lbl.visible = true
	)
	actions_row.add_child(btn_test)

	var btn_get = Button.new()
	btn_get.text = "🔗 Obtenir une clé"
	btn_get.clip_text = true
	btn_get.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_get.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_get.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn_get.pressed.connect(func(): OS.shell_open("https://openrouter.ai/keys"))
	actions_row.add_child(btn_get)

	parent.add_child(card)

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
	input.custom_minimum_size = Vector2(50, DesignTokens.TOUCH_MIN)
	input.text = SettingsManager.get_setting(setting_key, "")
	input.placeholder_text = "sk-..."
	input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	# Sauvegarde robuste (web/mobile) : sur chaque frappe, à la validation et à la perte de focus.
	input.text_changed.connect(func(new_text): _persist_api_key(setting_key, new_text))
	input.text_submitted.connect(func(_entered): _persist_api_key(setting_key, input.text))
	input.focus_exited.connect(func(): _persist_api_key(setting_key, input.text))
	edit_box.add_child(input)

	var show_btn = Button.new()
	show_btn.text = "👁️"
	show_btn.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_MIN) # M1 : bouton icône
	show_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	show_btn.pressed.connect(func(): input.secret = not input.secret)
	edit_box.add_child(show_btn)

	parent.add_child(row)

## Ligne de réglage générique : libellé + SpinBox lié à une clé de SettingsManager.
func _make_setting_spin(label_text: String, setting_key: String, default_val: int,
		min_val: int, max_val: int, step: int, as_int: bool) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(50, 0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	row.add_child(lbl)
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = SettingsManager.get_setting(setting_key, default_val)
	spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_MIN)
	spin.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	if spin.get_line_edit():
		spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.value_changed.connect(func(val): SettingsManager.set_setting(setting_key, int(val) if as_int else float(val)))
	row.add_child(spin)
	return row
