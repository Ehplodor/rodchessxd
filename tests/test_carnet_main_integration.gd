extends SceneTree
## tests/test_carnet_main_integration.gd — branchement de LeCarnet dans Main (bouton 📓).

const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")

var _failures := 0
var _ran := false

func _init() -> void:
	print("--- Running Carnet <-> Main integration test ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	if root.get_node_or_null("DatabaseManager") == null:
		printerr("DatabaseManager autoload introuvable")
		quit(1)
		return true

	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)

	var top = main.top_bar if main.top_bar != null else main.get_node_or_null("MainScroll/VBox/TopBar")
	_check(top != null, "TopBar présente")
	var btn = top.get_node_or_null("BtnCarnet") if top != null else null
	_check(btn != null, "bouton 📓 ajouté à la TopBar")
	_check(main.carnet_overlay != null, "overlay carnet instancié")
	_check(main.carnet_presenter != null, "présentateur carnet instancié")
	if main.carnet_overlay != null:
		_check(not main.carnet_overlay.visible, "overlay caché au démarrage")

	if btn != null:
		btn.pressed.emit()
	if main.carnet_overlay != null:
		_check(main.carnet_overlay.visible, "overlay visible après appui")
		_check(main.carnet_overlay._tabs_box.get_child_count() == 3, "3 onglets dans l'overlay")
		main._close_carnet_overlay()
		_check(not main.carnet_overlay.visible, "overlay refermé")

	main.queue_free()
	CarnetProfiles.reset()
	if _failures == 0:
		print("ALL CARNET MAIN INTEGRATION TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CARNET MAIN INTEGRATION TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)
