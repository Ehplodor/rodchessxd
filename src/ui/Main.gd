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
const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffMoments = preload("res://src/engine/CliffMoments.gd")
const CliffMomentsPanel = preload("res://src/ui/components/CliffMomentsPanel.gd")
const PlayerSide = preload("res://src/core/PlayerSide.gd")

@onready var main_scroll: ScrollContainer = $MainScroll
@onready var vbox: VBoxContainer = $MainScroll/VBox
@onready var top_bar: HBoxContainer = $MainScroll/VBox/TopBar
@onready var center_area: HBoxContainer = $MainScroll/VBox/CenterArea
@onready var board_column: VBoxContainer = $MainScroll/VBox/CenterArea/BoardColumn
@onready var board_container: Control = $MainScroll/VBox/CenterArea/BoardColumn/BoardContainer
@onready var nav_row: HBoxContainer = $MainScroll/VBox/NavRow
@onready var dashboard: VBoxContainer = $MainScroll/VBox/Dashboard

@onready var eval_bar: EvalBar2D = $MainScroll/VBox/CenterArea/BoardColumn/BoardContainer/EvalBar
@onready var chess_board: ChessBoard2D = $MainScroll/VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $MainScroll/VBox/Dashboard/GraphPanel/AdvantageGraph
@onready var engine_lines_panel: EngineLinesPanel2D = $MainScroll/VBox/Dashboard/EngineLinesPanel
@onready var game_review_panel: Control = get_node_or_null("AnalyseOverlay/Layout/GameReviewPanel")
@onready var move_list: MoveList2D = $AnalyseOverlay/Layout/MoveList
@onready var coach_panel: CoachPanel2D = $CoachOverlay/Layout/CoachPanel
@onready var analyse_overlay: Control = $AnalyseOverlay
@onready var coach_overlay: Control = $CoachOverlay

@onready var btn_analyze_game: Button = $MainScroll/VBox/NavRow/BtnAnalyzeGame
@onready var btn_toggle_sandbox: Button = $MainScroll/VBox/NavRow/BtnToggleSandbox
@onready var btn_toggle_live: Button = $MainScroll/VBox/NavRow/BtnToggleLive
@onready var btn_toggle_cliff: Button = $MainScroll/VBox/NavRow/BtnToggleCliff
@onready var top_eval_label: Label = $MainScroll/VBox/TopBar/EvalBadge/EvalText

var is_landscape_layout: bool = false

## Écart barre d'évaluation ↔ plateau (doit refléter ChessBoard2D.EVAL_BAR_GAP).
const EVAL_BAR_GAP := 6.0

@onready var player_top_row: MarginContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop
@onready var player_bottom_row: MarginContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom
@onready var player_dot_top: PanelContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerDotTop
@onready var player_dot_bottom: PanelContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerDotBottom
@onready var player_name_top: Label = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerNameTop
@onready var player_name_bottom: Label = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerNameBottom
@onready var turn_badge_top: PanelContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop
@onready var turn_badge_label_top: Label = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/TurnBadgeTop/TurnBadgeLabelTop
@onready var turn_badge_bottom: PanelContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom
@onready var turn_badge_label_bottom: Label = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/TurnBadgeBottom/TurnBadgeLabelBottom

@onready var player_shortcuts_top: HBoxContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerTop/PlayerTopRow/PlayerShortcutsTop
@onready var player_shortcuts_bottom: HBoxContainer = $MainScroll/VBox/CenterArea/BoardColumn/PlayerBottom/PlayerBottomRow/PlayerShortcutsBottom

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
var is_sandbox_mode: bool = false
var _sandbox_saved_pgn: String = ""
var _sandbox_saved_ply_idx: int = -1
var _sandbox_saved_game_id: String = ""
var _sandbox_saved_evals: Array = []

var error_label: Label = null
var _error_token := 0

## LeCarnet (UI 3 couches) : overlay plein écran + présentateur, câblés en code.
var carnet_overlay: Control = null
var carnet_presenter: CarnetPresenter = null

func _ready() -> void:
	DesignTokens.setup_global_fonts()
	DesignTokens.install_overflow_guard(get_tree())
	DesignTokens.guard_existing.call_deferred(self)
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
	if move_list != null and move_list.has_signal("moment_selected"):
		move_list.moment_selected.connect(func(ply):
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
	if btn_toggle_cliff != null and not btn_toggle_cliff.pressed.is_connected(_on_btn_toggle_cliff_pressed):
		btn_toggle_cliff.pressed.connect(_on_btn_toggle_cliff_pressed)
	if btn_toggle_sandbox != null and not btn_toggle_sandbox.pressed.is_connected(_on_btn_toggle_sandbox_pressed):
		btn_toggle_sandbox.pressed.connect(_on_btn_toggle_sandbox_pressed)
	if btn_analyze_game != null and not btn_analyze_game.pressed.is_connected(_on_btn_analyze_game_pressed):
		btn_analyze_game.pressed.connect(_on_btn_analyze_game_pressed)
	
	if engine_lines_panel != null:
		if engine_lines_panel.has_signal("cliff_study_requested") and not engine_lines_panel.cliff_study_requested.is_connected(_on_engine_cliff_study_requested):
			engine_lines_panel.cliff_study_requested.connect(_on_engine_cliff_study_requested)
		if engine_lines_panel.has_signal("cliff_step_preview_requested") and not engine_lines_panel.cliff_step_preview_requested.is_connected(_on_cliff_step_preview_requested):
			engine_lines_panel.cliff_step_preview_requested.connect(_on_cliff_step_preview_requested)
		if engine_lines_panel.has_signal("compare_all_lines_requested") and not engine_lines_panel.compare_all_lines_requested.is_connected(_on_engine_compare_all_lines_requested):
			engine_lines_panel.compare_all_lines_requested.connect(_on_engine_compare_all_lines_requested)
	
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
	_update_cliff_button_style()
	_update_sandbox_button_style()
	_move_graph_hud_to_engine_panel()
	_setup_cliff_dock()
	# Re-répartition dynamique dès qu'un bloc du bas change de hauteur (lignes
	# moteur dépliées/repliées, bandeaux joueurs, densité des raccourcis…).
	for layout_child in [top_bar, nav_row, dashboard, player_top_row, player_bottom_row]:
		if is_instance_valid(layout_child) \
				and not layout_child.resized.is_connected(_on_layout_child_resized):
			layout_child.resized.connect(_on_layout_child_resized)
	if is_instance_valid(main_scroll):
		DesignTokens.touch_scroll(main_scroll, [chess_board])
	_check_and_update_layout()
	call_deferred("_start_initial_eval")

## Joint un worker thread s'il est actif (toujours appelé depuis le thread principal).
func _join_thread(t: Thread) -> void:
	if t != null and t.is_started():
		t.wait_to_finish()

## Démarre une tâche lourde dans un thread dédié (Desktop/Android). Sur le Web, les
## chemins appellent les variantes async/await et n'utilisent pas ce helper.
func _start_worker(work: Callable) -> Thread:
	var t := Thread.new()
	t.start(work)
	return t

func _exit_tree() -> void:
	_flush_pending_annotations()
	if AICoach != null and AICoach.has_method("stop_speech"):
		AICoach.stop_speech()
	if analyzer != null and analyzer.is_analyzing:
		analyzer.cancel_analysis()
	_join_thread(analysis_thread)
	if cliff_analyzer != null and cliff_analyzer.is_analyzing:
		cliff_analyzer.cancel()
	_join_thread(cliff_thread)
	if _cliff_full_analyzer != null and _cliff_full_analyzer.is_analyzing:
		_cliff_full_analyzer.cancel()
	_join_thread(_cliff_full_thread)
	if _cliff_meso_analyzer != null and _cliff_meso_analyzer.is_analyzing:
		_cliff_meso_analyzer.cancel()
	_join_thread(_cliff_meso_thread)

func _notification(what: int) -> void:
	# Les barres système (gestes) peuvent apparaître/disparaître en cours de
	# partie : on recalcule les marges sûres quand l'application reprend le focus.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN \
			and (OS.has_feature("android") or OS.has_feature("ios")):
		_apply_safe_insets()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_flush_pending_annotations()
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and dm.has_method("sync_to_storage"):
			dm.sync_to_storage()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_flush_pending_annotations()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_pending_annotations()
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
		board_container.custom_minimum_size = Vector2.ZERO
		center_area.custom_minimum_size = Vector2.ZERO
		dashboard.custom_minimum_size = Vector2.ZERO
		if is_instance_valid(eval_bar):
			# Assez large pour afficher le score (ex. « -9.1 ») sans être rogné.
			eval_bar.custom_minimum_size = Vector2(30, 0)
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
			# Assez large pour afficher le score (ex. « -9.1 ») sans être rogné.
			eval_bar.custom_minimum_size = Vector2(30, 0)
		# Le plateau est l'élément central : on lui réserve en priorité la place
		# nécessaire pour atteindre la pleine largeur, le tableau de bord absorbant
		# le reste (compact au minimum sur les écrans courts, extensible au-delà).
		_update_board_priority_allocation()

	if analyse_overlay and analyse_overlay.visible:
		_dock_overlay(analyse_overlay)
	if coach_overlay and coach_overlay.visible:
		_dock_overlay(coach_overlay)

## Allocation « plateau d'abord » (portrait) : le plateau doit pouvoir atteindre la
## pleine largeur de l'écran dès que la hauteur le permet. On impose cette hauteur au
## conteneur du plateau pour ne jamais l'écraser, et MainScroll assure le défilement
## vertical complet quand les panneaux moteur ou cliff sont déroulés.
func _update_board_priority_allocation() -> void:
	if not is_inside_tree():
		return
	if is_landscape_layout:
		if is_instance_valid(board_container):
			board_container.custom_minimum_size = Vector2.ZERO
		if is_instance_valid(center_area):
			center_area.custom_minimum_size = Vector2.ZERO
		if is_instance_valid(dashboard):
			dashboard.custom_minimum_size = Vector2.ZERO
		return
	if not (is_instance_valid(vbox) and is_instance_valid(top_bar) and is_instance_valid(nav_row) \
			and is_instance_valid(dashboard) and is_instance_valid(player_top_row) \
			and is_instance_valid(player_bottom_row) and is_instance_valid(board_container) \
			and is_instance_valid(center_area)):
		return
	var sep_v := float(vbox.get_theme_constant("separation"))
	var col_sep := float(board_column.get_theme_constant("separation"))
	var top_h := _min_height(top_bar)
	var nav_h := _min_height(nav_row)
	var bands := _min_height(player_top_row) + _min_height(player_bottom_row)
	var bar_w := 0.0
	if is_instance_valid(eval_bar):
		bar_w = maxf(0.0, eval_bar.custom_minimum_size.x)
	var avail := size.y if size.y > 0.0 else (get_viewport_rect().size.y if get_viewport() else 800.0)
	if avail <= 0.0:
		return
	# Côté visé pour le plateau : toute la largeur moins (écart + barre d'éval).
	var side_target := maxf(ChessBoard2D.MIN_BOARD_SIDE, size.x - EVAL_BAR_GAP - bar_w)
	# IMPORTANT : On impose la hauteur cible au BoardContainer pour que le plateau
	# ne soit JAMAIS écrasé verticalement !
	board_container.custom_minimum_size = Vector2(0, side_target)
	var center_needed := bands + col_sep * 2.0 + side_target
	center_area.custom_minimum_size = Vector2(0, center_needed)

	var fixed := top_h + nav_h + sep_v * 3.0
	# Hauteur de CONTENU du dashboard (sans le minimum posé au passage précédent,
	# sinon il jouerait le rôle de plancher gonflé et bloquerait le plateau).
	var dash_min := _content_min_height(dashboard)
	var dash_target: float
	if fixed + dash_min + center_needed <= avail:
		# Assez de hauteur : plateau pleine largeur, le dashboard absorbe le surplus.
		dash_target = maxf(dash_min, avail - fixed - center_needed)
	else:
		# Écran court ou dashboard étendu : dashboard à sa taille naturelle/minimale.
		# Le MainScroll s'occupe de scroller verticalement l'ensemble sans rien écraser.
		dash_target = dash_min
	dashboard.custom_minimum_size = Vector2(0, dash_target)

static func _min_height(c: Control) -> float:
	if c == null or not is_instance_valid(c):
		return 0.0
	return c.get_combined_minimum_size().y

## Hauteur minimale intrinsèque d'un VBoxContainer : somme des enfants visibles
## (get_combined_minimum_size inclut custom_minimum_size du conteneur lui-même,
## ce qui fausserait la répartition — on agrège donc les enfants manuellement).
static func _content_min_height(box: VBoxContainer) -> float:
	if box == null or not is_instance_valid(box):
		return 0.0
	var sep := float(box.get_theme_constant("separation"))
	var total := 0.0
	for child in box.get_children():
		var ctrl := child as Control
		if ctrl == null or not ctrl.visible:
			continue
		if total > 0.0:
			total += sep
		total += ctrl.get_combined_minimum_size().y
	return total

## Si un bloc du bas (lignes moteur dépliées, bandeaux joueurs…) change de hauteur,
## on re-répartit pour garantir zéro débordement et un plateau toujours maximal.
func _on_layout_child_resized() -> void:
	if not is_landscape_layout:
		call_deferred("_update_board_priority_allocation")

## Transfère le HUD moteur du graphe (badge de profondeur + bascule d'analyses)
## vers l'en-tête du panneau « Ligne moteur ». C'est son emplacement naturel :
## informations du moteur regroupées avec sa sortie, aucun coût vertical (la
## rangée d'en-tête existe déjà), et surtout AUCUN risque de débordement de la
## barre du haut (le panneau occupe toute la largeur, titre extensible/tronqué).
## Idempotent (sécurisé si les nœuds manquent).
func _move_graph_hud_to_engine_panel() -> void:
	if not is_instance_valid(advantage_graph) or not is_instance_valid(engine_lines_panel):
		return
	if not engine_lines_panel.has_method("header_row"):
		return
	var host: HBoxContainer = engine_lines_panel.header_row()
	if host == null or not is_instance_valid(host):
		return
	for hud in [advantage_graph.depth_badge, advantage_graph.btn_switch_analysis]:
		if hud == null or not is_instance_valid(hud):
			continue
		if hud.get_parent() != host:
			hud.reparent(host)
		hud.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_instance_valid(advantage_graph.depth_badge):
		# La puce d'état n'a pas de largeur minimale (libellé rognable) : extensible, elle
		# prend l'espace restant de la rangée au lieu de s'effondrer ou de la faire déborder.
		advantage_graph.depth_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		advantage_graph.depth_badge.queue_redraw()

func _apply_modern_theme() -> void:
	# Fond principal de l'application
	var bg_panel = get_node_or_null("Background")
	if bg_panel:
		# Dégradé vertical : halo accent discret en haut, fond profond en bas.
		var grad := Gradient.new()
		grad.set_color(0, DesignTokens.BG_BASE.lerp(DesignTokens.ACCENT, 0.22))
		grad.set_color(1, DesignTokens.BG_DEEP)
		grad.add_point(0.35, DesignTokens.BG_BASE)
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill_from = Vector2(0.5, 0.0)
		tex.fill_to = Vector2(0.5, 1.0)
		tex.width = 4
		tex.height = 256
		var bg_style := StyleBoxTexture.new()
		bg_style.texture = tex
		bg_panel.add_theme_stylebox_override("panel", bg_style)

	var btn_normal := DesignTokens.flat(DesignTokens.BTN_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.BTN_BORDER, 1, Vector2(8, 2))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	# Barre du haut : boutons « fantômes » sans cadre, halo arrondi au survol.
	var ghost_normal := DesignTokens.flat(Color.TRANSPARENT, DesignTokens.RADIUS_MEDIUM,
			Color.TRANSPARENT, 0, Vector2(8, 2))
	var ghost_hover := ghost_normal.duplicate() as StyleBoxFlat
	ghost_hover.bg_color = Color(DesignTokens.TEXT_PRIMARY, 0.08)
	var ghost_pressed := ghost_normal.duplicate() as StyleBoxFlat
	ghost_pressed.bg_color = Color(DesignTokens.ACCENT, 0.18)
	# Rangée de navigation : pastilles pleines douces, sans liseré.
	btn_normal.border_color = Color.TRANSPARENT
	btn_normal.bg_color = Color(DesignTokens.TEXT_PRIMARY, 0.06)
	btn_hover.bg_color = Color(DesignTokens.TEXT_PRIMARY, 0.12)
	btn_hover.border_color = Color.TRANSPARENT
	btn_pressed.bg_color = Color(DesignTokens.ACCENT, 0.22)
	btn_pressed.border_color = Color.TRANSPARENT

	var font_color_normal := DesignTokens.TEXT_PRIMARY
	var font_color_hover := Color.WHITE if DesignTokens.current_theme_mode == "dark" else DesignTokens.TEXT_PRIMARY

	# Boutons de la barre du haut
	if is_instance_valid(top_bar):
		for child in top_bar.get_children():
			if child is Button:
				child.add_theme_stylebox_override("normal", ghost_normal)
				child.add_theme_stylebox_override("hover", ghost_hover)
				child.add_theme_stylebox_override("pressed", ghost_pressed)
				child.add_theme_color_override("font_color", font_color_normal)
				child.add_theme_color_override("font_hover_color", font_color_hover)
				child.add_theme_color_override("font_pressed_color", font_color_normal)
				child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Boutons de navigation sous le plateau (sauf Analyser, Live et Cliff)
	if is_instance_valid(nav_row):
		for child in nav_row.get_children():
			if child is Button and child != btn_analyze_game and child != btn_toggle_live and child != btn_toggle_cliff:
				child.add_theme_stylebox_override("normal", btn_normal)
				child.add_theme_stylebox_override("hover", btn_hover)
				child.add_theme_stylebox_override("pressed", btn_pressed)
				child.add_theme_color_override("font_color", font_color_normal)
				child.add_theme_color_override("font_hover_color", font_color_hover)
				child.add_theme_color_override("font_pressed_color", font_color_normal)
				child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	_apply_analyze_button_style(false)
	_update_live_button_style()
	_update_cliff_button_style()

	# Titre & pastille de version
	if is_instance_valid(top_bar):
		var title_lbl = top_bar.get_node_or_null("MarginContainer/TitleBox/AppTitle")
		if title_lbl:
			title_lbl.add_theme_font_size_override("font_size", 14)
			title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		var ver_lbl = top_bar.get_node_or_null("MarginContainer/TitleBox/VersionLabel")
		if ver_lbl:
			var app_version: String = str(ProjectSettings.get_setting("application/config/version", "1.1.0"))
			ver_lbl.text = "v" + app_version
			ver_lbl.add_theme_font_size_override("font_size", 10)
			ver_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		var badge = top_bar.get_node_or_null("EvalBadge")
		if badge:
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
	if is_instance_valid(main_scroll):
		main_scroll.clip_contents = true
	for ctrl in [vbox, top_bar, center_area, board_column,
			player_shortcuts_top, player_shortcuts_bottom,
			nav_row, dashboard, analyse_overlay,
			get_node_or_null("AnalyseOverlay/Layout"),
			coach_overlay,
			get_node_or_null("CoachOverlay/Layout")]:
		if ctrl is Control:
			ctrl.clip_contents = true
	# Compacité de la barre du haut : 6 boutons + titre + badge doivent tenir à 360 px.
	if is_instance_valid(top_bar):
		top_bar.add_theme_constant_override("separation", 4)
		var title_margin := top_bar.get_node_or_null("MarginContainer")
		if title_margin is MarginContainer:
			title_margin.add_theme_constant_override("margin_left", 0)
			title_margin.add_theme_constant_override("margin_right", 0)
		var eval_badge := top_bar.get_node_or_null("EvalBadge")
		if eval_badge is Control:
			eval_badge.custom_minimum_size = Vector2(44, 36)
	# Libellés dynamiques tronquables
	for label in [player_name_top, player_name_bottom,
			get_node_or_null("AnalyseOverlay/Layout/Header/Title"),
			get_node_or_null("CoachOverlay/Layout/Header/Title")]:
		if label is Label:
			label.clip_text = true
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.custom_minimum_size.x = 0
	for bar in [top_bar,
			get_node_or_null("AnalyseOverlay/Layout/Header"),
			get_node_or_null("CoachOverlay/Layout/Header")]:
		if bar == null:
			continue
		for child in bar.get_children():
			if child is Button and _has_ascii_letter(child.text):
				child.clip_text = true
				child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				child.custom_minimum_size.x = minf(child.custom_minimum_size.x, float(DesignTokens.TOUCH_MIN))
	# NavRow : « Analyser » est extensible (min 0), « Test » a une largeur garantie de 56 px,
	# « Live » garde 58 px et « Cliff » 62 px.
	if is_instance_valid(btn_analyze_game):
		btn_analyze_game.clip_text = true
		btn_analyze_game.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn_analyze_game.custom_minimum_size.x = 0
	if is_instance_valid(btn_toggle_sandbox):
		btn_toggle_sandbox.clip_text = true
		btn_toggle_sandbox.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn_toggle_sandbox.custom_minimum_size.x = 56
		_update_sandbox_button_style()
	if is_instance_valid(btn_toggle_live):
		btn_toggle_live.clip_text = false
		btn_toggle_live.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		btn_toggle_live.custom_minimum_size.x = 58
	if is_instance_valid(btn_toggle_cliff):
		btn_toggle_cliff.clip_text = false
		btn_toggle_cliff.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		btn_toggle_cliff.custom_minimum_size.x = 62
		_update_cliff_button_style()
	# Noms de joueurs : clip_text ramène leur largeur minimale à ~0 ; sans EXPAND
	# dans leur rangée, ils seraient alloués 0 px et disparaîtraient. On leur rend
	# l'espace disponible (le badge de résultat, extensible, reste calé à droite).
	if is_instance_valid(player_name_top):
		player_name_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_instance_valid(player_name_bottom):
		player_name_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	if is_sandbox_mode:
		_trigger_live_eval()
		return
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
					var cliff_rep: Dictionary = last_ea.get("cliff_data", g.get("cliff_data", {}))
					_apply_moment_markers(cliff_rep)
					if not cliff_rep.is_empty():
						_apply_cliff_data_to_moves(cliff_rep)
						move_list.set_cliff_report(cliff_rep)
					else:
						move_list.set_cliff_report({})
					move_list.refresh()
				if game_review_panel:
					game_review_panel.set_report(last_ea)
			else:
				var cliff_rep: Dictionary = g.get("cliff_data", {})
				_apply_moment_markers(cliff_rep)
				if not cliff_rep.is_empty():
					_apply_cliff_data_to_moves(cliff_rep)
					if move_list:
						move_list.set_cliff_report(cliff_rep)
				elif move_list:
					move_list.set_cliff_report({})
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
	# Plafonnée à l'écran : board_column.size.x est gonflée quand la rangée déborde
	# déjà, ce qui faisait afficher plus de raccourcis et entretenait le débordement.
	var vp_w: float = get_viewport_rect().size.x if get_viewport() else 450.0
	var available_w: float = board_column.size.x if board_column else 0.0
	if available_w <= 0.0 or available_w > vp_w:
		available_w = vp_w

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

	# Filet de sécurité mesuré : on retire d'abord des raccourcis secondaires (jusqu'à 3
	# visibles) tant que la rangée déborde avec le badge entier, puis le badge d'état
	# absorbe le dépassement restant.
	var row_avail := available_w - 16.0  # marges gauche/droite de PlayerTop/PlayerBottom
	for pair in [[player_top_row.get_node("PlayerTopRow"), turn_badge_label_top, top_shortcut_buttons],
			[player_bottom_row.get_node("PlayerBottomRow"), turn_badge_label_bottom, bottom_shortcut_buttons]]:
		var label: Label = pair[1]
		label.clip_text = false
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.custom_minimum_size.x = 0.0
		var shown: Array = (pair[2] as Array).filter(func(b): return b.visible)
		while shown.size() > 3 and DesignTokens.row_min_width(pair[0]) > row_avail:
			shown.pop_back().visible = false
	DesignTokens.fit_row(player_top_row.get_node("PlayerTopRow"), turn_badge_label_top, row_avail)
	DesignTokens.fit_row(player_bottom_row.get_node("PlayerBottomRow"), turn_badge_label_bottom, row_avail)

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
		var styles := DesignTokens.state_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(10, 2),
				Color("#7f1d1d"), Color("#ef4444"),
				Color("#991b1b"), Color("#f87171"),
				Color("#450a0a"), Color("#ef4444"))
		DesignTokens.apply_state(btn_analyze_game, styles, Color.WHITE, Color.WHITE, Color.WHITE, DesignTokens.FONT_BODY)
	else:
		var styles := DesignTokens.idle_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(10, 2),
				DesignTokens.PRIMARY_BG, DesignTokens.PRIMARY_BORDER,
				DesignTokens.PRIMARY_BG, DesignTokens.PRIMARY_BG_PRESSED,
				DesignTokens.TEXT_PRIMARY)
		DesignTokens.apply_state(btn_analyze_game, styles,
				DesignTokens.ON_PRIMARY, DesignTokens.ON_PRIMARY, DesignTokens.ON_PRIMARY, DesignTokens.FONT_BODY)

func _update_live_button_style() -> void:
	if btn_toggle_live == null:
		return
	if live_eval_enabled:
		btn_toggle_live.text = "⚡ Live"
		var styles := DesignTokens.state_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(8, 2),
				Color(0.06, 0.72, 0.51, 0.22), Color("#10b981"),
				Color(0.06, 0.72, 0.51, 0.35), Color("#34d399"),
				Color(0.06, 0.72, 0.51, 0.45), Color("#059669"))
		DesignTokens.apply_state(btn_toggle_live, styles, Color("#34d399"), Color.WHITE, Color("#10b981"), DesignTokens.FONT_BODY)
	else:
		btn_toggle_live.text = "⚡ Off"
		var styles := DesignTokens.idle_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(8, 2),
				DesignTokens.BTN_BG, DesignTokens.BTN_BORDER,
				DesignTokens.BTN_BG_HOVER, DesignTokens.BTN_BG_PRESSED)
		DesignTokens.apply_state(btn_toggle_live, styles,
				DesignTokens.TEXT_MUTED, DesignTokens.TEXT_PRIMARY, DesignTokens.TEXT_MUTED, DesignTokens.FONT_BODY)

func _update_cliff_button_style() -> void:
	if btn_toggle_cliff == null:
		return
	if is_cliff_live_active or _cliff_full_running:
		btn_toggle_cliff.text = "⏹ Stop"
		var styles := DesignTokens.state_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(6, 2),
				Color(0.40, 0.20, 0.65, 0.40), Color("#c084fc"),
				Color(0.45, 0.25, 0.70, 0.55), Color("#e9d5ff"),
				Color(0.35, 0.15, 0.60, 0.65), Color("#a855f7"))
		DesignTokens.apply_state(btn_toggle_cliff, styles, Color("#e9d5ff"), Color.WHITE, Color("#c084fc"), DesignTokens.FONT_BODY)
	else:
		btn_toggle_cliff.text = "🏔️ Cliff"
		var styles := DesignTokens.idle_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(6, 2),
				Color(0.18, 0.14, 0.28, 0.45), Color(0.45, 0.35, 0.65, 0.5),
				Color(0.24, 0.18, 0.38, 0.65), Color(0.14, 0.10, 0.22, 0.8),
				Color("#c084fc"))
		DesignTokens.apply_state(btn_toggle_cliff, styles, Color("#c084fc"), Color.WHITE, Color("#a855f7"), DesignTokens.FONT_BODY)

func _update_sandbox_button_style() -> void:
	if btn_toggle_sandbox == null:
		return
	if is_sandbox_mode:
		btn_toggle_sandbox.text = "⏯ Reprendre"
		btn_toggle_sandbox.tooltip_text = "Quitter le mode Test et revenir à la partie originale"
		var styles := DesignTokens.state_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(6, 2),
				Color(0.85, 0.55, 0.12, 0.30), Color("#f59e0b"),
				Color(0.85, 0.55, 0.12, 0.45), Color("#fbbf24"),
				Color(0.85, 0.55, 0.12, 0.60), Color("#d97706"))
		DesignTokens.apply_state(btn_toggle_sandbox, styles, Color("#fbbf24"), Color.WHITE, Color("#f59e0b"), DesignTokens.FONT_BODY)
	else:
		btn_toggle_sandbox.text = "⏸ Test"
		btn_toggle_sandbox.tooltip_text = "Mode Test (bac à sable) : tester des tactiques sans altérer la partie"
		var styles := DesignTokens.idle_styles(DesignTokens.RADIUS_SMALL, 1, Vector2(6, 2),
				DesignTokens.BTN_BG, DesignTokens.BTN_BORDER,
				DesignTokens.BTN_BG_HOVER, DesignTokens.BTN_BG_PRESSED)
		DesignTokens.apply_state(btn_toggle_sandbox, styles,
				DesignTokens.TEXT_MUTED, DesignTokens.TEXT_PRIMARY, DesignTokens.TEXT_MUTED, DesignTokens.FONT_BODY)

func _enter_sandbox_mode() -> void:
	if is_sandbox_mode:
		return
	if GameController == null or GameController.game == null:
		return
	_cancel_analysis_if_running()
	_sandbox_saved_pgn = GameController.game.export_pgn(false)
	_sandbox_saved_ply_idx = GameController.current_ply_index
	_sandbox_saved_game_id = GameController.current_game_id
	if advantage_graph != null:
		_sandbox_saved_evals = advantage_graph.evaluations.duplicate(true)
	else:
		_sandbox_saved_evals = []
	is_sandbox_mode = true
	# Vider current_game_id pour éviter tout enregistrement en BDD durant l'exploration
	GameController.current_game_id = ""
	_update_sandbox_button_style()
	_show_toast("Mode Test activé (variations libres)", true)

func _exit_sandbox_mode() -> void:
	if not is_sandbox_mode:
		return
	is_sandbox_mode = false
	if GameController and GameController.game:
		GameController.is_loading_game = true
		if _sandbox_saved_pgn != "":
			GameController.game.load_pgn(_sandbox_saved_pgn)
		GameController.current_game_id = _sandbox_saved_game_id
		GameController.is_loading_game = false
		if _sandbox_saved_ply_idx >= -1:
			GameController.navigate_to_ply(_sandbox_saved_ply_idx)
	if advantage_graph != null and not _sandbox_saved_evals.is_empty():
		advantage_graph.set_evaluations(_sandbox_saved_evals)
	_sandbox_saved_pgn = ""
	_sandbox_saved_ply_idx = -1
	_sandbox_saved_game_id = ""
	_sandbox_saved_evals = []
	_update_sandbox_button_style()
	_update_player_labels()
	var cur_ply = GameController.current_ply_index if GameController else -1
	_sync_eval_to_ply(cur_ply)
	if live_eval_enabled:
		_trigger_live_eval()
	_show_toast("Retour à la partie originale", true)

func _on_btn_toggle_sandbox_pressed() -> void:
	if is_sandbox_mode:
		_exit_sandbox_mode()
	else:
		_enter_sandbox_mode()

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
	_engine_lines_last_depth = -1
	_engine_lines_last_count = -1
	_engine_lines_last_fen = ""
	if advantage_graph != null and not advantage_graph.evaluations.is_empty():
		if ply_idx >= 0 and ply_idx < advantage_graph.evaluations.size():
			var rec: Dictionary = advantage_graph.evaluations[ply_idx]
			var score_cp: int = rec.get("score_cp", 0)
			var mate_in: int = rec.get("mate_in", 0)
			if eval_bar:
				eval_bar.set_score(score_cp, mate_in)
			if top_eval_label:
				top_eval_label.text = EvalFormatter.format_cp_mate(score_cp, mate_in)
			
			var best_uci: String = str(rec.get("best_move", ""))
			var stored_depth: int = int(rec.get("depth", 0))
			if chess_board:
				chess_board.set_best_move_arrow(best_uci, stored_depth)
			
			if engine_lines_panel:
				var target_fen = GameController.game.get_fen() if GameController and GameController.game else str(rec.get("fen", ""))
				var pv: Array = rec.get("pv_line", [])
				if pv.is_empty() and best_uci != "":
					pv = [best_uci]
				if not pv.is_empty():
					var stored_line := {
						"rank": 1,
						"depth": stored_depth,
						"score_cp": score_cp,
						"mate_in": mate_in,
						"best_move": best_uci,
						"fen": target_fen,
						"pv": pv
					}
					var eng_name := "Stockfish"
					if EngineManager and EngineManager.has_method("get_engine_display_name"):
						eng_name = EngineManager.get_engine_display_name()
					_engine_lines_last_fen = target_fen
					_engine_lines_last_depth = stored_depth
					_engine_lines_last_count = 1
					engine_lines_panel.set_lines([stored_line], eng_name, stored_depth)
		elif ply_idx == -1:
			if eval_bar:
				eval_bar.set_score(20, 0)
			if top_eval_label:
				top_eval_label.text = "+0.2"
			if chess_board:
				chess_board.set_best_move_arrow("")
			if engine_lines_panel:
				var init_line := {
					"rank": 1,
					"depth": 1,
					"score_cp": 20,
					"mate_in": 0,
					"best_move": "e2e4",
					"fen": ChessGame.INITIAL_FEN,
					"pv": ["e2e4", "e7e5"]
				}
				var eng_name := "Stockfish"
				if EngineManager and EngineManager.has_method("get_engine_display_name"):
					eng_name = EngineManager.get_engine_display_name()
				engine_lines_panel.set_lines([init_line], eng_name, 1)

	if _moment_overlay_ply != -99 and ply_idx != _moment_overlay_ply:
		_moment_overlay_ply = -99
		if chess_board != null:
			chess_board.clear_cliff_overlay()

	# Synchronisation bidirectionnelle : navigation classique -> cockpit Super-Live
	if cliff_dock != null and cliff_dock.visible:
		var plies: Array = _cliff_last_report.get("plies", [])
		if not plies.is_empty():
			if ply_idx >= 0 and ply_idx < plies.size():
				var step: Dictionary = plies[ply_idx]
				cliff_dock.highlight_step(ply_idx)
				_apply_cliff_overlay_for_step(step)
			elif ply_idx == -1:
				cliff_dock.highlight_step(-1)
				if chess_board != null:
					chess_board.clear_cliff_overlay()


func _on_play_sound(sound_type: String) -> void:
	if not SettingsManager.get_setting("sound_enabled", true):
		return
	match sound_type:
		"move": sfx_move.play()
		"capture": sfx_capture.play()
		"check": sfx_check.play()

func _on_engine_eval(score_cp: int, mate_in: int, depth: int, best_move: String, _pv: Array, multipv: Array) -> void:
	if is_cliff_live_active or _cliff_full_running:
		return
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
			if not multipv.is_empty():
				chess_board.set_engine_lines_arrows(multipv, depth)
			else:
				chess_board.set_best_move_arrow(best_move)

## Dernier état publié du panneau MultiPV (throttle par FEN + profondeur + nb de lignes).
var _engine_lines_last_depth: int = -1
var _engine_lines_last_count: int = -1
var _engine_lines_last_fen: String = ""

## T1.1 — Met à jour le panneau des lignes moteur (MultiPV).
## Throttlé (profondeur/nombre de lignes par position FEN) et ignoré pendant l'analyse de masse pour
## ne pas reconstruire les boutons à chaque ligne `info` du moteur.
func _update_engine_lines(multipv: Array, depth: int) -> void:
	if engine_lines_panel == null or multipv.is_empty():
		return
	if analyzer != null and analyzer.is_analyzing:
		return
	var line_fen := ""
	if not multipv.is_empty():
		line_fen = str(multipv[0].get("fen", ""))
	if line_fen != "" and line_fen != _engine_lines_last_fen:
		_engine_lines_last_fen = line_fen
		_engine_lines_last_depth = -1
		_engine_lines_last_count = -1
	elif depth == _engine_lines_last_depth and multipv.size() == _engine_lines_last_count:
		return
	_engine_lines_last_depth = depth
	_engine_lines_last_count = multipv.size()
	var eng_name := "Stockfish"
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

## Force l'écriture immédiate d'annotations en attente (pause, perte de focus, fermeture).
## Sans cela, une rafale de flèches suivie d'un passage en arrière-plan était perdue.
func _flush_pending_annotations() -> void:
	if _annotation_save_timer != null and not _annotation_save_timer.is_stopped():
		_annotation_save_timer.stop()
		_flush_annotation_save()

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
	GameSnapshot.apply_live_state(game, GameController.game)

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
	advantage_graph.set_phase_boundaries(GameSnapshot.phase_boundaries(report))
	advantage_graph.set_start_score(int(report.get("start_score_cp", 20)))

## T1.1 — Joue le premier coup de la ligne moteur choisie en mode Test (sandbox).
func _on_engine_line_selected(_rank: int, pv: Array, best_move: String) -> void:
	var move_uci := best_move
	if move_uci == "" and pv.size() > 0:
		move_uci = str(pv[0])
	if move_uci.length() < 4:
		return
	if chess_board != null:
		chess_board.set_best_move_arrow(move_uci)
	_play_engine_move_on_board(move_uci)

func _play_engine_move_on_board(move_uci: String) -> void:
	if GameController == null or GameController.game == null:
		return
	var found_move: ChessMove = GameController.game.find_move(move_uci)
	if found_move == null:
		return
	if not is_sandbox_mode:
		_enter_sandbox_mode()
	var played: bool = GameController.try_play_move(found_move.from_sq, found_move.to_sq, found_move.promotion)
	if played and chess_board != null:
		chess_board.set_best_move_arrow("")

# --- BANDEAU D'ERREURS À L'ÉCRAN ---

## Fabrique commune des libellés superposés (bandeau d'erreur, toast) : mêmes tokens,
## ancrage haut large, autowrap, non interactifs. Évite la duplication des deux builders.
func _make_top_overlay_label(offset_l: float, offset_r: float, top: float,
		bg: Color, border: Color, font_color: Color) -> Label:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(DesignTokens.RADIUS_MEDIUM)
	style.set_content_margin_all(10)
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_left = offset_l
	lbl.offset_right = offset_r
	lbl.offset_top = top
	lbl.offset_bottom = top
	lbl.add_theme_stylebox_override("normal", style)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", font_color)
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	lbl.hide()
	return lbl

func _build_error_banner() -> void:
	if error_label != null:
		return
	error_label = _make_top_overlay_label(16, -16, 10,
			DesignTokens.ERROR_BG, DesignTokens.DANGER, DesignTokens.ERROR_TEXT)

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
		var bg := Color(0.06, 0.72, 0.51, 0.92) if is_success else DesignTokens.SURFACE_ELEVATED
		var border := Color("#34d399") if is_success else DesignTokens.BORDER
		toast_label = _make_top_overlay_label(24, -24, 54, bg, border, Color.WHITE)
	else:
		var style: StyleBoxFlat = toast_label.get_theme_stylebox("normal")
		if style:
			style.bg_color = Color(0.06, 0.72, 0.51, 0.92) if is_success else DesignTokens.SURFACE_ELEVATED
			style.border_color = Color("#34d399") if is_success else DesignTokens.BORDER

	_toast_token += 1
	var token := _toast_token
	toast_label.text = msg
	# Hauteur adaptée au texte (multi-lignes) : jamais de message tronqué.
	toast_label.offset_bottom = toast_label.offset_top + _measure_error_height(msg)
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

## Masque toutes les vues superposées (Analyse / Coach / Carnet) : point unique évitant
## de répéter les trois affectations à chaque bascule d'overlay.
func _hide_all_overlays() -> void:
	if analyse_overlay != null:
		analyse_overlay.visible = false
	if coach_overlay != null:
		coach_overlay.visible = false
	if carnet_overlay != null:
		carnet_overlay.visible = false

func _open_analyse_overlay() -> void:
	_hide_all_overlays()
	if move_list:
		move_list.refresh()
	_show_overlay(analyse_overlay)

func _open_coach_overlay() -> void:
	_hide_all_overlays()
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
	_hide_all_overlays()
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
	_hide_all_overlays()

func close_overlays() -> void:
	_close_overlays()

## Retour à la vue principale (clic sur un coup dans l'analyse).
func show_board_tab() -> void:
	if not is_landscape_layout:
		_close_overlays()

# --- MENU « PLUS / ACTIONS » (PNG / PGN / Reset / Export / Chess.com / Aides) ---

var import_menu: PopupMenu = null
var settings_menu: PopupMenu = null

## Fabrique commune des menus déroulants (Import / Réglages) : police, fond, bordure
## et survol identiques. Évite de dupliquer la mise en thème dans les deux builders.
func _make_popup_menu(menu_name: String) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = menu_name
	menu.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	var item_style := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			Color.TRANSPARENT, 0, Vector2(14, 16))
	menu.add_theme_stylebox_override("hover", item_style)
	menu.add_theme_stylebox_override("selected", item_style)
	var panel_style := DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(4, 4))
	menu.add_theme_stylebox_override("panel", panel_style)
	menu.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	menu.add_theme_color_override("font_hover_color", DesignTokens.TEXT_PRIMARY)
	add_child(menu)
	return menu

func _build_import_menu() -> void:
	import_menu = _make_popup_menu("ImportMenu")
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
		DesignTokens.adapt_dialog(dialog)
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
	var scroll_target: Control = main_scroll if is_instance_valid(main_scroll) else vbox
	if scroll_target == null:
		return
	var win := get_window()
	if win == null or not (OS.has_feature("android") or OS.has_feature("ios")):
		scroll_target.offset_left = 0.0
		scroll_target.offset_top = 0.0
		scroll_target.offset_right = 0.0
		scroll_target.offset_bottom = 0.0
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

	scroll_target.offset_left = float(left_px) / scale_f
	scroll_target.offset_top = float(top_px) / scale_f
	scroll_target.offset_right = -float(right_px) / scale_f
	scroll_target.offset_bottom = -float(bottom_px) / scale_f
	print("M1SA win=", win_size, " safe=", safe, " cutouts=", DisplayServer.get_display_cutouts(),
			" vis=", vis, " scale=", scale_f, " insets=", Vector4(scroll_target.offset_left, scroll_target.offset_top,
			scroll_target.offset_right, scroll_target.offset_bottom))

# --- MODALES D'IMPORT & GESTION ---

var _modal_manager: ModalManager = null

func _open_modal(modal_node: Window) -> void:
	if _modal_manager == null:
		_modal_manager = ModalManager.new(self)
	_modal_manager.open(modal_node)

func _on_btn_import_png_pressed() -> void:
	_open_modal(OCREditorModal.new())

func _on_btn_import_pgn_pressed() -> void:
	_open_modal(PGNModal.new())

func _on_btn_chess_com_pressed() -> void:
	_open_modal(ChessComImportModal.new())

func _on_btn_library_pressed() -> void:
	if import_menu == null:
		_build_import_menu()
	var btn_lib = top_bar.get_node_or_null("BtnLibrary") if is_instance_valid(top_bar) else null
	if btn_lib:
		_popup_from_button(import_menu, btn_lib)

func _build_settings_menu() -> void:
	settings_menu = _make_popup_menu("SettingsMenu")
	settings_menu.add_item("⚙️  Réglages de l'application", 0)
	settings_menu.add_item("⚡  Moteurs d'échecs", 1)
	settings_menu.id_pressed.connect(_on_settings_menu_id_pressed)

func _on_settings_menu_id_pressed(id: int) -> void:
	match id:
		0: _open_modal(SettingsModal.new())
		1: _open_modal(EngineHubModal.new())

func _on_btn_settings_pressed() -> void:
	if settings_menu == null:
		_build_settings_menu()
	var btn_set = top_bar.get_node_or_null("BtnSettings") if is_instance_valid(top_bar) else null
	if btn_set:
		_popup_from_button(settings_menu, btn_set)

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
	_engine_lines_last_fen = ""
	_engine_lines_last_depth = -1
	_engine_lines_last_count = -1
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
	var def_anal := EngineAnalysisEntry.default_depth()
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

	_join_thread(analysis_thread)

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
		analysis_thread = _start_worker(func():
			analyzer.start_game_analysis(GameController.game, a_depth, options)
		)

## Archive une analyse moteur pour la partie active et rafraîchit les analyses stockées
## du graphe. Source unique pour l'analyse classique et l'analyse unifiée CHESS-CLIFF.
## `depth <= 0` : reprend la profondeur réglée dans les préférences.
func _persist_engine_analysis(report: Dictionary, evaluations: Array, depth: int,
		cliff_data: Dictionary = {}) -> void:
	var dm = get_node_or_null("/root/DatabaseManager")
	if dm == null or GameController == null:
		return
	var gid = GameController.get_or_create_game_id()
	if gid == "":
		return
	var sm = get_node_or_null("/root/SettingsManager")
	var def_anal := EngineAnalysisEntry.default_depth()
	var a_depth = sm.get_setting("analysis_depth", def_anal) if sm else def_anal
	var a_mode = sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"
	var entry := EngineAnalysisEntry.build(
			report, evaluations, depth if depth > 0 else a_depth, a_mode,
			EngineManager.get_engine_display_name() if EngineManager else "Stockfish",
			cliff_data)
	dm.add_engine_analysis(gid, entry)
	var game_rec = dm.get_game(gid)
	if advantage_graph != null:
		advantage_graph.update_stored_analyses(game_rec.get("engine_analyses", []))

func _on_analysis_finished(report: Dictionary) -> void:
	# Force le rafraîchissement du panneau MultiPV au retour du Live.
	_engine_lines_last_fen = ""
	_engine_lines_last_depth = -1
	_engine_lines_last_count = -1
	_join_thread(analysis_thread)

	if analyzer:
		analyzer.is_analyzing = false
	btn_analyze_game.text = "🔍 Analyser"
	_apply_analyze_button_style(false)
	btn_toggle_live.disabled = false

	if report.has("error"):
		var err: String = report["error"]
		_show_error_banner(err)
		if _moments_after_classic:
			_moments_after_classic = false
			if cliff_moments_panel != null:
				cliff_moments_panel.clear()
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
	_persist_engine_analysis(report, evals, 0)

	if move_list:
		move_list.set_analysis_report(report)
		move_list.refresh()
	if game_review_panel:
		game_review_panel.set_report(report)

	# Reprise automatique du Live SF19 à la position courante
	if live_eval_enabled:
		_trigger_live_eval()

	if report.has("cliff_data"):
		_apply_cliff_data_to_moves(report["cliff_data"])
		if move_list:
			move_list.set_cliff_report(report["cliff_data"])

	if _moments_after_classic:
		_moments_after_classic = false
		call_deferred("study_full_game")

## ── Intégration CHESS-CLIFF (Super Live V2.2 + analyse rétrospective) ────────
var cliff_analyzer: CliffAnalyzer = null
var cliff_thread: Thread = null
var is_cliff_live_active: bool = false

var cliff_dock: CliffLiveDock = null
var _cliff_full_running: bool = false
var _cliff_full_thread: Thread = null
var _cliff_full_analyzer: CliffAnalyzer = null
var _cliff_meso_thread: Thread = null
var _cliff_meso_analyzer: CliffAnalyzer = null
var _cliff_last_report: Dictionary = {}
var _cliff_source_meta: Dictionary = {}
var _cliff_replay_generation: int = 0
var _cliff_suspended_live: bool = false
var _cliff_prev_multipv: int = 1
var _cliff_studied_rank: int = 0
## Intervalle du rejeu Super Live (secondes par pas) — surchargeable en test.
var _cliff_replay_interval: float = 1.0
## Super-Analyse « Moments clés » (rapport cliff_version 3).
var cliff_moments_panel: CliffMomentsPanel = null
var _cliff_moments_report: Dictionary = {}
var _cliff_moments_phase: String = ""
## Super-Analyse demandée sans analyse classique : relancée à la fin de celle-ci.
var _moments_after_classic: bool = false
## Demi-coup affiché par une carte « Voir » (sa surcouche disparaît dès qu'on navigue ailleurs).
var _moment_overlay_ply: int = -99

func _setup_cliff_dock() -> void:
	if cliff_dock != null:
		return
	if engine_lines_panel == null:
		return
	cliff_dock = CliffLiveDock.new()
	engine_lines_panel.add_child(cliff_dock)
	cliff_dock.stop_requested.connect(_stop_cliff_super_live)
	cliff_dock.close_requested.connect(_close_cliff_dock)
	cliff_dock.replay_toggled.connect(_on_cliff_replay_toggled)
	cliff_dock.full_game_requested.connect(study_full_game)
	cliff_dock.step_selected.connect(_on_cliff_dock_step_selected)
	cliff_moments_panel = CliffMomentsPanel.new()
	engine_lines_panel.add_child(cliff_moments_panel)
	cliff_moments_panel.stop_requested.connect(_stop_all_cliff_analysis)
	cliff_moments_panel.close_requested.connect(_close_cliff_moments_panel)
	cliff_moments_panel.moment_selected.connect(_on_cliff_moment_selected)

func _on_cliff_dock_step_selected(idx: int, fen: String, uci: String) -> void:
	var plies: Array = _cliff_last_report.get("plies", [])
	var is_game_study: bool = not bool(_cliff_last_report.get("is_pv_line", false))
	var step: Dictionary = {}
	if idx >= 0 and idx < plies.size():
		step = plies[idx]

	if is_game_study and GameController != null and GameController.game != null:
		var hist_size: int = GameController.game.move_history.size()
		if idx >= 0 and idx < hist_size:
			GameController.navigate_to_ply(idx)
			_sync_eval_to_ply(idx)
			return

	if chess_board != null:
		if fen != "":
			chess_board.set_preview_fen(fen)
		if not step.is_empty():
			_apply_cliff_overlay_for_step(step)
		elif uci != "":
			chess_board.set_best_move_arrow(uci)
	if cliff_dock != null:
		cliff_dock.highlight_step(idx)

func _close_cliff_dock() -> void:
	if cliff_dock != null:
		cliff_dock.clear()
	if chess_board != null:
		chess_board.clear_preview_fen()
		chess_board.clear_cliff_overlay()
	_cliff_replay_generation += 1

func _on_btn_toggle_cliff_pressed() -> void:
	if _cliff_full_running or is_cliff_live_active:
		_stop_all_cliff_analysis()
		return
	# Si les moments clés de la partie existent déjà et le panneau est caché, on le réaffiche
	if not _cliff_moments_report.is_empty() and cliff_moments_panel != null and not cliff_moments_panel.visible:
		cliff_moments_panel.set_report(_cliff_moments_report, PlayerSide.resolve(GameController.game) == "white")
		return
	study_full_game()

func _on_engine_compare_all_lines_requested(lines: Array, meta: Dictionary) -> void:
	if is_cliff_live_active or _cliff_full_running:
		_stop_all_cliff_analysis()
		return
	if GameController == null or GameController.game == null:
		return
	var start_fen := GameController.game.get_fen()
	var tier := _cliff_finesse_tier()
	var envelope := ComputeFinesse.cliff_envelope_opts(tier)
	var oracle := ComputeFinesse.cliff_oracle_opts(tier)

	# Budget temps dur (Arnaud) : 250 ms par ligne max, profondeur limitée à 10 pour le meso rapide
	var opts := {
		"deep_depth": mini(10, int(oracle.get("deep_depth", 10))),
		"timeout_ms": mini(1500, int(oracle.get("timeout_ms", 1500))),
		"multipv": int(oracle.get("multipv", 3)),
		"max_plies": mini(4, int(envelope.get("max_plies", 4))),
		"line_plies": 4,
		"shallow_depth": 1,
		# Racine commune mémorisée par l'analyseur : payée une seule fois pour toutes les lignes.
		"probe_max": 4,
		"source_meta": meta
	}

	if _cliff_meso_analyzer != null and _cliff_meso_analyzer.is_analyzing:
		_cliff_meso_analyzer.cancel()

	_cliff_meso_analyzer = CliffAnalyzer.new(EngineManager)
	_cliff_meso_analyzer.single_line_analyzed.connect(func(rank: int, piste_data: Dictionary):
		call_deferred("_on_meso_single_line_ready", rank, piste_data)
	)

	_show_toast("🏔️ Comparaison cognitive des lignes en cours…", true)

	if OS.has_feature("web"):
		# Sur Web : exécution synchrone protégée
		var results: Dictionary = _cliff_meso_analyzer.analyze_multiple_lines_sync(start_fen, lines, opts)
		if is_instance_valid(engine_lines_panel):
			engine_lines_panel.set_line_pistes(results)
		_show_toast("🏔️ Comparaison cognitive des lignes terminée !", true)
	else:
		# Sur Desktop / Mobile natif : worker thread non-bloquant
		_join_thread(_cliff_meso_thread)
		_cliff_meso_thread = _start_worker(func():
			var results: Dictionary = _cliff_meso_analyzer.analyze_multiple_lines_sync(start_fen, lines, opts)
			call_deferred("_on_meso_all_lines_finished", results)
		)

func _on_meso_single_line_ready(rank: int, piste_data: Dictionary) -> void:
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_line_piste(rank, piste_data)

func _on_meso_all_lines_finished(results: Dictionary) -> void:
	_join_thread(_cliff_meso_thread)
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_line_pistes(results)
	_show_toast("🏔️ Comparaison cognitive des lignes terminée !", true)

func _on_engine_cliff_study_requested(rank: int, pv: Array, meta: Dictionary) -> void:
	if is_cliff_live_active:
		_stop_cliff_super_live()
		return
	_start_cliff_super_live(pv, meta)
	_cliff_studied_rank = rank

func _cliff_finesse_tier() -> int:
	var sm = get_node_or_null("/root/SettingsManager")
	var t := ComputeFinesse.default_tier()
	if sm != null:
		t = int(sm.get_setting("global_finesse_tier", t))
	return ComputeFinesse.effective_tier(t)

func _cliff_xray_enabled() -> bool:
	var sm = get_node_or_null("/root/SettingsManager")
	return bool(sm.get_setting("cliff_xray_enabled", false)) if sm != null else false

func _cliff_begin(meta: Dictionary) -> void:
	if cliff_moments_panel != null:
		cliff_moments_panel.visible = false
	_cliff_suspended_live = live_eval_enabled
	if EngineManager != null and EngineManager.has_method("stop_evaluation"):
		EngineManager.stop_evaluation()
	if EngineManager != null and EngineManager.has_method("set_multipv"):
		var cur = EngineManager.get("_multipv_requested")
		_cliff_prev_multipv = int(cur) if cur != null else 1
		if _cliff_prev_multipv < 2:
			EngineManager.set_multipv(2, false)
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_frozen(true)
		engine_lines_panel.set_active_line(int(meta.get("rank", 0)))
	if cliff_dock != null:
		cliff_dock.clear()
		cliff_dock.show_computing(0, 1)
		var eng := str(meta.get("engine", "SF"))
		cliff_dock.set_source_label("Source : Ligne #%d · d=%d · %s" % [
			int(meta.get("rank", 1)), int(meta.get("depth", 0)), eng])

func _cliff_end() -> void:
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_frozen(false)
		engine_lines_panel.set_active_line(0)
	if EngineManager != null and EngineManager.has_method("set_multipv") and _cliff_prev_multipv > 0:
		EngineManager.set_multipv(_cliff_prev_multipv, false)
	if chess_board != null:
		chess_board.clear_preview_fen()
		chess_board.clear_cliff_overlay()
	if _cliff_suspended_live:
		_trigger_live_eval()

func _start_cliff_super_live(pv_override: Array = [], source_meta: Dictionary = {}) -> void:
	if GameController == null or GameController.game == null:
		return
	if analyzer != null and analyzer.is_analyzing:
		_show_error_banner("Une analyse globale de la partie est déjà en cours.")
		return
	if EngineManager == null or not EngineManager.is_engine_available():
		_show_error_banner("Moteur Stockfish non disponible.")
		return

	var start_fen := GameController.game.get_fen()
	var pv_moves: Array = pv_override.duplicate()
	if pv_moves.is_empty() and is_instance_valid(engine_lines_panel) and not engine_lines_panel._lines.is_empty():
		pv_moves = (engine_lines_panel._lines[0] as Dictionary).get("pv", []).duplicate()
	if pv_moves.is_empty():
		_show_error_banner("Aucune ligne moteur disponible : lancez une évaluation Live.")
		if is_instance_valid(engine_lines_panel):
			engine_lines_panel.set_loading_state(true)
		return

	var meta := source_meta.duplicate()
	meta["fen"] = start_fen
	if not meta.has("rank"):
		meta["rank"] = 1
	_cliff_source_meta = meta
	_cliff_studied_rank = int(meta.get("rank", 1))
	_cliff_last_report = {}

	is_cliff_live_active = true
	_update_cliff_button_style()
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_cliff_active(true)
	_cliff_begin(meta)
	_show_toast("🏔️ Super Live : calcul de difficulté cognitive…", true)

	var tier := _cliff_finesse_tier()
	var oracle := ComputeFinesse.cliff_oracle_opts(tier)
	var envelope := ComputeFinesse.cliff_envelope_opts(tier)
	var intuition := ComputeFinesse.cliff_intuition_opts(tier)
	var opts := {
		"deep_depth": int(oracle.get("deep_depth", 16)),
		"timeout_ms": int(oracle.get("timeout_ms", 3000)),
		"multipv": int(oracle.get("multipv", 3)),
		"max_plies": int(envelope.get("max_plies", 8)),
		"shallow_depth": int(intuition.get("shallow_depth", 1)),
		"source_meta": meta
	}

	cliff_analyzer = CliffAnalyzer.new(EngineManager)
	cliff_analyzer.progress.connect(func(cur: int, tot: int):
		call_deferred("_on_cliff_super_live_progress", cur, tot)
	)
	cliff_analyzer.step_analyzed.connect(func(idx: int, uci: String, fen: String, data: Dictionary):
		call_deferred("_on_cliff_super_live_step", idx, uci, fen, data)
	)

	if OS.has_feature("web"):
		var rep = cliff_analyzer.analyze_pv_line(start_fen, pv_moves, opts)
		_on_cliff_super_live_finished(rep)
	else:
		_join_thread(cliff_thread)
		cliff_thread = _start_worker(func():
			var rep = cliff_analyzer.analyze_pv_line(start_fen, pv_moves, opts)
			call_deferred("_on_cliff_super_live_finished", rep)
		)

func _on_cliff_super_live_progress(cur: int, tot: int) -> void:
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_cliff_progress(cur, tot)
	if cliff_dock != null:
		cliff_dock.show_computing(cur, tot)

func _on_cliff_super_live_step(_idx: int, uci: String, fen_after: String, data: Dictionary) -> void:
	if not is_cliff_live_active:
		return
	# Aperçu non destructif : jamais d'altération de GameController.game.
	if chess_board != null and fen_after != "":
		chess_board.set_preview_fen(fen_after)
		_apply_cliff_overlay_for_step(data)
	if cliff_dock != null:
		cliff_dock.set_step(data)

func _apply_cliff_overlay_for_step(step: Dictionary) -> void:
	if chess_board == null:
		return
	var visual := CliffAnnotations.build_step_visual(step, _cliff_xray_enabled())
	var overlay: Dictionary = visual.get("overlay", {})
	if overlay.is_empty():
		var focus_u: String = str(visual.get("best_uci", ""))
		if focus_u != "":
			chess_board.set_best_move_arrow(focus_u)
		return
	chess_board.set_cliff_overlay(overlay)

func _on_cliff_super_live_finished(report: Dictionary) -> void:
	_join_thread(cliff_thread)

	is_cliff_live_active = false
	_update_cliff_button_style()
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_cliff_active(false)
	_cliff_end()
	if chess_board != null:
		chess_board.clear_preview_fen()
		chess_board.clear_cliff_overlay()

	if report.has("error"):
		_show_error_banner(str(report["error"]))
		return

	_cliff_last_report = report
	if cliff_dock != null:
		cliff_dock.set_report(report)

	# Badge de piste sur la ligne étudiée.
	if is_instance_valid(engine_lines_panel):
		var is_white_turn := true
		if GameController and GameController.game:
			is_white_turn = (GameController.game.active_color == ChessPiece.PieceColor.WHITE)
		engine_lines_panel.set_line_pistes({
			_cliff_studied_rank: CliffAnnotations.line_piste_summary(report, is_white_turn)
		})
		var best_u := CliffAnnotations.first_step_uci(report)
		if best_u != "" and chess_board != null:
			chess_board.set_best_move_arrow(best_u)

	_show_toast("🏔️ Étude Cliff de la ligne terminée !", true)

func _stop_cliff_super_live() -> void:
	_stop_all_cliff_analysis()

func _stop_all_cliff_analysis() -> void:
	if _moments_after_classic:
		_moments_after_classic = false
		_cancel_analysis_if_running()
	if cliff_moments_panel != null and (_cliff_full_running or not cliff_moments_panel.has_report()):
		cliff_moments_panel.clear()
	if cliff_analyzer != null and cliff_analyzer.is_analyzing:
		cliff_analyzer.cancel()
	if _cliff_full_analyzer != null and _cliff_full_analyzer.is_analyzing:
		_cliff_full_analyzer.cancel()
	if _cliff_meso_analyzer != null and _cliff_meso_analyzer.is_analyzing:
		_cliff_meso_analyzer.cancel()
	_cliff_replay_generation += 1
	is_cliff_live_active = false
	_cliff_full_running = false
	_update_cliff_button_style()
	if is_instance_valid(engine_lines_panel):
		engine_lines_panel.set_cliff_active(false)
		engine_lines_panel.set_frozen(false)
	_cliff_end()
	if cliff_dock != null:
		cliff_dock.clear()
	if chess_board != null:
		chess_board.clear_preview_fen()
		chess_board.clear_cliff_overlay()
	_show_toast("Analyse cognitive interrompue", true)

func _on_cliff_step_preview_requested(fen: String, uci: String) -> void:
	# Aperçu d'une position de la ligne Cliff sans altérer la partie réelle.
	if chess_board == null:
		return
	if fen != "":
		chess_board.set_preview_fen(fen)
	var step := _find_cliff_step(uci, fen)
	if not step.is_empty():
		_apply_cliff_overlay_for_step(step)
	elif uci != "":
		chess_board.set_best_move_arrow(uci)

func _find_cliff_step(uci: String, fen: String) -> Dictionary:
	return CliffAnnotations.find_step(_cliff_last_report.get("plies", []), uci, fen)

## Rejeu pas-à-pas (1 s/pas) sur l'échiquier, non destructif.
func _on_cliff_replay_toggled(playing: bool) -> void:
	if not playing:
		_cliff_replay_generation += 1
		return
	var plies: Array = _cliff_last_report.get("plies", [])
	if plies.is_empty():
		return
	_cliff_replay_generation += 1
	var gen := _cliff_replay_generation
	for i in range(plies.size()):
		if gen != _cliff_replay_generation or not is_instance_valid(self):
			return
		var step: Dictionary = plies[i]
		if chess_board != null:
			chess_board.set_preview_fen(str(step.get("fen_after", "")))
			_apply_cliff_overlay_for_step(step)
		if cliff_dock != null:
			cliff_dock.highlight_step(i)
		await get_tree().create_timer(_cliff_replay_interval).timeout
	if gen == _cliff_replay_generation:
		if cliff_dock != null:
			cliff_dock.stop_replay()
		if chess_board != null:
			chess_board.clear_preview_fen()
			chess_board.clear_cliff_overlay()

## Super-Analyse « Moments clés » : analyse classique (réutilisée ou lancée d'abord),
## criblage MultiPV 2 peu profond de chaque coup, puis Cliff sur les seuls candidats.
func study_full_game() -> void:
	if _cliff_full_running or is_cliff_live_active:
		return
	if analyzer != null and analyzer.is_analyzing:
		return
	if GameController == null or GameController.game == null:
		return
	if GameController.game.move_history.is_empty():
		_show_error_banner("Aucun coup à analyser.")
		return
	if EngineManager == null or not EngineManager.is_engine_available():
		_show_error_banner("Moteur Stockfish non disponible.")
		return

	var n_moves := GameController.game.move_history.size()
	if cliff_dock != null:
		cliff_dock.clear()
	if cliff_moments_panel != null:
		cliff_moments_panel.clear()
		cliff_moments_panel.visible = true

	# Les moments clés s'appuient sur l'analyse classique : on la lance d'abord si besoin,
	# puis _on_analysis_finished rappelle study_full_game.
	if not _has_classic_evals():
		_moments_after_classic = true
		if cliff_moments_panel != null:
			cliff_moments_panel.show_progress("Analyse classique…", 0, n_moves)
		_on_btn_analyze_game_pressed()
		return

	_cliff_suspended_live = live_eval_enabled
	var tier := _cliff_finesse_tier()
	var gopts := ComputeFinesse.game_analysis_opts(tier)
	var intuition := ComputeFinesse.cliff_intuition_opts(tier)
	var oracle := ComputeFinesse.cliff_oracle_opts(tier)
	var opts := {
		"deep_depth": int(gopts.get("depth", 14)),
		"shallow_depth": int(intuition.get("shallow_depth", 1)),
		"timeout_ms": int(oracle.get("timeout_ms", 4000)),
		"multipv": int(oracle.get("multipv", 3))
	}
	var evals: Array = advantage_graph.evaluations.duplicate(true)
	var theory_plies := 0
	while theory_plies < evals.size() and bool(evals[theory_plies].get("is_theory", false)):
		theory_plies += 1

	_cliff_full_running = true
	_update_cliff_button_style()
	if EngineManager != null and EngineManager.has_method("stop_evaluation"):
		EngineManager.stop_evaluation()
	_cliff_moments_phase = "Tri des coups…"
	if cliff_moments_panel != null:
		cliff_moments_panel.show_progress(_cliff_moments_phase, 0, n_moves)

	_cliff_full_analyzer = CliffAnalyzer.new(EngineManager)
	_cliff_full_analyzer.progress.connect(func(cur: int, tot: int):
		call_deferred("_on_cliff_full_progress", cur, tot)
	)
	var an := _cliff_full_analyzer
	var game_ref = GameController.game
	var work := func():
		var gaps: Dictionary = an.screen_plies(game_ref, theory_plies)
		var cands: Array = [] if an.cancel_requested else CliffMoments.select_candidates(evals, gaps)
		_cliff_moments_phase = "Analyse des moments…"
		var cliff: Dictionary = {} if an.cancel_requested else an.analyze_plies(game_ref, cands, opts)
		return CliffMoments.build_report(evals, gaps, cands, cliff, an.cancel_requested)
	if OS.has_feature("web"):
		_on_cliff_full_finished(work.call())
	else:
		_join_thread(_cliff_full_thread)
		_cliff_full_thread = _start_worker(func():
			call_deferred("_on_cliff_full_finished", work.call())
		)

## Vrai si l'analyse classique complète de la partie courante est affichée.
func _has_classic_evals() -> bool:
	if advantage_graph == null or GameController == null or GameController.game == null:
		return false
	var evals: Array = advantage_graph.evaluations
	var n := GameController.game.move_history.size()
	if evals.size() < n or n == 0:
		return false
	for e in evals:
		if not (e is Dictionary) or bool(e.get("is_placeholder", false)):
			return false
	return true

func _on_cliff_full_progress(cur: int, tot: int) -> void:
	if cliff_moments_panel != null and _cliff_full_running:
		cliff_moments_panel.show_progress(_cliff_moments_phase, cur, tot)

func _on_cliff_full_finished(report: Dictionary) -> void:
	_join_thread(_cliff_full_thread)
	_cliff_full_running = false
	_update_cliff_button_style()
	if _cliff_suspended_live:
		_trigger_live_eval()
	if bool(report.get("cancelled", false)):
		if cliff_moments_panel != null:
			cliff_moments_panel.clear()
		return

	_cliff_moments_report = report
	var hero_white := PlayerSide.resolve(GameController.game) == "white"
	if cliff_moments_panel != null:
		cliff_moments_panel.set_report(report, hero_white)
	if advantage_graph != null:
		advantage_graph.set_moment_markers(CliffMoments.markers(report))
	_apply_cliff_data_to_moves(report)
	if move_list:
		move_list.set_cliff_report(report)
	_archive_cliff_report(report)
	var n := (report.get("moments", []) as Array).size()
	_show_toast("🏔️ %d moment%s clé%s trouvé%s" % [n, "s" if n > 1 else "", "s" if n > 1 else "", "s" if n > 1 else ""], true)

## Carte « Voir » : position AVANT le coup, flèches (bon coup, appât) et cases piégées.
func _on_cliff_moment_selected(moment: Dictionary) -> void:
	if GameController == null or GameController.game == null:
		return
	var ply := int(moment.get("ply", 0))
	GameController.navigate_to_ply(ply - 1)
	_sync_eval_to_ply(ply - 1)
	if chess_board == null:
		return
	var step: Dictionary = {}
	for p in _cliff_moments_report.get("plies", []):
		if int(p.get("ply", -1)) == ply:
			step = p
			break
	var visual := CliffAnnotations.build_step_visual(step, true) if not step.is_empty() else {}
	var overlay: Dictionary = visual.get("overlay", {})
	if overlay.is_empty():
		chess_board.set_best_move_arrow(str(moment.get("best_uci", "")))
		return
	overlay["label"] = "%s %s" % [str(moment.get("icon", "")), str(moment.get("title", ""))]
	if str(moment.get("bait_uci", "")) == "":
		overlay["bait_uci"] = ""
	chess_board.set_cliff_overlay(overlay)
	_moment_overlay_ply = ply - 1

func _close_cliff_moments_panel() -> void:
	if cliff_moments_panel != null:
		cliff_moments_panel.visible = false
	if chess_board != null:
		chess_board.clear_cliff_overlay()
	_moment_overlay_ply = -99

## Fanions du graphe pour le rapport Cliff archivé de la partie affichée (v3 seulement).
func _apply_moment_markers(cliff_rep: Dictionary) -> void:
	if advantage_graph == null:
		return
	if int(cliff_rep.get("cliff_version", 0)) >= 3:
		_cliff_moments_report = cliff_rep
		advantage_graph.set_moment_markers(CliffMoments.markers(cliff_rep))
	else:
		_cliff_moments_report = {}
		advantage_graph.set_moment_markers([])

## Persiste le rapport au niveau de la partie (lu par _on_game_position_changed).
func _archive_cliff_report(report: Dictionary) -> void:
	var dm = get_node_or_null("/root/DatabaseManager")
	if dm == null or GameController == null:
		return
	var gid = GameController.get_or_create_game_id()
	if gid == "":
		return
	var g = dm.get_game(gid)
	if g.is_empty():
		return
	g["cliff_data"] = report
	dm.save_game(g)

## Sémantique canonique CHESS-CLIFF V2.3 : chaque entrée plies[t] est évaluée dans fen_before
## et correspond directement au coup joué history[t] (effort consenti pour trouver le coup).
func _apply_cliff_data_to_moves(cliff_report: Dictionary) -> void:
	if GameController == null or GameController.game == null:
		return
	CliffAnnotations.apply_to_moves(GameController.game.move_history, cliff_report)
