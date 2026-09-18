extends SceneTree
## tests/test_engine_analysis_entry.gd — schéma unique d'archivage moteur.
## Vérifie que la factorisation classic/Cliff préserve exactement les champs et
## les valeurs par défaut (aucune régression de schéma persisté).

const AnalysisEntry = preload("res://src/engine/EngineAnalysisEntry.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- EngineAnalysisEntry tests ---")

	var report := {
		"white_accuracy": 88.5, "black_accuracy": 74.1,
		"white_estimated_elo": 1720, "black_estimated_elo": 1610,
		"white_elo_ci": 45, "black_elo_ci": 52,
		"white_acpl": 32.0, "black_acpl": 55.0,
		"schema_version": 3, "theory_plies": 6,
		"opening": {"eco": "C20"}, "white_stats": {"blunder": 1},
	}
	var evals := [{"ply": 0, "score_cp": 20}]

	var entry := AnalysisEntry.build(report, evals, 18, "dynamic", "Stockfish 18")
	_check(str(entry.get("engine_name", "")) == "Stockfish 18", "engine_name transmis")
	_check(int(entry.get("depth", 0)) == 18, "depth transmis")
	_check(str(entry.get("mode", "")) == "dynamic", "mode transmis")
	_check(is_equal_approx(float(entry.get("white_accuracy", 0.0)), 88.5), "white_accuracy copiée")
	_check(int(entry.get("white_estimated_elo", 0)) == 1720, "elo blanc copié")
	_check(int(entry.get("white_ipr_elo", 0)) == 1720, "ipr_elo retombe sur elo estimé")
	_check(int(entry.get("schema_version", 0)) == 3, "schema_version copié")
	_check((entry.get("evaluations", []) as Array).size() == 1, "evaluations copiées")
	_check(not entry.has("cliff_data"), "pas de cliff_data hors mode unifié")

	# Valeurs par défaut sur rapport vide.
	var empty := AnalysisEntry.build({}, [], 14, "dynamic")
	_check(is_equal_approx(float(empty.get("white_accuracy", -1.0)), 0.0), "accuracy défaut 0.0")
	_check(int(empty.get("white_estimated_elo", 0)) == 1500, "elo défaut 1500")
	_check(int(empty.get("schema_version", 0)) == 1, "schema défaut 1")
	_check(empty.get("opening", null) is Dictionary, "opening défaut {}")
	_check(empty.get("biggest_swings", null) is Array, "biggest_swings défaut []")

	# Mode unifié : cliff_data présent.
	var cliff := AnalysisEntry.build(report, evals, 20, "dynamic", "Stockfish", {"plies": []})
	_check(cliff.has("cliff_data"), "cliff_data présent en mode unifié")

	# Le rapport source n'est pas muté.
	_check(not report.has("engine_name"), "le rapport source n'est pas muté")

	_check(AnalysisEntry.default_depth() == 18, "profondeur par défaut desktop = 18")

	if _failures == 0:
		print("ALL ENGINE ANALYSIS ENTRY TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("ENGINE ANALYSIS ENTRY TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
