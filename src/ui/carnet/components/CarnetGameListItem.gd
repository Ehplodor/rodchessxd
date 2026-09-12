class_name CarnetGameListItem
extends PanelContainer
## CarnetGameListItem.gd — T3 : Carte de partie élégante et ergonomique dans LeCarnet (Sync).
## Présente clairement les joueurs, le résultat, la perspective, le statut d'analyse et des actions explicites.

signal reanalyze_requested(game_id: String)
signal perspective_cycle_requested(game_id: String)
signal remove_requested(game_id: String)

var _game_id := ""
var _game_data: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", DesignTokens.card())

func set_game(game_data: Dictionary) -> void:
	_game_data = game_data
	_game_id = str(game_data.get("game_id", ""))

	# Nettoyage
	for child in get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(vbox)

	var white_name := str(game_data.get("white_name", "")).strip_edges()
	var black_name := str(game_data.get("black_name", "")).strip_edges()
	var white_elo := int(game_data.get("white_elo", 0))
	var black_elo := int(game_data.get("black_elo", 0))
	var title := str(game_data.get("title", "")).strip_edges()
	var result := str(game_data.get("result", "*")).strip_edges()
	var perspective := str(game_data.get("perspective", "")).to_lower()
	var status := str(game_data.get("status", "up_to_date"))

	# ── Ligne 1 : Joueurs & Badge Résultat ─────────────────────────────────────────
	var row1 := HBoxContainer.new()
	row1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(row1)

	var w_txt := white_name if white_name != "" else "Blancs"
	if white_elo > 0:
		w_txt += " (%d)" % white_elo
	var b_txt := black_name if black_name != "" else "Noirs"
	if black_elo > 0:
		b_txt += " (%d)" % black_elo

	var players_text := "⚪ %s  vs  ⚫ %s" % [w_txt, b_txt]
	if white_name == "" and black_name == "":
		players_text = title if title != "" else "Partie"

	var players_lbl := Label.new()
	players_lbl.text = players_text
	players_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	players_lbl.clip_text = true
	players_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	players_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	row1.add_child(players_lbl)

	var res_info := _format_result(result, perspective)
	var res_badge := _create_badge(res_info["text"], res_info["color"])
	row1.add_child(res_badge)

	# ── Ligne 2 : Métadonnées (Date, Coups, Ouverture, Source) ─────────────────────
	var row2 := HBoxContainer.new()
	row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(row2)

	var meta_parts: Array[String] = []
	var date_str := _format_date(str(game_data.get("date", "")))
	if date_str != "":
		meta_parts.append("📅 %s" % date_str)

	var moves_count := int(game_data.get("moves_count", 0))
	if moves_count > 0:
		meta_parts.append("♟ %d coups" % moves_count)

	var eco := str(game_data.get("eco", "")).strip_edges()
	if eco != "":
		meta_parts.append("📖 %s" % eco)

	var source := str(game_data.get("source", ""))
	if source == "chess_com":
		meta_parts.append("🌐 Chess.com")
	elif source == "pgn_import":
		meta_parts.append("📥 PGN")

	var meta_lbl := Label.new()
	meta_lbl.text = "  ·  ".join(meta_parts)
	meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta_lbl.clip_text = true
	meta_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	meta_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	row2.add_child(meta_lbl)

	# ── Ligne 3 : Point de vue (Perspective) & Statut d'analyse ───────────────────
	var row3 := HBoxContainer.new()
	row3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(row3)

	var btn_perspective := Button.new()
	var persp_txt := "⟳ Vue : Auto ▾"
	match perspective:
		"white": persp_txt = "⚪ Vue : Blancs ▾"
		"black": persp_txt = "⚫ Vue : Noirs ▾"
	btn_perspective.text = persp_txt
	btn_perspective.tooltip_text = "Point de vue analysé pour votre carnet. Cliquez pour basculer : Blancs / Noirs / Auto."
	btn_perspective.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
	DesignTokens.style_button(btn_perspective, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	btn_perspective.add_theme_color_override("font_color", DesignTokens.ACCENT if perspective == "" else DesignTokens.TEXT_PRIMARY)
	btn_perspective.pressed.connect(func(): perspective_cycle_requested.emit(_game_id))
	row3.add_child(btn_perspective)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(spacer)

	var status_info := _format_status(status, str(game_data.get("reason", "")))
	var status_badge := _create_badge(status_info["text"], status_info["color"])
	status_badge.tooltip_text = status_info["tooltip"]
	row3.add_child(status_badge)

	# ── Ligne 4 : Actions explicites ──────────────────────────────────────────────
	var row4 := HBoxContainer.new()
	row4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row4.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(row4)

	var btn_recalc := Button.new()
	if status == "pending":
		btn_recalc.text = "⚡ Analyser avec Stockfish"
		btn_recalc.tooltip_text = "Lancer l'analyse Stockfish de cette partie"
		btn_recalc.add_theme_color_override("font_color", DesignTokens.ACCENT)
	elif status == "stale":
		btn_recalc.text = "⟳ Mettre à jour les atomes"
		btn_recalc.tooltip_text = "Mettre à jour les atomes avec la nouvelle analyse moteur"
		btn_recalc.add_theme_color_override("font_color", DesignTokens.WARNING)
	else:
		btn_recalc.text = "⟳ Recalculer les atomes"
		btn_recalc.tooltip_text = "Recalculer les atomes et moments clés de cette partie pour ce carnet"
		btn_recalc.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

	btn_recalc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_recalc.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
	btn_recalc.clip_text = true
	btn_recalc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	DesignTokens.style_button(btn_recalc, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	btn_recalc.pressed.connect(func(): reanalyze_requested.emit(_game_id))
	row4.add_child(btn_recalc)

	var btn_remove := Button.new()
	btn_remove.text = "🗑 Retirer du carnet"
	btn_remove.tooltip_text = "Retirer cette partie de ce carnet (la partie reste précieusement archivée dans votre bibliothèque)"
	btn_remove.custom_minimum_size = Vector2(130.0, float(DesignTokens.TOUCH_DENSE))
	btn_remove.clip_text = true
	btn_remove.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	DesignTokens.style_button(btn_remove, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
	btn_remove.add_theme_color_override("font_color", DesignTokens.DANGER)
	btn_remove.pressed.connect(func(): remove_requested.emit(_game_id))
	row4.add_child(btn_remove)

func _format_result(result: String, perspective: String) -> Dictionary:
	match result:
		"1-0":
			if perspective == "white":
				return {"text": "1 - 0  Victoire", "color": DesignTokens.SUCCESS}
			elif perspective == "black":
				return {"text": "1 - 0  Défaite", "color": DesignTokens.DANGER}
			return {"text": "1 - 0", "color": DesignTokens.TEXT_PRIMARY}
		"0-1":
			if perspective == "black":
				return {"text": "0 - 1  Victoire", "color": DesignTokens.SUCCESS}
			elif perspective == "white":
				return {"text": "0 - 1  Défaite", "color": DesignTokens.DANGER}
			return {"text": "0 - 1", "color": DesignTokens.TEXT_PRIMARY}
		"1/2-1/2", "0.5-0.5":
			return {"text": "½ - ½  Nulle", "color": DesignTokens.TEXT_SECONDARY}
	return {"text": "—", "color": DesignTokens.TEXT_MUTED}

func _format_status(status: String, reason: String) -> Dictionary:
	match status:
		"up_to_date":
			return {
				"text": "✓ Analysée & à jour",
				"color": DesignTokens.SUCCESS,
				"tooltip": "Partie entièrement analysée et moments clés intégrés au carnet"
			}
		"pending":
			return {
				"text": "⏳ En attente d'analyse",
				"color": DesignTokens.WARNING,
				"tooltip": "Partie pas encore analysée par Stockfish ou à intégrer"
			}
		"stale":
			return {
				"text": "⚠ Recalcul nécessaire",
				"color": DesignTokens.WARNING,
				"tooltip": "L'analyse de la partie a évolué (%s), un recalcul est requis" % reason
			}
	return {
		"text": status,
		"color": DesignTokens.TEXT_MUTED,
		"tooltip": reason
	}

func _format_date(raw_date: String) -> String:
	var clean := raw_date.strip_edges()
	if clean == "":
		return ""
	if clean.length() >= 10:
		# Ex: "2026.09.08" ou "2026-09-08" -> "08/09/2026"
		var sep := "." if clean.contains(".") else ("-" if clean.contains("-") else "")
		if sep != "":
			var parts := clean.substr(0, 10).split(sep)
			if parts.size() == 3 and parts[0].length() == 4:
				return "%s/%s/%s" % [parts[2], parts[1], parts[0]]
		return clean.substr(0, 10)
	return clean

func _create_badge(text: String, color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(color.r, color.g, color.b, 0.15)
	b_style.border_color = color
	b_style.set_border_width_all(1)
	b_style.corner_radius_top_left = 4
	b_style.corner_radius_top_right = 4
	b_style.corner_radius_bottom_left = 4
	b_style.corner_radius_bottom_right = 4
	b_style.content_margin_left = 6
	b_style.content_margin_right = 6
	b_style.content_margin_top = 2
	b_style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", b_style)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", color)
	badge.add_child(lbl)
	return badge