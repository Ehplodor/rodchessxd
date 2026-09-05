class_name EngineHubModal
extends Window
## EngineHubModal.gd - Gestionnaire de moteurs d'échecs et téléchargement in-app (Maia Chess, Stockfish NNUE)

var http_request: HTTPRequest
var active_download_engine: String = ""
var download_progress_bar: ProgressBar
var status_lbl: Label

func _ready() -> void:
	title = "Engine Hub : Téléchargement de Moteurs"
	size = Vector2i(410, 520)
	exclusive = true
	close_requested.connect(queue_free)
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_download_completed)
	
	EngineManager.download_progress.connect(_on_engine_download_progress)
	EngineManager.download_completed.connect(_on_engine_download_completed)
	EngineManager.download_failed.connect(_on_engine_download_failed)
	EngineManager.engine_ready.connect(_on_engine_ready)
	
	_setup_ui()

func _add_engine_selector(parent: Node) -> void:
	if OS.has_feature("android"):
		var a_note := Label.new()
		a_note.text = "Sur Android, l'analyse utilise Stockfish. Maia (via lc0) n'est pas exécutable sur mobile."
		a_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		a_note.add_theme_font_size_override("font_size", 10)
		a_note.add_theme_color_override("font_color", Color("#94a3b8"))
		parent.add_child(a_note)
		return
	var title := Label.new()
	title.text = "Moteur d'analyse (Maia via lc0)"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color("#cbd5e1"))
	parent.add_child(title)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)

	var stock_btn := _make_choice_button("Stockfish")
	stock_btn.pressed.connect(_pick_engine.bind("stockfish", ""))
	flow.add_child(stock_btn)

	if not EngineManager.is_lc0_binary_present():
		if EngineManager.get_lc0_download_available():
			var dl_btn := _make_choice_button("Télécharger lc0 (Windows)")
			dl_btn.pressed.connect(_start_lc0_download)
			flow.add_child(dl_btn)
		else:
			var note := Label.new()
			note.text = "⚠ Pour analyser avec Maia : placez le binaire lc0 (\"lc0\" ou \"lc0.exe\") dans user://engines/ ou res://bin/."
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.add_theme_font_size_override("font_size", 10)
			note.add_theme_color_override("font_color", Color("#fbbf24"))
			parent.add_child(note)
		return

	for fn in EngineManager.MAIA_NET_FILES:
		if not EngineManager.is_maia_net_installed(fn):
			continue
		var elo := fn.trim_prefix("maia-").trim_suffix(".pb.gz")
		var btn := _make_choice_button("Maia " + elo)
		btn.pressed.connect(_pick_engine.bind("maia_lc0", fn))
		flow.add_child(btn)

func _activate_stockfish() -> void:
	if EngineManager.is_engine_profile_active("stockfish") and EngineManager.is_engine_available():
		status_lbl.text = "Stockfish est déjà actif."
		return
	var ok = EngineManager.set_engine_profile("stockfish")
	status_lbl.text = "Stockfish redémarré." if ok else "⚠ Impossible de démarrer Stockfish (binaire non exécutable ?)."

func _start_lc0_download() -> void:
	if EngineManager.is_lc0_download_active():
		status_lbl.text = "Téléchargement de lc0 déjà en cours..."
		return
	status_lbl.text = "Préparation du téléchargement de lc0 (Windows CPU)..."
	EngineManager.install_lc0_engine()

func _make_choice_button(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, 30)
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1e293b")
	st.set_corner_radius_all(6)
	st.content_margin_left = 10
	st.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_font_size_override("font_size", 11)
	return btn

func _pick_engine(profile: String, maia_fn: String) -> void:
	var ok = EngineManager.set_engine_profile(profile, maia_fn)
	if profile == "maia_lc0" and ok:
		status_lbl.text = "Moteur Maia (%s) sélectionné et démarré." % maia_fn
	elif profile == "stockfish" and ok:
		status_lbl.text = "Moteur Stockfish sélectionné."
	else:
		status_lbl.text = "⚠ Moteur indisponible : vérifiez lc0 / le réseau Maia."

func _setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var desc = Label.new()
	desc.text = "Téléchargez directement des réseaux et moteurs additionnels spécialisés dans l'analyse humaine ou grand-maître."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(desc)

	# Barre de téléchargement
	download_progress_bar = ProgressBar.new()
	download_progress_bar.custom_minimum_size = Vector2(0, 16)
	download_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	download_progress_bar.visible = false
	vbox.add_child(download_progress_bar)

	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	vbox.add_child(status_lbl)

	_add_engine_selector(vbox)

	# Liste des moteurs dans un ScrollContainer sécurisé
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var engines_list = VBoxContainer.new()
	engines_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	engines_list.add_theme_constant_override("separation", 8)
	scroll.add_child(engines_list)

	var is_android = OS.has_feature("android")

	# 1. Stockfish
	var sf_active = EngineManager.is_engine_profile_active("stockfish") and EngineManager.is_engine_available()
	if sf_active:
		_add_engine_card(engines_list, "Stockfish 19 (Actif)", "Moteur mondial #1 avec réseau neuronal NNUE intégré. En cours d'exécution.", true, "")
	elif EngineManager.has_engine_binary():
		_add_engine_card(engines_list, "Stockfish 19 (Disponible)", "Binaire présent mais moteur arrêté. Redémarrez Stockfish pour l'analyse.", false, "", _activate_stockfish, "Redémarrer")
	elif EngineManager.get_stockfish_download_available():
		_add_engine_card(engines_list, "Stockfish 19 (Télécharger)", "Téléchargez automatiquement le moteur officiel depuis le dépôt Stockfish. Aucune installation manuelle requise.", false, "", _start_stockfish_download, "Télécharger")
	else:
		_add_engine_card(engines_list, "Stockfish 19", "Aucun binaire compatible n'est disponible sur cette plateforme.", false, "")

	# 2. Modèles Maia Chess (bureau uniquement — lc0 non exécutable sur Android)
	if is_android:
		var maia_note = Label.new()
		maia_note.text = "ℹ Maia (réseaux neuronaux humains) n'est pas proposé sur Android : il nécessite le moteur lc0, non exécutable sur mobile."
		maia_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		maia_note.add_theme_font_size_override("font_size", 10)
		maia_note.add_theme_color_override("font_color", Color("#94a3b8"))
		engines_list.add_child(maia_note)
	else:
		for name in EngineManager.DOWNLOADABLE_ENGINES.keys():
			var data = EngineManager.DOWNLOADABLE_ENGINES[name]
			var local_file = OS.get_user_data_dir() + "/engines/" + data["filename"]
			var is_installed = FileAccess.file_exists(local_file)
			_add_engine_card(engines_list, name, data["desc"], is_installed, data["url"])

	# Bouton Fermer
	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, 36)
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _add_engine_card(parent: Node, name: String, desc: String, is_installed: bool, download_url: String, on_download: Callable = Callable(), action_label: String = "Télécharger") -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e293b")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var text_box = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	var title_lbl = Label.new()
	title_lbl.text = name
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	text_box.add_child(title_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	text_box.add_child(desc_lbl)

	var action_btn = Button.new()
	action_btn.custom_minimum_size = Vector2(85, 30)
	action_btn.add_theme_font_size_override("font_size", 10)
	if is_installed:
		action_btn.text = "✓ Actif"
		action_btn.disabled = true
	elif download_url != "":
		action_btn.text = "Télécharger"
		action_btn.pressed.connect(func(): _start_download(name, download_url))
	elif on_download.is_valid():
		action_btn.text = action_label
		action_btn.pressed.connect(on_download)
	else:
		action_btn.text = "Indisponible"
		action_btn.disabled = true
	row.add_child(action_btn)

	parent.add_child(panel)

func _start_download(engine_name: String, url: String) -> void:
	active_download_engine = engine_name
	download_progress_bar.visible = true
	download_progress_bar.value = 10
	status_lbl.text = "Téléchargement de %s en cours..." % engine_name

	var filename = EngineManager.DOWNLOADABLE_ENGINES[engine_name]["filename"]
	var save_path = OS.get_user_data_dir() + "/engines/" + filename
	http_request.download_file = save_path
	http_request.request(url)

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	download_progress_bar.visible = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		status_lbl.text = "✅ Téléchargement réussi pour %s !" % active_download_engine
		_reload()
	else:
		status_lbl.text = "❌ Erreur de téléchargement (Code %d)" % response_code

func _start_stockfish_download() -> void:
	if EngineManager.is_stockfish_download_active():
		status_lbl.text = "Téléchargement de Stockfish déjà en cours..."
		return
	status_lbl.text = "Préparation du téléchargement de Stockfish..."
	EngineManager.install_stockfish_engine()

func _on_engine_download_progress(engine_name: String, pct: float) -> void:
	download_progress_bar.visible = true
	download_progress_bar.value = pct
	status_lbl.text = "Téléchargement de %s : %d%%" % [engine_name, int(pct)]

func _on_engine_download_completed(engine_name: String) -> void:
	download_progress_bar.visible = false
	status_lbl.text = "✅ %s installé et prêt !" % engine_name
	_reload()

func _on_engine_download_failed(engine_name: String, error_msg: String) -> void:
	download_progress_bar.visible = false
	status_lbl.text = "❌ %s : %s" % [engine_name, error_msg]

func _on_engine_ready() -> void:
	_reload()

func _reload() -> void:
	for child in get_children():
		if child != http_request:
			child.queue_free()
	_setup_ui()
