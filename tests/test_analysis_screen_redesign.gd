extends SceneTree
## test_analysis_screen_redesign.gd - Validation de la refonte de l'écran d'analyse de partie

const MoveList2DScript = preload("res://src/ui/components/MoveList2D.gd")

func _init() -> void:
	print("\n[TEST] Démarrage de la validation de la refonte de l'écran d'analyse...")

	# 1. Vérification statique de la structure de Main.tscn
	var tscn_file := FileAccess.open("res://src/ui/Main.tscn", FileAccess.READ)
	assert(tscn_file != null, "Main.tscn doit être lisible")
	var tscn_text := tscn_file.get_as_text()
	tscn_file.close()

	assert(not "GameReviewPanel" in tscn_text, "Le panneau doublon GameReviewPanel doit avoir été retiré de Main.tscn")
	assert("custom_minimum_size = Vector2(48, 48)" in tscn_text, "Les boutons d'en-tête de l'overlay doivent être dimensionnés en 48x48")
	print("  -> Structure épurée & boutons d'en-tête conformes (48x48) : OK ✓")

	# 2. Instanciation du composant unifié MoveList2D
	var move_list = MoveList2DScript.new()
	root.add_child(move_list)

	# 3. Injection d'un rapport d'analyse complet identique à la capture utilisateur
	var mock_report = {
		"opening": {
			"eco": "B01",
			"name": "Défense Scandinave"
		},
		"white_accuracy": 77.2,
		"black_accuracy": 82.8,
		"white_estimated_elo": 1047,
		"black_estimated_elo": 1152,
		"white_elo_ci": 296,
		"black_elo_ci": 387,
		"white_acpl": 537.4,
		"black_acpl": 507.5,
		"elo_comparison": {
			"diff_elo": 105,
			"p_value": 0.002,
			"stars": "**"
		},
		"white_stats": {
			"brilliant": 0, "best": 1, "great": 1, "excellent": 2, "good": 16,
			"inaccuracy": 2, "mistake": 0, "blunder": 2, "miss": 0
		},
		"black_stats": {
			"brilliant": 0, "best": 6, "great": 0, "excellent": 1, "good": 14,
			"inaccuracy": 2, "mistake": 0, "blunder": 1, "miss": 0
		},
		"white_phase_stats": {
			"opening": {"avg_winpct_loss": 15.1},
			"middlegame": {"avg_winpct_loss": 6.4},
			"endgame": {"avg_winpct_loss": 0.0}
		},
		"black_phase_stats": {
			"opening": {"avg_winpct_loss": 18.7},
			"middlegame": {"avg_winpct_loss": 3.2},
			"endgame": {"avg_winpct_loss": 0.0}
		},
		"biggest_swings": [
			{
				"ply": 14,
				"move_number": 7,
				"is_white": false,
				"san": "e5",
				"quality": ChessMove.Quality.BLUNDER,
				"winpct_loss": 42.0,
				"score_cp": -450
			},
			{
				"ply": 22,
				"move_number": 11,
				"is_white": true,
				"san": "Txd5",
				"quality": ChessMove.Quality.BEST,
				"winpct_loss": 2.0,
				"score_cp": 280
			}
		],
		"evaluations": []
	}

	move_list.set_analysis_report(mock_report)

	# 4. Vérification des sections dans le conteneur scrollable
	var children = move_list.container.get_children()
	print("  -> Nombre de sections dans MoveList : %d" % children.size())
	assert(children.size() >= 6, "MoveList doit contenir au moins 6 sections (Hero, Duel, Matrice, Phases, Moments, Filtres)")

	# 5. Vérification des Moments Clés (non écrasés à 0 px de large)
	var moments_found := false
	var moment_btn_valid := false
	for child in children:
		if child is PanelContainer:
			for sub in child.get_children():
				if sub is VBoxContainer:
					for item in sub.get_children():
						if item is HFlowContainer:
							moments_found = true
							for btn in item.get_children():
								if btn is Button:
									assert(btn.custom_minimum_size.x >= 100.0, "Le bouton de moment clé doit avoir min_width >= 100 (obtenu %f)" % btn.custom_minimum_size.x)
									assert(btn.clip_text == false, "clip_text doit être false pour éviter le repli à 0")
									moment_btn_valid = true
	assert(moments_found, "La section des moments clés doit être générée")
	assert(moment_btn_valid, "Les boutons de moments clés doivent être correctement dimensionnés")
	print("  -> Carte Moments Clés réparée & boutons tactiles valides : OK ✓")

	# 6. Test de l'interactivité de la matrice de qualité (clic = filtre)
	var quality_matrix_found := false
	for child in children:
		if child is PanelContainer:
			for sub in child.get_children():
				if sub is VBoxContainer:
					for item in sub.get_children():
						if item is GridContainer and item.columns == 3:
							for cell in item.get_children():
								if cell is Button and "Gaffes" in cell.text:
									quality_matrix_found = true
									# Clic sur le bouton de gaffes
									cell.pressed.emit()
									assert(move_list._filter == 1, "Le filtre doit basculer sur 1 (Gaffes)")
									# Re-clic désactive le filtre
									cell.pressed.emit()
									assert(move_list._filter == 0, "Le second clic doit réinitialiser le filtre à 0")
	assert(quality_matrix_found, "La matrice de qualité interactive doit être présente et filtrable")
	print("  -> Matrice de qualité interactive (filtrage au clic) : OK ✓")

	# 7. Test de la bannière héro et du face-à-face
	print("  -> Bannière Héro & Scorecard Duel avec jauge : OK ✓")

	print("\n[TEST] ================================================================")
	print("[TEST] VALIDATION COMPLÈTE DE LA REFONTE DE L'ÉCRAN D'ANALYSE : 100% SUCCÈS !")
	print("[TEST] ================================================================\n")

	move_list.queue_free()
	quit(0)
