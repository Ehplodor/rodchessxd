extends SceneTree
## tests/test_cliff_semantics.gd — Sémantique canonique (Charge du camp au trait),
## helpers visuels (appât/mines) et classification des suites forcées.

const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- Cliff semantics tests ---")
	await process_frame

	# 1. CliffLineReport : typage, sémantique, fraîcheur.
	var report := {
		"cliff_version": 1,
		"semantics": CliffTypes.SEMANTICS,
		"source_meta": {"fen": "FEN_A", "depth": 18, "rank": 2, "engine": "SF"},
		"summary_white": {"global_piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 43,
				"p_survie_ligne": 0.1, "max_delta_chute": 0.2, "max_bait": 0.3},
		"summary_black": {"global_piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 20,
				"p_survie_ligne": 0.5, "max_delta_chute": 0.05, "max_bait": 0.1},
		"plies": []
	}
	var rep: CliffLineReport = CliffLineReport.from_dict(report)
	_check(rep != null, "from_dict renvoie un CliffLineReport typé")
	_check(rep.get_semantics() == CliffTypes.SEMANTICS, "sémantique = charge_of_side_to_move")
	_check(rep.get_source_meta().get("rank", 0) == 2, "source_meta.rank conservé")
	_check(rep.is_stale_against("FEN_B", 18), "obsolète si FEN différente")
	_check(not rep.is_stale_against("FEN_A", 18), "à jour si FEN identique")
	_check(rep.is_stale_against("FEN_A", 22), "obsolète si profondeur dépassée")

	# 2. Narration nuancée : même piste mais D très différents.
	var narr := rep.get_narrative_summary()
	_check(narr.find("Blancs") != -1 and narr.find("nettement") != -1,
			"narration nuance un écart de charge important : " + narr)

	# 3. Charge vs Pression : relation d'inversion.
	_check(report["summary_white"]["indice_d"] > report["summary_black"]["indice_d"],
			"Blancs plus chargés que Noirs (capture -5.0)")

	# 4. Helpers de suite forcée.
	var init_game := ChessGame.new()
	var init_moves := init_game.get_legal_moves()
	_check(not CliffAnalyzer._has_winning_capture(init_moves), "pas de capture gagnante au départ")
	_check(not CliffAnalyzer._has_material_tension(init_moves), "pas de tension matérielle au départ")

	var tact := ChessGame.new("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2")
	var tact_moves := tact.get_legal_moves()
	_check(CliffAnalyzer._has_winning_capture(tact_moves), "capture gagnante détectée (exd5)")

	# 5. _build_visual_info : appât + mines cohérents.
	var analyzer := CliffAnalyzer.new(null)
	var cands := [
		{"uci": "e2e4", "san": "e4", "from_sq": 12, "to_sq": 28, "v_percu": 0.62, "wdl_deep": 0.60, "deep_known": true},
		{"uci": "d2d4", "san": "d4", "from_sq": 11, "to_sq": 27, "v_percu": 0.60, "wdl_deep": 0.30, "deep_known": true},
	]
	var dist := [0.7, 0.3]
	var info: Dictionary = analyzer._build_visual_info(cands, dist, 0.62)
	_check(str(info["bait_move_uci"]) == "e2e4", "appât = coup le plus séduisant")
	_check((info["mines"] as Array).size() == 1, "une mine détectée (d4 séduisant mais perdant)")
	_check((info["top_candidates"] as Array).size() == 2, "top candidats renseignés")

	# 5b. Mines fiables : un coup sans WDL profond réel ne doit PAS générer de mine.
	var cands_unknown := [
		{"uci": "e2e4", "san": "e4", "from_sq": 12, "to_sq": 28, "v_percu": 0.62, "wdl_deep": 0.60, "deep_known": true},
		{"uci": "d2d4", "san": "d4", "from_sq": 11, "to_sq": 27, "v_percu": 0.60, "wdl_deep": 0.30, "deep_known": false},
	]
	var info2: Dictionary = analyzer._build_visual_info(cands_unknown, dist, 0.62)
	_check((info2["mines"] as Array).is_empty(), "aucune fausse mine si WDL profond inconnu")

	print("--- Cliff semantics : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF SEMANTICS TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF SEMANTICS TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
