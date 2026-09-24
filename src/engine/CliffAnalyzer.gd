class_name CliffAnalyzer
extends RefCounted
## CliffAnalyzer.gd — Orchestrateur moteur pour l'analyse cognitive CHESS-CLIFF.
## Trois recherches Stockfish par position (voir _evaluate_root) : intuition de TOUS les coups
## légaux (une MultiPV superficielle), oracle MultiPV profond, vérification groupée des coups
## humains probables hors MultiPV ; puis chute, appât, mobilité, survie et piste.
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
## Mémo des mesures de position par FEN, vidé à chaque analyse de premier niveau
## (une comparaison Méso le partage entre ses lignes).
var _pos_cache: Dictionary = {}

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
	_pos_cache.clear()

	var em = _resolve_engine()
	if em == null:
		return _finish({"error": "EngineManager non disponible", "cliff_version": 2})

	var moves: Array[ChessMove] = game.move_history.duplicate()
	if moves.is_empty():
		return _finish(_empty_report({}))

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var cfg := _read_config(options, 14 if is_mobile else 18, 4000)
	var theory_plies: int = int(options.get("theory_plies", 0))

	var vgame := ChessGame.new(_start_fen(game))
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

## Criblage des moments clés : une MultiPV 2 peu profonde par demi-coup hors théorie.
## Retourne { ply -> écart WDL entre 1re et 2e ligne } (point de vue du camp au trait) ;
## un demi-coup à coup légal unique ou sans 2e ligne mesurée est absent.
func screen_plies(game: ChessGame, theory_plies: int = 0, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	var gaps := {}
	var em = _resolve_engine()
	if em == null:
		is_analyzing = false
		return gaps
	var depth := int(options.get("screen_depth", CliffTypes.SCREEN_DEPTH))
	var vgame := ChessGame.new(_start_fen(game))
	var moves: Array = game.move_history
	for t in range(moves.size()):
		if cancel_requested:
			break
		progress.emit(t + 1, moves.size())
		if t >= theory_plies and vgame.get_legal_moves().size() > 1:
			var sign := 1 if vgame.active_color == ChessPiece.PieceColor.WHITE else -1
			var res: Dictionary = em.search_sync(vgame.get_fen(), {"depth": depth, "multipv": 2,
					"timeout_ms": CliffTypes.SCREEN_TIMEOUT_MS, "use_cache": false})
			var lines: Array = res.get("multipv_lines", [])
			if _engine_ok(res) and lines.size() >= 2:
				gaps[t] = CliffMath.delta_chute(CliffMath.wdl_of_line(lines[0], sign), CliffMath.wdl_of_line(lines[1], sign))
		vgame.make_move(moves[t])
	is_analyzing = false
	return gaps

## Analyse Cliff complète sur les seuls demi-coups `ply_indices` de la partie (moments clés).
## Retourne { ply -> données Cliff du demi-coup } ; émet ply_cliff_computed à chaque demi-coup.
func analyze_plies(game: ChessGame, ply_indices: Array, options: Dictionary = {}) -> Dictionary:
	is_analyzing = true
	cancel_requested = false
	_pos_cache.clear()
	var out := {}
	var em = _resolve_engine()
	if em == null:
		is_analyzing = false
		return out
	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var cfg := _read_config(options, 14 if is_mobile else 18, 4000)
	var wanted := {}
	for p in ply_indices:
		wanted[int(p)] = true
	var vgame := ChessGame.new(_start_fen(game))
	var moves: Array = game.move_history
	var done := 0
	for t in range(moves.size()):
		if cancel_requested or done >= wanted.size():
			break
		var move_t: ChessMove = moves[t]
		if wanted.has(t):
			done += 1
			progress.emit(done, wanted.size())
			var prev: ChessMove = moves[t - 1] if t > 0 else null
			var ply := _analyze_position(em, vgame, move_t, move_t.uci, str(move_t.san), prev, false, cfg)
			ply["ply"] = t
			ply["step"] = t
			vgame.make_move(move_t)
			ply["fen_after"] = vgame.get_fen()
			out[t] = ply
			ply_cliff_computed.emit(t, ply)
		else:
			vgame.make_move(move_t)
	is_analyzing = false
	return out

static func _start_fen(game: ChessGame) -> String:
	if game.pgn_headers.has("FEN") and str(game.pgn_headers["FEN"]).strip_edges() != "":
		return str(game.pgn_headers["FEN"]).strip_edges()
	return ChessGame.INITIAL_FEN

## Analyse la difficulté cognitive d'une ligne de coups (PV) depuis une FEN de départ.
## Émet `step_analyzed` à chaque coup (mode Super Live). Un coup illégal interrompt
## la ligne (`truncated_at`) : les demi-coups suivants seraient calculés sur une fausse position.
func analyze_pv_line(start_fen: String, pv_moves: Array, options: Dictionary = {}, reset_cancel: bool = true) -> Dictionary:
	is_analyzing = true
	if reset_cancel:
		cancel_requested = false
		_pos_cache.clear()

	var em = _resolve_engine()
	if em == null:
		return _finish({"error": "EngineManager non disponible", "cliff_version": 2})

	var is_mobile := OS.has_feature("android") or OS.has_feature("ios")
	var cfg := _read_config(options, 12 if is_mobile else 16, 3500)
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
	_pos_cache.clear()
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
## La partie « position » (indépendante du coup joué) est mémorisée par FEN : plusieurs
## lignes partageant une racine (comparaison Méso) ne la paient qu'une fois.
func _analyze_position(em, vgame: ChessGame, played: ChessMove, played_uci: String, san_move: String,
		prev: ChessMove, in_theory: bool, cfg: Dictionary) -> Dictionary:
	var fen_before := vgame.get_fen()
	var is_white_turn := vgame.active_color == ChessPiece.PieceColor.WHITE
	var legal_moves: Array[ChessMove] = vgame.get_legal_moves()

	var key := "%s|%d" % [fen_before, 1 if in_theory else 0]
	var pos: Dictionary
	if _pos_cache.has(key):
		pos = _pos_cache[key]
	else:
		pos = _evaluate_root(em, vgame, legal_moves, fen_before, is_white_turn, in_theory, cfg)
		if bool(pos["reliable"]):
			_pos_cache[key] = pos

	# Étiquette « suite forcée » : n'influence plus la survie (la saillance modélise déjà
	# l'évidence d'une prise ou d'un échec), elle qualifie seulement la nature du coup.
	var is_recap := prev != null and prev.captured_piece != ChessPiece.Type.NONE \
			and _is_recapture_available(legal_moves, prev.to_sq)
	var is_forced := legal_moves.size() == 1 or CliffMath.is_suite_forcee(
			vgame.is_in_check(vgame.active_color), is_recap, _has_winning_capture(vgame, legal_moves))

	var best_move_uci := str(pos["best_move"])
	var ply := {
		"san": san_move,
		"move_uci": played_uci,
		"played_uci": played_uci,
		"fen_before": fen_before,
		"fen": fen_before,
		"side_to_move": "white" if is_white_turn else "black",
		"is_white": is_white_turn,
		"reliable": pos["reliable"],
		"in_theory": in_theory,
		"best_move": best_move_uci,
		"second_best_move": pos["second_best_move"],
		"score_cp": pos["score_cp"],
		"mate_in": pos["mate_in"],
		"depth": pos["depth"],
		"oracle_timed_out": pos["oracle_timed_out"],
		"pv_line": [best_move_uci] if best_move_uci != "" else [],
		"multipv_lines": (pos["multipv_lines"] as Array).duplicate(true),
		"wdl_deep": pos["wdl_best"],
		"legal_moves_count": legal_moves.size(),
		"is_forced": is_forced,
	}

	var wdl_best := float(pos["wdl_best"])
	if in_theory or not bool(pos["reliable"]):
		_fill_neutral(ply, wdl_best, in_theory)
		return ply

	var cands: Array = (pos["cands"] as Array).duplicate(true)
	var p_dist: Array = pos["p_dist"]
	var delta_t := float(pos["delta_chute"])
	var indice_d_t := int(pos["indice_d"])

	# ── Nature cognitive et cases interdites ───────────────────────────
	var nature := CliffTypes.MoveNature.SAFE
	var poisoned_sqs: Array[int] = []
	var expl := ""
	if bool(pos["only_move"]):
		nature = CliffTypes.MoveNature.VITAL
		var best_idx := int(pos["best_idx"])
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

	var extra := _build_visual_info(cands, p_dist, float(pos["max_v_percu"]), wdl_best)
	ply.merge({
		"effort_d": indice_d_t,
		"indice_d": indice_d_t,
		"piste": CliffMath.classify_piste_by_d(indice_d_t),
		"delta_chute": delta_t,
		"delta_measured": pos["delta_measured"],
		"bait": pos["bait"],
		"p_survie": pos["p_survie"],
		"p_survie_lo": pos["p_survie_lo"],
		"p_survie_hi": pos["p_survie_hi"],
		"p_survie_exact": pos["p_survie_exact"],
		"probed_mass": pos["probed_mass"],
		"h_mob": pos["h_mob"],
		"move_nature": nature,
		"is_vital": nature == CliffTypes.MoveNature.VITAL,
		"only_move": pos["only_move"],
		"poisoned_squares": poisoned_sqs,
		"explanation": expl,
		"v_percu": float(cands[played_idx]["v_percu"]) if played_idx >= 0 else wdl_best,
		"wdl_static": float(cands[played_idx]["wdl_static"]) if played_idx >= 0 else wdl_best,
		"p_humain": float(p_dist[played_idx]) if played_idx >= 0 else 0.0,
		"threat": _threat(cands, p_dist),
		"bait_move_uci": extra.get("bait_move_uci", ""),
		"bait_from": extra.get("bait_from", -1),
		"bait_to": extra.get("bait_to", -1),
		"mines": extra.get("mines", []),
		"top_candidates": extra.get("top_candidates", [])
	}, true)
	return ply

## Mesures de la position (indépendantes du coup joué), en trois requêtes moteur :
## 1. Intuition : MultiPV = tous les coups légaux à faible profondeur (TT isolée).
## 2. Oracle : MultiPV K profond (vérité, Δ, meilleur coup).
## 3. Vérification : UNE recherche « searchmoves » sur les coups hors MultiPV les plus
##    probables pour un humain, jusqu'à couvrir PROBE_MASS de la masse P_humain.
## Aucune valeur inventée : un coup jamais mesuré en profondeur n'a qu'une borne.
func _evaluate_root(em, vgame: ChessGame, legal_moves: Array[ChessMove], fen: String,
		is_white_turn: bool, in_theory: bool, cfg: Dictionary) -> Dictionary:
	var sign := 1 if is_white_turn else -1
	var n_legal := legal_moves.size()

	# ── 1. INTUITION (d'abord : l'isolation TT ne doit pas effacer l'oracle) ──
	var shallow_by_uci := {}
	var intuition_ok := true
	if not in_theory and n_legal > 0:
		var ires: Dictionary = em.search_sync(fen, {
			"depth": cfg.shallow_depth + 1, "multipv": n_legal, "clear_tt": cfg.isolate_intuition,
			"timeout_ms": CliffTypes.INTUITION_TIMEOUT_MS, "use_cache": false})
		intuition_ok = _engine_ok(ires, false)
		for l in ires.get("multipv_lines", []):
			var u := str(l.get("best_move", ""))
			if u != "" and not shallow_by_uci.has(u):
				shallow_by_uci[u] = CliffMath.wdl_of_line(l, sign)

	# ── 2. ORACLE ─────────────────────────────────────────────────────────
	var k := maxi(1, mini(cfg.multipv, n_legal))
	var deep_res: Dictionary = em.search_sync(fen, {
		"depth": cfg.deep_depth, "multipv": k, "timeout_ms": cfg.timeout_ms})
	var reliable := _engine_ok(deep_res) and (in_theory or (intuition_ok and not shallow_by_uci.is_empty()))
	var mpv_lines: Array = deep_res.get("multipv_lines", [])
	var deep_by_uci := {}
	for l in mpv_lines:
		var u := str(l.get("best_move", ""))
		if u != "" and not deep_by_uci.has(u):
			deep_by_uci[u] = CliffMath.wdl_of_line(l, sign)
	var best_move_uci := str(deep_res.get("best_move", ""))
	var wdl_best := CliffMath.wdl(sign * int(deep_res.get("score_cp", 0)), sign * int(deep_res.get("mate_in", 0)))
	if deep_by_uci.has(best_move_uci):
		wdl_best = float(deep_by_uci[best_move_uci])
	elif best_move_uci != "":
		deep_by_uci[best_move_uci] = wdl_best

	var pos := {
		"reliable": reliable,
		"best_move": best_move_uci,
		"second_best_move": "",
		"score_cp": int(deep_res.get("score_cp", 0)),
		"mate_in": int(deep_res.get("mate_in", 0)),
		"depth": int(deep_res.get("depth", cfg.deep_depth)),
		"oracle_timed_out": bool(deep_res.get("timed_out", false)),
		"multipv_lines": mpv_lines,
		"wdl_best": wdl_best,
	}
	if in_theory or not reliable:
		return pos

	# Deuxième ligne réellement mesurée ? Sinon Δ reste inconnu (0) et aucun « coup vital ».
	var second_measured := false
	var wdl_second := wdl_best
	if mpv_lines.size() > 1:
		pos["second_best_move"] = str(mpv_lines[1].get("best_move", ""))
		if deep_by_uci.has(pos["second_best_move"]):
			wdl_second = float(deep_by_uci[pos["second_best_move"]])
			second_measured = true
	# Borne supérieure des coups hors MultiPV : la pire ligne rapportée (valable seulement
	# si le moteur a rendu les K lignes demandées ; sinon tous les coups sont déjà connus).
	var wdl_unknown_bound := wdl_best
	for v in deep_by_uci.values():
		wdl_unknown_bound = minf(wdl_unknown_bound, float(v))
	var delta_t := CliffMath.delta_chute(wdl_best, wdl_second) if second_measured else 0.0

	# ── Perception : saillance + valeur intuitive de CHAQUE coup légal ──
	var lowest_shallow := 1.0
	for v in shallow_by_uci.values():
		lowest_shallow = minf(lowest_shallow, float(v))
	var cands: Array = []
	var v_percu_all: Array[float] = []
	for lm in legal_moves:
		var is_check := vgame.gives_check(lm)
		var shallow_known := shallow_by_uci.has(lm.uci)
		# Coup absent de la recherche intuitive (interrompue) : le moins visible des coups mesurés.
		var w_s: float = float(shallow_by_uci[lm.uci]) if shallow_known else lowest_shallow
		var deep_known := deep_by_uci.has(lm.uci)
		var s_m := CliffMath.saillance({
			"is_check": is_check, "captured_piece": lm.captured_piece, "piece": lm.piece,
			"from_sq": lm.from_sq, "to_sq": lm.to_sq, "color": lm.color})
		var v_m := CliffMath.v_percu(w_s, s_m)
		v_percu_all.append(v_m)
		cands.append({
			"uci": lm.uci, "san": str(lm.san), "from_sq": lm.from_sq, "to_sq": lm.to_sq,
			"v_percu": v_m, "wdl_deep": float(deep_by_uci[lm.uci]) if deep_known else wdl_unknown_bound,
			"wdl_static": w_s, "is_check": is_check, "deep_known": deep_known,
			"shallow_known": shallow_known, "probed": false
		})
	var p_dist := CliffMath.p_humain_distribution(v_percu_all, cfg.beta)

	# ── 3. VÉRIFICATION groupée des coups humains probables hors MultiPV ──
	var probed_mass := _probe_unknown_candidates(em, fen, cands, p_dist, sign, cfg)

	# ── Viabilité (≤ WDL_MOK_TOLERANCE : mobilité, coup unique) et survie (perte
	# < WDL_FALL_TOLERANCE : pas de chute). Un coup jamais mesuré en profondeur n'est
	# admissible que si la borne (pire ligne MultiPV) l'autorise ; on l'estime alors
	# admissible si son évaluation intuitive vaut celle du meilleur coup.
	var tol := CliffTypes.WDL_MOK_TOLERANCE + 0.0001
	var fall_tol := CliffTypes.WDL_FALL_TOLERANCE + 0.0001
	var best_static := wdl_best
	for c in cands:
		if str(c["uci"]) == best_move_uci:
			best_static = float(c["wdl_static"])
	var wdl_eff: Array[float] = []
	var known_eff: Array = []
	var p_lo := 0.0
	var p_hi := 0.0
	var p_point := 0.0
	var max_v := -INF
	var max_idx := -1
	var best_idx := -1
	for i in range(cands.size()):
		var c: Dictionary = cands[i]
		var p := float(p_dist[i])
		var w := float(c["wdl_deep"])
		wdl_eff.append(w)
		if bool(c["deep_known"]):
			known_eff.append(true)
			if wdl_best - w < fall_tol:
				p_lo += p
				p_hi += p
				p_point += p
		else:
			var gap_static := best_static - float(c["wdl_static"])
			var bound_gap := wdl_best - wdl_unknown_bound
			known_eff.append(bound_gap <= tol and gap_static <= tol)
			if bound_gap < fall_tol:
				p_hi += p
				if gap_static < fall_tol:
					p_point += p
		if float(c["v_percu"]) > max_v:
			max_v = float(c["v_percu"])
			max_idx = i
		if str(c["uci"]) == best_move_uci:
			best_idx = i

	var viable := CliffMath.get_viable_indices(wdl_eff, wdl_best, known_eff)
	var bait_t := 0.0
	if max_idx >= 0 and bool(cands[max_idx]["deep_known"]):
		bait_t = CliffMath.bait(wdl_best, float(cands[max_idx]["wdl_deep"]))
	var h_mob_t := CliffMath.h_mob(wdl_eff, wdl_best, p_dist, known_eff)
	var p_surv_t := CliffMath.p_survie(p_point)
	var indice_d_t := CliffMath.indice_d([delta_t], [p_surv_t], [bait_t], h_mob_t)

	pos.merge({
		"cands": cands,
		"p_dist": p_dist,
		"max_v_percu": max_v,
		"best_idx": best_idx,
		"delta_chute": delta_t,
		"delta_measured": second_measured,
		"only_move": second_measured and viable.size() == 1 and delta_t >= CliffTypes.DELTA_VITAL - 0.0001,
		"bait": bait_t,
		"h_mob": h_mob_t,
		"p_survie": p_surv_t,
		"p_survie_lo": clampf(p_lo, 0.0, 1.0),
		"p_survie_hi": clampf(p_hi, 0.0, 1.0),
		"p_survie_exact": p_hi - p_lo < 0.005,
		"probed_mass": probed_mass,
		"indice_d": indice_d_t,
	}, true)
	return pos

## Métriques neutres (théorie ou moteur défaillant) : aucune charge attribuée.
func _fill_neutral(ply: Dictionary, wdl_best: float, in_theory: bool) -> void:
	var san := str(ply.get("san", ""))
	ply.merge({
		"effort_d": 0, "indice_d": 0, "piste": CliffTypes.Piste.AUTOROUTE,
		"delta_chute": 0.0, "delta_measured": false, "bait": 0.0, "p_survie": 1.0, "h_mob": 0.0,
		"move_nature": CliffTypes.MoveNature.SAFE, "is_vital": false, "only_move": false, "poisoned_squares": [] as Array[int],
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

## Vérifie en UNE recherche « searchmoves » (MultiPV = nb de coups) les coups hors MultiPV
## les plus probables pour un humain, par P_humain décroissante, jusqu'à ce que la masse
## mesurée atteigne cfg.probe_mass (au plus cfg.probe_max coups). Retourne la masse
## P_humain dont la valeur profonde est connue. Une recherche en échec laisse les bornes.
func _probe_unknown_candidates(em, fen: String, cands: Array, p_dist: Array, sign: int, cfg: Dictionary) -> float:
	var known_mass := 0.0
	var order: Array = []
	for i in range(cands.size()):
		if bool(cands[i]["deep_known"]):
			known_mass += float(p_dist[i])
		else:
			order.append(i)
	order.sort_custom(func(a, b): return float(p_dist[a]) > float(p_dist[b]))
	var picked: Array = []
	var ucis: Array = []
	var target_mass := known_mass
	for i in order:
		if target_mass >= cfg.probe_mass or picked.size() >= cfg.probe_max:
			break
		picked.append(i)
		ucis.append(str(cands[i]["uci"]))
		target_mass += float(p_dist[i])
	if picked.is_empty():
		return known_mass

	var res: Dictionary = em.search_sync(fen, {
		"depth": maxi(CliffTypes.PROBE_DEPTH, cfg.deep_depth / 2), "multipv": picked.size(),
		"searchmoves": ucis, "timeout_ms": CliffTypes.PROBE_TIMEOUT_MS, "use_cache": false})
	if not _engine_ok(res):
		return known_mass
	var by_uci := {}
	for l in res.get("multipv_lines", []):
		var u := str(l.get("best_move", ""))
		if u != "" and not by_uci.has(u):
			by_uci[u] = CliffMath.wdl_of_line(l, sign)
	for i in picked:
		var c: Dictionary = cands[i]
		if by_uci.has(c["uci"]):
			c["wdl_deep"] = float(by_uci[c["uci"]])
			c["deep_known"] = true
			c["probed"] = true
			known_mass += float(p_dist[i])
	return known_mass

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
	# Règle de l'Abysse : le demi-coup le plus exigeant ne peut pas être dilué par les
	# coups triviaux voisins. On retient son D (qui combine Δ, survie et appât) plutôt
	# que Δ seul : un ravin que tout le monde évite (repli évident) n'est pas un piège.
	var worst_ply_d := 0
	for p in plies:
		worst_ply_d = maxi(worst_ply_d, int(p.get("effort_d", 0)))
	d_score = maxi(d_score, worst_ply_d)
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

func _read_config(options: Dictionary, default_depth: int, default_timeout: int) -> Dictionary:
	return {
		"deep_depth": int(options.get("deep_depth", default_depth)),
		"shallow_depth": maxi(1, int(options.get("shallow_depth", 1))),
		# Isolation de l'intuition : ucinewgame avant la recherche superficielle, pour
		# qu'elle ne profite pas de la TT remplie par les recherches profondes.
		"isolate_intuition": bool(options.get("isolate_intuition", true)),
		"timeout_ms": int(options.get("timeout_ms", default_timeout)),
		"multipv": maxi(2, int(options.get("multipv", 3))),
		"probe_mass": clampf(float(options.get("probe_mass", CliffTypes.PROBE_MASS)), 0.0, 1.0),
		"probe_max": maxi(0, int(options.get("probe_max", CliffTypes.PROBE_MAX))),
		"beta": CliffMath.beta_for_elo(int(options.get("player_elo", 0))),
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
