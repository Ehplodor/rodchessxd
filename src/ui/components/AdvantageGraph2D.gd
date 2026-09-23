class_name AdvantageGraph2D
extends Control
## AdvantageGraph2D.gd - Graphe vectoriel interactif de la courbe d'avantage avec axes, HUD et zoom

signal move_scrubbed(ply_index: int)
signal analysis_selected(analysis_entry: Dictionary)

var evaluations: Array = []
var active_ply: int = -1
## T2.3 — Bornes de phase (plies) à matérialiser par des traits verticaux.
var phase_boundaries: Array = []

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

var _cached_points: PackedVector2Array = PackedVector2Array()
var _cached_ci_poly: PackedVector2Array = PackedVector2Array()
var _cached_ci_upper: PackedVector2Array = PackedVector2Array()
var _cached_ci_lower: PackedVector2Array = PackedVector2Array()
var _cached_fill_white: PackedVector2Array = PackedVector2Array()
var _cached_fill_black: PackedVector2Array = PackedVector2Array()
var _geom_dirty: bool = true
var _cached_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Compact : le graphe cède la place au plateau (élément central) sur les écrans
	# courts, et s'étend au-delà quand la hauteur disponible le permet.
	custom_minimum_size = Vector2(0, 96)
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

	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.settings_changed.connect(func(key, _val):
			if key == "app_theme_mode":
				queue_redraw()
		)

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
	# Police d'un cran plus petite et largeur confortable : les glyphes émoji
	# (⚡/✓) sont plus larges sur appareil que dans les métriques de test.
	depth_label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	depth_label.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	# Doit pouvoir se compacter dans la TopBar sur écrans étroits (360 px).
	depth_label.clip_text = true
	depth_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	depth_label.custom_minimum_size.x = 0
	badge_vbox.add_child(depth_label)

	depth_progress_bar = ProgressBar.new()
	depth_progress_bar.custom_minimum_size = Vector2(130, 3)
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
	btn_switch_analysis.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	btn_switch_analysis.custom_minimum_size = Vector2(140, 32)
	btn_switch_analysis.clip_text = true
	btn_switch_analysis.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn_switch_analysis.tooltip_text = "Cliquer pour basculer entre les différentes analyses de moteurs enregistrées"
	btn_switch_analysis.add_theme_stylebox_override("normal", chip_normal)
	btn_switch_analysis.add_theme_stylebox_override("hover", chip_hover)
	btn_switch_analysis.add_theme_stylebox_override("pressed", chip_pressed)
	btn_switch_analysis.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	btn_switch_analysis.pressed.connect(_cycle_analysis)
	add_child(btn_switch_analysis)

	_update_button_positions()

## Positionnement manuel du HUD : uniquement s'il vit encore dans le graphe.
## Dans la TopBar (cas nominal), le HBoxContainer gère la disposition.
func _update_button_positions() -> void:
	if depth_badge == null or not is_instance_valid(depth_badge) \
			or depth_badge.get_parent() != self:
		return
	var right_cursor = size.x - 8
	var min_allowed_x = 36.0
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

func prepare_live_analysis(total_plies: int) -> void:
	evaluations.clear()
	phase_boundaries.clear()
	var n = maxi(2, total_plies)
	for i in range(n):
		var info: Dictionary = ChessGame.ply_info_from_fen(_start_fen(), i)
		evaluations.append({
			"ply": i,
			"move_number": info["move_number"],
			"is_white": info["is_white"],
			"score_cp": 0,
			"ci_margin": 140.0,
			"ci_lower": -140.0,
			"ci_upper": 140.0,
			"is_placeholder": true
		})
	active_ply = 0
	_geom_dirty = true
	queue_redraw()

func _start_fen() -> String:
	var gc = get_node_or_null("/root/GameController")
	return gc.game.start_fen if gc and gc.game else ChessGame.INITIAL_FEN

func update_live_ply(ply_idx: int, record: Dictionary) -> void:
	while evaluations.size() <= ply_idx:
		evaluations.append({})
	record["is_placeholder"] = false
	evaluations[ply_idx] = record
	active_ply = ply_idx
	_geom_dirty = true
	queue_redraw()

func set_evaluations(eval_data: Array) -> void:
	evaluations.clear()
	for item in eval_data:
		if item is Dictionary:
			evaluations.append(item)
	if not evaluations.is_empty() and (active_ply < 0 or active_ply >= evaluations.size()):
		active_ply = evaluations.size() - 1
	_geom_dirty = true
	queue_redraw()

## T2.3 — Définit les plies de séparation de phases à afficher sur le graphe.
func set_phase_boundaries(bounds: Array) -> void:
	phase_boundaries = bounds.duplicate()
	queue_redraw()

## Style du marqueur affiché sur la courbe pour un coup remarquable.
## Source unique de vérité (cohérence rapport/graphe) : toute qualité non listée ici
## n'affiche aucun marqueur. Les couleurs proviennent de `ChessMove.quality_to_color`,
## identiques aux badges de la liste des coups et aux boutons « Moments clés » du rapport.
## L'ensemble couvre exactement les catégories remarquables du rapport :
## !!/! (positif), ?! (imprécision), ? (erreur), ??/X (gaffe ou occasion manquée).
static func notable_marker_for(quality: int) -> Dictionary:
	match quality:
		ChessMove.Quality.BRILLIANT:
			return {"radius": 5.0, "color": ChessMove.quality_to_color(quality), "ring": 1.2}
		ChessMove.Quality.GREAT:
			return {"radius": 4.5, "color": ChessMove.quality_to_color(quality), "ring": 1.0}
		ChessMove.Quality.BLUNDER, ChessMove.Quality.MISS:
			return {"radius": 4.5, "color": ChessMove.quality_to_color(quality), "ring": 1.0}
		ChessMove.Quality.MISTAKE:
			return {"radius": 3.5, "color": ChessMove.quality_to_color(quality), "ring": 0.0}
		ChessMove.Quality.INACCURACY:
			return {"radius": 2.5, "color": ChessMove.quality_to_color(quality), "ring": 0.0}
		_:
			return {}

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_button_positions()
		_geom_dirty = true
		queue_redraw()

# --- Géométrie ---
const MARGIN_LEFT := 32.0
const MARGIN_RIGHT := 12.0
const MARGIN_TOP := 10.0
const MARGIN_BOTTOM := 26.0  # Bande basse : libellé du coup courant, hors courbe
## Échelle symlog : fine autour de 0 (±1,5 pion quasi linéaire), compressée jusqu'à ±12 pions.
const MAX_DISPLAY_CP := 1200.0
const SYMLOG_C := 150.0
## Un mat se place au-delà de toute évaluation affichable (norme > 1).
const MATE_NORM := 1.12

## Évaluation (cp, point de vue Blancs) de la position de départ, avant le premier coup.
var start_score_cp: int = 20
var _poly_ok: Dictionary = {}

func set_start_score(cp: int) -> void:
	start_score_cp = cp
	_geom_dirty = true
	queue_redraw()

func _plot_rect() -> Rect2:
	return Rect2(MARGIN_LEFT, MARGIN_TOP,
			maxf(10.0, size.x - MARGIN_LEFT - MARGIN_RIGHT),
			maxf(10.0, size.y - MARGIN_TOP - MARGIN_BOTTOM))

## Ordonnée d'une évaluation (symlog symétrique, mats au-delà du plafond).
func _eval_to_y(cp: float, mate_in: int = 0) -> float:
	var r := _plot_rect()
	var mid_y := r.position.y + r.size.y * 0.5
	var half_h := r.size.y * 0.44
	var norm: float
	if mate_in != 0 or absf(cp) >= 9000.0:
		var white_mates := mate_in > 0 if mate_in != 0 else cp > 0.0
		norm = MATE_NORM if white_mates else -MATE_NORM
	else:
		var abs_cp := minf(absf(cp), MAX_DISPLAY_CP)
		norm = signf(cp) * log(1.0 + abs_cp / SYMLOG_C) / log(1.0 + MAX_DISPLAY_CP / SYMLOG_C)
	return mid_y - norm * half_h

## Abscisse du demi-coup `ply` (-1 = position de départ, au bord gauche).
func _ply_to_x(ply: int) -> float:
	var r := _plot_rect()
	var n := maxi(1, evaluations.size())
	return r.position.x + float(ply + 1) * r.size.x / float(n)

func _rebuild_geometry() -> void:
	_cached_size = size
	_geom_dirty = false
	var r := _plot_rect()
	var mid_y := r.position.y + r.size.y * 0.5
	_cached_points.clear()
	_cached_ci_upper.clear()
	_cached_ci_lower.clear()
	_cached_ci_poly.clear()
	_cached_fill_white.clear()
	_cached_fill_black.clear()

	_cached_points.append(Vector2(r.position.x, _eval_to_y(float(start_score_cp))))
	_cached_ci_upper.append(_cached_points[0])
	_cached_ci_lower.append(_cached_points[0])
	for i in range(evaluations.size()):
		var record: Dictionary = evaluations[i]
		var score_cp := float(record.get("score_cp", 0))
		var mate_in := int(record.get("mate_in", 0))
		var px := _ply_to_x(i)
		_cached_points.append(Vector2(px, _eval_to_y(score_cp, mate_in)))
		var margin := float(record.get("ci_margin", 35.0))
		_cached_ci_upper.append(Vector2(px, _eval_to_y(score_cp + margin, mate_in)))
		_cached_ci_lower.append(Vector2(px, _eval_to_y(score_cp - margin, mate_in)))

	_cached_ci_poly.append_array(_cached_ci_upper)
	for k in range(_cached_ci_lower.size() - 1, -1, -1):
		_cached_ci_poly.append(_cached_ci_lower[k])

	# Aires Blancs/Noirs : la courbe est coupée EXACTEMENT sur l'axe 0 à chaque
	# changement de signe (sinon les aires débordent en biseau de l'autre côté).
	var axis_pts := PackedVector2Array()
	for k in range(_cached_points.size()):
		var p := _cached_points[k]
		if k > 0:
			var q := _cached_points[k - 1]
			if (q.y - mid_y) * (p.y - mid_y) < 0.0:
				var t := (mid_y - q.y) / (p.y - q.y)
				axis_pts.append(Vector2(lerpf(q.x, p.x, t), mid_y))
		axis_pts.append(p)
	var right := r.position.x + r.size.x
	_cached_fill_white.append(Vector2(r.position.x, mid_y))
	_cached_fill_black.append(Vector2(r.position.x, mid_y))
	for p in axis_pts:
		_cached_fill_white.append(Vector2(p.x, minf(p.y, mid_y)))
		_cached_fill_black.append(Vector2(p.x, maxf(p.y, mid_y)))
	_cached_fill_white.append(Vector2(right, mid_y))
	_cached_fill_black.append(Vector2(right, mid_y))

	# Triangulation vérifiée une fois par géométrie, pas à chaque image.
	_poly_ok = {
		"ci": Geometry2D.triangulate_polygon(_cached_ci_poly).size() > 0,
		"white": Geometry2D.triangulate_polygon(_cached_fill_white).size() > 0,
		"black": Geometry2D.triangulate_polygon(_cached_fill_black).size() > 0,
	}

func _draw() -> void:
	var w := size.x
	var h := size.y
	var r := _plot_rect()
	var mid_y := r.position.y + r.size.y * 0.5
	var right := r.position.x + r.size.x
	var font := ThemeDB.fallback_font
	var fs := DesignTokens.FONT_MICRO - 1

	# 1. Fond + cadre.
	draw_rect(Rect2(0, 0, w, h), DesignTokens.BG_DEEP, true)
	draw_rect(Rect2(0.5, 0.5, w - 1.0, h - 1.0), DesignTokens.BORDER, false, DesignTokens.STROKE_HAIR)

	# 2. Repères ±2 et ±5 pions + axe d'égalité.
	var grid := DesignTokens.col("GRAPH_GRID")
	for g_cp in [500.0, 200.0, -200.0, -500.0]:
		var gy := _eval_to_y(g_cp)
		var c := grid if absf(g_cp) == 500.0 else Color(grid, grid.a * 0.6)
		draw_line(Vector2(r.position.x, gy), Vector2(right, gy), c, DesignTokens.STROKE_HAIR)
		draw_string(font, Vector2(3, gy + 4), "%+.1f" % (g_cp / 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignTokens.TEXT_MUTED)
	draw_line(Vector2(r.position.x, mid_y), Vector2(right, mid_y), Color(DesignTokens.ACCENT, 0.55), DesignTokens.STROKE_THIN)
	draw_string(font, Vector2(6, mid_y + 4), " 0.0", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DesignTokens.ACCENT)

	# 3. Sans données : mode d'emploi.
	if evaluations.is_empty():
		_draw_centered(font, "📈 Courbe d'avantage", mid_y - 8, DesignTokens.FONT_BODY, DesignTokens.TEXT_SECONDARY)
		_draw_centered(font, "Touchez « Analyser » sous le plateau pour la tracer", mid_y + 16, DesignTokens.FONT_CAPTION, DesignTokens.TEXT_MUTED)
		return

	if _geom_dirty or size != _cached_size:
		_rebuild_geometry()

	# 4. Bande d'intervalle de confiance.
	var ci_col := DesignTokens.ACCENT
	if _poly_ok.get("ci", false):
		draw_colored_polygon(_cached_ci_poly, Color(ci_col, 0.12))
	draw_polyline(_cached_ci_upper, Color(ci_col, 0.25), DesignTokens.STROKE_HAIR, true)
	draw_polyline(_cached_ci_lower, Color(ci_col, 0.25), DesignTokens.STROKE_HAIR, true)

	# 5. Aires d'avantage Blancs (au-dessus) / Noirs (en dessous).
	if _poly_ok.get("white", false):
		draw_colored_polygon(_cached_fill_white, DesignTokens.col("GRAPH_WHITE_AREA"))
	if _poly_ok.get("black", false):
		draw_colored_polygon(_cached_fill_black, DesignTokens.col("GRAPH_BLACK_AREA"))

	# 6. Repères de phase (fin d'ouverture, début de finale).
	for bound in phase_boundaries:
		var bp := int(bound)
		if bp <= 0 or bp >= evaluations.size():
			continue
		var bx := _ply_to_x(bp)
		draw_dashed_line(Vector2(bx, r.position.y), Vector2(bx, r.end.y), Color(DesignTokens.TEXT_MUTED, 0.45),
				DesignTokens.STROKE_HAIR, 5.0, true, true)

	# 7. Courbe principale.
	draw_polyline(_cached_points, DesignTokens.ACCENT, DesignTokens.STROKE, true)

	# 8. Pastilles des coups remarquables (taxonomie du rapport).
	for i in range(evaluations.size()):
		var record: Dictionary = evaluations[i]
		if record.get("is_placeholder", false):
			continue
		var marker := notable_marker_for(int(record.get("quality", ChessMove.Quality.NONE)))
		if marker.is_empty():
			continue
		var pt := _cached_points[i + 1]
		var mr := float(marker["radius"])
		draw_circle(pt, mr, marker["color"], true, -1.0, true)
		if float(marker["ring"]) > 0.0:
			draw_arc(pt, mr, 0, TAU, DesignTokens.arc_segments(mr), DesignTokens.TEXT_PRIMARY, float(marker["ring"]), true)

	# 9. Curseur actif (-1 = position de départ).
	var cur := clampi(active_ply, -1, evaluations.size() - 1)
	var cpt := _cached_points[cur + 1]
	var cursor := DesignTokens.col("CURSOR")
	draw_line(Vector2(cpt.x, r.position.y), Vector2(cpt.x, r.end.y), Color(cursor, 0.65), DesignTokens.STROKE_THIN)
	draw_circle(cpt, 5.0, cursor, true, -1.0, true)
	draw_arc(cpt, 5.0, 0, TAU, DesignTokens.arc_segments(5.0), DesignTokens.BG_DEEP, DesignTokens.STROKE_THIN, true)

	# 10. Libellé du coup courant dans la bande basse (jamais sur la courbe).
	var caption := "Position initiale   (%s)" % EvalFormatter.format_cp_mate(start_score_cp, 0)
	if cur >= 0:
		var rec: Dictionary = evaluations[cur]
		var eval_str := EvalFormatter.format_cp_mate(int(rec.get("score_cp", 0)), int(rec.get("mate_in", 0)))
		var margin_pawns := float(rec.get("ci_margin", 0.0)) / 100.0
		var ci_str := " [±%.1f]" % margin_pawns if margin_pawns > 0.0 else ""
		var ply_label := ("%d. %s" if rec.get("is_white", true) else "%d... %s") % [int(rec.get("move_number", 1)), str(rec.get("san", ""))]
		var badge_sym := ChessMove.quality_to_symbol(rec.get("quality", ChessMove.Quality.NONE))
		if badge_sym != "":
			ply_label += " " + badge_sym
		caption = "%s   (%s%s)" % [ply_label, eval_str, ci_str]
	draw_rect(Rect2(r.position.x, h - 24, r.size.x, 20), DesignTokens.SURFACE_ELEVATED, true)
	draw_string(font, Vector2(r.position.x + 4, h - 7), caption, HORIZONTAL_ALIGNMENT_LEFT,
			int(r.size.x - 8.0), DesignTokens.FONT_MICRO + 1, DesignTokens.TEXT_PRIMARY)

func _draw_centered(font: Font, text: String, y: float, fs: int, color: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(maxf(4.0, (size.x - tw) * 0.5), y), text, HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 8.0), fs, color)

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

## Ply sous le doigt (-1 = position de départ, au bord gauche).
func _ply_at(pos_x: float) -> int:
	var n := evaluations.size()
	if n == 0:
		return -1
	var r := _plot_rect()
	var ratio := clampf((pos_x - r.position.x) / r.size.x, 0.0, 1.0)
	return clampi(int(round(ratio * n)) - 1, -1, n - 1)

## Scrubbing (M2) : le marqueur suit le doigt à chaque événement (instantané),
## mais la navigation moteur est throttlée (~90 ms) pour éviter les rafales
## d'animations / le flash et les évaluations en double ; un unique navigate
## final est validé au relâchement (_commit_scrub).
func _scrub_to(pos_x: float, force: bool) -> void:
	var target = _ply_at(pos_x)
	if evaluations.is_empty() or target == active_ply:
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
	if not evaluations.is_empty():
		var gc = get_node_or_null("/root/GameController")
		if gc:
			gc.navigate_to_ply(active_ply)

func _on_move_navigated(move_idx: int) -> void:
	active_ply = move_idx
	queue_redraw()
