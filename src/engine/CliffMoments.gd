class_name CliffMoments
extends RefCounted
## CliffMoments.gd — Moments clés de la Super-Analyse (pur, sans moteur).
##
## 1. select_candidates : à partir de l'analyse classique (perte de gain par coup) et d'un
##    criblage MultiPV 2 (écart 1re/2e ligne), retient les quelques demi-coups où il se passe
##    quelque chose — y compris les chemins étroits TROUVÉS, invisibles pour l'analyse classique.
## 2. classify : Cliff juge chaque candidat (coup unique trouvé/manqué, appât, inattention,
##    position exigeante) et écarte les candidats triviaux (repli évident, reprise forcée).

const CliffTypes = preload("res://src/engine/CliffTypes.gd")

## `evals` : enregistrements classiques (clés ply, winpct_loss, is_theory).
## `gaps` : { ply -> écart WDL 1re/2e ligne } issu du criblage.
## Retourne les indices de demi-coups retenus, triés chronologiquement.
static func select_candidates(evals: Array, gaps: Dictionary, max_count: int = CliffTypes.MOMENT_MAX_CANDIDATES) -> Array:
	var scored: Array = []
	for e in evals:
		if not (e is Dictionary) or bool(e.get("is_theory", false)):
			continue
		var ply := int(e.get("ply", -1))
		if ply < 0:
			continue
		var loss := float(e.get("winpct_loss", 0.0))
		var gap := float(gaps.get(ply, 0.0))
		if loss < CliffTypes.MOMENT_LOSS_MIN and gap < CliffTypes.DELTA_VITAL - 0.0001:
			continue
		scored.append({"ply": ply, "score": maxf(loss / 100.0, gap)})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var out: Array = []
	for i in range(mini(max_count, scored.size())):
		out.append(int(scored[i]["ply"]))
	out.sort()
	return out

## Juge un demi-coup analysé par Cliff. `winpct_loss` : perte classique (points de gain).
## Retourne {} si le moment n'a rien d'instructif.
static func classify(cliff_ply: Dictionary, winpct_loss: float) -> Dictionary:
	if cliff_ply.is_empty() or not bool(cliff_ply.get("reliable", false)) or bool(cliff_ply.get("in_theory", false)):
		return {}
	var played := str(cliff_ply.get("played_uci", ""))
	var best := str(cliff_ply.get("best_move", ""))
	var p_surv := float(cliff_ply.get("p_survie", 1.0))
	var only_move := bool(cliff_ply.get("only_move", false))
	var bait_uci := str(cliff_ply.get("bait_move_uci", ""))
	var bait := float(cliff_ply.get("bait", 0.0))
	var best_san := _best_san(cliff_ply)
	var san := str(cliff_ply.get("san", played))

	var kind := -1
	var text := ""
	if only_move and played == best:
		if p_surv >= CliffTypes.MOMENT_OBVIOUS_SURVIVAL:
			return {}
		kind = CliffTypes.MomentKind.ONLY_FOUND
		text = "Seul %s tenait, et il fallait le voir (survie %d %%)." % [san, _pct(p_surv)]
	elif only_move:
		kind = CliffTypes.MomentKind.ONLY_MISSED
		text = "Seul %s tenait — %s." % [best_san,
				"il était trouvable" if p_surv >= CliffTypes.MOMENT_FINDABLE_SURVIVAL else "très difficile à voir"]
	elif played != "" and played == bait_uci and bait >= CliffTypes.MOMENT_BAIT_MIN:
		kind = CliffTypes.MomentKind.BAIT_TAKEN
		text = "%s était le coup le plus tentant… et le piège. Mieux : %s." % [san, best_san]
	elif winpct_loss >= CliffTypes.MOMENT_ERROR_LOSS and p_surv >= CliffTypes.MOMENT_EASY_SURVIVAL:
		kind = CliffTypes.MomentKind.CARELESS
		text = "Position facile (survie %d %%) : %s était naturel." % [_pct(p_surv), best_san]
	elif winpct_loss >= CliffTypes.MOMENT_ERROR_LOSS:
		kind = CliffTypes.MomentKind.HARD_ERROR
		text = "Position exigeante (survie %d %%). Il fallait %s." % [_pct(p_surv), best_san]
	else:
		return {}

	return {
		"ply": int(cliff_ply.get("ply", -1)),
		"is_white": bool(cliff_ply.get("is_white", true)),
		"san": san,
		"kind": kind,
		"title": str(CliffTypes.MOMENT_TITLES.get(kind, "")),
		"icon": str(CliffTypes.MOMENT_ICONS.get(kind, "")),
		"text": text,
		"played_uci": played,
		"best_uci": best,
		"bait_uci": bait_uci if kind == CliffTypes.MomentKind.BAIT_TAKEN else "",
		"fen_before": str(cliff_ply.get("fen_before", "")),
		"indice_d": int(cliff_ply.get("indice_d", 0)),
		"p_survie": p_surv,
		"delta_chute": float(cliff_ply.get("delta_chute", 0.0)),
		"winpct_loss": winpct_loss,
	}

## Rapport de Super-Analyse V3. `cliff_by_ply` : { ply -> données Cliff } (analyze_plies).
static func build_report(evals: Array, gaps: Dictionary, candidates: Array, cliff_by_ply: Dictionary,
		cancelled: bool = false) -> Dictionary:
	var loss_by_ply := {}
	for e in evals:
		if e is Dictionary:
			loss_by_ply[int(e.get("ply", -1))] = float(e.get("winpct_loss", 0.0))
	var moments: Array = []
	var plies: Array = []
	for ply in candidates:
		if not cliff_by_ply.has(ply):
			continue
		plies.append(cliff_by_ply[ply])
		var m := classify(cliff_by_ply[ply], float(loss_by_ply.get(ply, 0.0)))
		if not m.is_empty():
			moments.append(m)
	return {
		"cliff_version": 3,
		"semantics": CliffTypes.SEMANTICS,
		"moments": moments,
		"plies": plies,
		"screened": gaps.size(),
		"candidates": candidates.size(),
		"cancelled": cancelled,
	}

## Fanions du graphe d'avantage : [{ply, success}].
static func markers(report: Dictionary) -> Array:
	var out: Array = []
	for m in report.get("moments", []):
		out.append({"ply": int(m.get("ply", -1)), "success": CliffTypes.moment_is_success(int(m.get("kind", -1)))})
	return out

## Moment vu depuis l'autre camp : chaque difficulté adverse est une pression infligée.
static func as_pressure(moment: Dictionary) -> Dictionary:
	var m := moment.duplicate()
	var found := int(moment.get("kind", -1)) == CliffTypes.MomentKind.ONLY_FOUND
	m["icon"] = "⚡"
	m["title"] = "Pression infligée"
	m["text"] = ("Tu lui as posé un vrai problème ; il a trouvé la parade (%s)." if found
			else "Tu lui as posé un problème, et il a craqué (%s).") % str(moment.get("san", ""))
	m["pressure"] = true
	return m

## Résumé d'un camp en une ligne : « 2 tests réussis · 1 inattention ».
static func side_summary(moments: Array, white: bool) -> String:
	var counts := {}
	for m in moments:
		if bool(m.get("is_white", true)) == white:
			var k := int(m.get("kind", -1))
			counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array = []
	var labels := {
		CliffTypes.MomentKind.ONLY_FOUND: ["test réussi", "tests réussis"],
		CliffTypes.MomentKind.ONLY_MISSED: ["coup unique manqué", "coups uniques manqués"],
		CliffTypes.MomentKind.BAIT_TAKEN: ["appât mordu", "appâts mordus"],
		CliffTypes.MomentKind.CARELESS: ["inattention", "inattentions"],
		CliffTypes.MomentKind.HARD_ERROR: ["position exigeante ratée", "positions exigeantes ratées"],
	}
	for k in [CliffTypes.MomentKind.ONLY_FOUND, CliffTypes.MomentKind.ONLY_MISSED,
			CliffTypes.MomentKind.BAIT_TAKEN, CliffTypes.MomentKind.CARELESS, CliffTypes.MomentKind.HARD_ERROR]:
		var n := int(counts.get(k, 0))
		if n > 0:
			parts.append("%d %s" % [n, labels[k][0] if n == 1 else labels[k][1]])
	return "Aucun moment critique" if parts.is_empty() else " · ".join(parts)

static func _best_san(cliff_ply: Dictionary) -> String:
	var best := str(cliff_ply.get("best_move", ""))
	for c in cliff_ply.get("top_candidates", []):
		if str(c.get("uci", "")) == best:
			return str(c.get("san", best))
	return best

static func _pct(p: float) -> int:
	return int(round(clampf(p, 0.0, 1.0) * 100.0))
