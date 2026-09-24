extends SceneTree
## tests/test_cliff_robustness.gd — CliffAnalyzer face à des réponses moteur partielles,
## en échec ou tranchées, via un moteur factice déterministe (aucun Stockfish requis).

const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

## Moteur factice : `deep` est renvoyé tel quel par l'oracle MultiPV ; l'intuition
## (MultiPV = tous les coups, faible profondeur) note chaque coup légal à 0 ; les
## vérifications « searchmoves » échouent (bornes conservées).
class FakeEngine extends Node:
	var deep: Dictionary = {}
	var probe_calls := 0
	var deep_calls := 0
	func search_sync(fen: String, opts: Dictionary) -> Dictionary:
		if not (opts.get("searchmoves", []) as Array).is_empty():
			probe_calls += 1
			return {"score_cp": 0, "mate_in": 0, "best_move": "", "depth": 0, "timed_out": true}
		if int(opts.get("depth", 0)) <= 4:
			var lines: Array = []
			for m in ChessGame.new(fen).get_legal_moves():
				lines.append({"best_move": m.uci, "score_cp": 0, "mate_in": 0, "depth": 2})
			return {"score_cp": 0, "mate_in": 0, "best_move": lines[0]["best_move"], "depth": 2,
					"timed_out": false, "multipv_lines": lines}
		deep_calls += 1
		return deep.duplicate(true)

func _line(uci: String, cp: int) -> Dictionary:
	return {"best_move": uci, "score_cp": cp, "mate_in": 0}

func _init() -> void:
	print("--- Cliff robustness tests ---")
	var em := FakeEngine.new()
	root.add_child(em)
	var an := CliffAnalyzer.new(em)
	var start := ChessGame.INITIAL_FEN

	# 1. Une seule ligne MultiPV : Δ non mesuré, jamais « coup vital ».
	em.deep = {"score_cp": 30, "mate_in": 0, "best_move": "e2e4", "depth": 18,
			"multipv_lines": [_line("e2e4", 30)]}
	var rep := an.analyze_pv_line(start, ["e2e4"], {"fast_mode": true})
	var p0: Dictionary = rep["plies"][0]
	_check(p0["reliable"], "ligne unique : demi-coup fiable")
	_check(not p0["delta_measured"] and p0["delta_chute"] == 0.0, "ligne unique : Δ non inventé")
	_check(p0["move_nature"] != CliffTypes.MoveNature.VITAL or p0["indice_d"] >= CliffTypes.D_CHEMIN_MAX,
			"ligne unique : pas de faux coup unique vital")
	_check(em.probe_calls > 0, "sondes lancées sur les coups hors MultiPV")

	# 2. Échec moteur : demi-coup non fiable, neutre, exclu de la synthèse.
	em.deep = {"score_cp": 0, "best_move": "", "depth": 0, "error": "engine_unavailable"}
	rep = an.analyze_pv_line(start, ["e2e4"], {})
	p0 = rep["plies"][0]
	_check(not p0["reliable"], "erreur moteur → reliable = false")
	_check(p0["indice_d"] == 0 and p0["move_nature"] == CliffTypes.MoveNature.SAFE, "erreur moteur → aucune charge inventée")
	_check(rep["summary_white"]["indice_d"] == 0, "erreur moteur exclue de la synthèse")

	# 3. Vrai coup unique : deux lignes mesurées, écart énorme, coup joué ≠ meilleur.
	em.deep = {"score_cp": 400, "mate_in": 0, "best_move": "e2e4", "depth": 18,
			"multipv_lines": [_line("e2e4", 400), _line("d2d4", -400)]}
	rep = an.analyze_pv_line(start, ["g1f3"], {"fast_mode": true})
	p0 = rep["plies"][0]
	_check(p0["delta_measured"] and p0["delta_chute"] > 0.5, "Δ mesuré entre lignes 1 et 2")
	_check(p0["move_nature"] == CliffTypes.MoveNature.VITAL, "coup unique vital détecté")
	_check(str(p0["explanation"]).find("requis") != -1, "explication : coup requis manqué — " + str(p0["explanation"]))
	_check(p0["p_survie"] < 0.9, "survie < 1 quand un seul coup tient")

	# 4. Coup illégal dans la PV : ligne tronquée, pas d'analyse sur une fausse position.
	rep = an.analyze_pv_line(start, ["e2e4", "e2e4", "g1f3"], {})
	_check(int(rep.get("truncated_at", -1)) == 1 and rep["plies"].size() == 1, "PV illégale tronquée au 2e coup")

	# 5. Partie démarrant avec les Noirs au trait : camp correctement attribué.
	em.deep = {"score_cp": -20, "mate_in": 0, "best_move": "e7e5", "depth": 18,
			"multipv_lines": [_line("e7e5", -20), _line("c7c5", -25)]}
	var bfen := "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	rep = an.analyze_pv_line(bfen, ["e7e5"], {})
	p0 = rep["plies"][0]
	_check(not p0["is_white"], "départ Noirs : premier demi-coup attribué aux Noirs")
	_check(p0["wdl_deep"] > 0.5, "départ Noirs : WDL du point de vue du camp au trait")

	# 6. Position calme : trois lignes quasi égales, les autres coups inconnus mais admis par
	# la borne et équivalents à l'intuition → survie élevée, pas de fausse difficulté.
	em.deep = {"score_cp": 20, "mate_in": 0, "best_move": "e2e4", "depth": 18,
			"multipv_lines": [_line("e2e4", 20), _line("d2d4", 18), _line("g1f3", 15)]}
	rep = an.analyze_pv_line(start, ["c2c4"], {})
	p0 = rep["plies"][0]
	_check(p0["p_survie"] > 0.9, "position calme : survie élevée (%.2f)" % p0["p_survie"])
	_check(p0["p_survie_lo"] <= p0["p_survie"] and p0["p_survie"] <= p0["p_survie_hi"], "survie encadrée [lo, hi]")
	_check(not p0["p_survie_exact"], "masse jamais mesurée signalée (p_survie_exact = false)")
	_check(p0["piste"] == CliffTypes.Piste.AUTOROUTE, "position calme : Autoroute")

	# 7. Comparaison Méso : la racine commune n'est analysée qu'une fois.
	em.deep_calls = 0
	var lines := [{"rank": 1, "pv": ["e2e4"]}, {"rank": 2, "pv": ["d2d4"]}, {"rank": 3, "pv": ["g1f3"]}]
	var multi := an.analyze_multiple_lines_sync(start, lines, {"line_plies": 1})
	_check(multi.size() == 3, "3 lignes comparées")
	_check(em.deep_calls == 1, "racine commune mémorisée : 1 oracle pour 3 lignes (%d)" % em.deep_calls)

	# 8. Moments clés : criblage (1 appel par demi-coup hors théorie) et Cliff ciblé.
	var g := ChessGame.new()
	for u in ["e2e4", "e7e5", "g1f3", "b8c6"]:
		g.make_move(g.find_move(u))
	em.deep = {"score_cp": 20, "mate_in": 0, "best_move": "a2a3", "depth": 18,
			"multipv_lines": [_line("a2a3", 20), _line("h2h3", -300)]}
	em.deep_calls = 0
	var gaps := an.screen_plies(g, 1, {"screen_depth": 10})
	_check(em.deep_calls == 3, "criblage : 1 recherche par demi-coup hors théorie (%d)" % em.deep_calls)
	_check(gaps.size() == 3 and not gaps.has(0) and float(gaps[2]) > 0.2 and float(gaps[1]) == 0.0, "écarts 1re/2e mesurés du point de vue du camp au trait")
	em.deep_calls = 0
	var only := an.analyze_plies(g, [1, 3])
	_check(only.keys() == [1, 3] and em.deep_calls == 2, "Cliff uniquement sur les demi-coups demandés")
	_check(int(only[3]["ply"]) == 3 and str(only[3]["played_uci"]) == "b8c6", "demi-coup ciblé correctement rejoué")
	_check(only[1].has("only_move"), "only_move exposé pour le jugement des moments")

	em.queue_free()
	print("--- Cliff robustness : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF ROBUSTNESS TESTS PASSED SUCCESSFULLY!")
	quit(0 if _failures == 0 else 1)
