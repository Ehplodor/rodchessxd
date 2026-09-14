extends SceneTree
## test_openrouter_coach_integration.gd
## Validation complète de l'intégration BYOK OpenRouter, du catalogue,
## de l'extraction de raisonnement, de la concision des prompts et de l'UI.

var _ran := false

func _init() -> void:
	print("\n=== [TEST] Démarrage du test d'intégration OpenRouter Coach IA ===")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()
	quit(0)
	return true

func _run_tests() -> void:
	# 1. Validation de SettingsManager (Rationalisation ai_provider & api_key_openrouter)
	print("-> Test 1 : SettingsManager & Rationalisation OpenRouter...")
	var sm_script = load("res://src/core/SettingsManager.gd")
	assert(sm_script != null, "SettingsManager introuvable")
	var sm = sm_script.new()
	assert(sm.get_setting("ai_provider", "openrouter") in ["openrouter", "local_slm"], "ai_provider doit être openrouter ou local_slm")
	sm.set_setting("api_key_openrouter", "sk-or-v1-test-key-123456789")
	assert(sm.get_setting("api_key_openrouter", "") == "sk-or-v1-test-key-123456789", "Sauvegarde de la clé OpenRouter échouée")
	print("   ✓ SettingsManager rationalisé avec succès.")

	# 2. Validation de ModelCatalog (Modèle Unique Initial, Mise à jour API & Modèles de Raisonnement)
	print("-> Test 2 : ModelCatalog & Modèles de Raisonnement...")
	var mc_script = load("res://src/ai/ModelCatalog.gd")
	assert(mc_script != null, "ModelCatalog introuvable")
	var mc = mc_script.new()
	mc.load_catalog()
	assert(mc.has_signal("key_test_completed"), "ModelCatalog doit avoir key_test_completed")
	assert(mc.has_method("test_openrouter_key"), "ModelCatalog doit avoir test_openrouter_key")
	assert(mc.has_method("search_models"), "ModelCatalog doit avoir search_models")
	assert(mc.has_method("is_reasoning_model"), "ModelCatalog doit avoir is_reasoning_model")

	# Vérification du modèle initial
	assert(mc.models.size() >= 1, "Le catalogue doit comporter au moins le routeur initial")
	assert(mc.models[0].get("id", "") == "openrouter/free", "Le premier modèle doit être openrouter/free")

	# Simulation de mise à jour dynamique de modèles depuis l'API OpenRouter
	mc._merge_remote_models([
		{
			"id": "deepseek/deepseek-r1",
			"name": "DeepSeek R1",
			"pricing": {"prompt": "0.00000055", "completion": "0.00000219"},
			"context_length": 65536,
			"supported_parameters": ["include_reasoning"]
		},
		{
			"id": "google/gemini-2.5-flash",
			"name": "Gemini 2.5 Flash",
			"pricing": {"prompt": "0.00000015", "completion": "0.00000060"},
			"context_length": 1048576
		}
	])

	# Test des catégories
	var free_models = mc.search_models("", "free")
	assert(free_models.size() > 0, "Doit trouver des modèles gratuits")
	for m in free_models:
		assert(m.get("free_tier", false) == true or m.get("id", "").ends_with(":free") or m.get("id", "") == "openrouter/free", "Modèle filtré doit être gratuit")

	var reasoning_models = mc.search_models("", "reasoning")
	assert(reasoning_models.size() > 0, "Doit trouver des modèles de raisonnement")
	assert(mc.is_reasoning_model("deepseek/deepseek-r1"), "deepseek-r1 doit être un modèle de raisonnement")
	assert(mc.is_reasoning_model("anthropic/claude-3.7-sonnet:thinking"), "claude-3.7-sonnet:thinking doit être un modèle de raisonnement")
	assert(mc.is_reasoning_model("openai/o3-mini"), "o3-mini doit être un modèle de raisonnement")
	assert(not mc.is_reasoning_model("openai/gpt-4o-mini"), "gpt-4o-mini ne doit pas être un modèle de raisonnement")

	# Test de recherche textuelle
	var search_res = mc.search_models("deepseek", "all")
	assert(search_res.size() > 0, "Doit trouver des modèles avec 'deepseek'")
	for m in search_res:
		var txt = (m.get("id", "") + " " + m.get("name", "")).to_lower()
		assert(txt.contains("deepseek"), "Résultat de recherche doit contenir 'deepseek'")
	print("   ✓ ModelCatalog (catégories, recherche, raisonnement) validé.")

	# 3. Validation de AICoach (Extraction de Raisonnement & Concision des Prompts)
	print("-> Test 3 : AICoach (Extraction de Raisonnement & Prompts Concis)...")
	var ac_script = load("res://src/ai/AICoach.gd")
	assert(ac_script != null, "AICoach introuvable")
	var ac = ac_script.new()
	assert(ac.has_signal("coach_response_detailed"), "AICoach doit émettre coach_response_detailed")

	# Test extraction depuis <think>...</think>
	var think_content = "<think>\nCalculons 1. e4 e5 2. Nf3 Nc6.\nLa position est équilibrée.\n</think>\n🎯 Diagnostic : Égalité complète.\n💡 Levier tactique : Cavalier actif.\n📌 Plan conseillé : Pousser d4."
	var split_res = ac.extract_reasoning_from_text(think_content)
	assert(split_res.reasoning.contains("Calculons 1. e4 e5"), "Raisonnement dans <think> doit être extrait")
	assert(not split_res.content.contains("<think>"), "Le contenu final ne doit pas contenir la balise <think>")
	assert(split_res.content.begins_with("🎯 Diagnostic"), "Le contenu final doit commencer directement par le diagnostic")

	# Test prompt concis (règles des 100-150 mots et rubriques cibles)
	var prompt_data = ac.build_prompt_data(
		"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
		"e4",
		25,
		"e7e5",
		["e7e5", "g1f3", "b8c6"],
		"Pourquoi ce coup ?",
		{
			"perspective": "white",
			"last_move_natural": "Pion avance de e2 en e4",
			"opening_name": "Partie du Pion Roi (1. e4)"
		}
	)
	var sys_p = prompt_data.get("system", "")
	var usr_p = prompt_data.get("user", "")
	assert(sys_p.contains("100 à 150 mots"), "System prompt doit imposer 100 à 150 mots max")
	assert(sys_p.contains("🎯") and sys_p.contains("Diagnostic"), "System prompt doit imposer la structure Diagnostic")
	assert(sys_p.contains("💡") and sys_p.contains("Analyse"), "System prompt doit imposer la structure Analyse")
	assert(sys_p.contains("📌") and sys_p.contains("Plan conseillé"), "System prompt doit imposer la structure Plan conseillé")
	assert(usr_p.contains("Partie du Pion Roi"), "User prompt doit inclure le nom de l'ouverture étendu")
	assert(usr_p.contains("Dynamique récente"), "User prompt doit inclure le contexte dynamique de l'évaluation")
	print("   ✓ AICoach (extraction de réflexion et prompts concis) validé.")

	# 4. Validation des Composants UI (CoachReadingModal, ModelHubModal, CoachPanel2D, SettingsModal)
	print("-> Test 4 : Composants UI & Accès Clé OpenRouter...")
	var read_modal_script = load("res://src/ui/components/CoachReadingModal.gd")
	assert(read_modal_script != null, "CoachReadingModal introuvable")

	# Test CoachReadingModal avec réflexion interne
	var note_with_reasoning = {
		"move_san": "Nf3",
		"user_question": "Pourquoi ce coup ?",
		"response_text": "🎯 Diagnostic : Excellent coup.\n💡 Levier tactique : Contrôle du centre.\n📌 Plan conseillé : Rocade rapide.",
		"reasoning_text": "Étape 1 : Analyser Nf3.\nÉtape 2 : Valider d4 et e5.\nÉtape 3 : Synthétiser pour le joueur.",
		"model_id": "deepseek/deepseek-r1",
		"cost_label": "~0.0003 $"
	}
	var reading_modal = read_modal_script.new(note_with_reasoning)
	assert(reading_modal != null, "CoachReadingModal doit s'instancier avec reasoning_text")
	reading_modal.free()

	# Test CoachReadingModal en mode erreur
	var err_modal = read_modal_script.new({}, true, "Erreur 401: Clé API invalide")
	assert(err_modal != null, "CoachReadingModal doit s'instancier en mode erreur")
	err_modal.free()

	# Test ModelHubModal
	var hub_script = load("res://src/ui/components/ModelHubModal.gd")
	assert(hub_script != null, "ModelHubModal introuvable")
	var hub = hub_script.new()
	assert(hub != null, "ModelHubModal doit s'instancier")
	hub.free()

	# Test CoachPanel2D
	var coach_panel_script = load("res://src/ui/components/CoachPanel2D.gd")
	assert(coach_panel_script != null, "CoachPanel2D introuvable")
	var coach_panel = coach_panel_script.new()
	assert(coach_panel != null, "CoachPanel2D doit s'instancier")
	coach_panel.free()

	# Test SettingsModal
	var settings_modal_script = load("res://src/ui/components/SettingsModal.gd")
	assert(settings_modal_script != null, "SettingsModal introuvable")
	var settings_modal = settings_modal_script.new()
	assert(settings_modal != null, "SettingsModal doit s'instancier")
	settings_modal.free()

	print("   ✓ Composants UI validés avec succès.")
	print("\n🎉 TOUS LES TESTS D'INTÉGRATION OPENROUTER DU COACH IA SONT VALIDÉS AVEC SUCCÈS (100%) ! 🎉\n")
