extends SceneTree

## bench_analysis_modes.gd
## Compare le mode dynamique actuel, le mode à budget (proto) et une référence profonde
## sur plusieurs parties : temps, distribution des qualités et détection des coups à problème.

const PGN_USER := "1. d4 e6 2. e4 Nf6 3. Nc3 Nc6 4. Bd3 Nxd4 5. a4 Bc5 6. Be3 e5 7. Nf3 Nxf3+ 8. gxf3 Bb4 9. Bd2 d6 10. Bb5+ Kf8 11. Rg1 Bh3 12. Bf1 Bxf1 13. Rxf1 Qd7 14. Ne2 Nh5 15. Rg1 Qh3 16. Rg3 Qxh2 17. Bxb4 Nxg3 18. fxg3 Qh1+ 19. Kd2 Qxf3 20. Ra3 Qxe4 21. Re3 Qxb4+ 22. c3 Qxb2+ 23. Qc2 Qb6 24. Rf3 f6 25. g4 Rd8 26. g5 d5 27. gxf6 gxf6 28. Qf5 Qb2+ 29. Ke3 d4+ 30. Kd3 dxc3+ 31. Ke3 Qd2+ 32. Kf2 e4 33. Qxf6+ Kg8 34. Qf7#"
const PGN_FOOLS := "1. f3 e5 2. g4 Qh4#"
const PGN_QUIET := "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 11. Nbd2 Bb7 12. Bc2 Re8 13. Nf1 Bf8 14. Ng3 g6 15. a4 c5"

func _init() -> void:
	print("\n=== BENCHMARK MODES D'ANALYSE ===")
	await create_timer(0.2).timeout
	var em = root.get_node_or_null("EngineManager")
	var gc = root.get_node_or_null("GameController")
	if em == null or gc == null:
		print("Autoloads manquants"); quit(1); return
	if not em.is_engine_available():
		await em.engine_ready

	var games := {"user": PGN_USER, "fools": PGN_FOOLS, "quiet": PGN_QUIET}
	var modes := [
		{"name": "dynamic(0.08/0.25)", "depth": 14, "opts": {"mode": "dynamic", "dynamic_base": 0.08, "dynamic_max": 0.25, "wait_for_display": false}},
		{"name": "budget(8->14,K6)", "depth": 14, "opts": {"mode": "budget", "base_depth": 8, "deep_depth": 14, "max_deep": 6, "min_criticality": 12.0, "deep_movetime_ms": 250, "wait_for_display": false}},
		{"name": "profile16", "depth": 16, "opts": {"mode": "depth", "wait_for_display": false}}
	]

	for gname in games:
		var pgn: String = games[gname]
		gc.load_pgn(pgn)
		var base_game = gc.game
		var nplies = base_game.move_history.size()
		print("\n--- Partie %s (%d demi-coups) ---" % [gname, nplies])
		var reports := {}
		for m in modes:
			var a = load("res://src/engine/GameAnalyzer.gd").new()
			a.engine_manager = em
			em.clear_eval_cache()
			var t0 = Time.get_ticks_msec()
			var rep: Dictionary = a.start_game_analysis(base_game, int(m["depth"]), m["opts"])
			var dt = Time.get_ticks_msec() - t0
			reports[m["name"]] = rep
			print("  %-22s %6d ms | %s" % [m["name"], dt, _dist(rep)])
			var evs: Array = rep.get("evaluations", [])
			assert(evs.size() == nplies, "taille evaluations (%d vs %d)" % [evs.size(), nplies])
		# Détections des gros coups (groupe >= 2) vs référence
		var ref: Dictionary = reports["profile16"]
		for name in ["dynamic(0.08/0.25)", "budget(8->14,K6)"]:
			var cmp := _compare_problems(reports[name], ref)
			print("  %-22s vs profile16 : rappel=%d/%d, precision=%d/%d, pires écarts=%s" % [
				name, cmp["hit"], cmp["ref_total"], cmp["spurious"], cmp["cand_total"], str(cmp["top_ref"])])
	quit(0)

func _dist(rep: Dictionary) -> String:
	var ws: Dictionary = rep.get("white_stats", {})
	var bs: Dictionary = rep.get("black_stats", {})
	var cats := ["brilliant", "great", "inaccuracy", "mistake", "blunder", "miss"]
	var out := ""
	for c in cats:
		out += "%s=%d " % [c, int(ws.get(c, 0)) + int(bs.get(c, 0))]
	return out

## Compare les coups "à problème" (groupe >= 2 : erreur/gaffe) de cand vs ref.
func _compare_problems(cand: Dictionary, ref: Dictionary) -> Dictionary:
	var ce: Array = cand.get("evaluations", [])
	var re: Array = ref.get("evaluations", [])
	var n := mini(ce.size(), re.size())
	var hit := 0
	var ref_total := 0
	var spurious := 0
	var cand_total := 0
	var top_ref: Array = []
	for i in range(n):
		var cq := int(ce[i].get("quality", 0))
		var rq := int(re[i].get("quality", 0))
		var c_bad := MoveQualityService.group(cq) >= 2
		var r_bad := MoveQualityService.group(rq) >= 2
		if r_bad:
			ref_total += 1
			top_ref.append(i)
			if c_bad:
				hit += 1
		if c_bad:
			cand_total += 1
			if not r_bad:
				spurious += 1
	return {"hit": hit, "ref_total": ref_total, "spurious": spurious, "cand_total": cand_total, "top_ref": top_ref}
