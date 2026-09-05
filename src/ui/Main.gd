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
	
	_apply_modern_theme()
	call_deferred("_start_initial_eval")

func _apply_modern_theme() -> void:
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.12, 0.16, 0.23, 0.90)
	btn_normal.border_color = Color(0.20, 0.27, 0.38, 0.85)
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(6)
	btn_normal.content_margin_left = 6
	btn_normal.content_margin_right = 6
	btn_normal.content_margin_top = 3
	btn_normal.content_margin_bottom = 3

	var btn_hover = btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.16, 0.22, 0.32, 1.0)
	btn_hover.border_color = Color(0.22, 0.74, 0.97, 0.80)

	var btn_pressed = btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.08, 0.12, 0.18, 1.0)
	btn_pressed.border_color = Color(0.22, 0.74, 0.97, 1.0)

	# Appliquer à tous les boutons de TopBar
	var top_bar = $VBox/TopBar
	for child in top_bar.get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", Color("#f1f5f9"))
			child.add_theme_color_override("font_hover_color", Color("#ffffff"))

	# Appliquer aux boutons de navigation
	var nav_row = $VBox/NavRow
	for child in nav_row.get_children():
		if child is Button and child != $VBox/NavRow/BtnAnalyzeGame:
			child.add_theme_stylebox_override("normal", btn_normal)
			child.add_theme_stylebox_override("hover", btn_hover)
			child.add_theme_stylebox_override("pressed", btn_pressed)
			child.add_theme_color_override("font_color", Color("#f1f5f9"))

	# Bouton Analyser Partie (accent émeraude moderne)
	var btn_analyze = $VBox/NavRow/BtnAnalyzeGame
	var analyze_normal = StyleBoxFlat.new()
	analyze_normal.bg_color = Color("#059669")
	analyze_normal.border_color = Color("#10b981")
	analyze_normal.set_border_width_all(1)
	analyze_normal.set_corner_radius_all(6)
	analyze_normal.content_margin_left = 10
	analyze_normal.content_margin_right = 10
	analyze_normal.content_margin_top = 4
	analyze_normal.content_margin_bottom = 4

	var analyze_hover = analyze_normal.duplicate() as StyleBoxFlat
	analyze_hover.bg_color = Color("#10b981")
	analyze_hover.border_color = Color("#34d399")

	btn_analyze.add_theme_stylebox_override("normal", analyze_normal)
	btn_analyze.add_theme_stylebox_override("hover", analyze_hover)
	btn_analyze.add_theme_stylebox_override("pressed", analyze_normal)
	btn_analyze.add_theme_color_override("font_color", Color("#ffffff"))

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
		stats_label.text = "⏳ Analyse par Stockfish (%d/%d)..." % [cur, tot]

func _on_btn_analyze_game_pressed() -> void:
	if analyzer.is_analyzing:
		analyzer.cancel_analysis()
		stats_label.text = "Analyse interrompue par l'utilisateur."
		return

	var moves_count = GameController.game.move_history.size()
	if moves_count == 0:
		stats_label.text = "Jouez ou importez des coups avant de lancer l'analyse globale."
		return
	
	stats_label.text = "⏳ Démarrage de l'analyse Stockfish (0/%d)..." % moves_count
	
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
