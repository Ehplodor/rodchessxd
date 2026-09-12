class_name ChessComBulkImportModal
extends Window
## ChessComBulkImportModal.gd — T3 : import bulk Chess.com, création de carnet et analyse.

signal import_started
signal import_progress(phase: String, current: int, total: int)
signal import_completed(profile_name: String, game_count: int)

var _presenter: CarnetPresenter = null
var _status_lbl: Label
var _progress_bar: ProgressBar
var _phase_lbl: Label
var _username_edit: LineEdit
var _months_spin: SpinBox
var _max_games_spin: SpinBox
var _profile_name_edit: LineEdit
var _importing := false

func _init() -> void:
	exclusive = true
	close_requested.connect(queue_free)

func open(presenter: CarnetPresenter) -> void:
	_presenter = presenter
	_setup_ui()
	DesignTokens.adapt_modal_size(self, 420, 520)
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

	title = "Importer un carnet Chess.com"

	var last_user := ""
	var sm = _get_settings_manager()
	if sm != null:
		last_user = str(sm.get_setting("last_chesscom_username", ""))

	_username_edit = LineEdit.new()
	_username_edit.placeholder_text = "Pseudo Chess.com (ex: hikaru)"
	_username_edit.text = last_user
	_username_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_username_edit.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_username_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	var username_lbl = Label.new()
	username_lbl.text = "Pseudo Chess.com"
	username_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	username_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	username_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(username_lbl)
	vbox.add_child(_username_edit)

	var months_row = HBoxContainer.new()
	months_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	var months_lbl = Label.new()
	months_lbl.text = "Mois à importer :"
	months_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	months_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	months_row.add_child(months_lbl)
	_months_spin = SpinBox.new()
	_months_spin.min_value = 1
	_months_spin.max_value = 60
	_months_spin.value = 12
	_months_spin.size_flags_horizontal = Control.SIZE_FILL
	months_row.add_child(_months_spin)
	vbox.add_child(months_row)

	var max_games_row = HBoxContainer.new()
	max_games_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	var max_games_lbl = Label.new()
	max_games_lbl.text = "Max parties :"
	max_games_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_games_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	max_games_row.add_child(max_games_lbl)
	_max_games_spin = SpinBox.new()
	_max_games_spin.min_value = 50
	_max_games_spin.max_value = 2000
	_max_games_spin.value = 500
	_max_games_spin.size_flags_horizontal = Control.SIZE_FILL
	max_games_row.add_child(_max_games_spin)
	vbox.add_child(max_games_row)

	_profile_name_edit = LineEdit.new()
	_profile_name_edit.placeholder_text = "Nom du carnet"
	_profile_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_name_edit.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	_profile_name_edit.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	var name_lbl = Label.new()
	name_lbl.text = "Nom du carnet"
	name_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	name_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_lbl)
	vbox.add_child(_profile_name_edit)

	_phase_lbl = Label.new()
	_phase_lbl.text = ""
	_phase_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phase_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_phase_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	vbox.add_child(_phase_lbl)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
	vbox.add_child(_progress_bar)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_status_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	vbox.add_child(_status_lbl)

	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(actions_row)

	var btn_import = Button.new()
	btn_import.text = "Créer carnet & importer"
	btn_import.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_import.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(btn_import, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_import.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	btn_import.pressed.connect(_on_import_pressed)
	actions_row.add_child(btn_import)

	var btn_cancel = Button.new()
	btn_cancel.text = "Annuler"
	btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_cancel.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(btn_cancel, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	btn_cancel.add_theme_color_override("font_color", DesignTokens.DANGER)
	btn_cancel.pressed.connect(_on_cancel_pressed)
	actions_row.add_child(btn_cancel)

	_update_profile_name()

	_username_edit.text_changed.connect(_on_username_changed)
	_months_spin.value_changed.connect(_update_profile_name)
	_max_games_spin.value_changed.connect(_update_profile_name)

func _on_username_changed(_text: String) -> void:
	_update_profile_name()
	var sm = _get_settings_manager()
	if sm != null:
		sm.set_setting("last_chesscom_username", _username_edit.text.strip_edges())

func _get_settings_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("SettingsManager")
	return null

func _update_profile_name(_value: Variant = null) -> void:
	var user := _username_edit.text.strip_edges()
	if user != "" and _profile_name_edit.text.strip_edges() == "":
		_profile_name_edit.text = "Chess.com • %s" % user

func _on_import_pressed() -> void:
	if _importing:
		return
	var username := _username_edit.text.strip_edges()
	if username == "":
		_status_lbl.text = "Veuillez saisir un pseudo Chess.com."
		_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		return

	_importing = true
	_status_lbl.text = "Initialisation..."
	_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	_progress_bar.value = 0

	var options := {
		"max_months": int(_months_spin.value),
		"max_games": int(_max_games_spin.value),
		"depth": 14,
		"mode": "dynamic"
	}

	import_started.emit()
	_presenter.bulk_import_progress.connect(_on_bulk_progress)
	_presenter.batch_progress.connect(_on_batch_progress)
	_presenter.batch_state.connect(_on_batch_state)
	_presenter.error.connect(_on_import_error)
	_presenter.toast_requested.connect(_on_toast)

	call_deferred("_do_import", username, options)

func _do_import(username: String, options: Dictionary) -> void:
	_presenter.bulk_import_chesscom(username, _profile_name_edit.text.strip_edges(), options)

func _on_bulk_progress(phase: String, current: int, total: int) -> void:
	match phase:
		"fetching":
			_phase_lbl.text = "Récupération des mois %d/%d" % [current, total]
			_progress_bar.value = float(current) / maxi(1, float(total)) * 50.0
			_status_lbl.text = "Récupération des archives Chess.com..."
			_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		"importing":
			_phase_lbl.text = "Import des parties %d/%d" % [current, total]
			_progress_bar.value = 50.0 + float(current) / maxi(1, float(total)) * 30.0
			_status_lbl.text = "Import des parties dans la base..."
			_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		"analyzing":
			_phase_lbl.text = "Analyse %d/%d" % [current, total]
			_progress_bar.value = 80.0 + float(current) / maxi(1, float(total)) * 20.0
			_status_lbl.text = "Analyse moteur en cours..."
			_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
		"done":
			_progress_bar.value = 100.0
			_phase_lbl.text = "Terminé"
			_status_lbl.text = "Import terminé."
			_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)

func _on_batch_progress(done: int, total: int, _game_id: String) -> void:
	_progress_bar.value = 80.0 + float(done) / maxi(1, float(total)) * 20.0
	_phase_lbl.text = "Analyse %d/%d" % [done, total]
	_status_lbl.text = "Analyse moteur en cours..."
	_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)

func _on_batch_state(state: String) -> void:
	if state == "done":
		_progress_bar.value = 100.0
		_phase_lbl.text = "Terminé"
		_status_lbl.text = "Carnet prêt."
		_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		import_completed.emit(_profile_name_edit.text.strip_edges(), 0)
		call_deferred("_finish_ok")
	elif state == "cancelled" or state == "failed":
		_status_lbl.text = "Import annulé ou échoué."
		_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		_importing = false

func _on_import_error(err_msg: String) -> void:
	_status_lbl.text = "Erreur : %s" % err_msg
	_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
	_progress_bar.value = 0
	_importing = false

func _on_toast(msg: String, _is_success: bool) -> void:
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)

func _on_cancel_pressed() -> void:
	if _presenter != null:
		_presenter.cancel_bulk_import()
	_status_lbl.text = "Import annulé."
	_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
	_progress_bar.value = 0
	_importing = false
	call_deferred("_finish_ok")

func _finish_ok() -> void:
	if _presenter != null:
		_presenter.bulk_import_progress.disconnect(_on_bulk_progress)
		_presenter.batch_progress.disconnect(_on_batch_progress)
		_presenter.batch_state.disconnect(_on_batch_state)
		_presenter.error.disconnect(_on_import_error)
		_presenter.toast_requested.disconnect(_on_toast)
	queue_free()
