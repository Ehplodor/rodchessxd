extends SceneTree

func _init() -> void:
	print("[TEST] Démarrage du test de validation des réglages et redémarrage moteur...")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)

	await create_timer(0.3).timeout

	var sm = root.get_node("SettingsManager")
	var em = root.get_node("EngineManager")

	# 1. Vérification de SettingsModal
	print("  -> Test 1: Layout et bouton fixe de SettingsModal...")
	main_node._on_btn_settings_pressed()
	await create_timer(0.1).timeout

	var settings = null
	for child in main_node.get_children():
		if child.get_class() == "Window" and child.title.contains("Paramètres"):
			settings = child
			break

	assert(settings != null, "SettingsModal doit être instancié dans main_node")
	var root_vbox = settings.get_child(0) as VBoxContainer
	assert(root_vbox != null, "SettingsModal doit avoir un root_vbox")
	var scroll_found = false
	var bottom_bar_found = false
	var btn_close_found = false

	for child in root_vbox.get_children():
		if child is ScrollContainer:
			scroll_found = true
			assert(child.size_flags_vertical == Control.SIZE_EXPAND_FILL, "Le ScrollContainer doit être en EXPAND_FILL")
		elif child is MarginContainer:
			bottom_bar_found = true
			for b_child in child.get_children():
				if b_child is Button and b_child.text.contains("Fermer & Enregistrer"):
					btn_close_found = true

	assert(scroll_found, "ScrollContainer introuvable dans root_vbox")
	assert(bottom_bar_found, "bottom_bar introuvable dans root_vbox")
	assert(btn_close_found, "Bouton Fermer & Enregistrer introuvable dans bottom_bar")
	print("    ✅ SettingsModal possède bien un bouton 'Fermer & Enregistrer' fixé en bas hors du scroll.")

	# 2. Test sauvegarde des paramètres et redémarrage automatique
	print("  -> Test 2: Sauvegarde des paramètres et apply_engine_settings()...")
	sm.set_setting("engine_threads", 3)
	sm.set_setting("engine_hash_mb", 64)
	settings._on_save_and_close()
	await create_timer(0.4).timeout

	assert(em.is_engine_running, "L'engine doit être relancé et en cours d'exécution après apply_engine_settings")
	print("    ✅ L'engine a bien redémarré automatiquement avec les nouveaux paramètres.")

	# 3. Test de EngineHubModal : bouton Redémarrer disponible
	print("  -> Test 3: Bouton Redémarrer dans EngineHubModal...")
	main_node._on_btn_engine_hub_pressed()
	await create_timer(0.1).timeout

	var hub = null
	for child in main_node.get_children():
		if child.get_class() == "Window" and child.title.contains("Engine Hub"):
			hub = child
			break

	assert(hub != null, "EngineHubModal doit être instancié dans main_node")

	# Trouver le bouton Redémarrer sur la carte Stockfish
	var restart_btn_found = false
	for node in hub.find_children("", "Button", true, false):
		if node.text == "Redémarrer":
			restart_btn_found = true
			print("    ✅ Bouton 'Redémarrer' trouvé sur la carte Stockfish active.")
			# Simuler le clic
			node.pressed.emit()
			break

	assert(restart_btn_found, "Le bouton Redémarrer doit être présent sur la carte Stockfish quand elle est active")
	await create_timer(0.4).timeout

	assert(em.is_engine_running, "L'engine doit être toujours actif après clic sur Redémarrer")
	print("    ✅ Clic sur Redémarrer exécuté avec succès.")

	print("[TEST] Succès total de tous les tests de validation !")
	quit(0)
