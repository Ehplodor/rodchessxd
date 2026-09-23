extends SceneTree

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffMath = preload("res://src/engine/CliffMath.gd")
const ChessPiece = preload("res://src/core/ChessPiece.gd")

func _init() -> void:
	print("--- Running CliffMath Unit Tests ---")

	test_wdl_zero()
	test_wdl_large_positive()
	test_wdl_mate()
	test_saillance_check_highest()
	test_saillance_backward_penalty()
	test_boltzmann_sums_to_one()
	test_boltzmann_sharp()
	test_suite_forcee_check()
	test_delta_chute()
	test_classify_autoroute()
	test_classify_champ_mines()
	test_classify_fil_du_rasoir()
	test_classify_corniche()
	test_classify_chemin()
	test_indice_d_range()
	test_h_mob_collapsed()
	test_h_mob_multiple()
	test_p_survie_ligne()
	test_p_survie_forced()
	test_bait_semantics()
	test_viable_ignores_unknown()
	test_horizon_no_regime_jump()
	test_surprise_classification()

	print(">>> ALL CLIFF MATH TESTS PASSED SUCCESSFULLY! <<<")
	quit(0)

func test_wdl_zero() -> void:
	var w = CliffMath.wdl(0, 0)
	print("test_wdl_zero: wdl(0, 0) = ", w)
	assert(abs(w - 0.5) < 0.01, "wdl(0, 0) should be ~0.50")

func test_wdl_large_positive() -> void:
	var w = CliffMath.wdl(600, 0)
	print("test_wdl_large_positive: wdl(600, 0) = ", w)
	assert(w > 0.88, "wdl(600, 0) should be > 0.88")

func test_wdl_mate() -> void:
	var w_win = CliffMath.wdl(0, 3)
	var w_loss = CliffMath.wdl(0, -5)
	print("test_wdl_mate: mate_in 3 = ", w_win, ", mate_in -5 = ", w_loss)
	assert(w_win > CliffMath.wdl(3000, 0), "any winning mate must outrank any cp eval")
	assert(w_loss < CliffMath.wdl(-3000, 0), "any losing mate must rank below any cp eval")
	assert(CliffMath.wdl(0, 1) > CliffMath.wdl(0, 20), "shorter mate must be better")
	assert(CliffMath.wdl(0, -1) < CliffMath.wdl(0, -20), "being mated sooner must be worse")
	assert(CliffMath.wdl(0, 200) == CliffMath.wdl(0, CliffTypes.MATE_HORIZON), "mates beyond horizon are equal")

func test_saillance_check_highest() -> void:
	var quiet_move = {
		"is_check": false,
		"captured_piece": ChessPiece.Type.NONE,
		"piece": ChessPiece.Type.KNIGHT,
		"from_sq": 1, # b1
		"to_sq": 18, # c3
		"color": ChessPiece.PieceColor.WHITE
	}
	var check_move = quiet_move.duplicate()
	check_move["is_check"] = true

	var s_quiet = CliffMath.saillance(quiet_move)
	var s_check = CliffMath.saillance(check_move)
	print("test_saillance_check_highest: quiet=", s_quiet, " check=", s_check)
	assert(s_check > s_quiet, "Check move must have higher saillance than quiet move")
	assert(abs((s_check - s_quiet) - CliffTypes.W_CHECK) < 0.001, "Check diff must equal W_CHECK")

func test_saillance_backward_penalty() -> void:
	# White piece moving forward vs backward
	var forward_move = {
		"is_check": false,
		"captured_piece": ChessPiece.Type.NONE,
		"piece": ChessPiece.Type.KNIGHT,
		"from_sq": 18, # c3 (rank 3)
		"to_sq": 35,  # d5 (rank 5)
		"color": ChessPiece.PieceColor.WHITE
	}
	var backward_move = {
		"is_check": false,
		"captured_piece": ChessPiece.Type.NONE,
		"piece": ChessPiece.Type.KNIGHT,
		"from_sq": 35, # d5 (rank 5)
		"to_sq": 18,  # c3 (rank 3)
		"color": ChessPiece.PieceColor.WHITE
	}
	var s_fwd = CliffMath.saillance(forward_move)
	var s_bwd = CliffMath.saillance(backward_move)
	print("test_saillance_backward_penalty: fwd=", s_fwd, " bwd=", s_bwd)
	assert(s_fwd > s_bwd, "Forward move must have higher saillance than backward move")
	assert(s_bwd < 0.0, "Backward quiet move should have negative saillance penalty")

func test_boltzmann_sums_to_one() -> void:
	var v_all = [0.45, 0.52, 0.78, 0.31, 0.12]
	var dist = CliffMath.p_humain_distribution(v_all)
	var total = 0.0
	for p in dist:
		total += p
	print("test_boltzmann_sums_to_one: sum=", total)
	assert(abs(total - 1.0) < 0.0001, "Boltzmann distribution must sum to 1.0")

func test_boltzmann_sharp() -> void:
	var v_all = [0.2, 0.8, 0.2]
	var dist = CliffMath.p_humain_distribution(v_all)
	print("test_boltzmann_sharp: dist=", dist)
	assert(dist[1] > 0.90, "With beta=12, v=0.8 vs 0.2 must overwhelmingly dominate")

func test_suite_forcee_check() -> void:
	assert(CliffMath.is_suite_forcee(true, false, false) == true)
	assert(CliffMath.is_suite_forcee(false, true, false) == true)
	assert(CliffMath.is_suite_forcee(false, false, true) == true)
	assert(CliffMath.is_suite_forcee(false, false, false) == false)

func test_delta_chute() -> void:
	var d_wide = CliffMath.delta_chute(0.65, 0.60)
	var d_narrow = CliffMath.delta_chute(0.70, 0.35)
	print("test_delta_chute: wide=", d_wide, " narrow=", d_narrow)
	assert(abs(d_wide - 0.05) < 0.001)
	assert(abs(d_narrow - 0.35) < 0.001)

func test_classify_autoroute() -> void:
	var piste = CliffMath.classify_piste(0.70, 0.08, 0.0)
	print("test_classify_autoroute: piste=", piste)
	assert(piste == CliffTypes.Piste.AUTOROUTE, "Expected AUTOROUTE for P=0.70, delta=0.08")

func test_classify_champ_mines() -> void:
	var piste = CliffMath.classify_piste(0.02, 0.40, 0.10)
	print("test_classify_champ_mines: piste=", piste)
	assert(piste == CliffTypes.Piste.CHAMP_DE_MINES, "Expected CHAMP_DE_MINES for P=0.02")

func test_classify_fil_du_rasoir() -> void:
	var piste = CliffMath.classify_piste(0.20, 0.35, 0.05)
	print("test_classify_fil_du_rasoir: piste=", piste)
	assert(piste == CliffTypes.Piste.FIL_DU_RASOIR, "Expected FIL_DU_RASOIR for delta>=0.30 and P<0.40")

func test_classify_corniche() -> void:
	var piste = CliffMath.classify_piste(0.30, 0.15, 0.10)
	print("test_classify_corniche: piste=", piste)
	assert(piste == CliffTypes.Piste.CORNICHE, "Expected CORNICHE for P=0.30")

func test_classify_chemin() -> void:
	var piste = CliffMath.classify_piste(0.55, 0.10, 0.05)
	print("test_classify_chemin: piste=", piste)
	assert(piste == CliffTypes.Piste.CHEMIN, "Expected CHEMIN for P=0.55")

func test_indice_d_range() -> void:
	var d_min = CliffMath.indice_d([0.0], [1.0], [0.0], 2.0)
	var d_max = CliffMath.indice_d([1.0], [0.0], [1.0], 0.0)
	print("test_indice_d_range: min=", d_min, " max=", d_max)
	assert(d_min >= 0 and d_min <= 100, "D must be in [0, 100]")
	assert(d_max >= 0 and d_max <= 100, "D must be in [0, 100]")
	assert(d_min == 0, "D with no cliff, perfect survival, no bait should be 0")
	assert(d_max == 100, "D with maximal cliff, 0 survival, max bait should clamp to 100")

func test_h_mob_collapsed() -> void:
	# Best move wdl=0.8, all other moves far worse (> 0.05 difference)
	var wdl_all = [0.8, 0.4, 0.3, 0.2]
	var p_humain = [0.7, 0.1, 0.1, 0.1]
	var h = CliffMath.h_mob(wdl_all, 0.8, p_humain)
	print("test_h_mob_collapsed: h=", h)
	assert(h == 0.0, "H_mob with 1 viable move must be 0.0")

func test_h_mob_multiple() -> void:
	# 2 viable moves with equal probability
	var wdl_all = [0.80, 0.79, 0.20]
	var p_humain = [0.50, 0.50, 0.00]
	var h = CliffMath.h_mob(wdl_all, 0.80, p_humain)
	print("test_h_mob_multiple: h=", h)
	assert(abs(h - 1.0) < 0.001, "H_mob for 2 equal viable moves should be 1.0 bit")

func test_p_survie_ligne() -> void:
	var p_arr = [0.9, 0.9, 0.9]
	var p_line = CliffMath.p_survie_ligne(p_arr)
	print("test_p_survie_ligne: p_line=", p_line)
	assert(abs(p_line - 0.729) < 0.001, "P_survie_ligne must be product of plies")

func test_surprise_classification() -> void:
	assert(CliffTypes.classify_surprise(45) == CliffTypes.SurpriseNature.SHOCK, "S > 40 must be SHOCK")
	assert(CliffTypes.classify_surprise(25) == CliffTypes.SurpriseNature.SURPRISE, "S in (20, 40] must be SURPRISE")
	assert(CliffTypes.classify_surprise(5) == CliffTypes.SurpriseNature.NORMAL, "S in [-20, 20] must be NORMAL")
	assert(CliffTypes.classify_surprise(-25) == CliffTypes.SurpriseNature.RELIEF, "S in [-40, -20) must be RELIEF")
	assert(CliffTypes.classify_surprise(-50) == CliffTypes.SurpriseNature.MIRACLE, "S < -40 must be MIRACLE")
	assert(CliffTypes.get_surprise_icon(CliffTypes.SurpriseNature.SHOCK) == "⚡⚡", "SHOCK icon should be ⚡⚡")
	assert(CliffTypes.get_surprise_icon(CliffTypes.SurpriseNature.RELIEF) == "🪂", "RELIEF icon should be 🪂")
	print("test_surprise_classification: ok")

func test_p_survie_forced() -> void:
	assert(abs(CliffMath.p_survie(false, 0.6) - 0.6) < 0.0001, "non-forced: raw viable mass")
	var pf = CliffMath.p_survie(true, 0.6)
	assert(abs(pf - 0.8) < 0.0001, "forced: miss probability halved (0.4 -> 0.2)")
	assert(CliffMath.p_survie(true, 1.0) == 1.0, "forced never lowers survival")
	print("test_p_survie_forced: ok")

func test_bait_semantics() -> void:
	assert(CliffMath.bait(0.70, 0.70) == 0.0, "tempting move = best move -> no bait")
	assert(CliffMath.bait(0.70, 0.67) == 0.0, "tempting move viable -> no bait")
	assert(abs(CliffMath.bait(0.70, 0.30) - 0.40) < 0.0001, "bait = real loss")
	assert(CliffMath.bait(1.0, -1.0) == 1.0, "bait clamped to 1")
	print("test_bait_semantics: ok")

func test_viable_ignores_unknown() -> void:
	var v = CliffMath.get_viable_indices([0.70, 0.69, 0.69], 0.70, [true, true, false])
	assert(v == [0, 1], "a bound-only move is never viable")
	print("test_viable_ignores_unknown: ok")

func test_horizon_no_regime_jump() -> void:
	# 5 et 7 demi-coups identiques : même pire fenêtre de 4.
	var p5 = CliffMath.p_survie_horizon_min([0.9, 0.5, 0.5, 0.9, 0.9], 4)
	var p7 = CliffMath.p_survie_horizon_min([0.9, 0.5, 0.5, 0.9, 0.9, 0.9, 0.9], 4)
	assert(abs(p5 - p7) < 0.0001, "no jump between line lengths")
	print("test_horizon_no_regime_jump: ok")
