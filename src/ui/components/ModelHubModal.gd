class_name ModelHubModal
extends Window
## ModelHubModal.gd - Interface ergonomique de gestion et configuration des modèles IA (OpenRouter BYOK + Local)
## Recherche en temps réel, filtres par critères, test de clé API en 1 clic et conformité mobile.

signal model_selected(model_id: String)

const ModelCatalogScript = preload("res://src/ai/ModelCatalog.gd")

var current_active_id: String = ""
var active_filters: Array[String] = []
var search_query: String = ""

# Éléments d'interface
var active_badge_lbl: Label
var update_btn: Button
var update_status_lbl: Label
var session_stats_lbl: Label

# Clé OpenRouter
var key_input: LineEdit
var key_status_lbl: Label
var btn_test_key: Button
var key_edit_row: HBoxContainer
var btn_toggle_key: Button

# Recherche et filtres
var search_input: LineEdit
var filter_buttons: Dictionary = {}
var models_container: VBoxContainer
var main_scroll: ScrollContainer

# Composants SLM Local
var ollama_status_lbl: Label
var download_progress_bars: Dictionary = {}
var download_status_labels: Dictionary = {}

func _get_settings() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _get_catalog() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("ModelCatalog"):
		return tree.root.get_node("ModelCatalog")
	return null

func _get_coach() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("AICoach"):
		return tree.root.get_node("AICoach")
	return null

func _get_downloader() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("ModelDownloader"):
		return tree.root.get_node("ModelDownloader")
	return null

func _get_slm_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("LocalSLMManager"):
		return tree.root.get_node("LocalSLMManager")
	return null

func _ready() -> void:
	title = "⚡ Hub des Modèles IA (OpenRouter)"
	DesignTokens.adapt_modal_size(self, 410, 650)
	exclusive = true
	close_requested.connect(queue_free)

	var sm = _get_settings()
	current_active_id = sm.get_setting("active_model_id", "openrouter/free") if sm else "openrouter/free"

	var cat = _get_catalog()
	if cat:
		cat.catalog_updated.connect(_on_catalog_updated)
		cat.catalog_update_failed.connect(_on_catalog_update_failed)
		cat.local_ollama_detected.connect(_on_ollama_detected)
		cat.key_test_completed.connect(_on_key_test_completed)

	var dl = _get_downloader()
	if dl:
		dl.download_progress.connect(_on_slm_download_progress)
		dl.download_completed.connect(_on_slm_download_completed)
		dl.download_failed.connect(_on_slm_download_failed)
		dl.model_deleted.connect(_on_slm_model_deleted)

	_setup_ui()
	_refresh_active_badge()
	_refresh_models_list()

func _setup_ui() -> void:
	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 10
	root_vbox.offset_top = 10
	root_vbox.offset_right = -10
	root_vbox.offset_bottom = -10
	root_vbox.clip_contents = true
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	# --- CONTENEUR DE DÉFILEMENT PLEINE HAUTEUR ---
	# Permet à l'intégralité du contenu (en-tête, clé, recherche, filtres et liste des modèles)
	# de défiler sur toute la hauteur de l'écran sans étranglement.
	main_scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(main_scroll)
	main_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_scroll.clip_contents = true
	root_vbox.add_child(main_scroll)

	var scroll_content = VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.clip_contents = true
	scroll_content.add_theme_constant_override("separation", 8)
	main_scroll.add_child(scroll_content)

	# --- 1. EN-TÊTE : Modèle Actif & Actualiser ---
	var header_box = VBoxContainer.new()
	header_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_theme_constant_override("separation", 2)
	scroll_content.add_child(header_box)

	var top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(top_row)

	var title_lbl = Label.new()
	title_lbl.text = "🤖 Modèle Actif :"
	title_lbl.custom_minimum_size = Vector2(50, 0)
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	top_row.add_child(title_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	update_btn = Button.new()
	update_btn.text = "🔄 Actualiser"
	update_btn.tooltip_text = "Synchroniser avec l'API OpenRouter"
	# Sans clip_text : le bouton conserve sa largeur naturelle (sinon ~8 px).
	update_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	DesignTokens.style_button(update_btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	update_btn.pressed.connect(_on_refresh_catalog_pressed)
	top_row.add_child(update_btn)

	active_badge_lbl = Label.new()
	active_badge_lbl.text = "Chargement..."
	active_badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_badge_lbl.custom_minimum_size = Vector2(50, 0)
	active_badge_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	active_badge_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	header_box.add_child(active_badge_lbl)

	update_status_lbl = Label.new()
	var sm = _get_settings()
	var last_sync = sm.get_setting("last_catalog_sync", "Jamais") if sm else "Jamais"
	update_status_lbl.text = "Dernière synchro : %s" % (last_sync if last_sync != "" else "Catalogue initial")
	update_status_lbl.clip_text = true
	update_status_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	update_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	update_status_lbl.custom_minimum_size = Vector2(50, 0)
	update_status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	update_status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	header_box.add_child(update_status_lbl)

	# --- 2. BANDEAU CLÉ OPENROUTER (BYOK COMPACT / DÉPLIABLE) ---
	var cur_key = sm.get_setting("api_key_openrouter", "") if sm else ""
	var has_key = cur_key.strip_edges() != ""

	var key_card = PanelContainer.new()
	key_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var key_style := DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 6))
	key_card.add_theme_stylebox_override("panel", key_style)
	scroll_content.add_child(key_card)

	var key_vbox = VBoxContainer.new()
	key_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_vbox.clip_contents = true
	key_vbox.add_theme_constant_override("separation", 4)
	key_card.add_child(key_vbox)

	var key_head_row = HBoxContainer.new()
	key_head_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_vbox.add_child(key_head_row)

	var key_lbl = Label.new()
	key_lbl.text = "🔑 Clé OpenRouter :"
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_lbl.custom_minimum_size = Vector2(50, 0)
	key_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	key_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	key_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	key_head_row.add_child(key_lbl)

	btn_toggle_key = Button.new()
	btn_toggle_key.text = "⚙️ Modifier" if has_key else "▲ Masquer"
	btn_toggle_key.tooltip_text = "Afficher/Masquer le champ de clé OpenRouter"
	btn_toggle_key.clip_text = true
	btn_toggle_key.custom_minimum_size = Vector2(75, 28)
	DesignTokens.style_button(btn_toggle_key, DesignTokens.FONT_CAPTION - 1, 28)
	btn_toggle_key.pressed.connect(func():
		key_edit_row.visible = not key_edit_row.visible
		btn_toggle_key.text = "▲ Replier" if key_edit_row.visible else "⚙️ Modifier"
		_update_key_status_preview()
	)
	key_head_row.add_child(btn_toggle_key)

	var btn_get_key = Button.new()
	btn_get_key.text = "🔗 Clé 0 €"
	btn_get_key.tooltip_text = "Ouvrir openrouter.ai/keys pour générer une clé gratuite sans CB"
	btn_get_key.clip_text = true
	btn_get_key.custom_minimum_size = Vector2(65, 28)
	DesignTokens.style_button(btn_get_key, DesignTokens.FONT_CAPTION - 1, 28)
	btn_get_key.pressed.connect(func():
		OS.shell_open("https://openrouter.ai/keys")
	)
	key_head_row.add_child(btn_get_key)

	key_edit_row = HBoxContainer.new()
	key_edit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit_row.add_theme_constant_override("separation", 4)
	key_edit_row.visible = not has_key
	key_vbox.add_child(key_edit_row)

	key_input = LineEdit.new()
	key_input.secret = true
	key_input.placeholder_text = "sk-or-v1-..."
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.custom_minimum_size = Vector2(50, DesignTokens.TOUCH_DENSE)
	key_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	key_input.text = cur_key
	key_input.text_changed.connect(func(val):
		var s = _get_settings()
		if s:
			s.set_setting("api_key_openrouter", val.strip_edges())
		_update_key_status_preview()
	)
	key_edit_row.add_child(key_input)

	var show_key_btn = Button.new()
	show_key_btn.text = "👁️"
	show_key_btn.tooltip_text = "Afficher/Masquer la clé"
	show_key_btn.custom_minimum_size = Vector2(36, DesignTokens.TOUCH_DENSE)
	show_key_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	show_key_btn.pressed.connect(func(): key_input.secret = not key_input.secret)
	key_edit_row.add_child(show_key_btn)

	btn_test_key = Button.new()
	btn_test_key.text = "🔍 Tester"
	btn_test_key.tooltip_text = "Valider la clé auprès d'OpenRouter (/api/v1/auth/key)"
	btn_test_key.clip_text = true
	btn_test_key.custom_minimum_size = Vector2(60, DesignTokens.TOUCH_DENSE)
	DesignTokens.style_button(btn_test_key, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	btn_test_key.pressed.connect(_on_test_key_pressed)
	key_edit_row.add_child(btn_test_key)

	key_status_lbl = Label.new()
	key_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_status_lbl.custom_minimum_size = Vector2(50, 0)
	key_status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	key_vbox.add_child(key_status_lbl)
	_update_key_status_preview()

	# --- 3. BARRE DE RECHERCHE TEMPS RÉEL ---
	search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Rechercher un modèle (DeepSeek, Claude, R1, Flash...)"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(50, DesignTokens.TOUCH_DENSE)
	search_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	search_input.text_changed.connect(func(val):
		search_query = val
		_refresh_models_list()
	)
	scroll_content.add_child(search_input)

	# --- 4. FILTRES PAR CATÉGORIE (GridContainer 3 colonnes) ---
	var filter_grid = GridContainer.new()
	filter_grid.columns = 3
	filter_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_grid.add_theme_constant_override("h_separation", 4)
	filter_grid.add_theme_constant_override("v_separation", 4)
	scroll_content.add_child(filter_grid)

	var categories = [
		["all", "Tous"],
		["free", "🆓 Gratuits"],
		["reasoning", "🧠 Raison."],
		["fast_eco", "⚡ Éco"],
		["frontier", "👑 Frontier"],
		["local", "💻 Local"]
	]

	for cat_info in categories:
		var cat_key = cat_info[0]
		var cat_title = cat_info[1]
		var b = Button.new()
		b.text = cat_title
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		DesignTokens.style_button(b, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		b.pressed.connect(func():
			_toggle_filter(cat_key)
		)
		filter_buttons[cat_key] = b
		filter_grid.add_child(b)
	_update_filter_buttons_style()

	# --- 5. CONTENEUR DES CARTES DE MODÈLES ---
	models_container = VBoxContainer.new()
	models_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	models_container.add_theme_constant_override("separation", 6)
	scroll_content.add_child(models_container)

	# --- 6. PIED DE PAGE FIXE : Statistiques de Session & Fermer ---
	var footer_box = HBoxContainer.new()
	footer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_box.add_theme_constant_override("separation", 8)
	root_vbox.add_child(footer_box)

	session_stats_lbl = Label.new()
	var coach = _get_coach()
	var q_cnt = coach.session_queries_count if coach else 0
	var q_cst = coach.session_estimated_cost_usd if coach else 0.0
	session_stats_lbl.text = "Session : %d req | ~%.4f $" % [q_cnt, q_cst]
	session_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_stats_lbl.custom_minimum_size = Vector2(50, 0)
	session_stats_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	session_stats_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	session_stats_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	footer_box.add_child(session_stats_lbl)

	var close_btn = Button.new()
	close_btn.text = "Fermer"
	close_btn.clip_text = true
	close_btn.custom_minimum_size = Vector2(70, DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(close_btn)
	close_btn.pressed.connect(queue_free)
	footer_box.add_child(close_btn)

func _toggle_filter(cat_key: String) -> void:
	if cat_key == "all":
		active_filters.clear()
	else:
		if active_filters.has(cat_key):
			active_filters.erase(cat_key)
		else:
			active_filters.append(cat_key)
	_update_filter_buttons_style()
	_refresh_models_list()

func _update_filter_buttons_style() -> void:
	var is_all_active = active_filters.is_empty()
	for cat_key in filter_buttons:
		var btn: Button = filter_buttons[cat_key]
		var is_sel = is_all_active if cat_key == "all" else active_filters.has(cat_key)
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		if is_sel:
			style.bg_color = DesignTokens.SURFACE_ELEVATED
			style.border_width_bottom = 2
			style.border_color = DesignTokens.ACCENT
			btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
		else:
			style.bg_color = DesignTokens.SURFACE
			btn.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)

func _update_key_status_preview() -> void:
	var sm = _get_settings()
	var k = sm.get_setting("api_key_openrouter", "") if sm else ""
	if k.strip_edges() == "":
		key_status_lbl.text = "⚪ Non configurée : les modèles gratuits (:free) restent accessibles."
		key_status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		if btn_toggle_key:
			btn_toggle_key.text = "▲ Replier" if (key_edit_row and key_edit_row.visible) else "⚙️ Saisir"
	else:
		if key_edit_row and not key_edit_row.visible:
			key_status_lbl.text = "🔑 Clé enregistrée (active). Touchez '⚙️ Modifier' pour afficher ou tester."
		else:
			key_status_lbl.text = "🔑 Clé enregistrée. Touchez '🔍 Tester' pour vérifier son solde et sa validité."
		key_status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		if btn_toggle_key:
			btn_toggle_key.text = "▲ Replier" if (key_edit_row and key_edit_row.visible) else "⚙️ Modifier"

func _on_test_key_pressed() -> void:
	var sm = _get_settings()
	var k = sm.get_setting("api_key_openrouter", "") if sm else ""
	if k.strip_edges() == "":
		key_status_lbl.text = "⚠️ Veuillez saisir une clé OpenRouter avant de tester."
		key_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		return

	btn_test_key.disabled = true
	key_status_lbl.text = "⏳ Vérification de la clé auprès d'OpenRouter..."
	key_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)

	var cat = _get_catalog()
	if cat:
		cat.test_openrouter_key(k)

func _on_key_test_completed(success: bool, _info: Dictionary, message: String) -> void:
	btn_test_key.disabled = false
	if success:
		key_status_lbl.text = "✅ " + message
		key_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	else:
		key_status_lbl.text = "❌ " + message
		key_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)

func _refresh_active_badge() -> void:
	var cat = _get_catalog()
	if not cat:
		active_badge_lbl.text = current_active_id
		return

	var model_info = cat.find_model_by_id(current_active_id)
	var model_name = model_info.get("name", current_active_id)
	var cost_info = cat.get_cost_estimate(model_info)
	var cost_str = cost_info.get("label_per_query", "")

	active_badge_lbl.text = "%s  •  %s" % [model_name, cost_str]

func _refresh_models_list() -> void:
	if models_container == null:
		return

	for child in models_container.get_children():
		child.queue_free()

	download_progress_bars.clear()
	download_status_labels.clear()

	var cat = _get_catalog()
	if not cat:
		return

	# Si le seul filtre actif est "local" et aucune recherche active, afficher les sections dédiées
	if active_filters.size() == 1 and active_filters.has("local") and search_query.strip_edges() == "":
		_populate_local_special_view()
		return

	# Si le catalogue ne contient que le routeur initial par défaut, afficher une invitation conviviale
	if cat.models.size() <= 1 and search_query.strip_edges() == "" and active_filters.is_empty():
		_add_first_launch_notice(models_container)

	var results: Array[Dictionary] = cat.search_models(search_query, active_filters)
	if results.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucun modèle ne correspond à votre recherche."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		models_container.add_child(empty_lbl)
		return

	for m in results:
		if m.get("provider") == "native_slm":
			_add_native_slm_card(models_container, m)
		else:
			_add_openrouter_model_card(models_container, m)

func _add_first_launch_notice(parent: Control) -> void:
	var notice_card = PanelContainer.new()
	notice_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.ACCENT, 1, Vector2(10, 8))
	notice_card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(notice_card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	notice_card.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "✨ Démarrage Rapide (Modèle Gratuit Configuré)"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = "Le Routeur Gratuit OpenRouter est prêt à l'emploi sans clé API requise.\n\n💡 Pour explorer des centaines d'autres modèles (DeepSeek, Claude, Llama...) avec leurs caractéristiques complètes, touchez le bouton '🔄 Actualiser' ci-dessus."
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	desc_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	vbox.add_child(desc_lbl)

func _populate_local_special_view() -> void:
	var cat = _get_catalog()

	# Section SLM Embarqués
	var native_title = Label.new()
	native_title.text = "📦 Modèles Embarqués Autonomes (GGUF - Sans Logiciel Externe) :"
	native_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	native_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	native_title.add_theme_color_override("font_color", DesignTokens.ACCENT)
	models_container.add_child(native_title)

	if cat:
		for m in cat.models:
			if m.get("provider") == "native_slm":
				_add_native_slm_card(models_container, m)

	var sep = HSeparator.new()
	models_container.add_child(sep)

	# Section Serveur Ollama
	var ollama_title = Label.new()
	ollama_title.text = "🌐 Modèles Serveur Ollama (127.0.0.1:11434) :"
	ollama_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ollama_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	ollama_title.add_theme_color_override("font_color", Color("#c084fc"))
	models_container.add_child(ollama_title)

	var detect_btn = Button.new()
	detect_btn.text = "🔍 Détecter mes modèles (Ollama)"
	detect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DesignTokens.style_button(detect_btn)
	detect_btn.pressed.connect(func():
		ollama_status_lbl.text = "Recherche d'Ollama sur 127.0.0.1:11434..."
		var c = _get_catalog()
		if c: c.detect_local_ollama_models()
	)
	models_container.add_child(detect_btn)

	ollama_status_lbl = Label.new()
	ollama_status_lbl.text = "Touchez ci-dessus pour scanner votre serveur Ollama local."
	ollama_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ollama_status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	ollama_status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	models_container.add_child(ollama_status_lbl)

	if cat:
		for m in cat.models:
			if m.get("provider") == "ollama":
				_add_openrouter_model_card(models_container, m)

## Carte moderne de présentation d'un modèle OpenRouter / Cloud
func _add_openrouter_model_card(parent: Control, model_dict: Dictionary) -> void:
	var m_id = str(model_dict.get("id", ""))
	var m_name = str(model_dict.get("name", m_id))
	var m_desc = str(model_dict.get("description", ""))
	var is_active = (m_id == current_active_id)
	var is_free = bool(model_dict.get("free_tier", false)) or m_id.ends_with(":free")
	var is_reasoning = bool(model_dict.get("is_reasoning", false))

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := DesignTokens.flat(
			DesignTokens.SURFACE_ELEVATED if not is_active else Color("#172554"),
			DesignTokens.RADIUS_SMALL,
			DesignTokens.ACCENT if is_active else DesignTokens.BORDER,
			1, Vector2(DesignTokens.CARD_PAD_H, DesignTokens.CARD_PAD_V))
	if is_active:
		card_style.border_width_left = 3
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Ligne 1 : Nom + Badges + Bouton 'Choisir'
	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_theme_constant_override("separation", 6)
	vbox.add_child(title_row)

	var name_lbl = Label.new()
	var rec_prefix = "⭐ " if model_dict.get("recommended", false) else ""
	name_lbl.text = rec_prefix + m_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(50, 0)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	name_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	title_row.add_child(name_lbl)

	# Badges indicatifs
	if is_free:
		var b_free = Label.new()
		b_free.text = "🆓 Gratuit"
		b_free.custom_minimum_size = Vector2(36, 0)
		b_free.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
		b_free.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		title_row.add_child(b_free)

	if is_reasoning:
		var b_reas = Label.new()
		b_reas.text = "🧠 Think"
		b_reas.custom_minimum_size = Vector2(36, 0)
		b_reas.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
		b_reas.add_theme_color_override("font_color", Color("#a5b4fc"))
		title_row.add_child(b_reas)

	var btn_select = Button.new()
	btn_select.text = "✓ Actif" if is_active else "Choisir"
	btn_select.disabled = is_active
	btn_select.clip_text = true
	btn_select.custom_minimum_size = Vector2(60, DesignTokens.TOUCH_DENSE)
	btn_select.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_select.pressed.connect(func(): _select_model(m_id))
	title_row.add_child(btn_select)

	# Ligne 2 : Contexte & Coût
	var meta_row = HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_theme_constant_override("separation", 6)
	vbox.add_child(meta_row)

	var ctx_len = int(model_dict.get("context_length", 0))
	var ctx_str = "%dk ctx" % (ctx_len / 1024) if ctx_len >= 1024 else "%d ctx" % ctx_len
	var ctx_lbl = Label.new()
	ctx_lbl.text = "📖 " + ctx_str
	ctx_lbl.custom_minimum_size = Vector2(40, 0)
	ctx_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	ctx_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	meta_row.add_child(ctx_lbl)

	var cost_lbl = Label.new()
	cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_lbl.custom_minimum_size = Vector2(50, 0)
	cost_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var cat = _get_catalog()
	if cat:
		var cost_info = cat.get_cost_estimate(model_dict)
		if cost_info.per_query_usd == 0.0:
			cost_lbl.text = "🟢 0,00 € (Gratuit)"
			cost_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		else:
			cost_lbl.text = "🟡 %s (~%s / 1k)" % [cost_info.label_per_query, cost_info.label_per_1000]
			cost_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
	cost_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	meta_row.add_child(cost_lbl)

	# Ligne 3 : Description
	if m_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = m_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.custom_minimum_size = Vector2(50, 0)
		desc_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
		desc_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		vbox.add_child(desc_lbl)

## Carte pour les modèles SLM autonomes (GGUF)
func _add_native_slm_card(parent: Control, model_dict: Dictionary) -> void:
	var m_id = str(model_dict.get("id", ""))
	var m_name = str(model_dict.get("name", m_id))
	var m_desc = str(model_dict.get("description", ""))
	var is_active = (m_id == current_active_id)

	var downloader = _get_downloader()
	var is_installed = downloader.is_model_installed(m_id) if downloader else false
	var is_currently_downloading = (downloader != null and downloader.is_downloading and downloader.current_download_id == m_id)

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := DesignTokens.flat(
			DesignTokens.SURFACE_ELEVATED if not is_active else Color("#172554"),
			DesignTokens.RADIUS_SMALL,
			DesignTokens.ACCENT if is_active else DesignTokens.BORDER,
			1, Vector2(DesignTokens.CARD_PAD_H, DesignTokens.CARD_PAD_V))
	if is_active:
		card_style.border_width_left = 3
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(top_row)

	var name_lbl = Label.new()
	name_lbl.text = ("⭐ " if model_dict.get("recommended", false) else "") + m_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(50, 0)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	name_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	top_row.add_child(name_lbl)

	if is_installed:
		var btn_select = Button.new()
		btn_select.text = "✓ Actif" if is_active else "Choisir"
		btn_select.disabled = is_active
		btn_select.clip_text = true
		btn_select.custom_minimum_size = Vector2(60, DesignTokens.TOUCH_DENSE)
		btn_select.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		btn_select.pressed.connect(func(): _select_model(m_id))
		top_row.add_child(btn_select)

		var btn_del = Button.new()
		btn_del.text = "🗑️"
		btn_del.tooltip_text = "Supprimer du disque"
		btn_del.custom_minimum_size = Vector2(36, DesignTokens.TOUCH_DENSE)
		btn_del.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		btn_del.pressed.connect(func():
			if downloader: downloader.delete_model(m_id)
		)
		top_row.add_child(btn_del)
	elif is_currently_downloading:
		var btn_cancel = Button.new()
		btn_cancel.text = "❌ Stop"
		btn_cancel.clip_text = true
		btn_cancel.custom_minimum_size = Vector2(64, DesignTokens.TOUCH_DENSE)
		btn_cancel.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		btn_cancel.pressed.connect(func():
			if downloader: downloader.cancel_download()
		)
		top_row.add_child(btn_cancel)
	else:
		var btn_dl = Button.new()
		var size_lbl = "⬇️ Installer"
		if downloader and downloader.DOWNLOADABLE_SLM.has(m_id):
			size_lbl = "⬇️ %s" % downloader.DOWNLOADABLE_SLM[m_id].get("size_label", "")
		btn_dl.text = size_lbl
		btn_dl.clip_text = true
		btn_dl.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_DENSE)
		btn_dl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn_dl.pressed.connect(func():
			if downloader: downloader.start_download(m_id)
		)
		top_row.add_child(btn_dl)

	if is_currently_downloading:
		var pbar = ProgressBar.new()
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbar.custom_minimum_size = Vector2(0, 6)
		pbar.show_percentage = false
		vbox.add_child(pbar)
		download_progress_bars[m_id] = pbar

		var status_lbl = Label.new()
		status_lbl.text = "⬇️ Téléchargement en cours..."
		status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.custom_minimum_size = Vector2(50, 0)
		status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		vbox.add_child(status_lbl)
		download_status_labels[m_id] = status_lbl
	else:
		var status_lbl = Label.new()
		status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_lbl.custom_minimum_size = Vector2(50, 0)
		if is_installed:
			status_lbl.text = "🟢 Installé sur l'appareil (100% hors-ligne • 0,00 €)"
			status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		else:
			status_lbl.text = "⚪ Non installé • 0 € à vie (sans abonnement ni clé API)"
			status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		vbox.add_child(status_lbl)

	if m_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = m_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		desc_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		vbox.add_child(desc_lbl)

func _select_model(m_id: String) -> void:
	current_active_id = m_id
	var sm = _get_settings()
	if sm:
		sm.set_setting("active_model_id", m_id)

	var cat = _get_catalog()
	if cat:
		var model_info = cat.find_model_by_id(m_id)
		var modality = int(model_info.get("modality", 0))
		if modality == ModelCatalogScript.Modality.LOCAL_SLM:
			if sm: sm.set_setting("ai_provider", "local_slm")
		else:
			if sm: sm.set_setting("ai_provider", "openrouter")

	_refresh_active_badge()
	_refresh_models_list()
	model_selected.emit(m_id)

func _on_refresh_catalog_pressed() -> void:
	update_btn.disabled = true
	update_status_lbl.text = "⏳ Téléchargement des derniers modèles OpenRouter..."
	update_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
	var cat = _get_catalog()
	if cat:
		cat.fetch_online_catalog()

func _on_catalog_updated(count: int) -> void:
	update_btn.disabled = false
	update_status_lbl.text = "✓ %d modèles OpenRouter synchronisés à l'instant !" % count
	update_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_refresh_models_list()
	_refresh_active_badge()

func _on_catalog_update_failed(err_msg: String) -> void:
	update_btn.disabled = false
	update_status_lbl.text = "⚠️ " + err_msg
	update_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)

func _on_ollama_detected(models_found: Array) -> void:
	if ollama_status_lbl:
		if models_found.size() > 0:
			ollama_status_lbl.text = "✓ En ligne (%d modèles détectés)" % models_found.size()
			ollama_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		else:
			ollama_status_lbl.text = "Ollama non détecté (Démarrer avec 'ollama serve')"
			ollama_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
	_refresh_models_list()

func _on_slm_download_progress(model_id: String, received_bytes: int, total_bytes: int, percentage: float, speed_mb_s: float) -> void:
	if download_progress_bars.has(model_id):
		var bar: ProgressBar = download_progress_bars[model_id]
		bar.value = percentage
	if download_status_labels.has(model_id):
		var lbl: Label = download_status_labels[model_id]
		var rec_mb = received_bytes / 1048576.0
		var tot_mb = total_bytes / 1048576.0
		lbl.text = "⬇️ %.1f%% • %.1f / %.1f Mo (%.2f Mo/s)" % [percentage, rec_mb, tot_mb, speed_mb_s]

func _on_slm_download_completed(_model_id: String, _file_path: String) -> void:
	_refresh_models_list()
	_refresh_active_badge()

func _on_slm_download_failed(_model_id: String, _error_msg: String) -> void:
	_refresh_models_list()

func _on_slm_model_deleted(_model_id: String) -> void:
	_refresh_models_list()
	_refresh_active_badge()
