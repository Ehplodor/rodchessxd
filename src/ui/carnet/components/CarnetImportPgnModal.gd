class_name CarnetImportPgnModal
extends Window
## CarnetImportPgnModal.gd — T3 : import PGN direct dans le profil actif (composition PGNModal).

signal import_completed(game_id: String, new_keys: Array)

var _pgn_modal: PGNModal = null
var _presenter: CarnetPresenter = null
var _profile_id := ""
var _status_lbl: Label

func _init() -> void:
	exclusive = true
	close_requested.connect(queue_free)

func open(presenter: CarnetPresenter, profile_id: String) -> void:
	_presenter = presenter
	_profile_id = profile_id
	_setup_ui()
	DesignTokens.adapt_modal_size(self, 410, 540)
	popup_centered()

func _setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(vbox)

	title = "Importer PGN dans le carnet"

	_pgn_modal = PGNModal.new()
	_pgn_modal.exclusive = false
	vbox.add_child(_pgn_modal)

	# Connecter le signal pgn_loaded
	_pgn_modal.pgn_loaded.connect(_on_pgn_loaded)

	# Remplacer le bouton "Charger & Analyser" par "Charger dans ce carnet"
	# On doit trouver le bouton dans PGNModal et le remplacer
	call_deferred("_replace_load_button")

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(_status_lbl)

func _replace_load_button() -> void:
	if _pgn_modal == null:
		return
	# Le bouton "Charger & Analyser" est le dernier enfant du VBoxContainer dans PGNModal
	var pgn_vbox = _pgn_modal.get_child(0) if _pgn_modal.get_child_count() > 0 else null
	if pgn_vbox and pgn_vbox is VBoxContainer:
		var children = pgn_vbox.get_children()
		if children.size() > 0:
			var last_child = children[children.size() - 1]
			if last_child is Button and str(last_child.text).contains("Charger"):
				last_child.queue_free()
				var btn_load = Button.new()
				btn_load.text = "📥 Charger dans ce carnet"
				btn_load.custom_minimum_size = Vector2(0, DesignTokens.TOUCH_MIN)
				btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn_load.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
				btn_load.pressed.connect(_on_import_pressed)
				pgn_vbox.add_child(btn_load)

func _on_import_pressed() -> void:
	var text = _pgn_modal.pgn_text_edit.text.strip_edges()
	if text == "":
		_status_lbl.text = "Veuillez coller ou charger un texte PGN."
		_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		return
	_status_lbl.text = "Import en cours..."
	_status_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	call_deferred("_do_import", text)

func _do_import(pgn_text: String) -> void:
	var result = _presenter.import_pgn_to_profile(pgn_text, _profile_id)
	var game_id := str(result.get("game_id", ""))
	var matched_keys: Array = result.get("matched_keys", [])
	var new_keys: Array = result.get("new_keys", [])

	if game_id == "":
		_status_lbl.text = "❌ Échec de l'import PGN."
		_status_lbl.add_theme_color_override("font_color", DesignTokens.DANGER)
		return

	if new_keys.is_empty():
		_status_lbl.text = "✅ Partie importée et rattachée (%d clés existantes)." % matched_keys.size()
		_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
		import_completed.emit(game_id, [])
		await get_tree().create_timer(1.5).timeout
		queue_free()
	else:
		var names = ", ".join(new_keys.slice(0, 3))
		if new_keys.size() > 3:
			names += "…"
		_status_lbl.text = "Joueur(s) détecté(s) non dans le carnet : %s" % names
		_status_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)

		var first_key = str(new_keys[0]) if not new_keys.is_empty() else ""
		var dialog = ConfirmationDialog.new()
		dialog.title = "Ajouter aux clés du carnet ?"
		dialog.text = "Joueur «%s» détecté. Ajouter aux clés du carnet ?" % first_key
		dialog.ok_button_text = "Ajouter"
		dialog.cancel_button_text = "Ignorer"
		dialog.add_theme_color_override("font_color", DesignTokens.ACCENT)
		dialog.confirmed.connect(func():
			_presenter.add_player_key(first_key)
			_presenter.refresh_sync()
			_after_key_action(game_id)
		)
		dialog.canceled.connect(func():
			_after_key_action(game_id)
		)
		add_child(dialog)
		dialog.popup_centered()

func _after_key_action(game_id: String) -> void:
	_status_lbl.text = "✅ Partie importée."
	_status_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	import_completed.emit(game_id, [])
	await get_tree().create_timer(1.0).timeout
	queue_free()

func _on_pgn_loaded(pgn: String) -> void:
	# Signal relayé par PGNModal quand l'utilisateur clique sur "Charger & Analyser"
	# (ne se déclenche plus car on a remplacé le bouton)
	pass