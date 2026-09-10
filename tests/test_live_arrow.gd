extends SceneTree

## Test de non-régression : la flèche du meilleur coup est liée au FEN de la
## position affichée. Un rafraîchissement graphique ne doit pas l'effacer tant
## que la position n'a pas changé (correctif flèches Live desktop).
func _init() -> void:
	print("[TEST] --- Test flèche du meilleur coup liée à la position (Live) ---")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.2).timeout

	# Neutralise le moteur Live pour un test déterministe.
	var gc = root.get_node_or_null("GameController")
	var eng = root.get_node_or_null("EngineManager")
	assert(gc != null, "GameController doit être accessible")
	main_node.live_eval_enabled = false
	if eng != null:
		eng.stop_evaluation()
	await create_timer(0.1).timeout

	var board = main_node.chess_board
	assert(board != null, "Le plateau ChessBoard2D doit être présent dans Main.tscn")
	assert(board.has_method("set_best_move_arrow"), "Le plateau doit exposer set_best_move_arrow")

	var fen_start := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	assert(gc.load_fen(fen_start), "Le FEN de départ doit se charger")
	await create_timer(0.05).timeout

	board.set_best_move_arrow("e2e4", 12)
	assert(board.best_move_arrow_from != -1 and board.best_move_arrow_to != -1,
		"La flèche doit être posée après set_best_move_arrow")

	# Un rafraîchissement à position identique ne doit PAS effacer la flèche.
	board.reset_board_visuals()
	assert(board.best_move_arrow_from != -1 and board.best_move_arrow_to != -1,
		"La flèche doit survivre à un rafraîchissement à FEN identique")
	print("  -> Flèche conservée après rafraîchissement à FEN identique ✓")

	# Un changement de position doit effacer la flèche devenue obsolète.
	var fen_changed := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1"
	assert(gc.load_fen(fen_changed), "Le FEN modifié doit se charger")
	board.reset_board_visuals()
	assert(board.best_move_arrow_from == -1,
		"La flèche doit être effacée quand la position a changé")
	print("  -> Flèche effacée après changement de position ✓")

	main_node.queue_free()
	print("[TEST] --- TEST FLÈCHE LIVE RÉUSSI (100% OK) ! ---")
	quit(0)
