extends SceneTree
## tests/test_cliff_live_dock.gd — Cockpit Super Live : ruban, synthèse, récit.

const CliffLiveDock = preload("res://src/ui/components/CliffLiveDock.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _fake_step(i: int, piste: int) -> Dictionary:
	return {
		"step": i, "move_uci": "e2e4", "san": "e%d" % (i + 1),
		"fen_after": "FEN_%d" % i, "is_white": i % 2 == 0,
		"piste": piste, "indice_d": 10 + i * 20, "delta_chute": 0.05 * i,
		"bait": 0.3 if i == 1 else 0.0, "p_survie": 0.8 - 0.1 * i,
		"best_move": "e2e4", "bait_move_uci": "d2d4", "mines": [{"sq": 27, "weight": 0.5}]
	}

func _init() -> void:
	print("--- CliffLiveDock tests ---")
	await process_frame
	var dock = CliffLiveDock.new()
	root.add_child(dock)
	await process_frame

	_check(not dock.visible, "dock masqué à vide")

	var report := {
		"semantics": CliffTypes.SEMANTICS,
		"summary_white": {"global_piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 43,
				"p_survie_ligne": 0.1, "max_delta_chute": 0.2, "max_bait": 0.3},
		"summary_black": {"global_piste": CliffTypes.Piste.CHEMIN, "indice_d": 20,
				"p_survie_ligne": 0.5, "max_delta_chute": 0.05, "max_bait": 0.1},
		"plies": [_fake_step(0, CliffTypes.Piste.CHAMP_DE_MINES),
				_fake_step(1, CliffTypes.Piste.CORNICHE),
				_fake_step(2, CliffTypes.Piste.AUTOROUTE)]
	}
	dock.set_report(report)
	await process_frame

	_check(dock.visible, "dock visible après rapport")
	_check(dock._chips.size() == 3, "ruban : 3 pastilles")
	_check(dock._summary_label.text.contains("D=43") and dock._summary_label.text.contains("D=20"),
			"synthèse une ligne par camp")
	_check(dock._narrative.text != "", "récit rempli")
	_check(dock.get_combined_minimum_size().x <= 450.0,
			"pas de largeur minimale > 450 px (obtenu %.0f)" % dock.get_combined_minimum_size().x)

	# Interaction : un tap sur une pastille émet step_selected(idx, fen, uci).
	var captured := []
	dock.step_selected.connect(func(i: int, fen: String, uci: String):
		captured.append([i, fen, uci])
	)
	dock._chips[1].pressed.emit()
	_check(captured.size() == 1 and int(captured[0][0]) == 1, "tap pastille émet l'index")
	if captured.size() == 1:
		_check(str(captured[0][1]) == "FEN_1", "tap pastille émet le FEN")
		_check(str(captured[0][2]) == "e2e4", "tap pastille émet l'UCI")
	_check(dock._current_step == 1 and dock._narrative.text.begins_with("👉"), "pas courant expliqué")

	dock.show_computing(2, 5)
	_check(dock._progress.visible and int(dock._progress.value) == 2 and dock._btn_stop.visible, "progression n/N + Stop visible")

	dock.set_step(_fake_step(3, CliffTypes.Piste.FIL_DU_RASOIR))
	_check(dock._chips.size() == 4, "pastille ajoutée en direct")

	dock.clear()
	_check(not dock.visible and dock._chips.is_empty() and not dock._btn_stop.visible, "clear remet à zéro")

	dock.queue_free()
	print("--- CliffLiveDock : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF LIVE DOCK TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF LIVE DOCK TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
