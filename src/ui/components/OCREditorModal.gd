class_name OCREditorModal
extends Window
## OCREditorModal.gd - Fenêtre modale d'import PNG, aperçu et ajustement rapide de la position avant analyse

const ChessOCR = preload("res://src/vision/ChessOCR.gd")

signal fen_validated(fen: String)

var file_dialog: FileDialog
var fen_input: LineEdit
var image_preview: TextureRect
var grid_container: GridContainer

var current_board: Array = []
var selected_palette_piece: Dictionary = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}

var active_turn: int = ChessPiece.PieceColor.WHITE
var white_at_bottom: bool = true

var square_buttons: Array[Button] = []

func _ready() -> void:
	title = "Importer et Vérifier une Position"
	size = Vector2i(410, 640)
	exclusive = true
	unresizable = false
	close_requested.connect(queue_free)
	
	_setup_ui()
	_reset_board()

func _setup_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_left = 8
	main_vbox.offset_top = 8
	main_vbox.offset_right = -8
	main_vbox.offset_bottom = -8
	add_child(main_vbox)

	# 1. Bouton Sélectionner Image
	var btn_choose = Button.new()
	btn_choose.text = "📁 Sélectionner une image PNG / Capture"
	btn_choose.pressed.connect(_open_file_dialog)
	main_vbox.add_child(btn_choose)

	# 2. Grille 8x8 interactive pour vérification / correction
	var grid_panel = CenterContainer.new()
	main_vbox.add_child(grid_panel)

	grid_container = GridContainer.new()
	grid_container.columns = 8
	grid_container.add_theme_constant_override("h_separation", 1)
	grid_container.add_theme_constant_override("v_separation", 1)
	grid_panel.add_child(grid_container)

	for r in range(8):
		for f in range(8):
			var sq = (7 - r) * 8 + f
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(36, 36)
			btn.flat = false
			var is_light = (r + f) % 2 == 0
			var bg_col = Color("#334155") if is_light else Color("#1e293b")
			var style = StyleBoxFlat.new()
			style.bg_color = bg_col
			btn.add_theme_stylebox_override("normal", style)
			
			var sq_idx = sq
			btn.pressed.connect(func(): _on_square_pressed(sq_idx))
			grid_container.add_child(btn)
			square_buttons.append(btn)

	# 3. Palette de pièces rapides
	var palette_lbl = Label.new()
	palette_lbl.text = "Palette de correction rapide (cliquez une pièce puis une case) :"
	palette_lbl.add_theme_font_size_override("font_size", 11)
	palette_lbl.add_theme_color_override("font_color", Color("#94a3b8"))
	main_vbox.add_child(palette_lbl)

	var palette_box = HBoxContainer.new()
	palette_box.alignment = BoxContainer.ALIGNMENT_CENTER
	palette_box.add_theme_constant_override("separation", 4)
	main_vbox.add_child(palette_box)

	# Pièces blanches
	for t in [ChessPiece.Type.PAWN, ChessPiece.Type.KNIGHT, ChessPiece.Type.BISHOP, ChessPiece.Type.ROOK, ChessPiece.Type.QUEEN, ChessPiece.Type.KING]:
		_add_palette_btn(palette_box, t, ChessPiece.PieceColor.WHITE)

	# Pièces noires
	for t in [ChessPiece.Type.PAWN, ChessPiece.Type.KNIGHT, ChessPiece.Type.BISHOP, ChessPiece.Type.ROOK, ChessPiece.Type.QUEEN, ChessPiece.Type.KING]:
		_add_palette_btn(palette_box, t, ChessPiece.PieceColor.BLACK)

	# Bouton gomme (case vide)
	var btn_empty = Button.new()
	btn_empty.text = "Vide"
	btn_empty.add_theme_font_size_override("font_size", 11)
	btn_empty.pressed.connect(func(): selected_palette_piece = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE})
	palette_box.add_child(btn_empty)

	# 4. Trait et options
	var opt_row = HBoxContainer.new()
	opt_row.add_theme_constant_override("separation", 10)
	main_vbox.add_child(opt_row)

	var btn_turn = CheckButton.new()
	btn_turn.text = "Trait aux Blancs"
	btn_turn.button_pressed = true
	btn_turn.toggled.connect(func(pressed):
		active_turn = ChessPiece.PieceColor.WHITE if pressed else ChessPiece.PieceColor.BLACK
		btn_turn.text = "Trait aux Blancs" if pressed else "Trait aux Noirs"
		_update_fen_display()
	)
	opt_row.add_child(btn_turn)

	# 5. Champ FEN
	fen_input = LineEdit.new()
	fen_input.placeholder_text = "Notation FEN..."
	fen_input.text_submitted.connect(_on_fen_text_submitted)
	main_vbox.add_child(fen_input)

	# 6. Bouton Valider
	var btn_validate = Button.new()
	btn_validate.text = "🚀 Valider & Lancer l'Analyse"
	btn_validate.custom_minimum_size = Vector2(0, 44)
	btn_validate.pressed.connect(_on_validate_pressed)
	main_vbox.add_child(btn_validate)

	# FileDialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.png ; Images PNG", "*.jpg, *.jpeg ; Images JPEG"]
	file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(file_dialog)

func _add_palette_btn(parent: Node, type: int, color: int) -> void:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(28, 28)
	var path = ChessPiece.asset_path(type, color)
	if ResourceLoader.exists(path):
		btn.icon = load(path)
		btn.expand_icon = true
	else:
		btn.text = ChessPiece.to_char(type, color)
	
	btn.pressed.connect(func(): selected_palette_piece = {"type": type, "color": color})
	parent.add_child(btn)

func _reset_board() -> void:
	current_board.clear()
	current_board.resize(64)
	for i in range(64):
		current_board[i] = {"type": ChessPiece.Type.NONE, "color": ChessPiece.PieceColor.NONE}
	_update_grid_ui()
	_update_fen_display()

func _open_file_dialog() -> void:
	file_dialog.popup_centered(Vector2i(380, 500))

func _on_image_file_selected(path: String) -> void:
	var img = ChessOCR.load_image(path)
	if not img:
		return
	var board_rect = ChessOCR.detect_board_rect(img)
	var fen = ChessOCR.recognize_board_fen(img, board_rect, white_at_bottom)
	_load_fen_into_modal(fen)

func _load_fen_into_modal(fen: String) -> void:
	var dummy_game = ChessGame.new()
	if dummy_game.load_fen(fen):
		for i in range(64):
			current_board[i] = dummy_game.get_piece(i)
		active_turn = dummy_game.active_color
		_update_grid_ui()
		_update_fen_display()

func _on_square_pressed(sq: int) -> void:
	current_board[sq] = selected_palette_piece.duplicate()
	_update_grid_ui()
	_update_fen_display()

func _update_grid_ui() -> void:
	for r in range(8):
		for f in range(8):
			var sq = (7 - r) * 8 + f
			var btn_idx = r * 8 + f
			if btn_idx < square_buttons.size():
				var btn = square_buttons[btn_idx]
				var piece = current_board[sq]
				if piece.type != ChessPiece.Type.NONE:
					var path = ChessPiece.asset_path(piece.type, piece.color)
					if ResourceLoader.exists(path):
						btn.icon = load(path)
						btn.expand_icon = true
					else:
						btn.text = ChessPiece.to_char(piece.type, piece.color)
				else:
					btn.icon = null
					btn.text = ""

func _update_fen_display() -> void:
	var fen = ChessOCR._board_state_to_fen(current_board, white_at_bottom)
	var parts = fen.split(" ")
	parts[1] = "w" if active_turn == ChessPiece.PieceColor.WHITE else "b"
	var final_fen = " ".join(parts)
	fen_input.text = final_fen

func _on_fen_text_submitted(text: String) -> void:
	_load_fen_into_modal(text)

func _on_validate_pressed() -> void:
	var fen = fen_input.text.strip_edges()
	if fen != "":
		GameController.load_fen(fen)
		fen_validated.emit(fen)
		queue_free()
