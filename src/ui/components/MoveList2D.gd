class_name MoveList2D
extends ScrollContainer
## MoveList2D.gd - Écran d'analyse et feuille de coups.
## Affiche en haut les statistiques parallèles des deux joueurs (3 colonnes),
## le résumé synthétique en un coup d'œil (vainqueur, ELO, qualité, répartition des coups),
## puis en dessous la feuille de notation interactive avec filtres de qualité.

const MoveQualityService = preload("res://src/ui/components/MoveQualityService.gd")

var container: VBoxContainer
var move_buttons: Array[Button] = []
var _active_btn: Button = null
var _last_moves_count: int = -1
var _analysis_report: Dictionary = {}
var _active_stylebox: StyleBoxFlat = null

# Filtre actif : 0 = TOUS, sinon un filtre par qualité (?? ? ?! ✓ ✓+ ★ ! !!)
var _filter := 0

const _FILTERS := [
	{"label": "∅", "mode": 0, "tip": "Aucun filtre (tous les coups)"},  # TOUS
	{"label": "??", "mode": 1, "tip": "Gaffes"},   # BLUNDER / MISS
	{"label": "?", "mode": 2, "tip": "Erreurs"},   # MISTAKE
	{"label": "?!", "mode": 3, "tip": "Imprécisions"},  # INACCURACY
	{"label": "✓", "mode": 4, "tip": "Bons coups"},  # GOOD
	{"label": "✓+", "mode": 5, "tip": "Excellents coups"},  # EXCELLENT
	{"label": "★", "mode": 6, "tip": "Meilleurs coups"},  # BEST
	{"label": "!", "mode": 7, "tip": "Très bons coups"},  # GREAT
	{"label": "!!", "mode": 8, "tip": "Coups brillants"},  # BRILLIANT
]

func _ready() -> void:
	custom_minimum_size = Vector2(200, 120)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(self)

	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 8)
	add_child(container)

	var gc = _get_game_controller()
	if gc:
		gc.position_changed.connect(_on_position_changed)
		gc.move_navigated.connect(_on_move_navigated)

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

	# 1. Tableau comparatif parallèle 3 colonnes (Blancs, Libellé de Stat, Noirs)
	_build_parallel_stats_table()

	# 2. Carte Résumé synthétique en un coup d'œil (Vainqueur, ELO, Qualité, Types de coups)
	_build_summary_card()

	# 3. Séparateur et en-tête des coups
	_build_moves_header()

	# 4. Ligne de filtres
	_build_filter_row()

	# 5. Liste des coups détaillée
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

# --- 1. TABLEAU COMPARATIF 3 COLONNES ---
func _build_parallel_stats_table() -> void:
	var names = _get_player_names()
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
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title_lbl = Label.new()
	title_lbl.text = "⚔️ Statistiques des Joueurs en Parallèle"
	title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	title_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(title_lbl)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	# Ligne d'en-tête (Blancs, Libellé, Noirs)
	var head_w = Label.new()
	head_w.text = "⚪ " + names["white"]
	head_w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head_w.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	head_w.add_theme_color_override("font_color", Color("#f8fafc"))
	grid.add_child(head_w)

	var head_m = Label.new()
	head_m.text = "📊 Indicateur"
	head_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head_m.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	head_m.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	grid.add_child(head_m)

	var head_b = Label.new()
	head_b.text = "⚫ " + names["black"]
	head_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head_b.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	head_b.add_theme_color_override("font_color", Color("#cbd5e1"))
	grid.add_child(head_b)

	# Métriques principales
	var has_report = not _analysis_report.is_empty()
	var w_acc = _analysis_report.get("white_accuracy", 0.0)
	var b_acc = _analysis_report.get("black_accuracy", 0.0)
	var w_elo = _analysis_report.get("white_estimated_elo", 1500)
	var b_elo = _analysis_report.get("black_estimated_elo", 1500)
	var w_ci = _analysis_report.get("white_elo_ci", 0)
	var b_ci = _analysis_report.get("black_elo_ci", 0)
	var w_acpl = _analysis_report.get("white_acpl", 0.0)
	var b_acpl = _analysis_report.get("black_acpl", 0.0)

	var w_acc_str = ("%.1f %%" % w_acc) if has_report else "—"
	var b_acc_str = ("%.1f %%" % b_acc) if has_report else "—"
	var w_elo_str = ("%d" % w_elo + (" ±%d" % w_ci if w_ci > 0 else "")) if has_report else "—"
	var b_elo_str = ("%d" % b_elo + (" ±%d" % b_ci if b_ci > 0 else "")) if has_report else "—"
	var w_acpl_str = ("%.1f cp" % w_acpl) if has_report else "—"
	var b_acpl_str = ("%.1f cp" % b_acpl) if has_report else "—"

	_add_stat_row(grid, w_acc_str, "🎯 Précision CAPS2", b_acc_str, Color("#34d399"))
	_add_stat_row(grid, w_elo_str, "📈 ELO estimé", b_elo_str, Color("#38bdf8"))
	_add_stat_row(grid, w_acpl_str, "📉 Perte moy. (ACPL)", b_acpl_str, Color("#fde047"))

	# Catégories de coups
	_add_stat_row(grid, str(w_s.get("brilliant", 0)), "‼ Coups brillants", str(b_s.get("brilliant", 0)), Color("#38bdf8"))
	_add_stat_row(grid, str(w_s.get("best", 0)), "★ Meilleurs coups", str(b_s.get("best", 0)), Color("#10b981"))
	_add_stat_row(grid, str(w_s.get("great", 0) + w_s.get("excellent", 0)), "✓+ Excellents coups", str(b_s.get("great", 0) + b_s.get("excellent", 0)), Color("#14b8a6"))
	_add_stat_row(grid, str(w_s.get("good", 0)), "✓ Bons coups", str(b_s.get("good", 0)), Color("#94a3b8"))
	_add_stat_row(grid, str(w_s.get("inaccuracy", 0)), "?! Imprécisions", str(b_s.get("inaccuracy", 0)), Color("#eab308"))
	_add_stat_row(grid, str(w_s.get("mistake", 0)), "? Erreurs", str(b_s.get("mistake", 0)), Color("#f97316"))
	_add_stat_row(grid, str(w_s.get("blunder", 0) + w_s.get("miss", 0)), "?? Gaffes", str(b_s.get("blunder", 0) + b_s.get("miss", 0)), Color("#ef4444"))

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

# --- 2. CARTE RÉSUMÉ SYNTHÉTIQUE ---
func _build_summary_card() -> void:
	var names = _get_player_names()
	var q_stats = _get_player_quality_stats()
	var w_s = q_stats["white"]
	var b_s = q_stats["black"]

	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c_style = DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_MEDIUM,
			DesignTokens.BORDER, 1, Vector2(10, 8))
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

	var outcome_lbl = Label.new()
	outcome_lbl.text = outcome_text
	outcome_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	outcome_lbl.add_theme_color_override("font_color", outcome_color)
	vbox.add_child(outcome_lbl)

	# Qualité globale de la partie
	if not _analysis_report.is_empty():
		var w_acc = _analysis_report.get("white_accuracy", 0.0)
		var b_acc = _analysis_report.get("black_accuracy", 0.0)
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
		elo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elo_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elo_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		elo_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		vbox.add_child(elo_lbl)

	# Résumé synthétique des types de coups (de brillants aux grosses gaffes)
	var breakdown_lbl = Label.new()
	breakdown_lbl.text = "Répartition : ⚪ [★ %d • ✓ %d • ?! %d • ?? %d]   VS   ⚫ [★ %d • ✓ %d • ?! %d • ?? %d]" % [
		w_s.get("best", 0) + w_s.get("brilliant", 0),
		w_s.get("good", 0) + w_s.get("great", 0) + w_s.get("excellent", 0),
		w_s.get("inaccuracy", 0),
		w_s.get("blunder", 0) + w_s.get("mistake", 0),
		b_s.get("best", 0) + b_s.get("brilliant", 0),
		b_s.get("good", 0) + b_s.get("great", 0) + b_s.get("excellent", 0),
		b_s.get("inaccuracy", 0),
		b_s.get("blunder", 0) + b_s.get("mistake", 0)
	]
	breakdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	breakdown_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	breakdown_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	breakdown_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	vbox.add_child(breakdown_lbl)

# --- 3. TITRE DE LA SECTION COUPS ---
func _build_moves_header() -> void:
	# T1.2 — En-tête d'ouverture (ECO + nom) issue du rapport d'analyse.
	var opening: Dictionary = _analysis_report.get("opening", {})
	var opening_name := str(opening.get("name", ""))
	if opening_name != "":
		var eco := str(opening.get("eco", ""))
		var open_lbl := Label.new()
		open_lbl.text = "📖 %s%s" % [("%s — " % eco) if eco != "" else "", opening_name]
		open_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		open_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		open_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		container.add_child(open_lbl)

	var lbl = Label.new()
	lbl.text = "📜 Feuille des Coups & Navigation Interactive :"
	lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	container.add_child(lbl)

# --- 4. LIGNE DE FILTRES ---
func _build_filter_row() -> void:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", DesignTokens.SPACE_XS)
	row.add_theme_constant_override("v_separation", DesignTokens.SPACE_XS)
	container.add_child(row)

	for f in _FILTERS:
		var btn := Button.new()
		var mode: int = f["mode"]
		var is_active := mode == _filter
		btn.text = f["label"]
		btn.tooltip_text = f.get("tip", "")
		btn.toggle_mode = true
		btn.button_pressed = is_active
		btn.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_DENSE)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

		var sb_norm := DesignTokens.flat(DesignTokens.SURFACE_ELEVATED, DesignTokens.RADIUS_SMALL,
				DesignTokens.BORDER, 1, Vector2(8, 3))
		var sb_hover := sb_norm.duplicate() as StyleBoxFlat
		sb_hover.bg_color = DesignTokens.BTN_BG_HOVER
		var sb_pressed := DesignTokens.flat(DesignTokens.BTN_BG_PRESSED, DesignTokens.RADIUS_SMALL,
				DesignTokens.BORDER, 1, Vector2(8, 3))
		if is_active:
			sb_norm.bg_color = DesignTokens.BTN_BG_PRESSED
			sb_pressed.bg_color = DesignTokens.BTN_BG
			sb_pressed.border_color = DesignTokens.BTN_BORDER_ACTIVE
			sb_pressed.set_border_width_all(2)

		var font_col := DesignTokens.ACCENT if is_active else DesignTokens.TEXT_PRIMARY
		btn.add_theme_stylebox_override("normal", sb_norm)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("focus", sb_hover)
		btn.add_theme_color_override("font_color", font_col)
		btn.add_theme_color_override("font_hover_color", font_col)
		btn.add_theme_color_override("font_pressed_color", font_col)
		btn.add_theme_color_override("font_focus_color", font_col)
		btn.pressed.connect(func():
			if _filter != mode:
				_filter = mode
				_refresh_moves()
		)
		row.add_child(btn)

# --- 5. LIGNES DE COUPS ---
func _build_moves() -> void:
	var gc = _get_game_controller()
	var moves = gc.game.move_history if (gc and gc.game) else []
	var cur_ply = gc.current_ply_index if gc else -1
	var filtered := _filter != 0

	if not filtered:
		_build_dense(moves, cur_ply)
	else:
		_build_filtered_single(moves, cur_ply)

# Mode dense (2 coups par ligne) : affichage historique complet.
func _build_dense(moves: Array, cur_ply: int) -> void:
	var current_row: HBoxContainer = null
	for i in range(moves.size()):
		var m = moves[i]
		if i % 2 == 0:
			current_row = HBoxContainer.new()
			current_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			container.add_child(current_row)

			var num_lbl := Label.new()
			num_lbl.text = str((i / 2) + 1) + "."
			num_lbl.custom_minimum_size = Vector2(34, 0)
			num_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
			num_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
			current_row.add_child(num_lbl)

		var btn := _make_move_button(m, i)
		current_row.add_child(btn)
		if i == cur_ply:
			_highlight_active(btn)
			_active_btn = btn
		move_buttons.append(btn)

# Mode filtré : une ligne par coup visible (pleine largeur).
func _build_filtered_single(moves: Array, cur_ply: int) -> void:
	for i in range(moves.size()):
		var m = moves[i]
		if not _passes_filter(m.quality):
			continue
		var btn := _make_move_button(m, i)
		btn.text = str((i / 2) + 1) + ("..." if i % 2 == 1 else ". ") + btn.text
		container.add_child(btn)
		if i == cur_ply:
			_highlight_active(btn)
			_active_btn = btn
		move_buttons.append(btn)

func _make_move_button(m: ChessMove, ply: int) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	btn.set_meta("ply", ply)

	var text := m.san
	if m.is_theory:
		text += "  (théorie)"
	else:
		var badge := ChessMove.quality_to_symbol(m.quality)
		if badge != "":
			text += " " + badge
		text += _loss_suffix(m)
	# T2.4 — Horloge restante si les annotations PGN la fournissent.
	if m.clock_sec >= 0.0:
		text += "  ⏱%s" % _format_clock(m.clock_sec)
	# T1.4 — Motifs tactiques vérifiés (max 2, compacts).
	if m.motifs.size() > 0:
		var shown: Array = []
		for k in range(mini(2, m.motifs.size())):
			shown.append(str(m.motifs[k]))
		text += "  ⚑" + ", ".join(shown)
	btn.text = text
	btn.tooltip_text = _move_tooltip(m)

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
		_active_stylebox.set_corner_radius_all(4)
	return _active_stylebox

func _highlight_active(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	btn.add_theme_stylebox_override("normal", _get_active_stylebox())

func _reset_button_style(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	btn.remove_theme_stylebox_override("normal")
	var ply = btn.get_meta("ply", -1)
	var gc = _get_game_controller()
	var moves = gc.game.move_history if (gc and gc.game) else []
	if ply >= 0 and ply < moves.size():
		var m = moves[ply]
		if m.quality != ChessMove.Quality.NONE:
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
	if m.centipawn_loss > 0:
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
