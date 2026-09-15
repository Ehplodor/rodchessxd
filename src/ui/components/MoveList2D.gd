class_name MoveList2D
extends ScrollContainer
## MoveList2D.gd - Écran d'analyse et feuille de coups.
## Affiche en haut les statistiques parallèles des deux joueurs (3 colonnes),
## le résumé synthétique en un coup d'œil (vainqueur, ELO, qualité, répartition des coups),
## puis en dessous la feuille de notation interactive avec filtres de qualité.

signal moment_selected(ply: int)

const MoveQualityService = preload("res://src/ui/components/MoveQualityService.gd")

var container: VBoxContainer
var move_buttons: Array[Button] = []
var _active_btn: Button = null
var _last_moves_count: int = -1
var _analysis_report: Dictionary = {}
var _active_stylebox: StyleBoxFlat = null

# Filtre actif : 0 = TOUS, sinon un filtre par qualité (?? ? ?! ✓ ✓+ ★ ! !!)
var _filter := 0

## Largeur minimale d'un bouton de coup en mode dense (2 coups/ligne) : borne le calcul
## de hauteur du texte replié pour éviter des lignes anormalement hautes.
const _MOVE_MIN_W := 120.0

const _FILTERS := [
	{"label": "∅", "mode": 0, "tip": "Tous les coups", "color": Color("#64748b")},
	{"label": "??", "mode": 1, "tip": "Gaffes & Occasions manquées", "color": Color("#ef4444")},
	{"label": "?", "mode": 2, "tip": "Erreurs", "color": Color("#f97316")},
	{"label": "?!", "mode": 3, "tip": "Imprécisions", "color": Color("#eab308")},
	{"label": "✓", "mode": 4, "tip": "Bons coups", "color": Color("#94a3b8")},
	{"label": "✓+", "mode": 5, "tip": "Excellents coups", "color": Color("#84cc16")},
	{"label": "★", "mode": 6, "tip": "Meilleurs coups", "color": Color("#22c55e")},
	{"label": "!", "mode": 7, "tip": "Très bons coups", "color": Color("#3b82f6")},
	{"label": "!!", "mode": 8, "tip": "Coups brillants", "color": Color("#10b981")},
]

func _ready() -> void:
	custom_minimum_size = Vector2(0, 120)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(self)

	_ensure_container()

	var gc = _get_game_controller()
	if gc:
		gc.position_changed.connect(_on_position_changed)
		gc.move_navigated.connect(_on_move_navigated)

func _ensure_container() -> void:
	if container == null:
		container = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_theme_constant_override("separation", 8)
		add_child(container)

## Permet à Main d'injecter le rapport d'analyse complet
func set_analysis_report(report: Dictionary) -> void:
	_analysis_report = report
	var gc = _get_game_controller()
	if gc and report.has("evaluations"):
		gc.apply_evaluations(report.get("evaluations", []))
	_refresh_moves()

## Rafraîchissement public (appelé aussi à la fin de l'analyse, cf. Main).
func refresh() -> void:
	_refresh_moves()

func _on_position_changed() -> void:
	var gc = _get_game_controller()
	var cur_count = gc.game.move_history.size() if (gc and gc.game) else 0
	if cur_count != _last_moves_count:
		_refresh_moves()
	else:
		_update_active_button(gc.current_ply_index if gc else -1)

func _get_game_controller() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		return tree.root.get_node("GameController")
	return null

func _get_database_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("DatabaseManager"):
		return tree.root.get_node("DatabaseManager")
	return null

func _refresh_moves() -> void:
	_ensure_container()
	for child in container.get_children():
		child.queue_free()
	move_buttons.clear()
	_active_btn = null
	var gc = _get_game_controller()
	_last_moves_count = gc.game.move_history.size() if (gc and gc.game) else 0
	scroll_vertical = 0

	# Récupérer automatiquement l'analyse en base si non fournie
	if _analysis_report.is_empty():
		var dm = _get_database_manager()
		if dm and gc and gc.current_game_id != "":
			var g = dm.get_game(gc.current_game_id)
			var ea = g.get("engine_analyses", [])
			if not ea.is_empty():
				_analysis_report = ea.back()
				if gc and _analysis_report.has("evaluations"):
					gc.apply_evaluations(_analysis_report.get("evaluations", []))

	# 1. Bannière Héro (Résultat, Ouverture, Qualité globale, Différentiel ELO)
	_build_hero_card()

	# 2. Scorecard Duel Face-à-Face (Précision CAPS2, Jauge Duel, ELO, ACPL)
	_build_duel_scorecard()

	# 3. Matrice de Qualité interactive (8 catégories, cliquables pour filtrer)
	_build_quality_matrix()

	# 4. Progression par phases de jeu (Ouverture, Milieu, Finale)
	_build_phases_card()

	# 5. Tournants et Moments clés (boutons puces avec navigation directe)
	_build_moments_card()

	# 6. Titre de la feuille de notation des coups
	_build_moves_header()

	# 7. Barre des filtres interactifs
	_build_filter_row()

	# 8. Liste détaillée des coups
	_build_moves()
	call_deferred("_scroll_to_active")

# --- NOMS DES JOUEURS ---
func _get_player_names() -> Dictionary:
	var gc = _get_game_controller()
	var headers: Dictionary = gc.game.pgn_headers if (gc and gc.game) else {}
	var w: String = str(headers.get("White", "")).strip_edges()
	var b: String = str(headers.get("Black", "")).strip_edges()
	if w == "" or w.to_lower() in ["player 1", "joueur 1", "?"]:
		w = "Blancs"
	if b == "" or b.to_lower() in ["player 2", "joueur 2", "?"]:
		b = "Noirs"
	return {"white": w, "black": b}

# --- STATISTIQUES QUALITATIVES DES DEUX CAMPS ---
func _get_player_quality_stats() -> Dictionary:
	var w_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0}
	var b_stats := {"brilliant": 0, "great": 0, "best": 0, "excellent": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0, "miss": 0}
	
	var gc = _get_game_controller()
	if _analysis_report.has("white_stats") and not _analysis_report["white_stats"].is_empty():
		w_stats = _analysis_report["white_stats"]
		b_stats = _analysis_report.get("black_stats", {})
	elif gc and gc.game:
		for i in range(gc.game.move_history.size()):
			var m = gc.game.move_history[i]
			if m.is_theory:
				continue
			var is_w = (i % 2 == 0)
			var target = w_stats if is_w else b_stats
			match m.quality:
				ChessMove.Quality.BRILLIANT: target["brilliant"] += 1
				ChessMove.Quality.BEST: target["best"] += 1
				ChessMove.Quality.GREAT: target["great"] += 1
				ChessMove.Quality.EXCELLENT: target["excellent"] += 1
				ChessMove.Quality.GOOD: target["good"] += 1
				ChessMove.Quality.INACCURACY: target["inaccuracy"] += 1
				ChessMove.Quality.MISTAKE: target["mistake"] += 1
				ChessMove.Quality.BLUNDER: target["blunder"] += 1
				ChessMove.Quality.MISS: target["miss"] += 1
	return {"white": w_stats, "black": b_stats}

# --- 1. BANNIÈRE HÉRO (Résultat, Ouverture, Qualité, Différentiel) ---
func _build_hero_card() -> void:
	var names = _get_player_names()
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(12, 10))
	card.add_theme_stylebox_override("panel", c_style)
	container.add_child(card)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Résultat / Vainqueur
	var outcome_text = "♟️ Partie en cours"
	var outcome_color = DesignTokens.ACCENT

	var gc = _get_game_controller()
	if gc and gc.game:
		var cur_col = gc.game.active_color
		var in_chk = gc.game.is_in_check(cur_col)
		var no_moves = gc.game.get_legal_moves(cur_col).is_empty()
		var pgn_res = str(gc.game.pgn_headers.get("Result", "*")).strip_edges()

		if no_moves:
			if in_chk:
				var winner_is_white = (cur_col == ChessPiece.PieceColor.BLACK)
				var winner_name = names["white"] if winner_is_white else names["black"]
				outcome_text = "🏆 Victoire de %s (Échec et mat)" % winner_name
				outcome_color = Color("#34d399")
			else:
				outcome_text = "🤝 Partie Nulle par pat"
				outcome_color = Color("#94a3b8")
		elif pgn_res == "1-0":
			outcome_text = "🏆 Victoire de %s (1-0)" % names["white"]
			outcome_color = Color("#34d399")
		elif pgn_res == "0-1":
			outcome_text = "🏆 Victoire de %s (0-1)" % names["black"]
			outcome_color = Color("#34d399")
		elif pgn_res in ["1/2-1/2", "0.5-0.5"]:
			outcome_text = "🤝 Partie Nulle convenue (½ - ½)"
			outcome_color = Color("#94a3b8")

	# Badge de résultat proéminent
	var outcome_badge = PanelContainer.new()
	outcome_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ob_style = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_SMALL,
			outcome_color.lerp(DesignTokens.BORDER, 0.4), 1, Vector2(10, 6))
	outcome_badge.add_theme_stylebox_override("panel", ob_style)
	vbox.add_child(outcome_badge)

	var outcome_lbl = Label.new()
	outcome_lbl.text = outcome_text
	outcome_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outcome_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	outcome_lbl.add_theme_color_override("font_color", outcome_color)
	outcome_badge.add_child(outcome_lbl)

	# Ouverture (si présente)
	var opening: Dictionary = _analysis_report.get("opening", {})
	var opening_name := str(opening.get("name", ""))
	if opening_name != "":
		var eco := str(opening.get("eco", ""))
		var open_lbl := Label.new()
		open_lbl.text = "📖 %s%s" % [("%s — " % eco) if eco != "" else "", opening_name]
		open_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		open_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		open_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		open_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		vbox.add_child(open_lbl)

	# Qualité globale & Différentiel ELO
	if not _analysis_report.is_empty():
		var w_acc = float(_analysis_report.get("white_accuracy", 0.0))
		var b_acc = float(_analysis_report.get("black_accuracy", 0.0))
		var avg_acc = (w_acc + b_acc) * 0.5

		var qual_label = "Partie équilibrée"
		if avg_acc >= 85.0:
			qual_label = "Partie d'excellence (Niveau Maître)"
		elif avg_acc >= 75.0:
			qual_label = "Très bonne partie (Haute précision)"
		elif avg_acc >= 65.0:
			qual_label = "Partie disputée avec imprécisions tactiques"
		else:
			qual_label = "Partie animée et riche en rebondissements"

		var qual_lbl = Label.new()
		qual_lbl.text = "⭐ Qualité globale : %s (Précision moy. %.1f%%)" % [qual_label, avg_acc]
		qual_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qual_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qual_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		qual_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		qual_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		vbox.add_child(qual_lbl)

		# Différentiel ELO & test statistique
		var comp: Dictionary = _analysis_report.get("elo_comparison", {})
		var diff_elo = int(comp.get("diff_elo", _analysis_report.get("white_estimated_elo", 1500) - _analysis_report.get("black_estimated_elo", 1500)))
		var stars = comp.get("stars", "ns")
		var p_val = float(comp.get("p_value", 1.0))
		var p_str = "p < 0.001" if p_val < 0.001 else "p=%.3f" % p_val
		var favored_name = names["white"] if diff_elo >= 0 else names["black"]

		var elo_lbl = Label.new()
		elo_lbl.text = "📈 Différentiel : Δ %+d ELO en faveur de %s • %s %s" % [abs(diff_elo), favored_name, p_str, stars]
		elo_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elo_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elo_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		elo_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		vbox.add_child(elo_lbl)

		# Complexité moyenne & Cadence
		var w_cx = float(_analysis_report.get("white_complexity_avg", 1.0))
		var b_cx = float(_analysis_report.get("black_complexity_avg", 1.0))
		var avg_cx = (w_cx + b_cx) * 0.5
		var cx_word := "Modérée"
		if avg_cx >= 1.2:
			cx_word = "Élevée"
		elif avg_cx < 0.7:
			cx_word = "Faible"
		var meta_parts: Array = ["🧠 Complexité moy. : %s (%.1f)" % [cx_word, avg_cx]]
		if bool(_analysis_report.get("has_clock_data", false)):
			meta_parts.append("⏱ Cadence prise en compte")
		var meta_lbl = Label.new()
		meta_lbl.text = " • ".join(meta_parts)
		meta_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		meta_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		meta_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		vbox.add_child(meta_lbl)

# --- 2. SCORECARD DUEL (Face-à-Face, Précision, Jauge, ELO, ACPL) ---
func _build_duel_scorecard() -> void:
	var names = _get_player_names()
	var has_report = not _analysis_report.is_empty()
	var w_acc = float(_analysis_report.get("white_accuracy", 0.0))
	var b_acc = float(_analysis_report.get("black_accuracy", 0.0))
	var w_elo = int(_analysis_report.get("white_estimated_elo", 1500))
	var b_elo = int(_analysis_report.get("black_estimated_elo", 1500))
	var w_ci = int(_analysis_report.get("white_elo_ci", 0))
	var b_ci = int(_analysis_report.get("black_elo_ci", 0))
	var w_acpl = float(_analysis_report.get("white_acpl", 0.0))
	var b_acpl = float(_analysis_report.get("black_acpl", 0.0))

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	panel.add_theme_stylebox_override("panel", p_style)
	container.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "⚔️ Face-à-Face & Précision"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title_lbl)

	# Ligne des noms
	var names_row = HBoxContainer.new()
	names_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(names_row)

	var head_w = Label.new()
	head_w.text = "⚪ " + names["white"]
	head_w.tooltip_text = str(names["white"])
	head_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_w.clip_text = true
	head_w.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_w.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	head_w.add_theme_color_override("font_color", Color("#f8fafc"))
	names_row.add_child(head_w)

	var vs_lbl = Label.new()
	vs_lbl.text = "VS"
	vs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	vs_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	names_row.add_child(vs_lbl)

	var head_b = Label.new()
	head_b.text = names["black"] + " ⚫"
	head_b.tooltip_text = str(names["black"])
	head_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head_b.clip_text = true
	head_b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_b.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	head_b.add_theme_color_override("font_color", Color("#cbd5e1"))
	names_row.add_child(head_b)

	# Ligne Précision CAPS2 (grands chiffres)
	var acc_row = HBoxContainer.new()
	acc_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(acc_row)

	var w_acc_str = ("%.1f %%" % w_acc) if has_report else "—"
	var b_acc_str = ("%.1f %%" % b_acc) if has_report else "—"

	var lbl_w_acc = Label.new()
	lbl_w_acc.text = w_acc_str
	lbl_w_acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_w_acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_w_acc.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	lbl_w_acc.add_theme_color_override("font_color", Color("#34d399"))
	acc_row.add_child(lbl_w_acc)

	var lbl_mid_acc = Label.new()
	lbl_mid_acc.text = "🎯 Précision CAPS2"
	lbl_mid_acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_mid_acc.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_mid_acc.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	acc_row.add_child(lbl_mid_acc)

	var lbl_b_acc = Label.new()
	lbl_b_acc.text = b_acc_str
	lbl_b_acc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_b_acc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_b_acc.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	lbl_b_acc.add_theme_color_override("font_color", Color("#34d399"))
	acc_row.add_child(lbl_b_acc)

	# Barre Duel de Précision (Jauge horizontale bicolore)
	if has_report and (w_acc > 0.0 or b_acc > 0.0):
		var bar_box = HBoxContainer.new()
		bar_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_box.add_theme_constant_override("separation", 2)
		vbox.add_child(bar_box)

		var bar_w = Panel.new()
		bar_w.custom_minimum_size = Vector2(0, 8)
		bar_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_w.size_flags_stretch_ratio = maxf(1.0, w_acc)
		var sb_w = StyleBoxFlat.new()
		sb_w.bg_color = Color("#38bdf8")
		sb_w.set_corner_radius_all(3)
		bar_w.add_theme_stylebox_override("panel", sb_w)
		bar_box.add_child(bar_w)

		var bar_b = Panel.new()
		bar_b.custom_minimum_size = Vector2(0, 8)
		bar_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_b.size_flags_stretch_ratio = maxf(1.0, b_acc)
		var sb_b = StyleBoxFlat.new()
		sb_b.bg_color = Color("#818cf8")
		sb_b.set_corner_radius_all(3)
		bar_b.add_theme_stylebox_override("panel", sb_b)
		bar_box.add_child(bar_b)

	# Métriques secondaires : ELO estimé et ACPL
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	var w_elo_str = ("%d" % w_elo + (" ±%d" % w_ci if w_ci > 0 else "")) if has_report else "—"
	var b_elo_str = ("%d" % b_elo + (" ±%d" % b_ci if b_ci > 0 else "")) if has_report else "—"
	var w_acpl_str = ("%.1f cp" % w_acpl) if has_report else "—"
	var b_acpl_str = ("%.1f cp" % b_acpl) if has_report else "—"

	_add_stat_row(grid, w_elo_str, "📈 ELO estimé", b_elo_str, Color("#38bdf8"))
	_add_stat_row(grid, w_acpl_str, "📉 Perte moy. (ACPL)", b_acpl_str, Color("#fde047"))

# --- 3. MATRICE DE QUALITÉ DES COUPS (Interactive) ---
func _build_quality_matrix() -> void:
	var q_stats = _get_player_quality_stats()
	var w_s = q_stats["white"]
	var b_s = q_stats["black"]

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	panel.add_theme_stylebox_override("panel", p_style)
	container.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "🎯 Répartition de la Qualité des Coups"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title_lbl)

	var hint_lbl = Label.new()
	hint_lbl.text = "(Touchez une catégorie pour filtrer la notation)"
	hint_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	hint_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(hint_lbl)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(grid)

	_add_interactive_quality_row(grid, w_s.get("brilliant", 0), "‼ Coups brillants", b_s.get("brilliant", 0), Color("#38bdf8"), 8)
	_add_interactive_quality_row(grid, w_s.get("best", 0), "★ Meilleurs coups", b_s.get("best", 0), Color("#10b981"), 6)
	_add_interactive_quality_row(grid, w_s.get("great", 0) + w_s.get("excellent", 0), "✓+ Excellents coups", b_s.get("great", 0) + b_s.get("excellent", 0), Color("#14b8a6"), 5)
	_add_interactive_quality_row(grid, w_s.get("good", 0), "✓ Bons coups", b_s.get("good", 0), Color("#94a3b8"), 4)
	_add_interactive_quality_row(grid, w_s.get("inaccuracy", 0), "?! Imprécisions", b_s.get("inaccuracy", 0), Color("#eab308"), 3)
	_add_interactive_quality_row(grid, w_s.get("mistake", 0), "? Erreurs", b_s.get("mistake", 0), Color("#f97316"), 2)
	_add_interactive_quality_row(grid, w_s.get("blunder", 0) + w_s.get("miss", 0), "?? Gaffes", b_s.get("blunder", 0) + b_s.get("miss", 0), Color("#ef4444"), 1)

func _add_interactive_quality_row(grid: GridContainer, count_w: int, label_text: String, count_b: int, col: Color, filter_mode: int) -> void:
	var lbl_w = Label.new()
	lbl_w.text = str(count_w)
	lbl_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_w.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	lbl_w.add_theme_color_override("font_color", col if count_w > 0 else DesignTokens.TEXT_MUTED)
	grid.add_child(lbl_w)

	var is_active := (_filter == filter_mode)
	var btn = Button.new()
	btn.text = label_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.flat = not is_active
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.custom_minimum_size.y = 30
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn.add_theme_color_override("font_color", col)
	btn.tooltip_text = "Filtrer la notation sur : %s" % label_text

	var sb_norm = DesignTokens.flat(DesignTokens.BTN_BG_PRESSED if is_active else Color.TRANSPARENT,
			DesignTokens.RADIUS_SMALL, col if is_active else Color.TRANSPARENT, 1 if is_active else 0, Vector2(6, 2))
	var sb_h = DesignTokens.flat(DesignTokens.BTN_BG_HOVER, DesignTokens.RADIUS_SMALL, col, 1, Vector2(6, 2))
	btn.add_theme_stylebox_override("normal", sb_norm)
	btn.add_theme_stylebox_override("hover", sb_h)
	btn.add_theme_stylebox_override("pressed", sb_h)
	btn.pressed.connect(func():
		_filter = filter_mode if _filter != filter_mode else 0
		_refresh_moves()
	)
	grid.add_child(btn)

	var lbl_b = Label.new()
	lbl_b.text = str(count_b)
	lbl_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_b.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	lbl_b.add_theme_color_override("font_color", col if count_b > 0 else DesignTokens.TEXT_MUTED)
	grid.add_child(lbl_b)

func _add_stat_row(grid: GridContainer, val_w: String, label_text: String, val_b: String, accent_col: Color) -> void:
	var lbl_w = Label.new()
	lbl_w.text = val_w
	lbl_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_w.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_w.add_theme_color_override("font_color", accent_col)
	grid.add_child(lbl_w)

	var lbl_m = Label.new()
	lbl_m.text = label_text
	lbl_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_m.clip_text = true
	lbl_m.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_m.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_m.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	grid.add_child(lbl_m)

	var lbl_b = Label.new()
	lbl_b.text = val_b
	lbl_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl_b.add_theme_color_override("font_color", accent_col)
	grid.add_child(lbl_b)

# --- 4. PROGRESSION PAR PHASES DE JEU ---
func _build_phases_card() -> void:
	if _analysis_report.is_empty():
		return
	var w_phase: Dictionary = _analysis_report.get("white_phase_stats", {})
	var b_phase: Dictionary = _analysis_report.get("black_phase_stats", {})
	if w_phase.is_empty() and b_phase.is_empty():
		return

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	panel.add_theme_stylebox_override("panel", p_style)
	container.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "⏱️ Progression par Phase de Jeu (perte moy. de gain)"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title_lbl)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	var phases = [
		{"key": "opening", "label": "🏛️ Ouverture"},
		{"key": "middlegame", "label": "⚔️ Milieu de jeu"},
		{"key": "endgame", "label": "👑 Finale"}
	]

	for ph in phases:
		var wp: Dictionary = w_phase.get(ph["key"], {})
		var bp: Dictionary = b_phase.get(ph["key"], {})
		var w_loss = float(wp.get("avg_winpct_loss", 0.0))
		var b_loss = float(bp.get("avg_winpct_loss", 0.0))
		_add_stat_row(grid, "%.1f %%" % w_loss, ph["label"], "%.1f %%" % b_loss, DesignTokens.TEXT_SECONDARY)

# --- 5. TOURNANTS & MOMENTS CLÉS (Réparés & Cliquables) ---
func _build_moments_card() -> void:
	if _analysis_report.is_empty():
		return
	var swings: Array = _analysis_report.get("biggest_swings", [])
	if swings.is_empty():
		return

	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
	panel.add_theme_stylebox_override("panel", p_style)
	container.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "🔥 Tournants & Moments Clés"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
	vbox.add_child(title_lbl)

	var hint_lbl = Label.new()
	hint_lbl.text = "(Touchez un moment pour afficher la position)"
	hint_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	hint_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	vbox.add_child(hint_lbl)

	var row = HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", DesignTokens.SPACE_S)
	row.add_theme_constant_override("v_separation", DesignTokens.SPACE_XS)
	vbox.add_child(row)

	for swing in swings:
		var btn = Button.new()
		var is_w = bool(swing.get("is_white", true))
		var dots = "." if is_w else "..."
		var q_val = int(swing.get("quality", ChessMove.Quality.NONE))
		var q_sym = ChessMove.quality_to_symbol(q_val)
		var q_col = ChessMove.quality_to_color(q_val)
		var loss_pct = float(swing.get("winpct_loss", 0.0))

		btn.text = "%d%s %s  %s -%.0f%%" % [
			int(swing.get("move_number", 1)), dots, str(swing.get("san", "")),
			q_sym, loss_pct
		]
		btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		# Pas de clip_text : dans un HFlowContainer la puce garde sa largeur
		# naturelle et se replie (clip_text la réduirait à ~8 px).
		btn.clip_text = false
		btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.add_theme_color_override("font_color", q_col)

		var chip_sb = DesignTokens.flat(DesignTokens.SURFACE, DesignTokens.RADIUS_SMALL, q_col, 1, Vector2(10, 6))
		var chip_hover = chip_sb.duplicate() as StyleBoxFlat
		chip_hover.bg_color = DesignTokens.BTN_BG_HOVER
		btn.add_theme_stylebox_override("normal", chip_sb)
		btn.add_theme_stylebox_override("hover", chip_hover)
		btn.add_theme_stylebox_override("pressed", chip_hover)
		btn.add_theme_stylebox_override("focus", chip_sb)

		var ply = int(swing.get("ply", 0))
		btn.pressed.connect(func():
			moment_selected.emit(ply)
			var gc = _get_game_controller()
			if gc:
				gc.navigate_to_ply(ply)
			var main = find_parent("Main")
			if main and main.has_method("show_board_tab"):
				main.show_board_tab()
		)
		row.add_child(btn)

# --- 6. TITRE DE LA FEUILLE DES COUPS ---
func _build_moves_header() -> void:
	var lbl = Label.new()
	lbl.text = "📜 Feuille des Coups & Navigation Interactive :"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	container.add_child(lbl)

# --- ALIAS POUR COMPATIBILITÉ AVEC LES TESTS EXISTANTS ---
func _build_parallel_stats_table() -> void:
	_build_duel_scorecard()
	_build_quality_matrix()

func _build_summary_card() -> void:
	_build_hero_card()

# --- 4. LIGNE DE FILTRES ---
func _build_filter_row() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 3)
	container.add_child(row)

	for f in _FILTERS:
		var btn := Button.new()
		var mode: int = f["mode"]
		var is_active := mode == _filter
		var q_color: Color = f.get("color", DesignTokens.TEXT_PRIMARY)
		btn.text = f["label"]
		btn.tooltip_text = f.get("tip", "")
		btn.toggle_mode = true
		btn.button_pressed = is_active
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

		var sb_norm := StyleBoxFlat.new()
		sb_norm.corner_radius_top_left = DesignTokens.RADIUS_SMALL
		sb_norm.corner_radius_top_right = DesignTokens.RADIUS_SMALL
		sb_norm.corner_radius_bottom_left = DesignTokens.RADIUS_SMALL
		sb_norm.corner_radius_bottom_right = DesignTokens.RADIUS_SMALL
		sb_norm.content_margin_left = 2
		sb_norm.content_margin_right = 2
		sb_norm.content_margin_top = 4
		sb_norm.content_margin_bottom = 4

		if is_active:
			sb_norm.bg_color = Color(q_color.r, q_color.g, q_color.b, 0.28)
			sb_norm.border_color = q_color
			sb_norm.set_border_width_all(2)
		else:
			sb_norm.bg_color = DesignTokens.SURFACE_ELEVATED
			sb_norm.border_color = Color(q_color.r, q_color.g, q_color.b, 0.35)
			sb_norm.set_border_width_all(1)

		var sb_hover := sb_norm.duplicate() as StyleBoxFlat
		sb_hover.bg_color = Color(q_color.r, q_color.g, q_color.b, 0.38)

		var sb_pressed := sb_norm.duplicate() as StyleBoxFlat
		sb_pressed.bg_color = Color(q_color.r, q_color.g, q_color.b, 0.5)
		sb_pressed.border_color = q_color
		sb_pressed.set_border_width_all(2)

		var font_col := q_color if is_active else DesignTokens.TEXT_PRIMARY
		btn.add_theme_stylebox_override("normal", sb_norm)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("focus", sb_hover)
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_hover_color", q_color)
		btn.add_theme_color_override("font_pressed_color", q_color)
		btn.add_theme_color_override("font_focus_color", font_col)
		btn.pressed.connect(func():
			if _filter != mode:
				_filter = mode
				_refresh_moves()
			else:
				_filter = 0
				_refresh_moves()
		)
		row.add_child(btn)

# --- 5. LIGNES DE COUPS ---
func _build_moves() -> void:
	var gc = _get_game_controller()
	var moves = gc.game.move_history if (gc and gc.game) else []
	var cur_ply = gc.current_ply_index if gc else -1
	var filtered := _filter != 0

	_build_moves_table_header(filtered)

	if not filtered:
		_build_dense(moves, cur_ply)
	else:
		_build_filtered_single(moves, cur_ply)

func _build_moves_table_header(filtered: bool) -> void:
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)
	container.add_child(header)

	var num_header := Label.new()
	num_header.text = "#"
	num_header.custom_minimum_size = Vector2(36, 0)
	num_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_header.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	num_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	header.add_child(num_header)

	if not filtered:
		var white_header := Label.new()
		white_header.text = "⚪ Blanc"
		white_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		white_header.size_flags_stretch_ratio = 1.0
		white_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		white_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		header.add_child(white_header)

		var black_header := Label.new()
		black_header.text = "⚫ Noir"
		black_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		black_header.size_flags_stretch_ratio = 1.0
		black_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		black_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		header.add_child(black_header)
	else:
		var filtered_header := Label.new()
		filtered_header.text = "Coups correspondants au filtre actif"
		filtered_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filtered_header.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		filtered_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		header.add_child(filtered_header)

# Mode dense (2 coups par ligne) : affichage historique complet.
func _build_dense(moves: Array, cur_ply: int) -> void:
	var move_pair_count: int = (moves.size() + 1) / 2
	for pair_idx in range(move_pair_count):
		var white_ply: int = pair_idx * 2
		var black_ply: int = white_ply + 1
		var move_number: int = pair_idx + 1

		var current_panel := PanelContainer.new()
		current_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Zebra striping : fond subtil alterné
		var row_sb := StyleBoxFlat.new()
		row_sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		row_sb.content_margin_left = 4
		row_sb.content_margin_right = 4
		row_sb.content_margin_top = 2
		row_sb.content_margin_bottom = 2
		if pair_idx % 2 == 0:
			row_sb.bg_color = Color(0.12, 0.16, 0.23, 0.45)
		else:
			row_sb.bg_color = Color(0, 0, 0, 0)
		current_panel.add_theme_stylebox_override("panel", row_sb)
		container.add_child(current_panel)

		var current_row := HBoxContainer.new()
		current_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		current_row.add_theme_constant_override("separation", 6)
		current_panel.add_child(current_row)

		var num_lbl := Label.new()
		num_lbl.text = str(move_number) + "."
		num_lbl.custom_minimum_size = Vector2(36, 0)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		num_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		current_row.add_child(num_lbl)

		# Coup Blanc
		var white_move: ChessMove = moves[white_ply]
		var white_btn := _make_move_button(white_move, white_ply)
		current_row.add_child(white_btn)
		if white_ply == cur_ply:
			_highlight_active(white_btn)
			_active_btn = white_btn
		move_buttons.append(white_btn)

		# Coup Noir (si existant)
		if black_ply < moves.size():
			var black_move: ChessMove = moves[black_ply]
			var black_btn := _make_move_button(black_move, black_ply)
			current_row.add_child(black_btn)
			if black_ply == cur_ply:
				_highlight_active(black_btn)
				_active_btn = black_btn
			move_buttons.append(black_btn)
		else:
			var placeholder := Control.new()
			placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			placeholder.size_flags_stretch_ratio = 1.0
			current_row.add_child(placeholder)

# Mode filtré : une ligne par coup visible (pleine largeur).
func _build_filtered_single(moves: Array, cur_ply: int) -> void:
	var visible_count: int = 0
	for i in range(moves.size()):
		var m = moves[i]
		if not _passes_filter(m.quality):
			continue
		visible_count += 1
		var is_even := visible_count % 2 == 0

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row_sb := StyleBoxFlat.new()
		row_sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		row_sb.content_margin_left = 4
		row_sb.content_margin_right = 4
		row_sb.content_margin_top = 2
		row_sb.content_margin_bottom = 2
		row_sb.bg_color = Color(0.12, 0.16, 0.23, 0.45) if is_even else Color(0, 0, 0, 0)
		panel.add_theme_stylebox_override("panel", row_sb)
		container.add_child(panel)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)

		var num_lbl := Label.new()
		var move_num: int = (i / 2) + 1
		num_lbl.text = str(move_num) + ("..." if i % 2 == 1 else ".")
		num_lbl.custom_minimum_size = Vector2(44, 0)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		num_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		row.add_child(num_lbl)

		var btn := _make_move_button(m, i)
		row.add_child(btn)
		if i == cur_ply:
			_highlight_active(btn)
			_active_btn = btn
		move_buttons.append(btn)

	if visible_count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucun coup ne correspond au filtre sélectionné."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.custom_minimum_size = Vector2(0, 40)
		container.add_child(empty_lbl)

func _format_motifs_compact(motifs: Array) -> String:
	if motifs.is_empty():
		return ""
	var primary: String = str(motifs[0])
	match primary:
		"Pièce non protégée":
			return "⚑En prise"
		"Attaque à la découverte":
			return "⚑Découverte"
		"Fourchette royale":
			return "⚑Fourchette"
		"Mat du couloir":
			return "⚑Couloir"
		_:
			return "⚑" + primary

func _make_move_button(m: ChessMove, ply: int) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1.0
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 42)
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	btn.set_meta("ply", ply)

	# Ligne 1 : SAN + Badge qualité + perte
	var line1 := m.san
	if m.is_theory:
		line1 += " 📖"
	else:
		var badge := ChessMove.quality_to_symbol(m.quality)
		if badge != "":
			line1 += " " + badge
		line1 += _loss_suffix(m)

	# Ligne 2 : Horloge + motif tactique compact (si présents)
	var line2_parts: Array = []
	if m.clock_sec >= 0.0:
		line2_parts.append("⏱%s" % _format_clock(m.clock_sec))
	if m.motifs.size() > 0:
		var motif_str := _format_motifs_compact(m.motifs)
		if motif_str != "":
			line2_parts.append(motif_str)

	var full_text := line1
	if not line2_parts.is_empty():
		full_text += "\n" + "  ".join(line2_parts)
	btn.text = full_text
	btn.tooltip_text = _move_tooltip(m)

	# Stylebox discret avec padding intérieur confortable
	var sb_norm := StyleBoxFlat.new()
	sb_norm.bg_color = Color(0, 0, 0, 0)
	sb_norm.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
	sb_norm.content_margin_left = 6
	sb_norm.content_margin_right = 6
	sb_norm.content_margin_top = 3
	sb_norm.content_margin_bottom = 3

	var sb_hover := sb_norm.duplicate() as StyleBoxFlat
	sb_hover.bg_color = DesignTokens.BTN_BG_HOVER

	var sb_pressed := sb_norm.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = DesignTokens.BTN_BG_PRESSED

	btn.add_theme_stylebox_override("normal", sb_norm)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("focus", sb_hover)

	if m.is_theory:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	elif m.quality != ChessMove.Quality.NONE:
		btn.add_theme_color_override("font_color", ChessMove.quality_to_color(m.quality))
	else:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

	btn.pressed.connect(func():
		var gc = _get_game_controller()
		if gc:
			gc.navigate_to_ply(ply)
		var main := find_parent("Main")
		if main and main.has_method("show_board_tab"):
			main.show_board_tab()
	)
	return btn

func _get_active_stylebox() -> StyleBoxFlat:
	if _active_stylebox == null:
		_active_stylebox = StyleBoxFlat.new()
		_active_stylebox.bg_color = DesignTokens.SURFACE_ELEVATED
		_active_stylebox.border_color = DesignTokens.ACCENT
		_active_stylebox.set_border_width_all(1)
		_active_stylebox.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		_active_stylebox.content_margin_left = 6
		_active_stylebox.content_margin_right = 6
		_active_stylebox.content_margin_top = 3
		_active_stylebox.content_margin_bottom = 3
	return _active_stylebox

func _highlight_active(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn.add_theme_stylebox_override("normal", _get_active_stylebox())

func _reset_button_style(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var sb_norm := StyleBoxFlat.new()
	sb_norm.bg_color = Color(0, 0, 0, 0)
	sb_norm.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
	sb_norm.content_margin_left = 6
	sb_norm.content_margin_right = 6
	sb_norm.content_margin_top = 3
	sb_norm.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", sb_norm)

	var ply = btn.get_meta("ply", -1)
	var gc = _get_game_controller()
	var moves = gc.game.move_history if (gc and gc.game) else []
	if ply >= 0 and ply < moves.size():
		var m = moves[ply]
		if m.is_theory:
			btn.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		elif m.quality != ChessMove.Quality.NONE:
			btn.add_theme_color_override("font_color", ChessMove.quality_to_color(m.quality))
		else:
			btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	else:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

func _update_active_button(ply_idx: int) -> void:
	if _active_btn and is_instance_valid(_active_btn):
		if _active_btn.get_meta("ply", -1) == ply_idx:
			return
		_reset_button_style(_active_btn)
		_active_btn = null

	for btn in move_buttons:
		if is_instance_valid(btn) and btn.get_meta("ply", -1) == ply_idx:
			_highlight_active(btn)
			_active_btn = btn
			break
	call_deferred("_scroll_to_active")

func _loss_suffix(m: ChessMove) -> String:
	if m.quality == ChessMove.Quality.NONE or MoveQualityService.group(m.quality) == 0:
		return ""
	if m.centipawn_loss >= 3000:
		return " (-Mat)"
	elif m.centipawn_loss >= 1000:
		return " (-%.1f)" % (float(m.centipawn_loss) / 100.0)
	elif m.centipawn_loss > 0:
		return " (-%d)" % int(m.centipawn_loss)
	return ""

func _format_clock(total_sec: float) -> String:
	var s := int(maxf(0.0, total_sec))
	var h := s / 3600
	var mn := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, mn, sec]
	return "%d:%02d" % [mn, sec]

func _move_tooltip(m: ChessMove) -> String:
	var parts: Array = []
	if m.is_theory:
		parts.append("Théorie d'ouverture")
	else:
		if m.quality != ChessMove.Quality.NONE:
			parts.append("Qualité : %s" % ChessMove.quality_to_symbol(m.quality))
		if m.centipawn_loss > 0:
			parts.append("Perte : %d cp" % int(m.centipawn_loss))
	if m.motifs.size() > 0:
		var motif_strings: Array = []
		for motif in m.motifs:
			motif_strings.append(str(motif))
		parts.append("Motifs : " + ", ".join(motif_strings))
	return "\n".join(parts)

func _passes_filter(q: int) -> bool:
	match _filter:
		0:
			return true
		1:
			return q == ChessMove.Quality.BLUNDER or q == ChessMove.Quality.MISS
		2:
			return q == ChessMove.Quality.MISTAKE
		3:
			return q == ChessMove.Quality.INACCURACY
		4:
			return q == ChessMove.Quality.GOOD
		5:
			return q == ChessMove.Quality.EXCELLENT
		6:
			return q == ChessMove.Quality.BEST
		7:
			return q == ChessMove.Quality.GREAT
		8:
			return q == ChessMove.Quality.BRILLIANT
		_:
			return true

func _on_move_navigated(ply_idx: int) -> void:
	var gc = _get_game_controller()
	var cur_count = gc.game.move_history.size() if (gc and gc.game) else 0
	if cur_count != _last_moves_count or move_buttons.is_empty():
		_refresh_moves()
	else:
		_update_active_button(ply_idx)

func _scroll_to_active() -> void:
	var gc = _get_game_controller()
	var cur_ply = gc.current_ply_index if gc else -1
	for btn in move_buttons:
		if is_instance_valid(btn) and btn.get_meta("ply", -1) == cur_ply:
			ensure_control_visible(btn)
			return
