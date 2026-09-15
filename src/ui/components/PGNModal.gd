class_name PGNModal
extends Window
## PGNModal.gd - Fenêtre modale d'import/export de texte ou fichier PGN

signal pgn_loaded(pgn: String)

var pgn_text_edit: TextEdit
var file_dialog: FileDialog
var status_lbl: Label

func _ready() -> void:
	title = "Import / Export PGN"
	DesignTokens.adapt_modal_size(self, 410, 540)
	exclusive = true
	close_requested.connect(queue_free)
	_setup_ui()

func _setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -8
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Barre d'actions rapides
	var actions_row = HBoxContainer.new()
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_theme_constant_override("separation", 6)
	vbox.add_child(actions_row)

	var btn_paste = Button.new()
	btn_paste.text = "📋 Coller"
	btn_paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_paste.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_paste.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_paste.pressed.connect(func():
		var clip = DisplayServer.clipboard_get()
		if clip != "":
			pgn_text_edit.text = clip
	)
	actions_row.add_child(btn_paste)

	var btn_open_file = Button.new()
	btn_open_file.text = "📁 Ouvrir .pgn"
	btn_open_file.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_open_file.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_open_file.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_open_file.pressed.connect(_open_file_dialog)
	actions_row.add_child(btn_open_file)

	var btn_copy = Button.new()
	btn_copy.text = "💾 Copier PGN"
	btn_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_copy.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_copy.pressed.connect(func():
		var gc = _get_game_controller()
		var cur_pgn = gc.game.export_pgn() if (gc and gc.game) else ""
		DisplayServer.clipboard_set(cur_pgn)
		pgn_text_edit.text = cur_pgn
		status_lbl.text = "✅ PGN de la partie copié dans le presse-papier."
	)
	actions_row.add_child(btn_copy)

	# Zone de texte PGN
	pgn_text_edit = TextEdit.new()
	DesignTokens.touch_scroll(pgn_text_edit)
	pgn_text_edit.placeholder_text = "Collez votre texte PGN ici...\n\nExemple:\n[Event \"Game\"]\n1. e4 e5 2. Nf3 Nc6..."
	pgn_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pgn_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pgn_text_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	vbox.add_child(pgn_text_edit)

	# Pré-remplir avec la partie en cours si existante
	var gc_init = _get_game_controller()
	if gc_init and gc_init.game and gc_init.game.move_history.size() > 0:
		pgn_text_edit.text = gc_init.game.export_pgn()

	status_lbl = Label.new()
	status_lbl.text = ""
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(status_lbl)

	# Bouton Charger
	var btn_load = Button.new()
	btn_load.text = "🚀 Charger & Analyser cette partie"
	btn_load.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
	btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_load.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	btn_load.pressed.connect(_on_load_pressed)
	vbox.add_child(btn_load)

	# FileDialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.pgn ; Fichiers d'échecs PGN", "*.* ; Tous fichiers"]
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)

func _open_file_dialog() -> void:
	DesignTokens.adapt_modal_size(file_dialog, 380, 500)
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		var content = f.get_as_text()
		pgn_text_edit.text = content
		status_lbl.text = "Fichier %s chargé." % path.get_file()

func _on_load_pressed() -> void:
	var text = pgn_text_edit.text.strip_edges()
	if text == "":
		status_lbl.text = "Veuillez coller ou charger un texte PGN."
		return

	var gc = _get_game_controller()
	var success = gc.load_pgn(text) if gc else false
	if success:
		pgn_loaded.emit(text)
		queue_free()
	else:
		status_lbl.text = "❌ Format PGN non reconnu ou aucun coup valide trouvé."

func set_export_mode(pgn: String = "") -> void:
	title = "💾 Exporter la partie (PGN)"
	var export_text = pgn
	if export_text == "":
		var gc = _get_game_controller()
		if gc and gc.game:
			export_text = gc.game.export_pgn()
	if pgn_text_edit:
		pgn_text_edit.text = export_text
		pgn_text_edit.editable = false
	if export_text != "":
		DisplayServer.clipboard_set(export_text)
		if status_lbl:
			status_lbl.text = "✅ PGN de la partie copié dans le presse-papier !"

func _get_game_controller() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		return tree.root.get_node("GameController")
	return null
