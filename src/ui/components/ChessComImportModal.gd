class_name ChessComImportModal
extends Window
## ChessComImportModal.gd - Modale de récupération et sélection des parties d'un joueur Chess.com

signal game_selected(pgn: String)

const ChessComService = preload("res://src/network/ChessComService.gd")

var chess_com_service: ChessComService
var username_input: LineEdit
var status_lbl: Label
var games_container: VBoxContainer
var all_games: Array[Dictionary] = []
var active_filter: String = "all"

func _ready() -> void:
	title = "Importer depuis Chess.com"
	size = Vector2i(410, 640)
	exclusive = true
	close_requested.connect(queue_free)

	chess_com_service = ChessComService.new()
	add_child(chess_com_service)
	chess_com_service.games_fetched.connect(_on_games_fetched)
	chess_com_service.fetch_error.connect(_on_fetch_error)

	_setup_ui()

func _setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# 1. En-tête & Saisie du pseudo
	var input_row = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	username_input = LineEdit.new()
	username_input.placeholder_text = "Pseudo Chess.com (ex: hikaru, magnuscarlsen)..."
	username_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	username_input.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	username_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	username_input.text = SettingsManager.get_setting("last_chesscom_user", "")
	username_input.text_submitted.connect(func(_t): _start_fetch())
	input_row.add_child(username_input)

	var btn_fetch = Button.new()
	btn_fetch.text = "🔍 Récupérer"
	DesignTokens.style_button(btn_fetch)
	btn_fetch.pressed.connect(_start_fetch)
	input_row.add_child(btn_fetch)

	# 2. Label de statut
	status_lbl = Label.new()
	status_lbl.text = "Entrez un pseudo pour charger les dernières parties officielles."
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

	# 4. Liste déroulante des parties
	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	games_container = VBoxContainer.new()
	games_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_container.add_theme_constant_override("separation", 8)
	scroll.add_child(games_container)

	# Bouton Fermer
	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _add_filter_btn(parent: Node, label_text: String, filter_key: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	btn.pressed.connect(func():
		active_filter = filter_key
		_render_games_list()
	)
	parent.add_child(btn)

func _start_fetch() -> void:
	var user = username_input.text.strip_edges()
	if user == "":
		status_lbl.text = "Veuillez entrer un pseudo."
		status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		return

	SettingsManager.set_setting("last_chesscom_user", user)
	status_lbl.text = "⏳ Connexion à Chess.com et récupération des parties de %s..." % user
	status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	
	for child in games_container.get_children():
		child.queue_free()

	chess_com_service.fetch_player_games(user, 40)

func _on_games_fetched(games: Array[Dictionary]) -> void:
	all_games = games
	status_lbl.text = "✅ %d parties récupérées pour %s." % [games.size(), username_input.text]
	status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)

	# Sauvegarde automatique dans la bibliothèque locale DatabaseManager
	var tree = Engine.get_main_loop() as SceneTree
	var dm = tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null
	if dm:
		for g in games:
			dm.record_chesscom_game(g)

	_render_games_list()

func _on_fetch_error(msg: String, diag: Dictionary = {}) -> void:
	status_lbl.text = "❌ " + msg
	status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
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

	# Voile sombre semi-transparent
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.06, 0.09, 0.88)
	overlay.add_child(backdrop)

	# Conteneur centré
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var card_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM, DesignTokens.BORDER, 2, Vector2(16, 16))
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 10)
	card.add_child(content_vbox)

	# 1. En-tête : Titre
	var header_box = VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	content_vbox.add_child(header_box)

	var title_lbl = Label.new()
	title_lbl.text = "🚨 " + str(diag.get("title", "Diagnostic Réseau"))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
	header_box.add_child(title_lbl)

	# 2. Badges techniques (Pills)
	var badge_row = HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 6)
	content_vbox.add_child(badge_row)

	var code_val = int(diag.get("response_code", 0))
	var pill_http = Label.new()
	pill_http.text = " HTTP %d " % code_val
	pill_http.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var pill_style1 = DesignTokens.flat(DesignTokens.ERROR_BG if code_val == 0 or code_val >= 400 else DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL)
	pill_http.add_theme_stylebox_override("normal", pill_style1)
	pill_http.add_theme_color_override("font_color", DesignTokens.ERROR_TEXT if code_val == 0 or code_val >= 400 else DesignTokens.TEXT_PRIMARY)
	badge_row.add_child(pill_http)

	var pill_res = Label.new()
	pill_res.text = " %s (%d) " % [diag.get("result_name", "UNKNOWN"), diag.get("result_code", -1)]
	pill_res.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var pill_style2 = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL, DesignTokens.BORDER, 1)
	pill_res.add_theme_stylebox_override("normal", pill_style2)
	pill_res.add_theme_color_override("font_color", DesignTokens.ACCENT)
	badge_row.add_child(pill_res)

	var pill_os = Label.new()
	pill_os.text = " %s " % ("Android" if diag.get("is_android", false) else str(diag.get("os_name", "OS")))
	pill_os.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	var pill_style3 = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL)
	pill_os.add_theme_stylebox_override("normal", pill_style3)
	pill_os.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	badge_row.add_child(pill_os)

	# 3. Zone déroulante pour le détail
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
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

	var sep = HSeparator.new()
	text_vbox.add_child(sep)

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

	# 4. Boutons d'action : Copier le rapport et Fermer (SANS minuterie)
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
		child.queue_free()

	var filtered = []
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
	var style = DesignTokens.card()
	panel.add_theme_stylebox_override("panel", style)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	# Info joueurs & détails (colonne gauche fluide)
	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var players_lbl = Label.new()
	players_lbl.text = "⚪ %s (%d)  vs  ⚫ %s (%d)" % [
		game_data["white_user"], game_data["white_rating"],
		game_data["black_user"], game_data["black_rating"]
	]
	players_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	players_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	players_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	players_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	text_col.add_child(players_lbl)

	var details_row = HBoxContainer.new()
	details_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_row.add_theme_constant_override("separation", 8)
	text_col.add_child(details_row)

	var details_lbl = Label.new()
	var cadence = game_data.get("time_class", "").capitalize()
	var tc = game_data.get("time_control", "")
	details_lbl.text = "%s (%s)" % [cadence, tc]
	details_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	details_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	details_row.add_child(details_lbl)

	# Badge Résultat
	var badge_res = Label.new()
	var res = game_data.get("user_result", "draw")
	match res:
		"win":
			badge_res.text = "• Victoire"
			badge_res.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		"loss":
			badge_res.text = "• Défaite"
			badge_res.add_theme_color_override("font_color", DesignTokens.DANGER)
		_:
			badge_res.text = "• Nulle"
			badge_res.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	badge_res.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	details_row.add_child(badge_res)

	# Bouton Analyser (colonne droite fixe, toujours visible)
	var btn_analyze = Button.new()
	btn_analyze.text = "Analyser"
	btn_analyze.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_analyze.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var pgn = game_data.get("pgn", "")
	btn_analyze.pressed.connect(func():
		GameController.load_pgn(pgn)
		game_selected.emit(pgn)
		queue_free()
	)
	row.add_child(btn_analyze)

	games_container.add_child(panel)
