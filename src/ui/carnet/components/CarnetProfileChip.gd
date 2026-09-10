class_name CarnetProfileChip
extends Button
## CarnetProfileChip.gd — T3 : bouton compact d'un profil (nom tronqué, cible tactile).
## Émet `profile_selected(id)` au tap. Aucune connaissance du domaine au-delà du dict.

signal profile_selected(profile_id: String)

var profile_id := ""

func _init() -> void:
	toggle_mode = true
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	DesignTokens.style_button(self, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	pressed.connect(func(): profile_selected.emit(profile_id))

func set_profile(profile: Dictionary, active: bool) -> void:
	profile_id = str(profile.get("id", ""))
	text = str(profile.get("name", "Profil"))
	button_pressed = active
