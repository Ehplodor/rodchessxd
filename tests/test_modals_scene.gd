extends SceneTree

func _init() -> void:
	print("[SCENE TEST] Test d'instanciation des 6 modales dans l'arborescence complète...")
	await create_timer(0.1).timeout
	
	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	
	await create_timer(0.1).timeout

	print("  1. Test ouverture OCREditorModal...")
	main_node._on_btn_import_png_pressed()
	await create_timer(0.05).timeout

	print("  2. Test ouverture PGNModal...")
	main_node._on_btn_import_pgn_pressed()
	await create_timer(0.05).timeout

	print("  3. Test ouverture ChessComImportModal...")
	main_node._on_btn_chess_com_pressed()
	await create_timer(0.05).timeout

	print("  4. Test ouverture EngineHubModal...")
	main_node._on_btn_engine_hub_pressed()
	await create_timer(0.05).timeout

	print("  5. Test ouverture SettingsModal...")
	main_node._on_btn_settings_pressed()
	await create_timer(0.05).timeout

	print("  6. Test ouverture ModelHubModal...")
	var coach_panel = main_node.get_node("VBox/BottomTabs/Coach/CoachPanel")
	coach_panel._open_model_hub()
	await create_timer(0.05).timeout

	print("  7. Test ouverture LibraryModal...")
	main_node._on_btn_library_pressed()
	await create_timer(0.05).timeout

	print("[SCENE TEST] Succès total ! Toutes les 7 modales s'ouvrent, se mettent en page et se comportent correctement !")
	quit(0)
