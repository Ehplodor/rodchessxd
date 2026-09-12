class_name CarnetProgressModal
extends Window
## CarnetProgressModal.gd — Modale de progression dynamique et non-bloquante pour LeCarnet.
##
## Affiche l'état d'avancement d'un recalcul ou d'un lot en temps réel :
## - Nom de l'opération et du carnet
## - Compteur de parties (X / N) et pourcentage
## - Barre de progression animée
## - Partie courante et sous-étape (coups, atomes)
## - Actions : « Arrière-plan » (pour laisser tourner sans bloquer la vue), « Annuler » ou « Fermer »

signal cancelled
signal completed

var _title_lbl: Label
var _subtitle_lbl: Label
var _counter_lbl: Label
var _progress_bar: ProgressBar
var _game_info_lbl: Label
var _substep_lbl: Label
var _log_lbl: Label
var _btn_background: Button
var _btn_cancel: Button
var _btn_close: Button
var _actions_row: HBoxContainer

var _is_done: bool = false
var _total: int = 0
var _done: int = 0
var _logs: Array[String] = []

func _init() -> void:
	exclusive = false
	unresizable = true
	close_requested.connect(_on_close_requested)

func open(op_title: String, total_items: int, subtitle: String = "") -> void:
	_total = maxi(1, total_items)
	_done = 0
	_is_done = false
	_logs.clear()
	_setup_ui(op_title, subtitle)
	DesignTokens.adapt_modal_size(self, 420.0, 380.0)
	popup_centered()

func _setup_ui(op_title: String, subtitle: String) -> void:
	for child in get_children():
		child.queue_free()

	title = op_title

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = DesignTokens.WINDOW_INSET
	vbox.offset_top = DesignTokens.WINDOW_INSET
	vbox.offset_right = -DesignTokens.WINDOW_INSET
	vbox.offset_bottom = -DesignTokens.WINDOW_INSET
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	add_child(vbox)

	# Titre & sous-titre
	_title_lbl = Label.new()
	_title_lbl.text = op_title
	_title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	vbox.add_child(_title_lbl)

	if subtitle != "":
		_subtitle_lbl = Label.new()
		_subtitle_lbl.text = subtitle
		_subtitle_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		_subtitle_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		vbox.add_child(_subtitle_lbl)

	# Compteur et pourcentage
	_counter_lbl = Label.new()
	_counter_lbl.text = "Initialisation... (0 / %d)" % _total
	_counter_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_counter_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	vbox.add_child(_counter_lbl)

	# Barre de progression
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
	vbox.add_child(_progress_bar)

	# Panneau des détails de la partie courante
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_sb = StyleBoxFlat.new()
	card_sb.bg_color = DesignTokens.THEME_DARK["BG_BASE"]
	card_sb.border_color = DesignTokens.THEME_DARK["BORDER"]
	card_sb.set_border_width_all(1)
	card_sb.set_corner_radius_all(DesignTokens.RADIUS_SMALL)
	card_sb.content_margin_left = DesignTokens.CARD_PAD_H
	card_sb.content_margin_right = DesignTokens.CARD_PAD_H
	card_sb.content_margin_top = DesignTokens.CARD_PAD_V
	card_sb.content_margin_bottom = DesignTokens.CARD_PAD_V
	card.add_theme_stylebox_override("panel", card_sb)
	vbox.add_child(card)

	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	card.add_child(card_vbox)

	_game_info_lbl = Label.new()
	_game_info_lbl.text = "Préparation du lot..."
	_game_info_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_game_info_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	_game_info_lbl.clip_text = true
	_game_info_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_vbox.add_child(_game_info_lbl)

	_substep_lbl = Label.new()
	_substep_lbl.text = "Lecture de la bibliothèque..."
	_substep_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_substep_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_substep_lbl.clip_text = true
	_substep_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_vbox.add_child(_substep_lbl)

	_log_lbl = Label.new()
	_log_lbl.text = ""
	_log_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	_log_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	_log_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_lbl.max_lines_visible = 2
	card_vbox.add_child(_log_lbl)

	# Espacement
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Ligne des boutons d'actions
	_actions_row = HBoxContainer.new()
	_actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(_actions_row)

	_btn_background = Button.new()
	_btn_background.text = "Arrière-plan"
	_btn_background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_background.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_background, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_background.pressed.connect(_on_background_pressed)
	_actions_row.add_child(_btn_background)

	_btn_cancel = Button.new()
	_btn_cancel.text = "Annuler"
	_btn_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_cancel.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_cancel, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_cancel.add_theme_color_override("font_color", DesignTokens.DANGER)
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_actions_row.add_child(_btn_cancel)

	_btn_close = Button.new()
	_btn_close.text = "Fermer"
	_btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_close.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_close, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_close.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_btn_close.visible = false
	_btn_close.pressed.connect(queue_free)
	_actions_row.add_child(_btn_close)

## Met à jour dynamiquement la progression affichée à l'écran.
func update_progress(done: int, total: int, game_title: String, substep: String, log_text: String = "") -> void:
	if _is_done:
		return
	_done = done
	_total = maxi(1, total)
	var pct := clampf((float(_done) / float(_total)) * 100.0, 0.0, 100.0)
	if _progress_bar != null:
		_progress_bar.value = pct
	if _counter_lbl != null:
		_counter_lbl.text = "Partie %d / %d (%.0f%%)" % [_done, _total, pct]
	if _game_info_lbl != null and game_title != "":
		_game_info_lbl.text = game_title
	if _substep_lbl != null and substep != "":
		_substep_lbl.text = substep
	if log_text != "":
		append_log(log_text)

func append_log(text: String) -> void:
	_logs.append(text)
	if _logs.size() > 4:
		_logs.pop_front()
	if _log_lbl != null:
		_log_lbl.text = "\n".join(_logs)

## Marque l'opération comme terminée et affiche le bouton de fermeture.
func finish(summary_text: String) -> void:
	_is_done = true
	if _progress_bar != null:
		_progress_bar.value = 100.0
	if _counter_lbl != null:
		_counter_lbl.text = "Terminé (100%)"
		_counter_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	if _game_info_lbl != null:
		_game_info_lbl.text = summary_text
	if _substep_lbl != null:
		_substep_lbl.text = ""
	if _log_lbl != null:
		_log_lbl.text = ""

	if _btn_background != null:
		_btn_background.visible = false
	if _btn_cancel != null:
		_btn_cancel.visible = false
	if _btn_close != null:
		_btn_close.visible = true

	completed.emit()

func _on_background_pressed() -> void:
	# Masque la modale tout en laissant le traitement se poursuivre en arrière-plan
	visible = false

func _on_cancel_pressed() -> void:
	cancelled.emit()
	queue_free()

func _on_close_requested() -> void:
	if not _is_done:
		_on_background_pressed()
	else:
		queue_free()
