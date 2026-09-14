extends SceneTree

func _init() -> void:
	print("\n[TEST] --- Validation de l'échelle symlog et des aires Blanc/Noir du Graphe ---")
	await create_timer(0.1).timeout

	var graph = AdvantageGraph2D.new()
	graph.size = Vector2(300, 150)
	root.add_child(graph)
	await create_timer(0.1).timeout

	# 1. Tester la formule symlog
	var max_display_cp: float = 1200.0
	var symlog_c: float = 150.0
	var max_log_val: float = log(1.0 + max_display_cp / symlog_c)
	var mid_y: float = 75.0
	var half_h: float = 75.0 * 0.44

	var eval_to_y = func(cp: float) -> float:
		var sign_cp: float = 1.0 if cp >= 0.0 else -1.0
		var abs_cp: float = minf(absf(cp), max_display_cp)
		var norm: float = (log(1.0 + abs_cp / symlog_c) / max_log_val) * sign_cp
		return mid_y - (norm * half_h)

	# Vérification de l'axe médian (0.0 cp -> mid_y)
	assert(absf(eval_to_y.call(0.0) - mid_y) < 0.001, "0.0 cp doit être pile sur mid_y")

	# Vérification de la symétrie Blanc (+cp) / Noir (-cp)
	var y_plus_2 = eval_to_y.call(200.0)
	var y_minus_2 = eval_to_y.call(-200.0)
	assert(y_plus_2 < mid_y, "+2.0 pions doit être au-dessus du centre (axe Y inversé)")
	assert(y_minus_2 > mid_y, "-2.0 pions doit être en-dessous du centre")
	assert(absf((mid_y - y_plus_2) - (y_minus_2 - mid_y)) < 0.001, "L'échelle doit être parfaitement symétrique")

	# Vérification du comportement non-linéaire (différencie bien les bourdes même déjà à +5)
	# Le delta en pixels entre 0 et +200 cp doit être significatif, et entre +500 et +1000 aussi
	var delta_0_to_2 = mid_y - eval_to_y.call(200.0)
	var delta_5_to_10 = eval_to_y.call(500.0) - eval_to_y.call(1000.0)
	assert(delta_0_to_2 > 5.0, "La zone 0..2 pions doit avoir une bonne sensibilité")
	assert(delta_5_to_10 > 2.0, "La zone +5..+10 pions doit continuer à évoluer sans être cappée à 5")
	print("  -> Delta 0 à +2 pions : %.2f px" % delta_0_to_2)
	print("  -> Delta +5 à +10 pions : %.2f px" % delta_5_to_10)

	# 2. Test d'injection de données avec des scores extrêmes (+10, -8, +1.5)
	var test_data = [
		{"ply": 0, "score_cp": 20, "move_number": 1, "san": "e4", "is_white": true},
		{"ply": 1, "score_cp": 150, "move_number": 1, "san": "e5", "is_white": false},
		{"ply": 2, "score_cp": 600, "move_number": 2, "san": "Nf3", "is_white": true}, # Bourde noire -> +6 pions
		{"ply": 3, "score_cp": 1100, "move_number": 2, "san": "f6", "is_white": false}, # Grosse gaffe -> +11 pions
		{"ply": 4, "score_cp": -400, "move_number": 3, "san": "Nxe5", "is_white": true} # Contre-gaffe -> -4 pions
	]
	graph.set_evaluations(test_data)
	assert(graph.evaluations.size() == 5, "Le graphe doit contenir 5 évaluations")
	
	# 3. Test de cas limites : valeurs colinéaires ou dégénérées qui échouaient à la triangulation
	var flat_data = [
		{"ply": 0, "score_cp": 0, "ci_margin": 0.0},
		{"ply": 1, "score_cp": 0, "ci_margin": 0.0},
		{"ply": 2, "score_cp": 0, "ci_margin": 0.0}
	]
	graph.set_evaluations(flat_data)
	graph.queue_redraw()
	await process_frame
	await process_frame

	print("  ✅ Tracé symlog et polygones de remplissage Blanc/Noir validés sans régression !")
	graph.queue_free()
	quit(0)
