class_name GameAnalyzer
extends RefCounted
## GameAnalyzer.gd - Analyse complète de partie coup par coup, métriques ACPL, précision et estimation ELO

signal progress_updated(current_ply: int, total_plies: int)
## Émis avant le calcul de chaque position Web : l'UI doit afficher le coup avant
## que les retours `info` du moteur puissent dessiner la moindre flèche.
signal analysis_position_ready(ply_idx: int)
signal ply_analyzed(ply_idx: int, move_record: Dictionary, partial_stats: Dictionary)
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
var white_elo_ci_margin: int = 70
var black_elo_ci_margin: int = 70
var elo_stat_test: Dictionary = {}

var white_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0}
var black_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0}

var engine_manager: Node = null
var settings_manager: Node = null

func _init() -> void:
	engine_manager = _get_engine_manager()
	settings_manager = _get_settings_manager()

func start_game_analysis(game: ChessGame, depth: int = 14, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	move_evaluations.clear()
	
	if not engine_manager:
		engine_manager = _get_engine_manager()

	_reset_stats()
	
	var sm = _get_settings_manager()
	var mode: String = str(options.get("mode", sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"))
	var time_per_move: float = float(options.get("time_per_move", sm.get_setting("analysis_time_per_move", 0.3) if sm else 0.3))
	var dynamic_base: float = float(options.get("dynamic_base", sm.get_setting("analysis_dynamic_base", 0.15) if sm else 0.15))
	var dynamic_max: float = float(options.get("dynamic_max", sm.get_setting("analysis_dynamic_max", 0.8) if sm else 0.8))
	
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

	var start_eval = _evaluate_move_position(ChessGame.INITIAL_FEN, depth, mode, dynamic_base, dynamic_max, time_per_move, 20)
	if start_eval.has("error"):
		return _fail_analysis("Échec de l'évaluation de la position de départ par le moteur.")
	if start_eval.get("timed_out", false) and start_eval.get("depth", 0) <= 0:
		return _fail_analysis("Le moteur n'a pas répondu à l'évaluation de la position de départ.")
	var prev_score_cp = start_eval.get("score_cp", 20)
	var prev_best_move = start_eval.get("best_move", "")
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
		var expected_best_move = prev_best_move

		# Exécution du coup
		sim_game.make_move(move)
		var fen_after = sim_game.get_fen()

		# Détection immédiate de fin de partie (échec et mat ou pat) : évite le blocage du moteur
		var is_mate = move.is_checkmate or move.san.ends_with("#") or (sim_game.is_in_check(sim_game.active_color) and sim_game.get_legal_moves(sim_game.active_color).is_empty())
		var is_stalemate = (not is_mate) and (not sim_game.is_in_check(sim_game.active_color)) and sim_game.get_legal_moves(sim_game.active_color).is_empty()

		var eval_after_data: Dictionary
		if is_mate:
			var mate_score = 10000 if is_white else -10000
			eval_after_data = {
				"score_cp": mate_score,
				"best_move": move.uci,
				"depth": depth,
				"mate_in": 0
			}
		elif is_stalemate:
			eval_after_data = {
				"score_cp": 0,
				"best_move": "",
				"depth": depth,
				"mate_in": 0
			}
		else:
			# Évaluation de la position résultante selon le mode (profondeur, temps fixe ou dynamique adaptatif)
			eval_after_data = _evaluate_move_position(fen_after, depth, mode, dynamic_base, dynamic_max, time_per_move, score_before)
			if eval_after_data.has("error"):
				return _fail_analysis("Le moteur d'échecs n'a pas pu évaluer le coup %s." % move.san)
			if eval_after_data.get("timed_out", false) and eval_after_data.get("depth", 0) <= 0:
				return _fail_analysis("Le moteur n'a pas répondu dans le délai pour le coup %s." % move.san)
		if cancel_requested:
			break
		var score_after = eval_after_data.get("score_cp", score_before)
		var reply_best_move = eval_after_data.get("best_move", "")
		var eff_d = eval_after_data.get("depth", depth)

		# Mise à jour pour le coup suivant
		prev_score_cp = score_after
		prev_best_move = reply_best_move

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

		# Classification qualitative du coup par rapport au meilleur coup possible dans la position de départ du coup
		var quality = _classify_move(cp_loss, move, expected_best_move, score_before, score_after, is_white)
		move.quality = quality
		move.centipawn_loss = cp_loss
		move.eval_before_cp = score_before
		move.eval_after_cp = score_after
		move.best_move_uci = expected_best_move if expected_best_move != "" else reply_best_move

		if is_white:
			_increment_quality_stat(white_stats, quality)
		else:
			_increment_quality_stat(black_stats, quality)

		# Calcul de l'intervalle de confiance pour l'évaluation de cette position (IC 95%)
		var is_tactical = (quality == ChessMove.Quality.BRILLIANT or quality == ChessMove.Quality.BLUNDER or abs(score_after - score_before) > 75)
		var eval_ci = _calculate_eval_ci_margin(eff_d, cp_loss, is_tactical)

		# Enregistrement pour la courbe d'avantage avec IC
		var move_record = {
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": is_white,
			"san": move.san,
			"uci": move.uci,
			"score_cp": score_after,
			"loss_cp": cp_loss,
			"quality": quality,
			"best_move": reply_best_move,
			"best_alternative": expected_best_move,
			"fen": fen_after,
			"depth": eff_d,
			"ci_margin": eval_ci,
			"ci_lower": score_after - eval_ci,
			"ci_upper": score_after + eval_ci
		}
		move_evaluations.append(move_record)

		call_deferred("emit_signal", "progress_updated", i + 1, total_plies)
		call_deferred("emit_signal", "ply_analyzed", i, move_record, {
			"white_loss_sum": white_loss_sum,
			"black_loss_sum": black_loss_sum,
			"white_moves_count": white_moves_count,
			"black_moves_count": black_moves_count
		})

	# Calculs finaux ACPL
	white_acpl = float(white_loss_sum) / maxi(1, white_moves_count)
	black_acpl = float(black_loss_sum) / maxi(1, black_moves_count)

	# Calcul de précision CAPS2 basée sur la perte de probabilité de gain coup par coup
	white_accuracy = _calculate_caps_accuracy(move_evaluations, true)
	black_accuracy = _calculate_caps_accuracy(move_evaluations, false)

	# Estimation ELO avec intervalles de confiance et test statistique
	var w_stat = _calculate_elo_statistics(move_evaluations, true, white_accuracy, white_acpl, white_stats, white_moves_count)
	var b_stat = _calculate_elo_statistics(move_evaluations, false, black_accuracy, black_acpl, black_stats, black_moves_count)
	
	white_estimated_elo = w_stat["elo"]
	black_estimated_elo = b_stat["elo"]
	white_elo_ci_margin = w_stat["ci_margin"]
	black_elo_ci_margin = b_stat["ci_margin"]
	elo_stat_test = _perform_elo_comparison_test(w_stat, b_stat)

	is_analyzing = false
	var report = _build_final_report()
	call_deferred("emit_signal", "analysis_finished", report)
	return report

## Analyse asynchrone non-bloquante avec await (indispensable pour WebAssembly / HTML5 sans threads)
func start_game_analysis_async(game: ChessGame, depth: int = 14, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	move_evaluations.clear()
	
	if not engine_manager:
		engine_manager = _get_engine_manager()

	_reset_stats()
	
	var sm = _get_settings_manager()
	var mode: String = str(options.get("mode", sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"))
	var time_per_move: float = float(options.get("time_per_move", sm.get_setting("analysis_time_per_move", 0.3) if sm else 0.3))
	var dynamic_base: float = float(options.get("dynamic_base", sm.get_setting("analysis_dynamic_base", 0.15) if sm else 0.15))
	var dynamic_max: float = float(options.get("dynamic_max", sm.get_setting("analysis_dynamic_max", 0.8) if sm else 0.8))
	
	var moves = game.move_history
	var total_plies = moves.size()
	
	if total_plies == 0:
		is_analyzing = false
		var rep = _build_final_report()
		analysis_finished.emit(rep)
		return rep

	if not await _wait_for_engine_async():
		var err_msg = "Moteur d'échecs indisponible : impossible d'analyser la partie."
		return _fail_analysis(err_msg)
	# Le Web n'a qu'un worker UCI. On draine donc explicitement un éventuel Live
	# avant de commencer la série, puis on repart d'une partie UCI propre.
	if engine_manager.has_method("prepare_for_async_analysis"):
		if not await engine_manager.prepare_for_async_analysis():
			return _fail_analysis("Le moteur d'échecs n'a pas terminé l'évaluation Live précédente.")
	if cancel_requested:
		is_analyzing = false
		cancel_requested = false
		var cancelled_report = _build_final_report()
		analysis_finished.emit(cancelled_report)
		return cancelled_report

	# Analyse de la position de départ (une seule fois)
	var sim_game = ChessGame.new()
	sim_game.load_fen(ChessGame.INITIAL_FEN)

	var start_eval = await _evaluate_move_position_async(ChessGame.INITIAL_FEN, depth, mode, dynamic_base, dynamic_max, time_per_move, 20)
	if start_eval.has("error"):
		return _fail_analysis("Échec de l'évaluation de la position de départ par le moteur.")
	if start_eval.get("timed_out", false) and start_eval.get("depth", 0) <= 0:
		return _fail_analysis("Le moteur n'a pas répondu à l'évaluation de la position de départ.")
	var prev_score_cp = start_eval.get("score_cp", 20)
	var prev_best_move = start_eval.get("best_move", "")
	var white_loss_sum = 0
	var black_loss_sum = 0
	var white_moves_count = 0
	var black_moves_count = 0

	var tree = Engine.get_main_loop() as SceneTree

	for i in range(total_plies):
		if cancel_requested:
			break
		
		if engine_manager == null or not engine_manager.is_engine_available():
			return _fail_analysis("Le moteur d'échecs s'est arrêté en cours d'analyse de la partie.")
		
		var move = moves[i]
		var is_white = (i % 2 == 0)
		var score_before = prev_score_cp
		var expected_best_move = prev_best_move

		# Exécution du coup
		sim_game.make_move(move)
		var fen_after = sim_game.get_fen()

		# Ordre impératif en Web : la position doit être visible avant l'évaluation.
		# Ainsi chaque mise à jour `info` de Stockfish correspond exactement au
		# plateau affiché, jamais au demi-coup suivant.
		analysis_position_ready.emit(i)
		if tree:
			await tree.process_frame
		if cancel_requested:
			break

		# Détection immédiate de fin de partie (échec et mat ou pat) : évite le blocage du moteur
		var is_mate = move.is_checkmate or move.san.ends_with("#") or (sim_game.is_in_check(sim_game.active_color) and sim_game.get_legal_moves(sim_game.active_color).is_empty())
		var is_stalemate = (not is_mate) and (not sim_game.is_in_check(sim_game.active_color)) and sim_game.get_legal_moves(sim_game.active_color).is_empty()

		var eval_after_data: Dictionary
		if is_mate:
			var mate_score = 10000 if is_white else -10000
			eval_after_data = {
				"score_cp": mate_score,
				"best_move": move.uci,
				"depth": depth,
				"mate_in": 0
			}
		elif is_stalemate:
			eval_after_data = {
				"score_cp": 0,
				"best_move": "",
				"depth": depth,
				"mate_in": 0
			}
		else:
			eval_after_data = await _evaluate_move_position_async(fen_after, depth, mode, dynamic_base, dynamic_max, time_per_move, score_before)
			if eval_after_data.has("error"):
				return _fail_analysis("Le moteur d'échecs n'a pas pu évaluer le coup %s." % move.san)
			if eval_after_data.get("timed_out", false) and eval_after_data.get("depth", 0) <= 0:
				return _fail_analysis("Le moteur n'a pas répondu à l'évaluation du coup %s." % move.san)

		var score_after = eval_after_data.get("score_cp", score_before)
		var reply_best_move = eval_after_data.get("best_move", "")
		var depth_reached = eval_after_data.get("depth", depth)

		# Mise à jour pour le coup suivant
		prev_score_cp = score_after
		prev_best_move = reply_best_move

		var cp_loss = 0
		if is_white:
			cp_loss = max(0, score_before - score_after)
			white_loss_sum += cp_loss
			white_moves_count += 1
		else:
			cp_loss = max(0, score_after - score_before)
			black_loss_sum += cp_loss
			black_moves_count += 1

		var qual = _classify_move(cp_loss, move, expected_best_move, score_before, score_after, is_white)
		move.quality = qual
		move.centipawn_loss = cp_loss
		move.eval_before_cp = score_before
		move.eval_after_cp = score_after
		move.best_move_uci = expected_best_move if expected_best_move != "" else reply_best_move

		if is_white:
			_increment_quality_stat(white_stats, qual)
		else:
			_increment_quality_stat(black_stats, qual)

		var eval_ci = int(clampf(80.0 / sqrt(float(maxi(1, depth_reached))), 8.0, 45.0))
		var move_record = {
			"ply": i,
			"san": move.san,
			"uci": move.uci,
			"score_cp": score_after,
			"depth": depth_reached,
			"best_move": reply_best_move,
			"best_alternative": expected_best_move,
			"quality": qual,
			"cp_loss": cp_loss,
			"is_white": is_white,
			"ci_lower": score_after - eval_ci,
			"ci_upper": score_after + eval_ci
		}
		move_evaluations.append(move_record)

		progress_updated.emit(i + 1, total_plies)
		ply_analyzed.emit(i, move_record, {
			"white_loss_sum": white_loss_sum,
			"black_loss_sum": black_loss_sum,
			"white_moves_count": white_moves_count,
			"black_moves_count": black_moves_count
		})
		if tree:
			await tree.process_frame

	# Calculs finaux ACPL
	white_acpl = float(white_loss_sum) / maxi(1, white_moves_count)
	black_acpl = float(black_loss_sum) / maxi(1, black_moves_count)

	# Calcul de précision CAPS2
	white_accuracy = _calculate_caps_accuracy(move_evaluations, true)
	black_accuracy = _calculate_caps_accuracy(move_evaluations, false)

	# Estimation ELO avec intervalles de confiance et test statistique
	var w_stat = _calculate_elo_statistics(move_evaluations, true, white_accuracy, white_acpl, white_stats, white_moves_count)
	var b_stat = _calculate_elo_statistics(move_evaluations, false, black_accuracy, black_acpl, black_stats, black_moves_count)
	
	white_estimated_elo = w_stat["elo"]
	black_estimated_elo = b_stat["elo"]
	white_elo_ci_margin = w_stat["ci_margin"]
	black_elo_ci_margin = b_stat["ci_margin"]
	elo_stat_test = _perform_elo_comparison_test(w_stat, b_stat)

	is_analyzing = false
	var report = _build_final_report()
	analysis_finished.emit(report)
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

## Précision CAPS2 (Chess.com / Lichess) calculée coup par coup avec pondération contextuelle
func _calculate_caps_accuracy(evals: Array[Dictionary], for_white: bool) -> float:
	var move_accuracies: Array[float] = []
	var move_weights: Array[float] = []
	var prev_cp = 20 # Score de départ égalité légère blanc

	for ev in evals:
		var cur_cp = ev.get("score_cp", 0)
		var is_white_move = ev.get("is_white", true)
		var ply_idx = ev.get("ply", 0)

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
			acc = clampf(acc, 0.0, 100.0)
			move_accuracies.append(acc)

			# Pondération contextuelle :
			# 1. Les tous premiers coups d'ouverture théoriques (plies 0 à 6) ont un poids progressif
			# pour éviter une sur-évaluation artificielle de 100% sur les débuts de partie.
			var weight = 1.0
			if ply_idx < 6:
				weight = 0.65 + (float(ply_idx) / 6.0) * 0.35 # 0.65 -> 1.0
			# 2. Les coups tactiques décisifs ou gaffes critiques comptent pleinement
			var qual = ev.get("quality", ChessMove.Quality.NONE)
			if qual == ChessMove.Quality.BLUNDER or qual == ChessMove.Quality.BRILLIANT:
				weight *= 1.25
			move_weights.append(weight)

		prev_cp = cur_cp

	if move_accuracies.is_empty():
		return 50.0

	var sum_acc = 0.0
	var sum_weights = 0.0
	for j in range(move_accuracies.size()):
		var w = move_weights[j]
		sum_acc += move_accuracies[j] * w
		sum_weights += w

	if sum_weights <= 0.0:
		return 50.0

	return clampf(sum_acc / sum_weights, 5.0, 99.8)

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

func _get_settings_manager() -> Node:
	if settings_manager != null:
		return settings_manager
	if OS.get_main_thread_id() == OS.get_thread_caller_id():
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			settings_manager = tree.root.get_node_or_null("SettingsManager")
	return settings_manager

func _get_engine_manager() -> Node:
	if engine_manager != null:
		return engine_manager
	if OS.get_main_thread_id() == OS.get_thread_caller_id():
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.root:
			engine_manager = tree.root.get_node_or_null("EngineManager")
	return engine_manager

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

func _wait_for_engine_async() -> bool:
	if not engine_manager:
		engine_manager = _get_engine_manager()
	if engine_manager == null:
		return false
	var waited := 0
	var tree = Engine.get_main_loop() as SceneTree
	while not engine_manager.is_engine_available() and waited < ENGINE_START_WAIT_MS:
		if tree:
			await tree.process_frame
		waited += 16
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

## Marge d'erreur de l'évaluation de position (IC 95%) : décroît en 1 / sqrt(profondeur), sensible aux chocs tactiques
static func _calculate_eval_ci_margin(depth: int, cp_loss: int, is_tactical: bool) -> float:
	var effective_depth = maxf(1.0, float(depth))
	var base_se = 72.0 / sqrt(effective_depth)
	var tactical_mult = 1.35 if (is_tactical or cp_loss > 75) else 1.0
	var se = base_se * tactical_mult
	return 1.96 * se

## Estimation ELO biostatistique avec intervalle de confiance à 95%
func _calculate_elo_statistics(evals: Array[Dictionary], for_white: bool, accuracy: float, acpl: float, stats: Dictionary, moves_count: int) -> Dictionary:
	var base_elo = _estimate_elo(accuracy, acpl, stats, moves_count)
	if moves_count <= 0:
		return {"elo": base_elo, "se": 70.0, "ci_margin": 140, "ci_lower": base_elo - 140, "ci_upper": base_elo + 140, "n": 0}
	
	var move_accuracies: Array[float] = []
	var prev_cp = 20
	for ev in evals:
		var cur_cp = ev.get("score_cp", 0)
		var is_w = ev.get("is_white", true)
		if is_w == for_white:
			var win_before = _win_percentage(prev_cp) if for_white else (100.0 - _win_percentage(prev_cp))
			var win_after = _win_percentage(cur_cp) if for_white else (100.0 - _win_percentage(cur_cp))
			var win_loss = maxf(0.0, win_before - win_after)
			var acc = clampf(103.1668 * exp(-0.04354 * win_loss) - 3.1669, 0.0, 100.0)
			move_accuracies.append(acc)
		prev_cp = cur_cp
	
	var n = move_accuracies.size()
	var mean_acc = accuracy
	var var_acc = 0.0
	for a in move_accuracies:
		var_acc += pow(a - mean_acc, 2)
	var s_acc = sqrt(var_acc / float(maxi(1, n - 1)))
	var se_acc = s_acc / sqrt(float(maxi(1, n)))
	
	# Pente locale df/dA dérivée de la fonction de calibrage
	var slope = 43.75
	if mean_acc >= 98.0: slope = 125.0
	elif mean_acc >= 95.0: slope = 100.0
	elif mean_acc >= 90.0: slope = 70.0
	elif mean_acc >= 82.0: slope = 43.75
	elif mean_acc >= 72.0: slope = 30.0
	elif mean_acc >= 60.0: slope = 25.0
	elif mean_acc >= 45.0: slope = 20.0
	else: slope = 6.66
	
	var sample_mult = sqrt(20.0 / float(maxi(1, n))) if n < 20 else 1.0
	var se_elo = maxf(28.0, slope * se_acc * sample_mult)
	var t_crit = 1.96 if n >= 20 else (2.10 if n >= 10 else 2.30)
	var ci_margin = int(round(t_crit * se_elo))
	
	return {
		"elo": base_elo,
		"se": se_elo,
		"ci_margin": ci_margin,
		"ci_lower": base_elo - ci_margin,
		"ci_upper": base_elo + ci_margin,
		"n": n
	}

## Test statistique de comparaison des deux ELOs (test de Welch / Wald bilatéral)
func _perform_elo_comparison_test(w_data: Dictionary, b_data: Dictionary) -> Dictionary:
	var w_elo = float(w_data.get("elo", 1500))
	var b_elo = float(b_data.get("elo", 1500))
	var w_se = float(w_data.get("se", 50.0))
	var b_se = float(b_data.get("se", 50.0))
	
	var diff = w_elo - b_elo
	var denom = sqrt(pow(w_se, 2) + pow(b_se, 2))
	var t_stat = diff / maxf(1.0, denom)
	var z = absf(t_stat)
	
	var p_value = _calculate_normal_p_value(z)
	var stars = _p_value_to_stars(p_value)
	var is_significant = (p_value < 0.05)
	
	var desc = ""
	if p_value < 0.001:
		desc = "Différence hautement significative (p < 0.001 ***)"
	elif p_value < 0.01:
		desc = "Différence très significative (p < 0.01 **)"
	elif p_value < 0.05:
		desc = "Différence significative (p < 0.05 *)"
	else:
		desc = "Différence non significative (p >= 0.05 ns)"
		
	return {
		"diff_elo": int(round(diff)),
		"t_stat": t_stat,
		"p_value": p_value,
		"stars": stars,
		"is_significant": is_significant,
		"description": desc
	}

## Calcul de p-value bilatérale par approximation de Chebyshev / Abramowitz & Stegun
static func _calculate_normal_p_value(z: float) -> float:
	var x = absf(z)
	if x > 8.0:
		return 0.000001
	var p0 = 0.2316419
	var b1 = 0.319381530
	var b2 = -0.356563782
	var b3 = 1.781477937
	var b4 = -1.821255978
	var b5 = 1.330274429
	var t = 1.0 / (1.0 + p0 * x)
	var phi = (1.0 / sqrt(TAU)) * exp(-0.5 * x * x)
	var tail = phi * (b1 * t + b2 * t * t + b3 * t * t * t + b4 * t * t * t * t + b5 * t * t * t * t * t)
	return clampf(2.0 * tail, 0.0, 1.0)

static func _p_value_to_stars(p: float) -> String:
	if p < 0.001:
		return "***"
	elif p < 0.01:
		return "**"
	elif p < 0.05:
		return "*"
	return "ns"

## Évaluation selon le mode sélectionné : profondeur, temps fixe ou dynamique adaptatif
func _evaluate_move_position(fen: String, depth: int, mode: String, base_time_sec: float, max_time_sec: float, fixed_time_sec: float, prev_score: int) -> Dictionary:
	match mode:
		"time":
			var ms = int(round(fixed_time_sec * 1000.0))
			return _evaluate_fen_sync(fen, depth, ms)
		"dynamic":
			var base_ms = int(round(base_time_sec * 1000.0))
			var first_pass = _evaluate_fen_sync(fen, depth, base_ms)
			if first_pass.has("error") or cancel_requested:
				return first_pass
			var score_cand = first_pass.get("score_cp", prev_score)
			var delta_cp = abs(score_cand - prev_score)
			# Approfondissement automatique proportionnel à la criticité du coup
			if delta_cp >= 50 or abs(score_cand) >= 300:
				var factor = clampf(float(delta_cp - 50) / 150.0, 0.25, 1.0)
				var max_ms = int(round(max_time_sec * 1000.0))
				var deep_ms = int(lerpf(float(base_ms), float(max_ms), factor))
				if deep_ms > base_ms:
					var refined = _evaluate_fen_sync(fen, depth, deep_ms)
					if not refined.has("error") and not cancel_requested:
						return refined
			return first_pass
		_: # "depth"
			return _evaluate_fen_sync(fen, depth, -1)

func _evaluate_fen_sync(fen: String, depth: int, movetime_ms: int = -1) -> Dictionary:
	var engine = engine_manager
	if engine == null:
		engine = _get_engine_manager()
		engine_manager = engine

	if engine == null or not engine.is_engine_available():
		return {"error": "engine_unavailable", "score_cp": 0, "best_move": "", "depth": 0}

	if engine.has_method("evaluate_position_sync"):
		var tout = EVAL_TIMEOUT_MS if movetime_ms <= 0 else (movetime_ms + 600)
		return engine.evaluate_position_sync(fen, depth, tout, movetime_ms)

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

func _evaluate_move_position_async(fen: String, depth: int, mode: String, base_time_sec: float, max_time_sec: float, fixed_time_sec: float, prev_score: int) -> Dictionary:
	match mode:
		"time":
			var ms = int(round(fixed_time_sec * 1000.0))
			return await _evaluate_fen_async(fen, depth, ms)
		"dynamic":
			var base_ms = int(round(base_time_sec * 1000.0))
			var first_pass = await _evaluate_fen_async(fen, depth, base_ms)
			if first_pass.has("error") or cancel_requested:
				return first_pass
			var score_cand = first_pass.get("score_cp", prev_score)
			var delta_cp = abs(score_cand - prev_score)
			if delta_cp >= 50 or abs(score_cand) >= 300:
				var factor = clampf(float(delta_cp - 50) / 150.0, 0.25, 1.0)
				var max_ms = int(round(max_time_sec * 1000.0))
				var deep_ms = int(lerpf(float(base_ms), float(max_ms), factor))
				if deep_ms > base_ms:
					var refined = await _evaluate_fen_async(fen, depth, deep_ms)
					if not refined.has("error") and not cancel_requested:
						return refined
			return first_pass
		_: # "depth"
			return await _evaluate_fen_async(fen, depth, -1)

func _evaluate_fen_async(fen: String, depth: int, movetime_ms: int = -1) -> Dictionary:
	var engine = engine_manager
	if engine == null:
		engine = _get_engine_manager()
		engine_manager = engine

	if engine == null or not engine.is_engine_available():
		return {"error": "engine_unavailable", "score_cp": 0, "best_move": "", "depth": 0}

	if engine.has_method("evaluate_position_async"):
		var tout = EVAL_TIMEOUT_MS if movetime_ms <= 0 else (movetime_ms + 600)
		return await engine.evaluate_position_async(fen, depth, tout, movetime_ms)

	return _evaluate_fen_sync(fen, depth, movetime_ms)

func _build_final_report() -> Dictionary:
	return {
		"white_acpl": white_acpl,
		"black_acpl": black_acpl,
		"white_accuracy": white_accuracy,
		"black_accuracy": black_accuracy,
		"white_estimated_elo": white_estimated_elo,
		"black_estimated_elo": black_estimated_elo,
		"white_elo_ci": white_elo_ci_margin,
		"black_elo_ci": black_elo_ci_margin,
		"elo_comparison": elo_stat_test,
		"white_stats": white_stats,
		"black_stats": black_stats,
		"evaluations": move_evaluations
	}
