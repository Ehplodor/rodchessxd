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
@onready var chess_board: ChessBoard2D = $VBox/CenterArea/BoardColumn/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $VBox/Dashboard/GraphPanel/AdvantageGraph
@onready var move_list: MoveList2D = $AnalyseOverlay/Layout/MoveList
@onready var coach_panel: CoachPanel2D = $CoachOverlay/Layout/CoachPanel
@onready var analyse_overlay: Control = $AnalyseOverlay
@onready var coach_overlay: Control = $CoachOverlay

@onready var stats_label: Label = $VBox/Dashboard/StatsLabel
@onready var top_eval_label: Label = $VBox/TopBar/EvalBadge/EvalText

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

var error_label: Label = null
var _error_token := 0

func _ready() -> void:
	analyzer = GameAnalyzer.new()
	analyzer.analysis_finished.connect(_on_analysis_finished)
	analyzer.progress_updated.connect(func(cur, tot):
		call_deferred("_on_analysis_progress", cur, tot)
	)
	
	GameController.play_sound_requested.connect(_on_play_sound)
	GameController.position_changed.connect(_on_game_position_changed)
	GameController.move_navigated.connect(func(_idx): _update_player_labels())
	GameController.move_made.connect(func(_m): _update_player_labels())
	
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
	_update_player_labels()
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

	# Boutons de navigation sous le plateau (sauf le bouton Analyser)
	var nav_row = $VBox/NavRow
	for child in nav_row.get_children():
		if child is Button and child != nav_row.get_node("BtnAnalyzeGame"):
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", font_color_normal)
			child.add_theme_color_override("font_hover_color", font_color_hover)
			child.add_theme_color_override("font_pressed_color", font_color_normal)
			child.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)

	# Bouton Analyser Partie (accent émeraude, AA ≥ 4,5:1 sur normal et pressé)
	var btn_analyze: Button = nav_row.get_node("BtnAnalyzeGame")
	var analyze_normal := DesignTokens.flat(DesignTokens.PRIMARY_BG, DesignTokens.RADIUS_SMALL,
			DesignTokens.PRIMARY_BORDER, 1, Vector2(10, 2))
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

	# Bandeau stats (textes longs → retour à la ligne)
	var stats: Label = $VBox/Dashboard/StatsLabel
	stats.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	stats.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
		stats_label.text = "Position de départ prête. Touchez « Analyser » sous le plateau."
	else:
		var dm = get_node_or_null("/root/DatabaseManager")
		if dm and GameController.current_game_id != "":
			var g = dm.get_game(GameController.current_game_id)
			var ea = g.get("engine_analyses", [])
			advantage_graph.update_stored_analyses(ea)

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
			last_move_text = ChessMove.square_to_coord(m.from_sq) + "→" + ChessMove.square_to_coord(m.to_sq)

	# Badges d'état (⭐ Au trait pour le joueur actif, Dernier coup pour le joueur qui vient de jouer)
	_update_turn_badge(turn_badge_top, turn_badge_label_top, top_is_active, last_move_text if not top_is_active else "")
	_update_turn_badge(turn_badge_bottom, turn_badge_label_bottom, bottom_is_active, last_move_text if not bottom_is_active else "")

func _update_turn_badge(badge: PanelContainer, label: Label, is_active: bool, last_move_san: String) -> void:
	if badge == null or label == null:
		return
	if is_active:
		badge.visible = true
		var active_style = DesignTokens.flat(
			Color(0.06, 0.72, 0.51, 0.18),
			DesignTokens.RADIUS_SMALL,
			Color(0.06, 0.72, 0.51, 0.80),
			1,
			Vector2(8, 2)
		)
		badge.add_theme_stylebox_override("panel", active_style)
		label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		label.add_theme_color_override("font_color", Color("#34d399"))
		label.text = "⭐ Au trait"
	elif last_move_san != "":
		badge.visible = true
		var last_style = DesignTokens.flat(
			Color(0.94, 0.27, 0.27, 0.14),
			DesignTokens.RADIUS_SMALL,
			Color(0.94, 0.27, 0.27, 0.55),
			1,
			Vector2(8, 2)
		)
		badge.add_theme_stylebox_override("panel", last_style)
		label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		label.add_theme_color_override("font_color", Color("#f87171"))
		label.text = "Dernier coup : " + last_move_san
	else:
		badge.visible = false

func _clip_player_name(name: String, max_chars := 24) -> String:
	if name.length() <= max_chars:
		return name
	return name.substr(0, max_chars - 1) + "…"

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

## Vues superposées (Analyse / Coach) par-dessus la vue principale.

func _open_analyse_overlay() -> void:
	move_list.refresh()
	_show_overlay(analyse_overlay)

func _open_coach_overlay() -> void:
	_show_overlay(coach_overlay)

func _show_overlay(overlay: Control) -> void:
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = true
	move_child(overlay, get_child_count() - 1)

func _close_overlays() -> void:
	analyse_overlay.visible = false
	coach_overlay.visible = false

## Retour à la vue principale (clic sur un coup dans l'analyse).
func show_board_tab() -> void:
	_close_overlays()

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
	
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var a_depth = SettingsManager.get_setting("analysis_depth", def_anal)
	stats_label.text = "⏳ Démarrage de l'analyse %s (prof. %d, 0/%d)..." % [EngineManager.get_engine_display_name(), a_depth, moves_count]
	
	if analysis_thread and analysis_thread.is_started():
		analysis_thread.wait_to_finish()
	
	analyzer.is_analyzing = true
	analysis_thread = Thread.new()
	analysis_thread.start(func():
		analyzer.start_game_analysis(GameController.game, a_depth)
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
			var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
			var a_depth = SettingsManager.get_setting("analysis_depth", def_anal)
			var analysis_entry = {
				"engine_name": EngineManager.get_engine_display_name() if EngineManager else "Stockfish",
				"depth": a_depth,
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

	move_list.refresh()

	# Le graphe permanent (sous l'échiquier) s'est mis à jour : on reste sur la vue principale.
