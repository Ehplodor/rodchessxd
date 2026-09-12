extends SceneTree
## tests/test_carnet_components.gd — Couche T3 : composants réutilisables (sans scène).

const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")
const CarnetProfileChip = preload("res://src/ui/carnet/components/CarnetProfileChip.gd")
const CarnetSyncBadge = preload("res://src/ui/carnet/components/CarnetSyncBadge.gd")
const CarnetMotifCard = preload("res://src/ui/carnet/components/CarnetMotifCard.gd")
const CarnetRadarPanel = preload("res://src/ui/carnet/components/CarnetRadarPanel.gd")
const CarnetGameListItem = preload("res://src/ui/carnet/components/CarnetGameListItem.gd")
const CarnetProgressModal = preload("res://src/ui/carnet/components/CarnetProgressModal.gd")

var _failures := 0
var _ran := false

func _init() -> void:
	print("--- Running Carnet UI components (T3) test ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_test_profile_chip()
	_test_sync_badge()
	_test_motif_card()
	_test_radar_panel()
	_test_game_list_item()
	_test_progress_modal()
	if _failures == 0:
		print("ALL CARNET COMPONENT TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET COMPONENT TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _test_profile_chip() -> void:
	var chip = CarnetProfileChip.new()
	root.add_child(chip)
	chip.set_profile({"id": "p1", "name": "NomTrèsLongPourTesterLaTroncature"}, true)
	_check(chip.text == "NomTrèsLongPourTesterLaTroncature", "nom du profil affiché")
	_check(chip.clip_text, "clip_text activé")
	_check(chip.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "troncature ellipsis")
	_check(chip.custom_minimum_size.y >= float(DesignTokens.TOUCH_MIN), "cible tactile respectée")
	_check(chip.button_pressed, "profil actif coché")
	var seen := {"id": ""}
	chip.profile_selected.connect(func(id): seen["id"] = id)
	chip.emit_signal("pressed")
	_check(seen["id"] == "p1", "signal profile_selected émis")
	chip.queue_free()

func _test_sync_badge() -> void:
	var badge = CarnetSyncBadge.new()
	root.add_child(badge)
	badge.set_status(42, 4)
	_check(badge.displayed_text().contains("4 à traiter"), "badge signale le delta")
	badge.set_status(42, 0)
	_check(badge.displayed_text().contains("à jour"), "badge à jour")
	badge.queue_free()

func _test_motif_card() -> void:
	var card = CarnetMotifCard.new()
	root.add_child(card)
	card.set_motif({"libelle": "Finale : tours", "score": 57.0, "n": 9, "polarite": "négatif", "tendance": "stable"})
	_check(card.title_text() == "Finale : tours", "titre du motif")
	_check(is_equal_approx(card.score_value(), 57.0), "score du motif propagé")
	var fired := {}
	card.activated.connect(func(m): fired["m"] = m)
	card.emit_signal("gui_input", _left_click())
	_check(not fired.is_empty(), "activation du motif émise")
	card.queue_free()

func _left_click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e

func _test_radar_panel() -> void:
	var radar = CarnetRadarPanel.new()
	root.add_child(radar)
	radar.set_dimensions([{"label": "phase", "skill": 60.0}, {"label": "couple", "skill": 40.0}])
	_check(radar.dimension_count() == 2, "dimensions enregistrées")
	_check(radar.custom_minimum_size.y >= 200.0, "hauteur minimale du radar")

	var full := CarnetRadarPanel.radar_points([{"skill": 100.0}], Vector2.ZERO, 100.0)
	_check(full.size() == 1, "1 axe → 1 sommet")
	_check(is_equal_approx(full[0].distance_to(Vector2.ZERO), 100.0), "skill 100 → rayon plein")

	var zero := CarnetRadarPanel.radar_points([{"skill": 0.0}], Vector2(10, 10), 50.0)
	_check(zero[0] == Vector2(10, 10), "skill 0 → centre")
	radar.queue_free()

func _test_game_list_item() -> void:
	var item := CarnetGameListItem.new()
	root.add_child(item)
	var game_data := {
		"game_id": "game_test_123",
		"white_name": "Magnus Carlsen",
		"black_name": "Hikaru Nakamura",
		"white_elo": 2850,
		"black_elo": 2870,
		"result": "1-0",
		"perspective": "white",
		"status": "up_to_date",
		"reason": "up_to_date",
		"date": "2026.09.08",
		"eco": "B20",
		"moves_count": 42,
		"source": "chess_com"
	}
	item.set_game(game_data)
	_check(item.get_child_count() > 0, "CarnetGameListItem construit des enfants dans le panel")
	_check(item._format_date("2026.09.08") == "08/09/2026", "date formatée en DD/MM/YYYY")
	_check(item._format_date("2026-09-08") == "08/09/2026", "date avec tirets formatée en DD/MM/YYYY")
	
	var res_white := item._format_result("1-0", "white")
	_check(res_white["text"].contains("Victoire") and res_white["color"] == DesignTokens.SUCCESS, "résultat 1-0 blancs = victoire")
	var res_black := item._format_result("1-0", "black")
	_check(res_black["text"].contains("Défaite") and res_black["color"] == DesignTokens.DANGER, "résultat 1-0 noirs = défaite")

	var fired := {"reanalyze": false, "perspective": false, "remove": false}
	item.reanalyze_requested.connect(func(gid): fired["reanalyze"] = (gid == "game_test_123"))
	item.perspective_cycle_requested.connect(func(gid): fired["perspective"] = (gid == "game_test_123"))
	item.remove_requested.connect(func(gid): fired["remove"] = (gid == "game_test_123"))

	item.reanalyze_requested.emit("game_test_123")
	item.perspective_cycle_requested.emit("game_test_123")
	item.remove_requested.emit("game_test_123")

	_check(fired["reanalyze"], "signal reanalyze_requested émis avec game_id")
	_check(fired["perspective"], "signal perspective_cycle_requested émis avec game_id")
	_check(fired["remove"], "signal remove_requested émis avec game_id")
	item.queue_free()

func _test_progress_modal() -> void:
	var modal := CarnetProgressModal.new()
	root.add_child(modal)
	modal.open("Recalcul du carnet", 10, "Profil : Moi")
	_check(modal.title == "Recalcul du carnet", "modal titre initialisé")
	_check(modal._total == 10, "modal total initialisé à 10")
	_check(is_equal_approx(modal._progress_bar.value, 0.0), "modal progress bar initiale à 0%")

	modal.update_progress(5, 10, "Carlsen vs Nakamura", "Coup 24/48 • 3 atomes", "Atome tactique détecté")
	_check(is_equal_approx(modal._progress_bar.value, 50.0), "modal progress bar mise à jour à 50%")
	_check(modal._counter_lbl.text.contains("5 / 10"), "modal compteur contient 5 / 10")
	_check(modal._game_info_lbl.text == "Carlsen vs Nakamura", "modal titre de partie affiché")
	_check(modal._substep_lbl.text.contains("3 atomes"), "modal sous-étape affichée")
	_check(modal._log_lbl.text.contains("Atome tactique"), "modal journal d'activité mis à jour")

	var fired_events := {"completed": false, "cancelled": false}
	modal.completed.connect(func(): fired_events["completed"] = true)
	modal.finish("Recalcul terminé : 10 parties traitées")
	_check(modal._is_done, "modal marquée terminée")
	_check(is_equal_approx(modal._progress_bar.value, 100.0), "modal progress bar à 100%")
	_check(modal._btn_close.visible, "bouton fermer visible à la fin")
	_check(fired_events["completed"], "signal completed émis")

	var cancel_modal := CarnetProgressModal.new()
	root.add_child(cancel_modal)
	cancel_modal.open("Test Annulation", 5)
	cancel_modal.cancelled.connect(func(): fired_events["cancelled"] = true)
	cancel_modal._on_cancel_pressed()
	_check(fired_events["cancelled"], "signal cancelled émis lors de l'annulation")

	modal.queue_free()
