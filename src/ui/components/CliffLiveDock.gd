class_name CliffLiveDock
extends PanelContainer
## CliffLiveDock.gd — Cockpit CHESS-CLIFF « Super Live » (étude d'UNE ligne moteur).
##
## Volontairement sobre : un ruban de pastilles (un coup = une pastille colorée par sa piste,
## tap = aperçu sur l'échiquier), un récit, une ligne de synthèse par camp et le rejeu.
## La Super-Analyse de partie vit dans CliffMomentsPanel (moments clés).
## Conçu mobile-first (portrait ≤ 450 px logiques).

signal stop_requested
signal replay_toggled(playing: bool)
signal full_game_requested
signal close_requested
signal step_selected(idx: int, fen: String, uci: String)

const CliffTypes = preload("res://src/engine/CliffTypes.gd")
const CliffLineReport = preload("res://src/engine/CliffLineReport.gd")
const DesignTokens = preload("res://src/ui/theme/DesignTokens.gd")

var _source_label: Label
var _status_label: Label
var _btn_stop: Button
var _progress: ProgressBar
var _ribbon: HBoxContainer
var _ribbon_scroll: ScrollContainer
var _summary_label: Label
var _narrative: Label
var _title_label: Label
var _btn_replay: Button
var _btn_full: Button
var _btn_close: Button
var _chips: Array[Button] = []
var _ply_pistes: Array[int] = []
var _current_step: int = -1
var _replaying: bool = false
var _stale: bool = false
var _report: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DesignTokens.SURFACE, 0.96)
	sb.border_color = Color(0.35, 0.25, 0.55, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(DesignTokens.RADIUS_MEDIUM)
	sb.content_margin_left = DesignTokens.SPACE_S
	sb.content_margin_right = DesignTokens.SPACE_S
	sb.content_margin_top = DesignTokens.SPACE_XS
	sb.content_margin_bottom = DesignTokens.SPACE_XS
	add_theme_stylebox_override("panel", sb)
	_build()
	clear()

func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# En-tête
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 4)
	_title_label = Label.new()
	_title_label.text = "🏔️ CHESS-CLIFF · Super Live"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_title_label.add_theme_color_override("font_color", DesignTokens.col("CLIFF_ACCENT"))
	header.add_child(_title_label)
	_btn_stop = Button.new()
	_btn_stop.text = "⏹"
	_btn_stop.tooltip_text = "Arrêter le calcul"
	_btn_stop.custom_minimum_size = Vector2(40, 40)
	_btn_stop.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_btn_stop.pressed.connect(func(): stop_requested.emit())
	header.add_child(_btn_stop)
	_btn_close = Button.new()
	_btn_close.text = "✖"
	_btn_close.flat = true
	_btn_close.custom_minimum_size = Vector2(32, 40)
	_btn_close.add_theme_font_size_override("font_size", 12)
	_btn_close.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_btn_close.pressed.connect(func(): close_requested.emit())
	header.add_child(_btn_close)
	vbox.add_child(header)

	# Source + statut
	var meta_row := HBoxContainer.new()
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label = Label.new()
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label.clip_text = true
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source_label.add_theme_font_size_override("font_size", 10)
	_source_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	meta_row.add_child(_source_label)
	_status_label = Label.new()
	_status_label.clip_text = true
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	meta_row.add_child(_status_label)
	vbox.add_child(meta_row)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 4)
	_progress.show_percentage = false
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(DesignTokens.SURFACE_ELEVATED, 0.6)
	sb_bg.set_corner_radius_all(2)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = DesignTokens.col("CLIFF_ACCENT")
	sb_fill.set_corner_radius_all(2)
	_progress.add_theme_stylebox_override("background", sb_bg)
	_progress.add_theme_stylebox_override("fill", sb_fill)
	vbox.add_child(_progress)

	# Ruban de pastilles (un coup de la ligne = une pastille)
	_ribbon_scroll = ScrollContainer.new()
	_ribbon_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ribbon_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ribbon_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_ribbon_scroll.custom_minimum_size = Vector2(0, 32)
	DesignTokens.touch_scroll(_ribbon_scroll)
	_ribbon = HBoxContainer.new()
	_ribbon.add_theme_constant_override("separation", 3)
	_ribbon_scroll.add_child(_ribbon)
	vbox.add_child(_ribbon_scroll)

	# Synthèse par camp (une ligne) + récit
	_summary_label = Label.new()
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_summary_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	vbox.add_child(_summary_label)

	_narrative = Label.new()
	_narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	vbox.add_child(_narrative)

	var actions := HFlowContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 4)
	_btn_replay = _make_action("▶ Rejouer", func(): _toggle_replay())
	actions.add_child(_btn_replay)
	_btn_full = _make_action("🔎 Moments clés de la partie", func(): full_game_requested.emit())
	actions.add_child(_btn_full)
	vbox.add_child(actions)

func _make_action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	b.pressed.connect(cb)
	return b

# --- API publique -------------------------------------------------------

func clear() -> void:
	_report = {}
	_stale = false
	_replaying = false
	_ply_pistes.clear()
	_current_step = -1
	if is_instance_valid(_ribbon):
		for c in _ribbon.get_children():
			c.queue_free()
		_chips.clear()
	if is_instance_valid(_narrative):
		_narrative.text = ""
	if is_instance_valid(_summary_label):
		_summary_label.text = ""
	if is_instance_valid(_source_label):
		_source_label.text = ""
	if is_instance_valid(_status_label):
		_status_label.text = ""
	if is_instance_valid(_progress):
		_progress.visible = false
	if is_instance_valid(_btn_stop):
		_btn_stop.visible = false
	if is_instance_valid(_btn_replay):
		_btn_replay.text = "▶ Rejouer"
		_btn_replay.disabled = true
	if is_instance_valid(_btn_full):
		_btn_full.disabled = false
	visible = false

## Bascule sur l'état « calcul en cours » (n/N).
func show_computing(cur: int, total: int) -> void:
	visible = true
	_status_label.text = "Calcul…"
	_btn_stop.visible = true
	_progress.visible = true
	_progress.max_value = float(maxi(1, total))
	_progress.value = float(cur)

func set_dock_title(title_text: String) -> void:
	if is_instance_valid(_title_label):
		_title_label.text = title_text

func set_source_label(text: String) -> void:
	if is_instance_valid(_source_label):
		_source_label.text = text

func set_stale(is_stale: bool) -> void:
	_stale = is_stale
	if is_instance_valid(_status_label):
		_status_label.text = "⚠ Obsolète – relancer" if is_stale else ""

## Mise à jour progressive pendant le calcul (aperçu vivant).
func set_step(step: Dictionary) -> void:
	visible = true
	_status_label.text = "Calcul…"
	var idx := int(step.get("step", _ply_pistes.size()))
	_append_chip(step, idx)
	_current_step = idx
	var expl := str(step.get("explanation", ""))
	if expl != "":
		_narrative.text = "👉 " + expl

## Rapport final : ruban, synthèse par camp, récit.
func set_report(report: Dictionary) -> void:
	clear()
	_report = report
	if report.is_empty() or not report.has("summary_white"):
		return
	visible = true
	_status_label.text = "Terminé"
	_btn_replay.disabled = false

	var plies: Array = report.get("plies", [])
	for i in range(plies.size()):
		_append_chip(plies[i], i)
	_current_step = -1
	_summary_label.text = _side_line("Blancs", report.get("summary_white", {})) + "\n" \
			+ _side_line("Noirs", report.get("summary_black", {}))
	_show_global_narrative()

## Met en évidence un pas : pastille surlignée et explication du coup.
func highlight_step(idx: int) -> void:
	_current_step = idx
	for i in range(_chips.size()):
		_style_chip(_chips[i], _ply_pistes[i], i == idx)
	if is_instance_valid(_ribbon_scroll) and idx >= 0 and idx < _chips.size():
		_ribbon_scroll.ensure_control_visible(_chips[idx])

	var plies: Array = _report.get("plies", [])
	if idx >= 0 and idx < plies.size():
		var step: Dictionary = plies[idx]
		var expl := str(step.get("explanation", ""))
		if expl == "":
			expl = "%s : %s (D=%d) · Survie %d%%" % [str(step.get("san", "?")),
					CliffTypes.get_piste_name(int(step.get("piste", 0))), int(step.get("indice_d", 0)),
					int(round(float(step.get("p_survie", 1.0)) * 100.0))]
		_narrative.text = "👉 " + expl
		_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	else:
		_show_global_narrative()

func _toggle_replay() -> void:
	_replaying = not _replaying
	_btn_replay.text = "⏸ Pause" if _replaying else "▶ Rejouer"
	replay_toggled.emit(_replaying)

func is_replaying() -> bool:
	return _replaying

func stop_replay() -> void:
	_replaying = false
	if is_instance_valid(_btn_replay):
		_btn_replay.text = "▶ Rejouer"

# --- Interne ------------------------------------------------------------

func _show_global_narrative() -> void:
	if _report.is_empty():
		return
	var rep := CliffLineReport.from_dict(_report)
	_narrative.text = "« " + rep.get_narrative_summary() + " »"
	_narrative.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)

static func _side_line(side: String, summary: Dictionary) -> String:
	var piste := int(summary.get("global_piste", CliffTypes.Piste.AUTOROUTE))
	return "%s %s : %s (D=%d)" % [CliffTypes.get_piste_icon(piste), side,
			CliffTypes.get_piste_name(piste), int(summary.get("indice_d", 0))]

func _style_chip(btn: Button, piste: int, current: bool) -> void:
	var col := DesignTokens.piste_color(piste)
	btn.add_theme_color_override("font_color", Color.WHITE if current else col)
	btn.add_theme_stylebox_override("normal", DesignTokens.flat(
			Color(0.22, 0.28, 0.42, 0.95) if current else Color(DesignTokens.SURFACE_ELEVATED, 0.9),
			DesignTokens.RADIUS_SMALL, DesignTokens.col("CLIFF_ACCENT") if current else col,
			2 if current else 1, Vector2(4, 1)))

func _append_chip(step: Dictionary, idx: int) -> void:
	var san: String = str(step.get("san", step.get("move_uci", "?")))
	var piste: int = int(step.get("piste", CliffTypes.Piste.AUTOROUTE))
	var is_white: bool = bool(step.get("is_white", (idx % 2 == 0)))
	var nature: int = int(step.get("move_nature", CliffTypes.MoveNature.SAFE))
	var icon := CliffTypes.get_nature_icon(nature) if nature != CliffTypes.MoveNature.SAFE \
			else CliffTypes.get_piste_icon(piste)
	var move_num: int = ChessGame.ply_info_from_fen(str(step.get("fen_before", "")), 0)["move_number"] \
			if step.has("fen_before") else int(step.get("ply", idx)) / 2 + 1

	var btn := Button.new()
	btn.text = "%s %s %s" % ["%d." % move_num if is_white else "%d…" % move_num, san, icon]
	btn.tooltip_text = "%s — %s (D=%d) · Survie %d%%" % [san, CliffTypes.get_piste_name(piste),
			int(step.get("indice_d", 0)), int(round(float(step.get("p_survie", 1.0)) * 100.0))]
	btn.custom_minimum_size = Vector2(56, 28)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_stylebox_override("hover",
			DesignTokens.flat(Color(0.18, 0.22, 0.32, 0.98), DesignTokens.RADIUS_SMALL, Color.WHITE, 1, Vector2(4, 1)))
	_style_chip(btn, piste, false)

	var step_fen := str(step.get("fen_before", step.get("fen", step.get("fen_after", ""))))
	var step_uci := str(step.get("move_uci", step.get("played_uci", step.get("best_move", ""))))
	btn.pressed.connect(func():
		highlight_step(idx)
		step_selected.emit(idx, step_fen, step_uci)
	)
	_chips.append(btn)
	_ply_pistes.append(piste)
	_ribbon.add_child(btn)
