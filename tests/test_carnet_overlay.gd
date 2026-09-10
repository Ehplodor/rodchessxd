extends SceneTree
## tests/test_carnet_overlay.gd — Couche T2 : overlay plein écran + onglets + session.

const CarnetPresenter = preload("res://src/ui/carnet/CarnetPresenter.gd")
const CarnetOverlay = preload("res://src/ui/carnet/CarnetOverlay.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")

var _failures := 0
var _db: Node = null
var _ran := false

func _init() -> void:
	print("--- Running CarnetOverlay (T2) test ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_db = root.get_node_or_null("DatabaseManager")
	if _db == null:
		printerr("DatabaseManager autoload introuvable")
		quit(1)
		return true
	CarnetProfiles.reset()

	var presenter: CarnetPresenter = CarnetPresenter.new()
	var overlay: CarnetOverlay = CarnetOverlay.new()
	root.add_child(overlay)
	presenter.create_profile("UI", "local", ["ui"])
	overlay.open(presenter)

	_test_structure(overlay, presenter)
	_test_tabs(overlay)
	_test_session(overlay, presenter)

	overlay.queue_free()
	CarnetProfiles.reset()
	if _failures == 0:
		print("ALL CARNET OVERLAY TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET OVERLAY TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _trainer_path(pid: String) -> String:
	return "user://library/carnets/profiles/%s/trainer.json" % pid

func _test_structure(overlay: CarnetOverlay, presenter: CarnetPresenter) -> void:
	_check(overlay.visible, "overlay visible après open")
	_check(overlay._title.text.contains("UI"), "titre avec le profil actif")
	_check(overlay._tabs_box.get_child_count() == 3, "3 onglets présents")
	_check(overlay._sync_badge.displayed_text().contains("à jour"), "badge de sync cohérent")
	_check(overlay._profile_row.get_child_count() >= 1, "chip de profil affiché")

func _test_tabs(overlay: CarnetOverlay) -> void:
	overlay.select_tab("analyse")
	_check(overlay._content.get_child_count() >= 1, "onglet Analyse construit")
	overlay.select_tab("sync")
	_check(overlay._content.get_child_count() >= 2, "onglet Sync construit")
	overlay.select_tab("carnet")
	_check(overlay._content.get_child_count() >= 1, "onglet Carnet construit")

func _test_session(overlay: CarnetOverlay, presenter: CarnetPresenter) -> void:
	var drills: Array = [
		{"drill_id": "d1", "reponse_uci": "e2e4", "piege_uci": "a2a3", "type": "trouve_le_coup", "motif": "m", "polarite": "négatif", "position": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"},
		{"drill_id": "d2", "reponse_uci": "d2d4", "piege_uci": "h2h4", "type": "choix_binaire", "motif": "m", "polarite": "négatif", "position": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"},
	]
	var trainer: Dictionary = _db.load_json(_trainer_path(presenter.profile_id))
	trainer["drills"] = drills
	_db.save_json_atomic(_trainer_path(presenter.profile_id), trainer)

	# Les options QCM sont construites depuis le bon coup et le piège.
	var opts := presenter.drill_options(drills[0])
	_check(opts.size() == 2, "2 options QCM")
	var has_correct := false
	for o in opts:
		if bool(o.get("correct", false)) and str(o.get("san", "")) != "":
			has_correct = true
	_check(has_correct, "le bon coup est étiqueté et converti en SAN")

	presenter.start_session(drills)
	overlay.select_tab("carnet")
	_check(overlay._content.get_child_count() >= 3, "séance affichée")

	var wrong := overlay.choose("a2a3")
	_check(not bool(wrong.get("correct", true)), "mauvais choix signalé par l'overlay")
	_check(overlay.grade(1), "notation après réponse")

	var right := overlay.choose("d2d4")
	_check(bool(right.get("correct", false)), "bon choix signalé")
	_check(overlay.grade(4), "2e notation")
	_check(presenter.is_session_done(), "séance terminée")

	overlay.select_tab("carnet")
	_check(overlay._content.get_child_count() >= 2, "écran de résumé affiché")
	presenter.end_session()
	_check(presenter.session.is_empty(), "séance refermée")
