class_name GameAnalyzer
extends RefCounted
## GameAnalyzer.gd - Analyse complète de partie coup par coup, métriques ACPL, précision et estimation ELO

signal progress_updated(current_ply: int, total_plies: int)
## Émis avant le calcul de chaque position : l'UI doit afficher le coup avant
## que les retours `info` du moteur puissent dessiner la moindre flèche.
signal analysis_position_ready(ply_idx: int)
signal ply_analyzed(ply_idx: int, move_record: Dictionary, partial_stats: Dictionary)
signal analysis_finished(report: Dictionary)

const ENGINE_START_WAIT_MS: int = 3000
const EVAL_TIMEOUT_MS: int = 1500

# --- Analyse à budget (proto) : passe A peu profonde sur tous les plies, puis passe B
# profonde uniquement sur les plies critiques (budget global borné). ---
const BUDGET_BASE_DEPTH: int = 8
const BUDGET_DEEP_DEPTH: int = 14
const BUDGET_MAX_DEEP: int = 6
const BUDGET_MIN_CRITICALITY: float = 12.0
const BUDGET_DEEP_MOVETIME_MS: int = 250

var is_analyzing: bool = false
var cancel_requested: bool = false
var _awaited_display_ply: int = -1

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
## Point 2 — ELO IPR (Regan) par camp, exposé comme métadonnée explicative.
var white_ipr_elo: int = 1500
var black_ipr_elo: int = 1500
## Point 1 — Complexité moyenne des demi-coups hors théorie par camp.
var white_complexity_avg: float = 1.0
var black_complexity_avg: float = 1.0
## Point 4 — Vrai si l'horloge PGN (%clk) a alimenté la modulation temporelle.
var has_clock_data: bool = false

var white_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0}
var black_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0}

## Version du schéma de rapport (T0.5). Les lecteurs tolèrent l'absence du champ.
const SCHEMA_VERSION := 2

var opening_info: Dictionary = {}
var theory_plies: int = 0
var white_phase_stats: Dictionary = {}
var black_phase_stats: Dictionary = {}
var biggest_swings: Array = []
## MultiPV utilisateur à restaurer après une analyse de masse (T1.1).
var _multipv_before_analysis: int = -1

var engine_manager: Node = null
var settings_manager: Node = null

func _init() -> void:
	engine_manager = _get_engine_manager()
	settings_manager = _get_settings_manager()

func start_game_analysis(game: ChessGame, depth: int = 14, options: Dictionary = {}) -> Dictionary:
	if str(options.get("mode", "")) == "budget":
		return _start_game_analysis_budget(game, depth, options)
	is_analyzing = true
	cancel_requested = false
	_awaited_display_ply = -1
	move_evaluations.clear()
	
	if options.has("depth") and int(options["depth"]) > 0:
		depth = int(options["depth"])
	if not engine_manager:
		engine_manager = _get_engine_manager()

	_reset_stats()
	
	var sm = _get_settings_manager()
	var mode: String = str(options.get("mode", sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"))
	var time_per_move: float = float(options.get("time_per_move", sm.get_setting("analysis_time_per_move", 0.2) if sm else 0.2))
	var dynamic_base: float = float(options.get("dynamic_base", sm.get_setting("analysis_dynamic_base", 0.08) if sm else 0.08))
	var dynamic_max: float = float(options.get("dynamic_max", sm.get_setting("analysis_dynamic_max", 0.25) if sm else 0.25))
	var wait_for_display: bool = bool(options.get("wait_for_display", false))

	# T1.2 — Détection de l'ouverture / sortie de théorie (exclue des métriques).
	opening_info = OpeningBook.identify(_moves_to_uci(game.move_history))
	theory_plies = int(opening_info.get("out_of_book_ply", 0))
	# MultiPV réduit à 1 pendant l'analyse de masse (accélération maximale x2.5).
	# Restauré en fin d'analyse.
	if engine_manager != null and engine_manager.has_method("set_multipv"):
		_multipv_before_analysis = int(engine_manager.default_multipv())
		engine_manager.set_multipv(1, true)

	var moves = game.move_history
	var total_plies = moves.size()
	var clock_deltas := _extract_clock_deltas(moves)
	
	if total_plies == 0:
		is_analyzing = false
		_restore_default_multipv()
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
	var prev_fen: String = ChessGame.INITIAL_FEN
	var prev_pv: Array = start_eval.get("pv_line", [])
	var prev_multipv: Array = start_eval.get("multipv_lines", [])
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
		var fen_before: String = prev_fen
		var pv_before: Array = prev_pv
		var multipv_before: Array = prev_multipv

		# Point 1 — Nombre de coups légaux dans la position AVANT le coup (complexité).
		var legal_moves_count := sim_game.get_legal_moves(sim_game.active_color).size()

		# Exécution du coup
		sim_game.make_move(move)
		var fen_after = sim_game.get_fen()

		# Synchronisation de l'affichage avant évaluation pour que les flèches SF se tracent sur la bonne position
		if wait_for_display:
			_awaited_display_ply = i
			call_deferred("emit_signal", "analysis_position_ready", i)
			var _wait_start := Time.get_ticks_msec()
			while _awaited_display_ply == i and not cancel_requested:
				if Time.get_ticks_msec() - _wait_start >= 3000:
					_awaited_display_ply = -1
					break
				OS.delay_msec(10)
		else:
			call_deferred("emit_signal", "analysis_position_ready", i)
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
				"mate_in": 1 if is_white else -1
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
		var mate_after = int(eval_after_data.get("mate_in", 0))
		var reply_best_move = eval_after_data.get("best_move", "")
		var eff_d = eval_after_data.get("depth", depth)

		# Mise à jour pour le coup suivant (le MultiPV courant concernera le coup i+1)
		var prev_move: ChessMove = moves[i - 1] if i > 0 else null
		var ply_metrics := _evaluate_ply_quality(move, i, score_before, score_after, expected_best_move,
				fen_before, pv_before, multipv_before, is_white, legal_moves_count, prev_move)
		prev_score_cp = score_after
		prev_best_move = reply_best_move
		prev_fen = fen_after
		prev_pv = eval_after_data.get("pv_line", [])
		prev_multipv = eval_after_data.get("multipv_lines", [])

		var quality: int = ply_metrics["quality"]
		var cp_loss: int = ply_metrics["cp_loss"]
		var is_theory: bool = ply_metrics["is_theory"]
		var time_spent := -1.0
		if i < clock_deltas.size():
			time_spent = float(clock_deltas[i])

		# Les coups de théorie n'entrent ni dans l'ACPL, ni dans la précision, ni dans l'ELO.
		if not is_theory:
			if is_white:
				white_loss_sum += cp_loss
				white_moves_count += 1
			else:
				black_loss_sum += cp_loss
				black_moves_count += 1
		if is_white:
			_increment_quality_stat(white_stats, quality)
		else:
			_increment_quality_stat(black_stats, quality)

		move.quality = quality
		move.centipawn_loss = cp_loss
		move.eval_before_cp = score_before
		move.eval_after_cp = score_after
		move.is_theory = is_theory
		move.motifs = ply_metrics["motifs"]
		move.best_move_uci = expected_best_move if expected_best_move != "" else reply_best_move

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
			"mate_in": mate_after,
			"loss_cp": cp_loss,
			"quality": quality,
			"win_before": ply_metrics["win_before"],
			"win_after": ply_metrics["win_after"],
			"winpct_loss": ply_metrics["winpct_loss"],
			"is_theory": is_theory,
			"motifs": ply_metrics["motifs"],
			"complexity": ply_metrics["complexity"],
			"time_spent_sec": time_spent,
			"best_move": reply_best_move,
			"best_alternative": expected_best_move,
			"fen": fen_after,
			"depth": eff_d,
			"ci_margin": eval_ci,
			"ci_lower": score_after - eval_ci,
			"ci_upper": score_after + eval_ci,
			"pv_line": pv_before.duplicate() if pv_before is Array else []
		}
		move_evaluations.append(move_record)

		progress_updated.emit(i + 1, total_plies)
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
	_apply_elo_metadata(w_stat, b_stat)
	elo_stat_test = _perform_elo_comparison_test(w_stat, b_stat)

	is_analyzing = false
	_restore_default_multipv()
	var report = _build_final_report()
	call_deferred("emit_signal", "analysis_finished", report)
	return report

## Analyse asynchrone non-bloquante avec await (indispensable pour WebAssembly / HTML5 sans threads)
func start_game_analysis_async(game: ChessGame, depth: int = 14, options: Dictionary = {}) -> Dictionary:
	if str(options.get("mode", "")) == "budget":
		return await _start_game_analysis_budget_async(game, depth, options)
	is_analyzing = true
	cancel_requested = false
	_awaited_display_ply = -1
	move_evaluations.clear()
	
	if options.has("depth") and int(options["depth"]) > 0:
		depth = int(options["depth"])
	if not engine_manager:
		engine_manager = _get_engine_manager()

	_reset_stats()
	
	var sm = _get_settings_manager()
	var mode: String = str(options.get("mode", sm.get_setting("analysis_mode", "dynamic") if sm else "dynamic"))
	var time_per_move: float = float(options.get("time_per_move", sm.get_setting("analysis_time_per_move", 0.2) if sm else 0.2))
	var dynamic_base: float = float(options.get("dynamic_base", sm.get_setting("analysis_dynamic_base", 0.08) if sm else 0.08))
	var dynamic_max: float = float(options.get("dynamic_max", sm.get_setting("analysis_dynamic_max", 0.25) if sm else 0.25))
	var wait_for_display: bool = bool(options.get("wait_for_display", false))

	# T1.2 — Détection de l'ouverture / sortie de théorie (exclue des métriques).
	opening_info = OpeningBook.identify(_moves_to_uci(game.move_history))
	theory_plies = int(opening_info.get("out_of_book_ply", 0))
	# MultiPV réduit à 1 pendant l'analyse de masse (accélération maximale x2.5).
	# Restauré en fin d'analyse.
	if engine_manager != null and engine_manager.has_method("set_multipv"):
		_multipv_before_analysis = int(engine_manager.default_multipv())
		engine_manager.set_multipv(1, true)

	var moves = game.move_history
	var total_plies = moves.size()
	var clock_deltas := _extract_clock_deltas(moves)
	
	if total_plies == 0:
		is_analyzing = false
		_restore_default_multipv()
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
		_release_async_engine_session()
		is_analyzing = false
		cancel_requested = false
		_restore_default_multipv()
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
	var prev_fen: String = ChessGame.INITIAL_FEN
	var prev_pv: Array = start_eval.get("pv_line", [])
	var prev_multipv: Array = start_eval.get("multipv_lines", [])
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
		var fen_before: String = prev_fen
		var pv_before: Array = prev_pv
		var multipv_before: Array = prev_multipv

		# Point 1 — Nombre de coups légaux dans la position AVANT le coup (complexité).
		var legal_moves_count := sim_game.get_legal_moves(sim_game.active_color).size()

		# Exécution du coup
		sim_game.make_move(move)
		var fen_after = sim_game.get_fen()

		# Ordre impératif en Web : la position doit être visible avant l'évaluation.
		# Ainsi chaque mise à jour `info` de Stockfish correspond exactement au
		# plateau affiché, jamais au demi-coup suivant.
		if wait_for_display:
			_awaited_display_ply = i
			analysis_position_ready.emit(i)
			# Une frame ne suffit pas : la pièce reste visuellement en transit
			# pendant `move_anim_duration`. Main.gd accuse la fin du tween.
			# Timeout de sécurité (3 s) : si le SceneTree disparaît ou que le
			# signal d'accusé ne revient jamais, on continue plutôt que de
			# bloquer l'analyse indéfiniment.
			var _wait_start := Time.get_ticks_msec()
			while _awaited_display_ply == i and not cancel_requested:
				if Time.get_ticks_msec() - _wait_start >= 3000:
					_awaited_display_ply = -1
					break
				if tree:
					await tree.process_frame
				else:
					OS.delay_msec(10)
		else:
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
				"mate_in": 1 if is_white else -1
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
		var mate_after = int(eval_after_data.get("mate_in", 0))
		var reply_best_move = eval_after_data.get("best_move", "")
		var depth_reached = eval_after_data.get("depth", depth)

		var prev_move: ChessMove = moves[i - 1] if i > 0 else null
		var ply_metrics := _evaluate_ply_quality(move, i, score_before, score_after, expected_best_move,
				fen_before, pv_before, multipv_before, is_white, legal_moves_count, prev_move)
		prev_score_cp = score_after
		prev_best_move = reply_best_move
		prev_fen = fen_after
		prev_pv = eval_after_data.get("pv_line", [])
		prev_multipv = eval_after_data.get("multipv_lines", [])

		var qual: int = ply_metrics["quality"]
		var cp_loss: int = ply_metrics["cp_loss"]
		var is_theory: bool = ply_metrics["is_theory"]
		var time_spent := -1.0
		if i < clock_deltas.size():
			time_spent = float(clock_deltas[i])

		if not is_theory:
			if is_white:
				white_loss_sum += cp_loss
				white_moves_count += 1
			else:
				black_loss_sum += cp_loss
				black_moves_count += 1
		if is_white:
			_increment_quality_stat(white_stats, qual)
		else:
			_increment_quality_stat(black_stats, qual)

		move.quality = qual
		move.centipawn_loss = cp_loss
		move.eval_before_cp = score_before
		move.eval_after_cp = score_after
		move.is_theory = is_theory
		move.motifs = ply_metrics["motifs"]
		move.best_move_uci = expected_best_move if expected_best_move != "" else reply_best_move

		var is_tactical = (qual == ChessMove.Quality.BRILLIANT or qual == ChessMove.Quality.BLUNDER or abs(score_after - score_before) > 75)
		var eval_ci = _calculate_eval_ci_margin(depth_reached, cp_loss, is_tactical)
		var move_record = {
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": is_white,
			"san": move.san,
			"uci": move.uci,
			"score_cp": score_after,
			"mate_in": mate_after,
			"loss_cp": cp_loss,
			"quality": qual,
			"win_before": ply_metrics["win_before"],
			"win_after": ply_metrics["win_after"],
			"winpct_loss": ply_metrics["winpct_loss"],
			"is_theory": is_theory,
			"motifs": ply_metrics["motifs"],
			"complexity": ply_metrics["complexity"],
			"time_spent_sec": time_spent,
			"best_move": reply_best_move,
			"best_alternative": expected_best_move,
			"fen": fen_after,
			"depth": depth_reached,
			"ci_margin": eval_ci,
			"ci_lower": score_after - eval_ci,
			"ci_upper": score_after + eval_ci,
			"pv_line": pv_before.duplicate() if pv_before is Array else []
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
	_apply_elo_metadata(w_stat, b_stat)
	elo_stat_test = _perform_elo_comparison_test(w_stat, b_stat)

	_release_async_engine_session()
	is_analyzing = false
	_restore_default_multipv()
	var report = _build_final_report()
	analysis_finished.emit(report)
	return report

func cancel_analysis() -> void:
	cancel_requested = true
	is_analyzing = false
	_awaited_display_ply = -1

## Accusé de réception de Main.gd : le plateau a fini d'afficher ce demi-coup.
func confirm_analysis_position_displayed(ply_idx: int) -> void:
	if ply_idx == _awaited_display_ply:
		_awaited_display_ply = -1

func _release_async_engine_session() -> void:
	if engine_manager and engine_manager.has_method("finish_async_analysis_session"):
		engine_manager.finish_async_analysis_session()

func _reset_stats() -> void:
	for k in white_stats.keys():
		white_stats[k] = 0
		black_stats[k] = 0

## T0.2/T0.3/T0.4/T1.2/T1.4 + Plan ELO avancé (point 1) — Calcule les métriques d'un
## demi-coup à partir des évaluations avant/après, de la ligne principale et du MultiPV
## de la position AVANT le coup. Ne touche pas aux sommes ACPL/aux compteurs (fait par l'appelant).
## `legal_moves_count` (nb de coups légaux avant le coup) et `prev_move` (demi-coup
## précédent, pour la détection de recapture évidente) alimentent l'indice de complexité.
func _evaluate_ply_quality(
		move: ChessMove, ply: int, score_before: int, score_after: int,
		expected_best_move: String, prev_fen: String, prev_pv: Array,
		prev_multipv: Array, is_white: bool, legal_moves_count: int = -1,
		prev_move: ChessMove = null) -> Dictionary:
	var is_theory := ply < theory_plies
	var win_before := MoveQualityService.win_for(score_before, is_white)
	var win_after := MoveQualityService.win_for(score_after, is_white)
	var loss_cp := maxi(0, score_before - score_after) if is_white else maxi(0, score_after - score_before)

	var quality := ChessMove.Quality.NONE
	var motifs: Array = []
	var complexity := 1.0
	if not is_theory:
		var second_score: int = MoveQualityService.NO_SECOND_LINE
		var has_second := false
		if prev_multipv is Array and prev_multipv.size() >= 2:
			var second_line: Dictionary = prev_multipv[1]
			second_score = int(second_line.get("score_cp", MoveQualityService.NO_SECOND_LINE))
			has_second = true
		var pv: Array = prev_pv if prev_pv is Array else []
		# Le sacrifice n'est testé que pour le coup #1 non-pion (prérequis au « brillant ») :
		# évite une simulation coûteuse sur chaque demi-coup.
		var is_sac := false
		if move.uci == expected_best_move and move.piece != ChessPiece.Type.PAWN and win_after < 95.0:
			is_sac = MoveQualityService.is_sacrifice(prev_fen, move.uci, pv)
		quality = MoveQualityService.classify(move.uci, expected_best_move, score_before, score_after,
				loss_cp, is_white, is_sac, second_score)
		# Point 1 — Indice de complexité : coup forcé, recapture évidente, écart à la 2e ligne.
		var is_recapture := false
		if prev_move != null and int(move.captured_piece) != ChessPiece.Type.NONE \
				and int(prev_move.captured_piece) != ChessPiece.Type.NONE \
				and prev_move.to_sq == move.to_sq:
			is_recapture = true
		var second_gap := -1.0
		if has_second and second_score != MoveQualityService.NO_SECOND_LINE:
			second_gap = maxf(0.0, win_before - MoveQualityService.win_for(second_score, is_white))
		complexity = MoveQualityService.move_complexity(legal_moves_count, is_recapture, second_gap)
		# Motifs calculés uniquement pour les coups notables (perf + pertinence).
		if MoveQualityService.group(quality) > 0 or quality == ChessMove.Quality.BRILLIANT or quality == ChessMove.Quality.GREAT:
			motifs = TacticalMotifDetector.detect(prev_fen, move.uci)

	return {
		"quality": quality,
		"cp_loss": loss_cp,
		"win_before": win_before,
		"win_after": win_after,
		"winpct_loss": MoveQualityService.winpct_loss(win_before, win_after),
		"is_theory": is_theory,
		"complexity": complexity,
		"motifs": motifs
	}

## Liste des coups au format UCI pour l'identification d'ouverture.
func _moves_to_uci(history: Array) -> Array:
	var out: Array = []
	for m in history:
		if m is ChessMove:
			out.append(m.uci)
	return out

## Point 4 — Temps passé par demi-coup (secondes) dérivé des annotations [%clk] du PGN.
## Le temps du coup i = horloge du coup précédent du MÊME camp − horloge après le coup i.
## Retourne -1.0 quand l'horloge n'est pas connue (premier coup du camp ou PGN sans %clk) :
## le facteur temps reste alors neutre (rétrocompatibilité parfaite).
static func _extract_clock_deltas(moves: Array) -> Array:
	var deltas := []
	deltas.resize(moves.size())
	for i in range(moves.size()):
		deltas[i] = -1.0
	var last_clock := {}
	for i in range(moves.size()):
		var m = moves[i]
		if not (m is ChessMove) or m.clock_sec < 0.0:
			continue
		var col := int(m.color)
		if col == ChessPiece.PieceColor.NONE:
			col = 0 if i % 2 == 0 else 1
		if last_clock.has(col):
			deltas[i] = maxf(0.0, float(last_clock[col]) - float(m.clock_sec))
		last_clock[col] = float(m.clock_sec)
	return deltas

func _increment_quality_stat(stats: Dictionary, q: ChessMove.Quality) -> void:
	match q:
		ChessMove.Quality.BRILLIANT: stats["brilliant"] += 1
		ChessMove.Quality.GREAT: stats["great"] += 1
		ChessMove.Quality.BEST: stats["best"] += 1
		ChessMove.Quality.EXCELLENT: stats["excellent"] += 1
		ChessMove.Quality.GOOD: stats["good"] += 1
		ChessMove.Quality.INACCURACY: stats["inaccuracy"] += 1
		ChessMove.Quality.MISTAKE: stats["mistake"] += 1
		ChessMove.Quality.BLUNDER: stats["blunder"] += 1
		ChessMove.Quality.MISS: stats["miss"] += 1

## Conversion centipions -> Probabilité de gain (modèle sigmoïde standard FIDE / Lichess)
## 0 cp -> 50%, +100 cp -> ~64%, +300 cp -> ~85%, +600 cp -> ~97%
func _win_percentage(score_cp: int) -> float:
	# Source unique : évite la dérive entre classification (MoveQualityService) et CAPS2/ELO.
	return MoveQualityService.win_percentage(score_cp)

## Précision CAPS2 (Chess.com / Lichess) calculée coup par coup avec pondération contextuelle :
## progressivité des premiers coups, sévérité tactique, **complexité positionnelle** (point 1)
## et **gestion du temps** (point 4, uniquement si l'horloge PGN est disponible).
func _calculate_caps_accuracy(evals: Array[Dictionary], for_white: bool) -> float:
	# Passe 1 : collecte des demi-coups du camp (perte de win%, complexité, temps, qualité).
	var records: Array = []
	var prev_cp = 20 # Score de départ égalité légère blanc

	for ev in evals:
		var cur_cp = ev.get("score_cp", 0)
		var is_white_move = ev.get("is_white", true)

		# T1.2 — La théorie d'ouverture est exclue de la précision.
		if ev.get("is_theory", false):
			prev_cp = cur_cp
			continue

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
			records.append({
				"acc": acc,
				"ply": int(ev.get("ply", 0)),
				"quality": int(ev.get("quality", ChessMove.Quality.NONE)),
				"complexity": float(ev.get("complexity", 1.0)),
				"time": float(ev.get("time_spent_sec", -1.0))
			})

		prev_cp = cur_cp

	if records.is_empty():
		return 50.0

	# Temps moyen par coup du camp (si des données d'horloge existent).
	var time_sum := 0.0
	var time_count := 0
	for r in records:
		if float(r["time"]) >= 0.0:
			time_sum += float(r["time"])
			time_count += 1
	var mean_time := -1.0
	if time_count > 0:
		mean_time = time_sum / float(time_count)

	# Passe 2 : pondération composite de chaque coup.
	var move_accuracies: Array[float] = []
	var move_weights: Array[float] = []
	for r in records:
		var weight = 1.0
		var ply_idx: int = r["ply"]
		# 1. Les tous premiers coups d'ouverture théoriques (plies 0 à 6) ont un poids progressif
		# pour éviter une sur-évaluation artificielle de 100% sur les débuts de partie.
		if ply_idx < 6:
			weight = 0.65 + (float(ply_idx) / 6.0) * 0.35 # 0.65 -> 1.0
		# 2. Les coups tactiques décisifs ou gaffes critiques comptent pleinement
		var qual: int = r["quality"]
		if qual == ChessMove.Quality.BLUNDER or qual == ChessMove.Quality.BRILLIANT:
			weight *= 1.25
		# 3. Point 1 — un coup trouvé dans une position complexe compte plus qu'un coup forcé.
		weight *= clampf(float(r["complexity"]), MoveQualityService.COMPLEXITY_MIN, MoveQualityService.COMPLEXITY_MAX)
		# 4. Point 4 — modulation par le temps dépensé vs la cadence du joueur.
		weight *= _time_weight_factor(float(r["time"]), float(r["complexity"]), mean_time)
		move_accuracies.append(float(r["acc"]))
		move_weights.append(weight)

	var sum_acc = 0.0
	var sum_weights = 0.0
	for j in range(move_accuracies.size()):
		var w = move_weights[j]
		sum_acc += move_accuracies[j] * w
		sum_weights += w

	if sum_weights <= 0.0:
		return 50.0

	return clampf(sum_acc / sum_weights, 5.0, 99.8)

## Point 4 — Facteur de poids lié à la pendule (neutre = 1.0 sans horloge).
## - Intuition tactique : coup complexe (C > 1.3) trouvé très vite (< 0.3 × temps moyen) → léger sur-poids.
## - Hésitation sur l'évident : beaucoup de temps (> 2.5 × temps moyen) sur une position triviale (C < 0.4) → léger sous-poids.
static func _time_weight_factor(time_sec: float, complexity: float, mean_time: float) -> float:
	if time_sec < 0.0 or mean_time <= 0.0:
		return 1.0
	if complexity > 1.3 and time_sec < 0.3 * mean_time:
		return 1.1
	if complexity < 0.4 and time_sec > 2.5 * mean_time:
		return 0.9
	return 1.0

## Modèle d'estimation ELO réaliste et étalonné (branche CAPS2)
## Évite l'inflation absurde à 2800 ELO sur les ouvertures courtes
func _estimate_elo(accuracy: float, acpl: float, stats: Dictionary, moves_count: int) -> int:
	if moves_count == 0:
		return 1500

	# 1. Base ELO dérivée de la précision de jeu (étalonné sur Chess.com Game Review)
	var base_elo: float = _accuracy_to_elo_base(accuracy)

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

## ── Courbe de calibrage partagée (CAPS2 ↔ ELO) ──────────────────────────────

## Base ELO en fonction de la précision CAPS2 (segments linéaires, étalonnage Chess.com).
static func _accuracy_to_elo_base(accuracy: float) -> float:
	if accuracy >= 98.0:
		return 2500.0 + (accuracy - 98.0) * 125.0 # 98% -> 2500, 100% -> 2750
	elif accuracy >= 95.0:
		return 2200.0 + (accuracy - 95.0) * 100.0 # 95% -> 2200, 98% -> 2500
	elif accuracy >= 90.0:
		return 1850.0 + (accuracy - 90.0) * 70.0  # 90% -> 1850, 95% -> 2200
	elif accuracy >= 82.0:
		return 1500.0 + (accuracy - 82.0) * 43.75 # 82% -> 1500, 90% -> 1850
	elif accuracy >= 72.0:
		return 1200.0 + (accuracy - 72.0) * 30.0  # 72% -> 1200, 82% -> 1500
	elif accuracy >= 60.0:
		return 900.0 + (accuracy - 60.0) * 25.0   # 60% -> 900,  72% -> 1200
	elif accuracy >= 45.0:
		return 600.0 + (accuracy - 45.0) * 20.0   # 45% -> 600,  60% -> 900
	return maxf(300.0, 300.0 + accuracy * 6.66)   # <45% -> 300 à 600

## Pente locale dELO/dPrécision de la courbe de calibrage (pour les IC).
static func _elo_slope_for_accuracy(accuracy: float) -> float:
	if accuracy >= 98.0:
		return 125.0
	elif accuracy >= 95.0:
		return 100.0
	elif accuracy >= 90.0:
		return 70.0
	elif accuracy >= 82.0:
		return 43.75
	elif accuracy >= 72.0:
		return 30.0
	elif accuracy >= 60.0:
		return 25.0
	elif accuracy >= 45.0:
		return 20.0
	return 6.66

## Inverse de la courbe de calibrage : ELO → précision CAPS2 attendue (monotone croissante).
static func _elo_base_to_accuracy(elo: float) -> float:
	if elo >= 2500.0:
		return 98.0 + (elo - 2500.0) / 125.0
	elif elo >= 2200.0:
		return 95.0 + (elo - 2200.0) / 100.0
	elif elo >= 1850.0:
		return 90.0 + (elo - 1850.0) / 70.0
	elif elo >= 1500.0:
		return 82.0 + (elo - 1500.0) / 43.75
	elif elo >= 1200.0:
		return 72.0 + (elo - 1200.0) / 30.0
	elif elo >= 900.0:
		return 60.0 + (elo - 900.0) / 25.0
	elif elo >= 600.0:
		return 45.0 + (elo - 600.0) / 20.0
	return clampf((elo - 300.0) / 6.66, 0.0, 45.0)

## ── Point 2 — Modèle IPR de Ken Regan (Intrinsic Performance Rating) ─────────
## Modèle log-odds : la probabilité qu'un joueur de niveau θ joue un coup perdant
## δ points de win% décroît exponentiellement, P(m | θ) ∝ exp(-λ(θ) · δ), où
## λ(θ) = 1/μ(θ) et μ(θ) = perte moyenne de win% attendue au niveau θ (déduite de la
## courbe CAPS2 via la formule inverse de la précision par coup).
## L'estimateur est la vraisemblance maximale (MLE) pondérée par la complexité :
## le maximum est atteint pour μ(θ) = μ̂ = Σ(wᵢ·δᵢ) / Σwᵢ ; on résout μ(θ) = μ̂
## par bisection monotone sur [300, 2850] (convergence garantie, < 5 ms).

## Perte moyenne de win% attendue (par coup) d'un joueur de niveau `elo` (dérivée CAPS2).
static func _regan_mu(elo: float) -> float:
	var acc := clampf(_elo_base_to_accuracy(elo), 0.0, 99.95)
	var mu := log(103.1668 / (acc + 3.1669)) / 0.04354
	return clampf(mu, 0.0, 120.0)

## Log-vraisemblance pondérée des pertes observées sous le modèle exponentiel de paramètre μ.
static func _regan_log_likelihood(mu: float, losses: Array[float], weights: Array[float]) -> float:
	var lam := 1.0 / maxf(0.02, mu)
	var ll := 0.0
	for j in range(losses.size()):
		var w = weights[j]
		ll += w * (log(lam) - lam * losses[j])
	return ll

## Recherche du paramètre de sensibilité maximisant la vraisemblance :
## grille grossière sur [300, 2850] (pas de 50) puis bisection locale par dichotomie
## sur la dérivée de la log-vraisemblance (fonction concave en μ).
func _estimate_elo_regan_ipr(evals: Array[Dictionary], for_white: bool) -> Dictionary:
	var losses: Array[float] = []
	var weights: Array[float] = []
	for ev in evals:
		if ev.get("is_theory", false):
			continue
		if bool(ev.get("is_white", true)) != for_white:
			continue
		losses.append(maxf(0.0, float(ev.get("winpct_loss", 0.0))))
		weights.append(clampf(float(ev.get("complexity", 1.0)),
				MoveQualityService.COMPLEXITY_MIN, MoveQualityService.COMPLEXITY_MAX))
	if losses.is_empty():
		return {"elo": 1500, "mean_loss": 0.0, "n": 0}

	var wsum := 0.0
	var wloss := 0.0
	for j in range(losses.size()):
		wsum += weights[j]
		wloss += weights[j] * losses[j]
	var mean_loss := wloss / maxf(0.001, wsum)

	var lo := 300.0
	var hi := 2850.0
	# MLE en λ : λ* = Σw / Σ(w·δ) → μ̂ = 1/λ* = moyenne pondérée des pertes.
	var mu_star := mean_loss
	# Bornes : pertes quasi nulles → plafond ; pertes massives → plancher.
	if mu_star <= _regan_mu(hi):
		return {"elo": int(hi), "mean_loss": mean_loss, "n": losses.size()}
	if mu_star >= _regan_mu(lo):
		return {"elo": int(lo), "mean_loss": mean_loss, "n": losses.size()}
	# Grille grossière (sécurité anti-concavité locale), puis bisection monotone sur μ(elo).
	var grid_best_elo := lo
	var grid_best_ll := -INF
	var e := lo
	while e <= hi + 0.5:
		var ll := _regan_log_likelihood(_regan_mu(e), losses, weights)
		if ll > grid_best_ll:
			grid_best_ll = ll
			grid_best_elo = e
		e += 50.0
	var span := 50.0
	var blo := maxf(lo, grid_best_elo - span)
	var bhi := minf(hi, grid_best_elo + span)
	# μ(elo) est strictement décroissante : bisection sur μ(elo) - μ̂.
	for _it in range(40):
		var mid := 0.5 * (blo + bhi)
		if _regan_mu(mid) > mu_star:
			blo = mid
		else:
			bhi = mid
	var ipr_elo := int(round(clampf(0.5 * (blo + bhi), 300.0, 2850.0)))
	return {"elo": ipr_elo, "mean_loss": mean_loss, "n": losses.size()}

## Complexité moyenne pondérée des demi-coups du camp (métadonnée explicative du rapport).
func _average_complexity(evals: Array[Dictionary], for_white: bool) -> float:
	var total := 0.0
	var count := 0
	for ev in evals:
		if ev.get("is_theory", false):
			continue
		if bool(ev.get("is_white", true)) != for_white:
			continue
		total += clampf(float(ev.get("complexity", 1.0)), MoveQualityService.COMPLEXITY_MIN, MoveQualityService.COMPLEXITY_MAX)
		count += 1
	return (total / float(count)) if count > 0 else 1.0

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

## T1.1 — Restaure le MultiPV demandé par l'utilisateur après l'analyse de masse.
func _restore_default_multipv() -> void:
	if engine_manager != null and engine_manager.has_method("set_multipv"):
		var target: int = _multipv_before_analysis if _multipv_before_analysis > 0 else int(engine_manager.default_multipv())
		engine_manager.set_multipv(target, true)
	_multipv_before_analysis = -1

func _fail_analysis(msg: String) -> Dictionary:
	_release_async_engine_session()
	is_analyzing = false
	_restore_default_multipv()
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

## Estimation ELO biostatistique avec intervalle de confiance à 95%.
## Synthèse hybride du plan : 60% modèle IPR Regan (MLE pondérée complexité) +
## 40% branche CAPS2 calibrée, modulée par la gestion du temps (%clk) si disponible.
## Les statistiques de précision (variance, effectif efficace) sont pondérées par
## wᵢ = Cᵢ (complexité) × facteur temps, conformément au plan.
func _calculate_elo_statistics(evals: Array[Dictionary], for_white: bool, accuracy: float, acpl: float, stats: Dictionary, moves_count: int) -> Dictionary:
	var ipr_data = _estimate_elo_regan_ipr(evals, for_white)
	var complexity_avg = _average_complexity(evals, for_white)
	var base_elo = _estimate_elo(accuracy, acpl, stats, moves_count)
	if moves_count <= 0:
		return {"elo": base_elo, "se": 70.0, "ci_margin": 140, "ci_lower": base_elo - 140, "ci_upper": base_elo + 140,
				"n": 0, "ipr_elo": int(ipr_data.get("elo", 1500)), "complexity_avg": complexity_avg,
				"time_delta": 0.0, "has_clock": false}
	
	var move_accuracies: Array[float] = []
	var move_weights: Array[float] = []
	var move_times: Array[float] = []
	var move_complexities: Array[float] = []
	var prev_cp = 20
	var time_sum := 0.0
	var time_count := 0
	for ev in evals:
		var cur_cp = ev.get("score_cp", 0)
		var is_w = ev.get("is_white", true)
		if ev.get("is_theory", false):
			prev_cp = cur_cp
			continue
		if is_w == for_white:
			var win_before = _win_percentage(prev_cp) if for_white else (100.0 - _win_percentage(prev_cp))
			var win_after = _win_percentage(cur_cp) if for_white else (100.0 - _win_percentage(cur_cp))
			var win_loss = maxf(0.0, win_before - win_after)
			var acc = clampf(103.1668 * exp(-0.04354 * win_loss) - 3.1669, 0.0, 100.0)
			var c := clampf(float(ev.get("complexity", 1.0)),
					MoveQualityService.COMPLEXITY_MIN, MoveQualityService.COMPLEXITY_MAX)
			var t := float(ev.get("time_spent_sec", -1.0))
			if t >= 0.0:
				time_sum += t
				time_count += 1
			move_accuracies.append(acc)
			move_complexities.append(c)
			move_times.append(t)
		prev_cp = cur_cp
	
	var mean_time := -1.0
	if time_count > 0:
		mean_time = time_sum / float(time_count)
	var n = move_accuracies.size()
	for j in range(n):
		# Poids composite : complexité (point 1) × facteur temps (point 4, neutre sans %clk).
		move_weights.append(move_complexities[j] * _time_weight_factor(move_times[j], move_complexities[j], mean_time))
	
	var sum_w := 0.0
	var sum_w2 := 0.0
	var var_acc := 0.0
	for j in range(n):
		var w = move_weights[j]
		sum_w += w
		sum_w2 += w * w
		var_acc += w * pow(move_accuracies[j] - accuracy, 2)
	var s_acc := sqrt(maxf(0.0, (var_acc / sum_w) if sum_w > 0.0 else 0.0))
	# Effectif échantillonnal effectif de Kish (poids inégaux : (Σw)²/Σw²).
	var n_eff := float(n)
	if sum_w2 > 0.0 and sum_w > 0.0:
		n_eff = (sum_w * sum_w) / sum_w2
	n_eff = clampf(n_eff, 1.0, float(n))
	var se_acc = s_acc / sqrt(n_eff)
	
	# Pente locale dELO/dA dérivée de la fonction de calibrage
	var slope = _elo_slope_for_accuracy(accuracy)
	
	var sample_mult = sqrt(20.0 / n_eff) if n_eff < 20.0 else 1.0
	var se_elo = maxf(28.0, slope * se_acc * sample_mult)
	var t_crit = 1.96 if n >= 20 else (2.10 if n >= 10 else 2.30)
	var ci_margin = int(round(t_crit * se_elo))
	
	# IPR ajusté par la confiance d'échantillon (même amortisseur que la branche CAPS2).
	var confidence = clampf(float(moves_count) / 20.0, 0.25, 1.0)
	var ipr_raw = float(ipr_data.get("elo", base_elo))
	var ipr_adj = ipr_raw * confidence + 1250.0 * (1.0 - confidence)
	
	# Synthèse robuste : 60 % IPR (modélisation probabiliste) + 40 % CAPS2 (calibrage empirique).
	var combined = 0.6 * ipr_adj + 0.4 * float(base_elo)
	
	# Point 4 — modulation finale par la gestion du temps (neutre sans %clk).
	var time_mod = _compute_time_management(evals, for_white, moves_count)
	combined += float(time_mod.get("elo_delta", 0.0))
	
	# Point 1 — Amortisseur d'information : une partie faite de coups triviaux
	# (forcés / recaptures, complexité < neutre) porte peu de signal → régression
	# vers l'ancrage médian ; les positions complexes ne dépassent jamais le plafond.
	var cx_conf = clampf(complexity_avg / MoveQualityService.COMPLEXITY_NEUTRAL, 0.4, 1.0)
	combined = combined * cx_conf + 1250.0 * (1.0 - cx_conf)
	
	var final_elo = clampi(int(round(combined)), 300, 2850)
	
	return {
		"elo": final_elo,
		"se": se_elo,
		"ci_margin": ci_margin,
		"ci_lower": final_elo - ci_margin,
		"ci_upper": final_elo + ci_margin,
		"n": n,
		"ipr_elo": int(round(ipr_adj)),
		"complexity_avg": complexity_avg,
		"time_delta": float(time_mod.get("elo_delta", 0.0)),
		"has_clock": bool(time_mod.get("has_clock", false))
	}

## Point 4 — Modulation ELO par la gestion du temps (±60 ELO max, neutre sans horloge).
## - Intuition tactique : coups complexes (C > 1.3) joués très vite (< 0.3 × temps moyen) → bonus.
## - Hésitation sur l'évident : coups triviaux (C < 0.4) qui ont coûté > 2.5 × le temps moyen → amortisseur.
func _compute_time_management(evals: Array[Dictionary], for_white: bool, moves_count: int) -> Dictionary:
	if moves_count <= 0:
		return {"elo_delta": 0.0, "has_clock": false, "fast_count": 0, "slow_count": 0}
	var time_sum := 0.0
	var time_count := 0
	var complexities: Array[float] = []
	var times: Array[float] = []
	for ev in evals:
		if ev.get("is_theory", false):
			continue
		if bool(ev.get("is_white", true)) != for_white:
			continue
		var c = clampf(float(ev.get("complexity", 1.0)), MoveQualityService.COMPLEXITY_MIN, MoveQualityService.COMPLEXITY_MAX)
		var t = float(ev.get("time_spent_sec", -1.0))
		complexities.append(c)
		times.append(t)
		if t >= 0.0:
			time_sum += t
			time_count += 1
	if time_count == 0:
		return {"elo_delta": 0.0, "has_clock": false, "fast_count": 0, "slow_count": 0}
	var mean_time := time_sum / float(time_count)
	var fast := 0
	var slow := 0
	for j in range(complexities.size()):
		var t = times[j]
		if t < 0.0:
			continue
		if complexities[j] > 1.3 and t < 0.3 * mean_time:
			fast += 1
		elif complexities[j] < 0.4 and t > 2.5 * mean_time:
			slow += 1
	var bonus := 60.0 * float(fast) / float(maxi(1, moves_count))
	var penalty := 40.0 * float(slow) / float(maxi(1, moves_count))
	return {"elo_delta": bonus - penalty, "has_clock": true, "fast_count": fast, "slow_count": slow}

## Propage les métadonnées explicatives du modèle enrichi (IPR, complexité, horloge).
func _apply_elo_metadata(w_stat: Dictionary, b_stat: Dictionary) -> void:
	white_ipr_elo = int(w_stat.get("ipr_elo", white_estimated_elo))
	black_ipr_elo = int(b_stat.get("ipr_elo", black_estimated_elo))
	white_complexity_avg = float(w_stat.get("complexity_avg", 1.0))
	black_complexity_avg = float(b_stat.get("complexity_avg", 1.0))
	has_clock_data = bool(w_stat.get("has_clock", false)) or bool(b_stat.get("has_clock", false))

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
			# Approfondissement automatique réservé aux vraies bascules critiques / tactiques
			if delta_cp >= 80 or abs(score_cand) >= 400:
				var factor = clampf(float(delta_cp - 80) / 120.0, 0.25, 1.0)
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
			if delta_cp >= 80 or abs(score_cand) >= 400:
				var factor = clampf(float(delta_cp - 80) / 120.0, 0.25, 1.0)
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

## ============================================================================
## Analyse à budget (proto) — passe A peu profonde + passe B sur les plies critiques
## ============================================================================

## Éval synthétique d'une position terminale (mat/pat) ; {} si non terminale.
func _budget_terminal_eval(sim_game: ChessGame, move: ChessMove, is_white: bool, depth: int) -> Dictionary:
	var is_mate = move.is_checkmate or move.san.ends_with("#") or (sim_game.is_in_check(sim_game.active_color) and sim_game.get_legal_moves(sim_game.active_color).is_empty())
	if is_mate:
		return {
			"score_cp": 10000 if is_white else -10000,
			"mate_in": 1 if is_white else -1,
			"best_move": move.uci,
			"depth": depth,
			"pv_line": [],
			"multipv_lines": [],
			"timed_out": false,
			"cancelled": false
		}
	var is_stalemate = (not sim_game.is_in_check(sim_game.active_color)) and sim_game.get_legal_moves(sim_game.active_color).is_empty()
	if is_stalemate:
		return {
			"score_cp": 0, "mate_in": 0, "best_move": "", "depth": depth,
			"pv_line": [], "multipv_lines": [], "timed_out": false, "cancelled": false
		}
	return {}

## Score de criticité d'un demi-coup (à partir de sa classification provisoire) :
## perte de win%, sévérité de la qualité, motifs tactiques et transitions de mat.
func _budget_criticality(rec: Dictionary) -> float:
	if bool(rec.get("is_theory", false)):
		return 0.0
	var crit := float(rec.get("winpct_loss", 0.0))
	match int(rec.get("quality", ChessMove.Quality.NONE)):
		ChessMove.Quality.BLUNDER, ChessMove.Quality.MISS:
			crit += 8.0
		ChessMove.Quality.MISTAKE:
			crit += 4.0
	var motifs = rec.get("motifs", [])
	if motifs is Array and not motifs.is_empty():
		crit += 6.0
	if absi(int(rec.get("score_cp", 0))) >= 9000:
		crit += 20.0
	return crit

## Reconstruit le dossier de qualité d'un coup à partir de ses positions avant/après.
func _classify_move(i: int, moves: Array, pos_evals: Array, depth: int) -> Dictionary:
	var move: ChessMove = moves[i]
	var before: Dictionary = pos_evals[i]
	var after: Dictionary = pos_evals[i + 1]
	var is_white := (i % 2 == 0)
	var score_before := int(before.get("score_cp", 0))
	var score_after := int(after.get("score_cp", 0))
	var mate_after := int(after.get("mate_in", 0))
	var expected_best_move := str(before.get("best_move", ""))
	var reply_best_move := str(after.get("best_move", ""))
	var fen_before := str(before.get("fen", ""))
	var eff_d := int(after.get("depth", depth))
	var before_pv: Array = before.get("pv_line", [])
	if not (before_pv is Array):
		before_pv = []
	var before_mpv: Array = before.get("multipv_lines", [])
	if not (before_mpv is Array):
		before_mpv = []
	# Point 1 — complexité : nb de coups légaux avant le coup (reconstruction FEN) + recapture.
	var legal_moves_count := -1
	if fen_before != "":
		var sim = ChessGame.new()
		if sim.load_fen(fen_before):
			legal_moves_count = sim.get_legal_moves(sim.active_color).size()
	var prev_move: ChessMove = moves[i - 1] if i > 0 else null
	var ply_metrics := _evaluate_ply_quality(move, i, score_before, score_after, expected_best_move,
			fen_before, before_pv, before_mpv, is_white, legal_moves_count, prev_move)
	var quality: int = ply_metrics["quality"]
	var cp_loss: int = ply_metrics["cp_loss"]
	var is_theory: bool = ply_metrics["is_theory"]
	move.quality = quality
	move.centipawn_loss = cp_loss
	move.eval_before_cp = score_before
	move.eval_after_cp = score_after
	move.is_theory = is_theory
	move.motifs = ply_metrics["motifs"]
	move.best_move_uci = expected_best_move if expected_best_move != "" else reply_best_move
	var is_tactical = (quality == ChessMove.Quality.BRILLIANT or quality == ChessMove.Quality.BLUNDER or absi(score_after - score_before) > 75)
	var eval_ci = _calculate_eval_ci_margin(eff_d, cp_loss, is_tactical)
	return {
		"ply": i,
		"move_number": (i / 2) + 1,
		"is_white": is_white,
		"san": move.san,
		"uci": move.uci,
		"score_cp": score_after,
		"mate_in": mate_after,
		"loss_cp": cp_loss,
		"quality": quality,
		"win_before": ply_metrics["win_before"],
		"win_after": ply_metrics["win_after"],
		"winpct_loss": ply_metrics["winpct_loss"],
		"is_theory": is_theory,
		"motifs": ply_metrics["motifs"],
		"complexity": ply_metrics["complexity"],
		"time_spent_sec": -1.0,
		"best_move": reply_best_move,
		"best_alternative": expected_best_move,
		"fen": str(after.get("fen", "")),
		"depth": eff_d,
		"ci_margin": eval_ci,
		"ci_lower": score_after - eval_ci,
		"ci_upper": score_after + eval_ci,
		"pv_line": before_pv.duplicate()
	}

## Reconstruit toutes les évaluations + métriques agrégées à partir de pos_evals.
func _finalize_from_evals(moves: Array, pos_evals: Array, depth: int) -> void:
	move_evaluations.clear()
	_reset_stats()
	var clock_deltas := _extract_clock_deltas(moves)
	var white_loss_sum := 0
	var black_loss_sum := 0
	var white_moves_count := 0
	var black_moves_count := 0
	var n := maxi(0, pos_evals.size() - 1)
	for i in range(n):
		var rec := _classify_move(i, moves, pos_evals, depth)
		if i < clock_deltas.size():
			rec["time_spent_sec"] = float(clock_deltas[i])
		move_evaluations.append(rec)
		if not bool(rec.get("is_theory", false)):
			if bool(rec.get("is_white", true)):
				white_loss_sum += int(rec.get("loss_cp", 0))
				white_moves_count += 1
			else:
				black_loss_sum += int(rec.get("loss_cp", 0))
				black_moves_count += 1
		if bool(rec.get("is_white", true)):
			_increment_quality_stat(white_stats, int(rec.get("quality", ChessMove.Quality.NONE)))
		else:
			_increment_quality_stat(black_stats, int(rec.get("quality", ChessMove.Quality.NONE)))
	white_acpl = float(white_loss_sum) / maxi(1, white_moves_count)
	black_acpl = float(black_loss_sum) / maxi(1, black_moves_count)
	white_accuracy = _calculate_caps_accuracy(move_evaluations, true)
	black_accuracy = _calculate_caps_accuracy(move_evaluations, false)
	var w_stat = _calculate_elo_statistics(move_evaluations, true, white_accuracy, white_acpl, white_stats, white_moves_count)
	var b_stat = _calculate_elo_statistics(move_evaluations, false, black_accuracy, black_acpl, black_stats, black_moves_count)
	white_estimated_elo = w_stat["elo"]
	black_estimated_elo = b_stat["elo"]
	white_elo_ci_margin = w_stat["ci_margin"]
	black_elo_ci_margin = b_stat["ci_margin"]
	_apply_elo_metadata(w_stat, b_stat)
	elo_stat_test = _perform_elo_comparison_test(w_stat, b_stat)

func _budget_select_positions(provisional: Array, max_deep: int, min_crit: float) -> Array:
	var ranked: Array = []
	for i in range(provisional.size()):
		var crit := _budget_criticality(provisional[i])
		if crit >= min_crit:
			ranked.append({"idx": i, "crit": crit})
	ranked.sort_custom(func(a, b): return float(a["crit"]) > float(b["crit"]))
	var to_deepen := {}
	var picked := 0
	for item in ranked:
		if picked >= max_deep:
			break
		to_deepen[int(item["idx"])] = true
		to_deepen[int(item["idx"]) + 1] = true
		picked += 1
	var keys := to_deepen.keys()
	keys.sort()
	return keys

func _budget_deepen_critical_sync(pos_evals: Array, provisional: Array, deep_depth: int, max_deep: int, min_crit: float, deep_ms: int) -> void:
	if max_deep <= 0 or pos_evals.size() < 2:
		return
	for pos_idx in _budget_select_positions(provisional, max_deep, min_crit):
		if cancel_requested:
			return
		var pi := int(pos_idx)
		if pi < 0 or pi >= pos_evals.size():
			continue
		var cur: Dictionary = pos_evals[pi]
		if int(cur.get("depth", 0)) >= deep_depth:
			continue
		if absi(int(cur.get("score_cp", 0))) >= 9000:
			continue
		var fen := str(cur.get("fen", ""))
		if fen == "":
			continue
		var deep := _evaluate_fen_sync(fen, deep_depth, deep_ms)
		if deep.has("error") or cancel_requested:
			continue
		deep["fen"] = fen
		pos_evals[pi] = deep

func _budget_deepen_critical_async(pos_evals: Array, provisional: Array, deep_depth: int, max_deep: int, min_crit: float, deep_ms: int) -> void:
	if max_deep <= 0 or pos_evals.size() < 2:
		return
	for pos_idx in _budget_select_positions(provisional, max_deep, min_crit):
		if cancel_requested:
			return
		var pi := int(pos_idx)
		if pi < 0 or pi >= pos_evals.size():
			continue
		var cur: Dictionary = pos_evals[pi]
		if int(cur.get("depth", 0)) >= deep_depth:
			continue
		if absi(int(cur.get("score_cp", 0))) >= 9000:
			continue
		var fen := str(cur.get("fen", ""))
		if fen == "":
			continue
		var deep = await _evaluate_fen_async(fen, deep_depth, deep_ms)
		if deep.has("error") or cancel_requested:
			continue
		deep["fen"] = fen
		pos_evals[pi] = deep

func _start_game_analysis_budget(game: ChessGame, depth: int, options: Dictionary) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	_awaited_display_ply = -1
	move_evaluations.clear()
	if not engine_manager:
		engine_manager = _get_engine_manager()
	_reset_stats()
	var base_depth := int(options.get("base_depth", BUDGET_BASE_DEPTH))
	var deep_depth := int(options.get("deep_depth", BUDGET_DEEP_DEPTH))
	var max_deep := int(options.get("max_deep", BUDGET_MAX_DEEP))
	var min_crit := float(options.get("min_criticality", BUDGET_MIN_CRITICALITY))
	var deep_ms := int(options.get("deep_movetime_ms", BUDGET_DEEP_MOVETIME_MS))
	var wait_for_display := bool(options.get("wait_for_display", false))

	opening_info = OpeningBook.identify(_moves_to_uci(game.move_history))
	theory_plies = int(opening_info.get("out_of_book_ply", 0))
	if engine_manager != null and engine_manager.has_method("set_multipv"):
		_multipv_before_analysis = int(engine_manager.default_multipv())
		engine_manager.set_multipv(1, true)

	var moves = game.move_history
	var total_plies = moves.size()
	if total_plies == 0:
		is_analyzing = false
		_restore_default_multipv()
		var empty_rep := _build_final_report()
		call_deferred("emit_signal", "analysis_finished", empty_rep)
		return empty_rep
	if not _wait_for_engine():
		return _fail_analysis("Moteur d'échecs indisponible : impossible d'analyser la partie.")

	var sim_game = ChessGame.new()
	sim_game.load_fen(ChessGame.INITIAL_FEN)
	var pos_evals: Array = []
	var start_eval := _evaluate_fen_sync(ChessGame.INITIAL_FEN, base_depth, -1)
	if start_eval.has("error"):
		return _fail_analysis("Échec de l'évaluation de la position de départ par le moteur.")
	start_eval["fen"] = ChessGame.INITIAL_FEN
	pos_evals.append(start_eval)
	var provisional: Array = []

	for i in range(total_plies):
		if cancel_requested:
			break
		if engine_manager == null or not engine_manager.is_engine_available():
			return _fail_analysis("Le moteur d'échecs s'est arrêté en cours d'analyse de la partie.")
		var move: ChessMove = moves[i]
		var is_white := (i % 2 == 0)
		sim_game.make_move(move)
		var fen_after: String = sim_game.get_fen()
		if wait_for_display:
			_awaited_display_ply = i
			call_deferred("emit_signal", "analysis_position_ready", i)
			var _wait_start := Time.get_ticks_msec()
			while _awaited_display_ply == i and not cancel_requested:
				if Time.get_ticks_msec() - _wait_start >= 3000:
					_awaited_display_ply = -1
					break
				OS.delay_msec(10)
		else:
			call_deferred("emit_signal", "analysis_position_ready", i)
		if cancel_requested:
			break
		var after := _budget_terminal_eval(sim_game, move, is_white, base_depth)
		if after.is_empty():
			after = _evaluate_fen_sync(fen_after, base_depth, -1)
			if after.has("error"):
				return _fail_analysis("Le moteur d'échecs n'a pas pu évaluer le coup %s." % move.san)
		after["fen"] = fen_after
		pos_evals.append(after)
		var rec := _classify_move(i, moves, pos_evals, base_depth)
		provisional.append(rec)
		call_deferred("emit_signal", "progress_updated", i + 1, total_plies)
		call_deferred("emit_signal", "ply_analyzed", i, rec, {})

	if not cancel_requested:
		_budget_deepen_critical_sync(pos_evals, provisional, deep_depth, max_deep, min_crit, deep_ms)

	_finalize_from_evals(moves, pos_evals, deep_depth)
	is_analyzing = false
	_restore_default_multipv()
	var report := _build_final_report()
	call_deferred("emit_signal", "analysis_finished", report)
	return report

func _start_game_analysis_budget_async(game: ChessGame, depth: int, options: Dictionary) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	_awaited_display_ply = -1
	move_evaluations.clear()
	if not engine_manager:
		engine_manager = _get_engine_manager()
	_reset_stats()
	var base_depth := int(options.get("base_depth", BUDGET_BASE_DEPTH))
	var deep_depth := int(options.get("deep_depth", BUDGET_DEEP_DEPTH))
	var max_deep := int(options.get("max_deep", BUDGET_MAX_DEEP))
	var min_crit := float(options.get("min_criticality", BUDGET_MIN_CRITICALITY))
	var deep_ms := int(options.get("deep_movetime_ms", BUDGET_DEEP_MOVETIME_MS))
	var wait_for_display := bool(options.get("wait_for_display", false))

	opening_info = OpeningBook.identify(_moves_to_uci(game.move_history))
	theory_plies = int(opening_info.get("out_of_book_ply", 0))
	if engine_manager != null and engine_manager.has_method("set_multipv"):
		_multipv_before_analysis = int(engine_manager.default_multipv())
		engine_manager.set_multipv(1, true)

	var moves = game.move_history
	var total_plies = moves.size()
	if total_plies == 0:
		is_analyzing = false
		_restore_default_multipv()
		var empty_rep := _build_final_report()
		analysis_finished.emit(empty_rep)
		return empty_rep
	if not await _wait_for_engine_async():
		return _fail_analysis("Moteur d'échecs indisponible : impossible d'analyser la partie.")
	if engine_manager.has_method("prepare_for_async_analysis"):
		if not await engine_manager.prepare_for_async_analysis():
			return _fail_analysis("Le moteur d'échecs n'a pas terminé l'évaluation Live précédente.")
	if cancel_requested:
		_release_async_engine_session()
		is_analyzing = false
		_restore_default_multipv()
		var cancelled_report := _build_final_report()
		analysis_finished.emit(cancelled_report)
		return cancelled_report

	var tree = Engine.get_main_loop() as SceneTree
	var sim_game = ChessGame.new()
	sim_game.load_fen(ChessGame.INITIAL_FEN)
	var pos_evals: Array = []
	var start_eval = await _evaluate_fen_async(ChessGame.INITIAL_FEN, base_depth, -1)
	if start_eval.has("error"):
		return _fail_analysis("Échec de l'évaluation de la position de départ par le moteur.")
	start_eval["fen"] = ChessGame.INITIAL_FEN
	pos_evals.append(start_eval)
	var provisional: Array = []

	for i in range(total_plies):
		if cancel_requested:
			break
		if engine_manager == null or not engine_manager.is_engine_available():
			return _fail_analysis("Le moteur d'échecs s'est arrêté en cours d'analyse de la partie.")
		var move: ChessMove = moves[i]
		var is_white := (i % 2 == 0)
		sim_game.make_move(move)
		var fen_after: String = sim_game.get_fen()
		if wait_for_display:
			_awaited_display_ply = i
			analysis_position_ready.emit(i)
			var _wait_start := Time.get_ticks_msec()
			while _awaited_display_ply == i and not cancel_requested:
				if Time.get_ticks_msec() - _wait_start >= 3000:
					_awaited_display_ply = -1
					break
				if tree:
					await tree.process_frame
				else:
					OS.delay_msec(10)
		else:
			analysis_position_ready.emit(i)
			if tree:
				await tree.process_frame
		if cancel_requested:
			break
		var after := _budget_terminal_eval(sim_game, move, is_white, base_depth)
		if after.is_empty():
			after = await _evaluate_fen_async(fen_after, base_depth, -1)
			if after.has("error"):
				return _fail_analysis("Le moteur d'échecs n'a pas pu évaluer le coup %s." % move.san)
		after["fen"] = fen_after
		pos_evals.append(after)
		var rec := _classify_move(i, moves, pos_evals, base_depth)
		provisional.append(rec)
		progress_updated.emit(i + 1, total_plies)
		ply_analyzed.emit(i, rec, {})
		if tree:
			await tree.process_frame

	if not cancel_requested:
		await _budget_deepen_critical_async(pos_evals, provisional, deep_depth, max_deep, min_crit, deep_ms)

	_finalize_from_evals(moves, pos_evals, deep_depth)
	_release_async_engine_session()
	is_analyzing = false
	_restore_default_multipv()
	var report := _build_final_report()
	analysis_finished.emit(report)
	return report

func _build_final_report() -> Dictionary:
	_compute_phase_stats()
	_compute_biggest_swings()
	return {
		"schema_version": SCHEMA_VERSION,
		"white_acpl": white_acpl,
		"black_acpl": black_acpl,
		"white_accuracy": white_accuracy,
		"black_accuracy": black_accuracy,
		"white_estimated_elo": white_estimated_elo,
		"black_estimated_elo": black_estimated_elo,
		"white_elo_ci": white_elo_ci_margin,
		"black_elo_ci": black_elo_ci_margin,
		"white_ipr_elo": white_ipr_elo,
		"black_ipr_elo": black_ipr_elo,
		"white_complexity_avg": white_complexity_avg,
		"black_complexity_avg": black_complexity_avg,
		"has_clock_data": has_clock_data,
		"elo_comparison": elo_stat_test,
		"white_stats": white_stats,
		"black_stats": black_stats,
		"opening": opening_info,
		"theory_plies": theory_plies,
		"white_phase_stats": white_phase_stats,
		"black_phase_stats": black_phase_stats,
		"biggest_swings": biggest_swings,
		"evaluations": move_evaluations
	}

## T1.3 — Agrège la perte de win% moyenne par phase et par camp.
func _compute_phase_stats() -> void:
	white_phase_stats = _empty_phase_stats()
	black_phase_stats = _empty_phase_stats()
	for ev in move_evaluations:
		if ev.get("is_theory", false):
			continue
		var phase: String = GamePhaseService.phase_for(str(ev.get("fen", "")), int(ev.get("ply", 0)), theory_plies)
		var target: Dictionary = white_phase_stats if bool(ev.get("is_white", true)) else black_phase_stats
		var bucket: Dictionary = target[phase]
		bucket["moves"] = int(bucket.get("moves", 0)) + 1
		bucket["winpct_loss"] = float(bucket.get("winpct_loss", 0.0)) + float(ev.get("winpct_loss", 0.0))
	for stats in [white_phase_stats, black_phase_stats]:
		for phase in stats.keys():
			var b: Dictionary = stats[phase]
			var m := int(b.get("moves", 0))
			b["avg_winpct_loss"] = (float(b.get("winpct_loss", 0.0)) / float(m)) if m > 0 else 0.0

func _empty_phase_stats() -> Dictionary:
	return {
		"opening": {"moves": 0, "winpct_loss": 0.0, "avg_winpct_loss": 0.0},
		"middlegame": {"moves": 0, "winpct_loss": 0.0, "avg_winpct_loss": 0.0},
		"endgame": {"moves": 0, "winpct_loss": 0.0, "avg_winpct_loss": 0.0}
	}

## T1.3 — Les 3 plus gros basculements de win% (moments clés, cliquables dans l'UI).
func _compute_biggest_swings() -> void:
	var candidates: Array = []
	for ev in move_evaluations:
		if ev.get("is_theory", false):
			continue
		candidates.append(ev)
	candidates.sort_custom(func(a, b):
		return float(a.get("winpct_loss", 0.0)) > float(b.get("winpct_loss", 0.0))
	)
	biggest_swings = []
	for k in range(mini(3, candidates.size())):
		var ev: Dictionary = candidates[k]
		biggest_swings.append({
			"ply": int(ev.get("ply", 0)),
			"move_number": int(ev.get("move_number", 1)),
			"is_white": bool(ev.get("is_white", true)),
			"san": str(ev.get("san", "")),
			"quality": int(ev.get("quality", ChessMove.Quality.NONE)),
			"winpct_loss": float(ev.get("winpct_loss", 0.0)),
			"score_cp": int(ev.get("score_cp", 0))
		})
