extends SceneTree
## tests/test_carnet_trainer.gd — LeCarnet Étage 3 (§4.8 → §4.11).
## Vérifie SM-2, génération des drills, contraintes de LePlan, Élo-skill,
## écart théorie↔pratique, maîtrise, plateau et série/joker.

const CarnetTrainer = preload("res://src/carnet/CarnetTrainer.gd")
const CarnetConfig = preload("res://src/carnet/CarnetConfig.gd")

var _failures := 0

func _init() -> void:
	print("--- Running CarnetTrainer (Étage 3) test ---")
	_test_sm2()
	_test_generate_drills()
	_test_plan_constraints()
	_test_skill_and_ecart()
	_test_mastery_plateau_streak()
	if _failures == 0:
		print("ALL CARNET TRAINER TESTS PASSED SUCCESSFULLY!")
		quit(0)
	else:
		printerr("CARNET TRAINER TESTS FAILED: %d" % _failures)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _new_drill() -> Dictionary:
	return {
		"drill_id": "d1",
		"srs": {"EF": CarnetConfig.EF_INIT, "intervalle": 0, "repetitions": 0, "lapses": 0, "echeance": ""},
		"derniere_note": -1,
		"reussites": 0,
	}

func _test_sm2() -> void:
	var d := _new_drill()
	CarnetTrainer.update_srs(d, 5, "2026-09-10")
	_check(int(d["srs"]["intervalle"]) == 1, "note 5 → intervalle 1 jour")
	_check(int(d["srs"]["repetitions"]) == 1, "note 5 → répétition 1")
	_check(absf(float(d["srs"]["EF"]) - 2.6) < 0.001, "note 5 → EF 2.6")
	_check(str(d["srs"]["echeance"]) == "2026-09-11", "échéance = aujourd'hui + 1")

	CarnetTrainer.update_srs(d, 4, "2026-09-11")
	_check(int(d["srs"]["intervalle"]) == 6, "note 4 (2e) → intervalle 6 jours")
	_check(str(d["srs"]["echeance"]) == "2026-09-17", "échéance + 6")

	CarnetTrainer.update_srs(d, 4, "2026-09-17")
	_check(int(d["srs"]["intervalle"]) == 16, "3e réussite → round(6 × EF) = 16")
	_check(int(d["srs"]["repetitions"]) == 3, "répétitions = 3")
	_check(int(d["reussites"]) == 3, "compteur réussites = 3")

	CarnetTrainer.update_srs(d, 1, "2026-09-20")
	_check(int(d["srs"]["intervalle"]) == 1, "échec → intervalle 1")
	_check(int(d["srs"]["repetitions"]) == 0, "échec → répétitions 0")
	_check(int(d["srs"]["lapses"]) == 1, "échec → lapses 1")
	_check(absf(float(d["srs"]["EF"]) - 2.4) < 0.001, "échec → EF − 0,2")

func _drill_atom(id: String, gid: String, pos: String, best: String, played: String,
		polarite: String, opts: Dictionary = {}) -> Dictionary:
	return {
		"event_id": id,
		"game_id": gid,
		"date_iso": str(opts.get("date", "2026-08-20")),
		"couleur": "white",
		"polarite": polarite,
		"perte_winpct": float(opts.get("perte", 30.0)),
		"merite": float(opts.get("merite", 0.0)),
		"IS": float(opts.get("IS", 0.0)),
		"IM": float(opts.get("IM", 0.0)),
		"mystere": bool(opts.get("mystere", false)),
		"surprise": bool(opts.get("surprise", false)),
		"position_avant": pos,
		"meilleur_coup": best,
		"coup_uci": played,
		"pv": [],
		"marqueurs": opts.get("marqueurs", {}),
		"indices": opts.get("indices", {}),
		"features": {"piece_bougee": "D"},
	}

func _motif(famille: String, cle: String, score: float, ids: Array, polarite: String = "négatif", jeux: Array = []) -> Dictionary:
	return {
		"famille": famille,
		"cle": cle,
		"polarite": polarite,
		"score": score,
		"n": ids.size(),
		"etabli": true,
		"general": false,
		"atomes": ids,
		"jeux": jeux,
	}

func _test_generate_drills() -> void:
	var atoms: Array = []
	var ids: Array = []
	for i in range(5):
		var id := "a%d" % i
		ids.append(id)
		atoms.append(_drill_atom(id, "g%d" % i, "fen_pos_%d" % i, "e2e4", "d2d4", "négatif"))
	var faiblesses := [_motif("type_finale", "tours", 60.0, ids)]
	var drills := CarnetTrainer.generate_drills(atoms, faiblesses, [], [])
	_check(drills.size() == 4, "au plus DRILLS_PER_MOTIF = 4 drills par motif")
	var positions := {}
	for dr in drills:
		positions[dr["position"]] = true
	_check(positions.size() == drills.size(), "un drill par position distincte (dédoublonnage)")
	_check(str(drills[0]["type"]) == "choix_binaire", "type choix_binaire si meilleur coup non forcé")

	var patoms: Array = [
		_drill_atom("p0", "g0", "fen_p0", "d5e6", "d5e6", "positif", {"merite": 0.9, "IS": 70.0}),
		_drill_atom("p1", "g1", "fen_p1", "d5e6", "d5e6", "positif", {"merite": 0.9, "mystere": true, "IM": 70.0}),
	]
	var pos_motifs := [_motif("categorie", "brillant", 50.0, ["p0"], "positif")]
	var cur_motifs := [_motif("categorie", "surprise", 40.0, ["p1"], "curieux")]
	var pdrills := CarnetTrainer.generate_drills(patoms, [], pos_motifs, cur_motifs)
	_check(pdrills.size() >= 1, "drills positifs générés")
	_check(str(pdrills[0]["type"]) == "trouve_la_brillance", "type trouve_la_brillance")

func _mk_drill(id: String, motif: String, game: String, polarite: String, rep: int, echeance: String, score: float, gravite: float) -> Dictionary:
	return {
		"drill_id": id,
		"event_id": id + "_ev",
		"motif": motif,
		"polarite": polarite,
		"game_id": game,
		"motif_score": score,
		"gravite": gravite,
		"srs": {"EF": 2.5, "intervalle": 1, "repetitions": rep, "lapses": 0, "echeance": echeance},
		"maitrise": false,
	}

func _test_plan_constraints() -> void:
	var drills: Array = [
		_mk_drill("d1", "A", "g1", "négatif", 1, "2026-09-01", 70.0, 0.9),
		_mk_drill("d2", "A", "g2", "négatif", 1, "2026-09-02", 70.0, 0.8),
		_mk_drill("d3", "A", "g3", "négatif", 1, "2026-09-03", 70.0, 0.7),
		_mk_drill("d4", "B", "g4", "négatif", 1, "2026-09-01", 60.0, 0.6),
		_mk_drill("d5", "B", "g5", "négatif", 1, "2026-09-02", 60.0, 0.5),
		_mk_drill("d6", "P", "g6", "positif", 1, "2026-09-01", 50.0, 0.4),
		_mk_drill("d7", "P", "g7", "positif", 1, "2026-09-02", 50.0, 0.3),
	]
	var plan := CarnetTrainer.build_plan(drills, {"today_iso": "2026-09-10", "session_size": 5})
	var selected: Array = plan["drills"]
	_check(selected.size() <= 5, "taille de séance ≤ 5")
	_check(selected.size() > 0, "plan non vide")
	var per_motif := {}
	var per_game := {}
	for dr in selected:
		per_motif[dr["motif"]] = int(per_motif.get(dr["motif"], 0)) + 1
		per_game[dr["game_id"]] = int(per_game.get(dr["game_id"], 0)) + 1
	var motif_ok := true
	var game_ok := true
	for k in per_motif.keys():
		if int(per_motif[k]) > CarnetConfig.MAX_PER_MOTIF:
			motif_ok = false
	for k in per_game.keys():
		if int(per_game[k]) > 1:
			game_ok = false
	_check(motif_ok, "au plus MAX_PER_MOTIF = 2 par motif")
	_check(game_ok, "au plus 1 drill par partie")
	_check(int(plan["nb_positifs"]) <= 1, "part de positifs ≈ 20% (≤ 1 sur 5)")
	_check(not bool(plan["est_jour_repos"]), "jour non vide")

	var empty := CarnetTrainer.build_plan([], {"today_iso": "2026-09-10"})
	_check(bool(empty["est_jour_repos"]), "aucun drill → jour de repos")

func _test_skill_and_ecart() -> void:
	var state := {"skill": 50.0, "n": 0}
	CarnetTrainer.update_skill(state, 50.0, true)
	_check(float(state["skill"]) > 50.0, "réussite → compétence monte")
	CarnetTrainer.update_skill(state, 50.0, false)
	_check(float(state["skill"]) < float(50.0 + CarnetConfig.K_SKILL), "échec → compétence redescend")

	var comps: Array = [
		{"dimension": "phase", "cle": "endgame", "skill_theorie": 90.0, "skill_pratique": 40.0},
		{"dimension": "phase", "cle": "opening", "skill_theorie": 30.0, "skill_pratique": 25.0},
		{"dimension": "registre", "cle": "tactique", "skill_theorie": 80.0, "skill_pratique": 78.0},
		{"dimension": "phase", "cle": "middlegame", "skill_theorie": -1.0, "skill_pratique": 70.0},
	]
	var ecarts := CarnetTrainer.ecart_theorie_pratique(comps)
	var by_key := {}
	for e in ecarts:
		by_key["%s:%s" % [e["dimension"], e["cle"]]] = e
	_check(str(by_key["phase:endgame"]["regime"]) == "sait_mais_n_applique_pas", "régime transfert détecté")
	_check(str(by_key["phase:opening"]["regime"]) == "ne_sait_pas", "régime ne_sait_pas détecté")
	_check(str(by_key["registre:tactique"]["regime"]) == "acquis", "régime acquis détecté")
	_check(not by_key.has("phase:middlegame"), "compétence sans les deux contextes ignorée")

func _test_mastery_plateau_streak() -> void:
	var motifs: Array = [_motif("type_finale", "tours", 60.0, ["e1", "e2"], "négatif", ["old_g"])]
	var drills: Array = [{"motif": "type_finale|tours", "reussites": 3}]
	var mastered := CarnetTrainer.detect_mastery(motifs, drills, ["recent_g"])
	_check(mastered.has("type_finale|tours"), "motif acquis détecté (aucune partie récente + 3 réussites)")

	var not_mastered := CarnetTrainer.detect_mastery(motifs, drills, ["old_g"])
	_check(not_mastered.is_empty(), "motif réapparu → non acquis")

	_check(CarnetTrainer.detect_plateau([50, 50, 50, 50, 50, 50]), "plateau détecté (6 séances stables)")
	_check(not CarnetTrainer.detect_plateau([40, 50, 60, 70, 80, 90]), "progression → pas de plateau")

	var state := {"serie": 0, "derniere_date": "", "joker_disponible": 1}
	CarnetTrainer.update_streak(state, "2026-09-07", true)
	_check(int(state["serie"]) == 1, "série démarre à 1")
	CarnetTrainer.update_streak(state, "2026-09-08", true)
	_check(int(state["serie"]) == 2, "jour consécutif → série 2")
	CarnetTrainer.update_streak(state, "2026-09-10", true)
	_check(int(state["serie"]) == 3, "1 jour manqué couvert par joker → série 3")
	_check(int(state["joker_disponible"]) == 0, "joker consommé")
	CarnetTrainer.update_streak(state, "2026-09-12", true)
	_check(int(state["serie"]) == 1, "2e jour manqué sans joker → série repart à 1")
