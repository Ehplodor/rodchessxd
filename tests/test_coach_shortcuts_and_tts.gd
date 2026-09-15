extends SceneTree

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("=== Running Coach Shortcuts & TTS Tests ===")
	var failures = 0

	# -------------------------------------------------------------
	# 1. TEST SETTINGSMANAGER
	# -------------------------------------------------------------
	print("\n[Test 1] Vérification du paramètre de voix dans SettingsManager...")
	var sm = root.get_node_or_null("SettingsManager")
	if sm:
		var gender = sm.get_setting("coach_voice_gender", "")
		print("  -> coach_voice_gender actuel: ", gender)
		assert(gender in ["female", "male"], "coach_voice_gender doit être 'female' ou 'male'")

		var tts_model = sm.get_setting("coach_tts_model", "")
		print("  -> coach_tts_model actuel: ", tts_model)
		assert(tts_model in ["local_system", "deepgram/flux-tts:free", "fish-audio/s2.1-pro-free:free"], "coach_tts_model doit être un modèle valide")
		print("  ✓ Paramètres vocaux SettingsManager validés.")
	else:
		printerr("  ❌ SettingsManager non trouvé!")
		failures += 1

	# -------------------------------------------------------------
	# 2. TEST AICOACH TTS & CLEANING
	# -------------------------------------------------------------
	print("\n[Test 2] Vérification des méthodes AICoach et nettoyage vocal...")
	var ac = root.get_node_or_null("AICoach")
	if ac:
		assert(ac.has_method("execute_coach_prompt"), "AICoach doit posséder execute_coach_prompt")
		assert(ac.has_method("speak_text"), "AICoach doit posséder speak_text")
		assert(ac.has_method("stop_speech"), "AICoach doit posséder stop_speech")
		assert(ac.has_method("clean_text_for_speech"), "AICoach doit posséder clean_text_for_speech")

		# Test clean_text_for_speech
		var sample_md = "🎯 **Diagnostic** : <think>Calcul interne</think>Les Blancs ont un net avantage.\n\n💡 **Analyse & Réfutation** : Le coup `Fg5` cloue le Cavalier.\n\n📌 **Plan conseillé** : - Pousser d4."
		var cleaned = ac.clean_text_for_speech(sample_md)
		print("  -> Texte nettoyé: ", cleaned)
		assert(not cleaned.contains("<think>"), "Le raisonnement doit être exclu")
		assert(not cleaned.contains("Calcul interne"), "Le texte interne think doit être retiré")
		assert(not cleaned.contains("**"), "Le gras Markdown doit être retiré")
		assert(not cleaned.contains("`"), "Les backticks doivent être retirés")
		assert(not cleaned.contains("🎯"), "L'emoji cible doit être retiré")
		assert(not cleaned.contains("💡"), "L'emoji ampoule doit être retiré")
		assert(not cleaned.contains("📌"), "L'emoji punaise doit être retiré")
		assert(cleaned.contains("Les Blancs ont un net avantage"), "Le contenu essentiel doit être préservé")

		# Test phonétique des notations échiquéennes (roque, prise, échec, mat)
		var chess_sample = "Après 0-0 et Cxe4+, la Dame joue Dxf7#."
		var cleaned_chess = ac.clean_text_for_speech(chess_sample)
		print("  -> Notation échiquéenne nettoyée: ", cleaned_chess)
		assert(cleaned_chess.contains("Petit roque"), "0-0 doit devenir Petit roque")
		assert(cleaned_chess.contains("prend"), "x doit devenir prend")
		assert(cleaned_chess.contains("échec"), "+ doit devenir échec")
		assert(cleaned_chess.contains("échec et mat"), "# doit devenir échec et mat")

		# Test rejet de l'avertissement de limite de jetons (brouillon de réflexion)
		var fallback_text = "⚠️ *Le modèle a atteint sa limite de jetons pendant sa réflexion préliminaire. Voici sa réflexion brute :*\n\nDraft reasoning..."
		var cleaned_fallback = ac.clean_text_for_speech(fallback_text)
		assert(cleaned_fallback == "", "Le brouillon de réflexion brute ne doit pas être vocalisé")

		# Test plafonnement à 1500 caractères sans coupure brutale de mot
		var long_text = ""
		for _i in range(40):
			long_text += "Le coup Fg5 cloue le Cavalier f6 contre la Dame d8. Les Noirs doivent réagir avec h6. "
		var cleaned_long = ac.clean_text_for_speech(long_text, 1500)
		assert(cleaned_long.length() <= 1500, "Le texte nettoyé ne doit jamais excéder 1500 caractères")
		assert(cleaned_long.ends_with(".") or cleaned_long.ends_with("!") or cleaned_long.ends_with("?"), "Le texte doit se terminer proprement par une ponctuation")
		print("  -> Longueur texte plafonné: %d caractères (fin: '%s')" % [cleaned_long.length(), cleaned_long.substr(cleaned_long.length() - 20)])
		print("  ✓ clean_text_for_speech fonctionne parfaitement.")

		# Test détection des modèles de réflexion (ModelCatalog & AICoach)
		var mc = root.get_node_or_null("ModelCatalog")
		if mc and mc.has_method("is_reasoning_model"):
			assert(mc.is_reasoning_model("inclusionai/ling-3.0-flash-vl:free"), "Ling doit être détecté comme reasoning")
			assert(mc.is_reasoning_model("deepseek/deepseek-r1:free"), "R1 doit être détecté comme reasoning")
			assert(not mc.is_reasoning_model("meta-llama/llama-3.1-8b-instruct"), "Llama 3.1 8b standard ne doit pas être reasoning")
			print("  ✓ is_reasoning_model validé sur ModelCatalog.")
	else:
		printerr("  ❌ AICoach non trouvé!")
		failures += 1

	# -------------------------------------------------------------
	# 3. TEST COACHPANEL2D VOIX
	# -------------------------------------------------------------
	print("\n[Test 3] Vérification de l'interface CoachPanel2D avec sélecteur de voix...")
	var CoachPanel2DScript: GDScript = load("res://src/ui/components/CoachPanel2D.gd")
	if CoachPanel2DScript:
		var cp = CoachPanel2DScript.new()
		root.add_child(cp)
		assert(cp.voice_buttons.size() == 2, "CoachPanel2D doit avoir 2 boutons de voix (female, male)")
		assert("female" in cp.voice_buttons, "Bouton 'female' présent")
		assert("male" in cp.voice_buttons, "Bouton 'male' présent")
		
		# Test bascule voix
		cp._set_voice_gender("male")
		assert(cp.active_voice_gender == "male", "Bascule vers male réussie")
		if sm:
			assert(sm.get_setting("coach_voice_gender", "") == "male", "Persistance vers SettingsManager réussie")
		cp._set_voice_gender("female")
		assert(cp.active_voice_gender == "female", "Bascule vers female réussie")
		print("  ✓ CoachPanel2D sélecteur de voix validé.")
		cp.queue_free()
	else:
		printerr("  ❌ CoachPanel2D introuvable!")
		failures += 1

	# -------------------------------------------------------------
	# 4. TEST SETTINGSMODAL
	# -------------------------------------------------------------
	print("\n[Test 4] Vérification de la modale SettingsModal...")
	var SettingsModalScript: GDScript = load("res://src/ui/components/SettingsModal.gd")
	if SettingsModalScript:
		var sm_modal = SettingsModalScript.new()
		root.add_child(sm_modal)
		assert(is_instance_valid(sm_modal), "SettingsModal doit s'instancier correctement")
		print("  ✓ SettingsModal instancié sans erreur.")
		sm_modal.queue_free()
	else:
		printerr("  ❌ SettingsModal introuvable!")
		failures += 1

	# -------------------------------------------------------------
	# 5. TEST MAIN RACCOURCIS PLATEAU
	# -------------------------------------------------------------
	print("\n[Test 5] Vérification de l'arborescence Main et des raccourcis joueurs...")
	var MainSceneRes = load("res://src/ui/Main.tscn")
	if MainSceneRes:
		var main_scene = MainSceneRes.instantiate()
		root.add_child(main_scene)

		assert(main_scene.player_shortcuts_top != null, "PlayerShortcutsTop doit exister")
		assert(main_scene.player_shortcuts_bottom != null, "PlayerShortcutsBottom doit exister")
		assert(main_scene.top_shortcut_buttons.size() == 7, "Il doit y avoir 7 boutons raccourcis en haut")
		assert(main_scene.bottom_shortcut_buttons.size() == 7, "Il doit y avoir 7 boutons raccourcis en bas")
		assert(main_scene.top_speech_btn != null, "Le bouton audio haut doit exister")
		assert(main_scene.bottom_speech_btn != null, "Le bouton audio bas doit exister")

		# Vérifier tooltips adaptés
		var gc = root.get_node_or_null("GameController")
		if gc:
			gc.board_flipped = false
			main_scene._update_player_labels()
			# Si non retourné : haut = Noirs, bas = Blancs
			assert(main_scene.top_shortcut_buttons[0].tooltip_text.contains("Noirs"), "Haut non retourné -> Noirs")
			assert(main_scene.bottom_shortcut_buttons[0].tooltip_text.contains("Blancs"), "Bas non retourné -> Blancs")

			# Si retourné : haut = Blancs, bas = Noirs
			gc.board_flipped = true
			main_scene._update_player_labels()
			assert(main_scene.top_shortcut_buttons[0].tooltip_text.contains("Blancs"), "Haut retourné -> Blancs")
			assert(main_scene.bottom_shortcut_buttons[0].tooltip_text.contains("Noirs"), "Bas retourné -> Noirs")
			gc.board_flipped = false

			# Test d'adaptation responsive et sanctuarisation de la ligne du joueur
			main_scene.size = Vector2(360, 640)
			main_scene.board_column.size = Vector2(360, 400)
			main_scene._adjust_player_row_density()
			var visible_count = 0
			for b in main_scene.top_shortcut_buttons:
				if b.visible:
					visible_count += 1
			assert(visible_count <= 4, "Sur écran 360px étroit, le nombre de raccourcis doit être réduit pour éviter tout overflow")
			print("  -> Boutons visibles sur largeur 360px: %d/7 (Overflow évité ✓)" % visible_count)

			# Test sur écran plus large
			main_scene.size = Vector2(600, 800)
			main_scene.board_column.size = Vector2(600, 500)
			main_scene._adjust_player_row_density()
			var visible_wide = 0
			for b in main_scene.top_shortcut_buttons:
				if b.visible:
					visible_wide += 1
			assert(visible_wide == 7, "Sur écran large, tous les 7 raccourcis doivent être visibles")
			print("  -> Boutons visibles sur largeur 600px: %d/7 (Affichage complet ✓)" % visible_wide)

		print("  ✓ Raccourcis joueurs et adaptation de couleur validés.")
		main_scene.queue_free()
	else:
		printerr("  ❌ Main.tscn introuvable!")
		failures += 1

	print("\n=== TOUS LES TESTS SE SONT TERMINÉS AVEC SUCCÈS (%d échecs) ===" % failures)
	quit(failures)
