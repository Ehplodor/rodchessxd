extends SceneTree
## tests/test_modal_manager.gd — cycle de vie des modales (une seule à la fois).

const ModalManager = preload("res://src/ui/components/ModalManager.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- ModalManager tests ---")
	await process_frame

	var owner := Control.new()
	owner.name = "Owner"
	root.add_child(owner)
	var mgr := ModalManager.new(owner)
	_check(mgr.current == null, "aucune modale au départ")

	var m1 := AcceptDialog.new()
	m1.name = "M1"
	mgr.open(m1)
	_check(mgr.current == m1, "la modale ouverte devient courante")
	_check(owner.get_child_count() == 1, "la modale est enfant direct du propriétaire")
	_check(m1.visible, "la modale est visible")

	var m2 := AcceptDialog.new()
	m2.name = "M2"
	mgr.open(m2)
	_check(mgr.current == m2, "la nouvelle modale remplace la courante")
	_check(owner.get_child_count() == 2, "l'ancienne est libérée en différé")
	await process_frame
	_check(owner.get_child_count() == 1, "l'ancienne modale a été libérée")
	_check(not is_instance_valid(m1), "m1 détruite au frame suivant")

	# Ouverture invalide : sans effet.
	var before := mgr.current
	mgr.open(null)
	_check(mgr.current == before, "open(null) sans effet")

	owner.queue_free()
	await process_frame

	if _failures == 0:
		print("ALL MODAL MANAGER TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("MODAL MANAGER TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
