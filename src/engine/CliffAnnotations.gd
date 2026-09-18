class_name CliffAnnotations
extends RefCounted
## CliffAnnotations.gd — logique pure de présentation CHESS-CLIFF, extraite de Main.
##
## Aucune dépendance UI : ces helpers transforment un rapport Cliff / une étape de
## ligne en données prêtes à appliquer (annotations de coups, payload de surcouche
## X-ray, badge de piste d'une ligne). Testables sans scène.

## Applique les métriques Cliff d'un rapport sur les coups d'une partie.
## Sémantique canonique V2.3 : `plies[t]` est évalué dans `fen_before` et correspond
## directement à `moves[t]`. Renvoie le nombre de coups annotés.
static func apply_to_moves(moves: Array, report: Dictionary) -> int:
	var plies: Array = report.get("plies", [])
	var applied := 0
	for p_data in plies:
		if not (p_data is Dictionary):
			continue
		var move_idx: int = int(p_data.get("ply", p_data.get("step", -1)))
		if move_idx < 0 or move_idx >= moves.size():
			continue
		var m = moves[move_idx]
		if m == null:
			continue
		m.cliff_piste = int(p_data.get("piste", -1))
		m.cliff_delta_chute = float(p_data.get("delta_chute", 0.0))
		m.cliff_bait = float(p_data.get("bait", 0.0))
		m.cliff_p_survie = float(p_data.get("p_survie", 1.0))
		m.cliff_indice_d = int(p_data.get("effort_d", p_data.get("indice_d", -1)))
		m.cliff_surprise_nature = int(p_data.get("surprise_nature", CliffTypes.SurpriseNature.NORMAL))
		m.cliff_surprise_delta = int(p_data.get("surprise_delta", 0))
		applied += 1
	return applied

## Construit le visuel d'une étape de ligne Cliff.
## Renvoie `{ "best_uci": String, "overlay": Dictionary }` : `overlay` est vide quand
## aucune surcouche X-ray n'est nécessaire (il faut alors simplement la flèche du
## meilleur coup).
static func build_step_visual(step: Dictionary, xray_enabled: bool) -> Dictionary:
	var piste := int(step.get("piste", 0))
	var san := str(step.get("san", step.get("move_uci", "")))
	var indice := int(step.get("indice_d", 0))
	var is_vital := bool(step.get("is_vital", false))
	var nature := int(step.get("move_nature", CliffTypes.MoveNature.VITAL if is_vital else CliffTypes.MoveNature.SAFE))
	var label := "Joué : %s · %s · D=%d" % [san, CliffTypes.get_piste_name(piste), indice]
	if is_vital:
		label = "🧗 Coup unique vital : %s (D=%d)" % [san, indice]
	elif nature == CliffTypes.MoveNature.FORCED:
		label = "🛡️ Suite forcée : %s (D=%d)" % [san, indice]
	elif nature == CliffTypes.MoveNature.ATTACK:
		label = "⚡ Attaque directe : %s (D=%d)" % [san, indice]

	var best_u := str(step.get("best_move", step.get("move_uci", "")))
	var poisoned: Array = step.get("poisoned_squares", []) if step.get("poisoned_squares", []) is Array else []
	if not xray_enabled and not is_vital and poisoned.is_empty():
		return {"best_uci": best_u, "overlay": {}}

	var overlay := {
		"best_uci": best_u,
		"bait_uci": str(step.get("bait_move_uci", "")),
		"mines": step.get("mines", []),
		"poisoned_squares": poisoned,
		"is_vital": is_vital,
		"move_nature": nature,
		"label": label,
	}
	return {"best_uci": best_u, "overlay": overlay}

## Retrouve une étape de la ligne Cliff par FEN (avant/après) ou par UCI.
static func find_step(plies: Array, uci: String, fen: String) -> Dictionary:
	if fen != "":
		for p in plies:
			if p is Dictionary and (str(p.get("fen_after", "")) == fen or str(p.get("fen_before", "")) == fen):
				return p
	if uci != "":
		for p in plies:
			if p is Dictionary and str(p.get("move_uci", "")) == uci:
				return p
	return {}

## Résumé de piste d'une ligne (côté au trait) pour le badge du panneau moteur.
static func line_piste_summary(report: Dictionary, is_white_turn: bool) -> Dictionary:
	var summary: Dictionary = report.get("summary_white", {}) if is_white_turn else report.get("summary_black", {})
	return {
		"piste": int(summary.get("global_piste", -1)),
		"indice_d": int(summary.get("indice_d", -1)),
		"delta": float(summary.get("max_delta_chute", 0.0)),
		"bait": float(summary.get("max_bait", 0.0)),
		"p_survie": float(summary.get("p_survie_ligne", 1.0)),
	}

## Meilleur coup de la première étape d'un rapport Cliff (flèche initiale), "" sinon.
static func first_step_best_uci(report: Dictionary) -> String:
	var plies: Array = report.get("plies", [])
	if plies.is_empty() or not (plies[0] is Dictionary):
		return ""
	return str(plies[0].get("move_uci", ""))
