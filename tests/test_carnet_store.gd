extends SceneTree
## tests/test_carnet_store.gd — persistance multi-profils (§4.12-4.13) + batch.
## Écrit dans `user://library/carnets/` (nettoyé en début et fin de test).

const CarnetStore = preload("res://src/carnet/CarnetStore.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")
const CarnetBatchRunner = preload("res://src/carnet/CarnetBatchRunner.gd")
const CarnetConfig = preload("res://src/carnet/CarnetConfig.gd")

var _failures := 0
var _db: Node = null
var _ran := false

func _init() -> void:
	print("--- Running CarnetStore/Profiles/Batch test ---")

## Les autoloads ne sont montés qu'après `_init` : on exécute au premier frame.
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

	_test_idempotence()
	_test_compile()
	_test_record_review()
	_test_unknown_drill_does_not_advance_streak()
	_test_atomic_write_artifacts()
	_test_corruption_preserved()
	_test_profiles_and_isolation()
	_test_sync_status_and_dedup()
	_test_chesscom_dedup_and_keys()
	_test_batch_runner()
	_test_analysis_speed_config()
	_test_profile_delete_purges_data()
	_test_malformed_sync_resilience()
	_test_mastery_wiring()

	CarnetProfiles.reset()
	if _failures == 0:
		print("ALL CARNET STORE TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET STORE TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _pid() -> String:
	return CarnetProfiles.active_id()

func _base() -> String:
	return "user://library/carnets/profiles/%s" % _pid()

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _atom(id: String, gid: String, ply: int) -> Dictionary:
	return {
		"event_id": id,
		"game_id": gid,
		"ply": ply,
		"date_iso": "2026-08-%02d" % (10 + ply),
		"couleur": "white",
		"polarite": "négatif",
		"categorie": "",
		"qualite": "gaffe",
		"perte_winpct": 35.0,
		"merite": 0.0,
		"phase": "endgame",
		"regime": "équilibré",
		"eco": "",
		"type_finale": "tours",
		"schemas": [],
		"tranche": "21-30",
		"features": {"piece_bougee": "T"},
		"position_avant": "fen_%s_%d" % [gid, ply],
		"meilleur_coup": "e2e4",
		"coup_uci": "d2d4",
		"IS": 0.0, "IM": 0.0,
	}

func _test_idempotence() -> void:
	CarnetStore.ingest_game("g1", [_atom("a1", "g1", 0), _atom("a2", "g1", 1), _atom("a3", "g1", 2)],
			{"date_iso": "2026-08-10"})
	CarnetStore.ingest_game("g2", [_atom("b1", "g2", 0), _atom("b2", "g2", 1), _atom("b3", "g2", 2)],
			{"date_iso": "2026-08-11"})
	_check(CarnetStore.game_count() == 2, "2 parties ingérées")
	_check(CarnetStore.get_atoms().size() == 6, "6 atomes persistés")

	CarnetStore.ingest_game("g1", [_atom("a1", "g1", 0), _atom("a2", "g1", 1)], {"date_iso": "2026-08-10"})
	_check(CarnetStore.get_atoms().size() == 5, "ré-ingestion idempotente (5 atomes)")

	CarnetStore.remove_game("g2")
	_check(CarnetStore.get_atoms().size() == 2, "suppression de partie → atomes retirés")
	_check(CarnetStore.game_count() == 1, "1 partie restante")

func _test_compile() -> void:
	CarnetStore.ingest_game("g1", [_atom("a1", "g1", 0), _atom("a2", "g1", 1)], {"date_iso": "2026-08-10"})
	for i in range(4):
		CarnetStore.ingest_game("g%d" % (10 + i), [
			_atom("c%d_0" % i, "g%d" % (10 + i), 0),
			_atom("c%d_1" % i, "g%d" % (10 + i), 1),
			_atom("c%d_2" % i, "g%d" % (10 + i), 2),
		], {"date_iso": "2026-08-%02d" % (12 + i)})
	var ledger := CarnetStore.compile("2026-09-10")
	_check(int(ledger["nb_atomes"]) == 14, "compile voit 14 atomes")
	_check(ledger["motifs"].size() > 0, "motifs compilés")

func _test_record_review() -> void:
	var trainer_path := _base() + "/trainer.json"
	var trainer: Dictionary = _db.load_json(trainer_path)
	trainer["drills"] = [{
		"drill_id": "dr_test",
		"event_id": "a1",
		"motif": "type_finale|tours",
		"polarite": "négatif",
		"game_id": "g1",
		"position": "fen_g1_0",
		"type": "trouve_le_coup",
		"srs": {"EF": CarnetConfig.EF_INIT, "intervalle": 0, "repetitions": 0, "lapses": 0, "echeance": ""},
		"derniere_note": -1,
		"reussites": 0,
		"maitrise": false,
	}]
	_db.save_json_atomic(trainer_path, trainer)

	var updated := CarnetStore.record_review("dr_test", 5, "2026-09-10")
	_check(not updated.is_empty(), "drill retrouvé et mis à jour")
	_check(int(updated.get("srs", {}).get("repetitions", 0)) == 1, "répétition = 1 après note 5")
	_check(str(updated.get("srs", {}).get("echeance", "")) == "2026-09-11", "échéance SM-2 enregistrée")
	var state := CarnetStore.get_trainer_state()
	_check(int(state.get("serie", 0)) == 1, "série mise à jour à 1")

func _test_unknown_drill_does_not_advance_streak() -> void:
	var before := int(CarnetStore.get_trainer_state().get("serie", 0))
	var result := CarnetStore.record_review("dr_inexistant", 5, "2026-09-11")
	var after := int(CarnetStore.get_trainer_state().get("serie", 0))
	_check(result.is_empty(), "drill inconnu → aucun résultat")
	_check(after == before, "drill inconnu → série inchangée")

func _test_atomic_write_artifacts() -> void:
	var path := _base() + "/probe.json"
	_db.save_json_atomic(path, {"a": 1})
	_db.save_json_atomic(path, {"a": 2})
	_check(FileAccess.file_exists(path), "fichier écrit")
	_check(not FileAccess.file_exists(path + ".tmp"), "aucun .tmp orphelin après sauvegarde")
	_check(FileAccess.file_exists(path + ".bak"), "version précédente conservée en .bak")
	_db.remove_file(path + ".bak")
	_db.remove_file(path)

func _test_corruption_preserved() -> void:
	var path := _base() + "/probe.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ ceci n'est pas du JSON")
	f = null
	var loaded: Dictionary = _db.load_json(path)
	_check(loaded.is_empty(), "json corrompu → dictionnaire vide renvoyé")
	var da := DirAccess.open(_base())
	var preserved := false
	if da != null:
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if name.begins_with("probe.json.corrupt_"):
				preserved = true
				da.remove(name)
			name = da.get_next()
		da.list_dir_end()
	_check(preserved, "fichier corrompu préservé (.corrupt_*)")

func _test_profiles_and_isolation() -> void:
	var pid1 := _pid()
	var before_pid1 := CarnetStore.get_atoms(pid1).size()
	var pid2 := CarnetProfiles.create("Lucas", "local", ["lucas"])
	CarnetStore.ingest_game("gL", [_atom("L1", "gL", 0)], {"date_iso": "2026-08-15"}, pid2)
	_check(CarnetStore.get_atoms(pid2).size() == 1, "atomes isolés dans le profil Lucas")
	_check(CarnetStore.get_atoms(pid1).size() == before_pid1, "aucune fuite d'atomes vers le profil Moi")
	_check(CarnetProfiles.find_by_player_key("Lucas").get("id", "") == pid2, "recherche par clé joueur")
	CarnetProfiles.set_active(pid2)
	_check(CarnetProfiles.active_id() == pid2, "profil actif commuté")
	CarnetProfiles.set_active(pid1)
	_check(CarnetProfiles.active_id() == pid1, "profil actif restauré")

func _test_sync_status_and_dedup() -> void:
	var pgn := """[Event "Test"]
[White "Nicolas"]
[Black "IA"]
[Date "2026.08.20"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0"""
	var gid: String = _db.record_pgn_game(pgn, "pgn_import")
	_check(gid != "", "partie enregistrée")
	var gid2: String = _db.record_pgn_game(pgn, "pgn_import")
	_check(gid2 == gid, "réimport dédoublonné (même external_id)")

	var profile_id := CarnetProfiles.create("Nicolas", "local", ["nicolas"])
	_db.add_engine_analysis(gid, {
		"schema_version": 2, "depth": 14, "evaluations": [], "opening": {}, "theory_plies": 0,
	})
	var status := CarnetStore.sync_status(profile_id)
	_check(int(status["total"]) == 1, "1 partie rattachée au profil Nicolas")
	_check(status["pending"].size() == 1, "partie en attente (jamais atomisée)")
	_check(str(status["pending"][0].get("reason", "")) == "never_atomized", "raison = never_atomized")

	CarnetStore.ingest_game(gid, [_atom("n1", gid, 0)], {"perspective": "white"}, profile_id)
	status = CarnetStore.sync_status(profile_id)
	_check(status["known"].size() == 1, "partie connue après ingestion")
	_check(str(status["known"][0].get("reason", "")) == "up_to_date", "raison = up_to_date")
	_check(status["to_process"].is_empty(), "aucune partie restante à traiter")
	_db.delete_game(gid)
	_check(CarnetStore.game_count(profile_id) == 0, "suppression de partie → atomes purgés du carnet")
	_check(int(CarnetStore.sync_status(profile_id)["total"]) == 0, "partie supprimée absente du sync")

func _test_chesscom_dedup_and_keys() -> void:
	var pgn := """[Event "CC"]
[White "Nicolas"]
[Black "Rival"]
[Date "2026.08.22"]
[Result "0-1"]

1. e4 c5 2. Nf3 d6 1-0"""
	var info := {
		"pgn": pgn, "white_user": "Nicolas", "black_user": "Rival",
		"white_rating": 1500, "black_rating": 1600, "time_class": "rapid",
		"user_result": "win", "url": "https://chess.com/game/123", "account": "Nicolas",
	}
	var g1: String = _db.record_chesscom_game(info)
	var g2: String = _db.record_chesscom_game(info)
	_check(g1 != "" and g1 == g2, "Chess.com dédoublonné par URL")
	var data: Dictionary = _db.get_game(g1)
	var keys: Array = data.get("player_keys", [])
	_check(keys.has("nicolas"), "clé joueur du compte Chess.com présente")
	_db.delete_game(g1)

func _test_batch_runner() -> void:
	var pgn := """[Event "Batch"]
[White "BatchPlayer"]
[Black "Adversaire"]
[Date "2026.08.21"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 1-0"""
	var gid: String = _db.record_pgn_game(pgn, "pgn_import")
	var profile_id := CarnetProfiles.create("BatchPlayer", "local", ["batchplayer"])

	var runner := CarnetBatchRunner.new()
	runner.configure(profile_id, [gid])
	runner.analyzer = func(_game: Dictionary) -> Dictionary:
		return {
			"schema_version": 2, "depth": 8, "opening": {"eco": "C20", "out_of_book_ply": 4}, "theory_plies": 4,
			"evaluations": [
				{"ply": 0, "is_white": true, "uci": "e2e4", "san": "e4", "quality": 1, "score_cp": 20, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": true, "best_alternative": "", "best_move": ""},
				{"ply": 1, "is_white": false, "uci": "e7e5", "san": "e5", "quality": 1, "score_cp": 20, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": true, "best_alternative": "", "best_move": ""},
				{"ply": 2, "is_white": true, "uci": "f1c4", "san": "Bc4", "quality": 1, "score_cp": 25, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
				{"ply": 3, "is_white": false, "uci": "b8c6", "san": "Nc6", "quality": 1, "score_cp": 25, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
				{"ply": 4, "is_white": true, "uci": "d1h5", "san": "Qh5", "quality": 1, "score_cp": 30, "loss_cp": 0, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
				{"ply": 5, "is_white": false, "uci": "g8f6", "san": "Nf6", "quality": 1, "score_cp": 30, "loss_cp": 5, "winpct_loss": 0.0, "is_theory": false, "best_alternative": "", "best_move": ""},
			],
		}
	runner.run()

	_check(runner.state == "done", "batch terminé")
	_check(runner.processed == 1 and runner.failed == 0, "1 partie traitée, 0 échec")
	var game: Dictionary = _db.get_game(gid)
	_check(str(game.get("analysis_status", "")) == "done", "analyse enregistrée par le batch")
	var status := CarnetStore.sync_status(profile_id)
	_check(status["known"].size() == 1, "partie synchronisée après batch")
	_db.delete_game(gid)
	_check(CarnetStore.game_count(profile_id) == 0, "atomes du batch purgés à la suppression")

	var runner2 := CarnetBatchRunner.new()
	runner2.profile_id = profile_id
	runner2.queue = ["ghost"]
	runner2.cursor = 0
	runner2.state = "running"
	runner2.save_job()
	var reloaded := CarnetBatchRunner.load_job(profile_id)
	_check(int(reloaded.get("cursor", -1)) == 0, "lot reprisable rechargé")
	CarnetBatchRunner.clear_job_for(profile_id)

func _test_analysis_speed_config() -> void:
	var cfg_fast := CarnetConfig.get_analysis_speed_config(CarnetConfig.ANALYSIS_SPEED_FAST)
	_check(int(cfg_fast.get("depth", 0)) == 8, "vitesse rapide: profondeur 8")
	_check(is_equal_approx(float(cfg_fast.get("dynamic_base", 0.0)), 0.05), "vitesse rapide: base 0.05s")
	_check(is_equal_approx(float(cfg_fast.get("dynamic_max", 0.0)), 0.20), "vitesse rapide: max 0.20s")

	var cfg_std := CarnetConfig.get_analysis_speed_config(CarnetConfig.ANALYSIS_SPEED_BALANCED)
	_check(int(cfg_std.get("depth", 0)) == 12, "vitesse standard: profondeur 12")
	_check(is_equal_approx(float(cfg_std.get("dynamic_base", 0.0)), 0.10), "vitesse standard: base 0.10s")
	_check(is_equal_approx(float(cfg_std.get("dynamic_max", 0.0)), 0.40), "vitesse standard: max 0.40s")

	var cfg_deep := CarnetConfig.get_analysis_speed_config(CarnetConfig.ANALYSIS_SPEED_DEEP)
	_check(int(cfg_deep.get("depth", 0)) == 16, "vitesse approfondie: profondeur 16")
	_check(is_equal_approx(float(cfg_deep.get("dynamic_base", 0.0)), 0.20), "vitesse approfondie: base 0.20s")
	_check(is_equal_approx(float(cfg_deep.get("dynamic_max", 0.0)), 0.80), "vitesse approfondie: max 0.80s")

func _test_profile_delete_purges_data() -> void:
	var pid := CarnetProfiles.create("Ephémère", "local", ["ephemere"])
	CarnetStore.ingest_game("gE", [_atom("e1", "gE", 0)], {"date_iso": "2026-08-10"}, pid)
	var dir := "user://library/carnets/profiles/%s" % pid
	_check(DirAccess.dir_exists_absolute(dir), "dossier du profil créé sur disque")
	_check(CarnetStore.get_atoms(pid).size() == 1, "atomes présents avant suppression")

	# Profil par défaut : protégé, le dossier ne doit jamais être purgé.
	CarnetProfiles.delete(CarnetProfiles.DEFAULT_PROFILE_ID)
	_check(not CarnetProfiles.get_profile(CarnetProfiles.DEFAULT_PROFILE_ID).is_empty(),
			"profil par défaut non supprimable")

	# Identifiants invalides (traversal) : ignorés sans toucher au disque.
	CarnetProfiles.delete("../evil")
	_check(not CarnetProfiles.get_profile(pid).is_empty(), "identifiant invalide ignoré")

	CarnetProfiles.delete(pid)
	_check(CarnetProfiles.get_profile(pid).is_empty(), "profil retiré de l'index")
	_check(not DirAccess.dir_exists_absolute(dir), "dossier de données du profil purgé")
	_check(CarnetStore.get_atoms(pid).is_empty(), "atomes purgés avec le profil")

func _test_malformed_sync_resilience() -> void:
	var path := _base() + "/sync.json"
	_db.save_json_atomic(path, {"entries": {
		"good": {"date_iso": "2026-08-10"},
		"scalar": 42,
		"array": [],
		"null": null,
	}})
	var sync := CarnetStore._load_sync(_pid())
	_check(sync["entries"].has("good"), "entrée valide conservée")
	_check(not sync["entries"].has("scalar"), "entrée scalaire écartée")
	_check(not sync["entries"].has("array"), "entrée tableau écartée")
	_check(not sync["entries"].has("null"), "entrée nulle écartée")
	# Les parcours d'entrées (recent/dernier) ne doivent plus planter.
	var plan := CarnetStore.refresh_plan("2026-09-10")
	_check(plan.has("plan"), "refresh_plan survit à un sync.json malformé")

func _mastery_atom(id: String, gid: String, ply: int, date_iso: String, type_finale: String) -> Dictionary:
	# Atome « propre » : un seul motif (type_finale) pour éviter que la non-redondance
	# ne le rétrograde en motif « général » à cause de champs partagés.
	var a := _atom(id, gid, ply)
	a["date_iso"] = date_iso
	a["type_finale"] = type_finale
	a["phase"] = ""
	a["regime"] = ""
	a["features"] = {}
	a["eco"] = ""
	a["tranche"] = ""
	a["schemas"] = []
	a["qualite"] = ""
	return a

## Câblage complet de la maîtrise (§4.11 D) : seuil de réussites, exclusion du plan,
## et réactivation si le motif réapparaît dans la fenêtre récente.
func _test_mastery_wiring() -> void:
	CarnetProfiles.reset()
	var pid := CarnetProfiles.create("Maîtrise", "local", ["maitrise"])

	# Motif cible : 3 atomes négatifs « type_finale|tours » sur la partie gA (ancienne).
	CarnetStore.ingest_game("gA", [
		_mastery_atom("a0", "gA", 0, "2026-01-01", "tours"),
		_mastery_atom("a1", "gA", 1, "2026-01-01", "tours"),
		_mastery_atom("a2", "gA", 2, "2026-01-01", "tours"),
	], {"date_iso": "2026-01-01"}, pid)
	# 4 autres parties anciennes → G ≥ 5 (condition d'établissement du motif).
	for i in range(4):
		var gid := "gOld%d" % i
		CarnetStore.ingest_game(gid,
				[_mastery_atom("o%d" % i, gid, 0, "2026-01-02", "aucune")],
				{"date_iso": "2026-01-02"}, pid)
	# 11 parties récentes → gA sort de la fenêtre MASTERY_WINDOW (10).
	for i in range(11):
		var gid := "gNew%d" % i
		var d := "2026-06-%02d" % (1 + i)
		CarnetStore.ingest_game(gid, [_mastery_atom("n%d" % i, gid, 0, d, "aucune")],
				{"date_iso": d}, pid)

	# 1re compilation : le drill du motif cible est généré.
	CarnetStore.refresh_plan("2026-09-01", {}, pid)
	var target_id := ""
	for drill in CarnetStore.get_trainer_state(pid).get("drills", []):
		if drill is Dictionary and str(drill.get("motif", "")) == "type_finale|tours":
			target_id = str(drill.get("drill_id", ""))
			break
	_check(target_id != "", "drill du motif cible généré")

	# 3 réussites → seuil MASTERY_DRILLS atteint.
	for k in range(3):
		CarnetStore.record_review(target_id, 5, "2026-09-0%d" % (2 + k), pid)

	# 2e compilation : le motif est déclaré maîtrisé et sort du plan.
	var result := CarnetStore.refresh_plan("2026-09-05", {}, pid)
	var target_mastered := false
	var mastered_total := 0
	for drill in CarnetStore.get_trainer_state(pid).get("drills", []):
		if not (drill is Dictionary):
			continue
		if bool(drill.get("maitrise", false)):
			mastered_total += 1
		if str(drill.get("motif", "")) == "type_finale|tours":
			target_mastered = bool(drill.get("maitrise", false))
	_check(target_mastered, "motif type_finale|tours marqué maîtrisé après 3 réussites")
	_check(mastered_total >= 1, "au moins un drill maîtrisé persisté")
	var in_plan := false
	for drill in (result.get("plan", {}) as Dictionary).get("drills", []):
		if drill is Dictionary and str(drill.get("motif", "")) == "type_finale|tours":
			in_plan = true
	_check(not in_plan, "drill maîtrisé exclu du plan du jour")

	# Réactivation : le motif réapparaît dans une partie récente → maîtrise levée.
	CarnetStore.ingest_game("gRecent",
			[_mastery_atom("r0", "gRecent", 0, "2026-12-01", "tours")],
			{"date_iso": "2026-12-01"}, pid)
	CarnetStore.refresh_plan("2026-12-02", {}, pid)
	var reactivated := false
	for drill in CarnetStore.get_trainer_state(pid).get("drills", []):
		if drill is Dictionary and str(drill.get("motif", "")) == "type_finale|tours":
			reactivated = not bool(drill.get("maitrise", false))
	_check(reactivated, "motif réapparu récemment → maîtrise levée (retravaillable)")
	CarnetProfiles.reset()

