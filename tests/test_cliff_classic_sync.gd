extends SceneTree

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")
const ChessMove = preload("res://src/core/ChessMove.gd")

func _init() -> void:
	print("--- Running Cliff & Classical Analysis Synchronization Tests ---")
	await process_frame
	var em = root.get_node_or_null("/root/EngineManager")
	if em == null:
		em = root.get_node_or_null("EngineManager")
	if em != null and not em.is_engine_running:
		await em.engine_ready
	assert(em != null, "EngineManager should be available")

	test_cliff_to_classic_report_bridge(em)
	print(">>> ALL CLIFF CLASSIC SYNC TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func test_cliff_to_classic_report_bridge(em: Node) -> void:
	# 1. Préparer une partie courte : 1. e4 e5 2. Qh5 Nc6
	var game = ChessGame.new()
	for uci in ["e2e4", "e7e5", "d1h5", "b8c6"]:
		for m in game.get_legal_moves():
			if m.uci == uci:
				game.make_move(m)
				break

	assert(game.move_history.size() == 4)

	# 2. Analyser la partie avec CliffAnalyzer
	var cliff = CliffAnalyzer.new(em)
	var cliff_opts = {
		"deep_depth": 6,
		"fast_mode": true
	}
	var cliff_report = cliff.analyze_game(game, cliff_opts)
	assert(cliff_report.get("plies_analyzed", 0) == 4)
	var cliff_plies: Array = cliff_report.get("plies", [])
	assert(cliff_plies.size() == 4)

	# Vérifier que les plies contiennent les données d'évaluation moteur requises
	for p in cliff_plies:
		assert(p.has("score_cp"), "Cliff ply must contain score_cp")
		assert(p.has("mate_in"), "Cliff ply must contain mate_in")
		assert(p.has("best_move"), "Cliff ply must contain best_move")
		assert(p.has("depth"), "Cliff ply must contain depth")

	# 3. Passerelle GameAnalyzer : build_report_from_cliff_plies
	var analyzer = GameAnalyzer.new()
	var classic_report = analyzer.build_report_from_cliff_plies(game, cliff_plies, 6)

	assert(not classic_report.is_empty(), "Classic report must not be empty")
	assert(classic_report.has("evaluations"), "Classic report must have evaluations")
	var evals: Array = classic_report.get("evaluations", [])
	assert(evals.size() == 4, "Classic evaluations count must match move count")

	# Vérifier les métriques classiques clés
	assert(classic_report.has("white_accuracy"), "Report must have white_accuracy")
	assert(classic_report.has("black_accuracy"), "Report must have black_accuracy")
	assert(classic_report.has("white_acpl"), "Report must have white_acpl")
	assert(classic_report.has("black_acpl"), "Report must have black_acpl")
	assert(classic_report.has("white_estimated_elo"), "Report must have white_estimated_elo")
	assert(classic_report.has("black_estimated_elo"), "Report must have black_estimated_elo")
	assert(classic_report.has("biggest_swings"), "Report must have biggest_swings")

	print("  ok: white_accuracy = %.1f%%, black_accuracy = %.1f%%" % [
		float(classic_report.get("white_accuracy", 0.0)),
		float(classic_report.get("black_accuracy", 0.0))
	])
	print("  ok: white_acpl = %.1f, black_acpl = %.1f" % [
		float(classic_report.get("white_acpl", 0.0)),
		float(classic_report.get("black_acpl", 0.0))
	])
	print("  ok: white_elo = %d, black_elo = %d" % [
		int(classic_report.get("white_estimated_elo", 0)),
		int(classic_report.get("black_estimated_elo", 0))
	])

	# Vérifier chaque enregistrement d'évaluation pour la courbe d'avantage
	for i in range(evals.size()):
		var ev: Dictionary = evals[i]
		assert(ev.has("score_cp"), "Eval record must have score_cp")
		assert(ev.has("mate_in"), "Eval record must have mate_in")
		assert(ev.has("quality"), "Eval record must have quality")
		assert(ev.has("win_before"), "Eval record must have win_before")
		assert(ev.has("win_after"), "Eval record must have win_after")
		assert(ev.has("winpct_loss"), "Eval record must have winpct_loss")
		assert(ev.has("loss_cp"), "Eval record must have loss_cp")
		assert(ev.has("san"), "Eval record must have san")
		assert(ev.has("best_move"), "Eval record must have best_move")

	print("  ok: All 4 move evaluations successfully populated for AdvantageGraph & MoveList")

	# Test du comportement coup-par-coup de la Super-Analyse
	var main_scene = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main_scene)
	var gc = root.get_node_or_null("GameController")
	if gc != null and gc.game != null and gc.game.move_history.size() > 0:
		main_scene._cliff_full_running = true
		var step_dummy: Dictionary = {
			"fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
			"best_move_uci": "e2e4",
			"tactical_profile": "EQUILIBRE",
			"tactical_weight": 0.2,
			"delta_wp": 0.0,
			"phase_point": Vector2(0.5, 0.5)
		}
		main_scene._on_cliff_full_ply_step(0, step_dummy)
		assert(gc.current_ply_index == 0, "GameController current_ply_index should be advanced to ply 0")
		print("  ok: Super-Analyse advances board ply index step by step")
		main_scene._cliff_full_running = false
	main_scene.queue_free()

