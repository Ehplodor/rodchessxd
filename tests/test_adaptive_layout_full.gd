extends SceneTree

func _init() -> void:
	print("[TEST] --- Démarrage du test d'Adaptabilité Réactive Multi-Formats (9/16 <-> 16/9) ---")
	await create_timer(0.1).timeout

	var main_scene = load("res://src/ui/Main.tscn")
	var main_node = main_scene.instantiate()
	root.add_child(main_node)
	await create_timer(0.1).timeout

	# 1. Test Mode Portrait initial (450 x 800)
	print("\n[TEST 1] Mode Portrait standard (450 x 800)...")
	main_node.size = Vector2(450, 800)
	main_node._check_and_update_layout()
	await create_timer(0.05).timeout

	assert(main_node.is_landscape_layout == false, "Doit être en mode portrait pour 450x800")
	assert(main_node.dashboard.get_parent() == main_node.vbox, "Dashboard doit être dans VBox en portrait")
	assert(main_node.nav_row.get_parent() == main_node.vbox, "NavRow doit être dans VBox en portrait")
	assert(main_node.chess_board.size.x <= 450.0, "Plateau doit respecter la largeur portrait")
	print("  -> Mode Portrait validé : disposition verticale propre ✓ (Plateau: %s)" % str(main_node.chess_board.size))

	# 2. Test Bascule Mode Paysage Écran Large (1280 x 720 - 16/9)
	print("\n[TEST 2] Bascule Mode Paysage 16/9 (1280 x 720)...")
	main_node.size = Vector2(1280, 720)
	main_node._check_and_update_layout()
	await create_timer(0.05).timeout

	assert(main_node.is_landscape_layout == true, "Doit basculer en mode paysage pour 1280x720")
	assert(main_node.dashboard.get_parent() == main_node.center_area, "Dashboard doit être dans CenterArea à droite de l'échiquier")
	assert(main_node.nav_row.get_parent() == main_node.board_column, "NavRow doit être sous l'échiquier dans board_column")
	assert(main_node.chess_board.size.x > 400.0, "L'échiquier doit s'étendre en plein écran verticalement (obtenu: %f)" % main_node.chess_board.size.x)
	assert(is_equal_approx(main_node.chess_board.size.x, main_node.chess_board.size.y), "L'échiquier doit rester strictement carré")
	print("  -> Mode Paysage 16/9 validé : échiquier étendu à %s, Dashboard à droite ✓" % str(main_node.chess_board.size))

	# 3. Test Ancrage Latéral des Overlays (Analyse & Coach sans recouvrir le plateau)
	print("\n[TEST 3] Ancrage latéral de l'Analyse et du Coach (échiquier non recouvert)...")
	main_node._open_analyse_overlay()
	await create_timer(0.05).timeout
	assert(main_node.analyse_overlay.visible == true, "AnalyseOverlay doit être visible")
	assert(main_node.coach_overlay.visible == false, "CoachOverlay doit être masqué")
	assert(main_node.analyse_overlay.position.x >= 450.0, "AnalyseOverlay doit être ancré sur la moitié droite (obtenu x=%f)" % main_node.analyse_overlay.position.x)
	print("  -> AnalyseOverlay ancré à droite : x=%.1f, w=%.1f (échiquier libre à gauche) ✓" % [main_node.analyse_overlay.position.x, main_node.analyse_overlay.size.x])

	# Bascule directe vers Coach via le bouton d'en-tête
	main_node._open_coach_overlay()
	await create_timer(0.05).timeout
	assert(main_node.coach_overlay.visible == true, "CoachOverlay doit être visible")
	assert(main_node.analyse_overlay.visible == false, "AnalyseOverlay doit être masqué")
	assert(main_node.coach_overlay.position.x >= 450.0, "CoachOverlay doit être ancré sur la moitié droite")
	print("  -> CoachOverlay ancré à droite : x=%.1f, w=%.1f ✓" % [main_node.coach_overlay.position.x, main_node.coach_overlay.size.x])

	# Fermeture des overlays : retour au Dashboard
	main_node._close_overlays()
	assert(main_node.analyse_overlay.visible == false)
	assert(main_node.coach_overlay.visible == false)
	print("  -> Fermeture des overlays : Dashboard ré-affiché sous les yeux ✓")

	# 4. Test Re-bascule en Mode Portrait (Smartphone tourné de 90°)
	print("\n[TEST 4] Retour fluide au Mode Portrait (360 x 780)...")
	main_node.size = Vector2(360, 780)
	main_node._check_and_update_layout()
	await create_timer(0.05).timeout

	assert(main_node.is_landscape_layout == false, "Doit revenir en mode portrait")
	assert(main_node.dashboard.get_parent() == main_node.vbox, "Dashboard doit revenir dans VBox")
	assert(main_node.nav_row.get_parent() == main_node.vbox, "NavRow doit revenir dans VBox")
	print("  -> Retour portrait réussi, intégrité absolue de l'arborescence ✓")

	# 5. Test Grand Écran 1080p (1920 x 1080)
	print("\n[TEST 5] Test Écran Full HD (1920 x 1080)...")
	main_node.size = Vector2(1920, 1080)
	main_node._check_and_update_layout()
	await create_timer(0.05).timeout

	assert(main_node.is_landscape_layout == true)
	assert(main_node.chess_board.size.x > 600.0, "Sur 1080p le plateau doit dépasser 600px (obtenu: %f)" % main_node.chess_board.size.x)
	print("  -> Écran 1080p validé : Échiquier géant haute définition = %s ✓" % str(main_node.chess_board.size))

	main_node.queue_free()
	print("\n🎉 TOUS LES TESTS D'ADAPTABILITÉ RÉACTIVE PORTRAIT/PAYSAGE SONT RÉUSSIS (100% OK) !")
	quit(0)
