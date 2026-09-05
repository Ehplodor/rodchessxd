extends SceneTree
## test_model_downloader.gd - Test unitaire du gestionnaire de téléchargement SLM in-app

const ModelDownloaderScript = preload("res://src/ai/ModelDownloader.gd")

func _init() -> void:
	print("--- Test Unitaire : ModelDownloader (SLM In-App) ---")
	await create_timer(0.1).timeout

	var downloader = ModelDownloaderScript.new()
	root.add_child(downloader)

	# 1. Vérification du répertoire local
	var dir = DirAccess.open("user://")
	assert(dir.dir_exists("models"), "Le dossier user://models/ doit avoir été créé")
	print("✓ Dossier user://models/ vérifié avec succès.")

	# 2. Vérification des modèles configurés
	assert(downloader.DOWNLOADABLE_SLM.has("native_slm/smollm2-360m"), "SmolLM2 360M doit être dans le catalogue de téléchargement")
	assert(downloader.DOWNLOADABLE_SLM.has("native_slm/qwen2.5-0.5b"), "Qwen 2.5 0.5B doit être dans le catalogue")
	assert(downloader.DOWNLOADABLE_SLM.has("native_slm/smollm2-1.7b"), "SmolLM2 1.7B doit être dans le catalogue")

	var smol_info = downloader.DOWNLOADABLE_SLM["native_slm/smollm2-360m"]
	assert(smol_info.url.begins_with("https://"), "L'URL de téléchargement doit être en HTTPS")
	assert(smol_info.filename.ends_with(".gguf"), "Le fichier doit être au format GGUF")
	print("✓ Catalogue SLM vérifié : %s (%s, %s)" % [smol_info.name, smol_info.size_label, smol_info.ram_required])

	# 3. Test de détection et chemin d'un modèle non encore installé
	var installed_before = downloader.is_model_installed("native_slm/smollm2-360m")
	print("Statut initial SmolLM2 360M : %s" % ("Installé" if installed_before else "Non installé"))

	# 4. Simulation d'installation d'un fichier fictif pour valider get_model_file_path et delete_model
	var test_fn = "smollm2-360m-instruct-q4_k_m.gguf"
	var test_path = "user://models/" + test_fn
	var f = FileAccess.open(test_path, FileAccess.WRITE)
	assert(f != null, "Impossible de créer le fichier de test dans user://models/")
	f.store_string("GGUF_MOCK_HEADER")
	f.close()

	assert(downloader.is_model_installed("native_slm/smollm2-360m") == true, "Le modèle doit être détecté comme installé")
	var full_path = downloader.get_model_file_path("native_slm/smollm2-360m")
	assert(full_path != "" and FileAccess.file_exists(full_path), "get_model_file_path doit retourner un chemin valide")
	print("✓ Détection de modèle installé validée : %s" % full_path)

	var installed_list = downloader.get_installed_models()
	assert("native_slm/smollm2-360m" in installed_list, "La liste des modèles installés doit contenir smollm2-360m")
	print("✓ Liste des modèles installés : %s" % str(installed_list))

	# 5. Test de suppression du modèle pour libérer l'espace
	var del_ok = downloader.delete_model("native_slm/smollm2-360m")
	assert(del_ok == true, "La suppression du modèle doit réussir")
	assert(downloader.is_model_installed("native_slm/smollm2-360m") == false, "Le modèle ne doit plus être détecté après suppression")
	assert(not FileAccess.file_exists(test_path), "Le fichier ne doit plus exister sur le disque")
	print("✓ Suppression de modèle et libération d'espace validées avec succès !")

	downloader.queue_free()
	print("\n>>> TOUS LES TESTS MODEL_DOWNLOADER ONT RÉUSSI AVEC SUCCÈS ! <<<")
	quit(0)
