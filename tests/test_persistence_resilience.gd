extends SceneTree
## Test automatisé de persistance, atomicité, et auto-réparation de l'index

func _init() -> void:
	print("--- Test Persistance & Résilience (DatabaseManager) ---")
	await create_timer(0.05).timeout

	var dm = root.get_node_or_null("DatabaseManager")
	assert(dm != null, "DatabaseManager doit être chargé en autoload")

	# 1. Tester save_json_atomic avec Dictionary et Array
	var test_dict_path := "user://library/_test_atomic_dict.json"
	var test_array_path := "user://library/_test_atomic_array.json"

	dm.save_json_atomic(test_dict_path, {"hello": "world", "num": 42})
	assert(FileAccess.file_exists(test_dict_path), "Le fichier dictionnaire doit exister")
	var loaded_dict = dm.load_json(test_dict_path)
	assert(loaded_dict.get("hello") == "world" and loaded_dict.get("num") == 42, "Données dictionnaire intègres")
	print("✓ save_json_atomic avec Dictionary validé")

	dm.save_json_atomic(test_array_path, [{"id": 1}, {"id": 2}])
	assert(FileAccess.file_exists(test_array_path), "Le fichier tableau doit exister")
	var f_arr = FileAccess.open(test_array_path, FileAccess.READ)
	assert(f_arr != null, "Lecture du tableau")
	var parsed_arr = JSON.parse_string(f_arr.get_as_text())
	assert(parsed_arr is Array and parsed_arr.size() == 2, "Données tableau intègres")
	f_arr = null
	print("✓ save_json_atomic avec Array validé")

	# Nettoyage des tests atomiques
	dm.remove_file(test_dict_path)
	dm.remove_file(test_dict_path + ".bak")
	dm.remove_file(test_array_path)
	dm.remove_file(test_array_path + ".bak")

	# 2. Créer une partie de test réelle
	var pgn := """[Event "Test Resilience"]
[Site "Paris"]
[Date "2026.09.12"]
[White "Player Alpha"]
[Black "Player Beta"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0"""

	var test_gid = dm.record_pgn_game(pgn, "resilience_test")
	assert(test_gid != "", "La partie doit être enregistrée")
	assert(dm.get_game(test_gid).size() > 0, "Partie accessible sur disque")
	var initial_index_size = dm.games_index.size()
	assert(initial_index_size >= 1, "Index doit contenir au moins cette partie")
	print("✓ Partie de test enregistrée : %s" % test_gid)

	# 3. Test de récupération 1 : Corrompre games_index.json (ex: 0 octet ou texte invalide)
	# On s'assure d'abord qu'un .bak existe
	dm._save_index()
	assert(FileAccess.file_exists(dm.INDEX_FILE), "Index principal présent")
	assert(FileAccess.file_exists(dm.INDEX_FILE + ".bak"), "Index .bak présent après deuxième save")

	# Corrompre games_index.json avec des octets corrompus
	var corrupt_file = FileAccess.open(dm.INDEX_FILE, FileAccess.WRITE)
	corrupt_file.store_string("{corrupted-bad-json!!")
	corrupt_file.flush()
	corrupt_file = null

	# Recharger l'index : _load_index doit restaurer depuis .bak
	dm._load_index()
	assert(dm.games_index.size() == initial_index_size, "L'index doit avoir été restauré depuis .bak (taille attendue %d, reçue %d)" % [initial_index_size, dm.games_index.size()])
	print("✓ Récupération depuis .bak validée avec succès")

	# 4. Test de récupération 2 : Supprimer games_index.json ET games_index.json.bak
	# Recharger l'index : _load_index doit reconstruire l'index en scannant le dossier games/
	DirAccess.remove_absolute(dm.INDEX_FILE)
	DirAccess.remove_absolute(dm.INDEX_FILE + ".bak")
	assert(not FileAccess.file_exists(dm.INDEX_FILE), "Index principal supprimé")
	assert(not FileAccess.file_exists(dm.INDEX_FILE + ".bak"), "Index .bak supprimé")

	dm._load_index()
	assert(dm.games_index.size() >= 1, "L'index doit être reconstruit depuis games/ (reçu %d parties)" % dm.games_index.size())
	var found_test := false
	for item in dm.games_index:
		if item.get("id") == test_gid:
			found_test = true
			assert(item.get("white_name") == "Player Alpha", "Nom blanc restauré")
			break
	assert(found_test, "La partie de test doit être retrouvée dans l'index reconstruit")
	assert(FileAccess.file_exists(dm.INDEX_FILE), "L'index reconstruit a été ré-enregistré")
	print("✓ Reconstruction automatique depuis le disque validée avec succès")

	# 5. Tester sync_to_storage sans erreur
	dm.sync_to_storage()
	DatabaseManagerClass.sync_filesystem()
	print("✓ sync_to_storage / sync_filesystem exécuté sans encombre")

	# 6. Nettoyer la partie de test
	dm.delete_game(test_gid)
	assert(dm.get_game(test_gid).is_empty(), "Partie de test supprimée")

	print("\n>>> TOUS LES TESTS DE PERSISTANCE & RÉSILIENCE SONT VALIDÉS ! <<<")
	quit(0)
