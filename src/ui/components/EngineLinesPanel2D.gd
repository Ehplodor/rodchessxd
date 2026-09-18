class_name EngineLinesPanel2D
extends VBoxContainer
## EngineLinesPanel2D.gd - Panneau repliable des N meilleures lignes moteur (MultiPV, T1.1).
## Cliquer une ligne émet `line_selected` pour prévisualiser le coup sur l'échiquier.

signal line_selected(rank: int, pv: Array, best_move: String)
signal cliff_study_requested(rank: int, pv: Array, meta: Dictionary)
signal compare_all_lines_requested(lines: Array, meta: Dictionary)
signal cliff_step_preview_requested(fen: String, uci: String)

const CliffPisteBadge = preload("res://src/ui/components/CliffPisteBadge.gd")

var _header_btn: Button
var _header_row: HBoxContainer
var _btn_cliff_header: Button
var _rows_box: VBoxContainer
var _progress_bar: ProgressBar
var _collapsed := false
var _lines: Array = []
var _engine_name := "Moteur"
var _depth := 0
var _context_fen := ""
var _row_buttons: Array[Button] = []
var _row_boxes: Array[HBoxContainer] = []
var _row_badges: Array[CliffPisteBadge] = []
var _row_cliff_btns: Array[Button] = []
var _row_data: Array[Dictionary] = []
var _line_pistes: Dictionary = {}   # rank -> CliffTypes.Piste
var _active_rank: int = 0
var _loading: bool = false
var _frozen: bool = false
var _cliff_active: bool = false
var _san_cache: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation", 2)
	# En-tête : titre extensible (repliable) + emplacement pour le HUD moteur
	# (chip de profondeur + bascule d'analyses), placés ici par Main — c'est
	# l'emplacement naturel de ces informations, sans coût vertical ni débordement.
	_header_row = HBoxContainer.new()
	_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_row.add_theme_constant_override("separation", 6)
	add_child(_header_row)

	_header_btn = Button.new()
	_header_btn.flat = true
	_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header_btn.clip_text = true
	_header_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
	_header_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_header_btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	_header_btn.pressed.connect(_toggle)
	_header_row.add_child(_header_btn)

	# Bouton d'action directe Cliff dans l'en-tête de la ligne moteur
	_btn_cliff_header = Button.new()
	_btn_cliff_header.text = "🏔️ Cliff"
	_btn_cliff_header.tooltip_text = "Étudier la difficulté cognitive de la ligne (CHESS-CLIFF)"
	_btn_cliff_header.custom_minimum_size = Vector2(58, DesignTokens.TOUCH_DENSE)
	_btn_cliff_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb_cliff_norm = DesignTokens.flat(Color(0.20, 0.15, 0.35, 0.45), DesignTokens.RADIUS_SMALL,
			Color(0.55, 0.40, 0.90, 0.6), 1, Vector2(6, 2))
	var sb_cliff_hover = sb_cliff_norm.duplicate() as StyleBoxFlat
	sb_cliff_hover.bg_color = Color(0.30, 0.22, 0.50, 0.7)
	sb_cliff_hover.border_color = Color(0.70, 0.55, 1.0, 0.9)
	_btn_cliff_header.add_theme_stylebox_override("normal", sb_cliff_norm)
	_btn_cliff_header.add_theme_stylebox_override("hover", sb_cliff_hover)
	_btn_cliff_header.add_theme_stylebox_override("pressed", sb_cliff_hover)
	_btn_cliff_header.add_theme_color_override("font_color", Color("#c084fc"))
	_btn_cliff_header.add_theme_color_override("font_hover_color", Color.WHITE)
	_btn_cliff_header.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_btn_cliff_header.pressed.connect(_on_cliff_header_pressed)
	_header_row.add_child(_btn_cliff_header)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	add_child(_rows_box)

	# Pré-création d'un pool fixe de 5 rangées réutilisables (zéro queue_free à l'évaluation)
	for idx in range(5):
		var row_box := HBoxContainer.new()
		row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_theme_constant_override("separation", 4)

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Affordance tactile : style de carte interactif (pill/chip) avec bordure douce
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = Color(0.12, 0.17, 0.26, 0.55)
		sb_normal.border_color = Color(0.22, 0.33, 0.48, 0.6)
		sb_normal.set_border_width_all(1)
		sb_normal.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
		sb_normal.content_margin_left = 10
		sb_normal.content_margin_right = 10
		sb_normal.content_margin_top = 4
		sb_normal.content_margin_bottom = 4

		var sb_hover := sb_normal.duplicate() as StyleBoxFlat
		sb_hover.bg_color = Color(0.18, 0.25, 0.38, 0.8)
		sb_hover.border_color = DesignTokens.ACCENT

		var sb_pressed := sb_normal.duplicate() as StyleBoxFlat
		sb_pressed.bg_color = Color(0.08, 0.12, 0.20, 0.9)
		sb_pressed.border_color = DesignTokens.PRIMARY_BORDER

		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_pressed)
		btn.add_theme_stylebox_override("focus", sb_hover)
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
		btn.add_theme_color_override("font_hover_color", DesignTokens.ACCENT)

		btn.visible = false
		var btn_idx = idx
		btn.pressed.connect(func():
			_on_row_pressed(btn_idx)
		)
		row_box.add_child(btn)

		# Badge de piste cognitive (masqué tant que non calculé)
		var badge := CliffPisteBadge.new()
		badge.set_piste(-1)
		row_box.add_child(badge)

		# Bouton d'étude Cliff dédié à cette ligne
		var cliff_btn := Button.new()
		cliff_btn.text = "🏔️"
		cliff_btn.tooltip_text = "Étudier la difficulté cognitive de cette ligne (CHESS-CLIFF)"
		cliff_btn.custom_minimum_size = Vector2(44, DesignTokens.TOUCH_DENSE)
		cliff_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cliff_btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		cliff_btn.add_theme_color_override("font_color", Color("#c084fc"))
		cliff_btn.visible = false
		var cliff_idx = idx
		cliff_btn.pressed.connect(func():
			_on_row_cliff_pressed(cliff_idx)
		)
		row_box.add_child(cliff_btn)

		row_box.visible = false
		_rows_box.add_child(row_box)
		_row_boxes.append(row_box)
		_row_buttons.append(btn)
		_row_badges.append(badge)
		_row_cliff_btns.append(cliff_btn)
		_row_data.append({})

	# Fine barre de progression pour l'analyse Super Live (Cliff)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 4)
	_progress_bar.show_percentage = false
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_prog_bg = StyleBoxFlat.new()
	sb_prog_bg.bg_color = Color(0.1, 0.14, 0.22, 0.6)
	sb_prog_bg.set_corner_radius_all(2)
	var sb_prog_fill = StyleBoxFlat.new()
	sb_prog_fill.bg_color = Color("#c084fc") # Améthyste Cliff
	sb_prog_fill.set_corner_radius_all(2)
	_progress_bar.add_theme_stylebox_override("background", sb_prog_bg)
	_progress_bar.add_theme_stylebox_override("fill", sb_prog_fill)
	_progress_bar.visible = false
	_rows_box.add_child(_progress_bar)

	_update_header()

## Rangée d'en-tête où Main vient accrocher le HUD moteur (chip + bascule).
func header_row() -> HBoxContainer:
	return _header_row

func _on_cliff_header_pressed() -> void:
	if _lines.size() > 1:
		compare_all_lines_requested.emit(_lines, get_context_meta(1))
	else:
		var first_pv: Array = []
		if not _lines.is_empty():
			first_pv = _lines[0].get("pv", [])
		cliff_study_requested.emit(1, first_pv, get_context_meta(1))

func _on_row_cliff_pressed(idx: int) -> void:
	if _frozen or idx < 0 or idx >= _row_data.size():
		return
	var data: Dictionary = _row_data[idx]
	if data.is_empty():
		return
	var rank: int = int(data.get("rank", idx + 1))
	cliff_study_requested.emit(rank, data.get("pv", []), get_context_meta(rank))

func set_cliff_active(active: bool) -> void:
	_cliff_active = active
	if _btn_cliff_header:
		if active:
			_btn_cliff_header.text = "⏹ Stop"
			_btn_cliff_header.disabled = _loading
		else:
			_btn_cliff_header.text = ("🏔️ Comparer (%d)" % _lines.size()) if _lines.size() > 1 else "🏔️ Cliff"
	if not active:
		_progress_bar.visible = false

func set_cliff_progress(cur: int, total: int) -> void:
	_progress_bar.visible = true
	_progress_bar.max_value = float(total)
	_progress_bar.value = float(cur)

func _on_row_pressed(idx: int) -> void:
	if idx < 0 or idx >= _row_data.size():
		return
	var data: Dictionary = _row_data[idx]
	if data.is_empty():
		return
	line_selected.emit(int(data.get("rank", idx + 1)), data.get("pv", []), str(data.get("best_move", "")))

## Vrai si le panneau est replié (permet à l'appelant d'éviter tout travail inutile).
func is_collapsed() -> bool:
	return _collapsed

func set_lines(lines: Array, engine_name: String = "", depth: int = 0) -> void:
	_lines = lines
	if engine_name != "":
		_engine_name = engine_name
	_depth = depth
	var first_fen := ""
	if not lines.is_empty():
		first_fen = str((lines[0] as Dictionary).get("fen", ""))
	if first_fen != _context_fen:
		_context_fen = first_fen
		_line_pistes.clear()  # les pistes d'une position précédente ne valent plus
	# Ne rien reconstruire tant que le panneau est replié (perf : appelé à chaque info moteur).
	if not _collapsed:
		_rebuild()
	_update_header()

## Renseigne les pistes cognitives par rang (rank -> CliffTypes.Piste).
func set_line_pistes(pistes: Dictionary) -> void:
	_line_pistes = pistes
	if not _collapsed:
		_rebuild()

## Met à jour immédiatement le badge d'une ligne spécifique (hydratation progressive).
func set_line_piste(rank: int, summary: Dictionary) -> void:
	_line_pistes[rank] = summary
	if not _collapsed:
		_rebuild()

## Met en évidence la ligne en cours d'étude Cliff (0 = aucune).
func set_active_line(rank: int) -> void:
	_active_rank = rank
	if not _collapsed:
		_rebuild()

## État de chargement (aucune ligne disponible, calcul en cours).
func set_loading_state(is_loading: bool) -> void:
	_loading = is_loading
	if _loading:
		_header_btn.text = "⏳ Chargement des lignes moteur…"
	elif is_instance_valid(_header_btn):
		_update_header()
	if is_instance_valid(_btn_cliff_header):
		_btn_cliff_header.disabled = _loading

## Gèle les interactions du panneau pendant une étude Cliff.
func set_frozen(frozen: bool) -> void:
	_frozen = frozen
	for i in range(_row_buttons.size()):
		_row_buttons[i].disabled = frozen
		_row_cliff_btns[i].disabled = frozen
	if is_instance_valid(_header_btn):
		_header_btn.disabled = frozen
	if is_instance_valid(_btn_cliff_header):
		_btn_cliff_header.disabled = _loading if _cliff_active else (frozen or _loading)

func get_context_meta(rank: int) -> Dictionary:
	return {
		"fen": _context_fen,
		"depth": _depth,
		"rank": rank,
		"engine": _engine_name
	}

func _toggle() -> void:
	_collapsed = not _collapsed
	_rows_box.visible = not _collapsed
	if not _collapsed:
		_rebuild()
	_update_header()

func _update_header() -> void:
	if _header_btn == null:
		return
	var arrow := "▸" if _collapsed else "▾"
	var title_lines := "Ligne moteur" if _lines.size() <= 1 else ("Lignes moteur (%d)" % _lines.size())
	# Le moteur et la profondeur sont affichés par le HUD (chip) à droite :
	# on évite la redondance et la troncature du titre sur écran étroit.
	_header_btn.text = "%s %s" % [arrow, title_lines]
	if is_instance_valid(_btn_cliff_header) and not _cliff_active:
		_btn_cliff_header.text = ("🏔️ Comparer (%d)" % _lines.size()) if _lines.size() > 1 else "🏔️ Cliff"

func _rebuild() -> void:
	if _rows_box == null:
		return
	var count = mini(_lines.size(), _row_buttons.size())
	for i in range(count):
		var line: Dictionary = _lines[i]
		var pv: Array = line.get("pv", [])
		var row_box = _row_boxes[i]
		var btn = _row_buttons[i]
		if pv.is_empty():
			row_box.visible = false
			btn.visible = false
			_row_badges[i].visible = false
			_row_cliff_btns[i].visible = false
			_row_data[i] = {}
			continue
		var eval_str := EvalFormatter.format_cp_mate(int(line.get("score_cp", 0)), int(line.get("mate_in", 0)))
		var san_line := _pv_to_san(str(line.get("fen", "")), pv)
		# Affordance claire : symbole ▶ pour indiquer que la ligne est immédiatement jouable sur l'échiquier
		if _lines.size() > 1:
			btn.text = "#%d  %s   ▶ %s" % [i + 1, eval_str, san_line]
		else:
			btn.text = "%s   ▶ %s" % [eval_str, san_line]
		btn.tooltip_text = "%s\n%s\n▶ Cliquer pour jouer ce coup sur l'échiquier (mode Test)" % [eval_str, san_line]
		btn.visible = true
		row_box.visible = true
		_apply_row_style(i, btn)
		# Badge de piste cognitive (si connue pour ce rang)
		var raw = _line_pistes.get(i + 1, null)
		var piste := -1
		var summary: Dictionary = {}
		if raw is Dictionary:
			piste = int((raw as Dictionary).get("piste", -1))
			summary = raw
		elif raw != null:
			piste = int(raw)
		if piste >= 0:
			_row_badges[i].set_piste(piste, int(summary.get("indice_d", -1)),
					float(summary.get("delta", 0.0)), float(summary.get("bait", 0.0)),
					float(summary.get("p_survie", 1.0)))
		else:
			_row_badges[i].set_piste(-1)
		_row_cliff_btns[i].visible = true
		_row_cliff_btns[i].disabled = _frozen
		_row_data[i] = {
			"rank": i + 1,
			"pv": pv,
			"best_move": str(line.get("best_move", ""))
		}

	# Masquer les rangées du pool non utilisées
	for i in range(count, _row_buttons.size()):
		_row_boxes[i].visible = false
		_row_buttons[i].visible = false
		_row_badges[i].visible = false
		_row_cliff_btns[i].visible = false
		_row_data[i] = {}

## Met en évidence la ligne active (étudiée par Cliff) via la couleur du libellé.
func _apply_row_style(idx: int, btn: Button) -> void:
	if _active_rank == idx + 1:
		btn.add_theme_color_override("font_color", Color("#c084fc"))
	else:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

func _pv_to_san(fen: String, pv: Array) -> String:
	if fen == "":
		var tree = Engine.get_main_loop() as SceneTree
		if tree and tree.root and tree.root.has_node("GameController"):
			var gc = tree.root.get_node("GameController")
			if gc and gc.game:
				fen = gc.game.get_fen()
	if fen == "" or pv.is_empty():
		return " ".join(pv)
	var cache_key = fen + "|" + " ".join(pv.slice(0, 8))
	if _san_cache.has(cache_key):
		return _san_cache[cache_key]
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return " ".join(pv)
	var sans: Array = []
	var limit := mini(pv.size(), 8)
	var is_black_first = (game.active_color == ChessPiece.PieceColor.BLACK)
	var first_move_num = game.fullmove_number
	for k in range(limit):
		var mv := game.find_move(str(pv[k]))
		if mv == null:
			break
		var move_prefix := ""
		if k == 0:
			if is_black_first:
				move_prefix = "%d... " % first_move_num
			else:
				move_prefix = "%d. " % first_move_num
		elif game.active_color == ChessPiece.PieceColor.WHITE:
			move_prefix = "%d. " % game.fullmove_number
		sans.append(move_prefix + mv.san)
		game.make_move(mv)
	var res = " ".join(sans)
	if _san_cache.size() > 200:
		_san_cache.clear()
	_san_cache[cache_key] = res
	return res
