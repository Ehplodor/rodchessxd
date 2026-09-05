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
	username_input.text = SettingsManager.get_setting("last_chesscom_user", "")
	username_input.text_submitted.connect(func(_t): _start_fetch())
	input_row.add_child(username_input)

	var btn_fetch = Button.new()
	btn_fetch.text = "🔍 Récupérer"
	btn_fetch.pressed.connect(_start_fetch)
	input_row.add_child(btn_fetch)

	# 2. Label de statut
	status_lbl = Label.new()
	status_lbl.text = "Entrez un pseudo pour charger les dernières parties officielles."
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	vbox.add_child(status_lbl)

	# 3. Filtres de cadence (Blitz, Rapide, Bullet, etc.)
	var filters_row = HBoxContainer.new()
	filters_row.add_theme_constant_override("separation", 6)
	vbox.add_child(filters_row)

	_add_filter_btn(filters_row, "Toutes", "all")
	_add_filter_btn(filters_row, "⚡ Blitz", "blitz")
	_add_filter_btn(filters_row, "⏱️ Rapide", "rapid")
	_add_filter_btn(filters_row, "🚅 Bullet", "bullet")
	_add_filter_btn(filters_row, "♟️ Quotidien", "daily")

	# 4. Liste déroulante des parties
	var scroll = ScrollContainer.new()
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
	btn_close.custom_minimum_size = Vector2(0, 36)
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _add_filter_btn(parent: Node, label_text: String, filter_key: String) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(func():
		active_filter = filter_key
		_render_games_list()
	)
	parent.add_child(btn)

func _start_fetch() -> void:
	var user = username_input.text.strip_edges()
	if user == "":
		status_lbl.text = "Veuillez entrer un pseudo."
		status_lbl.add_theme_color_override("font_color", Color("#ef4444"))
		return

	SettingsManager.set_setting("last_chesscom_user", user)
	status_lbl.text = "⏳ Connexion à Chess.com et récupération des parties de %s..." % user
	status_lbl.add_theme_color_override("font_color", Color("#38bdf8"))
	
	for child in games_container.get_children():
		child.queue_free()

	chess_com_service.fetch_player_games(user, 40)

func _on_games_fetched(games: Array[Dictionary]) -> void:
	all_games = games
	status_lbl.text = "✅ %d parties récupérées pour %s." % [games.size(), username_input.text]
	status_lbl.add_theme_color_override("font_color", Color("#22c55e"))
	_render_games_list()

func _on_fetch_error(msg: String) -> void:
	status_lbl.text = "❌ " + msg
	status_lbl.add_theme_color_override("font_color", Color("#ef4444"))

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
		empty_lbl.add_theme_color_override("font_color", Color("#64748b"))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		games_container.add_child(empty_lbl)
		return

	for g in filtered:
		_add_game_card(g)

func _add_game_card(game_data: Dictionary) -> void:
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#1e293b")
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#334155")
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
	panel.add_child(row)

	# Info joueurs
	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	var players_lbl = Label.new()
	players_lbl.text = "⚪ %s (%d)  vs  ⚫ %s (%d)" % [
		game_data["white_user"], game_data["white_rating"],
		game_data["black_user"], game_data["black_rating"]
	]
	players_lbl.add_theme_font_size_override("font_size", 12)
	players_lbl.add_theme_color_override("font_color", Color("#f8fafc"))
	text_col.add_child(players_lbl)

	var details_lbl = Label.new()
	var cadence = game_data.get("time_class", "").capitalize()
	var tc = game_data.get("time_control", "")
	details_lbl.text = "%s (%s)" % [cadence, tc]
	details_lbl.add_theme_font_size_override("font_size", 10)
	details_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	text_col.add_child(details_lbl)

	# Badge Résultat
	var badge_res = Label.new()
	var res = game_data.get("user_result", "draw")
	match res:
		"win":
			badge_res.text = "Victoire"
			badge_res.add_theme_color_override("font_color", Color("#22c55e"))
		"loss":
			badge_res.text = "Défaite"
			badge_res.add_theme_color_override("font_color", Color("#ef4444"))
		_:
			badge_res.text = "Nulle"
			badge_res.add_theme_color_override("font_color", Color("#94a3b8"))
	badge_res.add_theme_font_size_override("font_size", 11)
	row.add_child(badge_res)

	# Bouton Analyser
	var btn_analyze = Button.new()
	btn_analyze.text = "Analyser"
	btn_analyze.add_theme_font_size_override("font_size", 11)
	var pgn = game_data.get("pgn", "")
	btn_analyze.pressed.connect(func():
		GameController.load_pgn(pgn)
		game_selected.emit(pgn)
		queue_free()
	)
	row.add_child(btn_analyze)

	games_container.add_child(panel)
