extends SceneTree

func _init() -> void:
	print("==================================================")
	print("--- BENCHMARK DE VITESSE MOTEUR & EVALCACHE (DEPTH 16) ---")
	print("==================================================")
	
	await create_timer(0.3).timeout
	
	var manager = root.get_node_or_null("EngineManager")
	if not manager:
		print("Initialisation d'EngineManager...")
		var script = load("res://src/engine/EngineManager.gd")
		manager = script.new()
		root.add_child(manager)
		manager.start_engine()
	
	if not manager.is_engine_available():
		print("Attente du signal engine_ready...")
		await manager.engine_ready
	
	var sm = root.get_node_or_null("SettingsManager")
	var threads = sm.get_setting("engine_threads", 2) if sm else 2
	var hash_mb = sm.get_setting("engine_hash_mb", 32) if sm else 32
	print("Configuration active : Threads=%d, Hash=%d Mo" % [threads, hash_mb])
	
	var test_fens = [
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", # Startpos
		"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", # 1. e4
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", # 1... e5
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", # 2. Nf3
		"r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3", # 2... Nc6
		"r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3", # 3. Bb5
		"r2q1rk1/ppp2ppp/2np1n2/2b1p1B1/2B1P1b1/2NP1N2/PPP2PPP/R2Q1RK1 w - - 0 8", # Milieu de jeu tactique
		"8/5k2/8/8/8/8/3K4/8 w - - 0 1" # Finale de rois
	]
	
	print("\n--- Phase 1 : Évaluation à froid (depth 16) ---")
	var cold_times: Array[int] = []
	var total_cold_ms := 0
	
	for i in range(test_fens.size()):
		var fen = test_fens[i]
		var t0 = Time.get_ticks_msec()
		var res = manager.evaluate_position_sync(fen, 16, 2500, -1)
		var elapsed = Time.get_ticks_msec() - t0
		cold_times.append(elapsed)
		total_cold_ms += elapsed
		print("  Position %d : %3d ms | Score=%+4d cp | BestMove=%s | Depth=%d" % [
			i + 1, elapsed, res.get("score_cp", 0), res.get("best_move", ""), res.get("depth", 0)
		])
	
	var avg_cold = float(total_cold_ms) / float(test_fens.size())
	print("  -> Temps moyen à froid : %.1f ms" % avg_cold)
	
	print("\n--- Phase 2 : Vérification du cache instantané (EvalCache) ---")
	var cache_times: Array[int] = []
	var total_cache_ms := 0
	
	for i in range(test_fens.size()):
		var fen = test_fens[i]
		var t0 = Time.get_ticks_msec()
		var res = manager.evaluate_position_sync(fen, 16, 2500, -1)
		var elapsed = Time.get_ticks_msec() - t0
		cache_times.append(elapsed)
		total_cache_ms += elapsed
		print("  Position %d (Cache) : %d ms | BestMove=%s" % [i + 1, elapsed, res.get("best_move", "")])
		if elapsed > 15:
			printerr("ALERTE: Le cache a pris trop de temps (%d ms) pour la position %d" % [elapsed, i + 1])
	
	var avg_cache = float(total_cache_ms) / float(test_fens.size())
	print("  -> Temps moyen en cache : %.2f ms" % avg_cache)
	
	print("\n--- Phase 3 : Test de réponse asynchrone / Live en cache ---")
	var live_cached = manager.get_cached_eval(test_fens[0], 16)
	assert(not live_cached.is_empty(), "La position initiale doit être en cache")
	assert(live_cached.get("best_move", "") != "", "Le meilleur coup doit être présent dans le cache")
	print("  ✅ Récupération directe get_cached_eval validée avec succès !")
	
	print("\n==================================================")
	print("RÉSULTAT GLOBAL DU BENCHMARK :")
	print("  - Temps moyen initial (froid) : %.1f ms" % avg_cold)
	print("  - Temps moyen en cache        : %.2f ms" % avg_cache)
	if avg_cold <= 150.0:
		print("  ✅ PERFORMANCE OBJECTIF ATTEINTE (≤ 0.1s - 0.15s à froid, 0.0s en cache) !")
	else:
		print("  ⚠️ Temps moyen supérieur à la cible : %.1f ms" % avg_cold)
	print("==================================================")
	
	quit(0)
