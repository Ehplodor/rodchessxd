extends SceneTree
## test_model_catalog.gd - Test unitaire : Modèle unique initial, mise à jour API, persistance & filtres cumulables

const ModelCatalogScript = preload("res://src/ai/ModelCatalog.gd")
const ModelHubModalScript = preload("res://src/ui/components/ModelHubModal.gd")

func _init() -> void:
	print("=== Running ModelCatalog & Cumulative Filters Tests ===")
	await create_timer(0.1).timeout

	# Nettoyage initial du cache pour tester les conditions réelles du 1er lancement
	var user_dir = DirAccess.open("user://")
	if user_dir and user_dir.file_exists("ai_models_catalog.json"):
		user_dir.remove("ai_models_catalog.json")

	print("\n[Test 1] Vérification de l'état initial (Zéro pré-chargement)...")
	var catalog = ModelCatalogScript.new()
	root.add_child(catalog)
	catalog.load_catalog()

	print("Modèles au premier lancement: %d" % catalog.models.size())
	assert(catalog.models.size() == 1, "Au premier lancement, EXACTEMENT un seul modèle doit être configuré")
	
	var initial_model = catalog.models[0]
	assert(initial_model.get("id", "") == "openrouter/free", "Le seul modèle initial doit être 'openrouter/free'")
	assert(initial_model.get("price_in_per_1m", -1.0) == 0.0, "Le modèle initial doit être gratuit")
	assert(initial_model.get("recommended", false) == true, "Le modèle initial doit être marqué recommandé")

	var cost_info = catalog.get_cost_estimate(initial_model)
	assert(cost_info.per_query_usd == 0.0, "Le coût calculé doit être 0 USD")
	assert(cost_info.label_per_query == "Gratuit (0,00 €)", "Le libellé doit indiquer la gratuité")
	print("✓ Modèle unique initial vérifié avec succès : %s (%s)" % [initial_model.name, cost_info.label_per_query])

	# -------------------------------------------------------------
	# 2. TEST MISE À JOUR DYNAMIQUE VIA API PUBLIQUE OPENROUTER
	# -------------------------------------------------------------
	print("\n[Test 2] Simulation de mise à jour depuis l'API publique OpenRouter...")
	var mock_api_response = [
		{
			"id": "deepseek/deepseek-r1",
			"name": "DeepSeek R1",
			"description": "Modèle de raisonnement de pointe libre et open weights.",
			"pricing": {
				"prompt": "0.00000055", # $0.55 / 1M
				"completion": "0.00000219" # $2.19 / 1M
			},
			"context_length": 65536,
			"supported_parameters": ["include_reasoning", "max_tokens"]
		},
		{
			"id": "google/gemini-2.5-flash",
			"name": "Gemini 2.5 Flash",
			"description": "Modèle multimodal ultra-rapide et économique.",
			"pricing": {
				"prompt": "0.00000015", # $0.15 / 1M
				"completion": "0.00000060" # $0.60 / 1M
			},
			"context_length": 1048576,
			"supported_parameters": ["temperature"]
		},
		{
			"id": "meta-llama/llama-3.3-70b-instruct:free",
			"name": "Llama 3.3 70B Instruct (Free)",
			"description": "Modèle Llama gratuit fourni par OpenRouter.",
			"pricing": {
				"prompt": "0",
				"completion": "0"
			},
			"context_length": 131072,
			"supported_parameters": ["temperature"]
		},
		{
			"id": "anthropic/claude-3.7-sonnet",
			"name": "Claude 3.7 Sonnet (Hybrid)",
			"description": "Modèle frontière avec pensée hybride approfondie.",
			"pricing": {
				"prompt": "0.00000300", # $3.00 / 1M
				"completion": "0.00001500" # $15.00 / 1M
			},
			"context_length": 200000,
			"supported_parameters": ["reasoning", "thinking"]
		},
		{
			"id": "openai/gpt-4.5-preview",
			"name": "GPT-4.5 Preview",
			"description": "Grand modèle frontière OpenAI pour tâches complexes.",
			"pricing": {
				"prompt": "0.00007500", # $75.00 / 1M
				"completion": "0.00015000" # $150.00 / 1M
			},
			"context_length": 128000
		},
		{
			"id": "deepseek/deepseek-r1:free",
			"name": "DeepSeek R1 (Free)",
			"description": "Raisonnement gratuit offert par la communauté.",
			"pricing": {
				"prompt": "0",
				"completion": "0"
			},
			"context_length": 65536,
			"supported_parameters": ["include_reasoning"]
		}
	]

	catalog._merge_remote_models(mock_api_response)
	print("Modèles après mise à jour: %d" % catalog.models.size())
	assert(catalog.models.size() == 7, "Le catalogue doit maintenant contenir 7 modèles (1 routeur + 6 distants)")

	# Vérifier que le routeur par défaut est resté en tête
	assert(catalog.models[0].id == "openrouter/free", "Le routeur gratuit doit rester préservé en tête de liste")

	# Vérification des caractéristiques extraites
	var r1 = catalog.find_model_by_id("deepseek/deepseek-r1")
	assert(not r1.is_empty(), "DeepSeek R1 doit être présent")
	assert(r1.get("is_reasoning", false) == true, "DeepSeek R1 doit être identifié comme modèle de raisonnement")
	assert(abs(float(r1.get("price_in_per_1m", 0.0)) - 0.55) < 0.01, "Prix prompt par million doit être ~0.55$")
	assert(abs(float(r1.get("price_out_per_1m", 0.0)) - 2.19) < 0.01, "Prix completion par million doit être ~2.19$")

	var gemini = catalog.find_model_by_id("google/gemini-2.5-flash")
	var gem_cost = catalog.get_cost_estimate(gemini)
	assert(gem_cost.per_query_usd > 0.0001 and gem_cost.per_query_usd < 0.0005, "Coût Gemini Flash calculé correctement")
	print("✓ Caractéristiques et calculs de coûts dynamiques vérifiés")

	# -------------------------------------------------------------
	# 3. TEST PERSISTANCE LOCALE & MULTIPLATEFORME
	# -------------------------------------------------------------
	print("\n[Test 3] Sauvegarde et rechargement local du catalogue...")
	catalog.save_catalog()

	var catalog2 = ModelCatalogScript.new()
	root.add_child(catalog2)
	catalog2.load_catalog()
	assert(catalog2.models.size() == 7, "Le rechargement depuis le cache local doit restaurer les 7 modèles")
	catalog2.queue_free()
	print("✓ Persistance locale validée")

	# -------------------------------------------------------------
	# 4. TEST DES FILTRES CUMULABLES (MULTI-CRITÈRES SANS TAGS EN DUR)
	# -------------------------------------------------------------
	print("\n[Test 4] Validation des filtres cumulables...")
	
	# Filtre simple 1 : Gratuit
	var res_free = catalog.search_models("", ["free"])
	print(" - Filtre [free]: %d modèles" % res_free.size())
	# Attendu : openrouter/free, llama-3.3-70b-instruct:free, deepseek-r1:free (3)
	assert(res_free.size() == 3, "Il doit y avoir 3 modèles gratuits")

	# Filtre simple 2 : Raisonnement
	var res_reasoning = catalog.search_models("", ["reasoning"])
	print(" - Filtre [reasoning]: %d modèles" % res_reasoning.size())
	# Attendu : deepseek-r1, claude-3.7-sonnet, deepseek-r1:free (3)
	assert(res_reasoning.size() == 3, "Il doit y avoir 3 modèles avec raisonnement")

	# Filtre CUMULATIF : [Gratuit] + [Raisonnement] (ET logique)
	var res_free_and_reasoning = catalog.search_models("", ["free", "reasoning"])
	print(" - Filtre CUMULÉ [free + reasoning]: %d modèles" % res_free_and_reasoning.size())
	# Attendu : deepseek/deepseek-r1:free uniquement (1)
	assert(res_free_and_reasoning.size() == 1, "Seul deepseek-r1:free est à la fois gratuit ET de raisonnement")
	assert(res_free_and_reasoning[0].id == "deepseek/deepseek-r1:free", "Le modèle retourné doit être deepseek-r1:free")

	# Filtre CUMULATIF : [Frontier] + [Raisonnement]
	var res_frontier_reasoning = catalog.search_models("", ["frontier", "reasoning"])
	print(" - Filtre CUMULÉ [frontier + reasoning]: %d modèles" % res_frontier_reasoning.size())
	assert(res_frontier_reasoning.size() == 3, "Il y a 3 modèles à la fois frontière et raisonnement (DeepSeek R1, Claude 3.7, DeepSeek R1 Free)")

	# Filtre CUMULATIF : [Frontier] + [Gratuit]
	var res_frontier_free = catalog.search_models("", ["frontier", "free"])
	print(" - Filtre CUMULÉ [frontier + free]: %d modèles" % res_frontier_free.size())
	assert(res_frontier_free.size() == 1 and res_frontier_free[0].id == "deepseek/deepseek-r1:free",
			"DeepSeek R1 (Free) doit être le seul modèle à la fois frontière et gratuit")

	# Recherche textuelle combinée aux filtres cumulés
	var res_search_filter = catalog.search_models("llama", ["free"])
	print(" - Recherche 'llama' + Filtre [free]: %d modèle" % res_search_filter.size())
	assert(res_search_filter.size() == 1 and res_search_filter[0].id == "meta-llama/llama-3.3-70b-instruct:free")

	print("✓ Filtres cumulables opérationnels sans faille")

	# -------------------------------------------------------------
	# 5. TEST DE L'INTERFACE MODELHUBMODAL (Boutons de filtres cumulables)
	# -------------------------------------------------------------
	print("\n[Test 5] Test du comportement UI ModelHubModal...")
	var hub = ModelHubModalScript.new()
	root.add_child(hub)

	assert(hub.active_filters.is_empty(), "Au départ, aucun filtre n'est activé (mode Tous)")
	
	hub._toggle_filter("free")
	assert(hub.active_filters == ["free"], "Le filtre 'free' doit être présent")

	hub._toggle_filter("reasoning")
	assert(hub.active_filters.has("free") and hub.active_filters.has("reasoning"),
			"Les filtres 'free' et 'reasoning' doivent être cumulés")

	hub._toggle_filter("free")
	assert(not hub.active_filters.has("free") and hub.active_filters.has("reasoning"),
			"Désactiver 'free' ne doit laisser que 'reasoning'")

	hub._toggle_filter("all")
	assert(hub.active_filters.is_empty(), "Cliquer sur 'Tous' doit vider les filtres")

	hub.queue_free()
	catalog.queue_free()

	print("\n>>> TOUS LES TESTS MODELCATALOG & FILTRES CUMULABLES ONT RÉUSSI ! <<<")
	quit(0)
