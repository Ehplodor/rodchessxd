class_name EvalFormatter
extends RefCounted
## EvalFormatter.gd - Formatage centralisé des évaluations (centipions / mat).
## Évite la duplication d'affichage entre le badge, la barre, le graphe et la liste des coups.

const MATE_CP := 10000

## Vrai si le score représente un mat (distance renseignée ou score extrême).
static func is_mate(score_cp: int, mate_in: int = 0) -> bool:
	if mate_in != 0:
		return true
	return absi(score_cp) >= MATE_CP

## "M3" / "-M2" / "+1.4" / "-0.6" / "0.0". Sans "+" pour la barre d'évaluation.
static func format_cp_mate(score_cp: int, mate_in: int = 0) -> String:
	if mate_in != 0:
		return "M%d" % mate_in if mate_in > 0 else "-M%d" % absi(mate_in)
	if absi(score_cp) >= MATE_CP:
		return "M" if score_cp > 0 else "-M"
	var pawns := float(score_cp) / 100.0
	return ("+%.1f" if pawns >= 0.0 else "%.1f") % pawns

## Représentation numérique pour la légende du graphe ("+5.0", "-2.0").
static func format_pawns(score_cp: int) -> String:
	var pawns := float(score_cp) / 100.0
	return ("+%.1f" if pawns >= 0.0 else "%.1f") % pawns
