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

# Conteneurs d'onglets
var tab_container: TabContainer
var free_models_container: VBoxContainer
var paid_models_container: VBoxContainer
var local_models_container: VBoxContainer
var ollama_status_lbl: Label

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

func _ready() -> void:
	title = "⚡ Hub des Modèles IA & Coach Grand-Maître"
	size = Vector2i(460, 680)
	exclusive = true
	close_requested.connect(queue_free)

	var sm = _get_settings()
	current_active_id = sm.get_setting("active_model_id", "groq/llama-3.3-70b-versatile") if sm else "groq/llama-3.3-70b-versatile"

	var cat = _get_catalog()
	if cat:
		cat.catalog_updated.connect(_on_catalog_updated)
		cat.catalog_update_failed.connect(_on_catalog_update_failed)
		cat.local_ollama_detected.connect(_on_ollama_detected)

	_setup_ui()
	_refresh_active_badge()
	_populate_all_tabs()

func _setup_ui() -> void:
	var root_panel = PanelContainer.new()
	root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("#090d16")
	panel_style.content_margin_left = 14
	panel_style.content_margin_top = 14
	panel_style.content_margin_right = 14
	panel_style.content_margin_bottom = 14
	root_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(root_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	root_panel.add_child(main_vbox)

	# 1. EN-TÊTE & BADGE MODÈLE ACTIF
	var header_box = VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 6)
	main_vbox.add_child(header_box)

	var top_row = HBoxContainer.new()
	header_box.add_child(top_row)

	var title_lbl = Label.new()
	title_lbl.text = "🤖 Modèle Actif :"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	top_row.add_child(title_lbl)

	active_badge_lbl = Label.new()
	active_badge_lbl.text = "Chargement..."
	active_badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_badge_lbl.add_theme_font_size_override("font_size", 12)
	active_badge_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	top_row.add_child(active_badge_lbl)

	# Bouton de mise à jour dynamique du catalogue
	update_btn = Button.new()
	update_btn.text = "🔄 Mettre à jour"
	update_btn.tooltip_text = "Interroge en temps réel les fournisseurs pour rafraîchir la liste et les tarifs des modèles."
	update_btn.add_theme_font_size_override("font_size", 11)
	update_btn.pressed.connect(_on_refresh_catalog_pressed)
	top_row.add_child(update_btn)

	update_status_lbl = Label.new()
	var sm = _get_settings()
	var last_sync = sm.get_setting("last_catalog_sync", "Jamais") if sm else "Jamais"
	update_status_lbl.text = "Dernière synchro : %s" % (last_sync if last_sync != "" else "Catalogue initial embarqué")
	update_status_lbl.add_theme_font_size_override("font_size", 10)
	update_status_lbl.add_theme_color_override("font_color", Color("#64748b"))
	header_box.add_child(update_status_lbl)

	# 2. ONGLETS DE MODALITÉS (Gratuit, Clé API, Local)
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(tab_container)

	# --- ONGLET 1 : CLOUD GRATUIT ---
	var tab_free = _create_tab_scroll("⚡ Cloud Gratuit (0 €)", tab_container)
	free_models_container = tab_free

	# --- ONGLET 2 : CLÉ API / ULTRA-ÉCO ---
	var tab_paid = _create_tab_scroll("🔑 Clé API / Pay-as-you-go", tab_container)
	paid_models_container = tab_paid

	# --- ONGLET 3 : SLM LOCAL HORS-LIGNE ---
	var tab_local = _create_tab_scroll("💻 SLM Local (Hors-ligne)", tab_container)
	local_models_container = tab_local

	# 3. STATISTIQUES DE SESSION & COÛTS
	var footer_box = HBoxContainer.new()
	main_vbox.add_child(footer_box)

	session_stats_lbl = Label.new()
	var coach = _get_coach()
	var q_cnt = coach.session_queries_count if coach else 0
	var q_cst = coach.session_estimated_cost_usd if coach else 0.0
	session_stats_lbl.text = "Session : %d requêtes | Coût estimé : ~%.4f $" % [q_cnt, q_cst]
	session_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_stats_lbl.add_theme_font_size_override("font_size", 11)
	session_stats_lbl.add_theme_color_override("font_color", Color("#a1a1aa"))
	footer_box.add_child(session_stats_lbl)

	var close_btn = Button.new()
	close_btn.text = "Fermer"
	close_btn.custom_minimum_size = Vector2(90, 32)
	close_btn.pressed.connect(queue_free)
	footer_box.add_child(close_btn)

func _create_tab_scroll(tab_title: String, parent: TabContainer) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.name = tab_title
	parent.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	return vbox

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
	desc.text = "Modèles utilisables sans carte bancaire ni frais récurrents. Vitesse extrême et explication humaine."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	free_models_container.add_child(desc)

	var cat = _get_catalog()
	if cat:
		var free_list = cat.get_models_by_modality(ModelCatalogScript.Modality.CLOUD_FREE)
		for m in free_list:
			_add_model_card(free_models_container, m)

	# Clé API Gratuite Configuration (Groq / Gemini)
	var sep = HSeparator.new()
	free_models_container.add_child(sep)

	var key_title = Label.new()
	key_title.text = "🔑 Clés d'Accès Gratuites (Sans Carte Bancaire) :"
	key_title.add_theme_font_size_override("font_size", 12)
	key_title.add_theme_color_override("font_color", Color("#38bdf8"))
	free_models_container.add_child(key_title)

	_add_quick_key_input(free_models_container, "Clé Groq Cloud (Gratuit jusqu'à 14 400 req/jour) :", "api_key_groq", "https://console.groq.com/keys")
	_add_quick_key_input(free_models_container, "Clé Google AI Studio (Gemini Free 15 req/min) :", "api_key_gemini", "https://aistudio.google.com/app/apikey")
	_add_quick_key_input(free_models_container, "Clé OpenRouter (Pour modèles gratuits :free) :", "api_key_openrouter", "https://openrouter.ai/keys")

## 2. Onglet Clé API Payante / Économique
func _populate_paid_tab() -> void:
	for child in paid_models_container.get_children():
		child.queue_free()

	var desc = Label.new()
	desc.text = "Modèles haut de gamme facturés au centième de centime par analyse. Tarifs estimés pour ~800 tokens par coup."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 11)
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
	key_title.add_theme_font_size_override("font_size", 12)
	key_title.add_theme_color_override("font_color", Color("#38bdf8"))
	paid_models_container.add_child(key_title)

	_add_quick_key_input(paid_models_container, "Clé DeepSeek (V4 Flash / R1) :", "api_key_deepseek", "https://platform.deepseek.com")
	_add_quick_key_input(paid_models_container, "Clé OpenAI (GPT-4o) :", "api_key_openai", "https://platform.openai.com")
	_add_quick_key_input(paid_models_container, "Clé Anthropic (Claude 3.5) :", "api_key_anthropic", "https://console.anthropic.com")
	_add_quick_key_input(paid_models_container, "Clé OpenRouter Universelle :", "api_key_openrouter", "https://openrouter.ai/keys")

## 3. Onglet SLM Local Hors-Ligne
func _populate_local_tab() -> void:
	for child in local_models_container.get_children():
		child.queue_free()

	var desc = Label.new()
	desc.text = "Exécution 100% hors-ligne et privée sur votre machine via Ollama ou runtime local. Zéro fuite de données, 0 € à vie."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	local_models_container.add_child(desc)

	# Bouton détection Ollama
	var detect_box = HBoxContainer.new()
	local_models_container.add_child(detect_box)

	var detect_btn = Button.new()
	detect_btn.text = "🔍 Détecter mes modèles locaux (Ollama)"
	detect_btn.pressed.connect(func():
		ollama_status_lbl.text = "Recherche d'Ollama sur 127.0.0.1:11434..."
		var cat = _get_catalog()
		if cat:
			cat.check_local_ollama_models()
	)
	detect_box.add_child(detect_btn)

	ollama_status_lbl = Label.new()
	ollama_status_lbl.text = "Statut : Non testé"
	ollama_status_lbl.add_theme_font_size_override("font_size", 11)
	ollama_status_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	detect_box.add_child(ollama_status_lbl)

	var cat = _get_catalog()
	if cat:
		var local_list = cat.get_models_by_modality(ModelCatalogScript.Modality.LOCAL_SLM)
		for m in local_list:
			_add_model_card(local_models_container, m)

	var sep = HSeparator.new()
	local_models_container.add_child(sep)

	# Guide de téléchargement
	var guide_lbl = Label.new()
	guide_lbl.text = "💡 Comment installer un SLM sur votre ordinateur ?\nOuvrez votre terminal et lancez l'une de ces commandes :"
	guide_lbl.add_theme_font_size_override("font_size", 11)
	guide_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	local_models_container.add_child(guide_lbl)

	_add_copyable_command(local_models_container, "GLM 5.3 Flash (Z.ai 18B Multimodal) :", "ollama run glm-5.3-flash")
	_add_copyable_command(local_models_container, "Qwen 3.8 27B (Top Populaire 2026) :", "ollama run qwen3.8")
	_add_copyable_command(local_models_container, "Nemotron 3.5 Lightning (30B MoE) :", "ollama run nemotron-3.5-lightning")
	_add_copyable_command(local_models_container, "Muse Glimmer 30B (Meta Apache 2.0) :", "ollama run muse-glimmer")
	_add_copyable_command(local_models_container, "SmolLM2 1.7B (Mobile & Léger) :", "ollama run smollm2:1.7b")

## Carte de présentation d'un modèle avec bouton de sélection immédiat
func _add_model_card(parent: Control, model_dict: Dictionary) -> void:
	var m_id = model_dict.get("id", "")
	var m_name = model_dict.get("name", m_id)
	var m_desc = model_dict.get("description", "")
	var is_active = (m_id == current_active_id)

	var card = PanelContainer.new()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color("#131b2e") if not is_active else Color("#172554")
	card_style.border_width_left = 2 if is_active else 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color("#38bdf8") if is_active else Color("#1e293b")
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 10
	card_style.content_margin_top = 8
	card_style.content_margin_right = 10
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var top_row = HBoxContainer.new()
	vbox.add_child(top_row)

	var name_lbl = Label.new()
	name_lbl.text = ("⭐ " if model_dict.get("recommended", false) else "") + m_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	top_row.add_child(name_lbl)

	# Coût indicatif
	var cost_lbl = Label.new()
	var cat = _get_catalog()
	if cat:
		var cost_info = cat.get_cost_estimate(model_dict)
		if cost_info.per_query_usd == 0.0:
			cost_lbl.text = "0,00 € (Gratuit)"
			cost_lbl.add_theme_color_override("font_color", Color("#22c55e"))
		else:
			cost_lbl.text = "%s (%s / 1000)" % [cost_info.label_per_query, cost_info.label_per_1000]
			cost_lbl.add_theme_color_override("font_color", Color("#fbbf24"))
	cost_lbl.add_theme_font_size_override("font_size", 10)
	top_row.add_child(cost_lbl)

	var btn_select = Button.new()
	btn_select.text = "✓ Actif" if is_active else "Choisir"
	btn_select.disabled = is_active
	btn_select.custom_minimum_size = Vector2(70, 24)
	btn_select.add_theme_font_size_override("font_size", 11)
	btn_select.pressed.connect(func(): _select_model(m_id))
	top_row.add_child(btn_select)

	if m_desc != "":
		var desc_lbl = Label.new()
		desc_lbl.text = m_desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_font_size_override("font_size", 10)
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

func _add_quick_key_input(parent: Control, label_text: String, setting_key: String, _help_url: String) -> void:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	row.add_child(lbl)

	var edit_row = HBoxContainer.new()
	row.add_child(edit_row)

	var input = LineEdit.new()
	input.secret = true
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color("#cbd5e1"))
	row.add_child(lbl)

	var cmd_lbl = LineEdit.new()
	cmd_lbl.editable = false
	cmd_lbl.text = command_text
	cmd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_lbl.add_theme_font_size_override("font_size", 10)
	row.add_child(cmd_lbl)

	var copy_btn = Button.new()
	copy_btn.text = "📋 Copier"
	copy_btn.add_theme_font_size_override("font_size", 10)
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(command_text))
	row.add_child(copy_btn)

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
