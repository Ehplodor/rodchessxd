class_name ChessComImportModal
extends Window
## ChessComImportModal.gd - Modale de récupération et sélection des parties d'un joueur Chess.com
## Affiche une liste ergonomique, responsive et détaillée des parties importées.

signal game_selected(pgn: String)

const ChessComService = preload("res://src/network/ChessComService.gd")

var chess_com_service: ChessComService
var username_input: LineEdit
var status_lbl: Label
var games_container: VBoxContainer
var all_games: Array[Dictionary] = []
var active_filter: String = "all"
var filter_buttons: Dictionary = {}

func _ready() -> void:
	title = "Importer depuis Chess.com"
	exclusive = true
	close_requested.connect(queue_free)

	_configure_window_size()

	chess_com_service = ChessComService.new()
	add_child(chess_com_service)
	chess_com_service.games_fetched.connect(_on_games_fetched)
	chess_com_service.fetch_error.connect(_on_fetch_error)

	_setup_ui()

func _configure_window_size() -> void:
	var screen_w = 450.0
	var screen_h = 800.0
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		var root_rect = tree.root.get_visible_rect()
		if root_rect.size.x > 0:
			screen_w = root_rect.size.x
			screen_h = root_rect.size.y
	elif DisplayServer.window_get_size().x > 0:
		var win_s = DisplayServer.window_get_size()
		screen_w = win_s.x
		screen_h = win_s.y

	var target_w = int(clampf(screen_w * 0.94, 340.0, 425.0))
	var target_h = int(clampf(screen_h * 0.90, 440.0, 720.0))
	size = Vector2i(target_w, target_h)

func _setup_ui() -> void:
	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 10))
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	add_child(bg_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.clip_contents = true
	vbox.add_theme_constant_override("separation", 8)
	bg_panel.add_child(vbox)

	# 1. En-tête & Saisie du pseudo
	var input_row = HBoxContainer.new()
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	username_input = LineEdit.new()
	username_input.placeholder_text = "Pseudo (ex: magnuscarlsen, hikaru)..."
	username_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_input.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	username_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var sm = _get_settings()
	if sm:
		username_input.text = sm.get_setting("last_chesscom_user", "")
	username_input.text_submitted.connect(func(_t): _start_fetch())
	input_row.add_child(username_input)

	var btn_fetch = Button.new()
	btn_fetch.text = "🔍 Chercher"
	btn_fetch.custom_minimum_size = Vector2(100, DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(btn_fetch)
	btn_fetch.pressed.connect(_start_fetch)
	input_row.add_child(btn_fetch)

	# 2. Label de statut
	status_lbl = Label.new()
	status_lbl.text = "Entrez un pseudo pour charger les dernières parties officielles."
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(status_lbl)

	# 3. Filtres de cadence (Blitz, Rapide, Bullet, etc.)
	var filters_row = HBoxContainer.new()
	filters_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters_row.add_theme_constant_override("separation", 4)
	vbox.add_child(filters_row)

	_add_filter_btn(filters_row, "Tout", "all")
	_add_filter_btn(filters_row, "⚡ Blitz", "blitz")
	_add_filter_btn(filters_row, "⏱️ Rapide", "rapid")
	_add_filter_btn(filters_row, "🚅 Bullet", "bullet")
	_add_filter_btn(filters_row, "♟️ Différé", "daily")
	_update_filter_buttons_style()

	# 4. Liste déroulante des parties
	var scroll = ScrollContainer.new()
	scroll.clip_contents = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(scroll)
	vbox.add_child(scroll)

	games_container = VBoxContainer.new()
	games_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_container.clip_contents = true
	games_container.add_theme_constant_override("separation", 6)
	scroll.add_child(games_container)

	# 5. Bouton Fermer
	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _get_settings() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _add_filter_btn(parent: Node, label_text: String, filter_key: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.clip_text = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn.pressed.connect(func():
		active_filter = filter_key
		_update_filter_buttons_style()
		_render_games_list()
	)
	filter_buttons[filter_key] = btn
	parent.add_child(btn)

func _update_filter_buttons_style() -> void:
	for key in filter_buttons.keys():
		var btn: Button = filter_buttons[key]
		if not is_instance_valid(btn):
			continue
		if key == active_filter:
			var active_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					DesignTokens.ACCENT, 1, Vector2(4, 2))
			btn.add_theme_stylebox_override("normal", active_s)
			btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
		else:
			var normal_s = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					Color.TRANSPARENT, 0, Vector2(4, 2))
			btn.add_theme_stylebox_override("normal", normal_s)
			btn.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)

func _start_fetch() -> void:
	var user = username_input.text.strip_edges()
	if user == "":
		status_lbl.text = "Veuillez entrer un pseudo."
		status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		return

	var sm = _get_settings()
	if sm:
		sm.set_setting("last_chesscom_user", user)

	status_lbl.text = "⏳ Récupération des parties récentes pour %s..." % user
	status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)

	for child in games_container.get_children():
		child.queue_free()

	var loading_card = PanelContainer.new()
	loading_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL, DesignTokens.BORDER, 1, Vector2(10, 16))
	loading_card.add_theme_stylebox_override("panel", l_style)
	var l_lbl = Label.new()
	l_lbl.text = "⏳ Connexion à Chess.com en cours..."
	l_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	l_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	loading_card.add_child(l_lbl)
	games_container.add_child(loading_card)

	chess_com_service.fetch_player_games(user, 40)

func _on_games_fetched(games: Array[Dictionary]) -> void:
	all_games = games
	status_lbl.text = "✅ %d parties chargées pour %s." % [games.size(), username_input.text]
	status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)

	# Sauvegarde automatique dans la bibliothèque locale DatabaseManager et association des IDs
	var tree = Engine.get_main_loop() as SceneTree
	var dm = tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null
	if dm:
		for g in games:
			var gid = dm.record_chesscom_game(g)
			g["game_id"] = gid

	_update_filter_counts()
	_render_games_list()

func _update_filter_counts() -> void:
	var counts := {"all": all_games.size(), "blitz": 0, "rapid": 0, "bullet": 0, "daily": 0}
	for g in all_games:
		var tc = g.get("time_class", "")
		if counts.has(tc):
			counts[tc] += 1

	if filter_buttons.has("all"):
		filter_buttons["all"].text = "Tout (%d)" % counts["all"]
	if filter_buttons.has("blitz"):
		filter_buttons["blitz"].text = "⚡ %d" % counts["blitz"]
	if filter_buttons.has("rapid"):
		filter_buttons["rapid"].text = "⏱️ %d" % counts["rapid"]
	if filter_buttons.has("bullet"):
		filter_buttons["bullet"].text = "🚅 %d" % counts["bullet"]
	if filter_buttons.has("daily"):
		filter_buttons["daily"].text = "♟️ %d" % counts["daily"]

func _on_fetch_error(msg: String, diag: Dictionary = {}) -> void:
	status_lbl.text = "❌ " + msg
	status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
	for child in games_container.get_children():
		child.queue_free()
	if not diag.is_empty():
		_show_diagnostic_popup(diag)

## Pop-up persistant de diagnostic algorithmique réseau (sans minuterie d'auto-fermeture)
func _show_diagnostic_popup(diag: Dictionary) -> void:
	var old = get_node_or_null("DiagnosticOverlay")
	if old:
		old.queue_free()

	var overlay = Control.new()
	overlay.name = "DiagnosticOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 50
	add_child(overlay)

	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.06, 0.09, 0.88)
	overlay.add_child(backdrop)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	var card_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM, DesignTokens.BORDER, 2, Vector2(16, 16))
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	card.add_child(content_vbox)

	var header_box = VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	content_vbox.add_child(header_box)

	var title_lbl = Label.new()
	title_lbl.text = "🚨 " + str(diag.get("title", "Diagnostic Réseau"))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
	header_box.add_child(title_lbl)

	var badge_row = HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 6)
	content_vbox.add_child(badge_row)

	var code_val = int(diag.get("response_code", 0))
	var pill_http = Label.new()
	pill_http.text = " HTTP %d " % code_val
	pill_http.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var pill_style1 = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL)
	pill_http.add_theme_stylebox_override("normal", pill_style1)
	pill_http.add_theme_color_override("font_color", DesignTokens.DANGER if code_val >= 400 or code_val == 0 else DesignTokens.TEXT_PRIMARY)
	badge_row.add_child(pill_http)

	var pill_res = Label.new()
	pill_res.text = " %s (%d) " % [diag.get("result_name", "UNKNOWN"), diag.get("result_code", -1)]
	pill_res.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var pill_style2 = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL, DesignTokens.BORDER, 1)
	pill_res.add_theme_stylebox_override("normal", pill_style2)
	pill_res.add_theme_color_override("font_color", DesignTokens.ACCENT)
	badge_row.add_child(pill_res)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(scroll)
	content_vbox.add_child(scroll)

	var text_vbox = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(text_vbox)

	var cause_title = Label.new()
	cause_title.text = "🔍 Cause algorithmique la plus probable :"
	cause_title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	cause_title.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	text_vbox.add_child(cause_title)

	var cause_lbl = Label.new()
	cause_lbl.text = str(diag.get("probable_cause", "Aucune information détaillée disponible."))
	cause_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cause_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	cause_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	text_vbox.add_child(cause_lbl)

	var rec_title = Label.new()
	rec_title.text = "💡 Vérifications conseillées :"
	rec_title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	rec_title.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	text_vbox.add_child(rec_title)

	var recs: Array = diag.get("recommendations", [])
	for r in recs:
		var rec_lbl = Label.new()
		rec_lbl.text = "• " + str(r)
		rec_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rec_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		rec_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		text_vbox.add_child(rec_lbl)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	content_vbox.add_child(btn_row)

	var btn_copy = Button.new()
	btn_copy.text = "📋 Copier le rapport"
	btn_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_copy.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	btn_copy.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	DesignTokens.style_button(btn_copy)
	var report_text = str(diag.get("formatted_report", ""))
	btn_copy.pressed.connect(func():
		DisplayServer.clipboard_set(report_text)
		btn_copy.text = "✅ Rapport copié !"
	)
	btn_row.add_child(btn_copy)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	DesignTokens.style_button(btn_close)
	btn_close.pressed.connect(overlay.queue_free)
	btn_row.add_child(btn_close)

func _render_games_list() -> void:
	for child in games_container.get_children():
		games_container.remove_child(child)
		child.queue_free()

	var filtered: Array[Dictionary] = []
	for g in all_games:
		if active_filter == "all" or g.get("time_class", "") == active_filter:
			filtered.append(g)

	if filtered.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune partie ne correspond à ce filtre."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		games_container.add_child(empty_lbl)
		return

	for g in filtered:
		_add_game_card(g)

func _add_game_card(game_data: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true

	var card_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 6))
	panel.add_theme_stylebox_override("panel", card_style)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# --- 1. Badge Résultat à gauche ---
	var res_col = VBoxContainer.new()
	res_col.custom_minimum_size = Vector2(56, 0)
	res_col.alignment = BoxContainer.ALIGNMENT_CENTER
	res_col.add_theme_constant_override("separation", 2)
	row.add_child(res_col)

	var user_res = game_data.get("user_result", "draw")
	var res_icon_lbl = Label.new()
	res_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_icon_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)

	match user_res:
		"win":
			res_icon_lbl.text = "🏆 Gagné"
			res_icon_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		"loss":
			res_icon_lbl.text = "💀 Perdu"
			res_icon_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		_:
			res_icon_lbl.text = "🤝 Nulle"
			res_icon_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	res_col.add_child(res_icon_lbl)

	var score_lbl = Label.new()
	score_lbl.text = game_data.get("score", "½-½")
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	score_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	res_col.add_child(score_lbl)

	# --- 2. Infos Joueurs & Détails au centre ---
	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var is_user_white = game_data.get("is_user_white", false)
	var is_user_black = game_data.get("is_user_black", false)

	# Ligne 1 : Blancs
	var w_lbl = Label.new()
	w_lbl.text = "⚪ %s (%d)" % [game_data.get("white_user", "Inconnu"), game_data.get("white_rating", 0)]
	w_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	w_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	if is_user_white:
		w_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	else:
		w_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	text_col.add_child(w_lbl)

	# Ligne 2 : Noirs
	var b_lbl = Label.new()
	b_lbl.text = "⚫ %s (%d)" % [game_data.get("black_user", "Inconnu"), game_data.get("black_rating", 0)]
	b_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	if is_user_black:
		b_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	else:
		b_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	text_col.add_child(b_lbl)

	# Ligne 3 : Cadence, Terminaison & Date
	var meta_row = HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_theme_constant_override("separation", 6)
	text_col.add_child(meta_row)

	var meta_lbl = Label.new()
	var cadence_str = _format_cadence(game_data.get("time_class", ""), game_data.get("time_control", ""))
	var term_str = game_data.get("termination_reason", "")
	var date_str = _format_timestamp(game_data.get("end_time", 0))

	var parts_meta: Array[String] = [cadence_str]
	if term_str != "":
		parts_meta.append(term_str)
	if date_str != "":
		parts_meta.append(date_str)

	meta_lbl.text = " • ".join(parts_meta)
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	meta_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	meta_row.add_child(meta_lbl)

	# --- 3. Bouton Analyser à droite ---
	var btn_analyze = Button.new()
	btn_analyze.text = "▶ Analyser"
	btn_analyze.tooltip_text = "Charger cette partie sur l'échiquier et ouvrir l'analyse"
	btn_analyze.custom_minimum_size = Vector2(84, DesignTokens.TOUCH_DENSE)
	btn_analyze.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn_analyze.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var captured_game = game_data
	btn_analyze.pressed.connect(func():
		_select_game(captured_game)
	)
	row.add_child(btn_analyze)

	# Taper n'importe où sur la carte permet aussi de sélectionner la partie
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_select_game(captured_game)
	)

	games_container.add_child(panel)

func _select_game(game_data: Dictionary) -> void:
	var pgn = game_data.get("pgn", "")
	if pgn == "":
		return
	var gid = game_data.get("game_id", "")
	var tree = Engine.get_main_loop() as SceneTree
	var gc = tree.root.get_node_or_null("GameController") if (tree and tree.root) else null
	if gc:
		gc.load_pgn(pgn, gid)
	game_selected.emit(pgn)
	queue_free()

func _format_timestamp(unix_sec: int) -> String:
	if unix_sec <= 0:
		return ""
	var dt = Time.get_datetime_dict_from_unix_time(unix_sec)
	return "%02d/%02d/%02d" % [dt.day, dt.month, dt.year % 100]

func _format_cadence(time_class: String, time_control: String) -> String:
	var prefix = "♟️"
	match time_class:
		"blitz": prefix = "⚡"
		"rapid": prefix = "⏱️"
		"bullet": prefix = "🚅"
		"daily": prefix = "📅"
	
	if time_control != "":
		var parts = time_control.split("+")
		if parts.size() > 0 and parts[0].is_valid_int():
			var secs = int(parts[0])
			var mins = secs / 60
			var inc = parts[1] if parts.size() > 1 else ""
			if inc != "" and inc != "0":
				return "%s %d+%s" % [prefix, mins, inc]
			elif mins > 0:
				return "%s %d min" % [prefix, mins]
			elif secs > 0:
				return "%s %ds" % [prefix, secs]
		return "%s %s" % [prefix, time_control]
	return "%s %s" % [prefix, time_class.capitalize()]
