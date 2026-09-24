class_name CliffMomentsPanel
extends PanelContainer
## CliffMomentsPanel.gd — Super-Analyse CHESS-CLIFF : les « Moments clés » de la partie.
##
## Une courte liste de cartes (≤ 12), vue d'abord depuis le camp de l'utilisateur :
## - « Tes moments » : tests réussis, coups uniques manqués, appâts mordus, inattentions ;
## - « Chez l'adversaire » (repliable) : ses moments, relus comme la pression que tu as infligée.
## Tap sur « Voir » → moment_selected(moment) : Main affiche la position AVANT le coup,
## avec flèches (bon coup, appât) et cases piégées.
## Conçu mobile-first (portrait ≤ 450 px logiques).

signal stop_requested
signal close_requested
signal moment_selected(moment: Dictionary)

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffMoments = preload("res://src/engine/CliffMoments.gd")
const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")

var _title_label: Label
var _btn_stop: Button
var _status_label: Label
var _progress: ProgressBar
var _btn_white: Button
var _btn_black: Button
var _summary_label: Label
var _mine_title: Label
var _mine_box: VBoxContainer
var _opp_toggle: Button
var _opp_box: VBoxContainer
var _moments: Array = []
var _hero_white := true
var _has_report := false

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", DesignTokens.flat(Color(DesignTokens.SURFACE, 0.96),
			DesignTokens.RADIUS_MEDIUM, Color(0.35, 0.25, 0.55, 0.7), 1,
			Vector2(DesignTokens.SPACE_S, DesignTokens.SPACE_XS)))
	_build()
	clear()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	_title_label = _label("🏔️ Moments clés", DesignTokens.FONT_CAPTION, DesignTokens.col("CLIFF_ACCENT"))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title_label)
	_btn_stop = Button.new()
	_btn_stop.text = "⏹"
	_btn_stop.tooltip_text = "Arrêter l'analyse"
	_btn_stop.custom_minimum_size = Vector2(40, 40)
	_btn_stop.pressed.connect(func(): stop_requested.emit())
	header.add_child(_btn_stop)
	var btn_close := Button.new()
	btn_close.text = "✖"
	btn_close.flat = true
	btn_close.custom_minimum_size = Vector2(32, 40)
	btn_close.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	btn_close.pressed.connect(func(): close_requested.emit())
	header.add_child(btn_close)
	vbox.add_child(header)

	_status_label = _label("", 11, DesignTokens.TEXT_MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 4)
	_progress.show_percentage = false
	_progress.add_theme_stylebox_override("background", DesignTokens.flat(Color(DesignTokens.SURFACE_ELEVATED, 0.6), 2))
	_progress.add_theme_stylebox_override("fill", DesignTokens.flat(DesignTokens.col("CLIFF_ACCENT"), 2))
	vbox.add_child(_progress)

	# Point de vue : Blancs / Noirs
	var side_row := HBoxContainer.new()
	side_row.add_theme_constant_override("separation", 4)
	_btn_white = _segment("⚪ Vu des Blancs", func(): set_hero(true))
	_btn_black = _segment("⚫ Vu des Noirs", func(): set_hero(false))
	side_row.add_child(_btn_white)
	side_row.add_child(_btn_black)
	vbox.add_child(side_row)

	_summary_label = _label("", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_PRIMARY)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_summary_label)

	_mine_title = _label("Tes moments", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY)
	vbox.add_child(_mine_title)
	_mine_box = VBoxContainer.new()
	_mine_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_mine_box)

	_opp_toggle = Button.new()
	_opp_toggle.flat = true
	_opp_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_opp_toggle.clip_text = true
	_opp_toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_opp_toggle.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_opp_toggle.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	_opp_toggle.pressed.connect(func():
		_opp_box.visible = not _opp_box.visible
		_refresh_opp_toggle()
	)
	vbox.add_child(_opp_toggle)
	_opp_box = VBoxContainer.new()
	_opp_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_opp_box)

# --- API publique -------------------------------------------------------

func clear() -> void:
	_moments = []
	_has_report = false
	_status_label.text = ""
	_progress.visible = false
	_btn_stop.visible = false
	_summary_label.text = ""
	_clear_box(_mine_box)
	_clear_box(_opp_box)
	_opp_box.visible = false
	_set_results_visible(false)
	visible = false

## Étape de calcul : « Tri des coups… 12/40 », « Analyse des moments 3/8 ».
func show_progress(phase_text: String, cur: int, total: int) -> void:
	visible = true
	_btn_stop.visible = true
	_status_label.text = "%s %d/%d" % [phase_text, cur, total]
	_progress.visible = true
	_progress.max_value = float(maxi(1, total))
	_progress.value = float(cur)

## Rapport final (cliff_version 3). `hero_white` : camp affiché en premier.
func set_report(report: Dictionary, hero_white: bool) -> void:
	_moments = report.get("moments", [])
	_has_report = true
	visible = true
	_btn_stop.visible = false
	_progress.visible = false
	_status_label.text = "%d coups triés · %d examinés en profondeur" % [
			int(report.get("screened", 0)), int(report.get("candidates", 0))]
	_set_results_visible(true)
	set_hero(hero_white)

func set_hero(white: bool) -> void:
	_hero_white = white
	_style_segment(_btn_white, white)
	_style_segment(_btn_black, not white)
	if not _has_report:
		return
	_summary_label.text = CliffMoments.side_summary(_moments, white)
	_clear_box(_mine_box)
	_clear_box(_opp_box)
	var mine := 0
	var opp := 0
	for m in _moments:
		if bool(m.get("is_white", true)) == white:
			_mine_box.add_child(_card(m))
			mine += 1
		else:
			_opp_box.add_child(_card(CliffMoments.as_pressure(m)))
			opp += 1
	if mine == 0:
		var empty := _label("Aucun moment critique : partie sans piège pour ce camp.", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mine_box.add_child(empty)
	_opp_toggle.set_meta("count", opp)
	_opp_toggle.visible = opp > 0
	_refresh_opp_toggle()

func hero_is_white() -> bool:
	return _hero_white

func has_report() -> bool:
	return _has_report

# --- Interne ------------------------------------------------------------

func _card(m: Dictionary) -> Control:
	var pressure := bool(m.get("pressure", false))
	var success := pressure or CliffTypes.moment_is_success(int(m.get("kind", -1)))
	var accent: Color = DesignTokens.col("CLIFF_ACCENT") if pressure \
			else (DesignTokens.SUCCESS if success else DesignTokens.DANGER)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", DesignTokens.flat(Color(DesignTokens.SURFACE_ELEVATED, 0.55),
			DesignTokens.RADIUS_SMALL, Color(accent, 0.8), 1, Vector2(DesignTokens.CARD_PAD_H, DesignTokens.CARD_PAD_V)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon := _label(str(m.get("icon", "")), DesignTokens.FONT_BODY, accent)
	icon.custom_minimum_size = Vector2(26, 0)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	var ply := int(m.get("ply", 0))
	var num := "%d." % (ply / 2 + 1) if bool(m.get("is_white", true)) else "%d…" % (ply / 2 + 1)
	var head := _label("%s %s · %s" % [num, str(m.get("san", "")), str(m.get("title", ""))],
			DesignTokens.FONT_CAPTION, accent)
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(head)
	var body := _label(str(m.get("text", "")), DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(body)
	row.add_child(col)

	var see := Button.new()
	see.text = "Voir"
	see.custom_minimum_size = Vector2(56, 40)
	see.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	see.pressed.connect(func(): moment_selected.emit(m))
	row.add_child(see)
	return panel

func _refresh_opp_toggle() -> void:
	var n := int(_opp_toggle.get_meta("count", 0))
	_opp_toggle.text = "%s Chez l'adversaire (%d)" % ["▾" if _opp_box.visible else "▸", n]

func _set_results_visible(v: bool) -> void:
	for c in [_btn_white.get_parent(), _summary_label, _mine_title, _mine_box]:
		c.visible = v
	_opp_toggle.visible = v and int(_opp_toggle.get_meta("count", 0)) > 0

func _clear_box(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()

func _segment(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	b.pressed.connect(cb)
	return b

func _style_segment(b: Button, active: bool) -> void:
	var accent := DesignTokens.col("CLIFF_ACCENT")
	b.add_theme_stylebox_override("normal", DesignTokens.flat(
			Color(0.24, 0.18, 0.38, 0.95) if active else Color(DesignTokens.SURFACE_ELEVATED, 0.6),
			DesignTokens.RADIUS_SMALL, accent if active else Color(DesignTokens.BORDER, 0.6), 1, Vector2(6, 2)))
	b.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY if active else DesignTokens.TEXT_MUTED)

static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
