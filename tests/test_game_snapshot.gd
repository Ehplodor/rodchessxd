extends SceneTree
## tests/test_game_snapshot.gd — instantané de partie et bornes de phase (purs).

const GameSnapshot = preload("res://src/core/GameSnapshot.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- GameSnapshot tests ---")
	await process_frame
	_test_apply_live_state()
	_test_phase_boundaries()

	if _failures == 0:
		print("ALL GAME SNAPSHOT TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("GAME SNAPSHOT TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)

func _test_apply_live_state() -> void:
	var pgn := """[Event "Snapshot"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0"""
	var live := ChessGame.new()
	_check(live.load_pgn(pgn), "PGN chargé")
	var game := {"result": "*"}
	GameSnapshot.apply_live_state(game, live)
	var moves: Array = game.get("moves", [])
	_check(moves.size() == 4, "4 demi-coups sérialisés")
	_check(int(moves[0].get("ply", -1)) == 0 and int(moves[0].get("move_number", 0)) == 1,
			"premier demi-coup : ply 0, coup 1")
	_check(bool(moves[0].get("is_white", false)), "ply 0 = blancs")
	_check(not bool(moves[1].get("is_white", true)), "ply 1 = noirs")
	_check(int(moves[1].get("move_number", 0)) == 1, "noir au coup 1")
	_check(str(moves[0].get("uci", "")) == "e2e4", "UCI du premier coup")
	_check(str(game.get("pgn_text", "")).contains("1."), "PGN régénéré")
	_check(str(game.get("result", "")) == "1-0", "résultat repris des en-têtes")

func _test_phase_boundaries() -> void:
	_check(GameSnapshot.phase_boundaries({}).is_empty(), "rapport vide → aucune borne")
	var theory := GameSnapshot.phase_boundaries({"theory_plies": 6, "evaluations": []})
	_check(theory.size() == 1 and int(theory[0]) == 6, "fin de théorie = première borne")

	var endgame_fen := "8/8/8/4k3/4K3/8/8/8 w - - 0 1"
	var with_endgame := GameSnapshot.phase_boundaries({
		"theory_plies": 0,
		"evaluations": [
			{"ply": 10, "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "is_theory": false},
			{"ply": 12, "fen": endgame_fen, "is_theory": false},
			{"ply": 14, "fen": endgame_fen, "is_theory": false},
		],
	})
	_check(with_endgame.size() == 1 and int(with_endgame[0]) == 12,
			"premier demi-coup de finale détecté (et une seule fois)")

	var theory_skipped := GameSnapshot.phase_boundaries({
		"theory_plies": 0,
		"evaluations": [{"ply": 12, "fen": endgame_fen, "is_theory": true}],
	})
	_check(theory_skipped.is_empty(), "les coups de théorie sont ignorés")
