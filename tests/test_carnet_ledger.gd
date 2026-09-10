extends SceneTree
## tests/test_carnet_ledger.gd — LeCarnet Étage 2 (§4.5 → §4.7).
## Vérifie score de motif, seuils d'établissement, non-redondance, forces, profil et tendance.

const CarnetLedger = preload("res://src/carnet/CarnetLedger.gd")

var _failures := 0

func _init() -> void:
	print("--- Running CarnetLedger (Étage 2) test ---")
	_test_negative_motif_and_redundancy()
	_test_forces()
	_test_emergents_and_low_sample()
	_test_profil_and_competences()
	_test_tendance()
	if _failures == 0:
		print("ALL CARNET LEDGER TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("CARNET LEDGER TESTS FAILED: %d" % _failures)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _atom(id: String, gid: String, date: String, polarite: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"event_id": id,
		"game_id": gid,
		"ply": int(opts.get("ply", 30)),
		"date_iso": date,
		"couleur": str(opts.get("couleur", "white")),
		"polarite": polarite,
		"categorie": str(opts.get("categorie", "")),
		"qualite": str(opts.get("qualite", "gaffe")),
		"perte_winpct": float(opts.get("perte", 30.0)),
		"merite": float(opts.get("merite", 0.0)),
		"phase": str(opts.get("phase", "endgame")),
		"regime": str(opts.get("regime", "équilibré")),
		"eco": str(opts.get("eco", "")),
		"type_finale": str(opts.get("type_finale", "aucune")),
		"schemas": opts.get("schemas", []),
		"tranche": str(opts.get("tranche", "31-40")),
		"features": {"piece_bougee": str(opts.get("piece", "D"))},
		"contexte": str(opts.get("contexte", "pratique")),
		"IS": float(opts.get("IS", 0.0)),
		"IM": float(opts.get("IM", 0.0)),
		"surprise": bool(opts.get("surprise", false)),
		"mystere": bool(opts.get("mystere", false)),
	}

func _find(motifs: Array, famille: String, cle: String) -> Dictionary:
	for m in motifs:
		if m["famille"] == famille and m["cle"] == cle:
			return m
	return {}

func _test_negative_motif_and_redundancy() -> void:
	var atoms: Array = []
	for i in range(9):
		var opts := {"type_finale": "tours" if i < 6 else "aucune", "ply": 30}
		atoms.append(_atom("e%d" % i, "g%d" % i, "2026-08-20", "négatif", opts))
	var ledger := CarnetLedger.compile(atoms, {"nb_parties": 25, "today_iso": "2026-09-10"})
	var phase := _find(ledger["motifs"], "phase", "endgame")
	var tours := _find(ledger["motifs"], "type_finale", "tours")
	_check(int(phase.get("n", 0)) == 9, "(phase,endgame) n = 9")
	_check(bool(phase.get("etabli", false)), "(phase,endgame) établi")
	_check(bool(phase.get("general", false)), "(phase,endgame) rétrogradé par non-redondance")
	var score: float = float(phase.get("score", 0.0))
	_check(score > 45.0 and score < 57.0, "score ≈ 51 (calcul §4.5) — obtenu %.1f" % score)
	_check(int(tours.get("n", 0)) == 6, "(type_finale,tours) n = 6")
	_check(not bool(tours.get("general", false)), "(type_finale,tours) est le motif spécifique retenu")
	var in_faiblesses := false
	for m in ledger["faiblesses"]:
		if m["famille"] == "type_finale" and m["cle"] == "tours":
			in_faiblesses = true
	_check(in_faiblesses, "(type_finale,tours) présent dans faiblesses")

func _test_forces() -> void:
	var atoms: Array = []
	for i in range(4):
		atoms.append(_atom("f%d" % i, "g%d" % i, "2026-08-25", "positif",
				{"categorie": "brillant", "merite": 0.9, "schemas": ["sacrifice"]}))
	var ledger := CarnetLedger.compile(atoms, {"nb_parties": 10, "today_iso": "2026-09-10"})
	_check(not ledger["forces"].is_empty(), "force établie détectée")
	var br = _find(ledger["forces"], "categorie", "brillant")
	_check(int(br.get("n", 0)) == 4, "force (categorie,brillant) n = 4")
	_check(float(br.get("score", 0.0)) > 0.0, "force score > 0")

func _test_emergents_and_low_sample() -> void:
	var atoms: Array = [
		_atom("x0", "g1", "2026-08-01", "négatif", {"type_finale": "pions"}),
		_atom("x1", "g2", "2026-08-02", "négatif", {"type_finale": "pions"}),
	]
	var ledger := CarnetLedger.compile(atoms, {"nb_parties": 2, "today_iso": "2026-09-10"})
	var pions := _find(ledger["motifs"], "type_finale", "pions")
	_check(int(pions.get("n", 0)) == 2, "motif émergent n = 2")
	_check(not bool(pions.get("etabli", false)), "n = 2 non établi")
	var found := false
	for m in ledger["emergeants"]:
		if m["famille"] == "type_finale" and m["cle"] == "pions":
			found = true
	_check(found, "motif n = 2 listé dans émergents")
	_check(ledger["faiblesses"].is_empty(), "moins de 5 parties → aucune faiblesse affirmée")

func _test_profil_and_competences() -> void:
	var atoms: Array = []
	for i in range(4):
		atoms.append(_atom("c%d" % i, "g%d" % i, "2026-08-20", "négatif", {"phase": "endgame", "perte": 20.0}))
	for i in range(4):
		atoms.append(_atom("d%d" % i, "h%d" % i, "2026-08-20", "négatif", {"phase": "opening", "perte": 5.0}))
	var led := CarnetLedger.compile(atoms, {"nb_parties": 12, "today_iso": "2026-09-10"})
	_check(not led["competences"].is_empty(), "compétences calculées")
	var radar: Dictionary = led["profil"]["radar"]
	var has_phase := false
	for k in radar.keys():
		if str(k).begins_with("phase:"):
			has_phase = true
	_check(has_phase, "radar contient des dimensions phase")
	var indice: float = float(led["profil"]["indice_progression"])
	_check(indice < 100.0 and indice >= 0.0, "indice de progression < 100 avec faiblesses")

	# Écart théorie ↔ pratique sur la même dimension.
	var mixed: Array = [
		_atom("t0", "g1", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "theorie", "perte": 0.0}),
		_atom("t1", "g1", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "theorie", "perte": 0.0}),
		_atom("t2", "g1", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "theorie", "perte": 0.0}),
		_atom("p0", "g2", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "pratique", "perte": 40.0}),
		_atom("p1", "g2", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "pratique", "perte": 40.0}),
		_atom("p2", "g2", "2026-08-20", "négatif", {"phase": "endgame", "contexte": "pratique", "perte": 40.0}),
	]
	var led2 := CarnetLedger.compile(mixed, {"nb_parties": 6, "today_iso": "2026-09-10"})
	var comp := {}
	for c in led2["competences"]:
		if c["dimension"] == "phase" and c["cle"] == "endgame":
			comp = c
	_check(not comp.is_empty(), "compétence phase/endgame présente")
	_check(float(comp.get("skill_theorie", 0.0)) > float(comp.get("skill_pratique", 0.0)),
			"théorie > pratique (écart positif)")
	_check(absf(float(comp.get("ecart", 0.0))) > 8.0, "écart théorie ↔ pratique > 8")

func _test_tendance() -> void:
	var atoms: Array = []
	for i in range(3):
		atoms.append(_atom("old%d" % i, "old_g%d" % i, "2026-06-01", "négatif"))
	for i in range(3):
		atoms.append(_atom("new%d" % i, "new_g%d" % i, "2026-09-01", "négatif"))
	var led := CarnetLedger.compile(atoms, {
		"nb_parties": 6, "today_iso": "2026-09-10",
		"recent_game_ids": ["new_g0", "new_g1", "new_g2"],
	})
	_check(led["tendance_globale"] is String, "tendance calculée sans erreur")
	var tours := _find(led["motifs"], "qualite", "gaffe")
	_check(str(tours.get("tendance", "")) == "stable", "tendance par motif via la fenêtre globale (recent = old)")
