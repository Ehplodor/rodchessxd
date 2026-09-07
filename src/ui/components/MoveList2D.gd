class_name MoveList2D
extends ScrollContainer
## MoveList2D.gd - Feuille de notation des coups avec pastilles d'analyse,
## perte en cp et filtres par qualité (jalon M3), navigation interactive.
## La qualité/loss des coups est posée par GameAnalyzer sur move_history
## (move.quality, move.centipawn_loss) ; refresh() est appelé en fin d'analyse.

const MoveQualityService = preload("res://src/ui/components/MoveQualityService.gd")

var container: VBoxContainer
var move_buttons: Array[Button] = []

# Filtre actif : 0 = tout, 1 = ?! , 2 = ? , 3 = ?? , 4 = positifs (✓ ! ★ !!)
var _filter := 0

const _FILTERS := [
	{"label": "Tout", "mode": 0},
	{"label": "??", "mode": 3},
	{"label": "?", "mode": 2},
	{"label": "?!", "mode": 1},
	{"label": "✓+", "mode": 4},
]

func _ready() -> void:
	custom_minimum_size = Vector2(200, 90)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	DesignTokens.touch_scroll(self)

	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 2)
	add_child(container)

	GameController.position_changed.connect(_refresh_moves)
	GameController.move_navigated.connect(_on_move_navigated)

## Rafraîchissement public (appelé aussi à la fin de l'analyse, cf. Main).
func refresh() -> void:
	_refresh_moves()

func _refresh_moves() -> void:
	for child in container.get_children():
		child.queue_free()
	move_buttons.clear()
	scroll_vertical = 0  # revenir en haut : le récap reste visible

	_build_recap()
	_build_filter_row()
	_build_moves()
	call_deferred("_scroll_to_active")

# --- RÉCAP PAR QUALITÉ ---

func _quality_counts() -> Dictionary:
	var c := {"gaffes": 0, "erreurs": 0, "imprecisions": 0, "brillants": 0}
	for m in GameController.game.move_history:
		var q: int = m.quality
		match q:
			ChessMove.Quality.BLUNDER, ChessMove.Quality.MISS:
				c["gaffes"] += 1
			ChessMove.Quality.MISTAKE:
				c["erreurs"] += 1
			ChessMove.Quality.INACCURACY:
				c["imprecisions"] += 1
			ChessMove.Quality.BRILLIANT, ChessMove.Quality.BEST, ChessMove.Quality.GREAT:
				c["brillants"] += 1
	return c

func _build_recap() -> void:
	var c := _quality_counts()
	var parts: Array[String] = []
	if c["gaffes"] > 0:
		parts.append("🤯 Gaffes %d" % c["gaffes"])
	if c["erreurs"] > 0:
		parts.append("😬 Erreurs %d" % c["erreurs"])
	if c["imprecisions"] > 0:
		parts.append("🤔 Imprécisions %d" % c["imprecisions"])
	if c["brillants"] > 0:
		parts.append("👏 Brillants %d" % c["brillants"])

	var recap := Label.new()
	recap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recap.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	recap.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	if parts.is_empty():
		recap.text = "Récap qualité : analyse la partie pour détailler les coups."
	else:
		recap.text = "Récap : " + " · ".join(parts)
	container.add_child(recap)

# --- LIGNE DE FILTRES ---

func _build_filter_row() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	container.add_child(row)

	for f in _FILTERS:
		var btn := Button.new()
		var mode: int = f["mode"]
		btn.text = f["label"]
		btn.toggle_mode = true
		btn.button_pressed = (mode == _filter)
		btn.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_DENSE)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		if mode == _filter:
			btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
		btn.pressed.connect(func():
			if _filter != mode:
				_filter = mode
				_refresh_moves()
		)
		row.add_child(btn)

# --- LIGNES DE COUPS ---

func _build_moves() -> void:
	var moves = GameController.game.move_history
	var cur_ply = GameController.current_ply_index
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
		move_buttons.append(btn)

# Mode filtré : une ligne par coup visible (pleine largeur), pas de trou de layout.
func _build_filtered_single(moves: Array, cur_ply: int) -> void:
	for i in range(moves.size()):
		var m = moves[i]
		if not _passes_filter(m.quality):
			continue
		var btn := _make_move_button(m, i)
		# Préfixe "N." intégré puisque le couple Blanc/Noir n'est pas conservé.
		btn.text = str((i / 2) + 1) + ("..." if i % 2 == 1 else ". ") + btn.text
		container.add_child(btn)
		if i == cur_ply:
			_highlight_active(btn)
		move_buttons.append(btn)

func _make_move_button(m: ChessMove, ply: int) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 48)  # M1 : dense, 2/ligne quand "Tout"
	btn.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	btn.set_meta("ply", ply)

	var text := m.san
	var badge := ChessMove.quality_to_symbol(m.quality)
	if badge != "":
		text += " " + badge
	text += _loss_suffix(m)
	btn.text = text

	if m.quality != ChessMove.Quality.NONE:
		btn.add_theme_color_override("font_color", ChessMove.quality_to_color(m.quality))
	else:
		btn.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)

	btn.pressed.connect(func():
		GameController.navigate_to_ply(ply)
		# Clic sur un coup : revenir à l'échiquier, positionné à ce coup.
		var main := find_parent("Main")
		if main and main.has_method("show_board_tab"):
			main.show_board_tab()
	)
	return btn

func _highlight_active(btn: Button) -> void:
	btn.add_theme_color_override("font_color", DesignTokens.ACCENT)
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.SURFACE_ELEVATED
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

## Suffixe "−N" de perte en centipions pour les coups fautifs (mini-texte).
func _loss_suffix(m: ChessMove) -> String:
	if m.quality == ChessMove.Quality.NONE or MoveQualityService.group(m.quality) == 0:
		return ""
	if m.centipawn_loss > 0:
		return " (−%d)" % int(m.centipawn_loss)
	return ""

func _passes_filter(q: int) -> bool:
	match _filter:
		0:
			return true
		1:
			return q == ChessMove.Quality.INACCURACY
		2:
			return q == ChessMove.Quality.MISTAKE
		3:
			return q == ChessMove.Quality.BLUNDER or q == ChessMove.Quality.MISS
		4:
			return q in [
				ChessMove.Quality.EXCELLENT, ChessMove.Quality.GOOD,
				ChessMove.Quality.GREAT, ChessMove.Quality.BEST,
				ChessMove.Quality.BRILLIANT]
		_:
			return true

func _on_move_navigated(_ply_idx: int) -> void:
	_refresh_moves()

func _scroll_to_active() -> void:
	var cur_ply = GameController.current_ply_index
	for btn in move_buttons:
		if is_instance_valid(btn) and btn.get_meta("ply", -1) == cur_ply:
			ensure_control_visible(btn)
			return
