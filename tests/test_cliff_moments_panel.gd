extends SceneTree
## tests/test_cliff_moments_panel.gd — Panneau « Moments clés » : cartes, point de vue, largeur.

const CliffMomentsPanel = preload("res://src/ui/components/CliffMomentsPanel.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _m(ply: int, white: bool, kind: int) -> Dictionary:
	return {"ply": ply, "is_white": white, "kind": kind, "san": "Qxf6+",
			"title": CliffTypes.MOMENT_TITLES[kind], "icon": CliffTypes.MOMENT_ICONS[kind],
			"text": "Un texte d'explication assez long pour devoir passer à la ligne sur un téléphone en portrait.",
			"best_uci": "d8f6", "played_uci": "d8f6", "fen_before": "x"}

func _init() -> void:
	print("--- CliffMomentsPanel tests ---")
	await process_frame
	var panel = CliffMomentsPanel.new()
	root.add_child(panel)
	await process_frame
	_check(not panel.visible, "masqué à vide")

	panel.show_progress("Tri des coups…", 3, 40)
	_check(panel.visible and panel._btn_stop.visible and panel._status_label.text.contains("3/40"), "progression + Stop")

	var report := {"cliff_version": 3, "screened": 34, "candidates": 6, "moments": [
		_m(20, true, CliffTypes.MomentKind.ONLY_FOUND),
		_m(31, false, CliffTypes.MomentKind.ONLY_MISSED),
		_m(33, false, CliffTypes.MomentKind.CARELESS),
	]}
	panel.set_report(report, false)
	await process_frame
	_check(not panel._btn_stop.visible, "Stop masqué à la fin")
	_check(panel._mine_box.get_child_count() == 2, "Noirs : 2 moments à soi")
	_check(panel._opp_box.get_child_count() == 1 and not panel._opp_box.visible, "adversaire : 1 carte, repliée")
	_check(panel._summary_label.text.contains("coup unique manqué") and panel._summary_label.text.contains("inattention"),
			"résumé Noirs : " + panel._summary_label.text)
	_check(panel._opp_toggle.text.contains("(1)"), "bascule adversaire comptée")

	panel.set_hero(true)
	await process_frame
	_check(panel._mine_box.get_child_count() == 1 and panel._opp_box.get_child_count() == 2, "vu des Blancs : cartes inversées")
	_check(panel._summary_label.text.contains("1 test réussi"), "résumé Blancs")

	var got := []
	panel.moment_selected.connect(func(m): got.append(m))
	var see: Button = panel._mine_box.get_child(0).get_child(0).get_child(2)
	see.pressed.emit()
	_check(got.size() == 1 and int(got[0]["ply"]) == 20, "« Voir » émet le moment")

	panel._opp_toggle.pressed.emit()
	await process_frame
	_check(panel._opp_box.visible, "section adversaire dépliable")
	_check(panel.get_combined_minimum_size().x <= 450.0,
			"largeur minimale ≤ 450 px (obtenu %.0f)" % panel.get_combined_minimum_size().x)

	panel.set_report({"moments": [], "screened": 10, "candidates": 0}, true)
	await process_frame
	_check(panel._mine_box.get_child_count() == 1 and not panel._opp_toggle.visible, "aucun moment : message, pas de section adversaire")

	panel.clear()
	_check(not panel.visible, "clear masque le panneau")
	panel.queue_free()
	print("--- CliffMomentsPanel : %d échec(s) ---" % _failures)
	if _failures == 0:
		print("ALL CLIFF MOMENTS PANEL TESTS PASSED SUCCESSFULLY!")
	quit(0 if _failures == 0 else 1)
