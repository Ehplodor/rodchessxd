extends Control
## Main.gd - Contrôleur principal de l'interface mobile de RodChessXD

const EvalBar2D = preload("res://src/ui/components/EvalBar2D.gd")
const ChessBoard2D = preload("res://src/ui/components/ChessBoard2D.gd")
const AdvantageGraph2D = preload("res://src/ui/components/AdvantageGraph2D.gd")
const MoveList2D = preload("res://src/ui/components/MoveList2D.gd")
const CoachPanel2D = preload("res://src/ui/components/CoachPanel2D.gd")
const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")
const OCREditorModal = preload("res://src/ui/components/OCREditorModal.gd")
const PGNModal = preload("res://src/ui/components/PGNModal.gd")
const ChessComImportModal = preload("res://src/ui/components/ChessComImportModal.gd")
const EngineHubModal = preload("res://src/ui/components/EngineHubModal.gd")
const SettingsModal = preload("res://src/ui/components/SettingsModal.gd")
const LibraryModal = preload("res://src/ui/components/LibraryModal.gd")

@onready var eval_bar: EvalBar2D = $VBox/CenterArea/EvalBar
@onready var chess_board: ChessBoard2D = $VBox/CenterArea/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $VBox/BottomTabs/Bilan/GraphContainer/AdvantageGraph
@onready var move_list: MoveList2D = $VBox/BottomTabs/Bilan/MoveList
@onready var coach_panel: CoachPanel2D = $VBox/BottomTabs/Coach/CoachPanel
@onready var bottom_tabs: TabContainer = $VBox/BottomTabs

@onready var stats_label: Label = $VBox/BottomTabs/Bilan/StatsLabel
@onready var top_eval_label: Label = $VBox/TopBar/EvalBadge/EvalText

@onready var sfx_move: AudioStreamPlayer = $Sounds/SfxMove
@onready var sfx_capture: AudioStreamPlayer = $Sounds/SfxCapture
@onready var sfx_check: AudioStreamPlayer = $Sounds/SfxCheck

var analyzer: GameAnalyzer
var analysis_thread: Thread = null

var error_label: Label = null
var _error_token := 0

func _ready() -> void:
	# Nommer clairement les onglets du panneau inférieur
	bottom_tabs.set_tab_title(0, "📈 Graphe & Analyse")
	bottom_tabs.set_tab_title(1, "🤖 Coach IA")

	analyzer = GameAnalyzer.new()
	analyzer.analysis_finished.connect(_on_analysis_finished)
	analyzer.progress_updated.connect(func(cur, tot):
		call_deferred("_on_analysis_progress", cur, tot)
	)
	
	GameController.play_sound_requested.connect(_on_play_sound)
	GameController.position_changed.connect(_on_game_position_changed)
	
	if EngineManager != null:
		EngineManager.evaluation_updated.connect(_on_engine_eval)
		EngineManager.engine_error.connect(_show_error_banner)
	
	var slm = get_node_or_null("/root/LocalSLMManager")
	if slm:
		slm.server_error.connect(_show_error_banner)
	
	_build_error_banner()
	_apply_modern_theme()
	_build_import_menu()
	if OS.has_feature("android") or OS.has_feature("ios"):
		get_window().size_changed.connect(_apply_safe_insets)
		_apply_safe_insets()
	call_deferred("_start_initial_eval")

func _notification(what: int) -> void:
	# Les barres système (gestes) peuvent apparaître/disparaître en cours de
	# partie : on recalcule les marges sûres quand l'application reprend le focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN \
			and (OS.has_feature("android") or OS.has_feature("ios")):
		_apply_safe_insets()

func _apply_modern_theme() -> void:
	var btn_normal := DesignTokens.flat(DesignTokens.BTN_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.BTN_BORDER, 1, Vector2(8, 2))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	var font_color_normal := DesignTokens.TEXT_PRIMARY
	var font_color_hover := Color.WHITE

	# Appliquer à tous les boutons de TopBar
	var top_bar = $VBox/TopBar
	for child in top_bar.get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", font_color_normal)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", font_color_normal)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Appliquer aux boutons de navigation
	var nav_row = $VBox/NavRow
	for child in nav_row.get_children():
		if child is Button and child != $VBox/NavRow/BtnAnalyzeGame:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", font_color_normal)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", font_color_normal)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Bouton Analyser Partie (accent émeraude, AA ≥ 4,5:1 sur normal et pressé)
	var btn_analyze = $VBox/NavRow/BtnAnalyzeGame
	var analyze_normal := DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.PRIMARY_BORDER, 1, Vector2(12, 2))
	var analyze_hover := analyze_normal.duplicate() as StyleBoxFlat
	analyze_hover.border_color = DesignTokens.TEXT_PRIMARY
	var analyze_pressed := analyze_normal.duplicate() as StyleBoxFlat
	analyze_pressed.bg_color = DesignTokens.PRIMARY_BG_PRESSED

	btn_analyze.add_theme_stylebox_override("normal", analyze_normal)
	btn_analyze.add_theme_stylebox_override("hover", analyze_hover)
	btn_analyze.add_theme_stylebox_override("pressed", analyze_pressed)
	btn_analyze.add_theme_color_override("font_color", DesignTokens.ON_PRIMARY)
	btn_analyze.add_theme_color_override("font_hover_color", DesignTokens.ON_PRIMARY)
	btn_analyze.add_theme_color_override("font_pressed_color", DesignTokens.ON_PRIMARY)
	btn_analyze.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Titre & badge d'évaluation
	$VBox/TopBar/MarginContainer/AppTitle.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	$VBox/TopBar/MarginContainer/AppTitle.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	var eval_badge: PanelContainer = $VBox/TopBar/EvalBadge
	eval_badge.add_theme_stylebox_override("panel",
			DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			Color.TRANSPARENT, 0, Vector2(10, 4)))
	$VBox/TopBar/EvalBadge/EvalText.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	$VBox/TopBar/EvalBadge/EvalText.add_theme_color_override("font_color", DesignTokens.ACCENT)

	# Onglets inférieurs : cibles hautes (~56 px), libellés lisibles
	var tab_selected := DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			Color.TRANSPARENT, 0, Vector2(14, 20))
	tab_selected.corner_radius_top_left = 12
	tab_selected.corner_radius_top_right = 12
	tab_selected.corner_radius_bottom_left = 0
	tab_selected.corner_radius_bottom_right = 0
	var tab_unselected := DesignTokens.flat(DesignTokens.BG_BASE, DesignTokens.RADIUS_MEDIUM,
			Color.TRANSPARENT, 0, Vector2(14, 20))
	tab_unselected.corner_radius_top_left = 12
	tab_unselected.corner_radius_top_right = 12
	tab_unselected.corner_radius_bottom_left = 0
	tab_unselected.corner_radius_bottom_right = 0
	var tab_hovered := tab_unselected.duplicate() as StyleBoxFlat
	tab_hovered.bg_color = DesignTokens.SURFACE_ELEVATED

	var tabs: TabContainer = $VBox/BottomTabs
	tabs.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	tabs.add_theme_color_override("font_selected_color", DesignTokens.TEXT_PRIMARY)
	tabs.add_theme_color_override("font_unselected_color", DesignTokens.TEXT_MUTED)
	tabs.add_theme_color_override("font_hovered_color", DesignTokens.TEXT_SECONDARY)
	tabs.add_theme_stylebox_override("tab_selected", tab_selected)
	tabs.add_theme_stylebox_override("tab_unselected", tab_unselected)
	tabs.add_theme_stylebox_override("tab_selected_hover", tab_hovered)
	tabs.add_theme_stylebox_override("tab_unselected_hover", tab_hovered)
	tabs.add_theme_stylebox_override("panel",
			DesignTokens.flat(DesignTokens.SURFACE, 0, Color.TRANSPARENT, 0, Vector2(10, 10)))

	# Bandeau de stats (textes longs → retour à la ligne)
	var stats: Label = $VBox/BottomTabs/Bilan/StatsLabel
	stats.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	stats.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_game_position_changed() -> void:
	if GameController.game.move_history.is_empty():
		advantage_graph.set_evaluations([])
		advantage_graph.update_stored_analyses([])
		stats_label.text = "Position de départ prête. Cliquez sur '🔍 Analyser Partie'."
	else:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and GameController.current_game_id != "":
			var g = dm.get_game(GameController.current_game_id)
			var ea = g.get("engine_analyses", [])
			advantage_graph.update_stored_analyses(ea)

func _start_initial_eval() -> void:
	if EngineManager != null and EngineManager.is_engine_running:
		EngineManager.evaluate_position(GameController.game.get_fen())

func _on_play_sound(sound_type: String) -> void:
	if not SettingsManager.get_setting("sound_enabled", true):
		return
	match sound_type:
		"move": sfx_move.play()
		"capture": sfx_capture.play()
		"check": sfx_check.play()

func _on_engine_eval(score_cp: int, mate_in: int, _depth: int, _best_move: String, _pv: Array, _multipv: Array) -> void:
	if top_eval_label:
		if mate_in != 0:
			top_eval_label.text = "Mat %d" % mate_in
		else:
			var pawns = score_cp / 100.0
			top_eval_label.text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns

# --- BANDEAU D'ERREURS À L'ÉCRAN ---

func _build_error_banner() -> void:
	if error_label != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.ERROR_BG
	style.border_color = DesignTokens.DANGER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	error_label = Label.new()
	error_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	error_label.offset_left = 16
	error_label.offset_right = -16
	error_label.offset_top = 10
	error_label.offset_bottom = 10
	error_label.add_theme_stylebox_override("normal", style)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.add_theme_color_override("font_color", DesignTokens.ERROR_TEXT)
	error_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(error_label)
	error_label.hide()

func _measure_error_height(msg: String) -> float:
	var font: Font = error_label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var font_size: int = error_label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = ThemeDB.fallback_font_size
	var view_w: float = self.size.x
	if view_w <= 0.0:
		view_w = float(ProjectSettings.get_setting("display/window/size/viewport_width", 450))
	var wrap_w := maxf(120.0, view_w - 32.0 - 20.0)
	var text_size := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, font_size)
	return clampf(ceilf(text_size.y) + 22.0, 40.0, 170.0)

func _show_error_banner(msg: String) -> void:
	if msg.is_empty():
		return
	if error_label == null:
		_build_error_banner()
	_error_token += 1
	var token := _error_token
	error_label.text = msg
	error_label.show()
	move_child(error_label, get_child_count() - 1)
	error_label.offset_bottom = error_label.offset_top + _measure_error_height(msg)
	await get_tree().process_frame
	if token != _error_token:
		return
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func() -> void:
		if token == _error_token:
			error_label.hide()
	)

# --- ACTIONS DES BOUTONS DE NAVIGATION ---

func _on_btn_first_pressed() -> void:
	GameController.go_first_move()

func _on_btn_prev_pressed() -> void:
	GameController.go_previous_move()

func _on_btn_next_pressed() -> void:
	GameController.go_next_move()

func _on_btn_last_pressed() -> void:
	GameController.go_last_move()

func _on_btn_flip_pressed() -> void:
	GameController.flip_board()

# --- MENU « IMPORTER » (PNG / PGN / Chess.com) ---

var import_menu: PopupMenu = null

func _build_import_menu() -> void:
	import_menu = PopupMenu.new()
	import_menu.name = "ImportMenu"
	import_menu.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var item_style := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			Color.TRANSPARENT, 0, Vector2(14, 16))
	import_menu.add_theme_stylebox_override("hover", item_style)
	import_menu.add_theme_stylebox_override("selected", item_style)
	var panel_style := DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(4, 4))
	import_menu.add_theme_stylebox_override("panel", panel_style)
	import_menu.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	import_menu.add_theme_color_override("font_hover_color", DesignTokens.TEXT_PRIMARY)
	import_menu.add_item("🖼️  Photo du plateau (PNG)")
	import_menu.add_item("📄  Fichier / texte PGN")
	import_menu.add_item("🌐  Synchroniser Chess.com")
	import_menu.id_pressed.connect(_on_import_menu_id_pressed)
	add_child(import_menu)

func _on_import_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_btn_import_png_pressed()
		1: _on_btn_import_pgn_pressed()
		2: _on_btn_chess_com_pressed()

func _on_btn_more_pressed() -> void:
	if import_menu == null:
		_build_import_menu()
	var btn: Button = $VBox/TopBar/BtnMore
	var popup_pos: Vector2i = btn.get_screen_position()
	popup_pos.y += btn.size.y - 4
	import_menu.popup(Rect2i(popup_pos, Vector2i(0, 0)))

# --- SAFE AREAS (encoche, barre de gestes) ---

func _apply_safe_insets() -> void:
	var vbox := $VBox
	var win := get_window()
	if win == null or not (OS.has_feature("android") or OS.has_feature("ios")):
		vbox.offset_left = 0.0
		vbox.offset_top = 0.0
		vbox.offset_right = 0.0
		vbox.offset_bottom = 0.0
		return

	var safe := DisplayServer.get_display_safe_area()
	var win_size := win.size
	var top_px := 0
	var bottom_px := 0
	var left_px := 0
	var right_px := 0
	if safe.size.x > 0 and safe.size.y > 0:
		# La zone sûre couvre déjà l'encoche et les barres système : aucune
		# addition des cutouts nécessaire (un trou de caméra centré ne doit pas
		# créer de marge latérale).
		top_px = maxi(0, safe.position.y)
		bottom_px = maxi(0, win_size.y - (safe.position.y + safe.size.y))
		left_px = maxi(0, safe.position.x)
		right_px = maxi(0, win_size.x - (safe.position.x + safe.size.x))
	elif not DisplayServer.get_display_cutouts().is_empty():
		# Repli : pas de zone sûre rapportée — n'ajouter que le bas d'une
		# encoche qui touche réellement le bord haut de la fenêtre.
		for cutout in DisplayServer.get_display_cutouts():
			if cutout.position.y <= 0.0:
				top_px = maxi(top_px, int(cutout.position.y + cutout.size.y))

	var vis := get_viewport().get_visible_rect().size
	var scale_f := 1.0
	if win_size.x > 0 and vis.x > 0.0:
		scale_f = float(win_size.x) / vis.x

	vbox.offset_left = float(left_px) / scale_f
	vbox.offset_top = float(top_px) / scale_f
	vbox.offset_right = -float(right_px) / scale_f
	vbox.offset_bottom = -float(bottom_px) / scale_f
	print("M1SA win=", win_size, " safe=", safe, " cutouts=", DisplayServer.get_display_cutouts(),
			" vis=", vis, " scale=", scale_f, " insets=", Vector4(vbox.offset_left, vbox.offset_top,
			vbox.offset_right, vbox.offset_bottom))

# --- MODALES D'IMPORT & GESTION ---

var current_modal: Window = null

func _open_modal(modal_node: Window) -> void:
	if current_modal and is_instance_valid(current_modal):
		current_modal.hide()
		current_modal.queue_free()
	current_modal = modal_node
	add_child(modal_node)
	modal_node.popup_centered()

func _on_btn_import_png_pressed() -> void:
	_open_modal(OCREditorModal.new())

func _on_btn_import_pgn_pressed() -> void:
	_open_modal(PGNModal.new())

func _on_btn_chess_com_pressed() -> void:
	_open_modal(ChessComImportModal.new())

func _on_btn_engine_hub_pressed() -> void:
	_open_modal(EngineHubModal.new())

func _on_btn_library_pressed() -> void:
	_open_modal(LibraryModal.new())

func _on_btn_settings_pressed() -> void:
	_open_modal(SettingsModal.new())

# --- ANALYSE DE PARTIE ---

func _on_analysis_progress(cur: int, tot: int) -> void:
	if analyzer.is_analyzing and cur < tot:
		stats_label.text = "⏳ Analyse par %s (%d/%d)..." % [EngineManager.get_engine_display_name(), cur, tot]

func _on_btn_analyze_game_pressed() -> void:
	if analyzer.is_analyzing:
		analyzer.cancel_analysis()
		if EngineManager != null:
			EngineManager.interrupt_evaluation()
		stats_label.text = "Analyse interrompue par l'utilisateur."
		return

	var moves_count = GameController.game.move_history.size()
	if moves_count == 0:
		stats_label.text = "Jouez ou importez des coups avant de lancer l'analyse globale."
		return
	
	stats_label.text = "⏳ Démarrage de l'analyse %s (0/%d)..." % [EngineManager.get_engine_display_name(), moves_count]
	
	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()
	
	analyzer.is_analyzing = true
	analysis_thread = Thread.new()
	analysis_thread.start(func():
		analyzer.start_game_analysis(GameController.game, 10)
	)

func _on_analysis_finished(report: Dictionary) -> void:
	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()

	if report.has("error"):
		var err: String = report["error"]
		stats_label.text = "❌ %s" % err
		_show_error_banner(err)
		return

	var evals = report.get("evaluations", [])
	advantage_graph.set_evaluations(evals)

	var w_acc = report.get("white_accuracy", 0.0)
	var b_acc = report.get("black_accuracy", 0.0)
	var w_elo = report.get("white_estimated_elo", 1500)
	var b_elo = report.get("black_estimated_elo", 1500)

	var total_moves = GameController.game.move_history.size() / 2
	var short_sample = " • [Échantillon court]" if total_moves < 12 else ""

	stats_label.text = "⚪ Blancs: %.1f%% (Est. %d ELO)  |  ⚫ Noirs: %.1f%% (Est. %d ELO)%s" % [w_acc, w_elo, b_acc, b_elo, short_sample]

	# Archivage automatique dans DatabaseManager pour la partie active
	var dm = get_node_or_null("/root/DatabaseManager")
	if dm and GameController:
		var gid = GameController.get_or_create_game_id()
		if gid != "":
			var analysis_entry = {
				"engine_name": "Stockfish",
				"depth": 10,
				"white_accuracy": w_acc,
				"black_accuracy": b_acc,
				"white_estimated_elo": w_elo,
				"black_estimated_elo": b_elo,
				"white_acpl": report.get("white_acpl", 0.0),
				"black_acpl": report.get("black_acpl", 0.0),
				"white_stats": report.get("white_stats", {}),
				"black_stats": report.get("black_stats", {}),
				"evaluations": evals
			}
			dm.add_engine_analysis(gid, analysis_entry)
			var game_rec = dm.get_game(gid)
			advantage_graph.update_stored_analyses(game_rec.get("engine_analyses", []))

	# Basculer immédiatement sur l'onglet du graphe pour que l'utilisateur le visualise en direct
	bottom_tabs.current_tab = 0
