class_name CliffPisteBadge
extends PanelContainer
## CliffPisteBadge.gd — Widget compact affichant le badge de classification de piste CHESS-CLIFF.
## Affiche l'icône de la piste et sa couleur avec un tooltip détaillé.

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")

var _label: Label
var _compact: bool = false
var _piste: int = -1

func _init() -> void:
	custom_minimum_size = Vector2(24, 20)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = false
	_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	add_child(_label)

	set_piste(-1)

func set_piste(piste: int, d_score: int = -1, delta: float = 0.0, bait: float = 0.0, p_survie: float = 1.0) -> void:
	_piste = piste
	if piste < 0:
		visible = false
		return

	visible = true
	var color := CliffTypes.get_piste_color(piste)
	var icon := CliffTypes.get_piste_icon(piste)
	var name := CliffTypes.get_piste_name(piste)
	var letter := CliffTypes.get_piste_letter(piste)

	_label.text = "%s %s" % [icon, letter] if _compact else "%s %s" % [icon, name]

	# Fond discret teinté de la couleur de la piste
	var bg_tint := Color(color.r, color.g, color.b, 0.15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_tint
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	add_theme_stylebox_override("panel", sb)

	# Tooltip riche
	var tt := "🏔️ Piste : %s" % name
	if d_score >= 0:
		tt += " (D=%d)" % d_score
	tt += "\n• Survie : %d%%" % int(round(p_survie * 100.0))
	if delta > 0.001:
		tt += "\n• Chute fatale Δ : %.2f" % delta
	if bait > 0.001:
		tt += "\n• Piège naturel (Bait) : %.2f" % bait

	tooltip_text = tt

## Affichage compact : icône + lettre (A/B/C/F/M) au lieu du nom complet.
func set_compact(compact: bool) -> void:
	_compact = compact
	if _piste >= 0:
		set_piste(_piste)

## Surbrillance du badge (ligne/pastille sélectionnée).
func set_selected(selected: bool) -> void:
	if selected:
		add_theme_constant_override("outline_size", 2)
		modulate = Color(1.15, 1.15, 1.15, 1.0)
	else:
		modulate = Color.WHITE
