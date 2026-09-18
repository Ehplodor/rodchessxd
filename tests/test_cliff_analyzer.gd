extends SceneTree

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffMath = preload("res://src/engine/CliffMath.gd")
const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")

func _init() -> void:
	print("--- Running CliffAnalyzer Integration Tests ---")

	test_line_report_wrapper()

	await create_timer(0.3).timeout

	var em = root.get_node_or_null("EngineManager")
	if not em:
		print("EngineManager not found in root, instantiating directly...")
		var script = load("res://src/engine/EngineManager.gd")
		em = script.new()
		root.add_child(em)

	if not em.is_engine_running:
		print("Waiting for engine to be ready...")
		await em.engine_ready

	print("Engine available:", em.is_engine_available())

	test_shallow_and_deep_methods(em)
	test_suspect_probe(em)
	test_analyze_short_game(em)
	test_analyze_pv_line(em)

	print(">>> ALL CLIFF ANALYZER INTEGRATION TESTS PASSED! <<<")
	quit(0)

func test_line_report_wrapper() -> void:
	var dummy_data = {
		"cliff_version": 2,
		"plies_analyzed": 2,
		"plies": [
			{"ply": 0, "piste": CliffTypes.Piste.AUTOROUTE, "indice_d": 10, "effort_d": 10, "pression_d": 65, "leverage": 55},
			{"ply": 1, "piste": CliffTypes.Piste.CORNICHE, "indice_d": 65, "effort_d": 65, "pression_d": 10, "leverage": -55, "delta_chute": 0.40, "p_survie": 0.04}
		],
		"summary_white": {
			"p_survie_ligne": 0.85,
			"global_piste": CliffTypes.Piste.AUTOROUTE,
			"indice_d": 12
		},
		"summary_black": {
			"p_survie_ligne": 0.32,
			"global_piste": CliffTypes.Piste.CORNICHE,
			"indice_d": 68
		}
	}

	var rep = CliffLineReport.from_dict(dummy_data)
	assert(rep.get_plies_count() == 2)
	assert(rep.get_piste_for_ply(0) == CliffTypes.Piste.AUTOROUTE)
	assert(rep.get_piste_for_ply(1) == CliffTypes.Piste.CORNICHE)
	assert(rep.get_summary_white()["indice_d"] == 12)
	assert(rep.get_summary_black()["indice_d"] == 68)
	assert(rep.get_tactical_leverage(0) == 55)
	assert(rep.get_tactical_leverage(1) == -55)

	var rupture = rep.get_rupture_point()
	assert(not rupture.is_empty())
	assert(rupture["index"] == 1)

	var narr = rep.get_narrative_summary()
	print("Report narrative:", narr)
	assert(narr.contains("Autoroute") and narr.contains("Corniche") and narr.contains("Décrochage critique"))

func test_shallow_and_deep_methods(em: Node) -> void:
	if not em.is_engine_available():
		print("Engine not available, skipping live SF queries")
		return

	# Start position
	var fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

	# Shallow sync test
	var shallow_res = em.evaluate_shallow_sync(fen, 1000)
	print("Shallow result:", shallow_res)
	assert(shallow_res.has("score_cp") or shallow_res.has("best_move"))
	assert(shallow_res.get("depth", 0) <= 2)

	# Deep MultiPV sync test
	var deep_res = em.evaluate_deep_multipv_sync(fen, 8, 2, 4000)
	print("Deep MultiPV result: depth=", deep_res.get("depth", 0), " lines=", deep_res.get("multipv_lines", []).size())
	assert(deep_res.get("depth", 0) >= 6)

func test_suspect_probe(em: Node) -> void:
	if not em.is_engine_available():
		return
	var fen := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	var probe = em.probe_suspect_move_fast(fen, "e2e4", 4, 300)
	print("Suspect probe result:", probe)
	assert(probe.has("best_move"))
	assert(probe.has("depth"))

func test_analyze_short_game(em: Node) -> void:
	if not em.is_engine_available():
		return

	# Play 1. e4 e5 2. Qh5
	var game = ChessGame.new()
	for m in game.get_legal_moves():
		if m.uci == "e2e4":
			game.make_move(m)
			break
	for m in game.get_legal_moves():
		if m.uci == "e7e5":
			game.make_move(m)
			break
	for m in game.get_legal_moves():
		if m.uci == "d1h5":
			game.make_move(m)
			break

	var analyzer = CliffAnalyzer.new(em)
	var options = {
		"deep_depth": 6,
		"fast_mode": true
	}
	var report = analyzer.analyze_game(game, options)
	print("Analyze game plies analyzed:", report.get("plies_analyzed", 0))
	assert(report.get("plies_analyzed", 0) == 3)
	assert(report.has("summary_white"))
	assert(report.has("summary_black"))
	var plies = report.get("plies", [])
	assert(plies.size() == 3)
	for p in plies:
		assert(p.has("piste"))
		assert(p.has("indice_d"))
		assert(p.has("effort_d"))
		assert(p.has("pression_d"))
		assert(p.has("d_latent_opponent"), "ply should contain d_latent_opponent")
		assert(p.has("surprise_delta"), "ply should contain surprise_delta")
		assert(p.has("surprise_nature"), "ply should contain surprise_nature")
		assert(p.has("leverage"))
		assert(p.has("delta_chute"))
		assert(p.has("bait"))
		assert(p.has("fen_before"))
		assert(p.has("fen_after"))

func test_analyze_pv_line(em: Node) -> void:
	var analyzer = CliffAnalyzer.new(em)
	var start_fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
	var pv_line = ["e7e5", "g1f3", "b8c6"]
	var options = {
		"deep_depth": 6,
		"fast_mode": true
	}
	var steps_box := [0]
	analyzer.step_analyzed.connect(func(idx, uci, fen, data):
		steps_box[0] += 1
	)
	var report = analyzer.analyze_pv_line(start_fen, pv_line, options)
	print("Analyze pv line count:", report.get("plies_analyzed", 0), "steps emitted:", steps_box[0])
	assert(report.get("plies_analyzed", 0) == 3)
	assert(steps_box[0] == 3)
	assert(report.get("is_pv_line", false) == true)
	assert(report.has("summary_white"))
	assert(report.has("summary_black"))

	# Test Level 2 Meso analysis: analyze_multiple_lines_sync
	var lines_multi = [
		{"rank": 1, "pv": ["e7e5", "g1f3"]},
		{"rank": 2, "pv": ["c7c5", "g1f3"]}
	]
	var multi_res = analyzer.analyze_multiple_lines_sync(start_fen, lines_multi, options)
	assert(multi_res.has(1), "Multi lines result should contain rank 1")
	assert(multi_res.has(2), "Multi lines result should contain rank 2")
	assert(multi_res[1].has("piste"))
	assert(multi_res[2].has("piste"))
	print("Analyze multiple lines count:", multi_res.size(), "ranks evaluated: ok")
