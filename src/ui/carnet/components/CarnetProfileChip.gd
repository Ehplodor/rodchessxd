class_name CarnetProfileChip
extends Button
## CarnetProfileChip.gd — T3 : bouton compact d'un profil (nom tronqué, cible tactile).
## Émet `profile_selected(id)` au tap. Aucune connaissance du domaine au-delà du dict.

signal profile_selected(profile_id: String)
signal context_menu_requested(profile_id: String, global_position: Vector2)

var profile_id := ""
var _long_press_timer: Timer = null
var _is_long_pressing := false

func _init() -> void:
	toggle_mode = true
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size = Vector2(DesignTokens.TOUCH_MIN, DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(self, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	pressed.connect(func(): profile_selected.emit(profile_id))

	_long_press_timer = Timer.new()
	_long_press_timer.wait_time = 0.5
	_long_press_timer.one_shot = true
	_long_press_timer.timeout.connect(_on_long_press)
	add_child(_long_press_timer)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			context_menu_requested.emit(profile_id, get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_long_pressing = true
				_long_press_timer.start()
			else:
				_is_long_pressing = false
				_long_press_timer.stop()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_is_long_pressing = true
			_long_press_timer.start()
		else:
			_is_long_pressing = false
			_long_press_timer.stop()

func _on_long_press() -> void:
	if _is_long_pressing:
		context_menu_requested.emit(profile_id, get_global_mouse_position())
		_is_long_pressing = false

func set_profile(profile: Dictionary, active: bool) -> void:
	profile_id = str(profile.get("id", ""))
	text = str(profile.get("name", "Profil"))
	button_pressed = active
