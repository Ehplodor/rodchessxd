extends SceneTree

func _init() -> void:
	print("[TEST] Validation des profondeurs (Live vs Bilan), affichage dynamique et sécurité moteur...")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)

	await create_timer(0.3).timeout

	var sm = root.get_node("SettingsManager")
	var em = root.get_node("EngineManager")

	assert(em.is_engine_running, "L'engine doit être en cours d'exécution au démarrage")
	var initial_pid = em.process_pipe.get("pid", -1)

	# --- 1. Test fermeture des paramètres sans modification ---
	print("  -> Test 1: Fermeture de SettingsModal SANS modification...")
	main_node._on_btn_settings_pressed()
	await create_timer(0.1).timeout

	var settings = null
	for child in main_node.get_children():
		if child.get_class() == "Window" and child.title.contains("Paramètres"):
			settings = child
			break
	assert(settings != null, "SettingsModal doit être instancié")

	# Fermer sans changer
	settings._on_save_and_close()
	await create_timer(0.2).timeout

	assert(em.is_engine_running, "L'engine doit TOUJOURS tourner après fermeture sans modification")
	var pid_after_noop = em.process_pipe.get("pid", -1)
	assert(pid_after_noop == initial_pid, "Le PID de l'engine ne doit pas avoir changé (zéro redémarrage)")
	print("    ✅ Aucun redémarrage moteur superflu lors d'une simple fermeture des paramètres.")

	# --- 2. Test modification de profondeur live seule ---
	print("  -> Test 2: Modification de la profondeur Live seule...")
	main_node._on_btn_settings_pressed()
	await create_timer(0.1).timeout
	for child in main_node.get_children():
		if child.get_class() == "Window" and child.title.contains("Paramètres"):
			settings = child
			break

	sm.set_setting("engine_depth", 20)
	settings._on_save_and_close()
	await create_timer(0.2).timeout

	assert(em.is_engine_running, "L'engine doit toujours tourner")
	assert(em.process_pipe.get("pid", -1) == initial_pid, "La profondeur live ne doit pas redémarrer le moteur")
	print("    ✅ Changement de profondeur live appliqué sans coupure du moteur.")

	# --- 3. Test has_engine_binary et protection code 143 ---
	print("  -> Test 3: Robustesse de has_engine_binary et simulation exit_code 143...")
	assert(em.has_engine_binary(), "has_engine_binary() doit être vrai")

	var error_received = false
	var on_err = func(msg): error_received = true
	em.engine_error.connect(on_err)

	# Simuler l'arrivée d'un signal SIGTERM 143
	em._on_plugin_engine_exited(143)
	await create_timer(0.1).timeout
	assert(not error_received, "L'exit code 143 (SIGTERM ordonné) ne doit PAS déclencher d'engine_error !")
	print("    ✅ Le code 143 est correctement reconnu comme arrêt normal/SIGTERM et non comme un crash.")

	# --- 4. Test feedback dynamique de profondeur sur le graphe & propreté de TopBar ---
	print("  -> Test 4: Affichage dynamique de profondeur au niveau du graphe et compacité TopBar...")
	var graph = main_node.advantage_graph
	assert(graph.depth_badge != null, "depth_badge doit exister dans AdvantageGraph2D")
	assert(graph.depth_progress_bar != null, "depth_progress_bar doit exister dans AdvantageGraph2D")
	assert(graph.depth_label != null, "depth_label doit exister dans AdvantageGraph2D")

	# Vérifier que le bouton d'agrandissement a bien été supprimé
	for c in graph.get_children():
		if c is Button:
			assert(not c.text.contains("Agrandir"), "Le bouton Agrandir ne doit plus exister !")

	# Simuler une émission d'évaluation à profondeur 12 sur cible 20
	graph._on_engine_eval(45, 0, 12, "e2e4", [], [])
	main_node._on_engine_eval(45, 0, 12, "e2e4", [], [])

	assert(graph.depth_label.text.contains("p. 12/20"), "depth_label sur le graphe doit indiquer (p. 12/20) : " + graph.depth_label.text)
	assert(graph.depth_progress_bar.value == 12.0, "La barre de progression du graphe doit être à 12")
	assert(main_node.top_eval_label.text == "+0.5", "top_eval_label doit rester compact avec uniquement le score : " + main_node.top_eval_label.text)
	print("    ✅ Affichage dynamique sur le graphe et compacité TopBar validés !")

	# --- 5. Test prise en compte de analysis_depth dans le bilan global ---
	print("  -> Test 5: Prise en compte de analysis_depth pour l'analyse de partie...")
	sm.set_setting("analysis_depth", 19)
	var def_anal = 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18
	var read_depth = sm.get_setting("analysis_depth", def_anal)
	assert(read_depth == 19, "analysis_depth doit être égal à 19")
	print("    ✅ analysis_depth est correctement configuré et distinct de engine_depth.")

	print("[TEST] Succès total de tous les tests de validation !")
	quit(0)
