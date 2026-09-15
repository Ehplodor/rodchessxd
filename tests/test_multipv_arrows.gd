extends SceneTree
## tests/test_multipv_arrows.gd — Test unitaire pour l'affichage multi-lignes et badges sur l'échiquier.

func _init() -> void:
	print("=== Test MultiPV Arrows & Badges on ChessBoard2D ===")
	await process_frame
	
	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	
	var board: ChessBoard2D = main.chess_board
	if board == null:
		printerr("FAIL: chess_board introuvable")
		quit(1)
		return
	
	# Simule une évaluation MultiPV avec 2 lignes
	var multipv_data = [
		{
			"rank": 1,
			"best_move": "e6f4",
			"pv": ["e6f4", "c4f7"],
			"depth": 15
		},
		{
			"rank": 2,
			"best_move": "g8h7",
			"pv": ["g8h7", "c4f7"],
			"depth": 15
		}
	]
	
	board.set_engine_lines_arrows(multipv_data, 15)
	
	if board.engine_lines_arrows.size() != 2:
		printerr("FAIL: nombre d'arcs attendu 2, obtenu %d" % board.engine_lines_arrows.size())
		quit(1)
		return
		
	var arr1 = board.engine_lines_arrows[0]
	var arr2 = board.engine_lines_arrows[1]
	
	if arr1.get("rank") != 1 or arr1.get("uci") != "e6f4":
		printerr("FAIL: données incorrectes pour ligne #1: %s" % str(arr1))
		quit(1)
		return
		
	if arr2.get("rank") != 2 or arr2.get("uci") != "g8h7":
		printerr("FAIL: données incorrectes pour ligne #2: %s" % str(arr2))
		quit(1)
		return
		
	print("  ok: 2 flèches enregistrées pour les 2 lignes moteur")
	print("  ok: rangs #1 et #2 correctement assignés")
	
	# Test réinitialisation sur coup joué
	board.set_best_move_arrow("")
	if not board.engine_lines_arrows.is_empty():
		printerr("FAIL: engine_lines_arrows non vidé après set_best_move_arrow('')")
		quit(1)
		return
		
	print("  ok: réinitialisation propre")
	print("=== TOUS LES TESTS MULTIPV SONT VALIDÉS AVEC SUCCÈS ===")
	quit(0)
