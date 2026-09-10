extends SceneTree
## tests/test_ui_overflow.gd — Diagnostique le débordement horizontal à 360 px de large
## (smartphone étroit). Échoue si un contrôle impose une largeur minimale > viewport.

var _failures := 0
var _ran := false

func _init() -> void:
	print("--- Running UI overflow diagnostic (360x800) ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	root.size = Vector2i(360, 800)
	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)
	var width := float(root.size.x)

	var offenders: Array = []
	_collect_offenders(main, width, offenders)
	offenders.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	_check(offenders.is_empty(), "aucun contrôle ne dépasse %.0f px (%d trouvés)" % [width, offenders.size()])
	for o in offenders.slice(0, 15):
		printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

	# Bouton Carnet intégré au style de la barre du haut.
	var btn = main.get_node_or_null("VBox/TopBar/BtnCarnet")
	_check(btn != null, "bouton Carnet présent")
	if btn != null:
		_check(btn.has_theme_stylebox_override("normal"), "bouton Carnet stylé comme les autres")

	# Les boutons-icônes (emoji) ne doivent jamais être tronqués, sinon leur libellé disparaît.
	var flip = main.get_node_or_null("VBox/TopBar/BtnFlip")
	_check(flip != null and not flip.clip_text, "bouton-icône de la barre non tronqué (libellé préservé)")

	# Ouverture du Carnet : z-order au-dessus de l'échiquier + pas de débordement.
	main._open_carnet_overlay()
	if main.carnet_overlay != null:
		_check(main.carnet_overlay.z_index >= 200, "overlay Carnet au-dessus des pièces")
		_check(not main.carnet_overlay.z_as_relative, "z_index absolu (z_as_relative = false)")
	offenders.clear()
	_collect_offenders(main, width, offenders)
	_check(offenders.is_empty(), "Carnet ouvert : aucun débordement")
	main._close_carnet_overlay()

	# Ouverture de l'Analyse : pas de débordement.
	main._open_analyse_overlay()
	offenders.clear()
	_collect_offenders(main, width, offenders)
	_check(offenders.is_empty(), "Analyse ouverte : aucun débordement")
	for o in offenders.slice(0, 10):
		printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

	main.queue_free()
	if _failures == 0:
		print("UI OVERFLOW CHECK PASSED SUCCESSFULLY!")
	else:
		printerr("UI OVERFLOW CHECK FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _collect_offenders(node: Node, width: float, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var w := (child as Control).get_combined_minimum_size().x
			if w > width + 0.5:
				out.append({"w": w, "path": str(child.get_path())})
		_collect_offenders(child, width, out)
