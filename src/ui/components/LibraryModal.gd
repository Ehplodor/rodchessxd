class_name LibraryModal
extends Window
## LibraryModal.gd - Fenêtre modale de consultation et gestion de la bibliothèque locale
## Permet de rechercher, filtrer, charger et exporter les parties et analyses archivées

signal game_selected(game_id: String)

var search_input: LineEdit
var active_filter: String = "all"
var games_container: VBoxContainer
var status_lbl: Label

func _ready() -> void:
	title = "📚 Bibliothèque des Parties & Analyses"
	DesignTokens.adapt_modal_size(self, 410, 560)
	exclusive = true
	close_requested.connect(queue_free)
	_setup_ui()
	_refresh_games_list()

func _setup_ui() -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = DesignTokens.BG_DEEP
	panel.add_theme_stylebox_override("panel", bg_style)
	add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 10
	vbox.offset_top = 10
	vbox.offset_right = -10
	vbox.offset_bottom = -10
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# 1. Barre de recherche
	var search_row = HBoxContainer.new()
	search_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_theme_constant_override("separation", 6)
	vbox.add_child(search_row)

	search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Rechercher (joueur, tournoi, date)..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	search_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	search_input.text_changed.connect(func(_t): _refresh_games_list())
	search_row.add_child(search_input)

	var btn_clear = Button.new()
	btn_clear.text = "✖"
	btn_clear.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_MIN)
	btn_clear.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_clear.pressed.connect(func():
		search_input.clear()
		_refresh_games_list()
	)
	search_row.add_child(btn_clear)

	# 2. Puces de filtres
	var filters_row = HBoxContainer.new()
	filters_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters_row.add_theme_constant_override("separation", 6)
	vbox.add_child(filters_row)

	_add_filter_btn(filters_row, "Toutes", "all")
	_add_filter_btn(filters_row, "Chess.com", "chess_com")
	_add_filter_btn(filters_row, "PGN", "pgn_import")
	_add_filter_btn(filters_row, "⚡ Analysées", "analyzed")

	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(status_lbl)

	# 3. Liste des parties avec défilement
	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	games_container = VBoxContainer.new()
	games_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_container.add_theme_constant_override("separation", 8)
	scroll.add_child(games_container)

	# 4. Pied de page
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
		_refresh_games_list()
	)
	parent.add_child(btn)

func _refresh_games_list() -> void:
	for child in games_container.get_children():
		child.queue_free()

	var tree = Engine.get_main_loop() as SceneTree
	var dm = tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null
	if not dm:
		status_lbl.text = "Base de données non initialisée."
		return

	var q = search_input.text.strip_edges()
	var all_items = dm.list_games(q)

	var filtered: Array[Dictionary] = []
	for it in all_items:
		if active_filter == "all":
			filtered.append(it)
		elif active_filter == "analyzed":
			if it.get("engine_analyses_count", 0) > 0 or it.get("coach_analyses_count", 0) > 0:
				filtered.append(it)
		elif it.get("source", "") == active_filter:
			filtered.append(it)

	status_lbl.text = "%d partie(s) archivée(s) trouvée(s)" % filtered.size()

	if filtered.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Aucune partie ne correspond aux critères de recherche.\nImportez des PGN ou vos parties Chess.com pour les retrouver ici !"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		games_container.add_child(empty_lbl)
		return

	for item in filtered:
		_create_game_card(item)

func _create_game_card(item: Dictionary) -> void:
	var card = PanelContainer.new()
	var style = DesignTokens.card()
	card.add_theme_stylebox_override("panel", style)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	# Colonne détails
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var title_lbl = Label.new()
	var w = item.get("white_name", "Blancs")
	var b = item.get("black_name", "Noirs")
	var w_elo = item.get("white_elo", 0)
	var b_elo = item.get("black_elo", 0)
	var w_str = "%s (%d)" % [w, w_elo] if w_elo > 0 else w
	var b_str = "%s (%d)" % [b, b_elo] if b_elo > 0 else b
	title_lbl.text = "⚪ %s  vs  ⚫ %s" % [w_str, b_str]
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	col.add_child(title_lbl)

	var meta_lbl = Label.new()
	var date_val = item.get("date", "")
	var res = item.get("result", "*")
	var moves_cnt = item.get("moves_count", 0)
	meta_lbl.text = "%s • %s coups • Résultat: %s" % [date_val, str(moves_cnt / 2), res]
	meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	meta_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	col.add_child(meta_lbl)

	# Badges d'analyses (empilés : deux badges à 15 px ne tiennent pas côte à côte
	# dans la colonne de 262 px — ils passeraient sous les boutons d'action)
	var badges_row = VBoxContainer.new()
	badges_row.add_theme_constant_override("separation", 2)
	col.add_child(badges_row)

	var eng_cnt = item.get("engine_analyses_count", 0)
	if eng_cnt > 0:
		var b_eng = Label.new()
		b_eng.text = "⚡ %d analyse(s) Stockfish" % eng_cnt
		b_eng.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b_eng.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		badges_row.add_child(b_eng)

	var coach_cnt = item.get("coach_analyses_count", 0)
	if coach_cnt > 0:
		var b_coach = Label.new()
		b_coach.text = "🤖 %d note(s) Coach" % coach_cnt
		b_coach.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		b_coach.add_theme_color_override("font_color", DesignTokens.WARNING)
		badges_row.add_child(b_coach)

	# Colonne actions
	var act_col = VBoxContainer.new()
	act_col.alignment = BoxContainer.ALIGNMENT_CENTER
	act_col.add_theme_constant_override("separation", 4)
	row.add_child(act_col)

	var btn_load = Button.new()
	btn_load.text = "🚀 Charger"
	btn_load.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_load.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var gid = item.get("id", "")
	btn_load.pressed.connect(func(): _load_game(gid))
	act_col.add_child(btn_load)

	var btn_del = Button.new()
	btn_del.text = "🗑️"
	btn_del.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_MIN)
	btn_del.tooltip_text = "Supprimer définitivement cette partie et ses analyses"
	btn_del.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_del.pressed.connect(func():
		var tree = Engine.get_main_loop() as SceneTree
		var dm = tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null
		if dm:
			dm.delete_game(gid)
			_refresh_games_list()
	)
	act_col.add_child(btn_del)

	games_container.add_child(card)

func _load_game(game_id: String) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var dm = tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null
	if not dm:
		return

	var game_record = dm.get_game(game_id)
	if game_record.is_empty():
		return

	var pgn = game_record.get("pgn_text", "")
	if pgn != "":
		var gc = tree.root.get_node_or_null("GameController") if (tree and tree.root) else null
		if gc:
			gc.load_pgn(pgn, game_id)
	
	# Si la partie possède des analyses moteur, charger la plus récente dans l'interface
	var engine_analyses = game_record.get("engine_analyses", [])
	var main = find_parent("Main")
	if not main:
		# Chercher dans l'arborescence racine
		if tree and tree.root:
			main = tree.root.get_node_or_null("Main")

	if main and engine_analyses.size() > 0:
		var last_ea = engine_analyses[engine_analyses.size() - 1]
		var evals = last_ea.get("evaluations", [])
		if main.advantage_graph:
			main.advantage_graph.set_evaluations(evals)
			main.advantage_graph.update_stored_analyses(engine_analyses)
		if main and main.has_method("close_overlays"):
			main.close_overlays()

	game_selected.emit(game_id)
	queue_free()
