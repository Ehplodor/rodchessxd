class_name GameSnapshot
extends RefCounted
## GameSnapshot.gd — helpers purs d'instantané d'une partie (extraits de Main).
##
## Sérialise l'état vivant d'une `ChessGame` dans la fiche persistée et calcule les
## bornes de phase du graphe d'avantage. Aucune dépendance UI.

## Reflète TOUS les coups joués dans la fiche persistée (sinon l'archive reste figée
## aux coups présents lors de sa création), ainsi que le PGN et le résultat.
static func apply_live_state(game: Dictionary, live: ChessGame) -> void:
	if live == null:
		return
	var moves_arr: Array = []
	for i in range(live.move_history.size()):
		var m = live.move_history[i]
		var info := live.ply_info(i)
		moves_arr.append({
			"ply": i,
			"move_number": info["move_number"],
			"is_white": info["is_white"],
			"san": m.san,
			"uci": m.uci,
			"quality": m.quality,
			"loss_cp": m.centipawn_loss,
		})
	game["moves"] = moves_arr
	game["pgn_text"] = live.export_pgn()
	game["result"] = live.pgn_headers.get("Result", game.get("result", "*"))

## Bornes de phase du graphe : fin de théorie puis premier demi-coup de finale.
static func phase_boundaries(report: Dictionary) -> Array:
	var evals: Array = report.get("evaluations", [])
	var theory: int = int(report.get("theory_plies", 0))
	var bounds: Array = []
	if theory > 0:
		bounds.append(theory)
	for ev in evals:
		if not (ev is Dictionary) or ev.get("is_theory", false):
			continue
		if GamePhaseService.phase_for(str(ev.get("fen", "")), int(ev.get("ply", 0)), theory) == "endgame":
			var es := int(ev.get("ply", 0))
			if es > 0:
				bounds.append(es)
			break
	return bounds
