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
const CoachReadingModal = preload("res://src/ui/components/CoachReadingModal.gd")
const CarnetPresenter = preload("res://src/ui/carnet/CarnetPresenter.gd")
const CarnetOverlay = preload("res://src/ui/carnet/CarnetOverlay.gd")
const CarnetBatchRunner = preload("res://src/carnet/CarnetBatchRunner.gd")

@onready var vbox: VBoxContainer = $VBox
@onready var top_bar: HBoxContainer = $VBox/TopBar
@onready var center_area: HBoxContainer = $VBox/CenterArea
@onready var board_column: VBoxContainer = $VBox/CenterArea/BoardColumn
@onready var board_container: Control = $VBox/CenterArea/BoardColumn/BoardContainer
@onready var nav_row: HBoxContainer = $VBox/NavRow
@onready var dashboard: VBoxContainer = $VBox/Dashboard

@onready var eval_bar: EvalBar2D = $VBox/CenterArea/EvalBar
@onready var chess_board: ChessBoard2D = $VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $VBox/Dashboard/GraphPanel/AdvantageGraph
@onready var engine_lines_panel: EngineLinesPanel2D = $VBox/Dashboard/EngineLinesPanel
@onready var game_review_panel: GameReviewPanel2D = $AnalyseOverlay/Layout/GameReviewPanel
@onready var move_list: MoveList2D = $AnalyseOverlay/Layout/MoveList
@onready var coach_panel: CoachPanel2D = $CoachOverlay/Layout/CoachPanel
@onready var analyse_overlay: Control = $AnalyseOverlay
@onready var coach_overlay: Control = $CoachOverlay

@onready var btn_analyze_game: Button = $VBox/NavRow/BtnAnalyzeGame
@onready var btn_toggle_live: Button = $VBox/NavRow/BtnToggleLive
@onready var top_eval_label: Label = $VBox/TopBar/EvalBadge/EvalText

var is_landscape_layout: bool = false

@onready var player_top_row: MarginContainer = $VBox/CenterArea/BoardColumn/PlayerTop
@onready var player_bottom_row: MarginContainer = $VBox/CenterArea/BoardColumn/PlayerBottom
@onready var player_dot_top: PanelContainer = $VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerDotTop
@onready var player_dot_bottom: PanelContainer = $VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerDotBottom
@onready var player_name_top: Label = $VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerNameTop
@onready var player_name_bottom: Label = $VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerNameBottom
@onready var turn_badge_top: PanelContainer = $VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop
@onready var turn_badge_label_top: Label = $VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop/TurnBadgeLabelTop
@onready var turn_badge_bottom: PanelContainer = $VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom
@onready var turn_badge_label_bottom: Label = $VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom/TurnBadgeLabelBottom

@onready var player_shortcuts_top: HBoxContainer = $VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerShortcutsTop
@onready var player_shortcuts_bottom: HBoxContainer = $VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerShortcutsBottom

const PLAYER_PROMPTS := [
	{
		"icon": "💡",
		"type": "why",
		"title": "Pourquoi ce coup ?",
		"query_white": "Explique dans un langage naturel, fluide et vivant pourquoi le coup joué est bon ou mauvais pour les Blancs et comment les Blancs doivent réagir.",
		"query_black": "Explique dans un langage naturel, fluide et vivant pourquoi le coup joué est bon ou mauvais pour les Noirs et comment les Noirs doivent réagir."
	},
	{
		"icon": "🎯",
		"type": "plan",
		"title": "Quel est mon plan ?",
		"query_white": "Explique de vive voix avec des mots simples et naturels quel est le plan stratégique principal pour les Blancs dans cette position.",
		"query_black": "Explique de vive voix avec des mots simples et naturels quel est le plan stratégique principal pour les Noirs dans cette position."
	},
	{
		"icon": "🧗",
		"type": "comeback",
		"title": "Remonter la pente",
		"query_white": "Les Blancs sont en difficulté ou cherchent à renverser la tendance. En tant que coach bienveillant et stratège, aide les Blancs à remonter la pente dans un style direct, motivant et naturel : donne des principes de défense active, de contre-attaque et de résilience psychologique, et indique les déséquilibres à exploiter pour les Blancs, SANS dévoiler directement le coup exact à jouer.",
		"query_black": "Les Noirs sont en difficulté ou cherchent à renverser la tendance. En tant que coach bienveillant et stratège, aide les Noirs à remonter la pente dans un style direct, motivant et naturel : donne des principes de défense active, de contre-attaque et de résilience psychologique, et indique les déséquilibres à exploiter pour les Noirs, SANS dévoiler directement le coup exact à jouer."
	},
	{
		"icon": "⚠️",
		"type": "threats",
		"title": "Menaces contre moi ?",
		"query_white": "Explique clairement et de manière vivante quelles sont les menaces tactiques immédiates dirigées contre les Blancs.",
		"query_black": "Explique clairement et de manière vivante quelles sont les menaces tactiques immédiates dirigées contre les Noirs."
	},
	{
		"icon": "⚔️",
		"type": "refutation",
		"title": "Réfutation tactique",
		"query_white": "Raconte la réfutation tactique coup par coup dans un langage naturel pour permettre aux Blancs de sanctionner l'adversaire.",
		"query_black": "Raconte la réfutation tactique coup par coup dans un langage naturel pour permettre aux Noirs de sanctionner l'adversaire."
	},
	{
		"icon": "🛡️",
		"type": "king_safety",
		"title": "Sécurité du Roi",
		"query_white": "Décris naturellement la sécurité du Roi blanc, les dangers qui pèsent sur son abri et comment parer les attaques contre lui.",
		"query_black": "Décris naturellement la sécurité du Roi noir, les dangers qui pèsent sur son abri et comment parer les attaques contre lui."
	},
	{
		"icon": "👶",
		"type": "simple",
		"title": "Explique simplement",
		"query_white": "Explique la situation du point de vue des Blancs comme une histoire vivante, avec des mots très simples, imagés et naturels pour joueur débutant.",
		"query_black": "Explique la situation du point de vue des Noirs comme une histoire vivante, avec des mots très simples, imagés et naturels pour joueur débutant."
	}
]

var top_shortcut_buttons: Array[Button] = []
var bottom_shortcut_buttons: Array[Button] = []
var top_speech_btn: Button = null
var bottom_speech_btn: Button = null
var _audio_in_progress_side_is_white: Variant = null

@onready var sfx_move: AudioStreamPlayer = $Sounds/SfxMove
@onready var sfx_capture: AudioStreamPlayer = $Sounds/SfxCapture
@onready var sfx_check: AudioStreamPlayer = $Sounds/SfxCheck

var analyzer: GameAnalyzer
var analysis_thread: Thread = null
var live_eval_enabled: bool = true

var error_label: Label = null
var _error_token := 0

## LeCarnet (UI 3 couches) : overlay plein écran + présentateur, câblés en code.
var carnet_overlay: Control = null
var carnet_presenter: CarnetPresenter = null

func _ready() -> void:
	DesignTokens.setup_global_fonts()
	analyzer = GameAnalyzer.new()
	analyzer.analysis_finished.connect(_on_analysis_finished)
	analyzer.analysis_position_ready.connect(_on_analysis_position_ready)
	analyzer.ply_analyzed.connect(_on_ply_analyzed)
	if chess_board and not chess_board.navigation_forward_completed.is_connected(_on_analysis_navigation_completed):
		chess_board.navigation_forward_completed.connect(_on_analysis_navigation_completed)
	
	GameController.play_sound_requested.connect(_on_play_sound)
	GameController.position_changed.connect(_on_game_position_changed)
	GameController.game_reset.connect(_cancel_analysis_if_running)
	GameController.move_navigated.connect(func(ply_idx):
		_cancel_analysis_if_running()
		_sync_eval_to_ply(ply_idx)
		_update_player_labels()
		_trigger_live_eval()
	)
	GameController.move_made.connect(func(_m):
		_update_player_labels()
		_trigger_live_eval()
	)
	
	if EngineManager != null:
		EngineManager.evaluation_updated.connect(_on_engine_eval)
		EngineManager.engine_error.connect(_show_error_banner)
		EngineManager.engine_ready.connect(func():
			_trigger_live_eval()
		)

	if advantage_graph != null:
		advantage_graph.analysis_selected.connect(_on_stored_analysis_selected)
		advantage_graph.move_scrubbed.connect(func(ply_idx):
			_sync_eval_to_ply(ply_idx)
		)
	if engine_lines_panel != null:
		engine_lines_panel.line_selected.connect(_on_engine_line_selected)
	if game_review_panel != null:
		game_review_panel.moment_selected.connect(func(ply):
			if GameController:
				GameController.navigate_to_ply(ply)
				_sync_eval_to_ply(ply)
		)
	# T2.1 — Persistance des annotations utilisateur, par position (ply).
	if chess_board != null:
		chess_board.user_annotations_changed.connect(_on_user_annotations_changed)
	if GameController != null:
		GameController.position_changed.connect(_load_annotations_for_ply)

	if btn_toggle_live != null and not btn_toggle_live.pressed.is_connected(_on_btn_toggle_live_pressed):
		btn_toggle_live.pressed.connect(_on_btn_toggle_live_pressed)
	if btn_analyze_game != null and not btn_analyze_game.pressed.is_connected(_on_btn_analyze_game_pressed):
		btn_analyze_game.pressed.connect(_on_btn_analyze_game_pressed)
	
	var slm = get_node_or_null("/root/LocalSLMManager")
	if slm:
		slm.server_error.connect(_show_error_banner)
	
	if SettingsManager != null:
		SettingsManager.settings_changed.connect(func(key, val):
			if key == "app_theme_mode":
				DesignTokens.apply_theme_mode(str(val))
				_apply_modern_theme()
		)

	_build_error_banner()
	# Le bouton du Carnet doit exister AVANT le thème pour recevoir le même style.
	_setup_carnet_overlay()
	_apply_modern_theme()
	_build_import_menu()
	if OS.has_feature("android") or OS.has_feature("ios"):
		get_window().size_changed.connect(_apply_safe_insets)
		_apply_safe_insets()

	# Câblage des raccourcis de prompts sur la ligne de chaque joueur
	_setup_player_shortcuts()

	# Écoute des signaux du Coach IA pour la restitution vocale et les erreurs
	if AICoach != null:
		AICoach.coach_speech_started.connect(_on_coach_speech_started)
		AICoach.coach_speech_finished.connect(_on_coach_speech_finished)
		AICoach.coach_speech_error.connect(_on_coach_speech_error)
		AICoach.coach_error.connect(_on_coach_error)

	_update_player_labels()
	_update_live_button_style()
	_check_and_update_layout()
	call_deferred("_start_initial_eval")

func _exit_tree() -> void:
	if AICoach != null and AICoach.has_method("stop_speech"):
		AICoach.stop_speech()
	if analyzer != null and analyzer.is_analyzing:
		analyzer.cancel_analysis()
	if analysis_thread != null and analysis_thread.is_started():
		analysis_thread.wait_to_finish()

func _notification(what: int) -> void:
	# Les barres système (gestes) peuvent apparaître/disparaître en cours de
	# partie : on recalcule les marges sûres quand l'application reprend le focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN \
			and (OS.has_feature("android") or OS.has_feature("ios")):
		_apply_safe_insets()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and dm.has_method("sync_to_storage"):
			dm.sync_to_storage()
	elif what == NOTIFICATION_RESIZED:
		_check_and_update_layout()

func _check_and_update_layout() -> void:
	if not is_inside_tree():
		return
	var cur_w = size.x
	var cur_h = maxf(1.0, size.y)
	if cur_w <= 0.0 or cur_h <= 0.0:
		var vp_size = get_viewport_rect().size if get_viewport() else Vector2(450, 800)
		cur_w = vp_size.x
		cur_h = maxf(1.0, vp_size.y)
	var aspect = cur_w / cur_h
	var should_be_landscape = (aspect >= 1.15) and (cur_w >= 560.0)
	_apply_adaptive_layout(should_be_landscape)
	_adjust_player_row_density()

func _apply_adaptive_layout(target_landscape: bool) -> void:
	if not is_instance_valid(vbox) or not is_instance_valid(center_area) or not is_instance_valid(board_column) or not is_instance_valid(dashboard) or not is_instance_valid(nav_row):
		return
	
	is_landscape_layout = target_landscape
	
	if is_landscape_layout:
		# --- MODE PAYSAGE (16/9, PC, Tablettes, Téléphone tourné) ---
		# La navigation s'intègre directement sous l'échiquier dans board_column
		if nav_row.get_parent() != board_column:
			nav_row.reparent(board_column)
		
		# Le tableau de bord se place à droite de board_column dans center_area (HBoxContainer)
		if dashboard.get_parent() != center_area:
			dashboard.reparent(center_area)
		
		board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board_column.size_flags_stretch_ratio = 1.15
		board_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		dashboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dashboard.size_flags_stretch_ratio = 1.0
		dashboard.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if is_instance_valid(eval_bar):
			eval_bar.custom_minimum_size = Vector2(24, 0)
	else:
		# --- MODE PORTRAIT (9/16, Smartphones standard) ---
		# Restauration de l'arborescence verticale initiale dans vbox
		if nav_row.get_parent() != vbox:
			nav_row.reparent(vbox)
			vbox.move_child(nav_row, center_area.get_index() + 1)
		
		if dashboard.get_parent() != vbox:
			dashboard.reparent(vbox)
			vbox.move_child(dashboard, nav_row.get_index() + 1)
		
		board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board_column.size_flags_stretch_ratio = 1.0
		board_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		dashboard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dashboard.size_flags_stretch_ratio = 1.0
		dashboard.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		
		center_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if is_instance_valid(eval_bar):
			eval_bar.custom_minimum_size = Vector2(20, 0)

	if analyse_overlay and analyse_overlay.visible:
		_dock_overlay(analyse_overlay)
	if coach_overlay and coach_overlay.visible:
		_dock_overlay(coach_overlay)

func _apply_modern_theme() -> void:
	# Fond principal de l'application
	var bg_panel = get_node_or_null("Background")
	if bg_panel:
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = DesignTokens.BG_BASE
		bg_panel.add_theme_stylebox_override("panel", bg_style)

	var btn_normal := DesignTokens.flat(DesignTokens.BTN_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.BTN_BORDER, 1, Vector2(8, 2))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	var font_color_normal := DesignTokens.TEXT_PRIMARY
	var font_color_hover := Color.WHITE if DesignTokens.current_theme_mode == "dark" else DesignTokens.TEXT_PRIMARY

	# Boutons de la barre du haut
	for child in $VBox/TopBar.get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", font_color_normal)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", font_color_normal)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Boutons de navigation sous le plateau (sauf Analyser et Live)
	var nav_row = $VBox/NavRow
	for child in nav_row.get_children():
		if child is Button and child != btn_analyze_game and child != btn_toggle_live:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", font_color_normal)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", font_color_normal)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	_apply_analyze_button_style(false)
	_update_live_button_style()

	# Titre & pastille de version
	var title_lbl = get_node_or_null("VBox/TopBar/MarginContainer/TitleBox/AppTitle")
	if title_lbl:
		title_lbl.add_theme_font_size_override("font_size", 14)
		title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	var ver_lbl = get_node_or_null("VBox/TopBar/MarginContainer/TitleBox/VersionLabel")
	if ver_lbl:
		var app_version: String = str(ProjectSettings.get_setting("application/config/version", "1.1.0"))
		ver_lbl.text = "v" + app_version
		ver_lbl.add_theme_font_size_override("font_size", 10)
		ver_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	var badge = $VBox/TopBar/EvalBadge
	badge.custom_minimum_size = Vector2(50, 36)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel",
			DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			Color.TRANSPARENT, 0, Vector2(8, 4)))
	if top_eval_label:
		top_eval_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top_eval_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top_eval_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		top_eval_label.add_theme_color_override("font_color", DesignTokens.ACCENT)

	# Vues superposées : fonds, titres + boutons de fermeture
	for overlay in [analyse_overlay, coach_overlay]:
		if overlay == null:
			continue
		var overlay_bg = overlay.get_node_or_null("Bg")
		if overlay_bg:
			var obg_style := StyleBoxFlat.new()
			obg_style.bg_color = DesignTokens.BG_BASE
			overlay_bg.add_theme_stylebox_override("panel", obg_style)
		if not overlay.has_node("Layout/Header"):
			continue
		var header: Node = overlay.get_node("Layout/Header")
		header.get_node("Title").add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		header.get_node("Title").add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		for c in header.get_children():
			if c is Button:
				c.add_theme_stylebox_override("normal", btn_normal)
				c.add_theme_stylebox_override("hover", btn_hover)
				c.add_theme_stylebox_override("pressed", btn_pressed)
				c.add_theme_color_override("font_color", font_color_normal)
				c.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	if is_instance_valid(advantage_graph):
		advantage_graph.queue_redraw()
	if is_instance_valid(eval_bar):
		eval_bar.queue_redraw()
	if is_instance_valid(move_list):
		move_list.refresh()
	_apply_overflow_guards()

## Empêche tout débordement horizontal sur écran étroit (smartphones 360-420 px) :
## encapsulation des conteneurs, troncature des titres/boutons dynamiques et débrayage
## de la largeur forcée des OptionButton (cf. cause identifiée sur SettingsModal).
func _apply_overflow_guards() -> void:
	clip_contents = true
	for path in ["VBox", "VBox/TopBar", "VBox/CenterArea", "VBox/CenterArea/BoardColumn",
			"VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerShortcutsTop",
			"VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerShortcutsBottom",
			"VBox/NavRow", "VBox/Dashboard", "AnalyseOverlay", "AnalyseOverlay/Layout",
			"CoachOverlay", "CoachOverlay/Layout"]:
		var node := get_node_or_null(path)
		if node is Control:
			(node as Control).clip_contents = true
	# Compacité de la barre du haut : 6 boutons + titre + badge doivent tenir à 360 px.
	var topbar := get_node_or_null("VBox/TopBar")
	if topbar is HBoxContainer:
		(topbar as HBoxContainer).add_theme_constant_override("separation", 4)
	var title_margin := get_node_or_null("VBox/TopBar/MarginContainer")
	if title_margin is MarginContainer:
		(title_margin as MarginContainer).add_theme_constant_override("margin_left", 0)
		(title_margin as MarginContainer).add_theme_constant_override("margin_right", 0)
	var eval_badge := get_node_or_null("VBox/TopBar/EvalBadge")
	if eval_badge is Control:
		(eval_badge as Control).custom_minimum_size = Vector2(44, 36)
	for path in ["VBox/TopBar/MarginContainer/TitleBox/AppTitle",
			"VBox/TopBar/MarginContainer/TitleBox/VersionLabel",
			"AnalyseOverlay/Layout/Header/Title", "CoachOverlay/Layout/Header/Title"]:
		var label := get_node_or_null(path)
		if label is Label:
			(label as Label).clip_text = true
			(label as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(label as Label).custom_minimum_size.x = 0
	for bar_path in ["VBox/TopBar", "VBox/NavRow", "AnalyseOverlay/Layout/Header",
			"CoachOverlay/Layout/Header"]:
		var bar := get_node_or_null(bar_path)
		if bar == null:
			continue
		for child in bar.get_children():
			# Ne jamais activer clip_text/ellipsis sur les boutons-icônes (emoji) :
			# cela retire la largeur minimale et fait disparaître le libellé. On ne
			# tronque que les boutons à texte alphabétique (Analyser, Fermer, …).
			if child is Button and _has_ascii_letter(child.text):
				child.clip_text = true
				child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				child.custom_minimum_size.x = minf(child.custom_minimum_size.x, float(DesignTokens.TOUCH_MIN))
	_harden_dropdowns(self)

static func _has_ascii_letter(text: String) -> bool:
	for i in range(text.length()):
		var c := text.unicode_at(i)
		if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
			return true
	return false

func _harden_dropdowns(node: Node) -> void:
	for child in node.get_children():
		if child is OptionButton:
			child.fit_to_longest_item = false
			child.clip_text = true
		_harden_dropdowns(child)

func _on_game_position_changed() -> void:
	_update_player_labels()
	if GameController.game.move_history.is_empty():
		advantage_graph.set_evaluations([])
		advantage_graph.update_stored_analyses([])
		if move_list:
			move_list.set_analysis_report({})
			move_list.refresh()
	else:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and GameController.current_game_id != "":
			var g = dm.get_game(GameController.current_game_id)
			var ea = g.get("engine_analyses", [])
			advantage_graph.update_stored_analyses(ea)
			if not ea.is_empty():
				var last_ea = ea.back()
				var evals = last_ea.get("evaluations", [])
				GameController.apply_evaluations(evals)
				# Pendant une analyse, la courbe est pilotée en direct par
				# _on_ply_analyzed (longueur totale de la partie préparée par
				# prepare_live_analysis). Une analyse archivée — potentiellement
				# partielle si la précédente a été stoppée — ne doit jamais écraser
				# la courbe en cours, sous peine de la tronquer.
				if analyzer == null or not analyzer.is_analyzing:
					advantage_graph.set_evaluations(evals)
					_update_graph_phase_boundaries(last_ea)
				if move_list:
					move_list.set_analysis_report(last_ea)
					move_list.refresh()
				if game_review_panel:
					game_review_panel.set_report(last_ea)
			else:
				if move_list:
					move_list.set_analysis_report({})
					move_list.refresh()
	_trigger_live_eval()

# --- LIBELLÉS JOUEURS EN HAUT / BAS DU PLATEAU ---

const _UNKNOWN_PLAYER_NAMES := ["", "player 1", "player 2", "joueur 1", "joueur 2", "?"]

func _is_unknown_player(name: String) -> bool:
	var n = name.strip_edges().to_lower()
	return n.is_empty() or n in _UNKNOWN_PLAYER_NAMES

func _style_player_dot(dot: PanelContainer, side_is_white: bool, is_active: bool) -> void:
	var bg_col: Color
	var border_col: Color
	var border_w: int = 1
	
	if side_is_white:
		bg_col = Color("#f8fafc")
		if is_active:
			border_col = Color("#10b981") # Vert émeraude actif éclatant
			border_w = 2
		else:
			border_col = Color("#94a3b8aa")
	else:
		bg_col = Color("#0f172a")
		if is_active:
			border_col = Color("#10b981") # Vert émeraude actif éclatant
			border_w = 2
		else:
			border_col = Color("#47556988")
			
	var style := DesignTokens.flat(bg_col, DesignTokens.RADIUS_MEDIUM, border_col, border_w)
	dot.add_theme_stylebox_override("panel", style)

func _update_player_labels() -> void:
	if not is_node_ready() or player_name_top == null:
		return
	var headers: Dictionary = GameController.game.pgn_headers if GameController.game else {}
	var white_raw: String = str(headers.get("White", "")).strip_edges()
	var black_raw: String = str(headers.get("Black", "")).strip_edges()

	# Toujours afficher un libellé clair, même pour les parties libres sans en-tête PGN
	var white_name: String = "Blancs" if _is_unknown_player(white_raw) else white_raw
	var black_name: String = "Noirs" if _is_unknown_player(black_raw) else black_raw

	var flipped: bool = GameController.board_flipped
	var bottom_side_white: bool = not flipped
	var top_side_white: bool = flipped

	player_top_row.visible = true
	player_bottom_row.visible = true

	var active_color: int = GameController.game.active_color if GameController.game else ChessPiece.PieceColor.WHITE
	var white_is_active: bool = (active_color == ChessPiece.PieceColor.WHITE)
	var top_is_active: bool = (top_side_white == white_is_active)
	var bottom_is_active: bool = not top_is_active

	# Formatage et surbrillance du nom des joueurs
	player_name_top.text = _clip_player_name(white_name if top_side_white else black_name)
	player_name_bottom.text = _clip_player_name(white_name if bottom_side_white else black_name)

	player_name_top.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	player_name_top.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY if top_is_active else DesignTokens.TEXT_MUTED)

	player_name_bottom.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	player_name_bottom.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY if bottom_is_active else DesignTokens.TEXT_MUTED)

	# Pastille couleur joueur avec contour actif
	player_dot_top.visible = true
	player_dot_bottom.visible = true
	_style_player_dot(player_dot_top, top_side_white, top_is_active)
	_style_player_dot(player_dot_bottom, bottom_side_white, bottom_is_active)

	# Mise à jour des raccourcis du Coach IA (adaptés Blancs vs Noirs)
	_update_player_shortcuts(top_side_white, bottom_side_white)

	# Récupération du dernier coup joué
	var last_move_text: String = ""
	if GameController.game and GameController.current_ply_index >= 0 and GameController.current_ply_index < GameController.game.move_history.size():
		var m = GameController.game.move_history[GameController.current_ply_index]
		if m.san != "":
			last_move_text = m.san
		elif m.from_sq >= 0 and m.to_sq >= 0:
			last_move_text = ChessMove.square_to_coord(m.from_sq) + " ➔ " + ChessMove.square_to_coord(m.to_sq)

	# --- DÉTECTION ÉTAT DE FIN DE PARTIE & ÉCHEC ---
	var is_checkmate: bool = false
	var is_stalemate: bool = false
	var checkmate_winner_is_white: bool = false
	var side_in_check: int = -1

	if GameController.game:
		var in_chk = GameController.game.is_in_check(active_color)
		if in_chk:
			side_in_check = active_color
		var legal_moves = GameController.game.get_legal_moves(active_color)
		if legal_moves.is_empty():
			if in_chk:
				is_checkmate = true
				checkmate_winner_is_white = (active_color == ChessPiece.PieceColor.BLACK)
			else:
				is_stalemate = true

	var pgn_result = str(headers.get("Result", "*")).strip_edges()
	var at_last_ply = (GameController.game and GameController.current_ply_index == GameController.game.move_history.size() - 1 and GameController.game.move_history.size() > 0)

	if is_checkmate:
		var top_is_winner = (top_side_white == checkmate_winner_is_white)
		_style_status_badge(turn_badge_top, turn_badge_label_top, "🏆 Gagné • Échec et mat" if top_is_winner else "💀 Perdu • Maté", "winner" if top_is_winner else "loser")
		_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🏆 Gagné • Échec et mat" if not top_is_winner else "💀 Perdu • Maté", "winner" if not top_is_winner else "loser")
	elif is_stalemate:
		_style_status_badge(turn_badge_top, turn_badge_label_top, "🤝 Nulle • Pat", "draw")
		_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🤝 Nulle • Pat", "draw")
	elif at_last_ply and pgn_result in ["1-0", "0-1", "1/2-1/2", "0.5-0.5"]:
		if pgn_result == "1-0":
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🏆 1-0 • Gagné" if top_side_white else "💀 0-1 • Perdu", "winner" if top_side_white else "loser")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🏆 1-0 • Gagné" if bottom_side_white else "💀 0-1 • Perdu", "winner" if bottom_side_white else "loser")
		elif pgn_result == "0-1":
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🏆 0-1 • Gagné" if not top_side_white else "💀 1-0 • Perdu", "winner" if not top_side_white else "loser")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🏆 0-1 • Gagné" if not bottom_side_white else "💀 1-0 • Perdu", "winner" if not bottom_side_white else "loser")
		else:
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🤝 ½ - ½ • Nulle", "draw")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🤝 ½ - ½ • Nulle", "draw")
	elif side_in_check != -1:
		var top_is_in_check = (top_side_white == (side_in_check == 0))
		if top_is_in_check:
			_style_status_badge(turn_badge_top, turn_badge_label_top, "⚠️ Échec au Roi !", "check")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, ("Dernier coup : " + last_move_text) if last_move_text != "" else "", "last_move")
		else:
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "⚠️ Échec au Roi !", "check")
			_style_status_badge(turn_badge_top, turn_badge_label_top, ("Dernier coup : " + last_move_text) if last_move_text != "" else "", "last_move")
	else:
		_style_status_badge(turn_badge_top, turn_badge_label_top, "⭐ Au trait" if top_is_active else (("Dernier coup : " + last_move_text) if last_move_text != "" else ""), "active" if top_is_active else "last_move")
		_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "⭐ Au trait" if bottom_is_active else (("Dernier coup : " + last_move_text) if last_move_text != "" else ""), "active" if bottom_is_active else "last_move")

	# Sanctuarise la visibilité des badges d'état et évite tout débordement sur petit écran
	_adjust_player_row_density()

func _style_status_badge(badge: PanelContainer, label: Label, text: String, type: String) -> void:
	if badge == null or label == null:
		return
	if text == "":
		badge.visible = false
		return
	badge.visible = true
	label.text = text
	label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)

	var bg_col: Color
	var border_col: Color
	var text_col: Color
	match type:
		"winner":
			bg_col = Color(0.06, 0.72, 0.51, 0.28)
			border_col = Color(0.16, 0.85, 0.55, 0.95)
			text_col = Color("#34d399")
		"loser":
			bg_col = Color(0.90, 0.20, 0.20, 0.25)
			border_col = Color(0.95, 0.25, 0.25, 0.95)
			text_col = Color("#f87171")
		"draw":
			bg_col = Color(0.35, 0.45, 0.55, 0.25)
			border_col = Color(0.50, 0.60, 0.70, 0.85)
			text_col = Color("#cbd5e1")
		"check":
			bg_col = Color(0.95, 0.55, 0.10, 0.28)
			border_col = Color(0.98, 0.65, 0.15, 0.95)
			text_col = Color("#fbbf24")
		"active":
			bg_col = Color(0.06, 0.72, 0.51, 0.18)
			border_col = Color(0.06, 0.72, 0.51, 0.80)
			text_col = Color("#34d399")
		_: # "last_move"
			bg_col = Color(0.94, 0.27, 0.27, 0.14)
			border_col = Color(0.94, 0.27, 0.27, 0.55)
			text_col = Color("#f87171")

	var style = DesignTokens.flat(bg_col, DesignTokens.RADIUS_SMALL, border_col, 1, Vector2(8, 2))
	badge.add_theme_stylebox_override("panel", style)
	label.add_theme_color_override("font_color", text_col)

func _clip_player_name(name: String, max_chars := 14) -> String:
	if name.length() <= max_chars:
		return name
	return name.substr(0, max_chars - 1) + "…"

## Adapte dynamiquement la visibilité des raccourcis et le nom des joueurs pour éviter
## tout débordement de ligne et sanctuariser la visibilité des informations d'état à droite.
func _adjust_player_row_density() -> void:
	if player_top_row == null or player_bottom_row == null:
		return

	# Largeur disponible estimée pour la ligne du joueur
	var available_w: float = board_column.size.x if board_column else 0.0
	if available_w <= 0.0:
		var vp_rect = get_viewport_rect() if get_viewport() else Rect2(0, 0, 450, 800)
		available_w = vp_rect.size.x - 32.0

	# Mesure de l'espace requis par les badges de droite
	var top_badge_w: float = turn_badge_top.get_combined_minimum_size().x if (turn_badge_top and turn_badge_top.visible) else 0.0
	var bottom_badge_w: float = turn_badge_bottom.get_combined_minimum_size().x if (turn_badge_bottom and turn_badge_bottom.visible) else 0.0
	var max_badge_w: float = maxf(top_badge_w, bottom_badge_w)

	# Si l'espace est très contraint (smartphone étroit ou badge d'état long comme "Dernier coup : Cg1 ➔ Cf3"),
	# on adapte le nombre de boutons affichés en priorité décroissante :
	# Priorité haute : 💡 Pourquoi ce coup (0), 🎯 Mon plan (1), 🧗 Remonter la pente (2), ⚠️ Menaces (3)
	# Secondaires : ⚔️ Réfutation (4), 🛡️ Sécurité (5), 👶 Simple (6)
	var max_shortcuts_to_show = PLAYER_PROMPTS.size() # Par défaut 7
	if available_w < 380.0 or (available_w < 440.0 and max_badge_w > 130.0):
		max_shortcuts_to_show = 3
	elif available_w < 430.0 or (available_w < 490.0 and max_badge_w > 140.0):
		max_shortcuts_to_show = 4
	elif available_w < 490.0 or (available_w < 540.0 and max_badge_w > 160.0):
		max_shortcuts_to_show = 5

	for i in range(top_shortcut_buttons.size()):
		top_shortcut_buttons[i].visible = (i < max_shortcuts_to_show)
	for i in range(bottom_shortcut_buttons.size()):
		bottom_shortcut_buttons[i].visible = (i < max_shortcuts_to_show)

	# Tronquer plus fortement le nom si la place manque
	var name_max_len = 14
	if available_w < 390.0 or max_badge_w > 130.0:
		name_max_len = 9
	elif available_w < 460.0:
		name_max_len = 11

	if GameController and GameController.game:
		var headers: Dictionary = GameController.game.pgn_headers
		var white_raw: String = str(headers.get("White", "")).strip_edges()
		var black_raw: String = str(headers.get("Black", "")).strip_edges()
		var white_name: String = "Blancs" if _is_unknown_player(white_raw) else white_raw
		var black_name: String = "Noirs" if _is_unknown_player(black_raw) else black_raw
		var flipped: bool = GameController.board_flipped
		var top_is_white: bool = flipped
		player_name_top.text = _clip_player_name(white_name if top_is_white else black_name, name_max_len)
		player_name_bottom.text = _clip_player_name(white_name if not top_is_white else black_name, name_max_len)

# --- RACCOURCIS PROMPTS COACH IA & RESTITUTION ORALE (TTS) ---

func _setup_player_shortcuts() -> void:
	if player_shortcuts_top == null or player_shortcuts_bottom == null:
		return

	for c in player_shortcuts_top.get_children():
		c.queue_free()
	for c in player_shortcuts_bottom.get_children():
		c.queue_free()
	top_shortcut_buttons.clear()
	bottom_shortcut_buttons.clear()

	var btn_normal := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(0, 0))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	# 1. Raccourcis haut
	for p in PLAYER_PROMPTS:
		var btn = Button.new()
		btn.text = p["icon"]
		btn.custom_minimum_size = Vector2(28, 28)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		player_shortcuts_top.add_child(btn)
		top_shortcut_buttons.append(btn)

	top_speech_btn = Button.new()
	top_speech_btn.text = "🔊"
	top_speech_btn.tooltip_text = "Conseil vocal en cours (cliquez pour arrêter)"
	top_speech_btn.custom_minimum_size = Vector2(28, 28)
	top_speech_btn.add_theme_font_size_override("font_size", 13)
	var speech_style := DesignTokens.flat(DesignTokens.BTN_BG_HOVER, DesignTokens.RADIUS_SMALL,
			DesignTokens.ACCENT, 1, Vector2(0, 0))
	top_speech_btn.add_theme_stylebox_override("normal", speech_style)
	top_speech_btn.visible = false
	top_speech_btn.pressed.connect(func():
		if AICoach:
			AICoach.stop_speech()
	)
	player_shortcuts_top.add_child(top_speech_btn)

	# 2. Raccourcis bas
	for p in PLAYER_PROMPTS:
		var btn = Button.new()
		btn.text = p["icon"]
		btn.custom_minimum_size = Vector2(28, 28)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		player_shortcuts_bottom.add_child(btn)
		bottom_shortcut_buttons.append(btn)

	bottom_speech_btn = Button.new()
	bottom_speech_btn.text = "🔊"
	bottom_speech_btn.tooltip_text = "Conseil vocal en cours (cliquez pour arrêter)"
	bottom_speech_btn.custom_minimum_size = Vector2(28, 28)
	bottom_speech_btn.add_theme_font_size_override("font_size", 13)
	bottom_speech_btn.add_theme_stylebox_override("normal", speech_style)
	bottom_speech_btn.visible = false
	bottom_speech_btn.pressed.connect(func():
		if AICoach:
			AICoach.stop_speech()
	)
	player_shortcuts_bottom.add_child(bottom_speech_btn)

func _update_player_shortcuts(top_side_white: bool, bottom_side_white: bool) -> void:
	if top_shortcut_buttons.size() != PLAYER_PROMPTS.size() or bottom_shortcut_buttons.size() != PLAYER_PROMPTS.size():
		return

	# Ligne du haut
	for idx in range(PLAYER_PROMPTS.size()):
		var p = PLAYER_PROMPTS[idx]
		var btn = top_shortcut_buttons[idx]
		var side_label = "Blancs" if top_side_white else "Noirs"
		btn.tooltip_text = "%s %s (Conseils %s • Restitution vocale)" % [p["icon"], p["title"], side_label]
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		btn.pressed.connect(func():
			_on_player_shortcut_pressed(top_side_white, p)
		)

	# Ligne du bas
	for idx in range(PLAYER_PROMPTS.size()):
		var p = PLAYER_PROMPTS[idx]
		var btn = bottom_shortcut_buttons[idx]
		var side_label = "Blancs" if bottom_side_white else "Noirs"
		btn.tooltip_text = "%s %s (Conseils %s • Restitution vocale)" % [p["icon"], p["title"], side_label]
		for conn in btn.pressed.get_connections():
			btn.pressed.disconnect(conn.callable)
		btn.pressed.connect(func():
			_on_player_shortcut_pressed(bottom_side_white, p)
		)

func _on_player_shortcut_pressed(is_white: bool, p: Dictionary) -> void:
	if AICoach == null:
		return

	# Si le coach parle déjà, un nouveau clic stoppe l'audio
	if AICoach.is_speaking:
		AICoach.stop_speech()
		return

	var sm = SettingsManager
	var openrouter_key = sm.get_setting("api_key_openrouter", "") if sm else ""
	var active_model = sm.get_setting("active_model_id", "openrouter/free") if sm else "openrouter/free"
	var prov = sm.get_setting("ai_provider", "openrouter") if sm else "openrouter"
	var is_free = active_model.begins_with("openrouter/free") or active_model.ends_with(":free") or active_model == "local"

	if prov != "local_slm" and not is_free and openrouter_key.strip_edges() == "":
		_show_coach_error_modal("Une clé API OpenRouter est requise pour utiliser ce modèle (%s).\n\nRenseignez votre clé dans les Réglages ou le Hub des Modèles." % active_model)
		return

	var perspective = "white" if is_white else "black"
	var side_label = "Blancs" if is_white else "Noirs"
	var query_text = p["query_white"] if is_white else p["query_black"]
	var label_text = "%s %s (%s)" % [p["icon"], p["title"], side_label]

	_audio_in_progress_side_is_white = is_white
	_update_speech_indicator(true, "⏳")

	AICoach.execute_coach_prompt(perspective, label_text, query_text, p["type"], true)

func _update_speech_indicator(indicator_visible: bool, icon: String = "🔊") -> void:
	if top_speech_btn == null or bottom_speech_btn == null:
		return
	if not indicator_visible:
		top_speech_btn.visible = false
		bottom_speech_btn.visible = false
		_audio_in_progress_side_is_white = null
		return

	var is_white = (_audio_in_progress_side_is_white == true)
	var flipped: bool = GameController.board_flipped if GameController else false
	var top_is_white: bool = flipped

	var target_top = (top_is_white == is_white)
	if target_top:
		top_speech_btn.text = icon
		top_speech_btn.visible = true
		bottom_speech_btn.visible = false
	else:
		bottom_speech_btn.text = icon
		bottom_speech_btn.visible = true
		top_speech_btn.visible = false

func _on_coach_speech_started() -> void:
	_update_speech_indicator(true, "🔊")

func _on_coach_speech_finished() -> void:
	_update_speech_indicator(false)

func _on_coach_speech_error(err_msg: String) -> void:
	_update_speech_indicator(false)
	_show_coach_error_modal("Erreur de synthèse vocale (T2S) :\n\n%s" % err_msg)

func _on_coach_error(err_msg: String) -> void:
	_update_speech_indicator(false)
	# Si l'erreur provient d'une requête audio initiée depuis le plateau, afficher la modale
	if AICoach and AICoach.last_query_context.get("extra_context", {}).get("request_audio", false):
		_show_coach_error_modal(err_msg)

func _show_coach_error_modal(error_msg: String) -> void:
	var modal = CoachReadingModal.new({}, true, error_msg)
	_open_modal(modal)

func _start_initial_eval() -> void:
	_trigger_live_eval()

func _trigger_live_eval() -> void:
	if not is_instance_valid(self):
		return
	if analyzer != null and analyzer.is_analyzing:
		return
	if not live_eval_enabled:
		return
	if EngineManager == null or not EngineManager.is_engine_running:
		return
	if GameController == null or GameController.game == null:
		return
	EngineManager.evaluate_position(GameController.game.get_fen())

func _apply_analyze_button_style(is_running: bool) -> void:
	if btn_analyze_game == null:
		return
	if is_running:
		var stop_normal := DesignTokens.flat(Color("#7f1d1d"), DesignTokens.RADIUS_SMALL,
				Color("#ef4444"), 1, Vector2(10, 2))
		var stop_hover := DesignTokens.flat(Color("#991b1b"), DesignTokens.RADIUS_SMALL,
				Color("#f87171"), 1, Vector2(10, 2))
		var stop_pressed := DesignTokens.flat(Color("#450a0a"), DesignTokens.RADIUS_SMALL,
				Color("#ef4444"), 1, Vector2(10, 2))
		btn_analyze_game.add_theme_stylebox_override("normal", stop_normal)
		btn_analyze_game.add_theme_stylebox_override("hover", stop_hover)
		btn_analyze_game.add_theme_stylebox_override("pressed", stop_pressed)
		btn_analyze_game.add_theme_color_override("font_color", Color.WHITE)
		btn_analyze_game.add_theme_color_override("font_hover_color", Color.WHITE)
		btn_analyze_game.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		var analyze_normal := DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL,
				DesignTokens.PRIMARY_BORDER, 1, Vector2(10, 2))
		var analyze_hover := analyze_normal.duplicate() as StyleBoxFlat
		analyze_hover.border_color = DesignTokens.TEXT_PRIMARY
		var analyze_pressed := analyze_normal.duplicate() as StyleBoxFlat
		analyze_pressed.bg_color = DesignTokens.PRIMARY_BG_PRESSED
		btn_analyze_game.add_theme_stylebox_override("normal", analyze_normal)
		btn_analyze_game.add_theme_stylebox_override("hover", analyze_hover)
		btn_analyze_game.add_theme_stylebox_override("pressed", analyze_pressed)
		btn_analyze_game.add_theme_color_override("font_color", DesignTokens.ON_PRIMARY)
		btn_analyze_game.add_theme_color_override("font_hover_color", DesignTokens.ON_PRIMARY)
		btn_analyze_game.add_theme_color_override("font_pressed_color", DesignTokens.ON_PRIMARY)
	btn_analyze_game.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

func _update_live_button_style() -> void:
	if btn_toggle_live == null:
		return
	if live_eval_enabled:
		btn_toggle_live.text = "⚡ Live"
		var live_normal := DesignTokens.flat(Color(0.06, 0.72, 0.51, 0.22), DesignTokens.RADIUS_SMALL,
				Color("#10b981"), 1, Vector2(8, 2))
		var live_hover := DesignTokens.flat(Color(0.06, 0.72, 0.51, 0.35), DesignTokens.RADIUS_SMALL,
				Color("#34d399"), 1, Vector2(8, 2))
		var live_pressed := DesignTokens.flat(Color(0.06, 0.72, 0.51, 0.45), DesignTokens.RADIUS_SMALL,
				Color("#059669"), 1, Vector2(8, 2))
		btn_toggle_live.add_theme_stylebox_override("normal", live_normal)
		btn_toggle_live.add_theme_stylebox_override("hover", live_hover)
		btn_toggle_live.add_theme_stylebox_override("pressed", live_pressed)
		btn_toggle_live.add_theme_color_override("font_color", Color("#34d399"))
		btn_toggle_live.add_theme_color_override("font_hover_color", Color.WHITE)
		btn_toggle_live.add_theme_color_override("font_pressed_color", Color("#10b981"))
	else:
		btn_toggle_live.text = "⚡ Off"
		var off_normal := DesignTokens.flat(DesignTokens.BTN_BG, DesignTokens.RADIUS_SMALL,
				DesignTokens.BTN_BORDER, 1, Vector2(8, 2))
		var off_hover := off_normal.duplicate() as StyleBoxFlat
		off_hover.bg_color = DesignTokens.BTN_BG_HOVER
		var off_pressed := off_normal.duplicate() as StyleBoxFlat
		off_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
		btn_toggle_live.add_theme_stylebox_override("normal", off_normal)
		btn_toggle_live.add_theme_stylebox_override("hover", off_hover)
		btn_toggle_live.add_theme_stylebox_override("pressed", off_pressed)
		btn_toggle_live.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		btn_toggle_live.add_theme_color_override("font_hover_color", DesignTokens.TEXT_PRIMARY)
		btn_toggle_live.add_theme_color_override("font_pressed_color", DesignTokens.TEXT_MUTED)
	btn_toggle_live.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

func _on_btn_toggle_live_pressed() -> void:
	live_eval_enabled = not live_eval_enabled
	_update_live_button_style()
	if live_eval_enabled:
		_trigger_live_eval()
	else:
		if EngineManager != null and not analyzer.is_analyzing:
			EngineManager.stop_evaluation()
		if chess_board:
			chess_board.set_best_move_arrow("")
		if top_eval_label:
			top_eval_label.text = "Live off"

func _on_stored_analysis_selected(analysis_entry: Dictionary) -> void:
	if GameController:
		GameController.apply_evaluations(analysis_entry.get("evaluations", []))
	if move_list:
		move_list.set_analysis_report(analysis_entry)
		move_list.refresh()
	if game_review_panel:
		game_review_panel.set_report(analysis_entry)
	_update_graph_phase_boundaries(analysis_entry)
	var cur_ply = GameController.current_ply_index if GameController else -1
	_sync_eval_to_ply(cur_ply)

func _sync_eval_to_ply(ply_idx: int) -> void:
	if advantage_graph != null and not advantage_graph.evaluations.is_empty():
		if ply_idx >= 0 and ply_idx < advantage_graph.evaluations.size():
			var rec: Dictionary = advantage_graph.evaluations[ply_idx]
			var score_cp: int = rec.get("score_cp", 0)
			var mate_in: int = rec.get("mate_in", 0)
			if eval_bar:
				eval_bar.set_score(score_cp, mate_in)
			if top_eval_label:
				top_eval_label.text = EvalFormatter.format_cp_mate(score_cp, mate_in)
			
			var best_uci: String = rec.get("best_move", "")
			if chess_board:
				chess_board.set_best_move_arrow(best_uci, int(rec.get("depth", 0)))
		elif ply_idx == -1:
			if eval_bar:
				eval_bar.set_score(20, 0)
			if top_eval_label:
				top_eval_label.text = "+0.2"
			if chess_board:
				chess_board.set_best_move_arrow("")

func _on_play_sound(sound_type: String) -> void:
	if not SettingsManager.get_setting("sound_enabled", true):
		return
	match sound_type:
		"move": sfx_move.play()
		"capture": sfx_capture.play()
		"check": sfx_check.play()

func _on_engine_eval(score_cp: int, mate_in: int, depth: int, best_move: String, _pv: Array, multipv: Array) -> void:
	_update_engine_lines(multipv, depth)
	if analyzer != null and analyzer.is_analyzing:
		if top_eval_label:
			top_eval_label.text = EvalFormatter.format_cp_mate(score_cp, mate_in)
		return

	# Si la position actuelle correspond à un coup déjà analysé dans le graphe,
	# on préserve la synchronisation stricte avec l'analyse pré-calculée.
	var cur_ply = GameController.current_ply_index if GameController else -1
	var has_stored_eval = false
	if advantage_graph != null and not advantage_graph.evaluations.is_empty():
		if cur_ply >= 0 and cur_ply < advantage_graph.evaluations.size():
			has_stored_eval = true
		elif cur_ply == -1:
			has_stored_eval = true

	if not has_stored_eval:
		if top_eval_label:
			top_eval_label.text = EvalFormatter.format_cp_mate(score_cp, mate_in)

		if eval_bar:
			eval_bar.set_score(score_cp, mate_in)

		if chess_board:
			chess_board.set_best_move_arrow(best_move)

## Dernier état publié du panneau MultiPV (throttle par profondeur + nb de lignes).
var _engine_lines_last_depth: int = -1
var _engine_lines_last_count: int = -1

## T1.1 — Met à jour le panneau des lignes moteur (MultiPV).
## Throttlé (profondeur/nombre de lignes) et ignoré pendant l'analyse de masse pour
## ne pas reconstruire les boutons à chaque ligne `info` du moteur.
func _update_engine_lines(multipv: Array, depth: int) -> void:
	if engine_lines_panel == null or multipv.is_empty():
		return
	if analyzer != null and analyzer.is_analyzing:
		return
	if depth == _engine_lines_last_depth and multipv.size() == _engine_lines_last_count:
		return
	_engine_lines_last_depth = depth
	_engine_lines_last_count = multipv.size()
	var eng_name := "Moteur"
	if EngineManager != null and EngineManager.has_method("get_engine_display_name"):
		eng_name = EngineManager.get_engine_display_name()
	engine_lines_panel.set_lines(multipv, eng_name, depth)

## T2.1 — Cache mémoire de la partie courante + écriture différée des annotations.
## Évite une lecture/parse et une réécriture complète du JSON à chaque flèche/ply.
var _annot_game_cache_id: String = ""
var _annot_game_cache: Dictionary = {}
var _annotation_save_timer: Timer = null

func _ensure_annotation_timer() -> void:
	if _annotation_save_timer == null:
		_annotation_save_timer = Timer.new()
		_annotation_save_timer.one_shot = true
		_annotation_save_timer.wait_time = 0.6
		_annotation_save_timer.timeout.connect(_flush_annotation_save)
		add_child(_annotation_save_timer)

func _get_cached_game(gid: String) -> Dictionary:
	if gid == "":
		return {}
	if gid != _annot_game_cache_id:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm == null:
			return {}
		var loaded: Dictionary = dm.get_game(gid)
		_annot_game_cache = loaded
		_annot_game_cache_id = gid if not loaded.is_empty() else ""
	return _annot_game_cache

## T2.1 — Sauvegarde (différée) les annotations du ply courant.
func _on_user_annotations_changed() -> void:
	if GameController == null or chess_board == null:
		return
	var gid: String = GameController.get_or_create_game_id()
	if gid == "":
		return
	var game := _get_cached_game(gid)
	if game.is_empty():
		return
	var ann: Dictionary = game.get("annotations", {})
	ann[str(GameController.current_ply_index)] = chess_board.get_user_annotations()
	game["annotations"] = ann
	_ensure_annotation_timer()
	_annotation_save_timer.start()

## Écrit une seule fois pour une rafale d'annotations.
func _flush_annotation_save() -> void:
	if GameController == null or _annot_game_cache_id == "" or _annot_game_cache.is_empty():
		return
	var dm = get_node_or_null("/root/DatabaseManager")
	if dm == null:
		return
	_sync_cached_game_moves(_annot_game_cache)
	dm.save_game(_annot_game_cache)

## Correction revue : l'enregistrement doit refléter TOUS les coups joués
## (sinon la fiche archivée reste figée aux coups présents lors de sa création).
func _sync_cached_game_moves(game: Dictionary) -> void:
	if GameController == null or GameController.game == null:
		return
	var live: ChessGame = GameController.game
	var moves_arr: Array = []
	for i in range(live.move_history.size()):
		var m = live.move_history[i]
		moves_arr.append({
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": (i % 2 == 0),
			"san": m.san,
			"uci": m.uci,
			"quality": m.quality,
			"loss_cp": m.centipawn_loss
		})
	game["moves"] = moves_arr
	game["pgn_text"] = live.export_pgn()
	game["result"] = live.pgn_headers.get("Result", game.get("result", "*"))

## T2.1 — Recharge les annotations de la position affichée.
func _load_annotations_for_ply() -> void:
	if GameController == null or chess_board == null:
		return
	if GameController.current_game_id == "":
		# « Nouvelle partie » doit aussi retirer les annotations de l'échiquier.
		chess_board.set_user_annotations({})
		return
	var game := _get_cached_game(GameController.current_game_id)
	var ann: Dictionary = game.get("annotations", {})
	var data = ann.get(str(GameController.current_ply_index), {})
	chess_board.set_user_annotations(data if data is Dictionary else {})

## T2.3 — Calcule et transmet les bornes de phase au graphe.
func _update_graph_phase_boundaries(report: Dictionary) -> void:
	if advantage_graph == null:
		return
	var evals: Array = report.get("evaluations", [])
	var theory: int = int(report.get("theory_plies", 0))
	var bounds: Array = []
	if theory > 0:
		bounds.append(theory)
	for ev in evals:
		if ev.get("is_theory", false):
			continue
		if GamePhaseService.phase_for(str(ev.get("fen", "")), int(ev.get("ply", 0)), theory) == "endgame":
			var es := int(ev.get("ply", 0))
			if es > 0:
				bounds.append(es)
			break
	advantage_graph.set_phase_boundaries(bounds)

## T1.1 — Prévisualise la première position d'une ligne choisie sur l'échiquier.
func _on_engine_line_selected(_rank: int, pv: Array, best_move: String) -> void:
	var move_uci := best_move
	if move_uci == "" and pv.size() > 0:
		move_uci = str(pv[0])
	if chess_board == null or move_uci.length() < 4:
		return
	chess_board.set_best_move_arrow(move_uci)

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

# --- NOTIFICATIONS FLOTTANTES (TOAST) ---

var toast_label: Label = null
var _toast_token := 0

func _show_toast(msg: String, is_success: bool = true) -> void:
	if msg.is_empty():
		return
	if toast_label == null:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.72, 0.51, 0.92) if is_success else DesignTokens.SURFACE_ELEVATED
		style.border_color = Color("#34d399") if is_success else DesignTokens.BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(DesignTokens.RADIUS_MEDIUM)
		style.set_content_margin_all(10)
		toast_label = Label.new()
		toast_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		toast_label.offset_left = 24
		toast_label.offset_right = -24
		toast_label.offset_top = 54
		toast_label.offset_bottom = 94
		toast_label.add_theme_stylebox_override("normal", style)
		toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		toast_label.add_theme_color_override("font_color", Color.WHITE)
		toast_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(toast_label)
		toast_label.hide()
	else:
		var style: StyleBoxFlat = toast_label.get_theme_stylebox("normal")
		if style:
			style.bg_color = Color(0.06, 0.72, 0.51, 0.92) if is_success else DesignTokens.SURFACE_ELEVATED
			style.border_color = Color("#34d399") if is_success else DesignTokens.BORDER

	_toast_token += 1
	var token := _toast_token
	toast_label.text = msg
	toast_label.show()
	move_child(toast_label, get_child_count() - 1)
	var timer := get_tree().create_timer(2.8)
	timer.timeout.connect(func() -> void:
		if token == _toast_token and is_instance_valid(toast_label):
			toast_label.hide()
	)

# --- ACTIONS DES BOUTONS DE NAVIGATION ---

func _on_btn_first_pressed() -> void:
	_cancel_analysis_if_running()
	GameController.go_first_move()

func _on_btn_prev_pressed() -> void:
	_cancel_analysis_if_running()
	GameController.go_previous_move()

func _on_btn_next_pressed() -> void:
	_cancel_analysis_if_running()
	GameController.go_next_move()

func _on_btn_last_pressed() -> void:
	_cancel_analysis_if_running()
	GameController.go_last_move()

func _on_btn_flip_pressed() -> void:
	GameController.flip_board()

## Vues superposées (Analyse / Coach) : plein écran sur mobile portrait, ancrées à droite en paysage (échiquier 100% visible)

func _dock_overlay(overlay: Control) -> void:
	if not is_instance_valid(overlay):
		return
	if is_landscape_layout:
		# En mode paysage : le panneau s'ancre sur la colonne de droite (Dashboard)
		# Le plateau de jeu à gauche reste 100% VISIBLE et INTERACTIF !
		var left_x: float = center_area.size.x * 0.53
		var top_y: float = top_bar.size.y if top_bar else 56.0
		if is_instance_valid(dashboard) and dashboard.is_inside_tree() and dashboard.size.x > 100.0:
			left_x = dashboard.global_position.x
			top_y = dashboard.global_position.y
		
		var right_w = maxf(280.0, size.x - left_x)
		var right_h = maxf(280.0, size.y - top_y)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		overlay.position = Vector2(left_x, top_y)
		overlay.size = Vector2(right_w, right_h)
	else:
		# En mode portrait : plein écran complet
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = 0
		overlay.offset_top = 0
		overlay.offset_right = 0
		overlay.offset_bottom = 0

func _open_analyse_overlay() -> void:
	coach_overlay.visible = false
	if move_list:
		move_list.refresh()
	_show_overlay(analyse_overlay)

func _open_coach_overlay() -> void:
	analyse_overlay.visible = false
	if coach_panel:
		coach_panel.refresh_for_current_ply()
	_show_overlay(coach_overlay)

## LeCarnet : overlay plein écran accessible depuis la barre supérieure.
func _setup_carnet_overlay() -> void:
	if top_bar == null:
		return
	carnet_presenter = CarnetPresenter.new()
	carnet_overlay = CarnetOverlay.new()
	carnet_overlay.name = "CarnetOverlay"
	add_child(carnet_overlay)
	carnet_overlay.closed.connect(_close_carnet_overlay)
	# Le lot analyse via le moteur partagé : il cède le pas à l'utilisateur.
	carnet_presenter.set_engine_free_provider(func() -> bool:
		if analyse_overlay != null and analyse_overlay.visible:
			return false
		if analyzer != null and analyzer.is_analyzing:
			return false
		return true)
	carnet_presenter.error.connect(_show_error_banner)
	var btn := Button.new()
	btn.name = "BtnCarnet"
	btn.text = "📓"
	btn.tooltip_text = "LeCarnet"
	DesignTokens.style_button(btn, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn.custom_minimum_size.x = 44.0
	btn.pressed.connect(_open_carnet_overlay)
	top_bar.add_child(btn)

func _open_carnet_overlay() -> void:
	if carnet_overlay == null or carnet_presenter == null:
		return
	if analyse_overlay:
		analyse_overlay.visible = false
	if coach_overlay:
		coach_overlay.visible = false
	carnet_overlay.open(carnet_presenter)
	# Plein écran + au-dessus de toutes les pièces (cf. fix overlays Analyse/Coach).
	carnet_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	carnet_overlay.visible = true
	move_child(carnet_overlay, get_child_count() - 1)

func _close_carnet_overlay() -> void:
	if carnet_overlay != null:
		carnet_overlay.visible = false

func _show_overlay(overlay: Control) -> void:
	_dock_overlay(overlay)
	overlay.visible = true
	move_child(overlay, get_child_count() - 1)

func _close_overlays() -> void:
	analyse_overlay.visible = false
	coach_overlay.visible = false
	if carnet_overlay != null:
		carnet_overlay.visible = false

func close_overlays() -> void:
	_close_overlays()

## Retour à la vue principale (clic sur un coup dans l'analyse).
func show_board_tab() -> void:
	if not is_landscape_layout:
		_close_overlays()

# --- MENU « PLUS / ACTIONS » (PNG / PGN / Reset / Export / Chess.com / Aides) ---

var import_menu: PopupMenu = null
var settings_menu: PopupMenu = null

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
	import_menu.add_item("📚  Bibliothèque & analyses archivées", 6)
	import_menu.add_separator("Importer")
	import_menu.add_item("🖼️  Photo du plateau (PNG)", 0)
	import_menu.add_item("📄  Fichier / texte PGN", 1)
	import_menu.add_item("🧩  Coller une position FEN", 7)
	import_menu.add_item("🌐  Synchroniser Chess.com", 2)
	import_menu.add_separator("Partie")
	import_menu.add_item("📋  Exporter le PGN (Copier)", 3)
	import_menu.add_item("📝  Exporter le PGN annoté (Copier)", 8)
	import_menu.add_item("✨  Nouvelle partie (Reset)", 4)
	import_menu.add_separator("Affichage")
	import_menu.add_item("🎯  Aides de coups (ON/OFF)", 5)
	import_menu.add_item("🧽  Effacer les annotations", 9)
	import_menu.id_pressed.connect(_on_import_menu_id_pressed)
	add_child(import_menu)

func _on_import_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_btn_import_png_pressed()
		1: _on_btn_import_pgn_pressed()
		2: _on_btn_chess_com_pressed()
		3: _export_pgn()
		4: _on_btn_new_game_pressed()
		5: _toggle_move_hints()
		6: _open_modal(LibraryModal.new())
		7: _on_btn_import_fen_pressed()
		8: _export_pgn(true)
		9: _on_btn_clear_annotations_pressed()

## T2.1 — Efface les annotations de la position courante (persisté via le cache).
func _on_btn_clear_annotations_pressed() -> void:
	if chess_board == null:
		return
	chess_board.clear_user_annotations()
	_show_toast("Annotations effacées")

func _export_pgn(annotated: bool = false) -> void:
	if GameController == null or GameController.game == null:
		_show_error_banner("Aucune partie à exporter.")
		return
	var pgn_text: String = GameController.game.export_pgn(annotated)
	DisplayServer.clipboard_set(pgn_text)
	var pgn_modal := PGNModal.new()
	pgn_modal.set_export_mode(pgn_text)
	_open_modal(pgn_modal)
	_show_toast("PGN %s copié dans le presse-papiers !" % ("annoté" if annotated else ""))

## T2.5 — Import rapide d'une position FEN (presse-papiers ou saisie via l'éditeur).
func _on_btn_import_fen_pressed() -> void:
	var clip := DisplayServer.clipboard_get().strip_edges()
	if _is_valid_fen(clip):
		GameController.load_fen(clip)
		_trigger_live_eval()
		_show_toast("Position FEN chargée depuis le presse-papiers")
		return
	_open_modal(OCREditorModal.new())

## Validation stricte avant tout chargement depuis le presse-papiers : 8 rangées de
## 8 cases, pièces connues, trait w/b. Évite de charger une position corrompue.
func _is_valid_fen(text: String) -> bool:
	if text.length() < 15 or text.length() > 120:
		return false
	var parts := text.split(" ", false)
	if parts.size() < 2:
		return false
	var rows := parts[0].split("/")
	if rows.size() != 8:
		return false
	for row in rows:
		var count := 0
		for c in row:
			if c.is_valid_int():
				var d := c.to_int()
				if d < 1 or d > 8:
					return false
				count += d
			elif c.to_upper() in ["P", "N", "B", "R", "Q", "K"]:
				count += 1
			else:
				return false
		if count != 8:
			return false
	return parts[1] == "w" or parts[1] == "b"

func _on_btn_new_game_pressed() -> void:
	if GameController.game and not GameController.game.move_history.is_empty():
		var dialog := ConfirmationDialog.new()
		dialog.title = "Nouvelle partie"
		dialog.dialog_text = "Voulez-vous réinitialiser l'échiquier et démarrer une nouvelle partie ?\nLa partie en cours sera effacée."
		dialog.ok_button_text = "Réinitialiser"
		dialog.cancel_button_text = "Annuler"
		dialog.confirmed.connect(_do_reset_game)
		add_child(dialog)
		dialog.popup_centered()
	else:
		_do_reset_game()

func _do_reset_game() -> void:
	if analyzer and analyzer.is_analyzing:
		analyzer.cancel_analysis()
	# Annule une éventuelle sauvegarde d'annotations en attente (nouvelle partie).
	if _annotation_save_timer:
		_annotation_save_timer.stop()
	_annot_game_cache_id = ""
	_annot_game_cache.clear()
	GameController.reset_to_initial()
	advantage_graph.set_evaluations([])
	advantage_graph.update_stored_analyses([])
	if eval_bar:
		eval_bar.set_score(20, 0)
	if top_eval_label:
		top_eval_label.text = "+0.2"
	if chess_board:
		chess_board.last_move_from = -1
		chess_board.last_move_to = -1
		chess_board.set_best_move_arrow("")
		chess_board.reset_board_visuals()
	_update_player_labels()
	if move_list:
		move_list.set_analysis_report({})
		move_list.refresh()
	_show_toast("Nouvelle partie initialisée")
	_trigger_live_eval()

func _toggle_move_hints() -> void:
	var cur_val: bool = SettingsManager.get_setting("show_move_hints", true)
	var new_val: bool = not cur_val
	SettingsManager.set_setting("show_move_hints", new_val)
	if chess_board:
		chess_board.show_move_hints = new_val
		if not new_val:
			chess_board.best_move_arrow_from = -1
			chess_board.best_move_arrow_to = -1
		if chess_board.arrow_overlay:
			chess_board.arrow_overlay.queue_redraw()
		chess_board.queue_redraw()
	var state_str = "activées" if new_val else "désactivées"
	_show_toast("Aides visuelles %s" % state_str)

## Affiche un PopupMenu sous un bouton du bandeau haut.
func _popup_from_button(menu: PopupMenu, btn_node: Node) -> void:
	if not is_instance_valid(btn_node):
		return
	var ctrl := btn_node as Control
	var pos: Vector2i = ctrl.get_screen_position()
	pos.y += int(ctrl.size.y) - 4
	menu.popup(Rect2i(pos, Vector2i(0, 0)))

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
	var vis: Vector2 = get_viewport().get_visible_rect().size
	if vis.x > 0 and vis.y > 0:
		var max_w = int(vis.x * 0.94)
		var max_h = int(vis.y * 0.92)
		modal_node.size = Vector2i(mini(modal_node.size.x, max_w), mini(modal_node.size.y, max_h))
	modal_node.popup_centered(modal_node.size)

func _on_btn_import_png_pressed() -> void:
	_open_modal(OCREditorModal.new())

func _on_btn_import_pgn_pressed() -> void:
	_open_modal(PGNModal.new())

func _on_btn_chess_com_pressed() -> void:
	_open_modal(ChessComImportModal.new())

func _on_btn_library_pressed() -> void:
	if import_menu == null:
		_build_import_menu()
	_popup_from_button(import_menu, $VBox/TopBar/BtnLibrary)

func _build_settings_menu() -> void:
	settings_menu = PopupMenu.new()
	settings_menu.name = "SettingsMenu"
	settings_menu.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var item_style := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			Color.TRANSPARENT, 0, Vector2(14, 16))
	settings_menu.add_theme_stylebox_override("hover", item_style)
	settings_menu.add_theme_stylebox_override("selected", item_style)
	var panel_style := DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(4, 4))
	settings_menu.add_theme_stylebox_override("panel", panel_style)
	settings_menu.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	settings_menu.add_theme_color_override("font_hover_color", DesignTokens.TEXT_PRIMARY)
	settings_menu.add_item("⚙️  Réglages de l'application", 0)
	settings_menu.add_item("⚡  Moteurs d'échecs", 1)
	settings_menu.id_pressed.connect(_on_settings_menu_id_pressed)
	add_child(settings_menu)

func _on_settings_menu_id_pressed(id: int) -> void:
	match id:
		0: _open_modal(SettingsModal.new())
		1: _open_modal(EngineHubModal.new())

func _on_btn_settings_pressed() -> void:
	if settings_menu == null:
		_build_settings_menu()
	_popup_from_button(settings_menu, $VBox/TopBar/BtnSettings)

# --- ANALYSE DE PARTIE ---

## Affiche le demi-coup avant que Stockfish ne commence à analyser sa position.
## Ne pas émettre `position_changed` ici : celui-ci déclencherait inutilement le Live.
func _on_analysis_position_ready(ply_idx: int) -> void:
	if not is_instance_valid(self) or analyzer == null or not analyzer.is_analyzing:
		return
	if GameController == null or GameController.game == null:
		# Accusé de réception même sans GameController : évite de bloquer la
		# boucle d'attente `wait_for_display` de l'analyseur.
		if analyzer:
			analyzer.confirm_analysis_position_displayed(ply_idx)
		return
	var total_moves = GameController.game.move_history.size()
	if ply_idx < 0 or ply_idx >= total_moves:
		# Idem : ply hors-limites mais la boucle attend notre signal.
		if analyzer:
			analyzer.confirm_analysis_position_displayed(ply_idx)
		return

	GameController.current_ply_index = ply_idx
	GameController.game.restore_state(ply_idx + 1)

	if chess_board:
		var move: ChessMove = GameController.game.move_history[ply_idx]
		# Toute flèche appartient à la position précédente jusqu'au premier retour
		# `info` de cette nouvelle évaluation : on l'efface donc immédiatement.
		chess_board.best_move_arrow_depth = 0
		chess_board.best_move_arrow_from = -1
		chess_board.best_move_arrow_to = -1
		if chess_board.arrow_overlay:
			chess_board.arrow_overlay.queue_redraw()
		chess_board.queue_redraw()

		if move.captured_piece != ChessPiece.Type.NONE:
			_on_play_sound("capture")
		elif move.is_check:
			_on_play_sound("check")
		else:
			_on_play_sound("move")
		chess_board._animate_navigation_forward(move, true)
	else:
		analyzer.confirm_analysis_position_displayed(ply_idx)

	_update_player_labels()

## Le calcul suivant attend ce signal : les flèches ne peuvent plus apparaître
## pendant que la pièce du coup précédent traverse encore le plateau.
func _on_analysis_navigation_completed(ply_idx: int) -> void:
	if analyzer and analyzer.is_analyzing:
		analyzer.confirm_analysis_position_displayed(ply_idx)

func _on_ply_analyzed(ply_idx: int, move_record: Dictionary, _partial_stats: Dictionary) -> void:
	if not is_instance_valid(self) or not analyzer.is_analyzing:
		return

	var total_moves = GameController.game.move_history.size() if GameController.game else 0
	if total_moves == 0 or ply_idx >= total_moves:
		return

	# 1. La position a déjà été affichée juste avant le calcul. Ici, on verrouille
	# seulement la recommandation finale et les données de ce demi-coup.
	if chess_board:
		# Flèche tactique moderne cyan de la recommandation Stockfish
		var best_uci: String = move_record.get("best_move", "")
		chess_board.set_best_move_arrow(best_uci, int(move_record.get("depth", 0)))

	# 2. Tracé progressif de la courbe d'avantage et de son halo de confiance
	if advantage_graph:
		advantage_graph.update_live_ply(ply_idx, move_record)

	# 3. Jauge d'évaluation et badge supérieur
	var score_cp: int = move_record.get("score_cp", 0)
	var mate_in: int = int(move_record.get("mate_in", 0))
	if eval_bar:
		eval_bar.set_score(score_cp, mate_in)
	if top_eval_label:
		top_eval_label.text = EvalFormatter.format_cp_mate(score_cp, mate_in)

func _cancel_analysis_if_running() -> void:
	if analyzer != null and analyzer.is_analyzing:
		analyzer.cancel_analysis()
		analyzer.is_analyzing = false
		if EngineManager != null:
			EngineManager.interrupt_evaluation()
		btn_analyze_game.text = "🔍 Analyser"
		_apply_analyze_button_style(false)
		btn_toggle_live.disabled = false

## T0.5 — Relance l'analyse pour appliquer le classifieur courant (win%, mat, brillants).
func _on_btn_reanalyze_pressed() -> void:
	if analyzer != null and analyzer.is_analyzing:
		return
	_close_overlays()
	_on_btn_analyze_game_pressed()

func _on_btn_analyze_game_pressed() -> void:
	if analyzer.is_analyzing:
		_cancel_analysis_if_running()
		if live_eval_enabled:
			_trigger_live_eval()
		return

	var moves_count = GameController.game.move_history.size()
	if moves_count == 0:
		return

	btn_analyze_game.text = "⏹ STOP"
	_apply_analyze_button_style(true)
	btn_toggle_live.disabled = true

	var sm = get_node_or_null("/root/SettingsManager")
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var mode: String = sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"
	var time_per_move: float = sm.get_setting("analysis_time_per_move", 0.2) if sm else 0.2
	var dynamic_base: float = sm.get_setting("analysis_dynamic_base", 0.08) if sm else 0.08
	var dynamic_max: float = sm.get_setting("analysis_dynamic_max", 0.25) if sm else 0.25
	var budget_base: int = sm.get_setting("analysis_budget_base_depth", 8) if sm else 8
	var budget_deep: int = sm.get_setting("analysis_budget_deep_depth", 14) if sm else 14
	var budget_max: int = sm.get_setting("analysis_budget_max_deep", 6) if sm else 6
	var budget_crit: float = sm.get_setting("analysis_budget_min_criticality", 12.0) if sm else 12.0
	var a_depth: int = sm.get_setting("analysis_depth", def_anal) if sm else def_anal

	# Verrouillage immédiat du mode analyse et arrêt du Live avant toute manipulation de l'échiquier
	analyzer.engine_manager = EngineManager
	analyzer.settings_manager = sm
	analyzer.is_analyzing = true
	if EngineManager != null:
		EngineManager.stop_evaluation()

	# Initialisation de la courbe d'avantage avec halo d'incertitude initial large
	if advantage_graph:
		advantage_graph.prepare_live_analysis(moves_count)

	# Remise visuelle à la position de départ pour suivre le déroulé coup par coup
	GameController.current_ply_index = -1
	GameController.game.restore_state(0)
	GameController.position_changed.emit()
	if chess_board:
		chess_board.last_move_from = -1
		chess_board.last_move_to = -1
		chess_board.best_move_arrow_from = -1
		chess_board.best_move_arrow_to = -1
		chess_board.reset_board_visuals()

	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()

	var options = {
		"mode": mode,
		"time_per_move": time_per_move,
		"dynamic_base": dynamic_base,
		"dynamic_max": dynamic_max,
		"base_depth": budget_base,
		"deep_depth": budget_deep,
		"max_deep": budget_max,
		"min_criticality": budget_crit,
		"deep_movetime_ms": 250,
		"wait_for_display": true
	}

	if OS.has_feature("web"):
		# Sur le Web (WASM/HTML5), pas de threads secondaires : analyse asynchrone non-bloquante avec await
		analyzer.start_game_analysis_async(GameController.game, a_depth, options)
	else:
		# Sur Desktop et Android, thread dédié pour préserver le framerate à 60 FPS
		analysis_thread = Thread.new()
		analysis_thread.start(func():
			analyzer.start_game_analysis(GameController.game, a_depth, options)
		)

func _on_analysis_finished(report: Dictionary) -> void:
	# Force le rafraîchissement du panneau MultiPV au retour du Live.
	_engine_lines_last_depth = -1
	_engine_lines_last_count = -1
	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()

	if analyzer:
		analyzer.is_analyzing = false
	btn_analyze_game.text = "🔍 Analyser"
	_apply_analyze_button_style(false)
	btn_toggle_live.disabled = false

	if report.has("error"):
		var err: String = report["error"]
		_show_error_banner(err)
		if live_eval_enabled:
			_trigger_live_eval()
		return

	var evals = report.get("evaluations", [])
	advantage_graph.set_evaluations(evals)
	_update_graph_phase_boundaries(report)
	var cur_ply = GameController.current_ply_index if GameController else -1
	_sync_eval_to_ply(cur_ply)

	# Rétablir l'évaluation en direct si activée, une fois le graphe et l'UI synchronisés
	if live_eval_enabled:
		_trigger_live_eval()

	# Archivage automatique dans DatabaseManager pour la partie active
	var dm = get_node_or_null("/root/DatabaseManager")
	if dm and GameController:
		var gid = GameController.get_or_create_game_id()
		if gid != "":
			var sm = get_node_or_null("/root/SettingsManager")
			var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
			var a_depth = sm.get_setting("analysis_depth", def_anal) if sm else def_anal
			var a_mode = sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"
			var analysis_entry = {
				"engine_name": EngineManager.get_engine_display_name() if EngineManager else "Stockfish",
				"depth": a_depth,
				"mode": a_mode,
				"white_accuracy": report.get("white_accuracy", 0.0),
				"black_accuracy": report.get("black_accuracy", 0.0),
				"white_estimated_elo": report.get("white_estimated_elo", 1500),
				"black_estimated_elo": report.get("black_estimated_elo", 1500),
				"white_elo_ci": report.get("white_elo_ci", 0),
				"black_elo_ci": report.get("black_elo_ci", 0),
				"elo_comparison": report.get("elo_comparison", {}),
				"white_acpl": report.get("white_acpl", 0.0),
				"black_acpl": report.get("black_acpl", 0.0),
				"white_stats": report.get("white_stats", {}),
				"black_stats": report.get("black_stats", {}),
				"schema_version": report.get("schema_version", 1),
				"opening": report.get("opening", {}),
				"theory_plies": report.get("theory_plies", 0),
				"white_phase_stats": report.get("white_phase_stats", {}),
				"black_phase_stats": report.get("black_phase_stats", {}),
				"biggest_swings": report.get("biggest_swings", []),
				"evaluations": evals
			}
			dm.add_engine_analysis(gid, analysis_entry)
			var game_rec = dm.get_game(gid)
			advantage_graph.update_stored_analyses(game_rec.get("engine_analyses", []))

	if move_list:
		move_list.set_analysis_report(report)
		move_list.refresh()
	if game_review_panel:
		game_review_panel.set_report(report)

	# Reprise automatique du Live SF19 à la position courante
	if live_eval_enabled:
		_trigger_live_eval()
