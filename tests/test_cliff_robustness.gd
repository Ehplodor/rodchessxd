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

## Moteur factice : `deep` est renvoyé tel quel par l'oracle MultiPV.
class FakeEngine extends Node:
	var deep: Dictionary = {}
	var probe_calls := 0
	func evaluate_deep_multipv_sync(_fen: String, _depth: int, _mpv: int, _t: int) -> Dictionary:
		return deep.duplicate(true)
	func evaluate_shallow_sync(_fen: String, _t: int, _d: int, _u: bool) -> Dictionary:
		return {"score_cp": 0, "mate_in": 0, "best_move": "a1a2", "depth": 1, "timed_out": false}
	func probe_suspect_move_fast(_fen: String, _uci: String, _d: int, _t: int) -> Dictionary:
		probe_calls += 1
		return {"score_cp": 0, "mate_in": 0, "best_move": "", "depth": 0, "timed_out": true}

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

	em.queue_free()
	print("--- Cliff robustness : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF ROBUSTNESS TESTS PASSED SUCCESSFULLY!")
	quit(0 if _failures == 0 else 1)
