extends SceneTree
## tests/test_ui_overflow.gd — Diagnostique le débordement horizontal sur écran étroit.
## Échoue si un contrôle impose une largeur minimale > largeur LOGIQUE du viewport.
##
## NB : avec stretch/mode=canvas_items et aspect=expand, la largeur logique ne peut
## jamais descendre sous viewport_width (450) : un téléphone de 360 px physiques
## affiche un viewport logique de 450 px de large (mise à l'échelle). On compare
## donc les minimums à la largeur logique réelle, pas à la largeur physique.

var _failures := 0

## Laisse la mise en page s'appliquer (les tailles ne sont pas fiables dans la
## frame même où l'on vient de modifier l'arborescence).
func _settle() -> void:
	await process_frame
	await process_frame

func _init() -> void:
	print("--- Running UI overflow diagnostic (narrow phone, logical width) ---")
	await process_frame
	root.size = Vector2i(360, 800)
	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)
	await _settle()
	var width: float = main.get_viewport_rect().size.x
	print("  viewport logique : %.0f px" % width)

	var offenders: Array = []
	_collect_offenders(main, width, offenders)
	offenders.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	_check(offenders.is_empty(), "aucun contrôle ne dépasse %.0f px logiques (%d trouvés)" % [width, offenders.size()])
	for o in offenders.slice(0, 15):
		printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

	# Bouton Carnet intégré au style de la barre du haut.
	var btn = main.get_node_or_null("VBox/TopBar/BtnCarnet")
	_check(btn != null, "bouton Carnet présent")
	if btn != null:
		_check(btn.has_theme_stylebox_override("normal"), "bouton Carnet stylé comme les autres")

	# Les boutons-icônes (emoji) ne doivent jamais être tronqués, sinon leur libellé disparaît.
	var flip = main.get_node_or_null("VBox/TopBar/BtnFlip")
	_check(flip != null and not flip.clip_text, "bouton-icône de la barre non tronqué (libellé préservé)")

	# Ouverture du Carnet : z-order au-dessus de l'échiquier + pas de débordement.
	main._open_carnet_overlay()
	await _settle()
	if main.carnet_overlay != null:
		_check(main.carnet_overlay.z_index >= 200, "overlay Carnet au-dessus des pièces")
		_check(not main.carnet_overlay.z_as_relative, "z_index absolu (z_as_relative = false)")
	offenders.clear()
	_collect_offenders(main, width, offenders)
	_check(offenders.is_empty(), "Carnet ouvert : aucun débordement")

	# Test de la vue séance (drill / échiquier / QCM) sans débordement à 360 px
	if main.carnet_overlay != null and main.carnet_presenter != null:
		var dummy_drill := {
			"position": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
			"reponse_uci": "e7e5",
			"piege_uci": "c7c5",
			"type": "choix_binaire",
			"motif": "qualite|occasion_manquée",
			"adversaire": "AdversaireLongNomTresLongPourTesterOverflow"
		}
		main.carnet_presenter.start_session([dummy_drill])
		main.carnet_overlay._build_session()
		await _settle()
		offenders.clear()
		_collect_offenders(main, width, offenders)
		_check(offenders.is_empty(), "Séance d'entraînement ouverte : aucun débordement")
		for o in offenders.slice(0, 10):
			printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

		# Réponse et affichage de la suite Stockfish
		main.carnet_overlay.choose("c7c5")
		await _settle()
		offenders.clear()
		_collect_offenders(main, width, offenders)
		_check(offenders.is_empty(), "Feedback post-réponse avec suite Stockfish : aucun débordement")

		# Déroulement de l'accordéon débutant
		for c in main.carnet_overlay._content.get_children():
			if c is PanelContainer:
				for sub in c.find_children("", "Button", true, false):
					if str(sub.text).find("Décoder la suite") != -1:
						sub.pressed.emit()
						break
		await _settle()
		offenders.clear()
		_collect_offenders(main, width, offenders)
		_check(offenders.is_empty(), "Accordéon débutant déroulé : aucun débordement")
		for o in offenders.slice(0, 10):
			printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

		main.carnet_presenter.end_session()

	main._close_carnet_overlay()

	# Ouverture de l'Analyse : pas de débordement, y compris avec des coups annotés
	# (SAN + qualité + horloge + motifs) qui allongent la liste des coups.
	var gc = root.get_node_or_null("GameController")
	if gc != null:
		gc.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 Nf6 5. O-O d6 6. Re1 a6 7. Bb3 Ba7 8. c3 h6")
		for mv in gc.game.move_history:
			mv.clock_sec = 123.4
			mv.is_theory = false
			mv.quality = ChessMove.Quality.MISTAKE
			mv.motifs = ["Fourchette royale", "Pièce non protégée"]
	main._open_analyse_overlay()
	await _settle()
	offenders.clear()
	_collect_offenders(main, width, offenders)
	_check(offenders.is_empty(), "Analyse ouverte (coups annotés) : aucun débordement")
	for o in offenders.slice(0, 10):
		printerr("  OVERSIZE %.0f px : %s" % [o["w"], o["path"]])

	# 1. Aucun libellé/bouton rogné sans protection (clip + ellipsis ou autowrap).
	var text_offenders: Array = []
	_collect_text_offenders(main, text_offenders)
	for o in text_offenders.slice(0, 12):
		printerr("  TEXT %.0f px dans %.0f px : %s" % [o["w"], o["box"], o["path"]])
	_check(text_offenders.is_empty(),
			"aucun libellé/bouton rogné sans clip/ellipsis (%d trouvés)" % text_offenders.size())

	# 1bis. Aucun bouton « écrasé » : clip_text annule la largeur minimale d'un
	# Button (→ ~8 px) s'il n'est ni EXPAND ni doté d'un minimum suffisant.
	var crushed: Array = []
	_collect_crushed_buttons(main, crushed)
	for o in crushed.slice(0, 12):
		printerr("  CRUSHED %.0f px '%s' : %s" % [o["w"], o["text"], o["path"]])
	_check(crushed.is_empty(), "aucun bouton écrasé (%d trouvés)" % crushed.size())

	# 1ter. Le HUD moteur (chip de profondeur + bascule d'analyses) doit vivre dans
	# l'en-tête du panneau « Ligne moteur » — jamais dans la barre du haut (sinon
	# il la pousse au-delà de l'écran et tronque tous les libellés).
	var graph = main.advantage_graph
	var hud_host: Node = graph.depth_badge.get_parent()
	_check(hud_host == main.engine_lines_panel.header_row(),
			"HUD moteur dans l'en-tête « Ligne moteur »")
	main._check_and_update_layout()
	await _settle()
	# Ses libellés doivent être entièrement visibles (non tronqués).
	for ctrl in [graph.depth_label, graph.btn_switch_analysis]:
		var txt := str(ctrl.text)
		if txt.is_empty():
			continue
		var f: Font = ctrl.get_theme_font("font")
		var fs: int = ctrl.get_theme_font_size("font_size")
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_check(tw <= ctrl.size.x + 1.0, "libellé moteur entier : '%s' (%.0f px pour %.0f)" % [txt, tw, ctrl.size.x])

	# 2. Les dialogues de confirmation s'adaptent (autowrap + largeur bornée).
	var dlg := ConfirmationDialog.new()
	dlg.title = "Supprimer la partie"
	dlg.dialog_text = "⚠️ Supprimer définitivement « RLFRRR vs Sibwara33 » ?\n\n" \
			+ "Ses analyses moteur/coach et ses traces dans les carnets seront également effacées."
	dlg.ok_button_text = "🗑️ Supprimer"
	dlg.cancel_button_text = "Annuler"
	var extra := dlg.add_button("⟳ Recalculer les atomes", true, "quick")
	main.add_child(dlg)
	DesignTokens.adapt_dialog(dlg)
	_check(dlg.dialog_autowrap, "dialogue : texte en autowrap")
	_check(not dlg.wrap_controls, "dialogue : largeur imposée (pas d'élargissement auto)")
	dlg.popup_centered()
	await _settle()
	_check(float(dlg.size.x) <= width + 0.5, "dialogue : largeur bornée à l'écran (%.0f px)" % dlg.size.x)
	_check(extra != null, "dialogue : bouton secondaire présent")
	var dlg_crushed: Array = []
	_collect_crushed_buttons(dlg, dlg_crushed)
	_check(dlg_crushed.is_empty(), "dialogue : aucun bouton écrasé (%d trouvés)" % dlg_crushed.size())
	for o in dlg_crushed.slice(0, 6):
		printerr("  CRUSHED %.0f px '%s' : %s" % [o["w"], o["text"], o["path"]])
	dlg.hide()
	dlg.queue_free()
	await _settle()

	main.queue_free()
	if _failures == 0:
		print("UI OVERFLOW CHECK PASSED SUCCESSFULLY!")
	else:
		printerr("UI OVERFLOW CHECK FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)

## Aucun libellé/bouton à texte alphabétique ne doit être rogné : soit son texte
## tient dans sa boîte, soit il est protégé (clip_text + ellipsis, ou autowrap).
func _collect_text_offenders(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.visible and not c.is_queued_for_deletion():
				var txt := ""
				if c is Label:
					var l := c as Label
					if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
						txt = l.text
				elif c is Button:
					txt = (c as Button).text
				if txt != "" and txt.find("\n") == -1 and _has_letter(txt):
					var clipped := false
					if c is Label:
						clipped = (c as Label).clip_text \
								or (c as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
					else:
						clipped = (c as Button).clip_text \
								or (c as Button).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
					if not clipped and c.size.x > 1.0:
						var font: Font = c.get_theme_font("font")
						var fs: int = c.get_theme_font_size("font_size")
						if font != null and fs > 0:
							var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
							if tw > c.size.x + 2.0:
								out.append({"w": tw, "box": c.size.x, "path": str(c.get_path())})
		_collect_text_offenders(child, out)

func _has_letter(txt: String) -> bool:
	for i in range(txt.length()):
		var ch := txt.unicode_at(i)
		if (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122):
			return true
	return false

## Détecte les boutons réduits à presque rien (largeur < 24 px) : signe d'un
## clip_text sans largeur garantie (EXPAND ou minimum) ou d'un conteneur qui ne
## leur alloue pas d'espace.
func _collect_crushed_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var c := child as Control
			if c.is_visible_in_tree() and not c.get_class().ends_with("Window"):
				var txt := ""
				var is_btn := false
				if c is Button:
					txt = (c as Button).text
					is_btn = true
				elif c is OptionButton:
					txt = (c as OptionButton).text
					is_btn = true
				if is_btn and txt != "" and _has_letter(txt) and c.size.x < 24.0:
					out.append({"w": c.size.x, "text": txt.substr(0, 22), "path": str(c.get_path())})
		_collect_crushed_buttons(child, out)

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _collect_offenders(node: Node, width: float, out: Array) -> void:
	for child in node.get_children():
		if child is Control:
			var in_horiz_scroll := node is ScrollContainer and (node as ScrollContainer).horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			if not in_horiz_scroll:
				var w := (child as Control).get_combined_minimum_size().x
				if w > width + 0.5:
					out.append({"w": w, "path": str(child.get_path())})
		_collect_offenders(child, width, out)
