extends Control
## Main.gd - Contrôleur principal de l'interface mobile de RodChessXD

const EvalBar2D = preload("res://src/ui/components/EvalBar2D.gd")
const ChessBoard2D = preload("res://src/ui/components/ChessBoard2D.gd")
const AdvantageGraph2D = preload("res://src/ui/components/AdvantageGraph2D.gd")
const MoveList2D = preload("res://src/ui/components/MoveList2D.gd")
const CoachPanel2D = preload("res://src/ui/components/CoachPanel2D.gd")
const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")
const OCREditorModal = preload("res://src/ui/components/OCREditorModal.gd")
const EngineHubModal = preload("res://src/ui/components/EngineHubModal.gd")
const SettingsModal = preload("res://src/ui/components/SettingsModal.gd")

@onready var eval_bar: EvalBar2D = $VBox/CenterArea/EvalBar
@onready var chess_board: ChessBoard2D = $VBox/CenterArea/BoardContainer/ChessBoard
@onready var advantage_graph: AdvantageGraph2D = $VBox/BottomTabs/Bilan/GraphContainer/AdvantageGraph
@onready var move_list: MoveList2D = $VBox/BottomTabs/Bilan/MoveList
@onready var coach_panel: CoachPanel2D = $VBox/BottomTabs/Coach/CoachPanel

@onready var stats_label: Label = $VBox/BottomTabs/Bilan/StatsLabel
@onready var top_eval_label: Label = $VBox/TopBar/EvalBadge/EvalText

@onready var sfx_move: AudioStreamPlayer = $Sounds/SfxMove
@onready var sfx_capture: AudioStreamPlayer = $Sounds/SfxCapture
@onready var sfx_check: AudioStreamPlayer = $Sounds/SfxCheck

var analyzer: GameAnalyzer

func _ready() -> void:
	analyzer = GameAnalyzer.new()
	analyzer.analysis_finished.connect(_on_analysis_finished)
	
	GameController.play_sound_requested.connect(_on_play_sound)
	
	if EngineManager != null:
		EngineManager.evaluation_updated.connect(_on_engine_eval)
	
	call_deferred("_start_initial_eval")

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

# --- MODALES & ANALYSE ---

func _on_btn_import_png_pressed() -> void:
	var modal: OCREditorModal = OCREditorModal.new()
	add_child(modal)
	modal.popup_centered()

func _on_btn_engine_hub_pressed() -> void:
	var hub: EngineHubModal = EngineHubModal.new()
	add_child(hub)
	hub.popup_centered()

func _on_btn_settings_pressed() -> void:
	var modal: SettingsModal = SettingsModal.new()
	add_child(modal)
	modal.popup_centered()

func _on_btn_analyze_game_pressed() -> void:
	var moves_count = GameController.game.move_history.size()
	if moves_count == 0:
		stats_label.text = "Jouez ou importez des coups avant de lancer l'analyse globale."
		return
	
	stats_label.text = "⏳ Analyse globale par Stockfish en cours (0/%d)..." % moves_count
	analyzer.progress_updated.connect(func(cur, tot):
		stats_label.text = "⏳ Analyse par Stockfish (%d/%d)..." % [cur, tot]
	, CONNECT_ONE_SHOT)
	
	var thread = Thread.new()
	thread.start(func():
		var report = analyzer.start_game_analysis(GameController.game, 12)
		call_deferred("_on_analysis_finished", report)
	)

func _on_analysis_finished(report: Dictionary) -> void:
	var evals = report.get("evaluations", [])
	advantage_graph.set_evaluations(evals)

	var w_acc = report.get("white_accuracy", 0.0)
	var b_acc = report.get("black_accuracy", 0.0)
	var w_elo = report.get("white_estimated_elo", 1500)
	var b_elo = report.get("black_estimated_elo", 1500)

	stats_label.text = "⚪ Blancs: %.1f%% (Est. %d ELO)  |  ⚫ Noirs: %.1f%% (Est. %d ELO)" % [w_acc, w_elo, b_acc, b_elo]
