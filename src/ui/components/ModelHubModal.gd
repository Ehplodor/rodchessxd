class_name ModelHubModal
extends Window
## ModelHubModal.gd - Interface ergonomique de gestion et configuration des modèles IA (Gratuit, API, Local)
## Permet la mise à jour dynamique du catalogue, l'affichage des coûts de revient et le test de connexion.

signal model_selected(model_id: String)

const ModelCatalogScript = preload("res://src/ai/ModelCatalog.gd")

var active_tab_index: int = 0
var current_active_id: String = ""

# Éléments d'interface
var active_badge_lbl: Label
var update_btn: Button
var update_status_lbl: Label
var session_stats_lbl: Label

# Boutons d'onglets segmentés
var btn_tab_free: Button
var btn_tab_paid: Button
var btn_tab_local: Button

# Conteneurs de défilement pour chaque onglet
var scroll_free: ScrollContainer
var scroll_paid: ScrollContainer
var scroll_local: ScrollContainer

var free_models_container: VBoxContainer
var paid_models_container: VBoxContainer
var local_models_container: VBoxContainer
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
	title = "⚡ Hub des Modèles IA"
	size = Vector2i(410, 650)
	exclusive = true
	close_requested.connect(queue_free)

	var sm = _get_settings()
	current_active_id = sm.get_setting("active_model_id", "z-ai/glm-5.3-flash:free") if sm else "z-ai/glm-5.3-flash:free"

	var cat = _get_catalog()
	if cat:
		cat.catalog_updated.connect(_on_catalog_updated)
		cat.catalog_update_failed.connect(_on_catalog_update_failed)
		cat.local_ollama_detected.connect(_on_ollama_detected)

	var dl = _get_downloader()
	if dl:
		dl.download_progress.connect(_on_slm_download_progress)
		dl.download_completed.connect(_on_slm_download_completed)
		dl.download_failed.connect(_on_slm_download_failed)
		dl.model_deleted.connect(_on_slm_model_deleted)

	_setup_ui()
	_refresh_active_badge()
	_populate_all_tabs()
	_switch_tab(0)

func _setup_ui() -> void:
	var root_panel = PanelContainer.new()
	root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#090d16")
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 8
	root_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(root_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 8)
	root_panel.add_child(main_vbox)

	# 1. EN-TÊTE & BADGE MODÈLE ACTIF
	var header_box = VBoxContainer.new()
	header_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_theme_constant_override("separation", 4)
	main_vbox.add_child(header_box)

	var top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(top_row)

	var title_lbl = Label.new()
	title_lbl.text = "🤖 Modèle Actif :"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	top_row.add_child(title_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	update_btn = Button.new()
	update_btn.text = "🔄 Actualiser"
	update_btn.tooltip_text = "Rafraîchir les modèles et tarifs en ligne"
	update_btn.add_theme_font_size_override("font_size", 10)
	update_btn.pressed.connect(_on_refresh_catalog_pressed)
	top_row.add_child(update_btn)

	active_badge_lbl = Label.new()
	active_badge_lbl.text = "Chargement..."
	active_badge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	active_badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_badge_lbl.add_theme_font_size_override("font_size", 11)
	active_badge_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	header_box.add_child(active_badge_lbl)

	update_status_lbl = Label.new()
	var sm = _get_settings()
	var last_sync = sm.get_setting("last_catalog_sync", "Jamais") if sm else "Jamais"
	update_status_lbl.text = "Dernière synchro : %s" % (last_sync if last_sync != "" else "Catalogue initial")
	update_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_status_lbl.add_theme_font_size_override("font_size", 9)
	update_status_lbl.add_theme_color_override("font_color", Color("#64748b"))
	header_box.add_child(update_status_lbl)

	# 2. ONGLETS SEGMENTÉS MODERNES & RESPONSIVES (Garanti sans débordement)
	var tab_bar = HBoxContainer.new()
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_theme_constant_override("separation", 6)
	main_vbox.add_child(tab_bar)

	btn_tab_free = Button.new()
	btn_tab_free.text = "⚡ Gratuit"
	btn_tab_free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tab_free.add_theme_font_size_override("font_size", 11)
	btn_tab_free.pressed.connect(func(): _switch_tab(0))
	tab_bar.add_child(btn_tab_free)

	btn_tab_paid = Button.new()
	btn_tab_paid.text = "🔑 Clés API"
	btn_tab_paid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tab_paid.add_theme_font_size_override("font_size", 11)
	btn_tab_paid.pressed.connect(func(): _switch_tab(1))
	tab_bar.add_child(btn_tab_paid)

	btn_tab_local = Button.new()
	btn_tab_local.text = "💻 Local"
	btn_tab_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tab_local.add_theme_font_size_override("font_size", 11)
	btn_tab_local.pressed.connect(func(): _switch_tab(2))
	tab_bar.add_child(btn_tab_local)

	# 3. CONTENEURS D'ONGLETS INDÉPENDANTS (Scrollable sans défilement horizontal)
	var tabs_content_area = PanelContainer.new()
	tabs_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tab_bg = StyleBoxFlat.new()
	tab_bg.bg_color = Color("#0b1120")
	tab_bg.corner_radius_top_left = 6
	tab_bg.corner_radius_top_right = 6
	tab_bg.corner_radius_bottom_left = 6
	tab_bg.corner_radius_bottom_right = 6
	tab_bg.content_margin_left = 6
	tab_bg.content_margin_top = 6
	tab_bg.content_margin_right = 6
	tab_bg.content_margin_bottom = 6
	tabs_content_area.add_theme_stylebox_override("panel", tab_bg)
	main_vbox.add_child(tabs_content_area)

	# --- ONGLET 1 : GRATUIT ---
	scroll_free = ScrollContainer.new()
	scroll_free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_free.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_free.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_content_area.add_child(scroll_free)

	free_models_container = VBoxContainer.new()
	free_models_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	free_models_container.add_theme_constant_override("separation", 8)
	scroll_free.add_child(free_models_container)

	# --- ONGLET 2 : CLÉ API ---
	scroll_paid = ScrollContainer.new()
	scroll_paid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_paid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_paid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_content_area.add_child(scroll_paid)

	paid_models_container = VBoxContainer.new()
	paid_models_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paid_models_container.add_theme_constant_override("separation", 8)
	scroll_paid.add_child(paid_models_container)

	# --- ONGLET 3 : SLM LOCAL ---
	scroll_local = ScrollContainer.new()
	scroll_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_local.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_local.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_content_area.add_child(scroll_local)

	local_models_container = VBoxContainer.new()
	local_models_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_models_container.add_theme_constant_override("separation", 8)
	scroll_local.add_child(local_models_container)

	# 4. STATISTIQUES DE SESSION & BOUTON FERMER
	var footer_box = HBoxContainer.new()
	footer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_box.add_theme_constant_override("separation", 8)
	main_vbox.add_child(footer_box)

	session_stats_lbl = Label.new()
	var coach = _get_coach()
	var q_cnt = coach.session_queries_count if coach else 0
	var q_cst = coach.session_estimated_cost_usd if coach else 0.0
	session_stats_lbl.text = "Session : %d req | ~%.4f $" % [q_cnt, q_cst]
	session_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_stats_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	session_stats_lbl.add_theme_font_size_override("font_size", 10)
	session_stats_lbl.add_theme_color_override("font_color", Color("#a1a1aa"))
	footer_box.add_child(session_stats_lbl)

	var close_btn = Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(80, 30)
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.pressed.connect(queue_free)
	footer_box.add_child(close_btn)

func _switch_tab(idx: int) -> void:
	active_tab_index = idx
	scroll_free.visible = (idx == 0)
	scroll_paid.visible = (idx == 1)
	scroll_local.visible = (idx == 2)

	# Mise à jour visuelle des boutons d'onglets
	_style_tab_button(btn_tab_free, idx == 0)
	_style_tab_button(btn_tab_paid, idx == 1)
	_style_tab_button(btn_tab_local, idx == 2)

func _style_tab_button(btn: Button, is_selected: bool) -> void:
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	if is_selected:
		style.bg_color = Color("#1e293b")
		style.border_width_bottom = 2
		style.border_color = Color("#38bdf8")
		btn.add_theme_color_override("font_color", Color("#38bdf8"))
	else:
		style.bg_color = Color("#0f172a")
		btn.add_theme_color_override("font_color", Color("#94a3b8"))
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("hover", style)

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

func _populate_all_tabs() -> void:
	_populate_free_tab()
	_populate_paid_tab()
	_populate_local_tab()

## 1. Onglet Cloud Gratuit
func _populate_free_tab() -> void:
	for child in free_models_container.get_children():
		child.queue_free()

	var desc = Label.new()
	desc.text = "Modèles gratuits sans carte bancaire ni frais récurrents. Vitesse extrême et explication humaine."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	free_models_container.add_child(desc)

	var cat = _get_catalog()
	if cat:
		var free_list = cat.get_models_by_modality(ModelCatalogScript.Modality.CLOUD_FREE)
		for m in free_list:
			_add_model_card(free_models_container, m)

	var sep = HSeparator.new()
	free_models_container.add_child(sep)

	var key_title = Label.new()
	key_title.text = "🔑 Clés d'Accès Gratuites (Sans Carte Bancaire) :"
	key_title.add_theme_font_size_override("font_size", 11)
	key_title.add_theme_color_override("font_color", Color("#38bdf8"))
	free_models_container.add_child(key_title)

	_add_quick_key_input(free_models_container, "Clé OpenRouter (Pour modèles gratuits :free) :", "api_key_openrouter", "https://openrouter.ai/keys")
	_add_quick_key_input(free_models_container, "Clé Groq Cloud (Gratuit jusqu'à 14 400 req/jour) :", "api_key_groq", "https://console.groq.com/keys")
	_add_quick_key_input(free_models_container, "Clé Google AI Studio (Gemini Free 15 req/min) :", "api_key_gemini", "https://aistudio.google.com/app/apikey")

## 2. Onglet Clé API Payante / Économique
func _populate_paid_tab() -> void:
	for child in paid_models_container.get_children():
		child.queue_free()

	var desc = Label.new()
	desc.text = "Modèles de pointe facturés à l'usage (quelques centièmes de centime par analyse)."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	paid_models_container.add_child(desc)

	var cat = _get_catalog()
	if cat:
		var paid_list = cat.get_models_by_modality(ModelCatalogScript.Modality.API_PAID)
		for m in paid_list:
			_add_model_card(paid_models_container, m)

	var sep = HSeparator.new()
	paid_models_container.add_child(sep)

	var key_title = Label.new()
	key_title.text = "🔑 Vos Clés API Personnelles :"
	key_title.add_theme_font_size_override("font_size", 11)
	key_title.add_theme_color_override("font_color", Color("#38bdf8"))
	paid_models_container.add_child(key_title)

	_add_quick_key_input(paid_models_container, "Clé OpenRouter Universelle :", "api_key_openrouter", "https://openrouter.ai/keys")
	_add_quick_key_input(paid_models_container, "Clé DeepSeek (V4 Flash / R1) :", "api_key_deepseek", "https://platform.deepseek.com")
	_add_quick_key_input(paid_models_container, "Clé OpenAI (GPT-4o) :", "api_key_openai", "https://platform.openai.com")
	_add_quick_key_input(paid_models_container, "Clé Anthropic (Claude 3.5) :", "api_key_anthropic", "https://console.anthropic.com")

## 3. Onglet SLM Local Hors-Ligne
func _populate_local_tab() -> void:
	download_progress_bars.clear()
	download_status_labels.clear()

	for child in local_models_container.get_children():
		child.queue_free()

	# --- SECTION A : COACH AUTONOME EMBARQUÉ (SANS OLLAMA) ---
	var native_title = Label.new()
	native_title.text = "📦 Coach Autonome Embarqué (Sans Ollama) :"
	native_title.add_theme_font_size_override("font_size", 11)
	native_title.add_theme_color_override("font_color", Color("#38bdf8"))
	local_models_container.add_child(native_title)

	var native_desc = Label.new()
	native_desc.text = "Modèles d'IA légers (GGUF) stockés sur votre appareil. 100% privé, 0 € à vie, sans connexion Internet et sans logiciel externe requis."
	native_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	native_desc.add_theme_font_size_override("font_size", 10)
	native_desc.add_theme_color_override("font_color", Color("#94a3b8"))
	local_models_container.add_child(native_desc)

	var cat = _get_catalog()
	if cat:
		var local_list = cat.get_models_by_modality(ModelCatalogScript.Modality.LOCAL_SLM)
		for m in local_list:
			if m.get("provider") == "native_slm":
				_add_native_slm_card(local_models_container, m)

	var sep_ollama = HSeparator.new()
	local_models_container.add_child(sep_ollama)

	# --- SECTION B : SERVEUR OLLAMA EXTERNE ---
	var ollama_title = Label.new()
	ollama_title.text = "🌐 Serveur Externe Ollama (Utilisateurs Avancés) :"
	ollama_title.add_theme_font_size_override("font_size", 11)
	ollama_title.add_theme_color_override("font_color", Color("#c084fc"))
	local_models_container.add_child(ollama_title)

	var ollama_desc = Label.new()
	ollama_desc.text = "Connectez RodChessXD à votre instance Ollama locale (127.0.0.1:11434)."
	ollama_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ollama_desc.add_theme_font_size_override("font_size", 10)
	ollama_desc.add_theme_color_override("font_color", Color("#94a3b8"))
	local_models_container.add_child(ollama_desc)

	# Bouton détection Ollama
	var detect_box = HBoxContainer.new()
	detect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	local_models_container.add_child(detect_box)

	var detect_btn = Button.new()
	detect_btn.text = "🔍 Détecter mes modèles (Ollama)"
	detect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detect_btn.add_theme_font_size_override("font_size", 11)
	detect_btn.pressed.connect(func():
		ollama_status_lbl.text = "Recherche d'Ollama sur 127.0.0.1:11434..."
		var c = _get_catalog()
		if c: c.detect_local_ollama_models()
	)
	detect_box.add_child(detect_btn)

	ollama_status_lbl = Label.new()
	ollama_status_lbl.text = "Cliquez ci-dessus pour scanner votre serveur Ollama local."
	ollama_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ollama_status_lbl.add_theme_font_size_override("font_size", 10)
	ollama_status_lbl.add_theme_color_override("font_color", Color("#64748b"))
	local_models_container.add_child(ollama_status_lbl)

	if cat:
		var local_list = cat.get_models_by_modality(ModelCatalogScript.Modality.LOCAL_SLM)
		for m in local_list:
			if m.get("provider") == "ollama":
				_add_model_card(local_models_container, m)

	var sep = HSeparator.new()
	local_models_container.add_child(sep)

	var guide_lbl = Label.new()
	guide_lbl.text = "💻 Commandes d'installation pour Ollama :"
	guide_lbl.add_theme_font_size_override("font_size", 11)
	guide_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	local_models_container.add_child(guide_lbl)

	_add_copyable_command(local_models_container, "GLM 5.3 Flash (18B Actifs) :", "ollama run glm-5.3-flash")
	_add_copyable_command(local_models_container, "Qwen 3.8 27B :", "ollama run qwen3.8")
	_add_copyable_command(local_models_container, "Nemotron 3.5 Lightning (30B) :", "ollama run nemotron-3.5-lightning")
	_add_copyable_command(local_models_container, "SmolLM2 1.7B (Ultra-léger) :", "ollama run smollm2:1.7b")

## Carte pour les modèles SLM autonomes avec gestionnaire de téléchargement et suppression
func _add_native_slm_card(parent: Control, model_dict: Dictionary) -> void:
	var m_id = model_dict.get("id", "")
	var m_name = model_dict.get("name", m_id)
	var m_desc = model_dict.get("description", "")
	var is_active = (m_id == current_active_id)

	var downloader = _get_downloader()
	var is_installed = downloader.is_model_installed(m_id) if downloader else false
	var is_currently_downloading = (downloader != null and downloader.is_downloading and downloader.current_download_id == m_id)

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color("#0f172a") if not is_active else Color("#172554")
	card_style.border_width_left = 2 if is_active else 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color("#38bdf8") if is_active else Color("#334155")
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 8
	card_style.content_margin_top = 6
	card_style.content_margin_right = 8
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Ligne 1 : Nom à gauche, Action à droite
	var top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(top_row)

	var name_lbl = Label.new()
	name_lbl.text = ("⭐ " if model_dict.get("recommended", false) else "") + m_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	top_row.add_child(name_lbl)

	if is_installed:
		var btn_select = Button.new()
		btn_select.text = "✓ Actif" if is_active else "Choisir"
		btn_select.disabled = is_active
		btn_select.custom_minimum_size = Vector2(64, 24)
		btn_select.add_theme_font_size_override("font_size", 10)
		btn_select.pressed.connect(func(): _select_model(m_id))
		top_row.add_child(btn_select)

		var btn_del = Button.new()
		btn_del.text = "🗑️"
		btn_del.tooltip_text = "Supprimer du disque"
		btn_del.custom_minimum_size = Vector2(28, 24)
		btn_del.add_theme_font_size_override("font_size", 10)
		btn_del.pressed.connect(func():
			if downloader: downloader.delete_model(m_id)
		)
		top_row.add_child(btn_del)
	elif is_currently_downloading:
		var btn_cancel = Button.new()
		btn_cancel.text = "❌ Annuler"
		btn_cancel.custom_minimum_size = Vector2(75, 24)
		btn_cancel.add_theme_font_size_override("font_size", 10)
		btn_cancel.pressed.connect(func():
			if downloader: downloader.cancel_download()
		)
		top_row.add_child(btn_cancel)
	else:
		var btn_dl = Button.new()
		var size_lbl = "Télécharger"
		if downloader and downloader.DOWNLOADABLE_SLM.has(m_id):
			size_lbl = "⬇️ Installer (%s)" % downloader.DOWNLOADABLE_SLM[m_id].get("size_label", "")
		btn_dl.text = size_lbl
		btn_dl.custom_minimum_size = Vector2(110, 24)
		btn_dl.add_theme_font_size_override("font_size", 10)
		btn_dl.pressed.connect(func():
			if downloader: downloader.start_download(m_id)
		)
		top_row.add_child(btn_dl)

	# Ligne 2 : Statut & Jauge de progression
	if is_currently_downloading:
		var pbar = ProgressBar.new()
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbar.custom_minimum_size = Vector2(0, 6)
		pbar.show_percentage = false
		vbox.add_child(pbar)
		download_progress_bars[m_id] = pbar

		var status_lbl = Label.new()
		status_lbl.text = "⬇️ Téléchargement en cours..."
		status_lbl.add_theme_font_size_override("font_size", 9)
		status_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
		vbox.add_child(status_lbl)
		download_status_labels[m_id] = status_lbl
	else:
		var status_lbl = Label.new()
		if is_installed:
			status_lbl.text = "🟢 Installé sur l'appareil (100% hors-ligne • 0,00 €)"
			status_lbl.add_theme_color_override("font_color", Color("#22c55e"))
		else:
			status_lbl.text = "⚪ Non installé • 0 € à vie (aucun abonnement ni clé API)"
			status_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
		status_lbl.add_theme_font_size_override("font_size", 9)
		vbox.add_child(status_lbl)

	# Ligne 3 : Description
	if m_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = m_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color("#64748b"))
		vbox.add_child(desc_lbl)

## Carte de présentation d'un modèle avec disposition multi-lignes 100% responsive
func _add_model_card(parent: Control, model_dict: Dictionary) -> void:
	var m_id = model_dict.get("id", "")
	var m_name = model_dict.get("name", m_id)
	var m_desc = model_dict.get("description", "")
	var is_active = (m_id == current_active_id)

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color("#131b2e") if not is_active else Color("#172554")
	card_style.border_width_left = 2 if is_active else 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color("#38bdf8") if is_active else Color("#1e293b")
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 8
	card_style.content_margin_top = 6
	card_style.content_margin_right = 8
	card_style.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Ligne 1 : Titre à gauche, Bouton 'Choisir' à droite (TOUJOURS visible et aligné)
	var title_row = HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title_row)

	var name_lbl = Label.new()
	name_lbl.text = ("⭐ " if model_dict.get("recommended", false) else "") + m_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	title_row.add_child(name_lbl)

	var btn_select = Button.new()
	btn_select.text = "✓ Actif" if is_active else "Choisir"
	btn_select.disabled = is_active
	btn_select.custom_minimum_size = Vector2(64, 24)
	btn_select.add_theme_font_size_override("font_size", 10)
	btn_select.pressed.connect(func(): _select_model(m_id))
	title_row.add_child(btn_select)

	# Ligne 2 : Coût indicatif
	var cost_lbl = Label.new()
	var cat = _get_catalog()
	if cat:
		var cost_info = cat.get_cost_estimate(model_dict)
		if cost_info.per_query_usd == 0.0:
			cost_lbl.text = "🟢 0,00 € (Gratuit)"
			cost_lbl.add_theme_color_override("font_color", Color("#22c55e"))
		else:
			cost_lbl.text = "🟡 %s (%s / 1000)" % [cost_info.label_per_query, cost_info.label_per_1000]
			cost_lbl.add_theme_color_override("font_color", Color("#fbbf24"))
	cost_lbl.add_theme_font_size_override("font_size", 9)
	vbox.add_child(cost_lbl)

	# Ligne 3 : Description avec retour à la ligne
	if m_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = m_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
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
		match modality:
			ModelCatalogScript.Modality.CLOUD_FREE:
				if sm: sm.set_setting("ai_provider", "free_cloud")
			ModelCatalogScript.Modality.API_PAID:
				if sm: sm.set_setting("ai_provider", "api_key")
			ModelCatalogScript.Modality.LOCAL_SLM:
				if sm: sm.set_setting("ai_provider", "local_slm")

	_refresh_active_badge()
	_populate_all_tabs()
	model_selected.emit(m_id)

func _add_quick_key_input(parent: Control, label_text: String, setting_key: String, _url_hint: String = "") -> void:
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	box.add_child(lbl)

	var edit_row = HBoxContainer.new()
	edit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(edit_row)

	var input = LineEdit.new()
	input.secret = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 10)
	var sm = _get_settings()
	input.text = sm.get_setting(setting_key, "") if sm else ""
	input.text_changed.connect(func(val):
		var s = _get_settings()
		if s:
			s.set_setting(setting_key, val.strip_edges())
	)
	edit_row.add_child(input)

	var show_btn = Button.new()
	show_btn.text = "👁️"
	show_btn.tooltip_text = "Afficher/Masquer la clé"
	show_btn.pressed.connect(func(): input.secret = not input.secret)
	edit_row.add_child(show_btn)

func _add_copyable_command(parent: Control, label_text: String, command_text: String) -> void:
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	box.add_child(lbl)

	var cmd_row = HBoxContainer.new()
	cmd_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(cmd_row)

	var cmd_lbl = LineEdit.new()
	cmd_lbl.editable = false
	cmd_lbl.text = command_text
	cmd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_lbl.add_theme_font_size_override("font_size", 9)
	cmd_row.add_child(cmd_lbl)

	var copy_btn = Button.new()
	copy_btn.text = "📋 Copier"
	copy_btn.add_theme_font_size_override("font_size", 9)
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(command_text))
	cmd_row.add_child(copy_btn)

# --- SIGNAUX & MISES À JOUR ---

func _on_refresh_catalog_pressed() -> void:
	update_btn.disabled = true
	update_status_lbl.text = "⏳ Téléchargement des derniers modèles et tarifs..."
	update_status_lbl.add_theme_color_override("font_color", Color("#fbbf24"))
	var cat = _get_catalog()
	if cat:
		cat.fetch_online_catalog()

func _on_catalog_updated(count: int) -> void:
	update_btn.disabled = false
	update_status_lbl.text = "✓ %d modèles synchronisés à l'instant !" % count
	update_status_lbl.add_theme_color_override("font_color", Color("#22c55e"))
	_populate_all_tabs()
	_refresh_active_badge()

func _on_catalog_update_failed(err_msg: String) -> void:
	update_btn.disabled = false
	update_status_lbl.text = "⚠️ " + err_msg
	update_status_lbl.add_theme_color_override("font_color", Color("#ef4444"))

func _on_ollama_detected(models_found: Array) -> void:
	if models_found.size() > 0:
		ollama_status_lbl.text = "✓ En ligne (%d modèles détectés)" % models_found.size()
		ollama_status_lbl.add_theme_color_override("font_color", Color("#22c55e"))
		_populate_local_tab()
	else:
		ollama_status_lbl.text = "Ollama non détecté (Démarrer avec 'ollama serve')"
		ollama_status_lbl.add_theme_color_override("font_color", Color("#ef4444"))

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
	_populate_local_tab()
	_refresh_active_badge()

func _on_slm_download_failed(_model_id: String, _error_msg: String) -> void:
	_populate_local_tab()

func _on_slm_model_deleted(_model_id: String) -> void:
	_populate_local_tab()
	_refresh_active_badge()
