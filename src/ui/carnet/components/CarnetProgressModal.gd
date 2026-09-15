class_name CarnetProgressModal
extends Window
## CarnetProgressModal.gd — Modale de progression continue, dynamique et non-bloquante pour LeCarnet.
##
## Affiche l'avancement d'un traitement en temps réel sans jamais geler l'application :
## - Contrôles complets : « ⏸ Pause » (ou « ▶ Reprendre »), « ⏹ Stop », « Arrière-plan », « Fermer »
## - Barre 1 (Principale) : Progression globale (parties traitées / total)
## - Barre 2 (Secondaire) : Progression de la partie en cours (demi-coups analysés / total)
## - Barre 3 (Tertiaire)   : Progression très fine (2px) du calcul du demi-coup par le moteur (profondeur)
## - Informations textuelles en direct sur la nature de l'opération (atomisation, moteur, coup en cours)

signal cancelled
signal completed
signal pause_requested
signal resume_requested

var _title_lbl: Label
var _subtitle_lbl: Label
var _counter_lbl: Label
var _progress_bar: ProgressBar

# Panneau partie en cours
var _op_badge_lbl: Label
var _game_info_lbl: Label
var _ply_counter_lbl: Label
var _game_progress_bar: ProgressBar
var _engine_ply_bar: ProgressBar
var _engine_depth_lbl: Label
var _substep_lbl: Label
var _log_lbl: Label

# Boutons d'action
var _btn_pause: Button
var _btn_stop: Button
var _btn_cancel: Button:
	get: return _btn_stop
var _btn_background: Button
var _btn_close: Button
var _actions_row: HBoxContainer

var _is_done: bool = false
var _is_paused: bool = false
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
	_is_paused = false
	_logs.clear()
	_setup_ui(op_title, subtitle)
	DesignTokens.adapt_modal_size(self, 480.0, 480.0)
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

	# 1. Titre & sous-titre
	_title_lbl = Label.new()
	_title_lbl.text = op_title
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BUTTON)
	_title_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	vbox.add_child(_title_lbl)

	if subtitle != "":
		_subtitle_lbl = Label.new()
		_subtitle_lbl.text = subtitle
		_subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_subtitle_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		_subtitle_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
		vbox.add_child(_subtitle_lbl)

	# 2. Barre 1 — Progression globale (principale)
	var global_header = HBoxContainer.new()
	global_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(global_header)

	var global_tag = Label.new()
	global_tag.text = "PROGRESSION GLOBALE"
	global_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	global_tag.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 1)
	global_tag.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	global_header.add_child(global_tag)

	_counter_lbl = Label.new()
	_counter_lbl.text = "Initialisation... (0 / %d)" % _total
	_counter_lbl.clip_text = true
	_counter_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_counter_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_counter_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	global_header.add_child(_counter_lbl)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.step = 0.0
	_progress_bar.value = 0.0
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size.y = float(DesignTokens.TOUCH_DENSE)
	vbox.add_child(_progress_bar)

	# 3. Panneau des détails de la partie courante
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

	# Ligne d'en-tête de la carte : Badge opération + Titre de la partie
	var card_top_row = HBoxContainer.new()
	card_top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_vbox.add_child(card_top_row)

	_op_badge_lbl = Label.new()
	_op_badge_lbl.text = "⚡ Préparation"
	_op_badge_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_op_badge_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)
	card_top_row.add_child(_op_badge_lbl)

	_game_info_lbl = Label.new()
	_game_info_lbl.text = "Chargement de la file..."
	_game_info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_game_info_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	_game_info_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	_game_info_lbl.clip_text = true
	_game_info_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_top_row.add_child(_game_info_lbl)

	# Barre 2 — Progression de la partie en cours (demi-coups)
	var ply_header = HBoxContainer.new()
	ply_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_vbox.add_child(ply_header)

	var ply_tag = Label.new()
	ply_tag.text = "PARTIE EN COURS"
	ply_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ply_tag.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	ply_tag.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	ply_header.add_child(ply_tag)

	_ply_counter_lbl = Label.new()
	_ply_counter_lbl.text = "—"
	_ply_counter_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_ply_counter_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_SECONDARY)
	ply_header.add_child(_ply_counter_lbl)

	_game_progress_bar = ProgressBar.new()
	_game_progress_bar.min_value = 0.0
	_game_progress_bar.max_value = 100.0
	_game_progress_bar.step = 0.0
	_game_progress_bar.value = 0.0
	_game_progress_bar.show_percentage = false
	_game_progress_bar.custom_minimum_size.y = 8.0
	_game_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g_bg = StyleBoxFlat.new()
	g_bg.bg_color = Color(0.12, 0.14, 0.18, 0.8)
	g_bg.set_corner_radius_all(4)
	_game_progress_bar.add_theme_stylebox_override("background", g_bg)
	var g_fill = StyleBoxFlat.new()
	g_fill.bg_color = DesignTokens.ACCENT
	g_fill.set_corner_radius_all(4)
	_game_progress_bar.add_theme_stylebox_override("fill", g_fill)
	card_vbox.add_child(_game_progress_bar)

	# Barre 3 — Progression très fine (2px) du demi-coup en cours (moteur)
	_engine_ply_bar = ProgressBar.new()
	_engine_ply_bar.min_value = 0.0
	_engine_ply_bar.max_value = 100.0
	_engine_ply_bar.step = 0.0
	_engine_ply_bar.value = 0.0
	_engine_ply_bar.show_percentage = false
	_engine_ply_bar.custom_minimum_size.y = 2.0
	_engine_ply_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var e_bg = StyleBoxFlat.new()
	e_bg.bg_color = Color(0.1, 0.12, 0.15, 0.4)
	e_bg.set_corner_radius_all(1)
	_engine_ply_bar.add_theme_stylebox_override("background", e_bg)
	var e_fill = StyleBoxFlat.new()
	e_fill.bg_color = Color(0.2, 0.85, 1.0, 0.95)
	e_fill.set_corner_radius_all(1)
	_engine_ply_bar.add_theme_stylebox_override("fill", e_fill)
	card_vbox.add_child(_engine_ply_bar)

	_engine_depth_lbl = Label.new()
	_engine_depth_lbl.text = ""
	_engine_depth_lbl.clip_text = true
	_engine_depth_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_engine_depth_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION - 2)
	_engine_depth_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	card_vbox.add_child(_engine_depth_lbl)

	# Sous-étape textuelle
	_substep_lbl = Label.new()
	_substep_lbl.text = "Lecture de la bibliothèque..."
	_substep_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_substep_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_MUTED)
	_substep_lbl.clip_text = true
	_substep_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_vbox.add_child(_substep_lbl)

	# Journal d'activité (logs)
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

	# 4. Ligne des boutons d'action : Pause / Reprendre, STOP, Arrière-plan, Fermer
	_actions_row = HBoxContainer.new()
	_actions_row.add_theme_constant_override("separation", DesignTokens.SPACE_S)
	vbox.add_child(_actions_row)

	_btn_pause = Button.new()
	_btn_pause.text = "⏸ Pause"
	_btn_pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_pause.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_pause, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_pause.pressed.connect(_on_pause_toggle_pressed)
	_actions_row.add_child(_btn_pause)

	_btn_stop = Button.new()
	_btn_stop.text = "⏹ Stop"
	_btn_stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_stop.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_stop, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_stop.add_theme_color_override("font_color", DesignTokens.DANGER)
	_btn_stop.pressed.connect(_on_stop_pressed)
	_actions_row.add_child(_btn_stop)

	_btn_background = Button.new()
	_btn_background.text = "Arrière-plan"
	_btn_background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_background.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_background, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_background.pressed.connect(_on_background_pressed)
	_actions_row.add_child(_btn_background)

	_btn_close = Button.new()
	_btn_close.text = "Fermer"
	_btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_close.custom_minimum_size.y = float(DesignTokens.TOUCH_MIN)
	DesignTokens.style_button(_btn_close, DesignTokens.FONT_BUTTON, DesignTokens.TOUCH_MIN)
	_btn_close.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	_btn_close.visible = false
	_btn_close.pressed.connect(queue_free)
	_actions_row.add_child(_btn_close)

## Met à jour dynamiquement la progression globale et détaillée (rétro-compatible).
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

## Met à jour uniquement la progression globale (parties traitées / total).
func update_global(done: int, total: int, summary: String = "") -> void:
	if _is_done:
		return
	_done = done
	_total = maxi(1, total)
	var pct := clampf((float(_done) / float(_total)) * 100.0, 0.0, 100.0)
	if _progress_bar != null:
		_progress_bar.value = pct
	if _counter_lbl != null:
		_counter_lbl.text = "Partie %d / %d (%.0f%%)" % [_done, _total, pct]
	if summary != "" and _substep_lbl != null:
		_substep_lbl.text = summary

## Met à jour l'avancement de la partie en cours (demi-coups analysés).
func update_game(game_title: String, ply: int, total_plies: int, step_desc: String = "", op_type: String = "") -> void:
	if _is_done:
		return
	if _game_info_lbl != null and game_title != "":
		_game_info_lbl.text = game_title
	if _op_badge_lbl != null and op_type != "":
		_op_badge_lbl.text = op_type
	var t_plies := maxi(1, total_plies)
	var pct := clampf((float(ply) / float(t_plies)) * 100.0, 0.0, 100.0)
	if _game_progress_bar != null:
		_game_progress_bar.value = pct
	if _ply_counter_lbl != null:
		_ply_counter_lbl.text = "Coup %d / %d (%.0f%%)" % [ply, total_plies, pct]
	if step_desc != "" and _substep_lbl != null:
		_substep_lbl.text = step_desc

## Met à jour l'avancement fin du moteur sur le demi-coup en cours (barre tertiaire 2px).
func update_engine_ply(current_depth: int, target_depth: int, move_text: String = "") -> void:
	if _is_done:
		return
	var t_depth := maxi(1, target_depth)
	var pct := clampf((float(current_depth) / float(t_depth)) * 100.0, 0.0, 100.0)
	if _engine_ply_bar != null:
		_engine_ply_bar.value = pct
	if _engine_depth_lbl != null:
		var txt := "Calcul du coup : prof. %d / %d" % [current_depth, target_depth]
		if move_text != "":
			txt += " (%s)" % move_text
		_engine_depth_lbl.text = txt

## Bascule l'état visuel et textuel de la pause.
func set_paused(paused: bool) -> void:
	_is_paused = paused
	if _btn_pause != null:
		_btn_pause.text = "▶ Reprendre" if _is_paused else "⏸ Pause"
	if _op_badge_lbl != null:
		if _is_paused:
			_op_badge_lbl.text = "⏸ En pause"
			_op_badge_lbl.add_theme_color_override("font_color", DesignTokens.WARNING)
		else:
			_op_badge_lbl.text = "⚙️ En cours"
			_op_badge_lbl.add_theme_color_override("font_color", DesignTokens.ACCENT)

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
	if _game_progress_bar != null:
		_game_progress_bar.value = 100.0
	if _engine_ply_bar != null:
		_engine_ply_bar.value = 100.0
	if _counter_lbl != null:
		_counter_lbl.text = "Terminé (100%)"
		_counter_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	if _op_badge_lbl != null:
		_op_badge_lbl.text = "✓ Terminé"
		_op_badge_lbl.add_theme_color_override("font_color", DesignTokens.SUCCESS)
	if _game_info_lbl != null:
		_game_info_lbl.text = summary_text
	if _ply_counter_lbl != null:
		_ply_counter_lbl.text = ""
	if _engine_depth_lbl != null:
		_engine_depth_lbl.text = ""
	if _substep_lbl != null:
		_substep_lbl.text = ""
	if _log_lbl != null:
		_log_lbl.text = ""

	if _btn_pause != null:
		_btn_pause.visible = false
	if _btn_stop != null:
		_btn_stop.visible = false
	if _btn_background != null:
		_btn_background.visible = false
	if _btn_close != null:
		_btn_close.visible = true

	completed.emit()

func _on_pause_toggle_pressed() -> void:
	if _is_done:
		return
	if not _is_paused:
		set_paused(true)
		pause_requested.emit()
	else:
		set_paused(false)
		resume_requested.emit()

func _on_stop_pressed() -> void:
	cancelled.emit()
	finish("Opération interrompue par l'utilisateur.")

func _on_cancel_pressed() -> void:
	_on_stop_pressed()

func _on_background_pressed() -> void:
	# Masque la modale tout en laissant le traitement se poursuivre en arrière-plan
	visible = false

func _on_close_requested() -> void:
	if not _is_done:
		_on_background_pressed()
	else:
		queue_free()
