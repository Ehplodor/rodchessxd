extends SceneTree
## Test automatisé de l'unification Bibliothèque/Carnet, du cache et du recalcul

func _init() -> void:
	print("--- Test Unification Bibliothèque / LeCarnet & Recalcul ---")
	await create_timer(0.05).timeout

	var dm = root.get_node_or_null("DatabaseManager")
	assert(dm != null, "DatabaseManager doit être chargé en autoload")

	# Nettoyage préventif d'anciens artefacts de test
	for p in CarnetProfiles.list():
		if str(p.get("name", "")) == "JoueurTest":
			CarnetProfiles.delete(str(p.get("id", "")))
	var stale_gid = dm.find_game_by_external_id("Championnat Unification:JoueurTest:Adversaire:2026.09.12")
	if stale_gid != "":
		dm.delete_game(stale_gid)

	# 1. Créer un profil de test dédié avec une player_key
	var test_profile_id := CarnetProfiles.create("JoueurTest", "local", ["joueurtest", "alpha"])
	assert(test_profile_id != "", "Le profil doit être créé")
	print("✓ Profil créé : %s" % test_profile_id)

	# 2. Enregistrer une partie dans la Bibliothèque avec analyses complètes
	var pgn := """[Event "Championnat Unification"]
[Site "Paris"]
[Date "2026.09.12"]
[White "JoueurTest"]
[Black "Adversaire"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6 1-0"""

	var gid: String = dm.record_pgn_game(pgn, "unification_test")
	assert(gid != "", "Partie enregistrée dans la Bibliothèque")

	# Ajouter une analyse moteur Stockfish dans la Bibliothèque
	var sf_analysis := {
		"engine_name": "Stockfish 18",
		"depth": 14,
		"schema_version": 1,
		"white_accuracy": 92.0,
		"black_accuracy": 80.0,
		"evaluations": [
			{"ply": 0, "score_cp": 20, "san": "e4", "best_san": "e4", "loss_cp": 0},
			{"ply": 1, "score_cp": 25, "san": "e5", "best_san": "e5", "loss_cp": 0},
			{"ply": 2, "score_cp": -250, "san": "Nf3", "best_san": "d4", "loss_cp": 300, "winpct_loss": 35.0, "quality": ChessMove.Quality.BLUNDER, "best_alternative": "d2d4"},
			{"ply": 3, "score_cp": 280, "san": "Nc6", "best_san": "d6", "loss_cp": 400, "winpct_loss": 40.0, "quality": ChessMove.Quality.BLUNDER, "best_alternative": "d7d6"}
		],
		"opening": {"eco": "C50", "name": "Giuoco Piano", "out_of_book_ply": 1}
	}
	dm.add_engine_analysis(gid, sf_analysis)

	# Ajouter une analyse de coach IA dans la Bibliothèque
	var coach_analysis := {
		"ply_index": 3,
		"move_san": "Nc6",
		"perspective": "white",
		"response_text": "Coup imprécis adverse permettant de prendre l'avantage au centre."
	}
	dm.add_coach_analysis(gid, coach_analysis)

	# Vérifier que la Bibliothèque contient tout
	var game_in_db: Dictionary = dm.get_game(gid)
	assert(game_in_db.get("engine_analyses", []).size() >= 1, "Analyse moteur présente dans la Bibliothèque")
	assert(game_in_db.get("coach_analyses", []).size() >= 1, "Coaching IA présent dans la Bibliothèque")
	print("✓ Partie et analyses archivées dans la Bibliothèque (Source Unique de Vérité)")

	# 3. Tester le recalcul unitaire : recalculate_game
	var recalc_res := CarnetStore.recalculate_game(gid, test_profile_id)
	assert(recalc_res.get("ok") == true, "Recalcul unitaire réussi")
	assert(recalc_res.get("atoms_count", 0) >= 1, "Atomes générés par recalcul")
	assert(recalc_res.get("perspective") == "white", "Perspective JoueurTest = white détectée")
	print("✓ Recalcul unitaire validé (%d atomes extraits)" % recalc_res.get("atoms_count", 0))

	# 4. Vérifier la préservation de la perspective Auto ("") dans sync.json après recalcul
	CarnetStore.update_game_perspective(gid, "", test_profile_id)
	CarnetStore.recalculate_game(gid, test_profile_id)
	var sync_check := CarnetStore._load_sync(test_profile_id)
	var forced_p := str(sync_check.get("entries", {}).get(gid, {}).get("perspective", "NON_VIDE"))
	assert(forced_p == "", "La perspective Auto ('') doit être scrupuleusement préservée dans sync.json")
	print("✓ Préservation de la perspective Auto ('') validée sans écrasement !")

	# 5. Tester l'apprentissage : Générer un plan et noter un exercice en SM-2
	var test_atom := {
		"event_id": "atom_test_1",
		"game_id": gid,
		"ply": 2,
		"couleur": "white",
		"polarite": CarnetConfig.POLARITE_NEGATIVE,
		"qualite": "gaffe",
		"perte_winpct": 35.0,
		"merite": 0.0,
		"phase": "ouverture",
		"regime": "équilibré",
		"position_avant": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"meilleur_coup": "e2e4",
		"coup_uci": "e2e3",
		"date_iso": "2026-09-12",
	}
	CarnetStore.ingest_game(gid, [test_atom], {"perspective": "white", "date_iso": "2026-09-12"}, test_profile_id)
	CarnetStore.refresh_plan("2026-09-12", {}, test_profile_id)

	var trainer_state := CarnetStore.get_trainer_state(test_profile_id)
	var drills: Array = trainer_state.get("drills", [])
	assert(not drills.is_empty(), "Au moins un exercice doit être généré dans le plan")
	var reviewed_drill_id: String = str(drills[0].get("drill_id", ""))
	assert(reviewed_drill_id != "", "Identifiant d'exercice valide")

	# Révision avec note de 4/5
	CarnetStore.record_review(reviewed_drill_id, 4, "2026-09-12", test_profile_id)
	var after_review := CarnetStore.get_trainer_state(test_profile_id)
	var check_drills: Array = after_review.get("drills", [])
	var first_rep: int = int(check_drills[0].get("srs", {}).get("repetitions", check_drills[0].get("repetitions", 0)))
	assert(first_rep == 1, "Répétition SM-2 enregistrée à 1")
	assert(int(after_review.get("serie", 0)) == 1, "Série à 1")
	print("✓ Révision SM-2 enregistrée pour l'exercice : %s" % reviewed_drill_id)

	# 6. Tester la non-perte des motifs émergents avec n >= 3 sur profil récent (G < 5)
	var atom_n3_a := test_atom.duplicate()
	atom_n3_a["event_id"] = "atom_emergent_a"
	var atom_n3_b := test_atom.duplicate()
	atom_n3_b["event_id"] = "atom_emergent_b"
	var atom_n3_c := test_atom.duplicate()
	atom_n3_c["event_id"] = "atom_emergent_c"
	CarnetStore.ingest_game(gid, [atom_n3_a, atom_n3_b, atom_n3_c], {"perspective": "white", "date_iso": "2026-09-12"}, test_profile_id)
	var ledger_n3 := CarnetStore.compile("2026-09-12", -1, test_profile_id)
	assert(ledger_n3.get("emergeants", []).size() >= 1, "Les motifs répétés n>=3 sur G<5 doivent être conservés dans emergeants")
	print("✓ Rétention des motifs émergents n>=3 validée sur profil débutant !")

	# 7. Tester la RECONSTITUTION TOTALE À FROID (Cold Start / Zero-State)
	# On simule un cache d'atomes vidé ou supprimé sur disque
	var atoms_dir := CarnetStore._atoms_dir(test_profile_id)
	var da := DirAccess.open(atoms_dir)
	if da != null:
		da.list_dir_begin()
		var fn := da.get_next()
		while fn != "":
			if not da.current_is_dir():
				da.remove(fn)
			fn = da.get_next()
		da.list_dir_end()

	# Relancer recalculate_profile : doit tout reconstituer depuis la Bibliothèque !
	var global_res := CarnetStore.recalculate_profile(test_profile_id)
	assert(global_res.get("ok") == true, "Recalcul global réussi")
	assert(global_res.get("processed_games") == 1, "1 partie traitée depuis la Bibliothèque")
	print("✓ Reconstitution totale à froid validée avec succès !")

	# 8. Vérifier la préservation de la mémoire humaine après recalcul global
	var restored_trainer := CarnetStore.get_trainer_state(test_profile_id)
	var preserved := false
	for d in restored_trainer.get("drills", []):
		if str(d.get("drill_id", "")) == reviewed_drill_id:
			var srs_rep: int = int(d.get("srs", {}).get("repetitions", d.get("repetitions", 0)))
			assert(srs_rep == 1, "L'historique SM-2 a été préservé malgré le recalcul !")
			preserved = true
			break
	assert(preserved, "L'exercice révisé doit être présent et conservé")
	assert(int(restored_trainer.get("serie", 0)) == 1, "La série de jours a été préservée")
	print("✓ Préservation de la mémoire humaine (SM-2 & Série) validée !")

	# Nettoyage du test
	CarnetProfiles.delete(test_profile_id)
	dm.delete_game(gid)

	print("\n>>> TOUS LES TESTS D'UNIFICATION & RECALCUL SONT VALIDÉS ! <<<")
	quit(0)
