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
const CarnetBoardWidget = preload("res://src/ui/carnet/components/CarnetBoardWidget.gd")

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
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(scroll)
	root_box.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_games_list = null
	_batch_label = null
	_batch_actions = null

func _rebuild_content() -> void:
	_clear_content()
	if presenter == null:
		return
	if presenter.session.is_empty():
		if _current_tab == _TAB_CARNET:
			print("[Carnet] rebuild: carnet tab")
			_build_carnet_tab()
		elif _current_tab == _TAB_ANALYSE:
			print("[Carnet] rebuild: analyse tab")
			_build_analyse_tab()
		else:
			print("[Carnet] rebuild: sync tab")
			_build_sync_tab()
	elif presenter.is_session_done():
		print("[Carnet] rebuild: summary")
		_build_summary()
	else:
		print("[Carnet] rebuild: session")
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
	var streak := presenter.get_streak_info()

	# 1. Bandeau de synthèse du carnet
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", DesignTokens.card())
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	stats_panel.add_child(stats_box)

	var stats_lbl := Label.new()
	stats_lbl.text = "📊 %d parties · %d moments clés · %d drills" % [
			streak.nb_parties, streak.nb_atomes, streak.nb_drills]
	stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	stats_box.add_child(stats_lbl)

	var streak_lbl := Label.new()
	var serie_val: int = streak.serie
	var joker_val: int = streak.joker
	streak_lbl.text = "🔥 Série : %d jour%s consécutif%s · %d joker%s" % [
			serie_val, "s" if serie_val > 1 else "", "s" if serie_val > 1 else "",
			joker_val, "s" if joker_val > 1 else ""]
	streak_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	streak_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	streak_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	streak_lbl.add_theme_color_override("font_color", DesignTokens.WARNING if serie_val > 0 else DesignTokens.TEXT_MUTED)
	stats_box.add_child(streak_lbl)
	_content.add_child(stats_panel)

	# 2. Programme du jour (LePlan)
	_content.add_child(_section_title("🎯 Séance quotidienne"))
	var plan_panel := PanelContainer.new()
	plan_panel.add_theme_stylebox_override("panel", DesignTokens.card())
	var plan_box := VBoxContainer.new()
	plan_box.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	plan_panel.add_child(plan_box)

	var objective := Label.new()
	objective.text = presenter.plan_objective()
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	plan_box.add_child(objective)

	# Badges des thèmes au programme (disposition flexible HFlow)
	var motifs_summary := presenter.plan_motifs_summary()
	if not motifs_summary.is_empty():
		var badges_flow := HFlowContainer.new()
		badges_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		badges_flow.add_theme_constant_override("h_separation", DesignTokens.SPACE_XS)
		badges_flow.add_theme_constant_override("v_separation", DesignTokens.SPACE_XS)
		for m in motifs_summary:
			var badge := PanelContainer.new()
			var b_style := StyleBoxFlat.new()
			var is_force := str(m.get("polarite", "")) == "positif"
			var col := DesignTokens.SUCCESS if is_force else DesignTokens.WARNING
			b_style.bg_color = Color(col.r, col.g, col.b, 0.20)
			b_style.border_color = col
			b_style.set_border_width_all(1)
			b_style.corner_radius_top_left = 6
			b_style.corner_radius_top_right = 6
			b_style.corner_radius_bottom_left = 6
			b_style.corner_radius_bottom_right = 6
			b_style.content_margin_left = 6
			b_style.content_margin_right = 6
			b_style.content_margin_top = 2
			b_style.content_margin_bottom = 2
			badge.add_theme_stylebox_override("panel", b_style)

			var b_lbl := Label.new()
			var prefix := "✨ " if is_force else "🎯 "
			b_lbl.text = "%s%dx %s" % [prefix, m.get("count", 1), m.get("label", "")]
			b_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			b_lbl.add_theme_color_override("font_color", col)
			badge.add_child(b_lbl)
			badges_flow.add_child(badge)
		plan_box.add_child(badges_flow)

	var drills: Array = presenter.plan.get("drills", [])
	var start := Button.new()
	if drills.is_empty():
		start.text = "Aucun exercice pour aujourd'hui"
		start.disabled = true
	else:
		start.text = "▶ Commencer la séance (%d exercices · ~3 min)" % drills.size()
		start.disabled = false
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.clip_text = true
	start.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	DesignTokens.style_button(start, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	start.add_theme_color_override("font_color", DesignTokens.ACCENT)
	start.pressed.connect(func(): _start_session())
	plan_box.add_child(start)
	_content.add_child(plan_panel)

	# 3. Progression & Maîtrise
	_content.add_child(_section_title("📈 Progression du carnet"))
	var prog_panel := PanelContainer.new()
	prog_panel.add_theme_stylebox_override("panel", DesignTokens.card())
	var prog_box := VBoxContainer.new()
	prog_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	prog_panel.add_child(prog_box)

	var prog_score: int = int(presenter.ledger.get("profil", {}).get("indice_progression", 0))
	var level_name := "Niveau 1 · Découverte"
	if prog_score >= 80:
		level_name = "Niveau 4 · Maîtrise avancée"
	elif prog_score >= 50:
		level_name = "Niveau 3 · Joueur confirmé"
	elif prog_score >= 25:
		level_name = "Niveau 2 · En progression"

	var prog_lbl := Label.new()
	prog_lbl.text = "Score d'apprentissage : %d / 100 (%s)" % [prog_score, level_name]
	prog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prog_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prog_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	prog_box.add_child(prog_lbl)

	var prog_bar := ProgressBar.new()
	prog_bar.max_value = 100.0
	prog_bar.value = float(prog_score)
	prog_bar.show_percentage = false
	prog_bar.custom_minimum_size.y = 8
	var fill := StyleBoxFlat.new()
	fill.bg_color = DesignTokens.ACCENT
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	prog_bar.add_theme_stylebox_override("fill", fill)
	prog_box.add_child(prog_bar)

	var mastery_lbl := Label.new()
	mastery_lbl.text = "⭐ %d exercice(s) maîtrisé(s) en répétition espacée" % streak.maitrise
	mastery_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mastery_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	mastery_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	prog_box.add_child(mastery_lbl)
	_content.add_child(prog_panel)

	# 4. Conseil de jeu basé sur la faiblesse n°1
	var faiblesses: Array = presenter.ledger.get("faiblesses", [])
	if not faiblesses.is_empty() and faiblesses[0] is Dictionary:
		var top_w: Dictionary = faiblesses[0]
		var f_card := PanelContainer.new()
		f_card.add_theme_stylebox_override("panel", DesignTokens.card())
		var f_box := VBoxContainer.new()
		f_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
		f_card.add_child(f_box)

		var f_head := Label.new()
		f_head.text = "💡 Conseil pour vos parties"
		f_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_head.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		f_head.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		f_box.add_child(f_head)

		var f_txt := Label.new()
		f_txt.text = "Point d'attention prioritaire : %s." % top_w.get("libelle", "")
		var f_desc := CarnetLedger.motif_description(str(top_w.get("famille", "")), str(top_w.get("cle", "")))
		if f_desc != "":
			f_txt.text += " %s" % f_desc
		f_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f_txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f_txt.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		f_txt.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		f_box.add_child(f_txt)
		_content.add_child(f_card)

func _start_session() -> void:
	presenter.start_plan_session()
	_rebuild_content()

func _build_session() -> void:
	var drill := presenter.current_drill()
	var total := presenter.session_size()
	var index := presenter.session_index()
	var result: Dictionary = presenter.session.get("last_result", {})
	var ctx := presenter.drill_game_context(drill)

	# 1. En-tête : Progression et Trait
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	_content.add_child(top_row)

	var progress := Label.new()
	progress.text = "Drill %d / %d" % [index + 1, total]
	progress.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.clip_text = true
	progress.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_row.add_child(progress)

	var trait_pill := PanelContainer.new()
	var trait_is_white: bool = str(ctx.get("side", "white")) == "white"
	var trait_style := StyleBoxFlat.new()
	trait_style.bg_color = DesignTokens.SURFACE_ELEVATED
	trait_style.corner_radius_top_left = 12
	trait_style.corner_radius_top_right = 12
	trait_style.corner_radius_bottom_left = 12
	trait_style.corner_radius_bottom_right = 12
	trait_style.content_margin_left = 8
	trait_style.content_margin_right = 8
	trait_style.content_margin_top = 4
	trait_style.content_margin_bottom = 4
	trait_pill.add_theme_stylebox_override("panel", trait_style)
	var trait_lbl := Label.new()
	trait_lbl.text = "⚪ Trait aux Blancs" if trait_is_white else "⚫ Trait aux Noirs"
	trait_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	trait_lbl.clip_text = true
	trait_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	trait_pill.add_child(trait_lbl)
	top_row.add_child(trait_pill)

	# 2. Contexte de la partie
	var context_card := PanelContainer.new()
	context_card.add_theme_stylebox_override("panel", DesignTokens.card())
	var context_box := VBoxContainer.new()
	context_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	context_card.add_child(context_box)

	var origin_lbl := Label.new()
	var opp_str: String = str(ctx.get("opponent", ""))
	var coup_num: int = int(ctx.get("coup_num", 0))
	if opp_str != "":
		origin_lbl.text = "⚔ Partie vs %s · Coup %d" % [opp_str, coup_num]
	else:
		origin_lbl.text = "⚔ Position d'entraînement"
	origin_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	origin_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	origin_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	context_box.add_child(origin_lbl)

	var theme_lbl := Label.new()
	var motif_name := presenter.drill_motif_label(drill)
	theme_lbl.text = "Thème : %s" % motif_name
	theme_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	theme_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	theme_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	context_box.add_child(theme_lbl)

	var last_mv_str: String = str(ctx.get("last_move_san", ""))
	if last_mv_str != "":
		var last_lbl := Label.new()
		last_lbl.text = "Dernier coup joué : %s" % last_mv_str
		last_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		last_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		last_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		last_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		context_box.add_child(last_lbl)

	_content.add_child(context_card)

	# 3. Échiquier 2D autonome centré et responsive
	var board_widget := CarnetBoardWidget.new()
	board_widget.load_position(str(drill.get("position", "")), str(ctx.get("side", "")) == "black", str(ctx.get("last_move_uci", "")))
	if not result.is_empty():
		var exp_uci := str(result.get("expected", ""))
		var played_uci := str(result.get("played", "")) if not bool(result.get("correct", false)) else ""
		board_widget.show_solution(exp_uci, played_uci)
	else:
		board_widget.move_attempted.connect(func(uci): choose(uci))

	var board_center := CenterContainer.new()
	board_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_center.add_child(board_widget)
	_content.add_child(board_center)

	# 4. Question & Options
	var type_label := Label.new()
	type_label.text = CarnetPresenter.drill_type_label(str(drill.get("type", "")))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_content.add_child(type_label)

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
	else:
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
		_content.add_child(btn_row)
		for option in options:
			var btn := Button.new()
			btn.text = CarnetPresenter.uci_to_san_fr(str(drill.get("position", "")), str(option.get("uci", "")))
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			DesignTokens.style_button(btn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
			btn.disabled = not result.is_empty()
			btn.pressed.connect(func(): choose(str(option.get("uci", ""))))
			btn_row.add_child(btn)

	# 5. Feedback post-réponse & Analyse Stockfish
	if not result.is_empty():
		var feedback_card := PanelContainer.new()
		var fb_box := VBoxContainer.new()
		fb_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
		feedback_card.add_child(fb_box)

		var fb_style := StyleBoxFlat.new()
		var is_ok: bool = bool(result.get("correct", false))
		fb_style.bg_color = Color(DesignTokens.SUCCESS.r, DesignTokens.SUCCESS.g, DesignTokens.SUCCESS.b, 0.15) if is_ok else Color(DesignTokens.DANGER.r, DesignTokens.DANGER.g, DesignTokens.DANGER.b, 0.15)
		fb_style.border_color = DesignTokens.SUCCESS if is_ok else DesignTokens.DANGER
		fb_style.set_border_width_all(1)
		fb_style.corner_radius_top_left = 8
		fb_style.corner_radius_top_right = 8
		fb_style.corner_radius_bottom_left = 8
		fb_style.corner_radius_bottom_right = 8
		fb_style.content_margin_left = 10
		fb_style.content_margin_right = 10
		fb_style.content_margin_top = 8
		fb_style.content_margin_bottom = 8
		feedback_card.add_theme_stylebox_override("panel", fb_style)

		var fb_title := Label.new()
		fb_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fb_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb_title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		if is_ok:
			fb_title.text = "✅ Bien vu ! Coup optimal trouvé."
			fb_title.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		else:
			var played_san := CarnetPresenter.uci_to_san_fr(str(drill.get("position", "")), str(result.get("played", "")))
			var exp_san := CarnetPresenter.uci_to_san_fr(str(drill.get("position", "")), str(result.get("expected", "")))
			fb_title.text = "❌ Dans votre partie, vous aviez joué %s. Le meilleur coup était %s." % [played_san, exp_san]
			fb_title.add_theme_color_override("font_color", DesignTokens.DANGER)
		fb_box.add_child(fb_title)
		_content.add_child(feedback_card)

		# Carte d'analyse Stockfish (meilleure suite SAN + explications déroulables débutant)
		var cont_card := _build_continuation_card(drill)
		if cont_card != null:
			_content.add_child(cont_card)

		var fb_hint := Label.new()
		fb_hint.text = "Évaluez votre aisance pour calibrer la prochaine répétition :"
		fb_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fb_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb_hint.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		fb_hint.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		_content.add_child(fb_hint)
		_content.add_child(_grade_row())

func _build_continuation_card(drill: Dictionary) -> Control:
	var cont := presenter.get_drill_continuation(drill)
	if cont.is_empty() or str(cont.get("san_line", "")) == "":
		return null

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", DesignTokens.card())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(vbox)

	# 1. En-tête avec badge moteur
	var header_hbox := HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "♟️ Meilleure suite"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	header_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var engine_lbl := Label.new()
	engine_lbl.text = str(cont.get("engine_label", "Stockfish 18"))
	engine_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	engine_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	header_hbox.add_child(engine_lbl)

	# 2. Ligne SAN standard (pour les joueurs sachant lire la notation échiquéenne)
	var san_panel := PanelContainer.new()
	var san_style := StyleBoxFlat.new()
	san_style.bg_color = Color(DesignTokens.BG_BASE.r, DesignTokens.BG_BASE.g, DesignTokens.BG_BASE.b, 0.7)
	san_style.set_border_width_all(1)
	san_style.border_color = DesignTokens.BORDER
	san_style.corner_radius_top_left = 6
	san_style.corner_radius_top_right = 6
	san_style.corner_radius_bottom_left = 6
	san_style.corner_radius_bottom_right = 6
	san_style.content_margin_left = 8
	san_style.content_margin_right = 8
	san_style.content_margin_top = 6
	san_style.content_margin_bottom = 6
	san_panel.add_theme_stylebox_override("panel", san_style)
	san_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var san_lbl := Label.new()
	san_lbl.text = str(cont.get("san_line", ""))
	san_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	san_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	san_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	san_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	san_panel.add_child(san_lbl)
	vbox.add_child(san_panel)

	# 3. Accordéon pour débutants (déroulable, masqué par défaut pour entraîner la lecture)
	var steps: Array = cont.get("steps", [])
	if not steps.is_empty():
		var toggle_btn := Button.new()
		toggle_btn.text = "▶ 💡 Décoder la suite coup par coup (débutant)"
		toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle_btn.clip_text = true
		toggle_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(toggle_btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		vbox.add_child(toggle_btn)

		var steps_box := VBoxContainer.new()
		steps_box.visible = false
		steps_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps_box.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
		vbox.add_child(steps_box)

		toggle_btn.pressed.connect(func():
			steps_box.visible = not steps_box.visible
			if steps_box.visible:
				toggle_btn.text = "▼ 💡 Masquer les explications coup par coup"
			else:
				toggle_btn.text = "▶ 💡 Décoder la suite coup par coup (débutant)"
		)

		for s in steps:
			if not (s is Dictionary):
				continue
			var step_card := PanelContainer.new()
			var sc_style := StyleBoxFlat.new()
			sc_style.bg_color = Color(DesignTokens.SURFACE.r, DesignTokens.SURFACE.g, DesignTokens.SURFACE.b, 0.6)
			sc_style.corner_radius_top_left = 6
			sc_style.corner_radius_top_right = 6
			sc_style.corner_radius_bottom_left = 6
			sc_style.corner_radius_bottom_right = 6
			sc_style.content_margin_left = 8
			sc_style.content_margin_right = 8
			sc_style.content_margin_top = 6
			sc_style.content_margin_bottom = 6
			step_card.add_theme_stylebox_override("panel", sc_style)
			step_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var s_box := VBoxContainer.new()
			s_box.add_theme_constant_override("separation", 2)
			s_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			step_card.add_child(s_box)

			var s_head := HBoxContainer.new()
			s_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s_box.add_child(s_head)

			var move_lbl := Label.new()
			var san_intl: String = str(s.get("san", ""))
			var san_fr: String = str(s.get("san_fr", ""))
			if san_intl != "" and san_intl != san_fr:
				move_lbl.text = "%s  (%s)" % [str(s.get("label", "")), san_intl]
			else:
				move_lbl.text = str(s.get("label", ""))
			move_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			move_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
			s_head.add_child(move_lbl)

			var s_sp := Control.new()
			s_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s_head.add_child(s_sp)

			var act_lbl := Label.new()
			var act_str := str(s.get("action", ""))
			act_lbl.text = "[%s]" % act_str
			act_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			if act_str.find("mat") != -1:
				act_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
			elif act_str.find("Échec") != -1:
				act_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
			elif act_str.find("Prise") != -1 or act_str.find("Promotion") != -1:
				act_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
			else:
				act_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			s_head.add_child(act_lbl)

			var desc_lbl := Label.new()
			desc_lbl.text = str(s.get("desc", ""))
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			desc_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			desc_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			s_box.add_child(desc_lbl)

			steps_box.add_child(step_card)

	return card

func _grade_row() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_S)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_XS)
	for note in [1, 3, 4, 5]:
		var btn := Button.new()
		btn.text = CarnetPresenter.grade_label(note)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		DesignTokens.style_button(btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_MIN)
		btn.pressed.connect(func(): grade(note))
		grid.add_child(btn)
	return grid

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
			var dim_str := str(c.get("dimension", ""))
			var cle_str := str(c.get("cle", ""))
			var lbl := _clean_dimension_label(dim_str, cle_str)
			dims.append({"label": lbl, "skill": c.get("skill", 0.0)})
	return dims

static func _clean_dimension_label(dim: String, cle: String) -> String:
	match dim:
		"phase":
			match cle:
				"opening": return "Ouvertures"
				"endgame": return "Finales"
				_: return "Milieu"
		"regime":
			match cle:
				"en_avance": return "Conversion"
				"en_retard": return "Défense"
				_: return "Égalité"
		"schema":
			match cle:
				"gain_tactique_manqué", "capture_ratée": return "Tactique"
				"piece_en_prise": return "Protection"
				"dame_sortie_tôt": return "Dévelop."
				"sécurité_roi", "roi_non_roqué": return "Sécurité"
				"structure_pions": return "Structure"
				"pression_temps": return "Temps"
				_: return cle.replace("_", " ").capitalize().substr(0, 10)
		"type_finale":
			match cle:
				"tours": return "Fin. Tours"
				"dames": return "Fin. Dames"
				"mineures": return "Fin. Min."
				"pions": return "Fin. Pions"
				_: return "Finales"
		"ouverture":
			var short_cle := cle.substr(0, 8) + "…" if cle.length() > 8 else cle
			return "Ouv. %s" % short_cle
	return cle.replace("_", " ").capitalize().substr(0, 10)

# ── Onglet ⟳ Sync ────────────────────────────────────────────────────────────────

func _build_sync_tab() -> void:
	_content.add_child(_section_title("Synchronisation"))
	var summary := Label.new()
	summary.text = presenter.sync_label()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_content.add_child(summary)

	# Actions Sync : ligne 1 = Mettre à jour ; ligne 2 = imports
	var actions_col = VBoxContainer.new()
	actions_col.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	_content.add_child(actions_col)

	var run = Button.new()
	run.text = "Mettre à jour"
	run.disabled = presenter.sync.get("to_process", []).size() == 0
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run.clip_text = true
	run.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	run.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	run.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(run, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	run.add_theme_color_override("font_color", DesignTokens.ACCENT)
	run.pressed.connect(func(): presenter.start_batch(); _update_batch_row())
	actions_col.add_child(run)

	var imports_row = HBoxContainer.new()
	imports_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	actions_col.add_child(imports_row)

	var btn_import_pgn = Button.new()
	btn_import_pgn.text = "📥 PGN"
	btn_import_pgn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_import_pgn.clip_text = true
	btn_import_pgn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn_import_pgn.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	btn_import_pgn.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(btn_import_pgn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_import_pgn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_import_pgn.pressed.connect(_on_import_pgn)
	imports_row.add_child(btn_import_pgn)

	var btn_import_chesscom = Button.new()
	btn_import_chesscom.text = "🌐 Chess.com"
	btn_import_chesscom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_import_chesscom.clip_text = true
	btn_import_chesscom.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn_import_chesscom.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	btn_import_chesscom.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(btn_import_chesscom, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_import_chesscom.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn_import_chesscom.pressed.connect(_on_import_chesscom)
	imports_row.add_child(btn_import_chesscom)

	var btn_recalc = Button.new()
	btn_recalc.text = "⟳ Recalculer"
	btn_recalc.tooltip_text = "Recalcule algorithmiquement tous les atomes et compétences du carnet depuis les analyses de la bibliothèque."
	btn_recalc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_recalc.clip_text = true
	btn_recalc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn_recalc.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	btn_recalc.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	DesignTokens.style_button(btn_recalc, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_recalc.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	btn_recalc.pressed.connect(_on_recalculate_profile)
	imports_row.add_child(btn_recalc)

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
	filter_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	filter_scroll.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.touch_scroll(filter_scroll)
	_content.add_child(filter_scroll)

	_filter_group = ButtonGroup.new()
	var filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_scroll.add_child(filter_row)

	var filters := [["all", "Toutes"], ["pending", "À traiter"], ["up_to_date", "À jour"], ["stale", "Périmées"]]
	for f in filters:
		var btn := Button.new()
		btn.text = f[1]
		btn.toggle_mode = true
		btn.button_group = _filter_group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		DesignTokens.style_button(btn, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		btn.pressed.connect(_on_filter_pressed.bind(f[0]))
		filter_row.add_child(btn)

	# Liste des parties
	var games_scroll = ScrollContainer.new()
	games_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	games_scroll.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN * 3)
	games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(games_scroll)
	_content.add_child(games_scroll)

	_games_list = VBoxContainer.new()
	_games_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_games_list.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	games_scroll.add_child(_games_list)
	print("[Carnet] _build_sync_tab: games_scroll added to _content, _games_list added to games_scroll")

	_refresh_games_list()
	print("[Carnet] _build_sync_tab: _refresh_games_list called")

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
	add_child(modal)
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

func _on_profile_context_menu_action(id: int) -> void:
	var profile_id: String = _profile_context_menu.get_item_metadata(id)
	match id:
		0: _on_edit_profile(profile_id)
		1: _on_manage_keys(profile_id)
		2: _on_delete_profile(profile_id)

func _on_edit_profile(profile_id: String) -> void:
	var modal = CarnetProfileEditorModal.new()
	add_child(modal)
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
	dialog.dialog_text = "Supprimer ce profil et toutes ses données ? Cette action est irréversible."
	dialog.ok_button_text = "Supprimer"
	dialog.add_theme_color_override("font_color", DesignTokens.DANGER)
	dialog.confirmed.connect(func():
		presenter.delete_profile(profile_id)
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()

func _on_import_pgn() -> void:
	var modal = CarnetImportPgnModal.new()
	add_child(modal)
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
		print("[Carnet] _refresh_games_list: _games_list is null")
		return
	for child in _games_list.get_children():
		child.queue_free()

	var profile_id := presenter.profile_id if presenter != null else ""
	print("[Carnet] _refresh_games_list: presenter=", presenter != null, " profile_id=", profile_id)
	var games: Array = []
	if presenter != null:
		var profile := CarnetProfiles.get_profile(profile_id)
		var keys: Array = profile.get("player_keys", []) if not profile.is_empty() else []
		var matches := CarnetProfiles.match_games(profile) if not profile.is_empty() else []
		var sync := CarnetStore.sync_status(profile_id)
		var entries: Dictionary = CarnetStore._load_sync(profile_id).get("entries", {}) if not profile.is_empty() else {}
		var hint := "Profil=%s | keys=%d | matches=%d | entries=%d | total_sync=%d" % [profile_id, keys.size(), matches.size(), entries.size(), sync.get("total", 0)]
		_games_list.add_child(_hint(hint))
		print("[Carnet] " + hint)
		games = presenter.get_profile_games(profile_id)
		print("[Carnet] get_profile_games returned ", games.size(), " games")
	else:
		_games_list.add_child(_hint("presenter=null"))
		print("[Carnet] _refresh_games_list: presenter is null")

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

	print("[Carnet] filtered=", filtered.size(), " current_filter=", _current_filter)
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

	print("[Carnet] _games_list enfants après ajout: ", _games_list.get_child_count())
	print("[Carnet] _games_list visible=", _games_list.visible, " size=", _games_list.size, " custom_minimum=", _games_list.custom_minimum_size)
	var scroll_parent = _games_list.get_parent()
	if scroll_parent != null:
		print("[Carnet] scroll_parent visible=", scroll_parent.visible, " size=", scroll_parent.size, " custom_minimum=", scroll_parent.custom_minimum_size)
	if _games_list.get_child_count() > 1:
		var first = _games_list.get_child(1)
		print("[Carnet] first item visible=", first.visible, " size=", first.size, " custom_minimum=", first.custom_minimum_size)

func _on_game_reanalyze(game_id: String) -> void:
	if presenter == null:
		return
	var db = presenter._db()
	var has_valid_analysis := false
	if db != null:
		var game: Dictionary = db.get_game(game_id)
		var analyses: Array = game.get("engine_analyses", []) if game.get("engine_analyses", []) is Array else []
		if not analyses.is_empty() and (analyses[-1].get("evaluations", []) as Array).size() > 0:
			has_valid_analysis = true

	presenter.reanalyze_game(game_id, presenter.profile_id)
	if has_valid_analysis:
		_on_toast_requested("Partie recalculée depuis la bibliothèque.", true)
	_update_batch_row()

func _on_game_perspective_cycle(game_id: String) -> void:
	presenter.cycle_game_perspective(game_id)
	presenter.recalculate_game(game_id)
	presenter.refresh_sync()
	_refresh_games_list()

func _on_recalculate_profile() -> void:
	if presenter == null:
		return
	var res := presenter.recalculate_profile()
	var count = int(res.get("processed_games", 0))
	var atoms = int(res.get("total_atoms", 0))
	_on_toast_requested("Carnet recalculé : %d parties, %d atomes mis à jour." % [count, atoms], true)
	_refresh_header()
	_rebuild_content()

func _on_game_remove(game_id: String) -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Retirer la partie du carnet"
	dialog.dialog_text = "Cette partie sera retirée du carnet (atomes, drills, sync). La partie reste dans la base globale."
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
