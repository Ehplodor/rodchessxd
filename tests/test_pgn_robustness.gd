extends SceneTree
## tests/test_pgn_robustness.gd — import/export PGN : multi-parties, commentaires,
## en-têtes échappés, départ Noirs, roque « 0-0 », coups illisibles.

const ChessGame = preload("res://src/core/ChessGame.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- PGN robustness tests ---")

	# 1. Multi-parties : les en-têtes de la 2e partie n'écrasent pas la 1re.
	var g := ChessGame.new()
	var multi := '[White "Alice"]\n[Result "1-0"]\n\n1. e4 e5 1-0\n\n[White "Bob"]\n[FEN "8/8/8/8/8/8/8/K6k w - - 0 1"]\n\n1. Kb1 *'
	_check(g.load_pgn(multi), "multi-parties chargé")
	_check(g.pgn_headers.get("White") == "Alice", "en-tête de la 1re partie conservé")
	_check(not g.pgn_headers.has("FEN") and g.move_history.size() == 2, "FEN de la 2e partie ignorée")

	# 2. En-têtes non réinitialisés entre deux imports.
	var g2 := ChessGame.new()
	g2.load_pgn('[FEN "8/8/8/8/8/8/8/K6k w - - 0 1"]\n\n1. Kb1 *')
	g2.load_pgn("1. d4 d5 *")
	_check(g2.move_history.size() == 2 and not g2.pgn_headers.has("FEN"), "import suivant repart de la position initiale")

	# 3. Commentaires « ; » jusqu'à la fin de ligne et accolades.
	var g3 := ChessGame.new()
	_check(g3.load_pgn("1. e4 ; commentaire Nf3 d4\ne5 {note Nc3} 2. Nf3 *"), "commentaires chargés")
	_check(g3.move_history.size() == 3 and g3.pgn_errors.is_empty(), "; ignoré jusqu'à la fin de ligne (3 coups)")

	# 4. Guillemets échappés dans une valeur d'en-tête, aller-retour export/import.
	var g4 := ChessGame.new()
	g4.load_pgn('[Event "Open \\"Rapide\\""]\n\n1. e4 *')
	_check(g4.pgn_headers.get("Event") == 'Open "Rapide"', "guillemets échappés conservés")
	var g4b := ChessGame.new()
	g4b.load_pgn(g4.export_pgn())
	_check(g4b.pgn_headers.get("Event") == 'Open "Rapide"', "aller-retour export/import")

	# 5. Roque noté 0-0.
	var g5 := ChessGame.new()
	g5.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. 0-0 *")
	_check(g5.move_history.size() == 7 and g5.pgn_errors.is_empty(), "roque 0-0 reconnu")

	# 6. Départ Noirs : numérotation et export.
	var g6 := ChessGame.new()
	g6.load_pgn('[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n\n1... e5 2. Nf3 *')
	_check(g6.move_history.size() == 2, "départ Noirs : 2 coups chargés")
	_check(not g6.ply_info(0)["is_white"] and g6.ply_info(0)["move_number"] == 1, "ply 0 = 1... (Noirs)")
	_check(g6.ply_info(1)["is_white"] and g6.ply_info(1)["move_number"] == 2, "ply 1 = 2. (Blancs)")
	_check(g6.export_pgn().contains("1... e5 2. Nf3"), "export : « 1... e5 2. Nf3 »")

	# 7. Coup illisible : arrêt et diagnostic ; texte sans aucun coup valide → échec.
	var g7 := ChessGame.new()
	_check(g7.load_pgn("1. e4 e5 2. Zz9 Nc6 *"), "partie partielle conservée")
	_check(g7.move_history.size() == 2 and g7.pgn_errors.size() == 1, "arrêt au premier coup illisible")
	var g8 := ChessGame.new()
	_check(not g8.load_pgn("1. Zz9 *"), "aucun coup valide → échec")
	var g9 := ChessGame.new()
	_check(g9.load_pgn("1. e4 {non fermé") and g9.move_history.size() == 1, "accolade non fermée : coups antérieurs conservés")
	_check(not g9.pgn_errors.is_empty(), "accolade non fermée signalée")

	print("--- PGN robustness : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL PGN ROBUSTNESS TESTS PASSED SUCCESSFULLY!")
	quit(0 if _failures == 0 else 1)
