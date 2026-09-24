extends SceneTree
## Benchmark CHESS-CLIFF : partie complète + comparaison de 5 lignes.
## godot --headless --path . -s tests/bench_cliff.gd

const CliffAnalyzer = preload("res://src/engine/CliffAnalyzer.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")
const CliffMoments = preload("res://src/engine/CliffMoments.gd")

const PGN := "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 b4 15. Nb1 h6 16. Bh4 c5 17. dxe5 Nxe4 18. Bxe7 Qxe7 19. exd6 Qf6 20. Nbd2 Nxd6"

const AMATEUR_PGN := "1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Ng5 d5 5. exd5 Nxd5 6. Nxf7 Kxf7 7. Qf3+ Ke6 8. Nc3 Ncb4 9. a3 Nxc2+ 10. Kd1 Nxa1 11. Nxd5 Kd6 12. d4 c6 13. Nc3 exd4 14. Ne4+ Kc7 15. Qf7+ Qd7 16. Bf4+ Kd8 17. Qf8+ Qe8 18. Qxf8"

func _init() -> void:
	await create_timer(0.3).timeout
	var em = root.get_node_or_null("EngineManager")
	if em == null:
		em = load("res://src/engine/EngineManager.gd").new()
		root.add_child(em)
	if not em.is_engine_running:
		await em.engine_ready

	var game := ChessGame.new()
	game.load_pgn(PGN)
	var opts := {"deep_depth": 14, "multipv": 3, "timeout_ms": 4000, "theory_plies": 6, "shallow_depth": 2}
	var t0 := 0
	var agame := ChessGame.new()
	agame.load_pgn(AMATEUR_PGN)
	print("amateur plies=%d" % agame.move_history.size())
	# Super-Analyse « Moments clés » : analyse classique, criblage, Cliff ciblé.
	var ga = load("res://src/engine/GameAnalyzer.gd").new()
	ga.engine_manager = em
	t0 = Time.get_ticks_msec()
	var classic: Dictionary = ga.start_game_analysis(agame, 14, {"mode": "dynamic", "wait_for_display": false})
	var t_classic := Time.get_ticks_msec() - t0
	var evals: Array = classic.get("evaluations", [])
	var theory := 0
	while theory < evals.size() and bool(evals[theory].get("is_theory", false)):
		theory += 1
	var an := CliffAnalyzer.new(em)
	t0 = Time.get_ticks_msec()
	var gaps := an.screen_plies(agame, theory)
	var t_screen := Time.get_ticks_msec() - t0
	var cands := CliffMoments.select_candidates(evals, gaps)
	t0 = Time.get_ticks_msec()
	var cliff := an.analyze_plies(agame, cands, opts)
	var t_cliff := Time.get_ticks_msec() - t0
	var mrep := CliffMoments.build_report(evals, gaps, cands, cliff)
	print("BENCH moments: classic %d ms | screen %d ms (%d plies) | cliff %d ms (%d candidates) | %d moments" % [
			t_classic, t_screen, gaps.size(), t_cliff, cands.size(), mrep["moments"].size()])
	for m in mrep["moments"]:
		print("   %s %s %s — %s" % [m["icon"], "W" if m["is_white"] else "B", m["san"], m["text"]])


	t0 = Time.get_ticks_msec()
	var go0 := int(em.get("go_count")) if em.get("go_count") != null else 0
	var rep: Dictionary = CliffAnalyzer.new(em).analyze_game(game, opts)
	var t1 := Time.get_ticks_msec()
	var go1 := int(em.get("go_count")) if em.get("go_count") != null else 0
	print("BENCH game: plies=%d  %d ms  go=%d  D_w=%d D_b=%d" % [rep.get("plies_analyzed", 0), t1 - t0, go1 - go0,
			int(rep.get("summary_white", {}).get("indice_d", -1)), int(rep.get("summary_black", {}).get("indice_d", -1))])

	var start_fen := "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
	var lines := [
		{"rank": 1, "pv": ["f1b5", "a7a6", "b5a4", "g8f6"]},
		{"rank": 2, "pv": ["f1c4", "f8c5", "c2c3", "g8f6"]},
		{"rank": 3, "pv": ["d2d4", "e5d4", "f3d4", "g8f6"]},
		{"rank": 4, "pv": ["b1c3", "g8f6", "f1b5", "f8b4"]},
		{"rank": 5, "pv": ["c2c3", "g8f6", "d2d3", "d7d5"]},
	]
	var mopts := {"deep_depth": 14, "multipv": 3, "timeout_ms": 3000, "line_plies": 4}
	t0 = Time.get_ticks_msec()
	go0 = int(em.get("go_count")) if em.get("go_count") != null else 0
	var res: Dictionary = CliffAnalyzer.new(em).analyze_multiple_lines_sync(start_fen, lines, mopts)
	t1 = Time.get_ticks_msec()
	go1 = int(em.get("go_count")) if em.get("go_count") != null else 0
	var pistes := []
	for r in res.keys():
		pistes.append("%d:D%d" % [r, int(res[r].get("indice_d", -1))])
	print("BENCH lines: %d ms  go=%d  %s" % [t1 - t0, go1 - go0, " ".join(pistes)])
	quit(0)
