extends Node
## DragScroller — défilement tactile universel.
## Problème : une liste remplie de boutons ne peut pas défiler au doigt avec le
## ScrollContainer seul (les boutons capturent le toucher), et l'ascenseur est
## difficile à atteindre. Ici : TAP = clic (le bouton reçoit l'événement), GLISSÉ
## au-delà d'un deadzone = défilement (l'événement est consommé, pas de clic).
## Appliqué à tous les ScrollContainer enregistrés via DesignTokens.touch_scroll().

const DEADZONE := 14.0

var _registry := {}   # instance_id -> ScrollContainer

func _ready() -> void:
	set_process_input(true)

func register(sc: ScrollContainer) -> void:
	if is_instance_valid(sc):
		_registry[sc.get_instance_id()] = sc
		if not sc.tree_exiting.is_connected(_on_sc_tree_exiting):
			sc.tree_exiting.connect(_on_sc_tree_exiting.bind(sc))

func _on_sc_tree_exiting(sc: ScrollContainer) -> void:
	if is_instance_valid(sc):
		_registry.erase(sc.get_instance_id())
	else:
		for id in _registry.keys():
			if _registry[id] == sc:
				_registry.erase(id)
				return

func _scroll_at(pos: Vector2) -> ScrollContainer:
	var best: ScrollContainer = null
	var best_area := INF
	for id in _registry.keys():
		var raw = _registry[id]
		if raw == null or not is_instance_valid(raw):
			_registry.erase(id)
			continue
		var sc: ScrollContainer = raw
		if sc.visible and sc.get_global_rect().has_point(pos):
			var area := sc.get_global_rect().size.x * sc.get_global_rect().size.y
			if area < best_area:
				best_area = area
				best = sc
	return best

# --- Pointage actif (touches et souris) ---

var _active := {}   # pointeur -> { "sc": ScrollContainer, "dragging": bool, "acc": Vector2 }

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var sc := _scroll_at(event.position)
			if sc:
				_active[event.index] = {"sc": sc, "dragging": false, "acc": Vector2.ZERO}
		else:
			_release_pointer(event.index)
	elif event is InputEventScreenDrag:
		if event.index in _active:
			_on_drag(event.index, event.relative)
		else:
			# Appui parti ailleurs : démarrage souple au premier glissé.
			var sc := _scroll_at(event.position)
			if sc:
				_active[event.index] = {"sc": sc, "dragging": true, "acc": Vector2.ZERO}
				get_viewport().set_input_as_handled()
				_scroll_by(sc, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var sc := _scroll_at(event.position)
			if sc:
				_active["mouse"] = {"sc": sc, "dragging": false, "acc": Vector2.ZERO}
		else:
			_release_pointer("mouse")
	elif event is InputEventMouseMotion:
		if "mouse" in _active and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_on_drag("mouse", event.relative)

func _on_drag(key: Variant, rel: Vector2) -> void:
	var e = _active.get(key)
	if e == null:
		return
	if not e["dragging"]:
		e["acc"] = e["acc"] + rel
		if e["acc"].length() < DEADZONE:
			return
		e["dragging"] = true
		get_viewport().set_input_as_handled()
		_scroll_by(e["sc"], e["acc"])
		e["acc"] = Vector2.ZERO
		return
	get_viewport().set_input_as_handled()
	_scroll_by(e["sc"], rel)

func _scroll_by(sc: ScrollContainer, delta: Vector2) -> void:
	# Le contenu suit le doigt : défiler du delta inverse.
	if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and delta.y != 0.0:
		sc.scroll_vertical += -delta.y
	if sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and delta.x != 0.0:
		sc.scroll_horizontal += -delta.x

func _release_pointer(key: Variant) -> void:
	var e = _active.get(key)
	if e == null:
		return
	# Si on glissait, consommer le relâchement pour éviter un clic parasite.
	if e["dragging"]:
		get_viewport().set_input_as_handled()
	_active.erase(key)
