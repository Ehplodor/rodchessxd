extends SceneTree
## tests/test_carnet_overlay.gd — Couche T2 : overlay plein écran + onglets + session.
## Version étendue : nouveaux comportements Sync (profils, liste parties, import).

const CarnetPresenter = preload("res://src/ui/carnet/CarnetPresenter.gd")
const CarnetOverlay = preload("res://src/ui/carnet/CarnetOverlay.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")
const CarnetProfileEditorModal = preload("res://src/ui/carnet/components/CarnetProfileEditorModal.gd")
const CarnetGameListItem = preload("res://src/ui/carnet/components/CarnetGameListItem.gd")
const CarnetImportPgnModal = preload("res://src/ui/carnet/components/CarnetImportPgnModal.gd")

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
	_test_sync_tab_structure(overlay)
	_test_profile_chip_context(overlay, presenter)
	_test_games_list_and_filters(overlay, presenter)

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

# ── Tests structure existants ───────────────────────────────────────────────────

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

	var wrong: Dictionary = overlay.choose("a2a3")
	_check(not bool(wrong.get("correct", true)), "mauvais choix signalé par l'overlay")
	_check(overlay.grade(1), "notation après réponse")

	var right: Dictionary = overlay.choose("d2d4")
	_check(bool(right.get("correct", false)), "bon choix signalé")
	_check(overlay.grade(4), "2e notation")
	_check(presenter.is_session_done(), "séance terminée")

	overlay.select_tab("carnet")
	_check(overlay._content.get_child_count() >= 2, "écran de résumé affiché")
	presenter.end_session()
	_check(presenter.session.is_empty(), "séance refermée")

# ── Tests onglet Sync enrichi ───────────────────────────────────────────────────

func _test_sync_tab_structure(overlay: CarnetOverlay) -> void:
	overlay.select_tab("sync")

	var has_add_btn := false
	for child in overlay._profile_row.get_children():
		if child is Button and str(child.text) == "+":
			has_add_btn = true
			break
	_check(has_add_btn, "bouton '+' de création de profil présent")

	var found := _find_buttons_in(overlay._content)
	_check(found.has("import_pgn"), "bouton 'Importer PGN' présent dans Sync")
	_check(found.has("import_chesscom"), "bouton '🌐 Chess.com' présent dans Sync (stub)")

	_check(overlay._games_list != null, "_games_list initialisé dans l'overlay")
	_check(overlay._filter_group != null, "_filter_group initialisé dans l'overlay")

	var filter_count := 0
	if overlay._filter_group is ButtonGroup:
		for btn in overlay._filter_group.get_buttons():
			filter_count += 1
	_check(filter_count >= 4, "4 filtres de liste de parties présents (%d trouvés)" % filter_count)

func _find_buttons_in(node: Node) -> Dictionary:
	var out := {}
	for child in node.get_children():
		if child is Button:
			var btn_text := str(child.text)
			if btn_text == "📥 PGN":
				out["import_pgn"] = true
			if btn_text == "🌐 Chess.com":
				out["import_chesscom"] = true
		var sub := _find_buttons_in(child)
		if sub.has("import_pgn"):
			out["import_pgn"] = true
		if sub.has("import_chesscom"):
			out["import_chesscom"] = true
	return out

# ── Tests menu contextuel sur puce profil ──────────────────────────────────────

func _test_profile_chip_context(overlay: CarnetOverlay, presenter: CarnetPresenter) -> void:
	overlay.select_tab("sync")

	var chip: CarnetProfileChip = null
	for child in overlay._profile_row.get_children():
		if child is CarnetProfileChip:
			chip = child
			break
	_check(chip != null, "chip de profil trouvé pour test menu contexte")

	if chip == null:
		return

	overlay._on_profile_context_menu(chip.profile_id, Vector2(100, 100))
	_check(overlay._profile_context_menu != null, "overlay construit un PopupMenu pour le contexte profil")

# ── Tests liste parties et filtres ─────────────────────────────────────────────

func _test_games_list_and_filters(overlay: CarnetOverlay, presenter: CarnetPresenter) -> void:
	overlay.select_tab("sync")

	var pgn := """[Event "OverlayTest"]
[White "OverlayUI"]
[Black "Opponent"]
[Date "2026.08.23"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0"""
	var gid: String = _db.record_pgn_game(pgn, "pgn_import")
	var pid := presenter.create_profile("OverlayProfile", "local", ["overlayui"])
	presenter.refresh_sync()

	overlay._refresh_games_list()

	var has_game_item := false
	for child in overlay._games_list.get_children():
		if child is CarnetGameListItem:
			has_game_item = true
			break
	_check(has_game_item, "CarnetGameListItem présent dans la liste après import")

	_db.delete_game(gid)
