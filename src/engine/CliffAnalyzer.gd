class_name CliffAnalyzer
extends RefCounted
## CliffAnalyzer.gd — Orchestrateur moteur pour l'analyse cognitive CHESS-CLIFF V2.3.
## Pilote Stockfish pour extraire la vérité profonde (Oracle) et l'évaluation intuitive (depth 1),
## puis calcule les métriques de chute, d'appât, de mobilité et de piste pour chaque demi-coup.
## Intègre le Radar de Pièges (Suspect Probe) et les vecteurs duaux (effort_d, pression_d, leverage).

signal progress(current_ply: int, total_plies: int)
signal ply_cliff_computed(ply: int, cliff_data: Dictionary)
signal step_analyzed(step_idx: int, move_uci: String, fen_after: String, cliff_data: Dictionary)
signal single_line_analyzed(rank: int, piste_data: Dictionary)
signal analysis_finished(report: Dictionary)

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffMath = preload("res://src/engine/CliffMath.gd")
const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")
const ChessPiece = preload("res://src/core/ChessPiece.gd")

var engine_manager: Node = null
var is_analyzing: bool = false
var cancel_requested: bool = false

func _init(p_engine: Node = null) -> void:
	engine_manager = p_engine

func cancel() -> void:
	cancel_requested = true

## Analyse complète d'une partie selon le modèle cognitif CHESS-CLIFF V2.3.
## Évalue systématiquement la position AVANT chaque coup (fen_before) pour mesurer
## le dilemme décisionnel réel du camp au trait, puis calcule la pression infligée au coup suivant.
func analyze_game(game: ChessGame, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false

	var em = engine_manager
	if em == null:
		em = Engine.get_main_loop().root.get_node_or_null("/root/EngineManager")
	if em == null:
		is_analyzing = false
		var err_rep = {"error": "EngineManager non disponible", "cliff_version": 2}
		analysis_finished.emit(err_rep)
		return err_rep

	var moves: Array[ChessMove] = game.move_history.duplicate()
	var total_plies := moves.size()
	if total_plies == 0:
		is_analyzing = false
		var empty_rep = {
			"cliff_version": 2,
			"semantics": CliffTypes.SEMANTICS,
			"plies_analyzed": 0,
			"plies": [],
			"summary_white": {},
			"summary_black": {}
		}
		analysis_finished.emit(empty_rep)
		return empty_rep

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var default_depth := 14 if is_mobile else 18
	var deep_depth: int = int(options.get("deep_depth", default_depth))
	var theory_plies: int = int(options.get("theory_plies", 0))
	var fast_mode: bool = bool(options.get("fast_mode", false))
	var source_meta: Dictionary = options.get("source_meta", {})
	var shallow_depth: int = maxi(1, int(options.get("shallow_depth", 1)))
	var top_k: int = int(options.get("top_k", 5))
	var use_ucinewgame: bool = bool(options.get("ucinewgame", true))
	var oracle_timeout: int = int(options.get("timeout_ms", 4000))
	var oracle_multipv: int = maxi(2, int(options.get("multipv", 2)))

	var start_fen := ChessGame.INITIAL_FEN
	if game.pgn_headers.has("FEN") and str(game.pgn_headers["FEN"]).strip_edges() != "":
		start_fen = str(game.pgn_headers["FEN"]).strip_edges()
	var vgame := ChessGame.new(start_fen)
	var plies_data: Array = []

	var white_deltas: Array[float] = []
	var white_survies: Array[float] = []
	var white_baits: Array[float] = []
	var white_hmobs: Array[float] = []

	var black_deltas: Array[float] = []
	var black_survies: Array[float] = []
	var black_baits: Array[float] = []
	var black_hmobs: Array[float] = []

	for t in range(total_plies):
		if cancel_requested:
			break

		progress.emit(t + 1, total_plies)

		var move_t: ChessMove = moves[t]
		var played_uci := move_t.uci
		var san_move := str(move_t.san)

		# Position AVANT le coup t (dilemme auquel fait face l'auteur du coup)
		var fen_before := vgame.get_fen()
		var side_to_move := "white" if vgame.active_color == ChessPiece.PieceColor.WHITE else "black"
		var is_white_turn := (vgame.active_color == ChessPiece.PieceColor.WHITE)

		# ── ORACLE : évaluation profonde MultiPV dans fen_before ─────
		var deep_res = em.evaluate_deep_multipv_sync(fen_before, deep_depth, oracle_multipv, oracle_timeout)
		var deep_score_cp: int = int(deep_res.get("score_cp", 0))
		var deep_mate_in: int = int(deep_res.get("mate_in", 0))

		# Perspective du camp au trait dans fen_before (l'auteur du coup t)
		var mover_score_cp: int = deep_score_cp if is_white_turn else -deep_score_cp
		var mover_mate_in: int = deep_mate_in if is_white_turn else -deep_mate_in
		var wdl_best := CliffMath.wdl(mover_score_cp, mover_mate_in)
		var best_move_uci: String = str(deep_res.get("best_move", ""))

		var mpv_lines: Array = deep_res.get("multipv_lines", [])
		var deep_by_uci := _deep_wdl_map(mpv_lines, is_white_turn)
		if best_move_uci != "" and not deep_by_uci.has(best_move_uci):
			deep_by_uci[best_move_uci] = wdl_best
		var wdl_second := 0.0
		var second_best_uci := ""
		if mpv_lines.size() > 1:
			var l2: Dictionary = mpv_lines[1]
			second_best_uci = str(l2.get("best_move", ""))
			wdl_second = float(deep_by_uci.get(second_best_uci, maxf(0.0, wdl_best - 0.20)))
		else:
			wdl_second = maxf(0.0, wdl_best - 0.20)

		var delta_t := CliffMath.delta_chute(wdl_best, wdl_second)

		# ── INTUITIF & COUPS LÉGAUX dans fen_before ─────────────────
		var legal_moves = vgame.get_legal_moves()
		var n_legal := legal_moves.size()
		var side_in_check := vgame.is_in_check(vgame.active_color)
		var is_recap := false
		if t > 0:
			is_recap = _is_recapture_available(legal_moves, moves[t - 1].to_sq)
		var is_forced := CliffMath.is_suite_forcee(side_in_check, is_recap,
				_has_winning_capture(legal_moves), _has_material_tension(legal_moves))

		var v_percu_all: Array[float] = []
		var wdl_deep_all: Array[float] = []
		var cands: Array = []
		var best_move_idx := 0
		var max_v_percu := -999.0
		var wdl_deep_of_max_v := wdl_best
		var max_cand_idx := -1
		var viable_indices: Array[int] = []

		var is_in_theory := (t < theory_plies)

		var p_surv_t: float = 1.0
		var bait_t: float = 0.0
		var h_mob_t: float = 0.0
		var piste_t: int = CliffTypes.Piste.AUTOROUTE
		var indice_d_t: int = 0
		var extra_t: Dictionary = {}
		var p_humain_dist: Array[float] = []

		if n_legal == 0:
			if side_in_check:
				p_surv_t = 0.0
				delta_t = 1.0
				bait_t = 0.0
				h_mob_t = 0.0
				piste_t = CliffTypes.Piste.CHAMP_DE_MINES
				indice_d_t = 100
			else:
				p_surv_t = 1.0
				delta_t = 0.0
				bait_t = 0.0
				h_mob_t = 0.0
				piste_t = CliffTypes.Piste.AUTOROUTE
				indice_d_t = 0
			cands = []
			extra_t = {"cands": [], "best_uci": "", "bait_uci": "", "mines": [], "top_candidates": []}
		elif is_in_theory:
			v_percu_all = [wdl_best]
			wdl_deep_all = [wdl_best]
			cands = [{"uci": best_move_uci, "san": "", "from_sq": -1, "to_sq": -1,
					"v_percu": wdl_best, "wdl_deep": wdl_best, "wdl_static": wdl_best,
					"is_check": false, "deep_known": true}]
			best_move_idx = 0
			max_v_percu = wdl_best
			wdl_deep_of_max_v = wdl_best
			p_humain_dist = [1.0]
			var p_humain_best := 1.0
			bait_t = CliffMath.bait(max_v_percu, wdl_deep_of_max_v)
			h_mob_t = CliffMath.h_mob(wdl_deep_all, wdl_best, p_humain_dist)
			p_surv_t = CliffMath.p_survie(is_forced, p_humain_best)
			indice_d_t = CliffMath.indice_d([delta_t], [p_surv_t], [bait_t], h_mob_t)
			piste_t = CliffMath.classify_piste_by_d(indice_d_t)
			extra_t = _build_visual_info(cands, p_humain_dist, max_v_percu)
		else:
			var moves_to_eval = legal_moves
			if fast_mode and top_k > 0 and legal_moves.size() > top_k:
				moves_to_eval = _filter_top_salient(vgame, legal_moves, best_move_uci, top_k, played_uci)

			for idx in range(moves_to_eval.size()):
				var lm: ChessMove = moves_to_eval[idx]
				if lm.uci == best_move_uci:
					best_move_idx = idx

				var wdl_shallow_m := wdl_best
				var is_check := false
				if not fast_mode or lm.uci == best_move_uci or lm.uci == played_uci or idx < 3:
					var child_game := ChessGame.new(fen_before)
					child_game.make_move(lm)
					is_check = child_game.is_in_check(child_game.active_color)
					var fen_m := child_game.get_fen()
					var shallow_res = em.evaluate_shallow_sync(fen_m, 250, shallow_depth, use_ucinewgame)
					var raw_s_cp: int = int(shallow_res.get("score_cp", 0))
					var raw_s_mate: int = int(shallow_res.get("mate_in", 0))
					var s_cp: int = raw_s_cp if is_white_turn else -raw_s_cp
					var s_mate: int = raw_s_mate if is_white_turn else -raw_s_mate
					wdl_shallow_m = CliffMath.wdl(s_cp, s_mate)
				else:
					wdl_shallow_m = maxf(0.05, wdl_best - 0.25)

				var m_dict = {
					"is_check": is_check,
					"captured_piece": lm.captured_piece,
					"piece": lm.piece,
					"from_sq": lm.from_sq,
					"to_sq": lm.to_sq,
					"color": lm.color
				}
				var s_m := CliffMath.saillance(m_dict)
				var v_m := CliffMath.v_percu(wdl_shallow_m, s_m)
				v_percu_all.append(v_m)

				var deep_known := deep_by_uci.has(lm.uci)
				var d_m: float = float(deep_by_uci.get(lm.uci, wdl_second))
				wdl_deep_all.append(d_m)
				cands.append({
					"uci": lm.uci, "san": str(lm.san), "from_sq": lm.from_sq, "to_sq": lm.to_sq,
					"v_percu": v_m, "wdl_deep": d_m, "wdl_static": wdl_shallow_m,
					"is_check": is_check, "deep_known": deep_known
				})

				if v_m > max_v_percu:
					max_v_percu = v_m
					wdl_deep_of_max_v = d_m
					max_cand_idx = idx

			# ── RADAR DE PIÈGES (Suspect Probe V2.3) ───────────────────
			# Si le coup le plus séduisant n'est pas le best_move et n'est pas dans le MultiPV profond,
			# on vérifie immédiatement sa véritable valeur via un probe ciblé sans vider la TT.
			if max_cand_idx >= 0 and max_cand_idx < cands.size():
				var top_cand: Dictionary = cands[max_cand_idx]
				var cand_uci: String = str(top_cand.get("uci", ""))
				if cand_uci != best_move_uci and not deep_by_uci.has(cand_uci):
					if em.has_method("probe_suspect_move_fast"):
						var probe = em.probe_suspect_move_fast(fen_before, cand_uci, 6, 250)
						var p_cp: int = int(probe.get("score_cp", 0))
						var p_mat: int = int(probe.get("mate_in", 0))
						var p_m_cp: int = p_cp if is_white_turn else -p_cp
						var p_m_mat: int = p_mat if is_white_turn else -p_mat
						var probe_wdl := CliffMath.wdl(p_m_cp, p_m_mat)
						deep_by_uci[cand_uci] = probe_wdl
						top_cand["wdl_deep"] = probe_wdl
						top_cand["deep_known"] = true
						wdl_deep_all[max_cand_idx] = probe_wdl
						wdl_deep_of_max_v = probe_wdl

			# Distribution Boltzmann
			p_humain_dist = CliffMath.p_humain_distribution(v_percu_all)
			var p_humain_best := 1.0
			if best_move_idx >= 0 and best_move_idx < p_humain_dist.size():
				p_humain_best = p_humain_dist[best_move_idx]

			# Métriques finales du demi-coup avec somme M_ok
			viable_indices = CliffMath.get_viable_indices(wdl_deep_all, wdl_best)
			var viable_p_sum := 0.0
			for v_idx in viable_indices:
				if v_idx >= 0 and v_idx < p_humain_dist.size():
					viable_p_sum += float(p_humain_dist[v_idx])
			bait_t = CliffMath.bait(max_v_percu, wdl_deep_of_max_v)
			h_mob_t = CliffMath.h_mob(wdl_deep_all, wdl_best, p_humain_dist)
			p_surv_t = CliffMath.p_survie(is_forced, p_humain_best, viable_p_sum)
			indice_d_t = CliffMath.indice_d([delta_t], [p_surv_t], [bait_t], h_mob_t)
			piste_t = CliffMath.classify_piste_by_d(indice_d_t)
			extra_t = _build_visual_info(cands, p_humain_dist, max_v_percu)

		# Nature cognitive et cases interdites
		var nature := CliffTypes.MoveNature.SAFE
		var is_vital := false
		var poisoned_sqs: Array[int] = []
		var expl := ""

		if viable_indices.size() == 1 and delta_t >= 0.20:
			nature = CliffTypes.MoveNature.VITAL
			is_vital = true
			expl = "🧗 Coup unique vital (%s) : seul coup évitant la chute immédiate (Δ=%.2f)." % [san_move, delta_t]
			for m in legal_moves:
				if m.from_sq == move_t.from_sq and m.to_sq != move_t.to_sq:
					poisoned_sqs.append(int(m.to_sq))
		elif is_forced:
			nature = CliffTypes.MoveNature.FORCED
			expl = "🛡️ Suite forcée (%s) : coup ou reprise incontournable." % san_move
		elif indice_d_t >= CliffTypes.D_CHEMIN_MAX:
			nature = CliffTypes.MoveNature.VITAL
			is_vital = true
			expl = "🧗 Sentier technique étroit (%s) : haute exigence tactique (D=%d)." % [san_move, indice_d_t]
		else:
			nature = CliffTypes.MoveNature.SAFE
			expl = "🟢 Choix naturel (%s) : position saine et ouverte (D=%d)." % [san_move, indice_d_t]

		# Coup joué dans vgame pour obtenir fen_after
		vgame.make_move(move_t)
		var fen_after := vgame.get_fen()

		# Calcul synchrone de la tension latente subie par l'adversaire au demi-coup t
		var menace_b := 0.0
		if not cands.is_empty():
			for c_idx in range(cands.size()):
				var c_dict: Dictionary = cands[c_idx]
				var p_h: float = float(p_humain_dist[c_idx]) if c_idx < p_humain_dist.size() else 0.0
				var w_a: float = float(c_dict.get("wdl_deep", wdl_best))
				var danger: float = clampf((w_a - 0.50) * 200.0, 0.0, 100.0)
				menace_b += p_h * danger
		else:
			menace_b = 100.0 if (side_in_check and n_legal == 0) else 0.0
		var last_opp_d: float = 15.0
		if is_white_turn:
			if not black_deltas.is_empty() and plies_data.size() > 0:
				last_opp_d = float(plies_data[plies_data.size() - 1].get("effort_d", 15))
		else:
			if not white_deltas.is_empty() and plies_data.size() > 0:
				last_opp_d = float(plies_data[plies_data.size() - 1].get("effort_d", 15))
		var d_latent_t: int = int(round(clampf(0.65 * menace_b + 0.35 * last_opp_d, 0.0, 100.0)))

		var ply_dict = {
			"ply": t,
			"step": t,
			"san": san_move,
			"move_uci": played_uci,
			"played_uci": played_uci,
			"fen_before": fen_before,
			"fen_after": fen_after,
			"fen": fen_before,
			"side_to_move": side_to_move,
			"is_white": is_white_turn,
			"effort_d": indice_d_t,
			"pression_d": 0,
			"d_latent_opponent": d_latent_t,
			"surprise_delta": 0,
			"surprise_nature": CliffTypes.SurpriseNature.NORMAL,
			"leverage": 0,
			"piste": piste_t,
			"indice_d": indice_d_t,
			"delta_chute": delta_t,
			"bait": bait_t,
			"p_survie": p_surv_t,
			"h_mob": h_mob_t,
			"move_nature": nature,
			"is_vital": is_vital,
			"poisoned_squares": poisoned_sqs,
			"explanation": expl,
			"best_move": best_move_uci,
			"second_best_move": second_best_uci,
			"score_cp": deep_score_cp,
			"mate_in": deep_mate_in,
			"depth": deep_depth,
			"pv_line": [best_move_uci] if best_move_uci != "" else [],
			"multipv_lines": mpv_lines,
			"wdl_deep": wdl_best,
			"legal_moves_count": n_legal,
			"is_forced": is_forced,
			"bait_move_uci": extra_t.get("bait_move_uci", ""),
			"bait_from": extra_t.get("bait_from", -1),
			"bait_to": extra_t.get("bait_to", -1),
			"mines": extra_t.get("mines", []),
			"top_candidates": extra_t.get("top_candidates", [])
		}
		plies_data.append(ply_dict)
		ply_cliff_computed.emit(t, ply_dict)

		# Accumulation par camp (l'auteur du coup consent l'effort)
		if is_white_turn:
			white_deltas.append(delta_t)
			white_survies.append(p_surv_t)
			white_baits.append(bait_t)
			white_hmobs.append(h_mob_t)
		else:
			black_deltas.append(delta_t)
			black_survies.append(p_surv_t)
			black_baits.append(bait_t)
			black_hmobs.append(h_mob_t)

	# Second passage pour pression_d, leverage et surprise_delta
	for i in range(plies_data.size()):
		var cur_d: int = int(plies_data[i].get("effort_d", 0))
		var pres_d: int = cur_d
		var latent_d: int = int(plies_data[i].get("d_latent_opponent", cur_d))
		var surprise: int = 0
		if i + 1 < plies_data.size():
			pres_d = int(plies_data[i + 1].get("effort_d", 0))
			surprise = pres_d - latent_d
		else:
			if vgame.is_in_check(vgame.active_color) and vgame.get_legal_moves().is_empty():
				pres_d = 100
			else:
				pres_d = cur_d
			surprise = 0
		plies_data[i]["pression_d"] = pres_d
		plies_data[i]["leverage"] = pres_d - cur_d
		plies_data[i]["surprise_delta"] = surprise
		plies_data[i]["surprise_nature"] = CliffTypes.classify_surprise(surprise)

	# Synthèses par camp
	var sum_w = _compute_side_summary(white_deltas, white_survies, white_baits, white_hmobs)
	var sum_b = _compute_side_summary(black_deltas, black_survies, black_baits, black_hmobs)

	var report = {
		"cliff_version": 2,
		"semantics": CliffTypes.SEMANTICS,
		"source_meta": source_meta,
		"plies_analyzed": plies_data.size(),
		"plies": plies_data,
		"summary_white": sum_w,
		"summary_black": sum_b,
		"pressure_white": sum_b,
		"pressure_black": sum_w
	}

	is_analyzing = false
	analysis_finished.emit(report)
	return report

## Analyse la difficulté cognitive d'une ligne de coups (PV) depuis une position FEN de départ.
## Émet `step_analyzed` pour chaque coup permettant d'animer l'échiquier en mode Super Live.
func analyze_pv_line(start_fen: String, pv_moves: Array, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false

	var em = engine_manager
	if em == null:
		em = Engine.get_main_loop().root.get_node_or_null("/root/EngineManager")
	if em == null:
		is_analyzing = false
		var err_rep = {"error": "EngineManager non disponible", "cliff_version": 2}
		analysis_finished.emit(err_rep)
		return err_rep

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var default_depth := 12 if is_mobile else 16
	var deep_depth: int = int(options.get("deep_depth", default_depth))
	var fast_mode: bool = bool(options.get("fast_mode", true))
	var max_plies: int = int(options.get("max_plies", 8))
	var source_meta: Dictionary = options.get("source_meta", {})
	var shallow_depth: int = maxi(1, int(options.get("shallow_depth", 1)))
	var top_k: int = int(options.get("top_k", 5))
	var use_ucinewgame: bool = bool(options.get("ucinewgame", true))
	var oracle_timeout: int = int(options.get("timeout_ms", 3500))
	var oracle_multipv: int = maxi(2, int(options.get("multipv", 2)))

	var vgame := ChessGame.new(start_fen)
	var plies_to_eval: int = mini(pv_moves.size(), max_plies)
	if plies_to_eval == 0:
		is_analyzing = false
		var empty_rep = {
			"cliff_version": 2,
			"semantics": CliffTypes.SEMANTICS,
			"is_pv_line": true,
			"start_fen": start_fen,
			"plies_analyzed": 0,
			"plies": [],
			"summary_white": {},
			"summary_black": {}
		}
		analysis_finished.emit(empty_rep)
		return empty_rep

	var plies_data: Array = []
	var white_deltas: Array[float] = []
	var white_survies: Array[float] = []
	var white_baits: Array[float] = []
	var white_hmobs: Array[float] = []

	var black_deltas: Array[float] = []
	var black_survies: Array[float] = []
	var black_baits: Array[float] = []
	var black_hmobs: Array[float] = []

	for k in range(plies_to_eval):
		if cancel_requested:
			break

		progress.emit(k + 1, plies_to_eval)

		var raw_uci: String = str(pv_moves[k])
		var side_to_move := "white" if vgame.active_color == ChessPiece.PieceColor.WHITE else "black"
		var is_white_turn := (vgame.active_color == ChessPiece.PieceColor.WHITE)
		var fen_before := vgame.get_fen()

		var move_obj: ChessMove = vgame.find_move(raw_uci)

		var deep_res = em.evaluate_deep_multipv_sync(fen_before, deep_depth, oracle_multipv, oracle_timeout)
		var deep_score_cp: int = int(deep_res.get("score_cp", 0))
		var deep_mate_in: int = int(deep_res.get("mate_in", 0))
		var mover_score_cp: int = deep_score_cp if is_white_turn else -deep_score_cp
		var mover_mate_in: int = deep_mate_in if is_white_turn else -deep_mate_in
		var wdl_best := CliffMath.wdl(mover_score_cp, mover_mate_in)
		var best_move_uci: String = str(deep_res.get("best_move", raw_uci))

		var mpv_lines: Array = deep_res.get("multipv_lines", [])
		var deep_by_uci := _deep_wdl_map(mpv_lines, is_white_turn)
		if best_move_uci != "" and not deep_by_uci.has(best_move_uci):
			deep_by_uci[best_move_uci] = wdl_best
		var wdl_second := 0.0
		var second_best_uci := ""
		if mpv_lines.size() > 1:
			var l2: Dictionary = mpv_lines[1]
			second_best_uci = str(l2.get("best_move", ""))
			wdl_second = float(deep_by_uci.get(second_best_uci, maxf(0.0, wdl_best - 0.20)))
		else:
			wdl_second = maxf(0.0, wdl_best - 0.20)

		var delta_k := CliffMath.delta_chute(wdl_best, wdl_second)

		var legal_moves = vgame.get_legal_moves()
		var n_legal := legal_moves.size()
		var v_percu_all: Array[float] = []
		var wdl_deep_all: Array[float] = []
		var cands: Array = []
		var best_move_idx := 0
		var max_v_percu := -999.0
		var wdl_deep_of_max_v := wdl_best
		var max_cand_idx := -1

		var moves_to_eval = legal_moves
		if fast_mode and top_k > 0 and legal_moves.size() > top_k:
			moves_to_eval = _filter_top_salient(vgame, legal_moves, best_move_uci, top_k, raw_uci)

		for idx in range(moves_to_eval.size()):
			var lm: ChessMove = moves_to_eval[idx]
			if lm.uci == best_move_uci:
				best_move_idx = idx

			var wdl_shallow_m := wdl_best
			var is_check := false
			if not fast_mode or lm.uci == best_move_uci or lm.uci == raw_uci or idx < 3:
				var child_game := ChessGame.new(fen_before)
				child_game.make_move(lm)
				is_check = child_game.is_in_check(child_game.active_color)
				var fen_m := child_game.get_fen()
				var shallow_res = em.evaluate_shallow_sync(fen_m, 250, shallow_depth, use_ucinewgame)
				var raw_s_cp: int = int(shallow_res.get("score_cp", 0))
				var raw_s_mate: int = int(shallow_res.get("mate_in", 0))
				var s_cp: int = raw_s_cp if is_white_turn else -raw_s_cp
				var s_mate: int = raw_s_mate if is_white_turn else -raw_s_mate
				wdl_shallow_m = CliffMath.wdl(s_cp, s_mate)
			else:
				wdl_shallow_m = maxf(0.05, wdl_best - 0.25)

			var m_dict = {
				"is_check": is_check,
				"captured_piece": lm.captured_piece,
				"piece": lm.piece,
				"from_sq": lm.from_sq,
				"to_sq": lm.to_sq,
				"color": lm.color
			}
			var s_m := CliffMath.saillance(m_dict)
			var v_m := CliffMath.v_percu(wdl_shallow_m, s_m)
			v_percu_all.append(v_m)

			var deep_known := deep_by_uci.has(lm.uci)
			var d_m: float = float(deep_by_uci.get(lm.uci, wdl_second))
			wdl_deep_all.append(d_m)
			cands.append({
				"uci": lm.uci, "san": str(lm.san), "from_sq": lm.from_sq, "to_sq": lm.to_sq,
				"v_percu": v_m, "wdl_deep": d_m, "wdl_static": wdl_shallow_m,
				"is_check": is_check, "deep_known": deep_known
			})

			if v_m > max_v_percu:
				max_v_percu = v_m
				wdl_deep_of_max_v = d_m
				max_cand_idx = idx

		# ── RADAR DE PIÈGES (Suspect Probe V2.3) ───────────────────
		if max_cand_idx >= 0 and max_cand_idx < cands.size():
			var top_cand: Dictionary = cands[max_cand_idx]
			var cand_uci: String = str(top_cand.get("uci", ""))
			if cand_uci != best_move_uci and not deep_by_uci.has(cand_uci):
				if em.has_method("probe_suspect_move_fast"):
					var probe = em.probe_suspect_move_fast(fen_before, cand_uci, 6, 250)
					var p_cp: int = int(probe.get("score_cp", 0))
					var p_mat: int = int(probe.get("mate_in", 0))
					var p_m_cp: int = p_cp if is_white_turn else -p_cp
					var p_m_mat: int = p_mat if is_white_turn else -p_mat
					var probe_wdl := CliffMath.wdl(p_m_cp, p_m_mat)
					deep_by_uci[cand_uci] = probe_wdl
					top_cand["wdl_deep"] = probe_wdl
					top_cand["deep_known"] = true
					wdl_deep_all[max_cand_idx] = probe_wdl
					wdl_deep_of_max_v = probe_wdl

		var p_humain_dist = CliffMath.p_humain_distribution(v_percu_all)
		var p_humain_best := 1.0
		if best_move_idx >= 0 and best_move_idx < p_humain_dist.size():
			p_humain_best = p_humain_dist[best_move_idx]

		var side_in_check := vgame.is_in_check(vgame.active_color)
		var is_forced = CliffMath.is_suite_forcee(side_in_check, false,
				_has_winning_capture(legal_moves), _has_material_tension(legal_moves))

		var viable_indices := CliffMath.get_viable_indices(wdl_deep_all, wdl_best)
		var viable_p_sum := 0.0
		for v_idx in viable_indices:
			if v_idx >= 0 and v_idx < p_humain_dist.size():
				viable_p_sum += float(p_humain_dist[v_idx])
		var bait_k := CliffMath.bait(max_v_percu, wdl_deep_of_max_v)
		var h_mob_k := CliffMath.h_mob(wdl_deep_all, wdl_best, p_humain_dist)
		var p_surv_k := CliffMath.p_survie(is_forced, p_humain_best, viable_p_sum)
		var indice_d_k := CliffMath.indice_d([delta_k], [p_surv_k], [bait_k], h_mob_k)
		var piste_k := CliffMath.classify_piste_by_d(indice_d_k)
		var extra_k := _build_visual_info(cands, p_humain_dist, max_v_percu)

		var san_move := move_obj.san if move_obj != null else raw_uci

		# Nature cognitive et cases interdites
		var nature_k := CliffTypes.MoveNature.SAFE
		var is_vital_k := false
		var poisoned_sqs_k: Array[int] = []
		var expl_k := ""

		if viable_indices.size() == 1 and delta_k >= 0.20:
			nature_k = CliffTypes.MoveNature.VITAL
			is_vital_k = true
			expl_k = "🧗 Coup unique vital (%s) : seul coup évitant la chute immédiate (Δ=%.2f)." % [san_move, delta_k]
			if move_obj != null:
				for m in legal_moves:
					if m.from_sq == move_obj.from_sq and m.to_sq != move_obj.to_sq:
						poisoned_sqs_k.append(int(m.to_sq))
		elif is_forced:
			nature_k = CliffTypes.MoveNature.FORCED
			expl_k = "🛡️ Suite forcée (%s) : coup ou reprise incontournable." % san_move
		elif indice_d_k >= CliffTypes.D_CHEMIN_MAX:
			nature_k = CliffTypes.MoveNature.VITAL
			is_vital_k = true
			expl_k = "🧗 Sentier technique étroit (%s) : haute exigence tactique (D=%d)." % [san_move, indice_d_k]
		else:
			nature_k = CliffTypes.MoveNature.SAFE
			expl_k = "🟢 Choix naturel (%s) : position saine et ouverte (D=%d)." % [san_move, indice_d_k]

		var played_idx := -1
		for i in range(cands.size()):
			if str(cands[i].get("uci", "")) == raw_uci:
				played_idx = i
				break
		var played_p_humain: float = float(p_humain_dist[played_idx]) if played_idx >= 0 and played_idx < p_humain_dist.size() else p_humain_best
		var played_v_percu := float(cands[played_idx].get("v_percu", wdl_best)) if played_idx >= 0 else wdl_best
		var played_wdl_static := float(cands[played_idx].get("wdl_static", wdl_best)) if played_idx >= 0 else wdl_best

		if move_obj != null:
			vgame.make_move(move_obj)
		var fen_after := vgame.get_fen()

		# Calcul synchrone de la tension latente subie par l'adversaire
		var menace_k := 0.0
		if not cands.is_empty():
			for c_idx in range(cands.size()):
				var c_dict: Dictionary = cands[c_idx]
				var p_h: float = float(p_humain_dist[c_idx]) if c_idx < p_humain_dist.size() else 0.0
				var w_a: float = float(c_dict.get("wdl_deep", wdl_best))
				var danger: float = clampf((w_a - 0.50) * 200.0, 0.0, 100.0)
				menace_k += p_h * danger
		else:
			menace_k = 100.0 if (side_in_check and legal_moves.is_empty()) else 0.0
		var last_opp_k: float = 15.0
		if is_white_turn:
			if not black_deltas.is_empty() and plies_data.size() > 0:
				last_opp_k = float(plies_data[plies_data.size() - 1].get("effort_d", 15))
		else:
			if not white_deltas.is_empty() and plies_data.size() > 0:
				last_opp_k = float(plies_data[plies_data.size() - 1].get("effort_d", 15))
		var d_latent_k: int = int(round(clampf(0.65 * menace_k + 0.35 * last_opp_k, 0.0, 100.0)))

		var step_dict = {
			"ply": k,
			"step": k,
			"move_uci": raw_uci,
			"played_uci": raw_uci,
			"san": san_move,
			"fen_before": fen_before,
			"fen_after": fen_after,
			"fen": fen_before,
			"side_to_move": side_to_move,
			"is_white": is_white_turn,
			"effort_d": indice_d_k,
			"pression_d": 0,
			"d_latent_opponent": d_latent_k,
			"surprise_delta": 0,
			"surprise_nature": CliffTypes.SurpriseNature.NORMAL,
			"leverage": 0,
			"piste": piste_k,
			"indice_d": indice_d_k,
			"delta_chute": delta_k,
			"bait": bait_k,
			"p_survie": p_surv_k,
			"h_mob": h_mob_k,
			"move_nature": nature_k,
			"is_vital": is_vital_k,
			"poisoned_squares": poisoned_sqs_k,
			"explanation": expl_k,
			"best_move": best_move_uci,
			"second_best_move": second_best_uci,
			"score_cp": deep_score_cp,
			"mate_in": deep_mate_in,
			"depth": deep_depth,
			"pv_line": [best_move_uci] if best_move_uci != "" else [],
			"multipv_lines": mpv_lines,
			"wdl_deep": wdl_best,
			"v_percu": played_v_percu,
			"wdl_static": played_wdl_static,
			"p_humain": played_p_humain,
			"bait_move_uci": extra_k.get("bait_move_uci", ""),
			"bait_from": extra_k.get("bait_from", -1),
			"bait_to": extra_k.get("bait_to", -1),
			"mines": extra_k.get("mines", []),
			"top_candidates": extra_k.get("top_candidates", [])
		}
		plies_data.append(step_dict)

		if is_white_turn:
			white_deltas.append(delta_k)
			white_survies.append(p_surv_k)
			white_baits.append(bait_k)
			white_hmobs.append(h_mob_k)
		else:
			black_deltas.append(delta_k)
			black_survies.append(p_surv_k)
			black_baits.append(bait_k)
			black_hmobs.append(h_mob_k)

		step_analyzed.emit(k, raw_uci, fen_after, step_dict)

	# Second passage pour pression_d, leverage et surprise_delta
	for i in range(plies_data.size()):
		var cur_d: int = int(plies_data[i].get("effort_d", 0))
		var pres_d: int = cur_d
		var latent_d: int = int(plies_data[i].get("d_latent_opponent", cur_d))
		var surprise: int = 0
		if i + 1 < plies_data.size():
			pres_d = int(plies_data[i + 1].get("effort_d", 0))
			surprise = pres_d - latent_d
		else:
			if vgame.is_in_check(vgame.active_color) and vgame.get_legal_moves().is_empty():
				pres_d = 100
			else:
				pres_d = cur_d
			surprise = 0
		plies_data[i]["pression_d"] = pres_d
		plies_data[i]["leverage"] = pres_d - cur_d
		plies_data[i]["surprise_delta"] = surprise
		plies_data[i]["surprise_nature"] = CliffTypes.classify_surprise(surprise)

	var sum_w = _compute_side_summary(white_deltas, white_survies, white_baits, white_hmobs)
	var sum_b = _compute_side_summary(black_deltas, black_survies, black_baits, black_hmobs)

	var report = {
		"cliff_version": 2,
		"semantics": CliffTypes.SEMANTICS,
		"is_pv_line": true,
		"start_fen": start_fen,
		"source_meta": source_meta,
		"plies_analyzed": plies_data.size(),
		"plies": plies_data,
		"summary_white": sum_w,
		"summary_black": sum_b,
		"pressure_white": sum_b,
		"pressure_black": sum_w
	}

	is_analyzing = false
	analysis_finished.emit(report)
	return report

## Construit la correspondance UCI -> WDL profond réel depuis les lignes MultiPV.
func _deep_wdl_map(mpv_lines: Array, is_white_turn: bool) -> Dictionary:
	var map := {}
	for l in mpv_lines:
		if not (l is Dictionary):
			continue
		var uci := str((l as Dictionary).get("best_move", ""))
		if uci == "":
			continue
		var cp := int((l as Dictionary).get("score_cp", 0))
		var mate := int((l as Dictionary).get("mate_in", 0))
		var mover_cp := cp if is_white_turn else -cp
		var mover_mate := mate if is_white_turn else -mate
		map[uci] = CliffMath.wdl(mover_cp, mover_mate)
	return map

## Construit les informations visuelles (Rayons X) d'une position :
## coup le plus séduisant (appât), cases-mines et top candidats.
func _build_visual_info(cands: Array, p_humain_dist: Array, max_v_percu: float) -> Dictionary:
	var bait_move_uci := ""
	var bait_from := -1
	var bait_to := -1
	var best_v := -999.0
	var mines: Array = []
	var top: Array = []

	for i in range(cands.size()):
		var c: Dictionary = cands[i]
		var v := float(c.get("v_percu", 0.0))
		var d := float(c.get("wdl_deep", 0.0))
		var p_h := float(p_humain_dist[i]) if i < p_humain_dist.size() else 0.0
		c["p_humain"] = p_h
		top.append(c)
		if v > best_v:
			best_v = v
			bait_move_uci = str(c.get("uci", ""))
			bait_from = int(c.get("from_sq", -1))
			bait_to = int(c.get("to_sq", -1))
		# Mine : coup très séduisant dont la vérité profonde est nettement pire.
		var deep_known := bool(c.get("deep_known", true))
		var trap := v - d
		if deep_known and trap >= 0.05 and v >= max_v_percu - 0.06 and int(c.get("to_sq", -1)) >= 0:
			mines.append({"sq": int(c.get("to_sq", -1)), "weight": clampf(trap, 0.0, 1.0)})

	top.sort_custom(func(a, b): return float(a.get("p_humain", 0.0)) > float(b.get("p_humain", 0.0)))

	return {
		"bait_move_uci": bait_move_uci,
		"bait_from": bait_from,
		"bait_to": bait_to,
		"mines": mines,
		"top_candidates": top.slice(0, 3)
	}

## Vrai si un coup légal capture une pièce de valeur >= à celle qui capture
## (pièce en prise / gain matériel évident) — condition de suite forcée.
static func _has_winning_capture(legal_moves: Array) -> bool:
	for m in legal_moves:
		if m.captured_piece != ChessPiece.Type.NONE:
			var v_tgt := CliffMath.piece_point_value(m.captured_piece)
			var v_src := CliffMath.piece_point_value(m.piece)
			if v_tgt >= v_src:
				return true
	return false

## Vrai si plusieurs captures sont disponibles (tension matérielle).
static func _has_material_tension(legal_moves: Array) -> bool:
	var caps := 0
	for m in legal_moves:
		if m.captured_piece != ChessPiece.Type.NONE:
			caps += 1
			if caps >= 2:
				return true
	return false

## Vrai si une reprise est disponible sur la case où le dernier coup a atterri.
static func _is_recapture_available(legal_moves: Array, target_sq: int) -> bool:
	if target_sq < 0:
		return false
	for m in legal_moves:
		if int(m.to_sq) == target_sq and m.captured_piece != ChessPiece.Type.NONE:
			return true
	return false

func _compute_side_summary(deltas: Array[float], survies: Array[float], baits: Array[float], hmobs: Array[float]) -> Dictionary:
	if survies.is_empty():
		return {
			"p_survie_ligne": 1.0,
			"avg_delta_chute": 0.0,
			"max_delta_chute": 0.0,
			"max_bait": 0.0,
			"avg_h_mob": 0.0,
			"global_piste": CliffTypes.Piste.AUTOROUTE,
			"indice_d": 0
		}

	# Si la partie/ligne dépasse 6 demi-coups, on utilise le minimum glissant sur un horizon de 4 demi-coups
	# pour éviter l'effondrement asymptotique artificiel du produit de survie.
	var p_ligne: float = 1.0
	if survies.size() > 6:
		p_ligne = CliffMath.p_survie_horizon_min(survies, CliffTypes.HORIZON_PLIES)
	else:
		p_ligne = CliffMath.p_survie_ligne(survies)

	var max_delta := 0.0
	var sum_delta := 0.0
	for d in deltas:
		sum_delta += d
		if d > max_delta:
			max_delta = d
	var avg_delta := sum_delta / float(deltas.size())

	var max_b := 0.0
	for b in baits:
		if b > max_b:
			max_b = b

	var sum_h := 0.0
	for h in hmobs:
		sum_h += h
	var avg_h := sum_h / float(hmobs.size())

	var d_score := CliffMath.indice_d(deltas, survies, baits, avg_h)
	# Règle de l'Abysse : un ravin critique (max_delta >= 0.30) ou une chute de survie
	# ne peut pas être totalement effacé par des coups triviaux voisins.
	if max_delta >= CliffTypes.DELTA_CORNICHE or p_ligne < CliffTypes.P_CHEMIN_LO:
		var d_abyss := int(round(max_delta * 100.0 * 0.70))
		d_score = maxi(d_score, d_abyss)
	var glob_piste := CliffMath.classify_piste_by_d(d_score)

	return {
		"p_survie_ligne": p_ligne,
		"avg_delta_chute": avg_delta,
		"max_delta_chute": max_delta,
		"max_bait": max_b,
		"avg_h_mob": avg_h,
		"global_piste": glob_piste,
		"indice_d": d_score
	}

## Filtre les coups légaux par saillance cognitive en priorisant le best_move et le coup joué.
## Teste dynamiquement si le coup donne échec pour alimenter correctement la saillance.
func _filter_top_salient(vgame: ChessGame, legal_moves: Array, best_move_uci: String, limit: int, priority_uci: String = "") -> Array:
	var scored: Array = []
	var fen_curr := vgame.get_fen()
	for m in legal_moves:
		var s := 0.0
		if m.uci == best_move_uci:
			s = 100.0 # Force absolue pour le meilleur coup
		elif priority_uci != "" and m.uci == priority_uci:
			s = 90.0  # Force absolue pour le coup joué
		else:
			var gives_check := false
			if m.captured_piece != ChessPiece.Type.NONE or m.piece in [ChessPiece.Type.QUEEN, ChessPiece.Type.ROOK, ChessPiece.Type.BISHOP, ChessPiece.Type.KNIGHT]:
				var ch := ChessGame.new(fen_curr)
				ch.make_move(m)
				gives_check = ch.is_in_check(ch.active_color)

			var m_dict = {
				"is_check": gives_check,
				"captured_piece": m.captured_piece,
				"piece": m.piece,
				"from_sq": m.from_sq,
				"to_sq": m.to_sq,
				"color": m.color
			}
			s = CliffMath.saillance(m_dict)
		scored.append({"move": m, "score": s})

	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var result: Array = []
	for i in range(mini(limit, scored.size())):
		result.append(scored[i]["move"])
	return result

## Niveau 2 (Méso) : Audite et compare rapidement plusieurs lignes moteur depuis une position FEN de départ.
## Retourne un dictionnaire { rank -> { "piste": int, "indice_d": int, "delta": float, "p_survie": float, "report": Dictionary } }
func analyze_multiple_lines_sync(start_fen: String, lines_array: Array, options: Dictionary = {}) -> Dictionary:
	var results: Dictionary = {}
	var max_lines: int = mini(lines_array.size(), int(options.get("max_lines", 5)))
	var line_plies: int = int(options.get("line_plies", 4)) # Audit rapide sur 4 demi-coups

	for i in range(max_lines):
		if cancel_requested:
			break
		var l_dict: Dictionary = lines_array[i]
		var pv: Array = l_dict.get("pv", [])
		var rank: int = int(l_dict.get("rank", i + 1))
		if pv.is_empty():
			continue

		var opts := options.duplicate()
		opts["max_plies"] = line_plies
		opts["fast_mode"] = true

		var rep: Dictionary = analyze_pv_line(start_fen, pv, opts)
		if rep.is_empty() or rep.has("error"):
			continue

		var is_white_start := true
		var vg := ChessGame.new(start_fen)
		is_white_start = (vg.active_color == ChessPiece.PieceColor.WHITE)

		var sum_side: Dictionary = rep.get("summary_white" if is_white_start else "summary_black", {})
		var line_summary = {
			"piste": int(sum_side.get("global_piste", CliffTypes.Piste.AUTOROUTE)),
			"indice_d": int(sum_side.get("indice_d", 0)),
			"delta": float(sum_side.get("max_delta_chute", 0.0)),
			"bait": float(sum_side.get("max_bait", 0.0)),
			"p_survie": float(sum_side.get("p_survie_ligne", 1.0)),
			"report": rep
		}
		results[rank] = line_summary
		single_line_analyzed.emit(rank, line_summary)
	return results

