extends SceneTree

func _init() -> void:
	print("--- Running EngineManager unit test ---")
	
	# Wait for root tree nodes to be ready
	await create_timer(0.2).timeout
	
	var manager = root.get_node_or_null("EngineManager")
	if not manager:
		print("EngineManager not found in root, instantiating directly...")
		var script = load("res://src/engine/EngineManager.gd")
		manager = script.new()
		root.add_child(manager)
		manager.start_engine()
	
	if not manager.is_engine_running:
		print("Waiting for engine to start...")
		await manager.engine_ready
	
	print("Engine is running! Testing evaluation on starting position...")
	
	var tracker := {"eval_received": false}
	manager.evaluation_updated.connect(func(score_cp, mate_in, depth, best_move, pv, _multipv):
		print("Evaluation update: Depth=%d, Score=%d cp, Mate=%d, BestMove=%s, PV=%s" % [depth, score_cp, mate_in, best_move, " ".join(pv.slice(0, 4))])
		if depth >= 8:
			tracker["eval_received"] = true
	)
	
	manager.evaluate_position(ChessGame.INITIAL_FEN, 10)
	
	var timeout = 0
	while not tracker["eval_received"] and timeout < 60:
		await create_timer(0.1).timeout
		timeout += 1

	assert(tracker["eval_received"] == true)
	print("ENGINE EVALUATION TEST PASSED SUCCESSFULLY!")
	quit(0)
