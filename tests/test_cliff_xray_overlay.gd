extends SceneTree
## tests/test_cliff_xray_overlay.gd — Calque Rayons X (meilleur coup + appât + mines).

const ChessBoard2D = preload("res://src/ui/components/ChessBoard2D.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- Cliff X-ray overlay tests ---")
	await process_frame
	var board = ChessBoard2D.new()
	root.add_child(board)
	board.size = Vector2(360, 360)
	await process_frame

	_check(not board.is_cliff_overlay_active(), "aucun calque au départ")

	board.set_cliff_overlay({
		"best_uci": "e2e4",
		"bait_uci": "d2d4",
		"mines": [{"sq": 27, "weight": 0.6}, {"sq": 20, "weight": 0.3}],
		"label": "Joué : e5 · Corniche · D=42"
	})
	await process_frame
	_check(board.is_cliff_overlay_active(), "calque actif après set_cliff_overlay")
	_check(str(board.cliff_overlay.get("bait_uci", "")) == "d2d4", "appât enregistré")
	_check((board.cliff_overlay.get("mines", []) as Array).size() == 2, "2 mines enregistrées")

	# Le nettoyage d'aperçu ne doit pas laisser le calque orphelin.
	board.set_preview_fen(ChessGame.INITIAL_FEN)
	board.clear_preview_fen()
	board.clear_cliff_overlay()
	await process_frame
	_check(not board.is_cliff_overlay_active(), "calque effacé proprement")

	board.queue_free()
	print("--- Cliff X-ray overlay : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF XRAY OVERLAY TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF XRAY OVERLAY TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
