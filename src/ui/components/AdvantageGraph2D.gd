class_name AdvantageGraph2D
extends Control
## AdvantageGraph2D.gd - Graphe vectoriel interactif de la courbe d'avantage avec axes, HUD et zoom

signal move_scrubbed(ply_index: int)
signal analysis_selected(analysis_entry: Dictionary)

var evaluations: Array = []
var active_ply: int = -1

var max_eval_cp: float = 500.0 # Plafond visuel à ±5 pions
var depth_badge: PanelContainer
var depth_label: Label
var depth_progress_bar: ProgressBar
var stored_analyses: Array = []
var current_analysis_idx: int = 0
var btn_switch_analysis: Button

# Scrubbing M2 : marqueur instantané, navigation moteur throttlée + 1 commit final.
var _scrubbing := false
var _last_nav_ms := 0
const SCRUB_NAV_MS := 90

func _ready() -> void:
	custom_minimum_size = Vector2(250, 130)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var gc = get_node_or_null("/root/GameController")
	if gc:
		gc.move_navigated.connect(_on_move_navigated)
		gc.position_changed.connect(_on_position_changed)

	var em = get_node_or_null("/root/EngineManager")
	if em:
		em.evaluation_updated.connect(_on_engine_eval)
		em.engine_ready.connect(_on_engine_ready)
		em.engine_error.connect(_on_engine_error)
		em.engine_profile_changed.connect(_on_engine_profile_changed)

	_setup_hud()

func _setup_hud() -> void:
	var chip_normal := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
			DesignTokens.BORDER, 1, Vector2(8, 3))
	var chip_hover := chip_normal.duplicate() as StyleBoxFlat
	chip_hover.bg_color = DesignTokens.BTN_BG_HOVER
	var chip_pressed := chip_normal.duplicate() as StyleBoxFlat
	chip_pressed.bg_color = DesignTokens.BTN_BG_PRESSED

	# Badge dynamique de calcul et profondeur moteur (remplace l'ancien bouton agrandir)
	depth_badge = PanelContainer.new()
	depth_badge.add_theme_stylebox_override("panel", chip_normal)
	depth_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(depth_badge)

	var badge_vbox := VBoxContainer.new()
	badge_vbox.add_theme_constant_override("separation", 2)
	depth_badge.add_child(badge_vbox)

	depth_label = Label.new()
	depth_label.text = "⚡ %s • Prêt" % _get_active_engine_name()
	depth_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	badge_vbox.add_child(depth_label)

	depth_progress_bar = ProgressBar.new()
	depth_progress_bar.custom_minimum_size = Vector2(100, 3)
	depth_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_progress_bar.show_percentage = false
	depth_progress_bar.min_value = 0
	depth_progress_bar.max_value = 16
	depth_progress_bar.value = 0

	var bg_sb = StyleBoxFlat.new()
	bg_sb.bg_color = DesignTokens.SURFACE
	bg_sb.set_corner_radius_all(1)
	var fill_sb = StyleBoxFlat.new()
	fill_sb.bg_color = DesignTokens.ACCENT
	fill_sb.set_corner_radius_all(1)
	depth_progress_bar.add_theme_stylebox_override("background", bg_sb)
	depth_progress_bar.add_theme_stylebox_override("fill", fill_sb)
	badge_vbox.add_child(depth_progress_bar)

	# Bouton pour basculer entre les analyses enregistrées (si multi-analyses)
	btn_switch_analysis = Button.new()
	btn_switch_analysis.visible = false
	btn_switch_analysis.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn_switch_analysis.custom_minimum_size = Vector2(0, 32)
	btn_switch_analysis.tooltip_text = "Cliquer pour basculer entre les différentes analyses de moteurs enregistrées"
	btn_switch_analysis.add_theme_stylebox_override("normal", chip_normal)
	btn_switch_analysis.add_theme_stylebox_override("hover", chip_hover)
	btn_switch_analysis.add_theme_stylebox_override("pressed", chip_pressed)
	btn_switch_analysis.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	btn_switch_analysis.pressed.connect(_cycle_analysis)
	add_child(btn_switch_analysis)

	_update_button_positions()

func _update_button_positions() -> void:
	var right_cursor = size.x - 8
	var min_allowed_x = 36.0
	if depth_badge:
		depth_badge.reset_size()
		var badge_w = depth_badge.size.x
		var badge_x = maxf(min_allowed_x, right_cursor - badge_w)
		depth_badge.position = Vector2(badge_x, 6)
		right_cursor = badge_x - 6.0
	if btn_switch_analysis and btn_switch_analysis.visible:
		btn_switch_analysis.reset_size()
		var btn_w = btn_switch_analysis.size.x
		var btn_x = maxf(min_allowed_x, right_cursor - btn_w)
		btn_switch_analysis.position = Vector2(btn_x, 6)

func _get_active_engine_name() -> String:
	var em = get_node_or_null("/root/EngineManager")
	if em and em.has_method("get_engine_display_name"):
		var raw = em.get_engine_display_name()
		if raw.begins_with("Stockfish"):
			return "SF"
		return raw
	return "SF"

func _on_position_changed() -> void:
	if depth_progress_bar:
		depth_progress_bar.value = 0
	if depth_label:
		depth_label.text = "⚡ %s • Calcul..." % _get_active_engine_name()
		depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_update_button_positions()

func _on_engine_eval(_score_cp: int, _mate_in: int, depth: int, _best_move: String, _pv: Array, _multipv: Array) -> void:
	var eng_name = _get_active_engine_name()
	var sm = get_node_or_null("/root/SettingsManager")
	var def_d = 12 if (OS.has_feature("android") or OS.has_feature("ios")) else 16
	var target_d = sm.get_setting("engine_depth", def_d) if sm else def_d

	if depth_progress_bar:
		depth_progress_bar.max_value = target_d
		depth_progress_bar.value = clampf(depth, 0, target_d)

	if depth_label:
		if depth >= target_d:
			depth_label.text = "⚡ %s • p. %d/%d ✓" % [eng_name, depth, target_d]
			depth_label.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		elif depth > 0:
			depth_label.text = "⚡ %s • p. %d/%d" % [eng_name, depth, target_d]
			depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		else:
			depth_label.text = "⚡ %s • Calcul..." % eng_name
			depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)

	_update_button_positions()

func _on_engine_ready() -> void:
	if depth_label:
		depth_label.text = "⚡ %s • Prêt" % _get_active_engine_name()
		depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	_update_button_positions()

func _on_engine_profile_changed(_profile_id: String) -> void:
	_on_engine_ready()

func _on_engine_error(_msg: String) -> void:
	if depth_label:
		depth_label.text = "⚠ Moteur arrêté"
		depth_label.add_theme_color_override("font_color", DesignTokens.WARNING)
	_update_button_positions()

func update_stored_analyses(analyses: Array) -> void:
	stored_analyses = analyses
	if stored_analyses.size() > 1:
		current_analysis_idx = stored_analyses.size() - 1
		_show_switch_analysis_button()
	else:
		if btn_switch_analysis:
			btn_switch_analysis.visible = false
	_update_button_positions()

func _show_switch_analysis_button() -> void:
	if not btn_switch_analysis:
		return
	btn_switch_analysis.visible = true
	var cur = stored_analyses[current_analysis_idx]
	var eng = cur.get("engine_name", "Stockfish")
	if eng.begins_with("Stockfish"):
		eng = "SF"
	var d = cur.get("depth", 10)
	btn_switch_analysis.text = "⚡ %s (d%d) [%d/%d]" % [eng, d, current_analysis_idx + 1, stored_analyses.size()]
	btn_switch_analysis.reset_size()
	_update_button_positions()

func _cycle_analysis() -> void:
	if stored_analyses.is_empty():
		return
	current_analysis_idx = (current_analysis_idx + 1) % stored_analyses.size()
	var cur = stored_analyses[current_analysis_idx]
	set_evaluations(cur.get("evaluations", []))
	_show_switch_analysis_button()
	analysis_selected.emit(cur)
	var main = find_parent("Main")
	if main:
		if main.has_method("_display_analysis_stats"):
			main._display_analysis_stats(cur)
		elif main.stats_label:
			var w_acc = cur.get("white_accuracy", 0.0)
			var b_acc = cur.get("black_accuracy", 0.0)
			var w_elo = cur.get("white_estimated_elo", 1500)
			var b_elo = cur.get("black_estimated_elo", 1500)
			var w_ci = cur.get("white_elo_ci", 0)
			var b_ci = cur.get("black_elo_ci", 0)
			var comp = cur.get("elo_comparison", {})
			var stars: String = comp.get("stars", "")
			var p_val: float = float(comp.get("p_value", 1.0))
			var diff_elo: int = int(comp.get("diff_elo", w_elo - b_elo))
			var stat_summary := ""
			if not comp.is_empty():
				var p_str = "p < 0.001" if p_val < 0.001 else "p=%.3f" % p_val
				stat_summary = " • Δ %+d ELO [%s %s]" % [diff_elo, p_str, stars]
			var w_ci_str = " ±%d" % w_ci if w_ci > 0 else ""
			var b_ci_str = " ±%d" % b_ci if b_ci > 0 else ""
			main.stats_label.text = "⚪ Blancs: %.1f%% (Est. %d%s ELO)  |  ⚫ Noirs: %.1f%% (Est. %d%s ELO)%s" % [
				w_acc, w_elo, w_ci_str,
				b_acc, b_elo, b_ci_str,
				stat_summary
			]

func prepare_live_analysis(total_plies: int) -> void:
	evaluations.clear()
	var n = maxi(2, total_plies)
	for i in range(n):
		evaluations.append({
			"ply": i,
			"move_number": (i / 2) + 1,
			"is_white": (i % 2 == 0),
			"score_cp": 0,
			"ci_margin": 140.0,
			"ci_lower": -140.0,
			"ci_upper": 140.0,
			"is_placeholder": true
		})
	active_ply = 0
	queue_redraw()

func update_live_ply(ply_idx: int, record: Dictionary) -> void:
	while evaluations.size() <= ply_idx:
		evaluations.append({})
	record["is_placeholder"] = false
	evaluations[ply_idx] = record
	active_ply = ply_idx
	queue_redraw()

func set_evaluations(eval_data: Array) -> void:
	evaluations.clear()
	for item in eval_data:
		if item is Dictionary:
			evaluations.append(item)
	if not evaluations.is_empty() and (active_ply < 0 or active_ply >= evaluations.size()):
		active_ply = evaluations.size() - 1
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_button_positions()
		queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y

	var left_margin = 32.0
	var right_margin = 12.0
	var top_margin = 46.0   # Bande haute : HUD dynamique moteur & bascule d'analyse
	var bottom_margin = 26.0 # Bande basse : libellé du coup courant, hors courbe

	var graph_w = maxf(10.0, w - left_margin - right_margin)
	var graph_h = maxf(10.0, h - top_margin - bottom_margin)
	var mid_y = top_margin + graph_h * 0.5

	# 1. Fond sombre élégant
	draw_rect(Rect2(0, 0, w, h), Color("#090e1a"), true)
	draw_rect(Rect2(0, 0, w, h), Color("#1e293b"), false, 1.0)

	# 2. Échelle Y logarithmique symétrique (symlog) et lignes repères
	# Permet de distinguer finement les petits avantages (0..2 pions) tout en visualisant
	# les grosses variations (+5, +10, mats) sans saturation abrupte.
	# Formule : sign(cp) * log(1 + |cp| / C) / log(1 + max_cp / C)
	var max_display_cp: float = 1200.0 # Échelle jusqu'à ±12 pions (ou mat)
	var symlog_c: float = 150.0 # Constante de transition linéaire -> log (1.5 pion)
	var max_log_val: float = log(1.0 + max_display_cp / symlog_c)
	var half_h: float = float(graph_h) * 0.44

	var eval_to_y = func(cp: float) -> float:
		var sign_cp: float = 1.0 if cp >= 0.0 else -1.0
		var abs_cp: float = minf(absf(cp), max_display_cp)
		var norm: float = (log(1.0 + abs_cp / symlog_c) / max_log_val) * sign_cp
		return mid_y - (norm * half_h)

	var default_font = ThemeDB.fallback_font
	var font_size = 11

	# Lignes repères clés : +5.0, +2.0, 0.0, -2.0, -5.0
	var guide_evals := [500.0, 200.0, -200.0, -500.0]
	var guide_labels := ["+5.0", "+2.0", "-2.0", "-5.0"]
	for k in range(guide_evals.size()):
		var g_cp = guide_evals[k]
		var gy = eval_to_y.call(g_cp)
		var is_major = absf(g_cp) == 500.0
		var col = Color("#47556944") if is_major else Color("#33415533")
		draw_line(Vector2(left_margin, gy), Vector2(w - right_margin, gy), col, 1.0)
		draw_string(default_font, Vector2(3, gy + 3), guide_labels[k], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, DesignTokens.TEXT_MUTED)

	# Ligne médiane 0.0 (Parité / Égalité)
	draw_line(Vector2(left_margin, mid_y), Vector2(w - right_margin, mid_y), Color("#38bdf888"), 1.5)
	draw_string(default_font, Vector2(6, mid_y + 3), " 0.0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, DesignTokens.ACCENT)

	# 3. État sans données : Affichage explicite du mode d'emploi
	var total_points = evaluations.size()
	if total_points < 2:
		var msg1 = "📈 Courbe d'Avantage"
		var msg2 = "Touchez « Analyser » sous le plateau pour la tracer"
		var s1 := 18
		var s2 := 15
		var msg1_w = default_font.get_string_size(msg1, HORIZONTAL_ALIGNMENT_LEFT, -1, s1).x
		var msg2_w = default_font.get_string_size(msg2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2).x
		draw_string(default_font, Vector2((w - msg1_w) * 0.5, mid_y - 8), msg1, HORIZONTAL_ALIGNMENT_LEFT, -1, s1, DesignTokens.TEXT_SECONDARY)
		draw_string(default_font, Vector2((w - msg2_w) * 0.5, mid_y + 16), msg2, HORIZONTAL_ALIGNMENT_LEFT, -1, s2, DesignTokens.TEXT_MUTED)
		return

	# 4. Calcul des coordonnées des points & halo de l'intervalle de confiance (IC 95%)
	var step_x = graph_w / float(total_points - 1)
	var points = PackedVector2Array()
	var ci_upper_points = PackedVector2Array()
	var ci_lower_points = PackedVector2Array()

	for i in range(total_points):
		var record = evaluations[i]
		var score_cp = float(record.get("score_cp", 0))
		var px = left_margin + i * step_x
		var py = eval_to_y.call(score_cp)
		points.append(Vector2(px, py))

		var margin = float(record.get("ci_margin", 35.0))
		var ci_u = score_cp + margin
		var ci_l = score_cp - margin
		ci_upper_points.append(Vector2(px, eval_to_y.call(ci_u)))
		ci_lower_points.append(Vector2(px, eval_to_y.call(ci_l)))

	# 5. Bande d'intervalle de confiance (IC 95% ombré doux)
	var ci_poly = PackedVector2Array()
	for p_u in ci_upper_points:
		ci_poly.append(p_u)
	for j in range(ci_lower_points.size() - 1, -1, -1):
		ci_poly.append(ci_lower_points[j])
	draw_colored_polygon(ci_poly, Color(0.22, 0.74, 0.97, 0.12))
	draw_polyline(ci_upper_points, Color(0.22, 0.74, 0.97, 0.25), 1.0, true)
	draw_polyline(ci_lower_points, Color(0.22, 0.74, 0.97, 0.25), 1.0, true)

	# 6. Polygones de remplissage distinctifs :
	# Aire blanche pure et soignée du côté blanc (au-dessus de mid_y),
	# Aire noire profonde du côté noir (en-dessous de mid_y).
	var fill_white = PackedVector2Array([Vector2(left_margin, mid_y)])
	for p in points:
		fill_white.append(Vector2(p.x, min(p.y, mid_y)))
	fill_white.append(Vector2(left_margin + graph_w, mid_y))
	draw_colored_polygon(fill_white, Color(0.95, 0.96, 0.98, 0.35))

	var fill_black = PackedVector2Array([Vector2(left_margin, mid_y)])
	for p in points:
		fill_black.append(Vector2(p.x, max(p.y, mid_y)))
	fill_black.append(Vector2(left_margin + graph_w, mid_y))
	draw_colored_polygon(fill_black, Color(0.02, 0.03, 0.06, 0.70))

	# Liseré doux séparateur sur les contours des aires
	draw_polyline(fill_white, Color(1.0, 1.0, 1.0, 0.25), 1.0, true)
	draw_polyline(fill_black, Color(0.0, 0.0, 0.0, 0.50), 1.0, true)

	# 7. Tracé de la courbe principale
	draw_polyline(points, Color("#38bdf8"), 2.2, true)

	# 8. Pastilles pour les coups marquants (seulement pour les coups analysés)
	for i in range(total_points):
		var record = evaluations[i]
		if record.get("is_placeholder", false):
			continue
		var quality = record.get("quality", ChessMove.Quality.NONE)
		var pt = points[i]

		if quality == ChessMove.Quality.BLUNDER:
			draw_circle(pt, 4.5, Color("#ef4444"))
			draw_arc(pt, 4.5, 0, TAU, 16, Color("#ffffff"), 1.0)
		elif quality == ChessMove.Quality.MISTAKE:
			draw_circle(pt, 3.5, Color("#f97316"))
		elif quality == ChessMove.Quality.BRILLIANT:
			draw_circle(pt, 5.0, Color("#10b981"))
			draw_arc(pt, 5.0, 0, TAU, 16, Color("#ffffff"), 1.2)

	# 9. Curseur actif : ligne + point, SANS texte superposé à la courbe.
	if active_ply >= 0 and active_ply < points.size():
		var cursor_pt = points[active_ply]
		draw_line(Vector2(cursor_pt.x, top_margin), Vector2(cursor_pt.x, h - bottom_margin), Color("#facc15aa"), 1.8)
		draw_circle(cursor_pt, 5.0, Color("#facc15"))
		draw_arc(cursor_pt, 5.0, 0, TAU, 16, Color("#090e1a"), 1.5)
	elif active_ply == -1 and not points.is_empty():
		# Curseur positionné sur le bord gauche de départ
		var init_y = eval_to_y.call(20.0)
		draw_line(Vector2(left_margin, top_margin), Vector2(left_margin, h - bottom_margin), Color("#facc15aa"), 1.8)
		draw_circle(Vector2(left_margin, init_y), 5.0, Color("#facc15"))
		draw_arc(Vector2(left_margin, init_y), 5.0, 0, TAU, 16, Color("#090e1a"), 1.5)

	# 10. Libellé du coup courant dans la bande basse avec IC (hors de la courbe).
	if active_ply == -1 and not evaluations.is_empty():
		var caption = "Position initiale   (+0.2)"
		draw_rect(Rect2(left_margin, h - 24, graph_w, 20), Color("#0f172acc"), true)
		var cap_w = graph_w - 8.0
		draw_string(default_font, Vector2(left_margin + 4, h - 7), caption,
				HORIZONTAL_ALIGNMENT_LEFT, int(cap_w), 13, DesignTokens.TEXT_PRIMARY)
	else:
		var rec = evaluations[active_ply] if active_ply >= 0 and active_ply < evaluations.size() else {}
		if not rec.is_empty():
			var score_cp = rec.get("score_cp", 0)
			var pawns_val = score_cp / 100.0
			var eval_str = ("+%.1f" if pawns_val >= 0 else "%.1f") % pawns_val
			var margin_pawns = float(rec.get("ci_margin", 0.0)) / 100.0
			var ci_str = " [±%.1f]" % margin_pawns if margin_pawns > 0.0 else ""
			var move_num = rec.get("move_number", 1)
			var san = rec.get("san", "")
			var is_w = rec.get("is_white", true)
			var qual = rec.get("quality", ChessMove.Quality.NONE)
			var badge_sym = ChessMove.quality_to_symbol(qual)
			var ply_label = ("%d. %s" if is_w else "%d... %s") % [move_num, san]
			if badge_sym != "":
				ply_label += " " + badge_sym
			var caption = "%s   (%s%s)" % [ply_label, eval_str, ci_str]
			draw_rect(Rect2(left_margin, h - 24, graph_w, 20), Color("#0f172acc"), true)
			var cap_w = graph_w - 8.0
			draw_string(default_font, Vector2(left_margin + 4, h - 7), caption,
					HORIZONTAL_ALIGNMENT_LEFT, int(cap_w), 13, DesignTokens.TEXT_PRIMARY)

# --- SCRUBBING TACTILE & NAVIGATION ---

func _gui_input(event: InputEvent) -> void:
	if evaluations.is_empty():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_scrubbing = true
			_scrub_to(event.position.x, true)
		else:
			_scrubbing = false
			_commit_scrub()
	elif event is InputEventMouseMotion:
		if _scrubbing and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_scrub_to(event.position.x, false)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_scrubbing = true
			_scrub_to(event.position.x, true)
		else:
			_scrubbing = false
			_commit_scrub()
	elif event is InputEventScreenDrag and _scrubbing:
		_scrub_to(event.position.x, false)

## Ply sous le doigt (hors de la colonne d'échelle de gauche).
func _ply_at(pos_x: float) -> int:
	var total_points = evaluations.size()
	if total_points == 0:
		return -1
	var left_margin = 32.0
	var right_margin = 12.0
	var graph_w = maxf(1.0, size.x - left_margin - right_margin)
	var ratio = clampf((pos_x - left_margin) / graph_w, 0.0, 1.0)
	return clampi(int(round(ratio * (total_points - 1))), 0, total_points - 1)

## Scrubbing (M2) : le marqueur suit le doigt à chaque événement (instantané),
## mais la navigation moteur est throttlée (~90 ms) pour éviter les rafales
## d'animations / le flash et les évaluations en double ; un unique navigate
## final est validé au relâchement (_commit_scrub).
func _scrub_to(pos_x: float, force: bool) -> void:
	var target = _ply_at(pos_x)
	if target < 0 or target == active_ply:
		return
	active_ply = target
	queue_redraw()
	move_scrubbed.emit(target)
	var now := Time.get_ticks_msec()
	if force or now - _last_nav_ms >= SCRUB_NAV_MS:
		_last_nav_ms = now
		var gc = get_node_or_null("/root/GameController")
		if gc:
			gc.navigate_to_ply(target)

func _commit_scrub() -> void:
	if active_ply >= 0:
		var gc = get_node_or_null("/root/GameController")
		if gc:
			gc.navigate_to_ply(active_ply)

func _on_move_navigated(move_idx: int) -> void:
	active_ply = move_idx
	queue_redraw()

