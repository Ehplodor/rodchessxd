extends SceneTree
## test_eval_sync_and_settings_layout.gd
## Valide :
## 1. L'absence d'overflow horizontal de SettingsModal (taille compacte <= 400px, bouton fermer contenu).
## 2. La synchronisation immédiate sans décalage d'un demi-coup entre AdvantageGraph2D, EvalBar2D et TopEvalLabel lors de la navigation et du scrubbing.
## 3. L'immunité contre l'écrasement par des évaluations asynchrones périmées.

func _init() -> void:
	print("\n[TEST] Validation de la mise en page SettingsModal et de la synchronisation EvalBar/Graphe...")
	await create_timer(0.1).timeout
	var root = get_root()
	
	# =========================================================================
	# TEST 1 : Vérification de la mise en page SettingsModal
	# =========================================================================
	print("  -> Test 1: Vérification du dimensionnement et de l'overflow de SettingsModal...")
	var modal = SettingsModal.new()
	root.add_child(modal)
	
	# La fenêtre doit avoir une taille calculée raisonnable
	assert(modal.size.x >= 280 and modal.size.x <= 420, "Largeur de SettingsModal inattendue : %d" % modal.size.x)
	assert(modal.size.y >= 440, "Hauteur de SettingsModal trop faible : %d" % modal.size.y)
	
	# Le root_vbox et le scroll doivent respecter la largeur de la fenêtre
	var root_vbox: VBoxContainer = null
	for child in modal.get_children():
		if child is VBoxContainer:
			root_vbox = child
			break
	assert(root_vbox != null, "root_vbox introuvable dans SettingsModal")
	
	# Vérification de la largeur minimale combinée de la modal : elle ne doit pas forcer 450px+
	var min_w = root_vbox.get_combined_minimum_size().x
	print("    Largeur minimale combinée de SettingsModal : %.1f px (cible <= 380 px)" % min_w)
	assert(min_w <= 380.0, "Débordement détecté : la largeur minimale combinée (%.1f px) dépasse 380 px !" % min_w)
	
	modal.queue_free()
	print("    ✅ SettingsModal est parfaitement contenu et ne déborde plus à droite.")
	
	# =========================================================================
	# TEST 2 : Initialisation de la scène Main et synchronisation EvalBar / Graphe
	# =========================================================================
	print("  -> Test 2: Synchronisation instantanée EvalBar2D / AdvantageGraph2D sur navigation...")
	var main_scene = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main_scene)
	await create_timer(0.2).timeout
	
	var gc = root.get_node_or_null("GameController")
	var graph: AdvantageGraph2D = main_scene.advantage_graph
	var eval_bar: EvalBar2D = main_scene.eval_bar
	var top_label: Label = main_scene.top_eval_label
	
	assert(graph != null, "AdvantageGraph2D introuvable dans Main")
	assert(eval_bar != null, "EvalBar2D introuvable dans Main")
	assert(top_label != null, "TopEvalLabel introuvable dans Main")
	
	# Simulation d'une partie avec un tournant critique à un coup précis (gaffe)
	# Ply 0 (1. e4) : +30 cp (+0.3)
	# Ply 1 (1... e5) : +20 cp (+0.2)
	# Ply 2 (2. Nf3) : +40 cp (+0.4)
	# Ply 3 (2... f6??) : +420 cp (+4.2)  <-- BLUNDER / TOURNANT
	# Ply 4 (3. Nxe5!) : +450 cp (+4.5)
	var sample_evals: Array = [
		{"ply": 0, "move_number": 1, "is_white": true, "san": "e4", "score_cp": 30, "quality": ChessMove.Quality.GOOD, "ci_margin": 25.0},
		{"ply": 1, "move_number": 1, "is_white": false, "san": "e5", "score_cp": 20, "quality": ChessMove.Quality.GOOD, "ci_margin": 25.0},
		{"ply": 2, "move_number": 2, "is_white": true, "san": "Nf3", "score_cp": 40, "quality": ChessMove.Quality.EXCELLENT, "ci_margin": 25.0},
		{"ply": 3, "move_number": 2, "is_white": false, "san": "f6", "score_cp": 420, "quality": ChessMove.Quality.BLUNDER, "ci_margin": 30.0},
		{"ply": 4, "move_number": 3, "is_white": true, "san": "Nxe5", "score_cp": 450, "quality": ChessMove.Quality.BEST, "ci_margin": 25.0}
	]
	
	graph.set_evaluations(sample_evals)
	
	# Étape 1 : Navigation au départ (ply = -1)
	main_scene._sync_eval_to_ply(-1)
	assert(eval_bar.display_score_text == "+0.2", "Au départ (ply=-1), l'EvalBar doit être à +0.2 (obtenu: %s)" % eval_bar.display_score_text)
	assert(top_label.text == "+0.2", "Au départ, top_eval_label doit être +0.2 (obtenu: %s)" % top_label.text)
	print("    ✅ Ply -1 (Position initiale) : EvalBar=%s, TopLabel=%s" % [eval_bar.display_score_text, top_label.text])
	
	# Étape 2 : Navigation à ply 2 (avant la gaffe : 2. Nf3)
	main_scene._sync_eval_to_ply(2)
	assert(eval_bar.display_score_text == "+0.4", "À ply 2, l'EvalBar doit être à +0.4 (obtenu: %s)" % eval_bar.display_score_text)
	assert(top_label.text == "+0.4", "À ply 2, top_eval_label doit être +0.4 (obtenu: %s)" % top_label.text)
	print("    ✅ Ply 2 (2. Nf3) : EvalBar=%s, TopLabel=%s" % [eval_bar.display_score_text, top_label.text])
	
	# Étape 3 : Navigation à ply 3 (LA GAFFE 2... f6?? -> bascule à +4.2)
	# Vérification qu'il n'y a AUCUN décalage d'un demi-coup
	main_scene._sync_eval_to_ply(3)
	assert(eval_bar.display_score_text == "+4.2", "À ply 3 (gaffe), l'EvalBar doit immédiatement passer à +4.2 sans retard d'un demi-coup ! (obtenu: %s)" % eval_bar.display_score_text)
	assert(top_label.text == "+4.2", "À ply 3, top_eval_label doit immédiatement être +4.2 (obtenu: %s)" % top_label.text)
	print("    ✅ Ply 3 (2... f6?? Gaffe décisive) : bascule immédiate à +4.2 sur l'EvalBar !")
	
	# Étape 4 : Navigation en arrière (ply 3 -> ply 2)
	main_scene._sync_eval_to_ply(2)
	assert(eval_bar.display_score_text == "+0.4", "En reculant à ply 2, l'EvalBar doit immédiatement redevenir +0.4 ! (obtenu: %s)" % eval_bar.display_score_text)
	assert(top_label.text == "+0.4", "En reculant à ply 2, top_eval_label doit être +0.4 (obtenu: %s)" % top_label.text)
	print("    ✅ Recul à ply 2 : retour immédiat à +0.4 (aucun demi-coup de retard en arrière).")
	
	# =========================================================================
	# TEST 3 : Validation du scrubbing tactile en temps réel
	# =========================================================================
	print("  -> Test 3: Validation du signal move_scrubbed (scrubbing tactile à 60 FPS)...")
	# Émission de move_scrubbed pour ply 4
	graph.move_scrubbed.emit(4)
	assert(eval_bar.display_score_text == "+4.5", "Pendant le scrubbing sur ply 4, l'EvalBar doit suivre à +4.5 (obtenu: %s)" % eval_bar.display_score_text)
	print("    ✅ Le scrubbing tactile pilote directement la jauge d'évaluation en continu.")
	
	# =========================================================================
	# TEST 4 : Protection contre l'écrasement par des évaluations moteur asynchrones périmées
	# =========================================================================
	print("  -> Test 4: Protection contre les évaluations asynchrones résiduelles du moteur...")
	# Position active fixée à ply 3 (+4.2)
	if gc:
		gc.current_ply_index = 3
	main_scene._sync_eval_to_ply(3)
	assert(eval_bar.display_score_text == "+4.2")
	
	# Le moteur live renvoie une évaluation obsolète d'un ancien coup (ex: score 10 cp, mat 0)
	main_scene._on_engine_eval(10, 0, 12, "g1f3", [], [])
	
	# L'EvalBar doit CONSERVER +4.2 et ne pas être écrasée par le score 10 cp (+0.1) !
	assert(eval_bar.display_score_text == "+4.2", "L'évaluation du coup actif a été écrasée par un retour asynchrone obsolète ! (obtenu: %s)" % eval_bar.display_score_text)
	assert(top_label.text == "+4.2", "top_eval_label a été écrasé par un retour asynchrone obsolète !")
	print("    ✅ L'évaluation analysée est préservée intacte contre les retours résiduels du moteur.")
	
	main_scene.queue_free()
	
	print("\n🎉 TOUS LES TESTS DE MISE EN PAGE ET DE SYNCHRONISATION EVALBAR/GRAPHE SONT VALIDÉS AVEC SUCCÈS !\n")
	quit(0)
	
	main_scene.queue_free()
	
	print("\n🎉 TOUS LES TESTS DE MISE EN PAGE ET DE SYNCHRONISATION EVALBAR/GRAPHE SONT VALIDÉS AVEC SUCCÈS !\n")
	quit(0)
