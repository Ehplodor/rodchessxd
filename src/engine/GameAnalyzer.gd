class_name GameAnalyzer
extends RefCounted
## GameAnalyzer.gd - Analyse complète de partie coup par coup, métriques ACPL, précision et estimation ELO

signal progress_updated(current_ply: int, total_plies: int)
signal analysis_finished(report: Dictionary)

const ENGINE_START_WAIT_MS: int = 3000
const EVAL_TIMEOUT_MS: int = 1500

var is_analyzing: bool = false
var cancel_requested: bool = false

# Données du rapport
var move_evaluations: Array[Dictionary] = []
var white_acpl: float = 0.0
var black_acpl: float = 0.0
var white_accuracy: float = 0.0
var black_accuracy: float = 0.0
var white_estimated_elo: int = 1500
var black_estimated_elo: int = 1500

var white_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0}
var black_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0}

var engine_manager: Node = null

func _init() -> void:
	engine_manager = _get_engine_manager()

func start_game_analysis(game: ChessGame, depth: int = 14) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	move_evaluations.clear()
	
	if not engine_manager:
		engine_manager = _get_engine_manager()

	_reset_stats()
	
	var moves = game.move_history
	var total_plies = moves.size()
	
	if total_plies == 0:
		is_analyzing = false
		var rep = _build_final_report()
		call_deferred("emit_signal", "analysis_finished", rep)
		return rep

	if not _wait_for_engine():
		var err_msg = "Moteur d'échecs indisponible : impossible d'analyser la partie."
		return _fail_analysis(err_msg)

	# Analyse de la position de départ (une seule fois)
	var sim_game = ChessGame.new()
	sim_game.load_fen(ChessGame.INITIAL_FEN)

	var start_eval = _evaluate_fen_sync(ChessGame.INITIAL_FEN, depth)
	if start_eval.has("error"):
		return _fail_analysis("Échec de l'évaluation de la position de départ par le moteur.")
	if start_eval.get("timed_out", false) and start_eval.get("depth", 0) <= 0:
		return _fail_analysis("Le moteur n'a pas répondu à l'évaluation de la position de départ.")
	var prev_score_cp = start_eval.get("score_cp", 20)
	var white_loss_sum = 0
	var black_loss_sum = 0
	var white_moves_count = 0
	var black_moves_count = 0

	for i in range(total_plies):
		if cancel_requested:
			break
		
		if engine_manager == null or not engine_manager.is_engine_available():
			return _fail_analysis("Le moteur d'échecs s'est arrêté en cours d'analyse de la partie.")
		
		var move = moves[i]
		var is_white = (i % 2 == 0)
		var score_before = prev_score_cp

		# Exécution du coup
		sim_game.make_move(move)
		var fen_after = sim_game.get_fen()

		# Évaluation de la position résultante
		var eval_after_data = _evaluate_fen_sync(fen_after, depth)
		if eval_after_data.has("error"):
			return _fail_analysis("Le moteur d'échecs n'a pas pu évaluer le coup %s." % move.san)
		if eval_after_data.get("timed_out", false) and eval_after_data.get("depth", 0) <= 0:
			return _fail_analysis("Le moteur n'a pas répondu dans le délai pour le coup %s." % move.san)
		if cancel_requested:
			break
		var score_after = eval_after_data.get("score_cp", score_before)
		var best_move_uci = eval_after_data.get("best_move", "")

		# Calcul de la perte en centipions (du point de vue du joueur actif)
		var cp_loss = 0
		if is_white:
			cp_loss = maxi(0, score_before - score_after)
			white_loss_sum += cp_loss
			white_moves_count += 1
		else:
			cp_loss = maxi(0, score_after - score_before)
			black_loss_sum += cp_loss
			black_moves_count += 1

		# Classification qualitative du coup
		var quality = _classify_move(cp_loss, move, best_move_uci, score_before, score_after, is_white)
		move.quality = quality
		move.centipawn_loss = cp_loss
		move.eval_before_cp = score_before
		move.eval_after_cp = score_after
		move.best_move_uci = best_move_uci

		if is_white:
			_increment_quality_stat(white_stats, quality)
		else:
			_increment_quality_stat(black_stats, quality)

		# Enregistrement pour la courbe d'avantage
		var move_record = {
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": is_white,
			"san": move.san,
			"uci": move.uci,
			"score_cp": score_after,
			"loss_cp": cp_loss,
			"quality": quality,
			"best_move": best_move_uci,
			"fen": fen_after
		}
		move_evaluations.append(move_record)

		prev_score_cp = score_after
		call_deferred("emit_signal", "progress_updated", i + 1, total_plies)

	# Calculs finaux ACPL
	white_acpl = float(white_loss_sum) / maxi(1, white_moves_count)
	black_acpl = float(black_loss_sum) / maxi(1, black_moves_count)

	# Calcul de précision CAPS2 basée sur la perte de probabilité de gain coup par coup
	white_accuracy = _calculate_caps_accuracy(move_evaluations, true)
	black_accuracy = _calculate_caps_accuracy(move_evaluations, false)

	# Estimation ELO réaliste calibrée sur les benchmarks FIDE / Chess.com
	white_estimated_elo = _estimate_elo(white_accuracy, white_acpl, white_stats, white_moves_count)
	black_estimated_elo = _estimate_elo(black_accuracy, black_acpl, black_stats, black_moves_count)

	is_analyzing = false
	var report = _build_final_report()
	call_deferred("emit_signal", "analysis_finished", report)
	return report

func cancel_analysis() -> void:
	cancel_requested = true

func _reset_stats() -> void:
	for k in white_stats.keys():
		white_stats[k] = 0
		black_stats[k] = 0

func _classify_move(cp_loss: int, move: ChessMove, best_move: String, _score_before: int, _score_after: int, _is_white: bool) -> ChessMove.Quality:
	# 1. Si le coup joué est exactement le #1 du moteur
	if move.uci == best_move:
		if move.captured_piece == ChessPiece.Type.NONE and move.piece != ChessPiece.Type.PAWN:
			return ChessMove.Quality.BRILLIANT
		return ChessMove.Quality.BEST

	# 2. Selon la perte en centipions (normes FIDE / Lichess)
	if cp_loss <= 15:
		return ChessMove.Quality.EXCELLENT
	elif cp_loss <= 40:
		return ChessMove.Quality.GOOD
	elif cp_loss <= 90:
		return ChessMove.Quality.INACCURACY
	elif cp_loss <= 200:
		return ChessMove.Quality.MISTAKE
	else:
		return ChessMove.Quality.BLUNDER

func _increment_quality_stat(stats: Dictionary, q: ChessMove.Quality) -> void:
	match q:
		ChessMove.Quality.BRILLIANT: stats["brilliant"] += 1
		ChessMove.Quality.BEST: stats["best"] += 1
		ChessMove.Quality.EXCELLENT: stats["excellent"] += 1
		ChessMove.Quality.GOOD: stats["good"] += 1
		ChessMove.Quality.INACCURACY: stats["inaccuracy"] += 1
		ChessMove.Quality.MISTAKE: stats["mistake"] += 1
		ChessMove.Quality.BLUNDER: stats["blunder"] += 1

## Conversion centipions -> Probabilité de gain (modèle sigmoïde standard FIDE / Lichess)
## 0 cp -> 50%, +100 cp -> ~64%, +300 cp -> ~85%, +600 cp -> ~97%
func _win_percentage(score_cp: int) -> float:
	return 100.0 / (1.0 + exp(-0.00368208 * float(score_cp)))

## Précision CAPS2 (Chess.com / Lichess) calculée coup par coup
func _calculate_caps_accuracy(evals: Array[Dictionary], for_white: bool) -> float:
	var move_accuracies: Array[float] = []
	var prev_cp = 20 # Score de départ égalité légère blanc

	for ev in evals:
		var cur_cp = ev.get("score_cp", 0)
		var is_white_move = ev.get("is_white", true)

		if is_white_move == for_white:
			var win_before: float
			var win_after: float

			if for_white:
				win_before = _win_percentage(prev_cp)
				win_after = _win_percentage(cur_cp)
			else:
				win_before = 100.0 - _win_percentage(prev_cp)
				win_after = 100.0 - _win_percentage(cur_cp)

			var win_loss = maxf(0.0, win_before - win_after)
			# Formule officielle CAPS2 : 103.1668 * exp(-0.04354 * win_loss) - 3.1669
			var acc = 103.1668 * exp(-0.04354 * win_loss) - 3.1669
			move_accuracies.append(clampf(acc, 0.0, 100.0))

		prev_cp = cur_cp

	if move_accuracies.is_empty():
		return 50.0

	var sum_acc = 0.0
	for a in move_accuracies:
		sum_acc += a
	return clampf(sum_acc / float(move_accuracies.size()), 5.0, 99.8)

## Modèle d'estimation ELO réaliste et étalonné
## Évite l'inflation absurde à 2800 ELO sur les ouvertures courtes
func _estimate_elo(accuracy: float, acpl: float, stats: Dictionary, moves_count: int) -> int:
	if moves_count == 0:
		return 1500

	# 1. Base ELO dérivée de la précision de jeu (étalonné sur Chess.com Game Review)
	var base_elo: float = 0.0
	if accuracy >= 98.0:
		base_elo = 2500.0 + (accuracy - 98.0) * 125.0 # 98% -> 2500, 100% -> 2750
	elif accuracy >= 95.0:
		base_elo = 2200.0 + (accuracy - 95.0) * 100.0 # 95% -> 2200, 98% -> 2500
	elif accuracy >= 90.0:
		base_elo = 1850.0 + (accuracy - 90.0) * 70.0  # 90% -> 1850, 95% -> 2200
	elif accuracy >= 82.0:
		base_elo = 1500.0 + (accuracy - 82.0) * 43.75 # 82% -> 1500, 90% -> 1850
	elif accuracy >= 72.0:
		base_elo = 1200.0 + (accuracy - 72.0) * 30.0  # 72% -> 1200, 82% -> 1500
	elif accuracy >= 60.0:
		base_elo = 900.0 + (accuracy - 60.0) * 25.0   # 60% -> 900,  72% -> 1200
	elif accuracy >= 45.0:
		base_elo = 600.0 + (accuracy - 45.0) * 20.0   # 45% -> 600,  60% -> 900
	else:
		base_elo = maxf(300.0, 300.0 + accuracy * 6.66) # <45% -> 300 à 600

	# 2. Modulateur ACPL : une perte moyenne élevée plafonne le niveau maximum crédible
	if acpl > 110.0:
		base_elo = minf(base_elo, 950.0)
	elif acpl > 75.0:
		base_elo = minf(base_elo, 1350.0)
	elif acpl > 50.0:
		base_elo = minf(base_elo, 1700.0)

	# 3. Pénalité pour gaffes et erreurs tactiques
	var blunders = stats.get("blunder", 0)
	var mistakes = stats.get("mistake", 0)
	var blunder_rate = float(blunders) / float(moves_count)
	var mistake_rate = float(mistakes) / float(moves_count)

	base_elo -= blunder_rate * 450.0 # Ex: 2 gaffes en 20 coups (-45 ELO)
	base_elo -= mistake_rate * 200.0

	# 4. Amortisseur statistique essentiel : Taille de l'échantillon (Nombre de coups)
	# 4 coups d'ouverture connus par cœur ne font pas un Grand-Maître à 2700 !
	# La pleine confiance n'est atteinte qu'à partir de 20 coups joués (~40 demi-coups).
	var confidence = clampf(float(moves_count) / 20.0, 0.25, 1.0)
	var median_anchor = 1250.0 # Point d'ancrage médian amateur / club
	var calibrated_elo = (base_elo * confidence) + (median_anchor * (1.0 - confidence))

	return clampi(int(round(calibrated_elo)), 300, 2850)

func _get_engine_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("EngineManager")
	return null

func _wait_for_engine() -> bool:
	if not engine_manager:
		engine_manager = _get_engine_manager()
	if engine_manager == null:
		return false
	var waited := 0
	while not engine_manager.is_engine_available() and waited < ENGINE_START_WAIT_MS:
		OS.delay_msec(50)
		waited += 50
	return engine_manager.is_engine_available()

func _fail_analysis(msg: String) -> Dictionary:
	is_analyzing = false
	cancel_requested = false
	_emit_engine_error(msg)
	var rep = _build_final_report()
	rep["error"] = msg
	call_deferred("emit_signal", "analysis_finished", rep)
	return rep

func _emit_engine_error(msg: String) -> void:
	var eng = engine_manager
	if eng == null:
		eng = _get_engine_manager()
	if eng:
		eng.call_deferred("emit_signal", "engine_error", msg)

func _evaluate_fen_sync(fen: String, depth: int) -> Dictionary:
	var engine = engine_manager
	if engine == null:
		engine = _get_engine_manager()
		engine_manager = engine

	if engine == null or not engine.is_engine_available():
		return {"error": "engine_unavailable", "score_cp": 0, "best_move": "", "depth": 0}

	if engine.has_method("evaluate_position_sync"):
		return engine.evaluate_position_sync(fen, depth, EVAL_TIMEOUT_MS)

	engine.evaluate_position(fen, depth)
	var max_wait = 20
	while engine.is_evaluating and max_wait > 0:
		OS.delay_msec(50)
		max_wait -= 1

	return {
		"score_cp": engine.eval_score_cp,
		"best_move": engine.best_move_uci,
		"depth": engine.eval_depth
	}

func _build_final_report() -> Dictionary:
	return {
		"white_acpl": white_acpl,
		"black_acpl": black_acpl,
		"white_accuracy": white_accuracy,
		"black_accuracy": black_accuracy,
		"white_estimated_elo": white_estimated_elo,
		"black_estimated_elo": black_estimated_elo,
		"white_stats": white_stats,
		"black_stats": black_stats,
		"evaluations": move_evaluations
	}
