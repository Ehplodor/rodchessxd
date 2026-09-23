class_name CliffAnalyzer
extends RefCounted
## CliffAnalyzer.gd — Orchestrateur moteur pour l'analyse cognitive CHESS-CLIFF.
## Pilote Stockfish pour extraire la vérité profonde (Oracle MultiPV) et l'évaluation intuitive
## (depth 1), puis calcule chute, appât, mobilité et piste pour chaque demi-coup.
##
## Principes :
## - Aucune valeur inventée : un coup hors MultiPV non sondé n'a qu'une BORNE supérieure
##   (la pire ligne MultiPV) et n'est jamais compté comme viable ; Δ n'est mesuré que si
##   une deuxième ligne existe réellement.
## - Un échec moteur (erreur, aucun bestmove) marque le demi-coup `reliable = false` au lieu
##   de le traiter comme une position nulle ; il est exclu des synthèses.
## - Les demi-coups de théorie sont évalués (courbe) mais ne comptent pas comme effort.

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

## Écart de pression (leverage) à partir duquel un coup libre devient une attaque.
const ATTACK_LEVERAGE := 25

var engine_manager: Node = null
var is_analyzing: bool = false
var cancel_requested: bool = false

func _init(p_engine: Node = null) -> void:
	engine_manager = p_engine

func cancel() -> void:
	cancel_requested = true

## Analyse complète d'une partie selon le modèle cognitif CHESS-CLIFF.
## Évalue la position AVANT chaque coup (fen_before) pour mesurer le dilemme réel
## du camp au trait, puis la pression infligée au coup suivant.
func analyze_game(game: ChessGame, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false

	var em = _resolve_engine()
	if em == null:
		return _finish({"error": "EngineManager non disponible", "cliff_version": 2})

	var moves: Array[ChessMove] = game.move_history.duplicate()
	if moves.is_empty():
		return _finish(_empty_report({}))

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var cfg := _read_config(options, 14 if is_mobile else 18, false, 4000)
	var theory_plies: int = int(options.get("theory_plies", 0))

	var start_fen := ChessGame.INITIAL_FEN
	if game.pgn_headers.has("FEN") and str(game.pgn_headers["FEN"]).strip_edges() != "":
		start_fen = str(game.pgn_headers["FEN"]).strip_edges()
	var vgame := ChessGame.new(start_fen)
	var plies_data: Array = []
	var total_plies := moves.size()

	for t in range(total_plies):
		if cancel_requested:
			break
		progress.emit(t + 1, total_plies)

		var move_t: ChessMove = moves[t]
		var prev: ChessMove = moves[t - 1] if t > 0 else null
		var ply := _analyze_position(em, vgame, move_t, move_t.uci, str(move_t.san), prev, t < theory_plies, cfg)
		vgame.make_move(move_t)
		_finalize_ply(ply, t, vgame.get_fen(), plies_data)
		plies_data.append(ply)
		ply_cliff_computed.emit(t, ply)

	return _finish(_build_report(plies_data, vgame, cfg.source_meta, {}))

## Analyse la difficulté cognitive d'une ligne de coups (PV) depuis une FEN de départ.
## Émet `step_analyzed` à chaque coup (mode Super Live). Un coup illégal interrompt
## la ligne (`truncated_at`) : les demi-coups suivants seraient calculés sur une fausse position.
func analyze_pv_line(start_fen: String, pv_moves: Array, options: Dictionary = {}, reset_cancel: bool = true) -> Dictionary:
	is_analyzing = true
	if reset_cancel:
		cancel_requested = false

	var em = _resolve_engine()
	if em == null:
		return _finish({"error": "EngineManager non disponible", "cliff_version": 2})

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var cfg := _read_config(options, 12 if is_mobile else 16, true, 3500)
	var max_plies: int = int(options.get("max_plies", 8))
	var line_meta := {"is_pv_line": true, "start_fen": start_fen}

	var vgame := ChessGame.new(start_fen)
	var plies_to_eval: int = mini(pv_moves.size(), max_plies)
	if plies_to_eval == 0:
		return _finish(_empty_report(line_meta))

	var plies_data: Array = []
	var prev: ChessMove = null
	for k in range(plies_to_eval):
		if cancel_requested:
			break
		progress.emit(k + 1, plies_to_eval)

		var raw_uci: String = str(pv_moves[k])
		var move_obj: ChessMove = vgame.find_move(raw_uci)
		if move_obj == null:
			line_meta["truncated_at"] = k
			break

		var step := _analyze_position(em, vgame, move_obj, raw_uci, str(move_obj.san), prev, false, cfg)
		vgame.make_move(move_obj)
		var fen_after := vgame.get_fen()
		_finalize_ply(step, k, fen_after, plies_data)
		plies_data.append(step)
		prev = move_obj
		step_analyzed.emit(k, raw_uci, fen_after, step)

	return _finish(_build_report(plies_data, vgame, cfg.source_meta, line_meta))

## Niveau Méso : audite rapidement plusieurs lignes moteur depuis une FEN de départ.
## Retourne { rank -> { piste, indice_d, delta, bait, p_survie, report } }.
## Une annulation interrompt l'ensemble : aucune ligne partielle n'est publiée.
func analyze_multiple_lines_sync(start_fen: String, lines_array: Array, options: Dictionary = {}) -> Dictionary:
	cancel_requested = false
	var results: Dictionary = {}
	var max_lines: int = mini(lines_array.size(), int(options.get("max_lines", 5)))
	var line_plies: int = int(options.get("line_plies", 4))
	var is_white_start := ChessGame.new(start_fen).active_color == ChessPiece.PieceColor.WHITE

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
		if not opts.has("probe_count"):
			opts["probe_count"] = 1

		var rep: Dictionary = analyze_pv_line(start_fen, pv, opts, false)
		if bool(rep.get("cancelled", false)):
			break
		if rep.is_empty() or rep.has("error"):
			continue

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

# ─────────────────────────────────────────────────────────────────────────
# Cœur : un demi-coup
# ─────────────────────────────────────────────────────────────────────────

## Analyse le dilemme du camp au trait dans `vgame` (non modifié) avant le coup `played`.
## `prev` : coup adverse précédent (détection de reprise), null au premier demi-coup.
func _analyze_position(em, vgame: ChessGame, played: ChessMove, played_uci: String, san_move: String,
		prev: ChessMove, in_theory: bool, cfg: Dictionary) -> Dictionary:
	var fen_before := vgame.get_fen()
	var is_white_turn := vgame.active_color == ChessPiece.PieceColor.WHITE
	var sign := 1 if is_white_turn else -1

	# ── ORACLE : MultiPV profond dans fen_before ────────────────────────
	var deep_res: Dictionary = em.evaluate_deep_multipv_sync(fen_before, cfg.deep_depth, cfg.multipv, cfg.timeout_ms)
	var reliable := _engine_ok(deep_res)
	var deep_score_cp: int = int(deep_res.get("score_cp", 0))
	var deep_mate_in: int = int(deep_res.get("mate_in", 0))
	var best_move_uci: String = str(deep_res.get("best_move", ""))

	var mpv_lines: Array = deep_res.get("multipv_lines", [])
	var deep_by_uci := _deep_wdl_map(mpv_lines, is_white_turn)
	var wdl_best := CliffMath.wdl(sign * deep_score_cp, sign * deep_mate_in)
	if deep_by_uci.has(best_move_uci):
		wdl_best = float(deep_by_uci[best_move_uci])
	elif best_move_uci != "":
		deep_by_uci[best_move_uci] = wdl_best

	# Deuxième ligne réellement mesurée ? Sinon Δ reste inconnu (0) et aucun « coup vital ».
	var second_best_uci := ""
	var wdl_second := wdl_best
	var second_measured := false
	if mpv_lines.size() > 1 and mpv_lines[1] is Dictionary:
		second_best_uci = str((mpv_lines[1] as Dictionary).get("best_move", ""))
		if deep_by_uci.has(second_best_uci):
			wdl_second = float(deep_by_uci[second_best_uci])
			second_measured = true
	# Borne supérieure des coups hors MultiPV : la pire ligne rapportée.
	var wdl_unknown_bound := wdl_second
	for v in deep_by_uci.values():
		wdl_unknown_bound = minf(wdl_unknown_bound, float(v))
	var delta_t := CliffMath.delta_chute(wdl_best, wdl_second) if second_measured else 0.0

	# ── Contexte tactique ───────────────────────────────────────────────
	var legal_moves: Array[ChessMove] = vgame.get_legal_moves()
	var n_legal := legal_moves.size()
	var side_in_check := vgame.is_in_check(vgame.active_color)
	var is_recap := prev != null and prev.captured_piece != ChessPiece.Type.NONE \
			and _is_recapture_available(legal_moves, prev.to_sq)
	var is_forced := n_legal == 1 or CliffMath.is_suite_forcee(side_in_check, is_recap,
			_has_winning_capture(vgame, legal_moves))

	var ply := {
		"san": san_move,
		"move_uci": played_uci,
		"played_uci": played_uci,
		"fen_before": fen_before,
		"fen": fen_before,
		"side_to_move": "white" if is_white_turn else "black",
		"is_white": is_white_turn,
		"reliable": reliable,
		"in_theory": in_theory,
		"best_move": best_move_uci,
		"second_best_move": second_best_uci,
		"score_cp": deep_score_cp,
		"mate_in": deep_mate_in,
		"depth": int(deep_res.get("depth", cfg.deep_depth)),
		"oracle_timed_out": bool(deep_res.get("timed_out", false)),
		"pv_line": [best_move_uci] if best_move_uci != "" else [],
		"multipv_lines": mpv_lines,
		"wdl_deep": wdl_best,
		"legal_moves_count": n_legal,
		"is_forced": is_forced,
	}

	if in_theory or not reliable:
		_fill_neutral(ply, wdl_best, in_theory)
		return ply

	# ── Candidats : perception intuitive (depth 1 + saillance) ──────────
	var moves_to_eval: Array = legal_moves
	if cfg.fast_mode and cfg.top_k > 0 and n_legal > cfg.top_k:
		moves_to_eval = _filter_top_salient(vgame, legal_moves, best_move_uci, cfg.top_k, played_uci)

	var cands: Array = []
	var v_percu_all: Array[float] = []
	var first_shallow := true
	for idx in range(moves_to_eval.size()):
		var lm: ChessMove = moves_to_eval[idx]
		var child := ChessGame.new(fen_before)
		child.make_move(lm)
		var is_check := child.is_in_check(child.active_color)

		var deep_known := deep_by_uci.has(lm.uci)
		var d_m: float = float(deep_by_uci[lm.uci]) if deep_known else wdl_unknown_bound

		var wdl_shallow_m := wdl_best - CliffTypes.SHALLOW_PLACEHOLDER_PENALTY
		var shallow_known := false
		if not child.has_any_legal_move():
			# Position terminale : valeur exacte, inutile d'interroger le moteur.
			wdl_shallow_m = 1.0 if is_check else 0.5
			shallow_known = true
		elif not cfg.fast_mode or lm.uci == best_move_uci or lm.uci == played_uci or idx < 3:
			# Un seul ucinewgame par position suffit : il purge la TT de la recherche
			# profonde ; la contamination entre coups frères à depth 1 est négligeable.
			var shallow_res: Dictionary = em.evaluate_shallow_sync(child.get_fen(),
					CliffTypes.SHALLOW_TIMEOUT_MS, cfg.shallow_depth, cfg.ucinewgame and first_shallow)
			first_shallow = false
			if _engine_ok(shallow_res, false):
				wdl_shallow_m = CliffMath.wdl(sign * int(shallow_res.get("score_cp", 0)),
						sign * int(shallow_res.get("mate_in", 0)))
				shallow_known = true
			elif deep_known:
				wdl_shallow_m = d_m

		var s_m := CliffMath.saillance({
			"is_check": is_check,
			"captured_piece": lm.captured_piece,
			"piece": lm.piece,
			"from_sq": lm.from_sq,
			"to_sq": lm.to_sq,
			"color": lm.color
		})
		var v_m := CliffMath.v_percu(wdl_shallow_m, s_m)
		v_percu_all.append(v_m)
		cands.append({
			"uci": lm.uci, "san": str(lm.san), "from_sq": lm.from_sq, "to_sq": lm.to_sq,
			"v_percu": v_m, "wdl_deep": d_m, "wdl_static": wdl_shallow_m,
			"is_check": is_check, "deep_known": deep_known, "shallow_known": shallow_known
		})

	var p_humain_dist := CliffMath.p_humain_distribution(v_percu_all)

	# ── RADAR DE PIÈGES : sonde les coups humainement probables hors MultiPV ──
	_probe_unknown_candidates(em, fen_before, cands, p_humain_dist, best_move_uci, sign, cfg.probe_count)

	var wdl_deep_all: Array[float] = []
	var known_all: Array = []
	var max_cand_idx := -1
	var max_v_percu := -INF
	var best_idx := -1
	for i in range(cands.size()):
		var c: Dictionary = cands[i]
		wdl_deep_all.append(float(c["wdl_deep"]))
		known_all.append(bool(c["deep_known"]))
		if float(c["v_percu"]) > max_v_percu:
			max_v_percu = float(c["v_percu"])
			max_cand_idx = i
		if str(c["uci"]) == best_move_uci:
			best_idx = i

	var viable_indices := CliffMath.get_viable_indices(wdl_deep_all, wdl_best, known_all)
	var viable_p_sum := 0.0
	for v_idx in viable_indices:
		viable_p_sum += float(p_humain_dist[v_idx])

	var bait_t := 0.0
	if max_cand_idx >= 0 and bool(cands[max_cand_idx]["deep_known"]):
		bait_t = CliffMath.bait(wdl_best, float(cands[max_cand_idx]["wdl_deep"]))
	var h_mob_t := CliffMath.h_mob(wdl_deep_all, wdl_best, p_humain_dist, known_all)
	var p_surv_t := CliffMath.p_survie(is_forced, viable_p_sum)
	var indice_d_t := CliffMath.indice_d([delta_t], [p_surv_t], [bait_t], h_mob_t)
	var extra := _build_visual_info(cands, p_humain_dist, max_v_percu, wdl_best)

	# ── Nature cognitive et cases interdites ───────────────────────────
	var nature := CliffTypes.MoveNature.SAFE
	var poisoned_sqs: Array[int] = []
	var expl := ""
	var only_move := second_measured and viable_indices.size() == 1 \
			and delta_t >= CliffTypes.DELTA_VITAL - 0.0001
	if only_move:
		nature = CliffTypes.MoveNature.VITAL
		var best_c: Dictionary = cands[best_idx] if best_idx >= 0 else {}
		var best_san := str(best_c.get("san", best_move_uci))
		if played_uci == best_move_uci:
			expl = "🧗 Coup unique vital (%s) : seul coup évitant la chute (Δ=%.2f)." % [san_move, delta_t]
		else:
			expl = "🧗 Coup unique requis (%s) — %s chute (Δ=%.2f)." % [best_san, san_move, delta_t]
		# Cases interdites : autres destinations de la pièce qui devait jouer.
		var must_from := int(best_c.get("from_sq", played.from_sq))
		var must_to := int(best_c.get("to_sq", played.to_sq))
		for m in legal_moves:
			if m.from_sq == must_from and m.to_sq != must_to:
				poisoned_sqs.append(int(m.to_sq))
	elif is_forced:
		nature = CliffTypes.MoveNature.FORCED
		expl = "🛡️ Suite forcée (%s) : coup ou reprise incontournable." % san_move
	elif indice_d_t >= CliffTypes.D_CHEMIN_MAX:
		nature = CliffTypes.MoveNature.VITAL
		expl = "🧗 Sentier technique étroit (%s) : haute exigence tactique (D=%d)." % [san_move, indice_d_t]
	else:
		expl = "🟢 Choix naturel (%s) : position saine et ouverte (D=%d)." % [san_move, indice_d_t]

	var played_idx := -1
	for i in range(cands.size()):
		if str(cands[i]["uci"]) == played_uci:
			played_idx = i
			break

	ply.merge({
		"effort_d": indice_d_t,
		"indice_d": indice_d_t,
		"piste": CliffMath.classify_piste_by_d(indice_d_t),
		"delta_chute": delta_t,
		"delta_measured": second_measured,
		"bait": bait_t,
		"p_survie": p_surv_t,
		"h_mob": h_mob_t,
		"move_nature": nature,
		"is_vital": nature == CliffTypes.MoveNature.VITAL,
		"poisoned_squares": poisoned_sqs,
		"explanation": expl,
		"v_percu": float(cands[played_idx]["v_percu"]) if played_idx >= 0 else wdl_best,
		"wdl_static": float(cands[played_idx]["wdl_static"]) if played_idx >= 0 else wdl_best,
		"p_humain": float(p_humain_dist[played_idx]) if played_idx >= 0 else 0.0,
		"threat": _threat(cands, p_humain_dist),
		"bait_move_uci": extra.get("bait_move_uci", ""),
		"bait_from": extra.get("bait_from", -1),
		"bait_to": extra.get("bait_to", -1),
		"mines": extra.get("mines", []),
		"top_candidates": extra.get("top_candidates", [])
	}, true)
	return ply

## Métriques neutres (théorie ou moteur défaillant) : aucune charge attribuée.
func _fill_neutral(ply: Dictionary, wdl_best: float, in_theory: bool) -> void:
	var san := str(ply.get("san", ""))
	ply.merge({
		"effort_d": 0, "indice_d": 0, "piste": CliffTypes.Piste.AUTOROUTE,
		"delta_chute": 0.0, "delta_measured": false, "bait": 0.0, "p_survie": 1.0, "h_mob": 0.0,
		"move_nature": CliffTypes.MoveNature.SAFE, "is_vital": false, "poisoned_squares": [] as Array[int],
		"explanation": ("📖 Théorie (%s)." % san) if in_theory else ("⚠️ Analyse moteur indisponible (%s)." % san),
		"v_percu": wdl_best, "wdl_static": wdl_best, "p_humain": 0.0,
		"threat": clampf((wdl_best - 0.5) * 200.0, 0.0, 100.0),
		"bait_move_uci": "", "bait_from": -1, "bait_to": -1, "mines": [], "top_candidates": []
	}, true)

## Complète un demi-coup une fois le coup joué : index, fen_after et tension latente.
func _finalize_ply(ply: Dictionary, index: int, fen_after: String, previous: Array) -> void:
	ply["ply"] = index
	ply["step"] = index
	ply["fen_after"] = fen_after
	var last_opp_d := CliffTypes.D_LATENT_PRIOR
	if not previous.is_empty():
		last_opp_d = float(previous.back().get("effort_d", CliffTypes.D_LATENT_PRIOR))
	var w := CliffTypes.D_LATENT_W_THREAT
	ply["d_latent_opponent"] = int(round(clampf(w * float(ply.get("threat", 0.0)) + (1.0 - w) * last_opp_d, 0.0, 100.0)))
	ply["pression_d"] = 0
	ply["leverage"] = 0
	ply["surprise_delta"] = 0
	ply["surprise_nature"] = CliffTypes.SurpriseNature.NORMAL

## Menace moyenne (0-100) qu'impose le camp au trait, pondérée par la probabilité humaine.
static func _threat(cands: Array, p_dist: Array) -> float:
	var threat := 0.0
	for i in range(mini(cands.size(), p_dist.size())):
		var w_a := float(cands[i].get("wdl_deep", 0.5))
		threat += float(p_dist[i]) * clampf((w_a - 0.50) * 200.0, 0.0, 100.0)
	return threat

## Sonde (searchmoves) les coups hors MultiPV les plus probables pour un humain,
## dans l'ordre décroissant de P_humain. Une sonde en échec laisse la borne en place.
func _probe_unknown_candidates(em, fen: String, cands: Array, p_dist: Array, best_uci: String,
		sign: int, budget: int) -> void:
	if budget <= 0 or not em.has_method("probe_suspect_move_fast"):
		return
	var order: Array = []
	for i in range(cands.size()):
		if not bool(cands[i]["deep_known"]) and str(cands[i]["uci"]) != best_uci:
			order.append(i)
	order.sort_custom(func(a, b): return float(p_dist[a]) > float(p_dist[b]))
	for i in order.slice(0, budget):
		var c: Dictionary = cands[i]
		var probe: Dictionary = em.probe_suspect_move_fast(fen, str(c["uci"]),
				CliffTypes.PROBE_DEPTH, CliffTypes.PROBE_TIMEOUT_MS)
		if not _engine_ok(probe):
			continue
		c["wdl_deep"] = CliffMath.wdl(sign * int(probe.get("score_cp", 0)), sign * int(probe.get("mate_in", 0)))
		c["deep_known"] = true
		c["probed"] = true

# ─────────────────────────────────────────────────────────────────────────
# Rapport
# ─────────────────────────────────────────────────────────────────────────

func _build_report(plies_data: Array, final_game: ChessGame, source_meta: Dictionary, extra: Dictionary) -> Dictionary:
	# Second passage : pression infligée, leverage, surprise, attaque.
	var final_mate := final_game.is_in_check(final_game.active_color) and not final_game.has_any_legal_move()
	for i in range(plies_data.size()):
		var p: Dictionary = plies_data[i]
		var cur_d: int = int(p.get("effort_d", 0))
		var pres_d := cur_d
		var surprise := 0
		if i + 1 < plies_data.size():
			pres_d = int(plies_data[i + 1].get("effort_d", 0))
			surprise = pres_d - int(p.get("d_latent_opponent", cur_d))
		elif final_mate:
			pres_d = 100
		p["pression_d"] = pres_d
		p["leverage"] = pres_d - cur_d
		p["surprise_delta"] = surprise
		p["surprise_nature"] = CliffTypes.classify_surprise(surprise)
		if int(p.get("move_nature", 0)) == CliffTypes.MoveNature.SAFE and bool(p.get("reliable", true)) \
				and pres_d - cur_d >= ATTACK_LEVERAGE:
			p["move_nature"] = CliffTypes.MoveNature.ATTACK
			p["explanation"] = "⚡ Attaque (%s) : impose une charge D=%d à l'adversaire." % [str(p.get("san", "")), pres_d]

	var sum_w := _compute_side_summary(_side_plies(plies_data, true))
	var sum_b := _compute_side_summary(_side_plies(plies_data, false))
	var report := {
		"cliff_version": 2,
		"semantics": CliffTypes.SEMANTICS,
		"source_meta": source_meta,
		"plies_analyzed": plies_data.size(),
		"plies": plies_data,
		"summary_white": sum_w,
		"summary_black": sum_b,
		"pressure_white": sum_b,
		"pressure_black": sum_w,
		"cancelled": cancel_requested
	}
	report.merge(extra, true)
	return report

func _empty_report(extra: Dictionary) -> Dictionary:
	var rep := {
		"cliff_version": 2,
		"semantics": CliffTypes.SEMANTICS,
		"plies_analyzed": 0,
		"plies": [],
		"summary_white": {},
		"summary_black": {}
	}
	rep.merge(extra, true)
	return rep

func _finish(report: Dictionary) -> Dictionary:
	is_analyzing = false
	analysis_finished.emit(report)
	return report

## Demi-coups qui comptent comme décision d'un camp (hors théorie et échecs moteur).
static func _side_plies(plies_data: Array, white: bool) -> Array:
	var out: Array = []
	for p in plies_data:
		if bool(p.get("is_white", true)) == white and bool(p.get("reliable", true)) and not bool(p.get("in_theory", false)):
			out.append(p)
	return out

func _compute_side_summary(plies: Array) -> Dictionary:
	if plies.is_empty():
		return {
			"p_survie_ligne": 1.0,
			"avg_delta_chute": 0.0,
			"max_delta_chute": 0.0,
			"max_bait": 0.0,
			"avg_h_mob": 0.0,
			"global_piste": CliffTypes.Piste.AUTOROUTE,
			"indice_d": 0
		}

	var deltas: Array[float] = []
	var survies: Array[float] = []
	var baits: Array[float] = []
	var sum_h := 0.0
	for p in plies:
		deltas.append(float(p.get("delta_chute", 0.0)))
		survies.append(float(p.get("p_survie", 1.0)))
		baits.append(float(p.get("bait", 0.0)))
		sum_h += float(p.get("h_mob", 0.0))
	var avg_h := sum_h / float(plies.size())
	var max_delta: float = deltas.max()
	var avg_delta := 0.0
	for d in deltas:
		avg_delta += d
	avg_delta /= float(deltas.size())

	# Pire fenêtre glissante (produit simple si la ligne tient dans l'horizon) :
	# pas de rupture de régime selon la longueur.
	var p_ligne := CliffMath.p_survie_horizon_min(survies, CliffTypes.HORIZON_PLIES)

	var d_score := CliffMath.indice_d(deltas, survies, baits, avg_h)
	# Règle de l'Abysse : un ravin ou un effondrement de survie ne peut pas être
	# dilué par les coups triviaux voisins. Échelle pleine : Δ=0.9 → D=90 (Champ de mines).
	if max_delta >= CliffTypes.DELTA_CORNICHE:
		d_score = maxi(d_score, int(round(max_delta * 100.0)))
	if p_ligne < CliffTypes.P_CHEMIN_LO:
		d_score = maxi(d_score, int(round((1.0 - p_ligne) * 100.0 * 0.75)))

	return {
		"p_survie_ligne": p_ligne,
		"avg_delta_chute": avg_delta,
		"max_delta_chute": max_delta,
		"max_bait": baits.max(),
		"avg_h_mob": avg_h,
		"global_piste": CliffMath.classify_piste_by_d(d_score),
		"indice_d": d_score
	}

# ─────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────

func _resolve_engine():
	if engine_manager != null:
		return engine_manager
	return Engine.get_main_loop().root.get_node_or_null("/root/EngineManager")

func _read_config(options: Dictionary, default_depth: int, default_fast: bool, default_timeout: int) -> Dictionary:
	return {
		"deep_depth": int(options.get("deep_depth", default_depth)),
		"fast_mode": bool(options.get("fast_mode", default_fast)),
		"shallow_depth": maxi(1, int(options.get("shallow_depth", 1))),
		"top_k": int(options.get("top_k", 5)),
		"ucinewgame": bool(options.get("ucinewgame", true)),
		"timeout_ms": int(options.get("timeout_ms", default_timeout)),
		"multipv": maxi(2, int(options.get("multipv", 3))),
		"probe_count": maxi(0, int(options.get("probe_count", CliffTypes.PROBE_COUNT))),
		"source_meta": options.get("source_meta", {}),
	}

## Vrai si une réponse moteur est exploitable (pas d'erreur, recherche effectuée).
## `need_move` : exige un bestmove (faux pour les évaluations de feuille depth 1
## dont la position peut être terminale).
static func _engine_ok(res: Dictionary, need_move: bool = true) -> bool:
	if res.has("error") or bool(res.get("cancelled", false)):
		return false
	if need_move and str(res.get("best_move", "")) == "":
		return false
	return int(res.get("depth", 1)) > 0 or int(res.get("mate_in", 0)) != 0

## Construit la correspondance UCI -> WDL profond réel depuis les lignes MultiPV.
func _deep_wdl_map(mpv_lines: Array, is_white_turn: bool) -> Dictionary:
	var map := {}
	var sign := 1 if is_white_turn else -1
	for l in mpv_lines:
		if not (l is Dictionary):
			continue
		var uci := str((l as Dictionary).get("best_move", ""))
		if uci == "" or map.has(uci):
			continue
		map[uci] = CliffMath.wdl(sign * int((l as Dictionary).get("score_cp", 0)),
				sign * int((l as Dictionary).get("mate_in", 0)))
	return map

## Informations visuelles (Rayons X) : coup le plus séduisant (appât), cases-mines, top candidats.
## Une mine est un coup quasi aussi séduisant que l'appât, dont la valeur profonde est CONNUE
## et non viable ; son poids est la perte réelle. `wdl_best` < 0 : déduit des candidats connus.
func _build_visual_info(cands: Array, p_humain_dist: Array, max_v_percu: float, wdl_best: float = -1.0) -> Dictionary:
	if wdl_best < 0.0:
		for c in cands:
			if bool(c.get("deep_known", true)):
				wdl_best = maxf(wdl_best, float(c.get("wdl_deep", 0.0)))

	var bait_idx := -1
	var best_v := -INF
	var mines: Array = []
	var top: Array = []
	for i in range(cands.size()):
		var c: Dictionary = cands[i]
		var v := float(c.get("v_percu", 0.0))
		c["p_humain"] = float(p_humain_dist[i]) if i < p_humain_dist.size() else 0.0
		top.append(c)
		if v > best_v:
			best_v = v
			bait_idx = i
		var loss := wdl_best - float(c.get("wdl_deep", 0.0))
		if bool(c.get("deep_known", true)) and loss > CliffTypes.WDL_MOK_TOLERANCE \
				and v >= max_v_percu - 0.06 and int(c.get("to_sq", -1)) >= 0:
			mines.append({"sq": int(c.get("to_sq", -1)), "weight": clampf(loss, 0.0, 1.0)})

	top.sort_custom(func(a, b): return float(a.get("p_humain", 0.0)) > float(b.get("p_humain", 0.0)))
	var bait_c: Dictionary = cands[bait_idx] if bait_idx >= 0 else {}
	return {
		"bait_move_uci": str(bait_c.get("uci", "")),
		"bait_from": int(bait_c.get("from_sq", -1)),
		"bait_to": int(bait_c.get("to_sq", -1)),
		"mines": mines,
		"top_candidates": top.slice(0, 3)
	}

## Vrai si un coup légal gagne du matériel à coup sûr : prise d'une pièce plus forte,
## ou d'une pièce non défendue (le roi ne capture que des pièces non défendues).
static func _has_winning_capture(game: ChessGame, legal_moves: Array) -> bool:
	for m in legal_moves:
		if m.captured_piece == ChessPiece.Type.NONE:
			continue
		var v_tgt := CliffMath.piece_point_value(m.captured_piece)
		var v_src := CliffMath.piece_point_value(m.piece)
		if v_tgt > v_src:
			return true
		var defender := ChessPiece.PieceColor.BLACK if m.color == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
		if not game.is_square_attacked(m.to_sq, defender):
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

## Filtre les coups légaux par saillance cognitive en priorisant le best_move et le coup joué.
func _filter_top_salient(vgame: ChessGame, legal_moves: Array, best_move_uci: String, limit: int, priority_uci: String = "") -> Array:
	var scored: Array = []
	var fen_curr := vgame.get_fen()
	for m in legal_moves:
		var s := 0.0
		if m.uci == best_move_uci:
			s = 100.0
		elif priority_uci != "" and m.uci == priority_uci:
			s = 90.0
		else:
			var ch := ChessGame.new(fen_curr)
			ch.make_move(m)
			var gives_check := ch.is_in_check(ch.active_color)
			s = CliffMath.saillance({
				"is_check": gives_check,
				"captured_piece": m.captured_piece,
				"piece": m.piece,
				"from_sq": m.from_sq,
				"to_sq": m.to_sq,
				"color": m.color
			})
		scored.append({"move": m, "score": s})

	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var result: Array = []
	for i in range(mini(limit, scored.size())):
		result.append(scored[i]["move"])
	return result
