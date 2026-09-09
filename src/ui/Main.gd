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

@onready var vbox: VBoxContainer = $VBox
@onready var top_bar: HBoxContainer = $VBox/TopBar
@onready var center_area: HBoxContainer = $VBox/CenterArea
@onready var board_column: VBoxContainer = $VBox/CenterArea/BoardColumn
@onready var board_container: AspectRatioContainer = $VBox/CenterArea/BoardColumn/BoardContainer
@onready var nav_row: HBoxContainer = $VBox/NavRow
@onready var dashboard: VBoxContainer = $VBox/Dashboard

@onready var eval_bar: EvalBar2D = $VBox/CenterArea/EvalBar
@onready var chess_board: ChessBoard2D = $VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $VBox/Dashboard/GraphPanel/AdvantageGraph
@onready var move_list: MoveList2D = $AnalyseOverlay/Layout/MoveList
@onready var coach_panel: CoachPanel2D = $CoachOverlay/Layout/CoachPanel
@onready var analyse_overlay: Control = $AnalyseOverlay
@onready var coach_overlay: Control = $CoachOverlay

@onready var stats_panel: PanelContainer = $VBox/Dashboard/StatsPanel
@onready var stats_grid: HBoxContainer = $VBox/Dashboard/StatsPanel/StatsVBox/StatsGrid
@onready var label_white_stats: Label = $VBox/Dashboard/StatsPanel/StatsVBox/StatsGrid/ColPlayers/LabelWhiteStats
@onready var label_black_stats: Label = $VBox/Dashboard/StatsPanel/StatsVBox/StatsGrid/ColPlayers/LabelBlackStats
@onready var label_delta: Label = $VBox/Dashboard/StatsPanel/StatsVBox/StatsGrid/ColDelta/DeltaBox/LabelDelta
@onready var label_pvalue: Label = $VBox/Dashboard/StatsPanel/StatsVBox/StatsGrid/ColDelta/DeltaBox/LabelPValue
@onready var stats_label: Label = $VBox/Dashboard/StatsPanel/StatsVBox/StatsLabel

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

@onready var sfx_move: AudioStreamPlayer = $Sounds/SfxMove
@onready var sfx_capture: AudioStreamPlayer = $Sounds/SfxCapture
@onready var sfx_check: AudioStreamPlayer = $Sounds/SfxCheck

var analyzer: GameAnalyzer
var analysis_thread: Thread = null
var live_eval_enabled: bool = true

var error_label: Label = null
var _error_token := 0

func _ready() -> void:
	DesignTokens.setup_global_fonts()
	analyzer = GameAnalyzer.new()
	analyzer.analysis_finished.connect(_on_analysis_finished)
	analyzer.progress_updated.connect(_on_analysis_progress)
	analyzer.analysis_position_ready.connect(_on_analysis_position_ready)
	analyzer.ply_analyzed.connect(_on_ply_analyzed)
	if chess_board and not chess_board.navigation_forward_completed.is_connected(_on_analysis_navigation_completed):
		chess_board.navigation_forward_completed.connect(_on_analysis_navigation_completed)
	
	GameController.play_sound_requested.connect(_on_play_sound)
	GameController.position_changed.connect(_on_game_position_changed)
	GameController.move_navigated.connect(func(ply_idx):
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

	if btn_toggle_live != null and not btn_toggle_live.pressed.is_connected(_on_btn_toggle_live_pressed):
		btn_toggle_live.pressed.connect(_on_btn_toggle_live_pressed)
	if btn_analyze_game != null and not btn_analyze_game.pressed.is_connected(_on_btn_analyze_game_pressed):
		btn_analyze_game.pressed.connect(_on_btn_analyze_game_pressed)
	
	var slm = get_node_or_null("/root/LocalSLMManager")
	if slm:
		slm.server_error.connect(_show_error_banner)
	
	_build_error_banner()
	_apply_modern_theme()
	_build_import_menu()
	if OS.has_feature("android") or OS.has_feature("ios"):
		get_window().size_changed.connect(_apply_safe_insets)
		_apply_safe_insets()
	_update_player_labels()
	_update_live_button_style()
	_check_and_update_layout()
	call_deferred("_start_initial_eval")

func _exit_tree() -> void:
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
	var btn_normal := DesignTokens.flat(DesignTokens.BTN_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.BTN_BORDER, 1, Vector2(8, 2))
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = DesignTokens.BTN_BG_HOVER
	btn_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	btn_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	var tile_normal := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BTN_BORDER, 1, Vector2(12, 4))
	var tile_hover := tile_normal.duplicate() as StyleBoxFlat
	tile_hover.bg_color = DesignTokens.BTN_BG_HOVER
	tile_hover.border_color = DesignTokens.BTN_BORDER_ACTIVE
	var tile_pressed := tile_normal.duplicate() as StyleBoxFlat
	tile_pressed.bg_color = DesignTokens.BTN_BG_PRESSED
	tile_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE

	var font_color_normal := DesignTokens.TEXT_PRIMARY
	var font_color_hover := Color.WHITE

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

	# Titre & badge d'évaluation
	$VBox/TopBar/MarginContainer/AppTitle.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	$VBox/TopBar/MarginContainer/AppTitle.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
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

	# Panneau des statistiques (grille 2x2 et libellé d'état)
	if stats_panel:
		var panel_style := DesignTokens.flat(
			DesignTokens.SURFACE_ELEVATED,
			DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER,
			1,
			Vector2(10, 6)
		)
		stats_panel.add_theme_stylebox_override("panel", panel_style)

	if label_white_stats:
		label_white_stats.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		label_white_stats.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	if label_black_stats:
		label_black_stats.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		label_black_stats.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	if label_delta:
		label_delta.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
		label_delta.add_theme_color_override("font_color", Color("#38bdf8"))
	if label_pvalue:
		label_pvalue.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
		label_pvalue.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)

	if stats_label:
		stats_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		stats_label.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Tuiles Analyse / Coach
	for child in $VBox/Dashboard/Tiles.get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", tile_normal)
			child.add_theme_stylebox_override("hover", tile_hover)
			child.add_theme_stylebox_override("pressed", tile_pressed)
			child.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", DesignTokens.TEXT_PRIMARY)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Vues superposées : titres + boutons de fermeture
	for overlay in [analyse_overlay, coach_overlay]:
		if overlay == null or not overlay.has_node("Layout/Header"):
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

func _on_game_position_changed() -> void:
	_update_player_labels()
	if GameController.game.move_history.is_empty():
		advantage_graph.set_evaluations([])
		advantage_graph.update_stored_analyses([])
		if stats_grid:
			stats_grid.visible = false
		if stats_label:
			stats_label.text = "Position de départ prête. Touchez « Analyser » sous le plateau."
	else:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and GameController.current_game_id != "":
			var g = dm.get_game(GameController.current_game_id)
			var ea = g.get("engine_analyses", [])
			advantage_graph.update_stored_analyses(ea)
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
		if stats_label and not (analyzer and analyzer.is_analyzing):
			var winner_label = white_name if checkmate_winner_is_white else black_name
			stats_label.text = "🏁 Fin de partie : Échec et mat ! %s l'emporte." % winner_label
	elif is_stalemate:
		_style_status_badge(turn_badge_top, turn_badge_label_top, "🤝 Nulle • Pat", "draw")
		_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🤝 Nulle • Pat", "draw")
		if stats_label and not (analyzer and analyzer.is_analyzing):
			stats_label.text = "🏁 Fin de partie : Nulle par pat."
	elif at_last_ply and pgn_result in ["1-0", "0-1", "1/2-1/2", "0.5-0.5"]:
		if pgn_result == "1-0":
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🏆 1-0 • Gagné" if top_side_white else "💀 0-1 • Perdu", "winner" if top_side_white else "loser")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🏆 1-0 • Gagné" if bottom_side_white else "💀 0-1 • Perdu", "winner" if bottom_side_white else "loser")
			if stats_label and not (analyzer and analyzer.is_analyzing):
				stats_label.text = "🏁 Fin de partie : Victoire de %s (1-0)." % white_name
		elif pgn_result == "0-1":
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🏆 0-1 • Gagné" if not top_side_white else "💀 1-0 • Perdu", "winner" if not top_side_white else "loser")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🏆 0-1 • Gagné" if not bottom_side_white else "💀 1-0 • Perdu", "winner" if not bottom_side_white else "loser")
			if stats_label and not (analyzer and analyzer.is_analyzing):
				stats_label.text = "🏁 Fin de partie : Victoire de %s (0-1)." % black_name
		else:
			_style_status_badge(turn_badge_top, turn_badge_label_top, "🤝 ½ - ½ • Nulle", "draw")
			_style_status_badge(turn_badge_bottom, turn_badge_label_bottom, "🤝 ½ - ½ • Nulle", "draw")
			if stats_label and not (analyzer and analyzer.is_analyzing):
				stats_label.text = "🏁 Fin de partie : Nulle convenue (½ - ½)."
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

func _clip_player_name(name: String, max_chars := 24) -> String:
	if name.length() <= max_chars:
		return name
	return name.substr(0, max_chars - 1) + "…"

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
			chess_board.best_move_arrow_from = -1
			chess_board.best_move_arrow_to = -1
			if chess_board.arrow_overlay:
				chess_board.arrow_overlay.queue_redraw()
			chess_board.queue_redraw()
		if top_eval_label:
			top_eval_label.text = "Live off"

func _display_analysis_stats(report_or_entry: Dictionary, is_partial: bool = false) -> void:
	if stats_grid == null:
		return

	var w_acc: float = float(report_or_entry.get("white_accuracy", 0.0))
	var b_acc: float = float(report_or_entry.get("black_accuracy", 0.0))
	var w_elo: int = int(report_or_entry.get("white_estimated_elo", 1500))
	var b_elo: int = int(report_or_entry.get("black_estimated_elo", 1500))
	var w_ci: int = int(report_or_entry.get("white_elo_ci", 0))
	var b_ci: int = int(report_or_entry.get("black_elo_ci", 0))
	var comp: Dictionary = report_or_entry.get("elo_comparison", {})
	var stars: String = comp.get("stars", "ns")
	var p_val: float = float(comp.get("p_value", 1.0))
	var diff_elo: int = int(comp.get("diff_elo", w_elo - b_elo))

	var w_ci_str = " ±%d" % w_ci if w_ci > 0 else ""
	var b_ci_str = " ±%d" % b_ci if b_ci > 0 else ""

	# L1C1 : Blancs
	if label_white_stats:
		label_white_stats.text = "⚪ Blancs : %.1f%%  •  %d%s ELO" % [w_acc, w_elo, w_ci_str]
	# L2C1 : Noirs
	if label_black_stats:
		label_black_stats.text = "⚫ Noirs  : %.1f%%  •  %d%s ELO" % [b_acc, b_elo, b_ci_str]

	# Colonne 2 (1/3 droite, centrée) : Δ ELO en haut, p-value + significativité en bas
	if label_delta:
		label_delta.text = "Δ %+d ELO" % diff_elo
	if label_pvalue:
		var p_str = "p < 0.001" if p_val < 0.001 else "p=%.3f" % p_val
		label_pvalue.text = "%s %s" % [p_str, stars]

	stats_grid.visible = true

	var total_moves = GameController.game.move_history.size() / 2 if GameController.game else 0
	var short_sample = " • [Échantillon court]" if total_moves < 12 else ""
	if is_partial:
		var count = report_or_entry.get("evaluations", []).size()
		stats_label.text = "⏹ Analyse arrêtée (%d demi-coups) • Données partielles conservées." % count
	else:
		stats_label.text = "Analyse complète SF19 terminée.%s" % short_sample

func _on_stored_analysis_selected(analysis_entry: Dictionary) -> void:
	_display_analysis_stats(analysis_entry, false)
	if move_list:
		move_list.set_analysis_report(analysis_entry)
		move_list.refresh()
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
				if mate_in != 0:
					top_eval_label.text = "Mat %d" % mate_in
				else:
					var pawns = score_cp / 100.0
					top_eval_label.text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns
			
			var best_uci: String = rec.get("best_move", "")
			if chess_board:
				chess_board.best_move_arrow_depth = int(rec.get("depth", 0))
				if best_uci.length() >= 4:
					chess_board.best_move_arrow_from = ChessMove.coord_to_square(best_uci.substr(0, 2))
					chess_board.best_move_arrow_to = ChessMove.coord_to_square(best_uci.substr(2, 2))
				else:
					chess_board.best_move_arrow_from = -1
					chess_board.best_move_arrow_to = -1
				if chess_board.arrow_overlay:
					chess_board.arrow_overlay.queue_redraw()
				chess_board.queue_redraw()
		elif ply_idx == -1:
			if eval_bar:
				eval_bar.set_score(20, 0)
			if top_eval_label:
				top_eval_label.text = "+0.2"
			if chess_board:
				chess_board.best_move_arrow_depth = 0
				chess_board.best_move_arrow_from = -1
				chess_board.best_move_arrow_to = -1
				if chess_board.arrow_overlay:
					chess_board.arrow_overlay.queue_redraw()
				chess_board.queue_redraw()

func _on_play_sound(sound_type: String) -> void:
	if not SettingsManager.get_setting("sound_enabled", true):
		return
	match sound_type:
		"move": sfx_move.play()
		"capture": sfx_capture.play()
		"check": sfx_check.play()

func _on_engine_eval(score_cp: int, mate_in: int, depth: int, best_move: String, _pv: Array, _multipv: Array) -> void:
	if analyzer != null and analyzer.is_analyzing:
		if top_eval_label:
			if mate_in != 0:
				top_eval_label.text = "Mat %d" % mate_in
			else:
				var pawns = score_cp / 100.0
				top_eval_label.text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns
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
			if mate_in != 0:
				top_eval_label.text = "Mat %d" % mate_in
			else:
				var pawns = score_cp / 100.0
				top_eval_label.text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns

		if eval_bar:
			eval_bar.set_score(score_cp, mate_in)

		if chess_board:
			if best_move.length() >= 4:
				chess_board.best_move_arrow_from = ChessMove.coord_to_square(best_move.substr(0, 2))
				chess_board.best_move_arrow_to = ChessMove.coord_to_square(best_move.substr(2, 2))
			else:
				chess_board.best_move_arrow_from = -1
				chess_board.best_move_arrow_to = -1
			if chess_board.arrow_overlay:
				chess_board.arrow_overlay.queue_redraw()
			chess_board.queue_redraw()

	if live_eval_enabled and stats_label and stats_grid and (not stats_grid.visible):
		var eng_name = EngineManager.get_engine_display_name() if EngineManager else "Stockfish"
		var pawns_val = score_cp / 100.0
		var eval_str = ("Mat %d" % mate_in) if mate_in != 0 else (("%+0.1f" if pawns_val >= 0 else "%.1f") % pawns_val)
		var best_str = best_move if best_move != "" else "—"
		stats_label.text = "⚡ %s live (prof. %d) : Eval %s • Coup : %s" % [eng_name, depth, eval_str, best_str]

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
	GameController.go_first_move()

func _on_btn_prev_pressed() -> void:
	GameController.go_previous_move()

func _on_btn_next_pressed() -> void:
	GameController.go_next_move()

func _on_btn_last_pressed() -> void:
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

func _show_overlay(overlay: Control) -> void:
	_dock_overlay(overlay)
	overlay.visible = true
	move_child(overlay, get_child_count() - 1)

func _close_overlays() -> void:
	analyse_overlay.visible = false
	coach_overlay.visible = false

## Retour à la vue principale (clic sur un coup dans l'analyse).
func show_board_tab() -> void:
	if not is_landscape_layout:
		_close_overlays()

# --- MENU « PLUS / ACTIONS » (PNG / PGN / Reset / Export / Chess.com / Aides) ---

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
	import_menu.add_item("🖼️  Photo du plateau (PNG)", 0)
	import_menu.add_item("📄  Fichier / texte PGN", 1)
	import_menu.add_item("🌐  Synchroniser Chess.com", 2)
	import_menu.add_separator("Partie")
	import_menu.add_item("📋  Exporter le PGN (Copier)", 3)
	import_menu.add_item("✨  Nouvelle partie (Reset)", 4)
	import_menu.add_separator("Affichage")
	import_menu.add_item("🎯  Aides de coups (ON/OFF)", 5)
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

func _export_pgn() -> void:
	if GameController == null or GameController.game == null:
		_show_error_banner("Aucune partie à exporter.")
		return
	var pgn_text: String = GameController.game.export_pgn()
	DisplayServer.clipboard_set(pgn_text)
	var pgn_modal := PGNModal.new()
	pgn_modal.set_export_mode(pgn_text)
	_open_modal(pgn_modal)
	_show_toast("PGN copié dans le presse-papiers !")

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
	GameController.reset_to_initial()
	advantage_graph.set_evaluations([])
	advantage_graph.update_stored_analyses([])
	if stats_grid:
		stats_grid.visible = false
	if stats_label:
		stats_label.text = "Nouvelle partie commencée. Échiquier réinitialisé."
	if eval_bar:
		eval_bar.set_score(20, 0)
	if top_eval_label:
		top_eval_label.text = "+0.2"
	if chess_board:
		chess_board.last_move_from = -1
		chess_board.last_move_to = -1
		chess_board.best_move_arrow_from = -1
		chess_board.best_move_arrow_to = -1
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

func _on_btn_engine_hub_pressed() -> void:
	_open_modal(EngineHubModal.new())

func _on_btn_library_pressed() -> void:
	_open_modal(LibraryModal.new())

func _on_btn_settings_pressed() -> void:
	_open_modal(SettingsModal.new())

# --- ANALYSE DE PARTIE ---

func _on_analysis_progress(cur: int, tot: int) -> void:
	if analyzer.is_analyzing and cur < tot:
		var eng_name = EngineManager.get_engine_display_name() if EngineManager else "Stockfish"
		stats_label.text = "⏳ Analyse par %s (%d/%d)..." % [eng_name, cur, tot]

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
		chess_board._animate_navigation_forward(move)
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
		chess_board.best_move_arrow_depth = int(move_record.get("depth", 0))
		if best_uci.length() >= 4:
			chess_board.best_move_arrow_from = ChessMove.coord_to_square(best_uci.substr(0, 2))
			chess_board.best_move_arrow_to = ChessMove.coord_to_square(best_uci.substr(2, 2))
		else:
			chess_board.best_move_arrow_from = -1
			chess_board.best_move_arrow_to = -1
		if chess_board.arrow_overlay:
			chess_board.arrow_overlay.queue_redraw()
		chess_board.queue_redraw()

	# 2. Tracé progressif de la courbe d'avantage et de son halo de confiance
	if advantage_graph:
		advantage_graph.update_live_ply(ply_idx, move_record)

	# 3. Jauge d'évaluation et badge supérieur
	var score_cp: int = move_record.get("score_cp", 0)
	if eval_bar:
		eval_bar.set_score(score_cp)
	if top_eval_label:
		var pawns: float = score_cp / 100.0
		top_eval_label.text = ("+%.1f" if pawns >= 0 else "%.1f") % pawns

	# 4. Bandeau de statistiques et retour en direct
	var san: String = move_record.get("san", "")
	var move_num: int = move_record.get("move_number", (ply_idx / 2) + 1)
	var is_w: bool = move_record.get("is_white", true)
	var ply_str: String = ("%d. %s" if is_w else "%d... %s") % [move_num, san]
	var margin_pawns: float = float(move_record.get("ci_margin", 0.0)) / 100.0
	var pawns_val: float = score_cp / 100.0
	var eval_display: String = ("%+0.1f [±%.1f]" if margin_pawns > 0 else "%+0.1f") % [pawns_val, margin_pawns]
	var eff_d: int = move_record.get("depth", 0)
	var d_str: String = " (p.%d)" % eff_d if eff_d > 0 else ""

	stats_label.text = "⏳ Analyse en direct (%d/%d) : %s%s • Eval: %s" % [
		ply_idx + 1,
		total_moves,
		ply_str,
		d_str,
		eval_display
	]

func _on_btn_analyze_game_pressed() -> void:
	if analyzer.is_analyzing:
		analyzer.cancel_analysis()
		if EngineManager != null:
			EngineManager.interrupt_evaluation()
		btn_analyze_game.text = "🔍 Analyser"
		_apply_analyze_button_style(false)
		btn_toggle_live.disabled = false
		stats_label.text = "Arrêt de l'analyse en cours..."
		if live_eval_enabled:
			_trigger_live_eval()
		return

	var moves_count = GameController.game.move_history.size()
	if moves_count == 0:
		stats_label.text = "Jouez ou importez des coups avant de lancer l'analyse globale."
		return

	btn_analyze_game.text = "⏹ STOP"
	_apply_analyze_button_style(true)
	btn_toggle_live.disabled = true
	if stats_grid:
		stats_grid.visible = false

	var sm = get_node_or_null("/root/SettingsManager")
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var mode: String = sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"
	var time_per_move: float = sm.get_setting("analysis_time_per_move", 0.3) if sm else 0.3
	var dynamic_base: float = sm.get_setting("analysis_dynamic_base", 0.15) if sm else 0.15
	var dynamic_max: float = sm.get_setting("analysis_dynamic_max", 0.8) if sm else 0.8
	var a_depth: int = sm.get_setting("analysis_depth", def_anal) if sm else def_anal

	var mode_label := ""
	match mode:
		"dynamic":
			mode_label = "dynamique (%.2fs-%.2fs)" % [dynamic_base, dynamic_max]
		"time":
			mode_label = "temps fixe (%.2fs/coup)" % time_per_move
		"depth":
			mode_label = "profondeur %d" % a_depth
		_:
			mode_label = "dynamique"

	var eng_name = EngineManager.get_engine_display_name() if EngineManager else "Stockfish"
	stats_label.text = "⏳ Démarrage de l'analyse %s (%s, 0/%d)..." % [eng_name, mode_label, moves_count]

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
	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()

	if analyzer:
		analyzer.is_analyzing = false
	btn_analyze_game.text = "🔍 Analyser"
	_apply_analyze_button_style(false)
	btn_toggle_live.disabled = false

	if report.has("error"):
		var err: String = report["error"]
		stats_label.text = "❌ %s" % err
		_show_error_banner(err)
		if live_eval_enabled:
			_trigger_live_eval()
		return

	var evals = report.get("evaluations", [])
	advantage_graph.set_evaluations(evals)
	var cur_ply = GameController.current_ply_index if GameController else -1
	_sync_eval_to_ply(cur_ply)

	var total_moves = GameController.game.move_history.size() if GameController.game else 0
	var is_partial = (evals.size() < total_moves)
	_display_analysis_stats(report, is_partial)

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
				"evaluations": evals
			}
			dm.add_engine_analysis(gid, analysis_entry)
			var game_rec = dm.get_game(gid)
			advantage_graph.update_stored_analyses(game_rec.get("engine_analyses", []))

	if move_list:
		move_list.set_analysis_report(report)
		move_list.refresh()

	# Reprise automatique du Live SF19 à la position courante
	if live_eval_enabled:
		_trigger_live_eval()
