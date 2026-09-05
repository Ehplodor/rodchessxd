extends SceneTree
## test_local_slm_manager.gd - Test unitaire du superviseur de processus SLM local

const LocalSLMManagerScript = preload("res://src/ai/LocalSLMManager.gd")

func _init() -> void:
	print("--- Test Unitaire : LocalSLMManager (Inférence Locale) ---")
	await create_timer(0.1).timeout

	var slm_mgr = LocalSLMManagerScript.new()
	root.add_child(slm_mgr)

	# 1. Vérification de l'endpoint et du port
	var endpoint = slm_mgr.get_api_endpoint_url()
	assert(endpoint == "http://127.0.0.1:8085/v1/chat/completions", "L'endpoint par défaut doit être 127.0.0.1:8085/v1/chat/completions")
	print("✓ Endpoint API OpenAI compatible vérifié : %s" % endpoint)

	# 2. Vérification de la recherche d'exécutable
	var exe_path = slm_mgr.get_server_executable_path()
	print("Chemin de l'exécutable d'inférence détecté : %s" % (exe_path if exe_path != "" else "Aucun (normal si llama-server n'est pas encore présent dans bin/)"))
	var is_available = slm_mgr.is_inference_engine_available()
	print("Disponibilité du moteur d'inférence : %s" % str(is_available))

	# 3. Test de tentative de démarrage sans fichier modèle (doit échouer proprement sans crash)
	var started_dummy = slm_mgr.start_server_for_model("model_inexistant")
	assert(started_dummy == false, "Le serveur ne doit pas démarrer si le fichier modèle n'existe pas")
	assert(slm_mgr.is_running == false, "Le statut is_running doit rester false")
	print("✓ Gestion d'erreur sans crash validée pour modèle inexistant.")

	# 4. Test d'extinction sécurisée (stop_server ne doit jamais planter même si non démarré)
	slm_mgr.stop_server()
	assert(slm_mgr.is_running == false, "stop_server doit laisser is_running à false")
	print("✓ Arrêt propre sans crash validé.")

	slm_mgr.queue_free()
	print("\n>>> TOUS LES TESTS LOCAL_SLM_MANAGER ONT RÉUSSI AVEC SUCCÈS ! <<<")
	quit(0)
