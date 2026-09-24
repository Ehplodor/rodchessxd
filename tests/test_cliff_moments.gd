extends SceneTree
## tests/test_cliff_moments.gd — Sélection et jugement des moments clés (pur, sans moteur).

const CliffMoments = preload("res://src/engine/CliffMoments.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const PlayerSide = preload("res://src/core/PlayerSide.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _ev(ply: int, loss: float, theory: bool = false) -> Dictionary:
	return {"ply": ply, "winpct_loss": loss, "is_theory": theory}

func _cp(overrides: Dictionary) -> Dictionary:
	var base := {"ply": 20, "is_white": true, "reliable": true, "in_theory": false, "san": "Qxf6+",
			"played_uci": "d8f6", "best_move": "d8f6", "p_survie": 0.4, "only_move": false,
			"bait_move_uci": "", "bait": 0.0, "indice_d": 60, "delta_chute": 0.5, "fen_before": "x",
			"top_candidates": [{"uci": "d8f6", "san": "Qxf6+"}, {"uci": "h7h6", "san": "h6"}]}
	base.merge(overrides, true)
	return base

func _init() -> void:
	print("--- Cliff moments tests ---")

	# 1. Sélection des candidats.
	var evals := [_ev(0, 30.0, true), _ev(1, 2.0), _ev(2, 12.0), _ev(3, 0.0), _ev(4, 6.0)]
	var cands := CliffMoments.select_candidates(evals, {3: 0.45, 1: 0.05})
	_check(not cands.has(0), "théorie exclue même avec une grosse perte")
	_check(not cands.has(1), "ni perte ni chemin étroit → écarté")
	_check(cands.has(2) and cands.has(4), "pertes ≥ 5 points retenues")
	_check(cands.has(3), "chemin étroit TROUVÉ (perte 0) retenu grâce au criblage")
	_check(cands == [2, 3, 4], "ordre chronologique")
	var many: Array = []
	for i in range(30):
		many.append(_ev(i, 5.0 + float(i)))
	var capped := CliffMoments.select_candidates(many, {}, 12)
	_check(capped.size() == 12 and capped.has(29) and not capped.has(0), "plafond : les 12 plus marquants")

	# 2. Jugement.
	var m := CliffMoments.classify(_cp({"only_move": true}), 0.0)
	_check(int(m.get("kind", -1)) == CliffTypes.MomentKind.ONLY_FOUND, "coup unique difficile trouvé")
	_check(CliffMoments.classify(_cp({"only_move": true, "p_survie": 0.95}), 0.0).is_empty(),
			"coup unique évident (repli forcé) écarté")
	m = CliffMoments.classify(_cp({"only_move": true, "played_uci": "h7h6", "san": "h6", "p_survie": 0.6}), 40.0)
	_check(int(m.get("kind", -1)) == CliffTypes.MomentKind.ONLY_MISSED, "coup unique manqué")
	_check(str(m["text"]).contains("Qxf6+") and str(m["text"]).contains("trouvable"), "texte : bon coup + trouvable")
	m = CliffMoments.classify(_cp({"played_uci": "h7h6", "san": "h6", "bait_move_uci": "h7h6", "bait": 0.3}), 25.0)
	_check(int(m.get("kind", -1)) == CliffTypes.MomentKind.BAIT_TAKEN and m["bait_uci"] == "h7h6", "appât mordu")
	m = CliffMoments.classify(_cp({"played_uci": "h7h6", "san": "h6", "p_survie": 0.9}), 20.0)
	_check(int(m.get("kind", -1)) == CliffTypes.MomentKind.CARELESS, "erreur en position facile = inattention")
	m = CliffMoments.classify(_cp({"played_uci": "h7h6", "san": "h6", "p_survie": 0.3}), 20.0)
	_check(int(m.get("kind", -1)) == CliffTypes.MomentKind.HARD_ERROR, "erreur en position dure")
	_check(CliffMoments.classify(_cp({"played_uci": "h7h6"}), 6.0).is_empty(), "simple imprécision : pas un moment")
	_check(CliffMoments.classify(_cp({"reliable": false, "only_move": true}), 50.0).is_empty(), "moteur défaillant : rien inventé")

	# 3. Pression et résumé.
	var found := CliffMoments.classify(_cp({"only_move": true}), 0.0)
	var pr := CliffMoments.as_pressure(found)
	_check(bool(pr["pressure"]) and str(pr["icon"]) == "⚡", "moment adverse vu comme pression")
	var summary := CliffMoments.side_summary([found, m], true)
	_check(summary.contains("1 test réussi") and summary.contains("position exigeante"), "résumé : " + summary)
	_check(CliffMoments.side_summary([], false) == "Aucun moment critique", "résumé vide")

	# 4. Camp de l'utilisateur.
	_check(PlayerSide.resolve_from("Magnus", "rodolphe", ["rodolphe"], "", false) == "black", "profil Carnet → Noirs")
	_check(PlayerSide.resolve_from("Rodolphe ", "x", ["rodolphe"], "black", true) == "white", "profil prioritaire, noms normalisés")
	_check(PlayerSide.resolve_from("a", "b", [], "black", false) == "black", "repli coach_perspective")
	_check(PlayerSide.resolve_from("a", "b", [], "neutral", true) == "black", "repli échiquier retourné")
	_check(PlayerSide.resolve_from("?", "?", ["?"], "", false) == "white", "défaut Blancs")

	print("--- Cliff moments : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF MOMENTS TESTS PASSED SUCCESSFULLY!")
	quit(0 if _failures == 0 else 1)
