extends SceneTree

## Plan ELO avancé — Tests des points 1 (complexité), 2 (IPR Regan) et 4 (gestion du temps).
## Exécution : Godot headless --script tests/test_advanced_elo_model.gd

const GameAnalyzer = preload("res://src/engine/GameAnalyzer.gd")

func _init() -> void:
	print("--- Test du modèle ELO avancé : complexité, IPR Regan, gestion du temps ---")
	var analyzer = GameAnalyzer.new()

	# ── 1. Indice de complexité (point 1) ─────────────────────────────────────
	print("  -> Test 1: Indice de complexité positionnelle...")
	var cx_forced = MoveQualityService.move_complexity(1, false, -1.0)
	assert(absf(cx_forced - 0.25) < 0.001, "Coup légal unique (échec forcé) : C = 0.25")

	var cx_recap = MoveQualityService.move_complexity(30, true, -1.0)
	assert(absf(cx_recap - 0.35) < 0.001, "Recapture évidente : C = 0.35")

	var cx_jungle = MoveQualityService.move_complexity(30, false, 5.0)
	assert(absf(cx_jungle - 0.85) < 0.001, "Position plurielle (5 coups équivalents) : C = 0.85")

	var cx_unique = MoveQualityService.move_complexity(20, false, 15.0)
	assert(absf(cx_unique - 1.5) < 0.001, "Coup unique critique (Δ=15) : C = 1.5")

	var cx_hero = MoveQualityService.move_complexity(20, false, 90.0)
	assert(absf(cx_hero - 2.0) < 0.001, "Coup héroïque (Δ=90) : C plafonné à 2.0")
	print("    ✅ Seuils de complexité validés (forcé %.2f, recapture %.2f, pluriel %.2f, unique %.2f, héroïque %.2f)."
			% [cx_forced, cx_recap, cx_jungle, cx_unique, cx_hero])

	# ── 2. Extraction des deltas d'horloge (point 4) ─────────────────────────
	print("  -> Test 2: Extraction du temps passé par coup ([%%clk])...")
	# Séquence : w 120s → b 115s → w 100s → b 60s
	var moves_clock := []
	var c1 = ChessMove.new(); c1.color = ChessPiece.PieceColor.WHITE; c1.clock_sec = 120.0
	var c2 = ChessMove.new(); c2.color = ChessPiece.PieceColor.BLACK; c2.clock_sec = 115.0
	var c3 = ChessMove.new(); c3.color = ChessPiece.PieceColor.WHITE; c3.clock_sec = 100.0
	var c4 = ChessMove.new(); c4.color = ChessPiece.PieceColor.BLACK; c4.clock_sec = 60.0
	moves_clock = [c1, c2, c3, c4]
	var deltas = GameAnalyzer._extract_clock_deltas(moves_clock)
	assert(float(deltas[0]) < 0.0, "Premier coup blanc : temps inconnu (-1)")
	assert(float(deltas[1]) < 0.0, "Premier coup noir : temps inconnu (-1)")
	assert(absf(float(deltas[2]) - 20.0) < 0.001, "Coup blanc 2 : 120-100 = 20 s")
	assert(absf(float(deltas[3]) - 55.0) < 0.001, "Coup noir 2 : 115-60 = 55 s")
	# PGN sans %clk : tout à -1 (facteur temps neutre)
	var c5 = ChessMove.new(); c5.color = ChessPiece.PieceColor.WHITE; c5.clock_sec = -1.0
	var deltas_nc = GameAnalyzer._extract_clock_deltas([c5, c5])
	assert(float(deltas_nc[0]) < 0.0 and float(deltas_nc[1]) < 0.0, "Sans %clk : deltas inconnus")
	print("    ✅ Deltas d'horloge validés (chaîne par camp + PGN sans %clk neutre).")

	# ── 3. Estimateur IPR Regan (point 2) ────────────────────────────────────
	print("  -> Test 3: Solveur IPR (MLE, bornes et convergence)...")
	var start_ticks := Time.get_ticks_msec()
	# Gaffes massives (perte 40 win% par coup) → plancher ~300
	var evals_weak: Array[Dictionary] = []
	for i in range(40):
		evals_weak.append({"ply": i, "is_white": true, "is_theory": false,
				"winpct_loss": 40.0, "complexity": 1.0})
	var ipr_weak = analyzer._estimate_elo_regan_ipr(evals_weak, true)
	assert(ipr_weak["elo"] <= 400, "40 pertes de 40 win%% : IPR doit être au plancher (≤400), obtenu %d" % ipr_weak["elo"])
	# Jeu parfait (aucune perte) → plafond
	var evals_perfect: Array[Dictionary] = []
	for i in range(40):
		evals_perfect.append({"ply": i, "is_white": true, "is_theory": false,
				"winpct_loss": 0.0, "complexity": 1.0})
	var ipr_perfect = analyzer._estimate_elo_regan_ipr(evals_perfect, true)
	assert(ipr_perfect["elo"] >= 2800, "Jeu parfait : IPR au plafond (≥2800), obtenu %d" % ipr_perfect["elo"])
	# Niveau ~1500 : précision par coup ≈ 82% → perte moyenne ≈ 4.4 win%
	var evals_club: Array[Dictionary] = []
	for i in range(40):
		evals_club.append({"ply": i, "is_white": true, "is_theory": false,
				"winpct_loss": 4.4, "complexity": 1.0})
	var ipr_club = analyzer._estimate_elo_regan_ipr(evals_club, true)
	assert(absf(float(ipr_club["elo"]) - 1500.0) < 120.0, "Perte moy. 4.4 : IPR ≈ 1500 (±120), obtenu %d" % ipr_club["elo"])
	var elapsed_ms := Time.get_ticks_msec() - start_ticks
	assert(elapsed_ms < 300, "Solveur IPR trop lent : %d ms pour 3 résolutions" % elapsed_ms)
	# La théorie est exclue et la complexité pondère la MLE
	var evals_theory: Array[Dictionary] = []
	for i in range(10):
		evals_theory.append({"ply": i, "is_white": true, "is_theory": true, "winpct_loss": 50.0, "complexity": 1.0})
	var ipr_theory = analyzer._estimate_elo_regan_ipr(evals_theory, true)
	assert(ipr_theory["n"] == 0 and ipr_theory["elo"] == 1500, "Partie 100%% théorie : IPR neutre (1500)")
	print("    ✅ IPR validé (plancher %d, plafond %d, club %d, %d ms)." % [ipr_weak["elo"], ipr_perfect["elo"], ipr_club["elo"], elapsed_ms])

	# ── 4. Anti-trivialité : les recaptures évidentes ne font pas un Maître ──
	print("  -> Test 4: Effet anti-trivialité sur l'ELO synthétisé...")
	# 12 demi-coups parfaits mais TOUS triviaux (recaptures, C=0.35)
	var evals_trivial: Array[Dictionary] = []
	for i in range(12):
		evals_trivial.append({"ply": i, "is_white": i % 2 == 0, "is_theory": false,
				"score_cp": 20, "winpct_loss": 0.0, "complexity": 0.35, "time_spent_sec": -1.0})
	var acc_trivial = analyzer._calculate_caps_accuracy(evals_trivial, true)
	assert(acc_trivial > 99.0, "12 recaptures parfaites : précision ≈ 100%%, obtenue %.1f" % acc_trivial)
	var stat_trivial = analyzer._calculate_elo_statistics(evals_trivial, true, acc_trivial, 0.0,
			{"blunder": 0, "mistake": 0}, 12)
	print("    12 recaptures évidentes 100%% : ELO %d (Attendu: <= 1700, l'ancien modèle donnait ~2000)" % stat_trivial["elo"])
	assert(stat_trivial["elo"] <= 1700, "Anti-trivialité : 12 recaptures parfaites ne doivent PAS donner un Maître")
	# Même précision obtenue dans des positions complexes : mérite reconnu
	var evals_hard: Array[Dictionary] = []
	for i in range(12):
		evals_hard.append({"ply": i, "is_white": i % 2 == 0, "is_theory": false,
				"score_cp": 20, "winpct_loss": 0.0, "complexity": 2.0, "time_spent_sec": -1.0})
	var acc_hard = analyzer._calculate_caps_accuracy(evals_hard, true)
	var stat_hard = analyzer._calculate_elo_statistics(evals_hard, true, acc_hard, 0.0,
			{"blunder": 0, "mistake": 0}, 12)
	print("    12 coups complexes parfaits    : ELO %d ( Attendu: > %d)" % [stat_hard["elo"], stat_trivial["elo"]])
	assert(stat_hard["elo"] > stat_trivial["elo"], "Le mérite tactique en position complexe doit être récompensé")

	# ── 5. Gestion du temps (point 4) : bonus intuition, amortisseur d'hésitation ──
	print("  -> Test 5: Facteur temps et modulation de l'ELO...")
	assert(absf(GameAnalyzer._time_weight_factor(-1.0, 1.5, 60.0) - 1.0) < 0.001, "Sans horloge : facteur neutre 1.0")
	assert(absf(GameAnalyzer._time_weight_factor(10.0, 1.5, 60.0) - 1.1) < 0.001, "Intuition tactique (complexe, rapide) : 1.1")
	assert(absf(GameAnalyzer._time_weight_factor(200.0, 0.25, 60.0) - 0.9) < 0.001, "Hésitation sur l'évident : 0.9")
	assert(absf(GameAnalyzer._time_weight_factor(60.0, 1.0, 60.0) - 1.0) < 0.001, "Cas neutre : 1.0")
	# Une intuition tactique rapide dans une partie de 20 coups : +3 ELO (60/20)
	var evals_clock: Array[Dictionary] = []
	for i in range(20):
		evals_clock.append({"ply": i, "is_white": true, "is_theory": false,
				"score_cp": 20, "winpct_loss": 0.0, "complexity": 1.5, "time_spent_sec": 60.0})
	evals_clock[5]["time_spent_sec"] = 5.0 # coup complexe trouvé en 5 s (moy. 60 s)
	var tm = analyzer._compute_time_management(evals_clock, true, 20)
	assert(tm["has_clock"] == true, "Horloge détectée")
	assert(absf(float(tm["elo_delta"]) - 3.0) < 0.01, "Bonus intuition : 60 × 1/20 = +3 ELO")
	# Sans aucune donnée %clk : neutre
	var evals_noclock: Array[Dictionary] = []
	for i in range(20):
		evals_noclock.append({"ply": i, "is_white": true, "is_theory": false,
				"score_cp": 20, "winpct_loss": 0.0, "complexity": 1.0, "time_spent_sec": -1.0})
	var tm_nc = analyzer._compute_time_management(evals_noclock, true, 20)
	assert(tm_nc["has_clock"] == false and absf(float(tm_nc["elo_delta"])) < 0.001, "Sans %clk : modulation neutre")
	print("    ✅ Facteurs temps validés (bonus +%.1f, sans horloge neutre)." % float(tm["elo_delta"]))

	print("\n>>> MODÈLE ELO AVANCÉ (COMPLEXITÉ + IPR REGAN + TEMPS) VALIDÉ À 100%% AVEC SUCCÈS ! <<<")
	quit(0)
