extends SceneTree
## tests/test_carnet_events.gd — LeCarnet Étage 1 (§4.3 → §4.4.2).
## Vérifie la détection négative/positive/curieuse, les garde-fous et l'idempotence.
## Aucun moteur, aucun réseau : entrées synthétiques uniquement.

const ChessGame = preload("res://src/core/ChessGame.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")
const CarnetEvents = preload("res://src/carnet/CarnetEvents.gd")

var _failures := 0

func _init() -> void:
	print("--- Running CarnetEvents (Étage 1) test ---")

	_test_event_id()
	_test_negative_atom()
	_test_guards()
	_test_positive_unique()
	_test_surprise()
	_test_mystery()
	_test_quiet_move_ignored()
	_test_annotate_game()

	if _failures == 0:
		print("ALL CARNET EVENTS TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("CARNET EVENTS TESTS FAILED: %d" % _failures)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _base_coup() -> Dictionary:
	return {
		"game_id": "g1",
		"ply": 0,
		"date_iso": "2026-09-01",
		"couleur": "white",
		"san": "e4",
		"uci": "e2e4",
		"piece": 1,
		"quality": ChessMove.Quality.BEST,
		"cp_loss": 0,
		"perte_winpct": 0.0,
		"eval_avant": 20,
		"eval_apres": 20,
		"meilleur_coup_uci": "e2e4",
		"pv": [],
		"fen_avant": ChessGame.INITIAL_FEN,
		"fen_apres": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
		"phase": "opening",
		"dans_la_theorie": false,
		"eco": "C20",
		"ply_sortie_theorie": 4,
		"nb_plies_partie": 40,
	}

func _test_event_id() -> void:
	var a := CarnetEvents.event_id_for("g1", 12, "white")
	var b := CarnetEvents.event_id_for("g1", 12, "white")
	var c := CarnetEvents.event_id_for("g1", 13, "white")
	var d := CarnetEvents.event_id_for("g2", 12, "white")
	_check(a == b and a != c and a != d, "event_id stable et discriminant")
	_check(a.length() == 40, "event_id = SHA1 hex (40 car.)")

func _test_negative_atom() -> void:
	var coup := _base_coup()
	coup["quality"] = ChessMove.Quality.BLUNDER
	coup["perte_winpct"] = 40.0
	coup["cp_loss"] = 300
	coup["eval_apres"] = -280
	var atom := CarnetEvents.annotate(coup)
	_check(not atom.is_empty(), "faute -> atome")
	_check(atom.get("polarite", "") == "négatif", "polarité négative")
	_check(atom.get("categorie", "") == "gaffe", "catégorie = gaffe")
	_check(float(atom.get("perte_winpct", 0.0)) == 40.0, "perte_winpct conservée")
	_check(atom.has("IS") and atom.has("IM"), "IS/IM présents")
	_check(atom.get("regime", "") == "équilibré", "régime calculé sur win% avant le coup")

func _test_guards() -> void:
	var theory := _base_coup()
	theory["quality"] = ChessMove.Quality.BLUNDER
	theory["perte_winpct"] = 40.0
	theory["dans_la_theorie"] = true
	_check(CarnetEvents.annotate(theory).is_empty(), "coup de théorie ignoré")

	var forced := _base_coup()
	forced["quality"] = ChessMove.Quality.BLUNDER
	forced["perte_winpct"] = 40.0
	forced["nb_coups_legaux"] = 1
	_check(CarnetEvents.annotate(forced).is_empty(), "coup forcé ignoré")

	var short_game := _base_coup()
	short_game["quality"] = ChessMove.Quality.BLUNDER
	short_game["perte_winpct"] = 40.0
	short_game["nb_plies_partie"] = 5
	_check(CarnetEvents.annotate(short_game).is_empty(), "partie < 10 plies ignorée")

	var slow := _base_coup()
	slow["quality"] = ChessMove.Quality.INACCURACY
	slow["perte_winpct"] = 5.0
	_check(CarnetEvents.annotate(slow).is_empty(), "perte < 10 win% ignorée")

func _test_positive_unique() -> void:
	var coup := _base_coup()
	coup["quality"] = ChessMove.Quality.BEST
	coup["multipv"] = [
		{"score_cp": 20, "move": "e2e4"},
		{"score_cp": -300, "move": "d2d4"},
	]
	var atom := CarnetEvents.annotate(coup)
	_check(not atom.is_empty(), "seul coup -> atome")
	_check(atom.get("polarite", "") == "positif", "polarité positive")
	_check(bool(atom["marqueurs"]["coup_unique"]), "marqueur coup_unique")
	_check(atom.get("categorie", "") == "trouvaille", "catégorie trouvaille")

func _test_surprise() -> void:
	var coup := _base_coup()
	coup["quality"] = ChessMove.Quality.BEST
	coup["uci"] = "g1f3"
	coup["meilleur_coup_uci"] = "g1f3"
	coup["piece"] = 2
	coup["eval_avant"] = 0
	coup["eval_apres"] = 500
	coup["win_before"] = 50.0
	coup["win_after"] = 89.0
	coup["ply_sortie_theorie"] = 0
	coup["multipv"] = [
		{"score_cp": 0, "move": "g1f3"},
		{"score_cp": -350, "move": "b1c3"},
	]
	var atom := CarnetEvents.annotate(coup)
	_check(not atom.is_empty(), "surprise -> atome")
	_check(bool(atom.get("surprise", false)), "drapeau surprise (IS ≥ 60)")
	_check(float(atom.get("IS", 0.0)) >= 60.0, "IS ≥ 60")

func _test_mystery() -> void:
	var coup := _base_coup()
	coup["uci"] = "b1c3"
	coup["meilleur_coup_uci"] = "b1c3"
	coup["piece"] = 2
	coup["quality"] = ChessMove.Quality.BEST
	coup["fen_avant"] = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1"
	coup["winpct_by_depth"] = {8: 50.0, 22: 90.0}
	var mp := []
	for i in range(6):
		mp.append({"score_cp": 20 - i, "move": "m%d" % i})
	coup["multipv"] = mp
	var atom := CarnetEvents.annotate(coup)
	_check(not atom.is_empty(), "mystère -> atome")
	_check(bool(atom.get("mystere", false)), "drapeau mystère (IM ≥ 65)")
	_check(float(atom.get("IM", 0.0)) >= 65.0, "IM ≥ 65")

func _test_quiet_move_ignored() -> void:
	var coup := _base_coup()
	coup["quality"] = ChessMove.Quality.GOOD
	var atom := CarnetEvents.annotate(coup)
	_check(atom.is_empty(), "coup calme ignoré")

func _test_annotate_game() -> void:
	var sim = ChessGame.new()
	var moves := []
	for i in range(12):
		var legal = sim.get_legal_moves()
		if legal.is_empty():
			break
		var m = legal[0]
		moves.append({"ply": i, "is_white": i % 2 == 0, "san": m.san, "uci": m.uci})
		sim.make_move(m)
	var evals := []
	for i in range(moves.size()):
		var q = ChessMove.Quality.BLUNDER if i == 6 else ChessMove.Quality.GOOD
		evals.append({
			"ply": i,
			"is_white": i % 2 == 0,
			"san": moves[i]["san"],
			"uci": moves[i]["uci"],
			"quality": q,
			"loss_cp": 300 if i == 6 else 5,
			"score_cp": -280 if i == 6 else 20,
			"winpct_loss": 40.0 if i == 6 else 0.0,
			"is_theory": false,
			"best_alternative": "",
			"best_move": "",
		})
	var game_data := {"id": "gg", "date": "2026-09-02", "moves": moves}
	var analysis := {"evaluations": evals, "opening": {"eco": "C20", "out_of_book_ply": 4}, "theory_plies": 4}
	var atoms := CarnetEvents.annotate_game(game_data, analysis)
	_check(atoms.size() >= 1, "annotate_game produit au moins un atome")
	var found_blunder := false
	for a in atoms:
		if a.get("ply", -1) == 6:
			found_blunder = true
	_check(found_blunder, "la gaffe au ply 6 est détectée")
