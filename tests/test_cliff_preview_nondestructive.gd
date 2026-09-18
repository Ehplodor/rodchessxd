extends SceneTree
## tests/test_cliff_preview_nondestructive.gd — Garantit que l'aperçu CHESS-CLIFF
## n'altère jamais la partie réelle : l'historique des coups doit rester intact,
## sinon l'analyse classique (« 🔍 Analyser ») ne peut plus se lancer.

const ChessMove = preload("res://src/core/ChessMove.gd")
const ChessPiece = preload("res://src/core/ChessPiece.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- Cliff preview non-destructive test ---")
	await process_frame
	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.25).timeout

	var gc = root.get_node_or_null("GameController")
	_check(gc != null, "GameController présent")
	if gc == null:
		main.queue_free()
		printerr("CLIFF PREVIEW TESTS FAILED: %d" % (_failures + 1))
		quit(1)
		return

	gc.reset_to_initial()
	var pgn := "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7"
	_check(gc.load_pgn(pgn), "PGN chargé")
	var before: int = gc.game.move_history.size()
	_check(before == 10, "10 demi-coups enregistrés (obtenu %d)" % before)

	# --- Super Live : chaque pas affiche une position d'aperçu ---
	var preview_fen := "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
	main.is_cliff_live_active = true
	main._on_cliff_super_live_step(0, "e7e5", preview_fen, {})
	await process_frame
	_check(main.chess_board.is_previewing(), "aperçu actif après un pas Super Live")
	_check(gc.game.move_history.size() == before,
			"historique préservé pendant l'aperçu (%d/%d)" % [gc.game.move_history.size(), before])
	var e5: int = ChessMove.coord_to_square("e5")
	var piece: Dictionary = main.chess_board._preview_game.get_piece(e5)
	_check(piece.type == ChessPiece.Type.PAWN and piece.color == ChessPiece.PieceColor.BLACK,
			"l'échiquier affiche bien la position d'aperçu (pion noir en e5)")

	# --- Fin du Super Live : retour à la partie réelle, intacte ---
	main.is_cliff_live_active = false
	main._on_cliff_super_live_finished({})
	await process_frame
	_check(not main.chess_board.is_previewing(), "aperçu terminé après fin du Super Live")
	_check(gc.game.move_history.size() == before,
			"historique intact après fin (%d)" % gc.game.move_history.size())

	# --- Aperçu d'une position via la pastille Cliff (fiche) ---
	main._on_cliff_step_preview_requested(preview_fen, "e2e4")
	await process_frame
	_check(main.chess_board.is_previewing(), "aperçu actif via pastille Cliff")
	_check(gc.game.move_history.size() == before, "historique préservé via pastille Cliff")
	main.chess_board.clear_preview_fen()
	await process_frame
	_check(not main.chess_board.is_previewing(), "aperçu effacé")
	_check(gc.game.move_history.size() == before, "historique toujours intact après nettoyage")

	# --- L'analyse classique doit rester lançable ---
	_check(gc.game.move_history.size() > 0, "analyse classique possible (coups présents)")
	_check(main.analyzer != null and not main.analyzer.is_analyzing, "analyseur au repos")

	main.queue_free()
	if _failures == 0:
		print("ALL CLIFF PREVIEW NONDESTRUCTIVE TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF PREVIEW NONDESTRUCTIVE TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
