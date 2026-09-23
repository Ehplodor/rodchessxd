extends SceneTree
## tests/test_cliff_annotations.gd — logique pure de présentation CHESS-CLIFF.

const CliffAnnotations = preload("res://src/engine/CliffAnnotations.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- CliffAnnotations tests ---")

	_test_apply_to_moves()
	_test_build_step_visual()
	_test_find_step()
	_test_line_summary()

	if _failures == 0:
		print("ALL CLIFF ANNOTATIONS TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF ANNOTATIONS TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)

func _test_apply_to_moves() -> void:
	var moves := [ChessMove.new(), ChessMove.new(), ChessMove.new()]
	var report := {"plies": [
		{"ply": 0, "piste": 3, "delta_chute": 0.4, "bait": 0.1, "p_survie": 0.5,
			"effort_d": 77, "surprise_nature": 2, "surprise_delta": 5},
		{"ply": 2, "piste": 1, "indice_d": 30},
		{"ply": 9, "piste": 1},
		"bad",
	]}
	var n := CliffAnnotations.apply_to_moves(moves, report)
	_check(n == 2, "2 coups annotés (hors-bornes et non-dict ignorés)")
	_check(int(moves[0].cliff_piste) == 3, "piste copiée")
	_check(is_equal_approx(float(moves[0].cliff_delta_chute), 0.4), "delta_chute copié")
	_check(int(moves[0].cliff_indice_d) == 77, "effort_d prioritaire sur indice_d")
	_check(int(moves[2].cliff_indice_d) == 30, "fallback indice_d")
	_check(int(moves[1].cliff_piste) == -1, "coup non listé inchangé")

func _test_build_step_visual() -> void:
	# X-ray off, pas de vitalité, pas de case empoisonnée → pas de surcouche.
	var quiet := CliffAnnotations.build_step_visual({"san": "e4", "piste": 3, "best_move": "e2e4"}, false)
	_check(str(quiet.get("best_uci", "")) == "e2e4", "meilleur coup exposé")
	_check((quiet.get("overlay", {}) as Dictionary).is_empty(), "aucune surcouche si X-ray off")

	# X-ray activé → surcouche complète.
	var xray := CliffAnnotations.build_step_visual({"san": "e4", "piste": 3, "best_move": "e2e4"}, true)
	var ov := xray.get("overlay", {}) as Dictionary
	_check(not ov.is_empty(), "surcouche si X-ray on")
	_check(str(ov.get("label", "")).contains("e4"), "label contient le SAN")
	_check(ov.has("poisoned_squares") and ov.has("mines"), "champs mines/cases empoisonnées présents")

	# Coup vital : surcouche même sans X-ray.
	var vital := CliffAnnotations.build_step_visual(
			{"san": "Qh5", "piste": 5, "is_vital": true, "indice_d": 88}, false)
	_check(not (vital.get("overlay", {}) as Dictionary).is_empty(), "vital force la surcouche")
	_check(str((vital.get("overlay", {}) as Dictionary).get("label", "")).contains("vital"),
			"label vital spécifique")

	# Case empoisonnée seule : surcouche.
	var poison := CliffAnnotations.build_step_visual(
			{"san": "Nf3", "piste": 2, "poisoned_squares": [12]}, false)
	_check(not (poison.get("overlay", {}) as Dictionary).is_empty(), "case empoisonnée force la surcouche")

func _test_find_step() -> void:
	var plies := [
		{"move_uci": "e2e4", "fen_before": "FEN_A", "fen_after": "FEN_B"},
		{"move_uci": "e7e5", "fen_before": "FEN_B", "fen_after": "FEN_C"},
	]
	_check(str(CliffAnnotations.find_step(plies, "", "FEN_B").get("move_uci", "")) == "e7e5",
			"recherche par FEN : l'étape décidée dans cette position")
	_check(str(CliffAnnotations.find_step(plies, "", "FEN_C").get("move_uci", "")) == "e7e5",
			"recherche par FEN finale (fen_after)")
	_check(str(CliffAnnotations.find_step(plies, "e7e5", "").get("move_uci", "")) == "e7e5",
			"recherche par UCI")
	_check(CliffAnnotations.find_step(plies, "zzzz", "").is_empty(), "introuvable → {}")

func _test_line_summary() -> void:
	var report := {
		"summary_white": {"global_piste": 2, "indice_d": 40, "max_delta_chute": 0.3,
			"max_bait": 0.2, "p_survie_ligne": 0.7},
		"summary_black": {"global_piste": 5, "indice_d": 90, "max_delta_chute": 0.8,
			"max_bait": 0.5, "p_survie_ligne": 0.1},
		"plies": [{"move_uci": "g1f3"}],
	}
	var w := CliffAnnotations.line_piste_summary(report, true)
	_check(int(w.get("piste", -1)) == 2, "résumé côté blancs")
	_check(is_equal_approx(float(w.get("p_survie", 0.0)), 0.7), "p_survie côté blancs")
	var b := CliffAnnotations.line_piste_summary(report, false)
	_check(int(b.get("piste", -1)) == 5, "résumé côté noirs")
	_check(CliffAnnotations.first_step_uci(report) == "g1f3", "premier coup de la ligne")
	_check(CliffAnnotations.first_step_uci({}) == "", "rapport vide → \"\"")
