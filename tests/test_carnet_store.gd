extends SceneTree
## tests/test_carnet_store.gd — persistance idempotente de LeCarnet (§4.12-4.13).
## Écrit dans `user://library/carnet/` (nettoyé en début et fin de test).

const CarnetStore = preload("res://src/carnet/CarnetStore.gd")
const CarnetConfig = preload("res://src/carnet/CarnetConfig.gd")

var _failures := 0
var _db: Node = null
var _ran := false
var _exit_code := 0

func _init() -> void:
	print("--- Running CarnetStore (persistance) test ---")

## Les autoloads ne sont montés qu'après `_init` : on exécute au premier frame.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_db = root.get_node_or_null("DatabaseManager")
	if _db == null:
		printerr("DatabaseManager autoload introuvable")
		_exit_code = 1
		quit(_exit_code)
		return true
	_db.delete_carnet()

	_test_idempotence()
	_test_compile()
	_test_record_review()
	_test_unknown_drill_does_not_advance_streak()
	_test_atomic_write_artifacts()
	_test_corruption_preserved()

	_db.delete_carnet()
	_cleanup_carnet_artifacts()
	if _failures == 0:
		print("ALL CARNET STORE TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET STORE TESTS FAILED: %d" % _failures)
		_exit_code = 0 if _failures == 0 else 1
	quit(_exit_code)
	return true

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

	# Ré-ingestion de g1 : remplacement, pas d'accumulation.
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
	_check(int(ledger["nb_parties"]) == 5, "compile voit 5 parties")
	_check(int(ledger["nb_atomes"]) == 14, "compile voit 14 atomes")
	_check(ledger["motifs"].size() > 0, "motifs compilés")

func _test_record_review() -> void:
	# Injecte un drill persisté puis vérifie la mise à jour SM-2 + série.
	var carnet: Dictionary = _db.get_carnet()
	var trainer: Dictionary = carnet.get("trainer", {})
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
	carnet["trainer"] = trainer
	_db.save_carnet(carnet)

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
	# Deux sauvegardes successives doivent produire un .bak et ne laisser aucun .tmp.
	_db.save_carnet(_db.get_carnet())
	_db.save_carnet(_db.get_carnet())
	_check(FileAccess.file_exists("user://library/carnet/carnet.json"), "carnet.json écrit")
	_check(not FileAccess.file_exists("user://library/carnet/carnet.json.tmp"),
			"aucun .tmp orphelin après sauvegarde")
	_check(FileAccess.file_exists("user://library/carnet/carnet.json.bak"),
			"version précédente conservée en .bak")

func _test_corruption_preserved() -> void:
	var path := "user://library/carnet/carnet.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ ceci n'est pas du JSON")
	f = null
	var loaded: Dictionary = _db.get_carnet()
	_check(loaded.get("games", {}).is_empty(), "carnet corrompu → carnet vide renvoyé")
	var da := DirAccess.open("user://library/carnet")
	var preserved := false
	if da != null:
		da.list_dir_begin()
		var name := da.get_next()
		while name != "":
			if name.begins_with("carnet.json.corrupt_"):
				preserved = true
			name = da.get_next()
		da.list_dir_end()
	_check(preserved, "fichier corrompu préservé (carnet.json.corrupt_*)")

func _cleanup_carnet_artifacts() -> void:
	var da := DirAccess.open("user://library/carnet")
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name.begins_with("carnet.json.corrupt_") or name == "carnet.json.bak" or name == "carnet.json.tmp":
			da.remove(name)
		name = da.get_next()
	da.list_dir_end()
