class_name CarnetSyncBadge
extends PanelContainer
## CarnetSyncBadge.gd — T3 : badge d'état de synchronisation d'un carnet.
## Vert si tout est à jour, ambre s'il reste des parties à traiter.

var _label: Label

func _init() -> void:
	add_theme_stylebox_override("panel",
			DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
					DesignTokens.BORDER, 1, Vector2(DesignTokens.SPACE_S, DesignTokens.SPACE_XS)))
	_label = Label.new()
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.clip_text = true
	_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	add_child(_label)
	set_status(0, 0)

## `to_process` = nombre de parties restantes ; `total` = parties du profil.
func set_status(total: int, to_process: int) -> void:
	if to_process > 0:
		_label.text = "%d · %d à traiter" % [total, to_process]
		_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	else:
		_label.text = "%d · à jour" % total
		_label.add_theme_color_override("font_color", DesignTokens.SUCCESS)

func displayed_text() -> String:
	return _label.text
