class_name CarnetProfileEditorModal
extends Window
## CarnetProfileEditorModal.gd — T3 : modale créer/éditer/supprimer profil + gérer clés.
## Modes : "create" | "edit"

signal profile_saved(profile_id: String, is_new: bool)

var _mode := "create"
var _profile_id := ""
var _name_edit: LineEdit
var _keys_edit: TextEdit
var _keys_list: VBoxContainer
var _presenter: CarnetPresenter = null

func _init() -> void:
	exclusive = true
	close_requested.connect(queue_free)

func open_create(presenter: CarnetPresenter) -> void:
	_presenter = presenter
	_mode = "create"
	_profile_id = ""
	_setup_ui()
	DesignTokens.adapt_modal_size(self, 410, 500)
	popup_centered()

func open_edit(presenter: CarnetPresenter, profile_id: String) -> void:
	_presenter = presenter
	_mode = "edit"
	_profile_id = profile_id
	_setup_ui()
	var profile := CarnetProfiles.get_profile(profile_id)
	if not profile.is_empty():
		_name_edit.text = str(profile.get("name", ""))
		var keys: Array = profile.get("player_keys", [])
		_keys_edit.text = "\n".join(keys)
		_rebuild_keys_list()
	DesignTokens.adapt_modal_size(self, 410, 560)
	popup_centered()

func _setup_ui() -> void:
	for child in get_children():
		if child is not FileDialog:
			child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(vbox)

	title = "Nouveau profil" if _mode == "create" else "Éditer le profil"

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nom du profil"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_name_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	vbox.add_child(Label.new()._setup("Nom du profil", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY))
	vbox.add_child(_name_edit)

	vbox.add_child(Label.new()._setup("Clés joueur (une par ligne)", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY))

	var keys_scroll = ScrollContainer.new()
	keys_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DesignTokens.touch_scroll(keys_scroll)
	vbox.add_child(keys_scroll)

	_keys_list = VBoxContainer.new()
	_keys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_list.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	keys_scroll.add_child(_keys_list)

	_keys_edit = TextEdit.new()
	_keys_edit.placeholder_text = "alice\nbob\ncharlie"
	_keys_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keys_edit.custom_minimum_size.y = 120.0
	_keys_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	DesignTokens.touch_scroll(_keys_edit)
	_keys_edit.text_changed.connect(_rebuild_keys_list)
	vbox.add_child(_keys_edit)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(btn_row)

	var btn_add_key = Button.new()
	btn_add_key.text = "+ Ajouter clé"
	btn_add_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_add_key.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(btn_add_key, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_add_key.pressed.connect(_on_add_key)
	btn_row.add_child(btn_add_key)

	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(actions_row)

	if _mode == "create":
		var btn_create = Button.new()
		btn_create.text = "Créer"
		btn_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_create.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_create, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_create.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		btn_create.pressed.connect(_on_save)
		actions_row.add_child(btn_create)
	else:
		var btn_rename = Button.new()
		btn_rename.text = "Renommer"
		btn_rename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_rename.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_rename, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_rename.add_theme_color_override("font_color", DesignTokens.ACCENT)
		btn_rename.pressed.connect(_on_rename)
		actions_row.add_child(btn_rename)

		var btn_delete = Button.new()
		btn_delete.text = "Supprimer"
		btn_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_delete.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_delete, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_delete.add_theme_color_override("font_color", DesignTokens.DANGER)
		btn_delete.pressed.connect(_on_delete)
		actions_row.add_child(btn_delete)

	var btn_close = Button.new()
	btn_close.text = "Fermer"
	btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_close.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(btn_close, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_close.pressed.connect(queue_free)
	vbox.add_child(btn_close)

func _rebuild_keys_list() -> void:
	for child in _keys_list.get_children():
		child.queue_free()
	var text = _keys_edit.text.strip_edges()
	if text == "":
		return
	var lines = text.split("\n")
	for line in lines:
		var key = line.strip_edges()
		if key == "":
			continue
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
		_keys_list.add_child(row)

		var lbl = Label.new()
		lbl.text = key
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		row.add_child(lbl)

		var btn_remove = Button.new()
		btn_remove.text = "✕"
		btn_remove.custom_minimum_size = Vector2(DesignTokens.TOUCH_DENSE, DesignTokens.TOUCH_DENSE)
		DesignTokens.style_button(btn_remove, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		btn_remove.add_theme_color_override("font_color", DesignTokens.DANGER)
		btn_remove.pressed.connect(func(k=key): _on_remove_key(k))
		row.add_child(btn_remove)

func _on_add_key() -> void:
	var current = _keys_edit.text.strip_edges()
	var dialog = AcceptDialog.new()
	dialog.title = "Ajouter une clé joueur"
	var input = LineEdit.new()
	input.placeholder_text = "ex: alice"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	dialog.add_child(input)
	var btn_ok = dialog.add_button("Ajouter", true, "confirmed")
	btn_ok.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	var btn_cancel = dialog.add_button("Annuler", false, "canceled")
	btn_cancel.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	dialog.confirmed.connect(func():
		var val = input.text.strip_edges()
		if val != "":
			var normalized = DatabaseManagerClass.normalize_player_key(val)
			if normalized != "":
				if current != "":
					_keys_edit.text = current + "\n" + normalized
				else:
					_keys_edit.text = normalized
				_rebuild_keys_list()
	)
	dialog.popup_centered()

func _on_remove_key(key: String) -> void:
	var text = _keys_edit.text.strip_edges()
	var lines = text.split("\n")
	var new_lines: Array = []
	for line in lines:
		if line.strip_edges() != key:
			new_lines.append(line)
	_keys_edit.text = "\n".join(new_lines)
	_rebuild_keys_list()

func _on_save() -> void:
	var name = _name_edit.text.strip_edges()
	if name == "":
		return
	var keys_text = _keys_edit.text.strip_edges()
	var keys: Array = []
	if keys_text != "":
		for line in keys_text.split("\n"):
			var k = line.strip_edges()
			if k != "":
				var norm = DatabaseManagerClass.normalize_player_key(k)
				if norm != "" and not keys.has(norm):
					keys.append(norm)
	if _mode == "create":
		var id = _presenter.create_profile(name, "local", keys)
		profile_saved.emit(id, true)
	else:
		_presenter.rename_profile(_profile_id, name)
		var profile := CarnetProfiles.get_profile(_profile_id)
		var old_keys: Array = profile.get("player_keys", [])
		for k in old_keys:
			if not keys.has(k):
				_presenter.remove_player_key(_profile_id, k)
		for k in keys:
			if not old_keys.has(k):
				_presenter.add_player_key(k)
		profile_saved.emit(_profile_id, false)
	queue_free()

func _on_rename() -> void:
	var name = _name_edit.text.strip_edges()
	if name == "":
		return
	_presenter.rename_profile(_profile_id, name)
	profile_saved.emit(_profile_id, false)
	queue_free()

func _on_delete() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "Supprimer le profil"
	dialog.text = "Supprimer ce profil et toutes ses données ? Cette action est irréversible."
	dialog.ok_button_text = "Supprimer"
	dialog.add_theme_color_override("font_color", DesignTokens.DANGER)
	dialog.confirmed.connect(func():
		_presenter.delete_profile(_profile_id)
		profile_saved.emit(_profile_id, false)
		queue_free()
	)
	dialog.popup_centered()

func _setup(text: String, font_size: int, color: Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl