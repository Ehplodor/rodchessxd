class_name MoveList2D
extends ScrollContainer
## MoveList2D.gd - Feuille de notation des coups avec pastilles d'analyse et navigation interactive

var container: VBoxContainer
var move_buttons: Array[Button] = []

func _ready() -> void:
	custom_minimum_size = Vector2(240, 140)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 2)
	add_child(container)
	
	GameController.position_changed.connect(_refresh_moves)
	GameController.move_navigated.connect(_on_move_navigated)

func _refresh_moves() -> void:
	for child in container.get_children():
		child.queue_free()
	move_buttons.clear()

	var moves = GameController.game.move_history
	var cur_ply = GameController.current_ply_index

	var current_row: HBoxContainer = null

	for i in range(moves.size()):
		var m = moves[i]
		var is_white = (i % 2 == 0)
		var move_num = (i / 2) + 1

		if is_white:
			current_row = HBoxContainer.new()
			current_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			container.add_child(current_row)

			var num_lbl = Label.new()
			num_lbl.text = str(move_num) + "."
			num_lbl.custom_minimum_size = Vector2(30, 0)
			num_lbl.add_theme_color_override("font_color", Color("#64748b"))
			num_lbl.add_theme_font_size_override("font_size", 12)
			current_row.add_child(num_lbl)

		var btn = Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 13)

		var badge = ChessMove.quality_to_symbol(m.quality)
		var text = m.san
		if badge != "":
			text += " " + badge

		btn.text = text

		if m.quality != ChessMove.Quality.NONE:
			btn.add_theme_color_override("font_color", ChessMove.quality_to_color(m.quality))
		else:
			btn.add_theme_color_override("font_color", Color("#f1f5f9"))

		if i == cur_ply:
			btn.add_theme_color_override("font_color", Color("#38bdf8"))
			# Légère surbrillance de fond
			var style = StyleBoxFlat.new()
			style.bg_color = Color("#1e293b")
			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", style)

		var ply_idx = i
		btn.pressed.connect(func(): GameController.navigate_to_ply(ply_idx))
		current_row.add_child(btn)
		move_buttons.append(btn)

	# Défilement automatique vers le bas
	call_deferred("_scroll_to_active")

func _on_move_navigated(_ply_idx: int) -> void:
	_refresh_moves()

func _scroll_to_active() -> void:
	var cur_ply = GameController.current_ply_index
	if cur_ply >= 0 and cur_ply < move_buttons.size():
		var btn = move_buttons[cur_ply]
		if is_instance_valid(btn):
			ensure_control_visible(btn)
