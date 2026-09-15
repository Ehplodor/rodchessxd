class_name CarnetProfileEditorModal
extends Window
## CarnetProfileEditorModal.gd — T3 : modale créer/éditer/supprimer profil + gérer clés.
## Modes : "create" | "edit"

signal profile_saved(profile_id: String, is_new: bool)

var _mode := "create"
var _profile_id := ""
var _name_edit: LineEdit
var _new_key_input: LineEdit
var _btn_add_key: Button
var _keys_list: VBoxContainer
var _keys: Array = []
var _presenter: CarnetPresenter = null

func _init() -> void:
	exclusive = true
	close_requested.connect(queue_free)

func open_create(presenter: CarnetPresenter) -> void:
	_presenter = presenter
	_mode = "create"
	_profile_id = ""
	_keys = []
	_setup_ui()
	_rebuild_keys_list()
	DesignTokens.adapt_modal_size(self, 410, 520)
	popup_centered()

func open_edit(presenter: CarnetPresenter, profile_id: String) -> void:
	_presenter = presenter
	_mode = "edit"
	_profile_id = profile_id
	_keys = []
	var profile := CarnetProfiles.get_profile(profile_id)
	if not profile.is_empty():
		for k in profile.get("player_keys", []):
			var norm := DatabaseManagerClass.normalize_player_key(str(k))
			if norm != "" and not _keys.has(norm):
				_keys.append(norm)
	_setup_ui()
	if not profile.is_empty():
		_name_edit.text = str(profile.get("name", ""))
	_rebuild_keys_list()
	DesignTokens.adapt_modal_size(self, 410, 520)
	popup_centered()

func _setup_ui() -> void:
	for child in get_children():
		if child is not FileDialog:
			child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(vbox)

	title = "Nouveau carnet" if _mode == "create" else "Éditer le carnet"

	# 1. Nom du carnet
	vbox.add_child(_setup_label("Nom du carnet", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "ex: Moi, Lichess..."
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_name_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	vbox.add_child(_name_edit)

	# 2. Clés de joueur
	vbox.add_child(_setup_label("Clés joueur (pseudos Lichess, Chess.com...)", DesignTokens.FONT_CAPTION, DesignTokens.TEXT_SECONDARY))

	var add_key_row := HBoxContainer.new()
	add_key_row.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_key_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(add_key_row)

	_new_key_input = LineEdit.new()
	_new_key_input.placeholder_text = "Ajouter un pseudo (ex: rodchess)"
	_new_key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_key_input.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_new_key_input.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_new_key_input.text_submitted.connect(func(_t): _on_add_key_from_input())
	add_key_row.add_child(_new_key_input)

	_btn_add_key = Button.new()
	_btn_add_key.text = "+ Ajouter"
	_btn_add_key.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_btn_add_key.custom_minimum_size.x = 0.0
	# Pas de clip_text : le bouton garde sa largeur naturelle dans la rangée
	# (le champ de saisie voisin est celui qui s'étend).
	_btn_add_key.clip_text = false
	DesignTokens.style_button(_btn_add_key, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_add_key.add_theme_color_override("font_color", DesignTokens.ACCENT)
	_btn_add_key.pressed.connect(_on_add_key_from_input)
	add_key_row.add_child(_btn_add_key)

	# 3. Liste déroulante des clés
	var keys_scroll := ScrollContainer.new()
	keys_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keys_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_scroll.custom_minimum_size.y = 130.0
	DesignTokens.touch_scroll(keys_scroll)
	vbox.add_child(keys_scroll)

	_keys_list = VBoxContainer.new()
	_keys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_list.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	keys_scroll.add_child(_keys_list)

	# 4. Actions
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(actions_row)

	if _mode == "create":
		var btn_create := Button.new()
		btn_create.text = "Créer le carnet"
		btn_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_create.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_create, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_create.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		btn_create.pressed.connect(_on_save)
		actions_row.add_child(btn_create)

		var btn_cancel := Button.new()
		btn_cancel.text = "Annuler"
		btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_cancel.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_cancel, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_cancel.pressed.connect(queue_free)
		actions_row.add_child(btn_cancel)
	else:
		var btn_save := Button.new()
		btn_save.text = "Enregistrer"
		btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_save.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_save, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_save.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		btn_save.pressed.connect(_on_save)
		actions_row.add_child(btn_save)

		if _profile_id != CarnetProfiles.DEFAULT_PROFILE_ID:
			var btn_delete := Button.new()
			btn_delete.text = "Supprimer"
			btn_delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn_delete.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
			DesignTokens.style_button(btn_delete, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
			btn_delete.add_theme_color_override("font_color", DesignTokens.DANGER)
			btn_delete.pressed.connect(_on_delete)
			actions_row.add_child(btn_delete)

		var btn_close := Button.new()
		btn_close.text = "Fermer"
		btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_close.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
		DesignTokens.style_button(btn_close, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
		btn_close.pressed.connect(queue_free)
		actions_row.add_child(btn_close)

func _on_add_key_from_input() -> void:
	if _new_key_input == null:
		return
	var raw := _new_key_input.text.strip_edges()
	if raw == "":
		return
	var norm := DatabaseManagerClass.normalize_player_key(raw)
	if norm == "":
		return
	if not _keys.has(norm):
		_keys.append(norm)
		_rebuild_keys_list()
	_new_key_input.text = ""
	_new_key_input.grab_focus()

func _rebuild_keys_list() -> void:
	if _keys_list == null:
		return
	for child in _keys_list.get_children():
		child.queue_free()

	if _keys.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Aucune clé de joueur enregistrée.\nSaisissez votre pseudo ci-dessus puis cliquez sur « + Ajouter » pour rattacher vos parties à ce carnet."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		empty_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
		_keys_list.add_child(empty_lbl)
		return

	for key in _keys:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
		_keys_list.add_child(row)

		var lbl := Label.new()
		lbl.text = "👤 %s" % key
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
		row.add_child(lbl)

		var btn_remove := Button.new()
		btn_remove.text = "✕"
		btn_remove.tooltip_text = "Retirer la clé « %s »" % key
		btn_remove.custom_minimum_size = Vector2(DesignTokens.TOUCH_DENSE, DesignTokens.TOUCH_DENSE)
		DesignTokens.style_button(btn_remove, DesignTokens.FONT_CAPTION, DesignTokens.TOUCH_DENSE)
		btn_remove.add_theme_color_override("font_color", DesignTokens.DANGER)
		btn_remove.pressed.connect(func(k=key): _on_remove_key(k))
		row.add_child(btn_remove)

func _on_remove_key(key: String) -> void:
	_keys.erase(key)
	_rebuild_keys_list()

func _on_save() -> void:
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name == "":
		name = "Moi" if _profile_id == CarnetProfiles.DEFAULT_PROFILE_ID else "Carnet"

	if _mode == "create":
		var id := _presenter.create_profile(name, "local", _keys)
		profile_saved.emit(id, true)
	else:
		_presenter.update_profile(_profile_id, name, _keys)
		profile_saved.emit(_profile_id, false)
	queue_free()

func _on_delete() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Supprimer le carnet"
	dialog.dialog_text = "Supprimer ce carnet et toutes ses données ? Cette action est irréversible."
	dialog.ok_button_text = "Supprimer"
	dialog.cancel_button_text = "Annuler"
	dialog.add_theme_color_override("font_color", DesignTokens.DANGER)
	dialog.confirmed.connect(func():
		_presenter.delete_profile(_profile_id)
		profile_saved.emit(_profile_id, false)
		queue_free()
	)
	add_child(dialog)
	DesignTokens.adapt_dialog(dialog)
	dialog.popup_centered()

func _setup_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl
