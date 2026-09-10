extends SceneTree
## tests/test_carnet_dataset.gd — Jeu de données cohérent : deux vraies parties jouées
## via les fonctions de l'application (ChessGame), importées, analysées puis traitées
## par le lot, jusqu'à la compilation du carnet. Aucun moteur requis.

const ChessGame = preload("res://src/core/ChessGame.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")
const CarnetStore = preload("res://src/carnet/CarnetStore.gd")
const CarnetBatchRunner = preload("res://src/carnet/CarnetBatchRunner.gd")
const CarnetEvents = preload("res://src/carnet/CarnetEvents.gd")
const DateUtil = preload("res://src/core/DateUtil.gd")

const PSEUDO := "Didier"
const MOVES_A := ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3", "g8f6",
		"c2c3", "d7d6", "e1g1", "c8g4"]
const MOVES_B := ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6", "c4d5", "e6d5",
		"g1f3", "f8b4", "c1g5", "b8c6"]

var _failures := 0
var _db: Node = null
var _ran := false

func _init() -> void:
	print("--- Running coherent Carnet dataset test (%s) ---" % PSEUDO)

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_db = root.get_node_or_null("DatabaseManager")
	if _db == null:
		printerr("DatabaseManager autoload introuvable")
		quit(1)
		return true
	CarnetProfiles.reset()

	# Dates PGN robustes : « 2026.08.30 » normalisée, date inconnue rejetée sans erreur.
	_check(DateUtil.normalize("2026.08.30") == "2026-08-30", "date PGN point → ISO")
	_check(DateUtil.normalize("2026.??.??") == "", "date inconnue rejetée")
	_check(DateUtil.day_index("2026.??.??") == -1, "date inconnue → index -1")

	var game_a := _play(MOVES_A)
	var game_b := _play(MOVES_B)
	_check(game_a.move_history.size() == MOVES_A.size(), "partie A jouée intégralement (12 plies)")
	_check(game_b.move_history.size() == MOVES_B.size(), "partie B jouée intégralement (12 plies)")

	var gid_a: String = _db.record_pgn_game(_to_pgn(game_a), "pgn_import")
	var gid_b: String = _db.record_pgn_game(_to_pgn(game_b), "pgn_import")
	_check(gid_a != "" and gid_b != "", "parties importées via l'application")
	_check(_db.record_pgn_game(_to_pgn(game_a), "pgn_import") == gid_a, "réimport A dédoublonné")

	# Analyse cohérente : bonus calquée sur les vrais coups, une gaffe à un ply réel.
	_db.add_engine_analysis(gid_a, _analysis(game_a, 6))
	_db.add_engine_analysis(gid_b, _analysis(game_b, 9))

	var pid := CarnetProfiles.create(PSEUDO, "local", [PSEUDO])
	var status := CarnetStore.sync_status(pid)
	_check(int(status["total"]) == 2, "2 parties rattachées au pseudo %s" % PSEUDO)
	_check(status["pending"].size() == 2, "2 parties à traiter")

	var runner := CarnetBatchRunner.new()
	runner.configure(pid, [gid_a, gid_b])
	runner.run()
	_check(runner.processed == 2 and runner.failed == 0, "lot : 2 parties traitées, 0 échec")

	status = CarnetStore.sync_status(pid)
	_check(status["known"].size() == 2, "2 parties synchronisées")
	var atoms := CarnetStore.get_atoms(pid)
	_check(atoms.size() >= 1, "au moins un atome généré depuis les vraies parties")
	var has_negative := false
	for a in atoms:
		if str(a.get("polarite", "")) == "négatif":
			has_negative = true
	_check(has_negative, "la gaffe réelle produit un atome négatif")

	var ledger := CarnetStore.compile("2026-09-10", -1, pid)
	_check(int(ledger["nb_atomes"]) == atoms.size(), "carnet compile les atomes des parties")
	_check(not (ledger["motifs"] as Array).is_empty(), "motifs agrégés depuis le jeu de données")

	# Vérifie la stabilité de l'identité d'atome (idempotence).
	var ids := {}
	for a in atoms:
		ids[str(a.get("event_id", ""))] = true
	_check(ids.size() == atoms.size(), "event_id uniques")

	_db.delete_game(gid_a)
	_check(CarnetStore.game_count(pid) == 1, "suppression A purge ses atomes, B reste")
	_db.delete_game(gid_b)
	CarnetProfiles.reset()

	if _failures == 0:
		print("ALL CARNET DATASET TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET DATASET TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _play(uci_list: Array) -> ChessGame:
	var game := ChessGame.new()
	game.load_fen(ChessGame.INITIAL_FEN)
	for uci in uci_list:
		var move = game.find_move(str(uci))
		if move == null:
			break
		game.make_move(move)
	return game

func _to_pgn(game: ChessGame) -> String:
	game.pgn_headers["White"] = PSEUDO
	game.pgn_headers["Black"] = "Adversaire"
	game.pgn_headers["Date"] = "2026.08.30"
	game.pgn_headers["Result"] = "1-0"
	return game.export_pgn()

func _analysis(game: ChessGame, blunder_ply: int) -> Dictionary:
	var evals: Array = []
	var opening_plies := 4
	for i in range(game.move_history.size()):
		var m = game.move_history[i]
		var is_blunder := i == blunder_ply
		evals.append({
			"ply": i,
			"is_white": i % 2 == 0,
			"uci": m.uci,
			"san": m.san,
			"quality": ChessMove.Quality.BLUNDER if is_blunder else ChessMove.Quality.GOOD,
			"score_cp": -260 if is_blunder else 20,
			"loss_cp": 280 if is_blunder else 5,
			"winpct_loss": 38.0 if is_blunder else 0.0,
			"is_theory": i < opening_plies,
			"best_alternative": "",
			"best_move": "",
		})
	return {
		"schema_version": 2,
		"depth": 8,
		"opening": {"eco": "C50", "out_of_book_ply": opening_plies},
		"theory_plies": opening_plies,
		"evaluations": evals,
	}
