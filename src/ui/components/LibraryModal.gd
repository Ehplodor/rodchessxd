class_name LibraryModal
extends Window
## LibraryModal.gd - Fenêtre modale de consultation et gestion de la bibliothèque locale
## Permet de rechercher, filtrer (filtres cumulables), charger, exporter et
## supprimer en lot les parties analysées archivées.

signal game_selected(game_id: String)

const SOURCE_LABELS := {
	"chess_com": "Chess.com",
	"pgn_import": "PGN",
	"manual_play": "Jeu libre",
	"fen_import": "FEN",
	"ocr_scan": "Scan OCR"
}

const MOVES_ALL := 0
const MOVES_LESS := 1
const MOVES_MORE := 2
const MOVES_BETWEEN := 3

var search_input: LineEdit
var games_container: VBoxContainer
var status_lbl: Label
var btn_delete_visible: Button

# Filtres cumulables
var selected_sources: Array[String] = []
var analyzed_only: bool = false
var moves_op: int = MOVES_ALL

var moves_option: OptionButton
var moves_a: SpinBox
var moves_b: SpinBox
var moves_sep: Label

var _chip_all: Button
var _chip_analyzed: Button
var _source_chips: Dictionary = {}
var _visible_ids: Array[String] = []

func _ready() -> void:
	title = "📚 Bibliothèque des Parties & Analyses"
	DesignTokens.adapt_modal_size(self, 410, 640)
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

	# 2. Filtres de source / analyse (cumulables, retour à la ligne automatique)
	var chips = HFlowContainer.new()
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	vbox.add_child(chips)

	_chip_all = _make_chip("Toutes")
	_chip_all.pressed.connect(func():
		selected_sources.clear()
		analyzed_only = false
		_update_chip_styles()
		_refresh_games_list()
	)
	chips.add_child(_chip_all)

	for raw_key in SOURCE_LABELS.keys():
		var key: String = str(raw_key)
		var chip := _make_chip(str(SOURCE_LABELS[key]))
		chip.pressed.connect(func(): _toggle_source(key))
		_source_chips[key] = chip
		chips.add_child(chip)

	_chip_analyzed = _make_chip("⚡ Analysées")
	_chip_analyzed.pressed.connect(func():
		analyzed_only = not analyzed_only
		_update_chip_styles()
		_refresh_games_list()
	)
	chips.add_child(_chip_analyzed)

	# 3. Filtre sur le nombre de coups
	var moves_row = HBoxContainer.new()
	moves_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_row.add_theme_constant_override("separation", 6)
	vbox.add_child(moves_row)

	var moves_lbl = Label.new()
	moves_lbl.text = "Coups"
	moves_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	moves_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	moves_row.add_child(moves_lbl)

	moves_option = OptionButton.new()
	moves_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	moves_option.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	moves_option.fit_to_longest_item = false
	moves_option.clip_text = true
	moves_option.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	moves_option.add_item("tous")
	moves_option.add_item("moins de")
	moves_option.add_item("plus de")
	moves_option.add_item("entre")
	moves_option.item_selected.connect(func(idx):
		moves_op = idx
		_update_moves_visibility()
		_refresh_games_list()
	)
	moves_row.add_child(moves_option)

	moves_a = _make_move_spin()
	moves_a.value_changed.connect(func(_v): _refresh_games_list())
	moves_row.add_child(moves_a)

	moves_sep = Label.new()
	moves_sep.text = "à"
	moves_sep.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	moves_sep.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	moves_row.add_child(moves_sep)

	moves_b = _make_move_spin()
	moves_b.value = 40
	moves_b.value_changed.connect(func(_v): _refresh_games_list())
	moves_row.add_child(moves_b)

	moves_lbl.tooltip_text = "Nombre de coups joués (une valeur de 999 vaut « illimité »)"
	_update_moves_visibility()

	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(status_lbl)

	# 4. Liste des parties avec défilement
	var scroll = ScrollContainer.new()
	DesignTokens.touch_scroll(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	games_container = VBoxContainer.new()
	games_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_container.add_theme_constant_override("separation", 8)
	scroll.add_child(games_container)

	# 5. Pied de page : suppression groupée + fermeture
	var footer = HBoxContainer.new()
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_theme_constant_override("separation", 8)
	vbox.add_child(footer)

	btn_delete_visible = Button.new()
	btn_delete_visible.text = "🗑️ Supprimer"
	btn_delete_visible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_delete_visible.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_delete_visible.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_delete_visible.add_theme_color_override("font_color", DesignTokens.DANGER)
	btn_delete_visible.add_theme_stylebox_override("normal",
			DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					DesignTokens.DANGER, 1, Vector2(10, 6)))
	btn_delete_visible.pressed.connect(_on_delete_visible_pressed)
	footer.add_child(btn_delete_visible)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_close.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_close.pressed.connect(queue_free)
	footer.add_child(btn_close)

	_update_chip_styles()

func _make_chip(label_text: String) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	return btn

func _make_move_spin() -> SpinBox:
	var spin = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 999
	spin.step = 1
	spin.custom_minimum_size = Vector2(80, DesignTokens.TOUCH_DENSE)
	spin.suffix = ""
	spin.allow_greater = false
	return spin

func _update_moves_visibility() -> void:
	moves_a.visible = moves_op != MOVES_ALL
	moves_sep.visible = moves_op == MOVES_BETWEEN
	moves_b.visible = moves_op == MOVES_BETWEEN

func _toggle_source(key: String) -> void:
	if selected_sources.has(key):
		selected_sources.erase(key)
	else:
		selected_sources.append(key)
	_update_chip_styles()
	_refresh_games_list()

func _update_chip_styles() -> void:
	var none_selected := selected_sources.is_empty() and not analyzed_only
	_style_chip(_chip_all, none_selected)
	for key in _source_chips.keys():
		_style_chip(_source_chips[key], selected_sources.has(key))
	_style_chip(_chip_analyzed, analyzed_only)

func _style_chip(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
		btn.add_theme_stylebox_override("normal",
				DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
						DesignTokens.ACCENT, 1, Vector2(10, 4)))
	else:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		btn.add_theme_stylebox_override("normal",
				DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
						DesignTokens.BORDER, 1, Vector2(10, 4)))

func _get_db() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("DatabaseManager") if (tree and tree.root) else null

func _passes_filters(item: Dictionary) -> bool:
	if analyzed_only:
		var eng = int(item.get("engine_analyses_count", 0))
		var coach = int(item.get("coach_analyses_count", 0))
		if eng <= 0 and coach <= 0:
			return false
	if not selected_sources.is_empty():
		if not selected_sources.has(str(item.get("source", ""))):
			return false

	var moves := int(item.get("moves_count", 0)) / 2
	match moves_op:
		MOVES_LESS:
			if moves >= int(moves_a.value):
				return false
		MOVES_MORE:
			if moves <= int(moves_a.value):
				return false
		MOVES_BETWEEN:
			if moves < int(moves_a.value) or moves > int(moves_b.value):
				return false
	return true

func _has_active_filters() -> bool:
	if selected_sources.size() > 0 or analyzed_only:
		return true
	if moves_op != MOVES_ALL:
		return true
	return search_input != null and search_input.text.strip_edges() != ""

func _refresh_games_list() -> void:
	for child in games_container.get_children():
		child.queue_free()

	var dm = _get_db()
	if not dm:
		status_lbl.text = "Base de données non initialisée."
		_visible_ids.clear()
		_update_delete_button()
		return

	var q = search_input.text.strip_edges()
	var all_items = dm.list_games(q)

	var filtered: Array[Dictionary] = []
	for it in all_items:
		if _passes_filters(it):
			filtered.append(it)

	_visible_ids.clear()
	for item in filtered:
		_visible_ids.append(str(item.get("id", "")))

	var total_cnt: int = all_items.size()
	if _has_active_filters():
		status_lbl.text = "%d partie(s) affichée(s) sur %d — %s" % [
			filtered.size(), total_cnt, _describe_filters()
		]
	else:
		status_lbl.text = "%d partie(s) archivée(s) au total" % total_cnt
	_update_delete_button()

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

func _update_delete_button() -> void:
	if btn_delete_visible == null:
		return
	var count := _visible_ids.size()
	btn_delete_visible.disabled = count == 0
	var prefix := "tout " if not _has_active_filters() else ""
	btn_delete_visible.text = "🗑️ Supprimer %s(%d)" % [prefix, count]

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
	btn_del.pressed.connect(func(): _confirm_delete_single(gid))
	act_col.add_child(btn_del)

	games_container.add_child(card)

# --- SUPPRESSION ---

func _confirm_delete_single(game_id: String) -> void:
	var dm = _get_db()
	if not dm:
		return
	var item: Dictionary = dm.get_game(game_id)
	var title := str(item.get("title", "cette partie"))
	var dialog := ConfirmationDialog.new()
	dialog.title = "Supprimer la partie"
	dialog.dialog_text = "⚠️ Supprimer définitivement « %s » ?\n\nSes analyses moteur/coach et ses traces dans les carnets seront également effacées." % title
	dialog.ok_button_text = "🗑️ Supprimer"
	dialog.cancel_button_text = "Annuler"
	dialog.confirmed.connect(func():
		dm.delete_game(game_id)
		_refresh_games_list()
	)
	add_child(dialog)
	DesignTokens.adapt_dialog(dialog)
	dialog.popup_centered()

func _on_delete_visible_pressed() -> void:
	if _visible_ids.is_empty():
		return
	var ids := _visible_ids.duplicate()
	var count := ids.size()
	var criteria := _describe_filters()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Supprimer des parties"
	dialog.dialog_text = "⚠️ Supprimer %d partie(s) ?\n\nCritères d'affichage :\n%s\n\nLa suppression est définitive : les parties, leurs analyses moteur et coach ainsi que leurs traces dans les carnets seront effacées." % [count, criteria]
	dialog.ok_button_text = "🗑️ Supprimer (%d)" % count
	dialog.cancel_button_text = "Annuler"
	dialog.confirmed.connect(func():
		var dm = _get_db()
		if not dm:
			return
		var removed := 0
		if dm.has_method("delete_games"):
			removed = dm.delete_games(ids)
		else:
			for gid in ids:
				dm.delete_game(gid)
				removed += 1
		_refresh_games_list()
		_toast("🗑️ %d partie(s) supprimée(s)." % removed)
	)
	add_child(dialog)
	DesignTokens.adapt_dialog(dialog)
	dialog.popup_centered()

func _toast(msg: String) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return
	var main = tree.root.get_node_or_null("Main")
	if main and main.has_method("_show_toast"):
		main._show_toast(msg)

# --- DESCRIPTION EN LANGAGE NATUREL DES FILTRES ---

func _source_label(key: String) -> String:
	return str(SOURCE_LABELS.get(key, key))

func _join_natural(items: Array, conjunction: String) -> String:
	if items.is_empty():
		return ""
	if items.size() == 1:
		return str(items[0])
	var head := PackedStringArray()
	for i in range(items.size() - 1):
		head.append(str(items[i]))
	return "%s %s %s" % [", ".join(head), conjunction, str(items[items.size() - 1])]

func _describe_moves() -> String:
	match moves_op:
		MOVES_LESS:
			return "de moins de %d coups" % int(moves_a.value)
		MOVES_MORE:
			return "de plus de %d coups" % int(moves_a.value)
		MOVES_BETWEEN:
			return "de %d à %d coups" % [int(moves_a.value), int(moves_b.value)]
	return ""

func _describe_filters() -> String:
	var parts: Array[String] = []
	if not selected_sources.is_empty():
		var names: Array[String] = []
		for s in selected_sources:
			names.append(_source_label(s))
		parts.append("issues de %s" % _join_natural(names, "ou"))
	if analyzed_only:
		parts.append("déjà analysées")
	var q := search_input.text.strip_edges() if search_input != null else ""
	if q != "":
		parts.append("contenant « %s »" % q)
	var mv := _describe_moves()
	if mv != "":
		parts.append(mv)
	if parts.is_empty():
		return "TOUTES les parties de la bibliothèque"
	return "les parties " + _join_natural(parts, "et")

func _load_game(game_id: String) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	var dm = _get_db()
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
		var gc = tree.root.get_node_or_null("GameController") if (tree and tree.root) else null
		if gc:
			gc.apply_evaluations(evals)
		if main.advantage_graph:
			main.advantage_graph.set_evaluations(evals)
			main.advantage_graph.update_stored_analyses(engine_analyses)
		if main.move_list:
			main.move_list.set_analysis_report(last_ea)
			main.move_list.refresh()
		if main.game_review_panel:
			main.game_review_panel.set_report(last_ea)
		if main.has_method("_update_graph_phase_boundaries"):
			main._update_graph_phase_boundaries(last_ea)
		if main and main.has_method("close_overlays"):
			main.close_overlays()

	game_selected.emit(game_id)
	hide()
	queue_free()
