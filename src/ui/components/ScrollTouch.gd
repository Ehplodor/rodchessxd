extends Node
## ScrollTouch — défilement tactile au doigt, attaché comme enfant d'une zone
## défilable (ScrollContainer, RichTextLabel, TextEdit).
## Le gestionnaire vit dans le viewport du conteneur : fonctionne aussi dans les
## fenêtres/modales. TAP = clic/sélection ; GLISSÉ au-delà d'un deadzone = défilement.

const DEADZONE := 14.0

var target: Control

var _active := {}   # pointeur -> { "dragging": bool, "acc": Vector2 }

func _ready() -> void:
	name = "_ScrollTouch"
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(target) or not target.visible:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			if target.get_global_rect().has_point(event.position):
				_active[event.index] = {"dragging": false, "acc": Vector2.ZERO}
		else:
			_release(event.index)
	elif event is InputEventScreenDrag:
		if event.index in _active:
			_on_drag(event.index, event.relative)
		elif target.get_global_rect().has_point(event.position):
			# Démarrage souple si aucun appui enregistré ici.
			_active[event.index] = {"dragging": true, "acc": Vector2.ZERO}
			get_viewport().set_input_as_handled()
			_scroll_by(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if target.get_global_rect().has_point(event.position):
				_active["mouse"] = {"dragging": false, "acc": Vector2.ZERO}
		else:
			_release("mouse")
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
		_scroll_by(e["acc"])
		e["acc"] = Vector2.ZERO
		return
	get_viewport().set_input_as_handled()
	_scroll_by(rel)

func _can_v(t: Control) -> bool:
	if t is ScrollContainer:
		return (t as ScrollContainer).vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	if t is RichTextLabel:
		return (t as RichTextLabel).scroll_active
	if t is TextEdit:
		return true
	return false

func _can_h(t: Control) -> bool:
	if t is ScrollContainer:
		return (t as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	return false

func _scroll_by(delta: Vector2) -> void:
	var t := target
	if _can_v(t) and delta.y != 0.0:
		var cur = t.get("scroll_vertical")
		if cur is float or cur is int:
			t.set("scroll_vertical", int(cur - delta.y))
	if _can_h(t) and delta.x != 0.0:
		var curx = t.get("scroll_horizontal")
		if curx is float or curx is int:
			t.set("scroll_horizontal", int(curx - delta.x))

func _release(key: Variant) -> void:
	var e = _active.get(key)
	if e != null and e["dragging"]:
		get_viewport().set_input_as_handled()
	_active.erase(key)
