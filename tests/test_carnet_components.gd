extends SceneTree
## tests/test_carnet_components.gd — Couche T3 : composants réutilisables (sans scène).

const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")
const CarnetProfileChip = preload("res://src/ui/carnet/components/CarnetProfileChip.gd")
const CarnetSyncBadge = preload("res://src/ui/carnet/components/CarnetSyncBadge.gd")
const CarnetMotifCard = preload("res://src/ui/carnet/components/CarnetMotifCard.gd")
const CarnetRadarPanel = preload("res://src/ui/carnet/components/CarnetRadarPanel.gd")

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
