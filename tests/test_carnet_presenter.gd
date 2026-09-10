extends SceneTree
## tests/test_carnet_presenter.gd — Couche T1 (CarnetPresenter), sans scène/moteur.

const CarnetPresenter = preload("res://src/ui/carnet/CarnetPresenter.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")
const CarnetStore = preload("res://src/carnet/CarnetStore.gd")

var _failures := 0
var _db: Node = null
var _ran := false
var _finished := {}

func _init() -> void:
	print("--- Running CarnetPresenter (T1) test ---")

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

	var presenter: CarnetPresenter = CarnetPresenter.new()
	_test_profiles(presenter)
	_test_sync_and_carnet(presenter)
	_test_session(presenter)
	_test_reveal(presenter)
	_test_batch(presenter)

	CarnetProfiles.reset()
	if _failures == 0:
		print("ALL CARNET PRESENTER TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET PRESENTER TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _trainer_path(pid: String) -> String:
	return "user://library/carnets/profiles/%s/trainer.json" % pid

func _test_profiles(presenter: CarnetPresenter) -> void:
	presenter.refresh_profiles()
	_check(presenter.profiles.size() >= 1, "profil par défaut présent")
	_check(presenter.profile_id != "", "profil actif défini")

	var id := presenter.create_profile("Alice", "local", ["alice"])
	_check(presenter.profile_id == id, "profil créé et actif")
	_check(presenter.active_profile_name() == "Alice", "nom du profil actif")
	presenter.select_profile(CarnetProfiles.active_id())
	_check(presenter.active_profile_name() == "Alice", "sélection stable")

func _test_sync_and_carnet(presenter: CarnetPresenter) -> void:
	var status := presenter.refresh_sync()
	_check(int(status.get("total", -1)) == 0, "sync vide au départ")
	_check(presenter.sync_label().contains("à jour"), "libellé sync sans delta")

	var ledger := presenter.refresh_carnet("2026-09-10")
	_check(ledger.has("motifs"), "carnet compilé")
	_check(presenter.ledger.has("profil"), "profil de compétences exposé")

func _test_session(presenter: CarnetPresenter) -> void:
	var drills: Array = [
		{"drill_id": "d1", "reponse_uci": "e2e4", "type": "trouve_le_coup", "motif": "type_finale|tours", "polarite": "négatif", "position": "p1"},
		{"drill_id": "d2", "reponse_uci": "d2d4", "type": "choix_binaire", "motif": "phase|endgame", "polarite": "négatif", "position": "p2"},
	]
	# Persiste les drills comme le ferait refresh_plan (nécessaire à record_review).
	var trainer: Dictionary = _db.load_json(_trainer_path(presenter.profile_id))
	trainer["drills"] = drills
	_db.save_json_atomic(_trainer_path(presenter.profile_id), trainer)

	presenter.session_finished.connect(func(summary): _finished = summary)
	presenter.start_session(drills)
	_check(presenter.session_size() == 2, "séance de 2 drills")
	_check(str(presenter.current_drill().get("drill_id", "")) == "d1", "premier drill courant")

	var wrong := presenter.answer("a2a3")
	_check(not bool(wrong.get("correct", true)), "mauvais coup détecté")
	_check(bool(wrong.get("revealed", false)), "réponse révélée après échec")
	var again := presenter.answer("a2a3")
	_check(int(presenter.session_summary().get("wrong", 0)) == 1, "double réponse non recomptée")
	_check(bool(again.get("revealed", false)), "réponse figée après coup")
	_check(presenter.grade(1), "notation acceptée après réponse")

	_check(str(presenter.current_drill().get("drill_id", "")) == "d2", "passage au 2e drill")
	var right := presenter.answer("d2d4")
	_check(bool(right.get("correct", false)), "bon coup détecté")
	_check(presenter.grade(4), "notation du 2e drill")
	_check(presenter.is_session_done(), "séance terminée")

	var summary := presenter.session_summary()
	_check(int(summary.get("total", 0)) == 2, "résumé : 2 drills")
	_check(int(summary.get("correct", 0)) == 1, "résumé : 1 correct")
	_check(int(summary.get("wrong", 0)) == 1, "résumé : 1 erreur")
	_check(not _finished.is_empty(), "signal session_finished émis")

	var state := CarnetStore.get_trainer_state(presenter.profile_id)
	var by_id := {}
	for d in state.get("drills", []):
		by_id[str(d.get("drill_id", ""))] = d
	_check(int(by_id["d1"].get("srs", {}).get("repetitions", -1)) == 0, "note 1 → répétitions 0 (échec)")
	_check(str(by_id["d1"].get("srs", {}).get("echeance", "")) != "", "échéance SM-2 enregistrée")
	_check(int(by_id["d2"].get("srs", {}).get("repetitions", -1)) == 1, "note 4 → répétitions 1")

func _test_reveal(presenter: CarnetPresenter) -> void:
	var drill := {
		"drill_id": "d_reveal", "reponse_uci": "e2e4", "type": "trouve_le_coup",
		"motif": "m", "polarite": "négatif",
		"position": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
	}
	var trainer: Dictionary = _db.load_json(_trainer_path(presenter.profile_id))
	trainer["drills"] = [drill]
	_db.save_json_atomic(_trainer_path(presenter.profile_id), trainer)
	presenter.start_session([drill])
	_check(presenter.drill_options(drill).size() == 1, "drill sans piège : une seule option")
	var res := presenter.reveal()
	_check(bool(res.get("revealed", false)) and bool(res.get("gave_up", false)), "révélation marquée")
	_check(presenter.grade(1), "notation possible après révélation")
	_check(presenter.is_session_done(), "séance close après révélation + note")

func _test_batch(presenter: CarnetPresenter) -> void:
	var pgn := """[Event "Present"]
[White "PresentPlayer"]
[Black "Rival"]
[Date "2026.08.23"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0"""
	var gid: String = _db.record_pgn_game(pgn, "pgn_import")
	var pid := presenter.create_profile("PresentPlayer", "local", ["presentplayer"])

	presenter.set_analyzer(func(_game: Dictionary) -> Dictionary:
		return {
			"schema_version": 2, "depth": 8, "opening": {"eco": "C20", "out_of_book_ply": 2}, "theory_plies": 2,
			"evaluations": [
				{"ply": 0, "is_white": true, "uci": "e2e4", "san": "e4", "quality": 1, "score_cp": 20, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": true, "best_alternative": "", "best_move": ""},
				{"ply": 1, "is_white": false, "uci": "e7e5", "san": "e5", "quality": 1, "score_cp": 20, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": true, "best_alternative": "", "best_move": ""},
				{"ply": 2, "is_white": true, "uci": "g1f3", "san": "Nf3", "quality": 1, "score_cp": 25, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
				{"ply": 3, "is_white": false, "uci": "b8c6", "san": "Nc6", "quality": 1, "score_cp": 25, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
			],
		})
	presenter.refresh_sync()
	_check(presenter.sync.get("to_process", []).size() == 1, "1 partie à traiter")

	presenter.start_batch([gid])
	_check(presenter.is_batching(), "lot démarré")
	var guard := 0
	while presenter.poll_batch() and guard < 10:
		guard += 1
	_check(str(presenter.batch.state) == "done", "lot terminé")
	_check(presenter.sync.get("known", []).size() == 1, "partie synchronisée après lot")
	_db.delete_game(gid)
