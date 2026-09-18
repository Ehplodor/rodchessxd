class_name CliffSummaryPanel
extends PanelContainer
## CliffSummaryPanel.gd — Panneau de synthèse affiché dans l'onglet Bilan pour CHESS-CLIFF.
## Présente la carte de difficulté cognitive, les pistes globales et la synthèse narrative.

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")

var _vbox: VBoxContainer
var _title_label: Label
var _sides_container: HBoxContainer
var _white_box: VBoxContainer
var _black_box: VBoxContainer
var _narrative_label: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 140)

	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.SURFACE_ELEVATED
	sb.border_color = DesignTokens.BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(DesignTokens.RADIUS_MEDIUM)
	sb.content_margin_left = DesignTokens.CARD_PAD_H
	sb.content_margin_right = DesignTokens.CARD_PAD_H
	sb.content_margin_top = DesignTokens.CARD_PAD_V
	sb.content_margin_bottom = DesignTokens.CARD_PAD_V
	add_theme_stylebox_override("panel", sb)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(_vbox)

	# 1. En-tête
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label = Label.new()
	_title_label.text = "🏔️ CHESS-CLIFF — Difficulté cognitive"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_title_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	header.add_child(_title_label)
	_vbox.add_child(header)

	var sep1 := HSeparator.new()
	_vbox.add_child(sep1)

	# 2. Colonnes Blancs / Noirs
	_sides_container = HBoxContainer.new()
	_sides_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sides_container.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	_vbox.add_child(_sides_container)

	_white_box = _build_side_box("BLANCS")
	_black_box = _build_side_box("NOIRS")
	_sides_container.add_child(_white_box)
	_sides_container.add_child(_black_box)

	var sep2 := HSeparator.new()
	_vbox.add_child(sep2)

	# 3. Synthèse narrative
	var narr_panel := PanelContainer.new()
	narr_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_narr := StyleBoxFlat.new()
	sb_narr.bg_color = DesignTokens.BTN_BG_HOVER
	sb_narr.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
	sb_narr.content_margin_left = DesignTokens.SPACE_S
	sb_narr.content_margin_right = DesignTokens.SPACE_S
	sb_narr.content_margin_top = DesignTokens.SPACE_XS
	sb_narr.content_margin_bottom = DesignTokens.SPACE_XS
	narr_panel.add_theme_stylebox_override("panel", sb_narr)

	_narrative_label = Label.new()
	_narrative_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative_label.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_narrative_label.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	narr_panel.add_child(_narrative_label)
	_vbox.add_child(narr_panel)

func _build_side_box(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var lbl_title := Label.new()
	lbl_title.name = "SideTitle"
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_title.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	box.add_child(lbl_title)

	var lbl_piste := Label.new()
	lbl_piste.name = "PisteLabel"
	lbl_piste.text = "—"
	lbl_piste.clip_text = true
	lbl_piste.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_piste.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	box.add_child(lbl_piste)

	var lbl_survie := Label.new()
	lbl_survie.name = "SurvieLabel"
	lbl_survie.text = "Survie : —"
	lbl_survie.clip_text = true
	lbl_survie.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_survie.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_survie.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	box.add_child(lbl_survie)

	var lbl_falaise := Label.new()
	lbl_falaise.name = "FalaiseLabel"
	lbl_falaise.text = "Ravin max (Δ) : —"
	lbl_falaise.clip_text = true
	lbl_falaise.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_falaise.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_falaise.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	box.add_child(lbl_falaise)

	var lbl_appat := Label.new()
	lbl_appat.name = "AppatLabel"
	lbl_appat.text = "Piège max : —"
	lbl_appat.clip_text = true
	lbl_appat.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_appat.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_appat.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	box.add_child(lbl_appat)

	return box

func set_report_data(report_dict: Dictionary) -> void:
	var report = CliffLineReport.from_dict(report_dict)
	set_report(report)

func set_report(report: CliffLineReport) -> void:
	var sw = report.get_summary_white()
	var sb = report.get_summary_black()

	_populate_side(_white_box, sw)
	_populate_side(_black_box, sb)

	_narrative_label.text = "« " + report.get_narrative_summary() + " »"

func _populate_side(box: VBoxContainer, summary: Dictionary) -> void:
	if summary.is_empty():
		return

	var piste: int = int(summary.get("global_piste", CliffTypes.Piste.AUTOROUTE))
	var d_score: int = int(summary.get("indice_d", 0))
	var p_survie: float = float(summary.get("p_survie_ligne", 1.0))
	var delta_max: float = float(summary.get("max_delta_chute", 0.0))
	var bait_max: float = float(summary.get("max_bait", 0.0))

	var color := CliffTypes.get_piste_color(piste)
	var icon := CliffTypes.get_piste_icon(piste)
	var name := CliffTypes.get_piste_name(piste)

	var lbl_piste := box.get_node_or_null("PisteLabel") as Label
	if lbl_piste:
		lbl_piste.text = "%s %s (D=%d)" % [icon, name, d_score]
		lbl_piste.add_theme_color_override("font_color", color)

	var lbl_survie := box.get_node_or_null("SurvieLabel") as Label
	if lbl_survie:
		lbl_survie.text = "Survie : %d%%" % int(round(p_survie * 100.0))

	var lbl_falaise := box.get_node_or_null("FalaiseLabel") as Label
	if lbl_falaise:
		lbl_falaise.text = "Ravin max (Δ) : %.2f" % delta_max

	var lbl_appat := box.get_node_or_null("AppatLabel") as Label
	if lbl_appat:
		lbl_appat.text = "Piège max : %.2f" % bait_max
