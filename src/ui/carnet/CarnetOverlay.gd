class_name CarnetOverlay
extends Control
## CarnetOverlay.gd — Couche T2 : surface plein écran de LeCarnet (portrait 450×800).
##
## En-tête sur deux lignes (règle UI mobile) : navigation + sélecteur de profil, puis
## badge de synchronisation + action. Trois onglets = trois couches fonctionnelles :
##   📓 Carnet (plan + séance) · 📊 Analyse (carnet profond) · ⟳ Sync (profils + lot).
##
## Construit en code (pas de .tscn) : instanciable et testable sans scène. Aucune
## logique de domaine ici : tout passe par `CarnetPresenter`.

signal closed

const CarnetProfileEditorModal = preload("res://src/ui/carnet/components/CarnetProfileEditorModal.gd")
const CarnetImportPgnModal = preload("res://src/ui/carnet/components/CarnetImportPgnModal.gd")
const CarnetGameListItem = preload("res://src/ui/carnet/components/CarnetGameListItem.gd")
const ChessComBulkImportModal = preload("res://src/ui/carnet/components/ChessComBulkImportModal.gd")

const _TAB_CARNET := "carnet"
const _TAB_ANALYSE := "analyse"
const _TAB_SYNC := "sync"

var presenter: CarnetPresenter = null

var _title: Label
var _sync_badge: CarnetSyncBadge
var _profile_row: HBoxContainer
var _tabs_box: HBoxContainer
var _tab_group := ButtonGroup.new()
var _content: VBoxContainer
var _batch_label: Label
var _batch_actions: HBoxContainer
var _current_tab := _TAB_CARNET

# Sync tab state
var _games_list: VBoxContainer = null
var _filter_group: ButtonGroup = null
var _current_filter := "all"
var _profile_context_menu: PopupMenu = null

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Au-dessus de l'échiquier principal (les pièces ont un z_index élevé) et
	# encapsulé pour ne jamais déborder de l'écran.
	z_index = 200
	z_as_relative = false
	clip_contents = true
	_build_shell()
	visible = false

func _build_shell() -> void:
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", DesignTokens.flat(DesignTokens.BG_DEEP))
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", DesignTokens.WINDOW_INSET)
	margin.add_theme_constant_override("margin_right", DesignTokens.WINDOW_INSET)
	margin.add_theme_constant_override("margin_top", DesignTokens.WINDOW_INSET)
	margin.add_theme_constant_override("margin_bottom", DesignTokens.WINDOW_INSET)
	add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	margin.add_child(root_box)

	# Ligne 1 : retour + titre.
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	root_box.add_child(row1)
	var back := Button.new()
	back.text = "◀"
	DesignTokens.style_button(back, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	back.custom_minimum_size.x = float(DesignTokens.TOUCH_MIN)
	back.pressed.connect(func(): closed.emit())
	row1.add_child(back)
	_title = Label.new()
	_title.text = "LeCarnet"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	row1.add_child(_title)

	# Ligne 2 : profils défilables + badge de sync.
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	root_box.add_child(row2)
	var profiles_scroll := ScrollContainer.new()
	profiles_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	profiles_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	profiles_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profiles_scroll.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.touch_scroll(profiles_scroll)
	row2.add_child(profiles_scroll)
	_profile_row = HBoxContainer.new()
	_profile_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	profiles_scroll.add_child(_profile_row)
	_sync_badge = CarnetSyncBadge.new()
	row2.add_child(_sync_badge)

	# Barre d'onglets.
	_tabs_box = HBoxContainer.new()
	_tabs_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	root_box.add_child(_tabs_box)
	for entry in [[_TAB_CARNET, "📓 Carnet"], [_TAB_ANALYSE, "📊 Analyse"], [_TAB_SYNC, "⟳ Sync"]]:
		var btn := Button.new()
		btn.text = entry[1]
		btn.toggle_mode = true
		btn.button_group = _tab_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(btn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn.pressed.connect(_on_tab_pressed.bind(entry[0]))
		_tabs_box.add_child(btn)

	# Contenu défilable.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(scroll)
	root_box.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	scroll.add_child(_content)

func _process(_delta: float) -> void:
	# Le lot doit progresser même si l'overlay est refermé (le présentateur survit).
	if presenter != null and presenter.is_batching():
		presenter.poll_batch()
		_update_batch_row()

# ── API vues ─────────────────────────────────────────────────────────────────────

func open(p: CarnetPresenter) -> void:
	_set_presenter(p)
	p.refresh_profiles()
	p.refresh_sync()
	p.refresh_carnet()
	p.refresh_plan()
	select_tab(_TAB_CARNET)
	visible = true

func close() -> void:
	visible = false
	closed.emit()

func select_tab(tab: String) -> void:
	_current_tab = tab
	_refresh_header()
	_rebuild_content()

func choose(uci: String) -> Dictionary:
	if presenter == null:
		return {}
	var result := presenter.answer(uci)
	_rebuild_content()
	return result

func grade(note: int) -> bool:
	if presenter == null:
		return false
	var ok := presenter.grade(note)
	_rebuild_content()
	return ok

func _reveal() -> void:
	if presenter == null:
		return
	presenter.reveal()
	_rebuild_content()

# ── Câblage présentateur ─────────────────────────────────────────────────────────

func _set_presenter(p: CarnetPresenter) -> void:
	if presenter == p:
		return
	presenter = p
	p.sync_changed.connect(_refresh_header)
	p.carnet_changed.connect(_refresh_header)
	p.plan_changed.connect(_refresh_header)
	p.batch_state.connect(func(_s): _update_batch_row())
	p.batch_progress.connect(func(_d, _t, _g): _update_batch_row())
	p.profile_updated.connect(_on_profile_updated)
	p.game_list_changed.connect(_on_game_list_changed)
	p.toast_requested.connect(_on_toast_requested)

func _refresh_header() -> void:
	if presenter == null:
		return
	_title.text = "LeCarnet · %s" % presenter.active_profile_name()
	_sync_badge.set_status(int(presenter.sync.get("total", 0)),
			(presenter.sync.get("to_process", []) as Array).size())
	_rebuild_profiles()

func _rebuild_profiles() -> void:
	for child in _profile_row.get_children():
		child.queue_free()
	for profile in presenter.profiles:
		if not (profile is Dictionary):
			continue
		var chip := CarnetProfileChip.new()
		chip.set_profile(profile, str(profile.get("id", "")) == presenter.profile_id)
		chip.profile_selected.connect(_on_profile_selected)
		chip.context_menu_requested.connect(_on_profile_context_menu)
		_profile_row.add_child(chip)

	# Bouton "+" pour créer un profil
	var btn_add := Button.new()
	btn_add.text = "+"
	btn_add.tooltip_text = "Créer un nouveau profil"
	btn_add.custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	btn_add.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	DesignTokens.style_button(btn_add, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_add.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_add.pressed.connect(_on_create_profile)
	_profile_row.add_child(btn_add)

func _on_profile_selected(id: String) -> void:
	presenter.select_profile(id)
	presenter.refresh_sync()
	presenter.refresh_carnet()
	presenter.refresh_plan()
	_refresh_header()
	_rebuild_content()

func _on_tab_pressed(tab: String) -> void:
	select_tab(tab)

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _rebuild_content() -> void:
	_clear_content()
	if presenter == null:
		return
	if presenter.session.is_empty():
		if _current_tab == _TAB_CARNET:
			_build_carnet_tab()
		elif _current_tab == _TAB_ANALYSE:
			_build_analyse_tab()
		else:
			_build_sync_tab()
	elif presenter.is_session_done():
		_build_summary()
	else:
		_build_session()

func _build_summary() -> void:
	var summary := presenter.session_summary()
	_content.add_child(_section_title("Séance terminée"))
	_content.add_child(_hint("Réussis : %d / %d · Précision : %d%%" % [
			int(summary.get("correct", 0)), int(summary.get("total", 0)), int(summary.get("accuracy", 0.0))]))
	var done := Button.new()
	done.text = "Terminer"
	DesignTokens.style_button(done, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	done.pressed.connect(func(): presenter.end_session(); _rebuild_content())
	_content.add_child(done)

# ── Onglet 📓 Carnet ─────────────────────────────────────────────────────────────

func _build_carnet_tab() -> void:
	_content.add_child(_section_title("Aujourd'hui"))
	var objective := Label.new()
	objective.text = presenter.plan_objective()
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_content.add_child(objective)

	var drills: Array = presenter.plan.get("drills", [])
	var start := Button.new()
	start.text = "Commencer la séance (%d)" % drills.size()
	start.disabled = drills.is_empty()
	start.clip_text = true
	start.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	DesignTokens.style_button(start, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	start.pressed.connect(func(): _start_session())
	_content.add_child(start)

	var progress := Label.new()
	progress.text = "Indice de progression : %d / 100" % int(presenter.ledger.get("profil", {}).get("indice_progression", 0))
	progress.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	progress.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_content.add_child(progress)

func _start_session() -> void:
	presenter.start_plan_session()
	_rebuild_content()

func _build_session() -> void:
	var drill := presenter.current_drill()
	var total := presenter.session_size()
	var index := presenter.session_index()
	var progress := Label.new()
	progress.text = "Drill %d / %d" % [index + 1, total]
	progress.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	progress.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_content.add_child(progress)

	var type_label := Label.new()
	type_label.text = CarnetPresenter.drill_type_label(str(drill.get("type", "")))
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	type_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_content.add_child(type_label)

	var result: Dictionary = presenter.session.get("last_result", {})
	var options := presenter.drill_options(drill)
	if options.size() < 2:
		var reveal := Button.new()
		reveal.text = "Révéler la solution"
		reveal.disabled = not result.is_empty()
		reveal.clip_text = true
		reveal.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(reveal, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		reveal.pressed.connect(_reveal)
		_content.add_child(reveal)
	for option in options:
		var btn := Button.new()
		btn.text = str(option.get("san", option.get("uci", "")))
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(btn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn.disabled = not result.is_empty()
		btn.pressed.connect(func(): choose(str(option.get("uci", ""))))
		_content.add_child(btn)

	if not result.is_empty():
		var feedback := Label.new()
		if bool(result.get("correct", false)):
			feedback.text = "✅ Bien vu !"
			feedback.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		else:
			feedback.text = "❌ Le meilleur coup était %s." % CarnetPresenter.uci_to_san(
					str(drill.get("position", "")), str(result.get("expected", "")))
			feedback.add_theme_color_override("font_color", DesignTokens.DANGER)
		feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(feedback)
		_content.add_child(_grade_row())

func _grade_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	for note in [1, 3, 4, 5]:
		var btn := Button.new()
		btn.text = CarnetPresenter.grade_label(note)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_MIN)
		btn.pressed.connect(func(): grade(note))
		row.add_child(btn)
	return row

# ── Onglet 📊 Analyse ────────────────────────────────────────────────────────────

func _build_analyse_tab() -> void:
	var added := false
	var radar_dims := _radar_dimensions(presenter.ledger.get("competences", []))
	if not radar_dims.is_empty():
		var radar := CarnetRadarPanel.new()
		radar.set_dimensions(radar_dims)
		_content.add_child(radar)
		added = true
	added = _add_motif_section("Faiblesses", presenter.ledger.get("faiblesses", [])) or added
	added = _add_motif_section("Forces", presenter.ledger.get("forces", [])) or added
	added = _add_motif_section("Curiosités", presenter.ledger.get("curiosites", [])) or added
	added = _add_motif_section("Pistes à confirmer", presenter.ledger.get("emergeants", [])) or added
	if not added:
		_content.add_child(_hint("Pas encore assez de parties analysées pour dessiner ce carnet."))

func _add_motif_section(title: String, motifs: Array) -> bool:
	if motifs.is_empty():
		return false
	_content.add_child(_section_title(title))
	for motif in motifs:
		if not (motif is Dictionary):
			continue
		var card := CarnetMotifCard.new()
		card.set_motif(motif)
		_content.add_child(card)
	return true

static func _radar_dimensions(competences: Array, max_dim: int = 6) -> Array:
	var dims: Array = []
	for c in competences:
		if c is Dictionary and int(c.get("n", 0)) >= 2 and dims.size() < max_dim:
			dims.append({"label": "%s : %s" % [c.get("dimension", ""), c.get("cle", "")], "skill": c.get("skill", 0.0)})
	return dims

# ── Onglet ⟳ Sync ────────────────────────────────────────────────────────────────

func _build_sync_tab() -> void:
	_content.add_child(_section_title("Synchronisation"))
	var summary := Label.new()
	summary.text = presenter.sync_label()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_content.add_child(summary)

	# Boutons d'action : Mettre à jour + Importer PGN + Importer Chess.com
	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	_content.add_child(actions_row)

	var run := Button.new()
	run.text = "Mettre à jour le carnet"
	run.disabled = presenter.sync.get("to_process", []).size() == 0
	run.clip_text = true
	run.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DesignTokens.style_button(run, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	run.pressed.connect(func(): presenter.start_batch(); _update_batch_row())
	actions_row.add_child(run)

	var btn_import_pgn = Button.new()
	btn_import_pgn.text = "📥 Importer PGN"
	btn_import_pgn.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	btn_import_pgn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(btn_import_pgn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_import_pgn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_import_pgn.pressed.connect(_on_import_pgn)
	actions_row.add_child(btn_import_pgn)

	var btn_import_chesscom = Button.new()
	btn_import_chesscom.text = "🌐 Importer Chess.com"
	btn_import_chesscom.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	btn_import_chesscom.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(btn_import_chesscom, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_import_chesscom.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_import_chesscom.pressed.connect(_on_import_chesscom)
	actions_row.add_child(btn_import_chesscom)

	_batch_label = Label.new()
	_batch_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_batch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_batch_label)
	_batch_actions = HBoxContainer.new()
	_batch_actions.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	_content.add_child(_batch_actions)
	_update_batch_row()

	# Filtres pour la liste des parties
	_content.add_child(_section_title("Parties du carnet"))
	var filter_scroll = ScrollContainer.new()
	filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	filter_scroll.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.touch_scroll(filter_scroll)
	_content.add_child(filter_scroll)

	_filter_group = ButtonGroup.new()
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	filter_scroll.add_child(filter_row)

	var filters := [["all", "Toutes"], ["pending", "À traiter"], ["stale", "À jour"], ["up_to_date", "Périmées"]]
	for f in filters:
		var btn := Button.new()
		btn.text = f[1]
		btn.toggle_mode = true
		btn.button_group = _filter_group
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		btn.pressed.connect(_on_filter_pressed.bind(f[0]))
		filter_row.add_child(btn)

	# Liste des parties
	var games_scroll = ScrollContainer.new()
	games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(games_scroll)
	_content.add_child(games_scroll)

	_games_list = VBoxContainer.new()
	_games_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_list.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	games_scroll.add_child(_games_list)

	_refresh_games_list()

func _update_batch_row() -> void:
	if _batch_label == null:
		return
	if presenter == null or presenter.batch == null:
		_batch_label.text = ""
		_clear_node(_batch_actions)
		return
	var batch := presenter.batch
	_batch_label.text = "Traitement : %d / %d (échecs : %d)" % [batch.processed, batch.queue.size(), batch.failed]
	_clear_node(_batch_actions)
	if batch.state == "running":
		_append_batch_action("Pause", func(): presenter.pause_batch())
		_append_batch_action("Annuler", func(): presenter.cancel_batch())
	elif batch.state == "paused":
		_append_batch_action("Reprendre", func(): presenter.resume_batch())
		_append_batch_action("Annuler", func(): presenter.cancel_batch())

func _append_batch_action(label: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DesignTokens.style_button(btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	btn.pressed.connect(func(): action.call(); _update_batch_row())
	_batch_actions.add_child(btn)

# ── Aides de construction ────────────────────────────────────────────────────────

static func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	label.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	return label

static func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	return label

static func _clear_node(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

# ── Nouveaux handlers Sync ─────────────────────────────────────────────────────────

func _on_create_profile() -> void:
	var modal = CarnetProfileEditorModal.new()
	modal.open_create(presenter)
	modal.profile_saved.connect(func(profile_id, is_new):
		presenter.refresh_profiles()
		presenter.refresh_sync()
		modal.queue_free()
	)

func _on_profile_context_menu(profile_id: String, global_pos: Vector2) -> void:
	if _profile_context_menu == null:
		_profile_context_menu = PopupMenu.new()
		add_child(_profile_context_menu)
		_profile_context_menu.id_pressed.connect(_on_profile_context_menu_action)
	_profile_context_menu.clear()
	var profile := CarnetProfiles.get_profile(profile_id)
	var is_default := str(profile.get("id", "")) == CarnetProfiles.DEFAULT_PROFILE_ID
	_profile_context_menu.add_item("Renommer", 0)
	_profile_context_menu.set_item_metadata(0, profile_id)
	_profile_context_menu.add_item("Gérer clés", 1)
	_profile_context_menu.set_item_metadata(1, profile_id)
	if not is_default:
		_profile_context_menu.add_separator()
		_profile_context_menu.add_item("Supprimer", 2)
		_profile_context_menu.set_item_metadata(2, profile_id)
	_profile_context_menu.popup(Rect2i(global_pos, Vector2i(1, 1)))

func _on_profile_context_menu_action(id: int, profile_id: String) -> void:
	match id:
		0: _on_edit_profile(profile_id)
		1: _on_manage_keys(profile_id)
		2: _on_delete_profile(profile_id)

func _on_edit_profile(profile_id: String) -> void:
	var modal = CarnetProfileEditorModal.new()
	modal.open_edit(presenter, profile_id)
	modal.profile_saved.connect(func(pid, is_new):
		presenter.refresh_profiles()
		presenter.refresh_sync()
		modal.queue_free()
	)

func _on_manage_keys(profile_id: String) -> void:
	_on_edit_profile(profile_id)

func _on_delete_profile(profile_id: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Supprimer le profil"
	dialog.text = "Supprimer ce profil et toutes ses données ? Cette action est irréversible."
	dialog.ok_button_text = "Supprimer"
	dialog.add_theme_color_override("font_color", DesignTokens.DANGER)
	dialog.confirmed.connect(func():
		presenter.delete_profile(profile_id)
		dialog.queue_free()
	)
	dialog.popup_centered()

func _on_import_pgn() -> void:
	var modal = CarnetImportPgnModal.new()
	modal.open(presenter, presenter.profile_id)
	modal.import_completed.connect(func(game_id, new_keys):
		presenter.refresh_sync()
		presenter.refresh_carnet()
		presenter.refresh_plan()
		_refresh_games_list()
		modal.queue_free()
	)

func _on_import_chesscom() -> void:
	var modal = ChessComBulkImportModal.new()
	add_child(modal)
	modal.open(presenter)
	modal.import_completed.connect(func(_profile_name, _game_count):
		presenter.refresh_profiles()
		presenter.refresh_sync()
		presenter.refresh_carnet()
		presenter.refresh_plan()
		_refresh_games_list()
		modal.queue_free()
	)

func _on_filter_pressed(filter_id: String) -> void:
	_current_filter = filter_id
	_refresh_games_list()

func _refresh_games_list() -> void:
	if _games_list == null:
		return
	for child in _games_list.get_children():
		child.queue_free()

	var games := presenter.get_profile_games(presenter.profile_id)
	var filtered: Array = []
	for game in games:
		var status := str(game.get("status", "up_to_date"))
		if _current_filter == "all":
			filtered.append(game)
		elif _current_filter == "pending" and status == "pending":
			filtered.append(game)
		elif _current_filter == "stale" and status == "stale":
			filtered.append(game)
		elif _current_filter == "up_to_date" and status == "up_to_date":
			filtered.append(game)

	if filtered.is_empty():
		_games_list.add_child(_hint("Aucune partie pour ce filtre."))
		return

	for game in filtered:
		var item = CarnetGameListItem.new()
		item.set_game(game)
		item.reanalyze_requested.connect(_on_game_reanalyze)
		item.perspective_cycle_requested.connect(_on_game_perspective_cycle)
		item.remove_requested.connect(_on_game_remove)
		_games_list.add_child(item)

func _on_game_reanalyze(game_id: String) -> void:
	presenter.reanalyze_game(game_id, presenter.profile_id)
	_update_batch_row()

func _on_game_perspective_cycle(game_id: String) -> void:
	presenter.cycle_game_perspective(game_id)
	presenter.refresh_sync()
	_refresh_games_list()

func _on_game_remove(game_id: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Retirer la partie du carnet"
	dialog.text = "Cette partie sera retirée du carnet (atomes, drills, sync). La partie reste dans la base globale."
	dialog.ok_button_text = "Retirer"
	dialog.add_theme_color_override("font_color", DesignTokens.DANGER)
	dialog.confirmed.connect(func():
		presenter.remove_game_from_profile(game_id, presenter.profile_id)
		_refresh_games_list()
		dialog.queue_free()
	)
	dialog.popup_centered()

func _on_profile_updated(profile_id: String) -> void:
	_refresh_header()
	_refresh_games_list()

func _on_game_list_changed() -> void:
	_refresh_games_list()

func _on_toast_requested(msg: String, is_success: bool) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("Main"):
		var main = tree.root.get_node("Main")
		if main.has_method("_show_toast"):
			main._show_toast(msg, is_success)
