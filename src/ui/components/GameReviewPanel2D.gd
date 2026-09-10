class_name GameReviewPanel2D
extends VBoxContainer
## GameReviewPanel2D.gd - Rapport de partie synthétique (T1.3) : ouverture, phases,
## distribution des qualités et moments clés cliquables. Dérivé du rapport archivé.

signal moment_selected(ply: int)

const _PHASE_ORDER := ["opening", "middlegame", "endgame"]

var _content: VBoxContainer
var _header: Label

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_header = Label.new()
	_header.text = "📋 Rapport de partie"
	_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_header.add_theme_color_override("font_color", DesignTokens.ACCENT)
	add_child(_header)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	add_child(_content)

func clear() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_header.text = "📋 Rapport de partie"

func set_report(report: Dictionary) -> void:
	if _content == null:
		return
	clear()
	if report.is_empty():
		_header.text = "📋 Rapport de partie — aucune analyse"
		return

	var opening: Dictionary = report.get("opening", {})
	var opening_name := str(opening.get("name", ""))
	var eco := str(opening.get("eco", ""))
	_header.text = "📋 Rapport de partie%s" % (("  —  %s %s" % [eco, opening_name]) if opening_name != "" else "")

	var w_phase: Dictionary = report.get("white_phase_stats", {})
	var b_phase: Dictionary = report.get("black_phase_stats", {})
	var w_stats: Dictionary = report.get("white_stats", {})
	var b_stats: Dictionary = report.get("black_stats", {})
	var w_acc := float(report.get("white_accuracy", 0.0))
	var b_acc := float(report.get("black_accuracy", 0.0))
	var w_acpl := float(report.get("white_acpl", 0.0))
	var b_acpl := float(report.get("black_acpl", 0.0))

	_add_line("🎯 Précision : ⚪ %.1f %%  •  ⚫ %.1f %%" % [w_acc, b_acc], DesignTokens.TEXT_PRIMARY)
	_add_line("📉 ACPL : ⚪ %.1f cp  •  ⚫ %.1f cp" % [w_acpl, b_acpl], DesignTokens.TEXT_SECONDARY)

	for phase in _PHASE_ORDER:
		var wp: Dictionary = w_phase.get(phase, {})
		var bp: Dictionary = b_phase.get(phase, {})
		_add_line("  %s — ⚪ perte moy. %.1f %%  •  ⚫ %.1f %%" % [
			GamePhaseService.phase_label_fr(phase),
			float(wp.get("avg_winpct_loss", 0.0)),
			float(bp.get("avg_winpct_loss", 0.0))
		], DesignTokens.TEXT_MUTED)

	_add_line("✅ Meilleurs : ⚪ %d  •  ⚫ %d   |   ?? Gaffes : ⚪ %d  •  ⚫ %d" % [
		int(w_stats.get("best", 0)) + int(w_stats.get("brilliant", 0)),
		int(b_stats.get("best", 0)) + int(b_stats.get("brilliant", 0)),
		int(w_stats.get("blunder", 0)) + int(w_stats.get("miss", 0)),
		int(b_stats.get("blunder", 0)) + int(b_stats.get("miss", 0))
	], DesignTokens.TEXT_SECONDARY)

	var swings: Array = report.get("biggest_swings", [])
	if not swings.is_empty():
		_add_line("🔥 Moments clés :", DesignTokens.WARNING)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", DesignTokens.SPACE_XS)
		row.add_theme_constant_override("v_separation", DesignTokens.SPACE_XS)
		_content.add_child(row)
		for swing in swings:
			var btn := Button.new()
			var dots := "." if bool(swing.get("is_white", true)) else "..."
			btn.text = "%d%s %s (-%.0f%%)" % [
				int(swing.get("move_number", 1)), dots, str(swing.get("san", "")),
				float(swing.get("winpct_loss", 0.0))
			]
			btn.flat = true
			btn.clip_text = true
			btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
			btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			btn.add_theme_color_override("font_color", ChessMove.quality_to_color(int(swing.get("quality", ChessMove.Quality.NONE))))
			var ply := int(swing.get("ply", 0))
			btn.pressed.connect(func(): moment_selected.emit(ply))
			row.add_child(btn)

func _add_line(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", color)
	_content.add_child(lbl)
