extends SceneTree
## Tests P0/P1 : mat, classification win%, brillant/GREAT/MISS, ouverture, motifs, phases.

func _init() -> void:
	print("[TEST] Qualité des coups, mat, ouvertures, motifs et phases...")
	await create_timer(0.1).timeout

	# --- 1. EvalFormatter : mat vs centipions ---
	print("  -> Test 1: Formatage des évaluations (mat / pions)...")
	assert(EvalFormatter.format_cp_mate(140) == "+1.4", "140 cp doit donner +1.4")
	assert(EvalFormatter.format_cp_mate(-60) == "-0.6", "-60 cp doit donner -0.6")
	assert(EvalFormatter.format_cp_mate(10000, 3) == "M3", "Mat 3 doit donner M3")
	assert(EvalFormatter.format_cp_mate(-10000, -2) == "-M2", "Mat -2 doit donner -M2")
	assert(EvalFormatter.is_mate(10000, 0), "10000 cp doit être reconnu comme mat")
	assert(not EvalFormatter.is_mate(300, 0), "300 cp n'est pas un mat")
	print("    OK")

	# --- 2. Classification par perte de win% ---
	print("  -> Test 2: Classification win% (blunder, miss, imprécision)...")
	# Coup le meilleur -> BEST
	assert(MoveQualityService.classify("e2e4", "e2e4", 20, 20, 0, true) == ChessMove.Quality.BEST, "Meilleur coup = BEST")
	# Position égale, grosse perte -> BLUNDER
	var q_std := MoveQualityService.classify("h2h3", "e2e4", 20, -500, 520, true)
	assert(q_std == ChessMove.Quality.BLUNDER, "Grosse perte en position égale = BLUNDER")
	# Position gagnante (+8), grosse perte -> MISS (occasion gâchée)
	var q_miss := MoveQualityService.classify("h2h3", "e2e4", 800, 100, 700, true)
	assert(q_miss == ChessMove.Quality.MISS, "Occasion de gain gâchée = MISS")
	# Perte modérée -> MISTAKE / INACCURACY
	assert(MoveQualityService.classify("h2h3", "e2e4", 100, -200, 300, true) == ChessMove.Quality.MISTAKE, "Perte moyenne = MISTAKE")
	# Brillant : meilleur coup + sacrifice + position non gagnée d'avance
	var q_brill := MoveQualityService.classify("f3f7", "f3f7", 30, 60, 0, true, true)
	assert(q_brill == ChessMove.Quality.BRILLIANT, "Sacrifice gagnant = BRILLIANT")
	# Pas brillant si pas de sacrifice
	assert(MoveQualityService.classify("f3f7", "f3f7", 30, 60, 0, true, false) != ChessMove.Quality.BRILLIANT, "Sans sacrifice, pas de BRILLIANT")
	# GREAT : meilleur coup, 2e ligne nettement moins bonne
	var q_great := MoveQualityService.classify("e2e4", "e2e4", 40, 40, 0, true, false, -400)
	assert(q_great == ChessMove.Quality.GREAT, "Seul coup préservant le résultat = GREAT")
	print("    OK")

	# --- 3. Détection de sacrifice ---
	print("  -> Test 3: Détection de sacrifice...")
	# Dame blanche prend d5 défendu par c6 : perte nette de la dame.
	var sac_fen := "4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1"
	assert(MoveQualityService.is_sacrifice(sac_fen, "d1d5", ["d1d5", "c6d5"]), "Qxd5 cxd5 doit être un sacrifice")
	assert(not MoveQualityService.is_sacrifice(sac_fen, "d1d2", ["d1d2"]), "Un simple recul de dame n'est pas un sacrifice")
	print("    OK")

	# --- 4. Motifs tactiques ---
	print("  -> Test 4: Détection de motifs (fourchette royale)...")
	var fork_fen := "r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1"
	var motifs := TacticalMotifDetector.detect(fork_fen, "b5c7", ["b5c7"])
	assert(motifs.has("Échec"), "Nc7+ doit donner Échec")
	assert(motifs.has("Fourchette royale"), "Nc7+ attaquant roi et tour = Fourchette royale")
	print("    OK (%s)" % ", ".join(motifs))

	# --- 5. Table d'ouvertures ---
	print("  -> Test 5: Identification d'ouverture (ECO)...")
	var ruy := OpeningBook.identify(["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"])
	assert(ruy["eco"] == "C60", "Ruy Lopez attendu C60, obtenu %s" % ruy["eco"])
	assert(ruy["out_of_book_ply"] == 5, "Ruy Lopez : 5 plies de théorie")
	var unknown := OpeningBook.identify(["a2a3", "a7a6"])
	assert(unknown["out_of_book_ply"] == 0, "Suite inconnue : aucune théorie")
	print("    OK")

	# --- 6. Phases de partie ---
	print("  -> Test 6: Classification des phases...")
	assert(not GamePhaseService.is_endgame_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"), "Position initiale = pas finale")
	assert(GamePhaseService.is_endgame_fen("8/8/4k3/8/8/4K3/8/8 w - - 0 1"), "Rois seuls = finale")
	assert(GamePhaseService.phase_for("8/8/4k3/8/8/4K3/8/8 w - - 0 1", 40, 8) == "endgame", "Ply 40 rois seuls = finale")
	assert(GamePhaseService.phase_for(ChessGame.INITIAL_FEN, 2, 0) == "opening", "Début = ouverture")
	print("    OK")

	# --- 7. Export PGN annoté (NAG) ---
	print("  -> Test 7: Export PGN annoté...")
	var game := ChessGame.new()
	game.load_pgn("1. e4 e5 2. Nf3")
	game.move_history[0].quality = ChessMove.Quality.BRILLIANT
	game.move_history[0].coach_explanation = "Coup clé"
	var pgn := game.export_pgn(true)
	assert(pgn.contains("e4 $3"), "Le PGN annoté doit contenir le NAG $3 pour un brillant")
	assert(pgn.contains("{Coup clé}"), "Le PGN annoté doit contenir le commentaire du coach")
	assert(not game.export_pgn(false).contains("$3"), "Le PGN simple ne doit pas contenir de NAG")
	print("    OK")

	# --- 8. Comparaison classification : mat terminal cohérent ---
	print("  -> Test 8: Cohérence mat/perspective...")
	assert(MoveQualityService.win_for(0, true) == 50.0, "Position égale = 50% pour les Blancs")
	assert(MoveQualityService.win_for(10000, false) == 0.0, "Mat blancs = 0% pour les Noirs")
	assert(MoveQualityService.win_for(10000, true) == 100.0, "Mat blancs = 100% pour les Blancs")
	print("    OK")

	print("\nTOUS LES TESTS QUALITÉ / OUVERTURES / MOTIFS SONT VALIDÉS.")
	quit(0)
