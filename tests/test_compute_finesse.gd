extends SceneTree
## tests/test_compute_finesse.gd — Cohérence des 5 paliers de finesse de calcul.

const ComputeFinesse = preload("res://src/engine/ComputeFinesse.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- ComputeFinesse tests ---")
	await process_frame

	# 1. Monotonie : chaque palier est >= au précédent sur tous les knobs.
	var keys := ["analysis_depth", "budget_base_depth", "budget_deep_depth",
			"live_depth", "live_multipv", "oracle_depth", "oracle_timeout",
			"oracle_multipv", "shallow_depth", "pv_max_plies"]
	for k in keys:
		var ok := true
		for t in range(4):
			if float(ComputeFinesse.profile(t)[k]) > float(ComputeFinesse.profile(t + 1)[k]):
				ok = false
		_check(ok, "%s strictement croissant sur les 5 paliers" % k)

	# 2. Enveloppe optionnelle : non décroissante (top_k=0 = tous).
	for t in range(4):
		var a := int(ComputeFinesse.profile(t)["shallow_top_k"])
		var b := int(ComputeFinesse.profile(t + 1)["shallow_top_k"])
		_check(a == 0 or b == 0 or a <= b, "shallow_top_k cohérent %d->%d" % [t, t + 1])

	# 3. Libellés et crans.
	_check(ComputeFinesse.TIER_LABELS.size() == 5, "5 libellés de palier")
	_check(ComputeFinesse.tier_label(0) == "Éco", "palier 0 = Éco")
	_check(ComputeFinesse.tier_label(4) == "Maximum", "palier 4 = Maximum")
	_check(ComputeFinesse.clamp_tier(9) == 4, "clamp haut")
	_check(ComputeFinesse.clamp_tier(-3) == 0, "clamp bas")

	# 4. Options par moteur.
	_check(int(ComputeFinesse.cliff_oracle_opts(3).deep_depth) == 18, "oracle d=18 en Approfondi")
	_check(bool(ComputeFinesse.cliff_envelope_opts(0).fast_mode), "palier 0 en fast_mode")
	_check(int(ComputeFinesse.live_opts(4).multipv) >= 2, "MultiPV >= 2 en Maximum")
	_check(int(ComputeFinesse.game_analysis_opts(2).theory_plies) == 8, "théorie 8 en Équilibré")

	# 5. Estimations croissantes et cohérentes.
	var e_lo := ComputeFinesse.estimate_seconds(0, 30, false)
	var e_hi := ComputeFinesse.estimate_seconds(4, 30, false)
	_check(e_lo.x > 0 and e_lo.y >= e_lo.x, "estimation Éco cohérente")
	_check(e_hi.x >= e_lo.x, "estimation Maximum >= Éco")
	_check(ComputeFinesse.format_estimate(3, 30, false).begins_with("≈"), "format d'estimation")

	print("--- ComputeFinesse : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL COMPUTE FINESSE TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("COMPUTE FINESSE TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
