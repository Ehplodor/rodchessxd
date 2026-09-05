extends SceneTree
## test_model_catalog.gd - Test unitaire du catalogue de modèles et du calculateur de coûts

const ModelCatalogScript = preload("res://src/ai/ModelCatalog.gd")
const ModelHubModalScript = preload("res://src/ui/components/ModelHubModal.gd")

func _init() -> void:
	print("--- Running ModelCatalog & Cost Estimation Unit Tests ---")
	await create_timer(0.2).timeout
	
	var catalog = ModelCatalogScript.new()
	root.add_child(catalog)
	catalog.load_catalog()

	print("Total models loaded in catalog: %d" % catalog.models.size())
	assert(catalog.models.size() >= 8, "Le catalogue doit comporter au moins 8 modèles de référence")

	# 1. Vérification des modèles par modalité
	var free_models = catalog.get_models_by_modality(ModelCatalogScript.Modality.CLOUD_FREE)
	var paid_models = catalog.get_models_by_modality(ModelCatalogScript.Modality.API_PAID)
	var local_models = catalog.get_models_by_modality(ModelCatalogScript.Modality.LOCAL_SLM)

	print("Cloud Gratuit (Plug & Play) : %d modèles" % free_models.size())
	print("Clé API Économique (BYOK)  : %d modèles" % paid_models.size())
	print("SLM Local (Hors-ligne)     : %d modèles" % local_models.size())

	assert(free_models.size() >= 2, "Doit comporter au moins 2 modèles gratuits (Groq, Gemini)")
	assert(paid_models.size() >= 3, "Doit comporter au moins 3 modèles payants (DeepSeek, GPT, Claude)")
	assert(local_models.size() >= 2, "Doit comporter au moins 2 modèles locaux (SmolLM2, Qwen)")

	# 2. Test du calcul de coût de revient
	var glm_free = catalog.find_model_by_id("z-ai/glm-5.3-flash:free")
	assert(not glm_free.is_empty(), "GLM 5.3 Flash gratuit doit être présent dans le catalogue")
	var glm_cost = catalog.get_cost_estimate(glm_free)
	print("\nGLM 5.3 Flash (Gratuit OpenRouter) Cost:")
	print(" - Par coup: %s" % glm_cost.label_per_query)
	print(" - Pour 1000 coups: %s" % glm_cost.label_per_1000)
	assert(glm_cost.per_query_usd == 0.0, "Le modèle gratuit doit avoir un coût de 0 USD")

	var gemini_38 = catalog.find_model_by_id("google/gemini-3.8-flash")
	assert(not gemini_38.is_empty(), "Gemini 3.8 Flash doit être présent")
	var gem_cost = catalog.get_cost_estimate(gemini_38)
	print("\nGemini 3.8 Flash Cost:")
	assert(gem_cost.per_query_usd >= 0.0, "Gemini 3.8 Flash a un coût estimé valide")

	var ds_v4_flash = catalog.find_model_by_id("deepseek/deepseek-v4-flash")
	assert(not ds_v4_flash.is_empty(), "DeepSeek V4 Flash doit être présent")
	var ds_flash_cost = catalog.get_cost_estimate(ds_v4_flash)
	print("\nDeepSeek V4 Flash Cost:")
	print(" - Par coup: %s (USD: %.6f)" % [ds_flash_cost.label_per_query, ds_flash_cost.per_query_usd])
	# 500 in ($0.22/1M) + 300 out ($0.66/1M) => ~0.000308$ (~0,29 $ / 1000 coups)
	assert(ds_flash_cost.per_query_usd > 0.0002 and ds_flash_cost.per_query_usd < 0.0005, "Coût DeepSeek V4 Flash attendu ~0.000308 $")

	var ds_v4_pro = catalog.find_model_by_id("deepseek/deepseek-v4-pro")
	assert(not ds_v4_pro.is_empty(), "DeepSeek V4 Pro doit être présent")
	var ds_pro_cost = catalog.get_cost_estimate(ds_v4_pro)
	print("\nDeepSeek V4 Pro Cost:")
	print(" - Par coup: %s (USD: %.6f)" % [ds_pro_cost.label_per_query, ds_pro_cost.per_query_usd])
	print(" - Pour 1000 coups: %s (USD: %.4f)" % [ds_pro_cost.label_per_1000, ds_pro_cost.per_1000_usd])
	assert(ds_pro_cost.per_query_usd > 0.0007 and ds_pro_cost.per_query_usd < 0.0012, "Coût DeepSeek V4 Pro attendu ~0.000968 $")

	var gpt6_astra = catalog.find_model_by_id("openai/gpt-6-astra")
	assert(not gpt6_astra.is_empty(), "GPT-6 Astra doit être présent")
	var astra_cost = catalog.get_cost_estimate(gpt6_astra)
	print("\nGPT-6 Astra Cost:")
	print(" - Par coup: %s (USD: %.6f)" % [astra_cost.label_per_query, astra_cost.per_query_usd])
	print(" - Pour 1000 coups: %s" % astra_cost.label_per_1000)
	# 500 in ($10.00/1M) = 0.005$ + 300 out ($50.00/1M) = 0.015$ => 0.020$ (2 c€)
	assert(abs(astra_cost.per_query_usd - 0.020) < 0.0001, "Coût GPT-6 Astra attendu 0.020 $ par coup")

	# Vérification des modèles natifs autonomes embarqués
	var smollm_native = catalog.find_model_by_id("native_slm/smollm2-360m")
	assert(not smollm_native.is_empty() and smollm_native.get("provider") == "native_slm", "SmolLM2 360M natif doit être présent")
	var qwen_native = catalog.find_model_by_id("native_slm/qwen2.5-0.5b")
	assert(not qwen_native.is_empty() and qwen_native.get("provider") == "native_slm", "Qwen 2.5 0.5B natif doit être présent")
	print("\nModèles SLM natifs autonomes vérifiés : %s, %s" % [smollm_native.name, qwen_native.name])

	var qwen38_local = catalog.find_model_by_id("ollama/qwen3.8")
	assert(not qwen38_local.is_empty() and qwen38_local.get("provider") == "ollama", "Qwen 3.8 doit être présent dans les modèles locaux")

	var glm_local = catalog.find_model_by_id("ollama/glm-5.3-flash")
	assert(not glm_local.is_empty() and glm_local.get("provider") == "ollama", "GLM 5.3 Flash local doit être présent dans les modèles locaux")

	# 3. Test de fusion de modèles distants (Simulation mise à jour légère)
	print("\nSimulation de mise à jour distante (Merge OpenRouter payload)...")
	var mock_remote = [
		{
			"id": "deepseek/deepseek-v4-turbo",
			"name": "DeepSeek V4 Turbo (Nouveau)",
			"description": "Nouveau modèle ultra rapide détecté lors de la mise à jour.",
			"pricing": {
				"prompt": "0.00000015", # $0.15 / 1M
				"completion": "0.00000045" # $0.45 / 1M
			},
			"context_length": 65536
		}
	]
	var initial_count = catalog.models.size()
	catalog._merge_remote_models(mock_remote)
	assert(catalog.models.size() == initial_count + 1, "Le nouveau modèle distant doit être ajouté au catalogue")
	
	var added_model = catalog.find_model_by_id("deepseek/deepseek-v4-turbo")
	assert(added_model.name == "DeepSeek V4 Turbo (Nouveau)", "Le nom du nouveau modèle doit correspondre")
	print("Nouveau modèle ajouté avec succès : %s" % added_model.name)

	# 4. Test d'instanciation de ModelHubModal et détection Ollama
	print("\nTest de la détection Ollama locale et de l'interface ModelHubModal...")
	assert(catalog.has_method("detect_local_ollama_models"), "ModelCatalog doit implémenter detect_local_ollama_models")
	assert(catalog.has_method("check_local_ollama_models"), "ModelCatalog doit implémenter check_local_ollama_models")
	catalog.detect_local_ollama_models()
	print("Méthode detect_local_ollama_models appelée avec succès !")

	var hub = ModelHubModalScript.new()
	root.add_child(hub)
	print("ModelHubModal instanciée sans erreur !")
	hub.queue_free()

	print("\n>>> TOUS LES TESTS MODELCATALOG ONT RÉUSSI AVEC SUCCÈS ! <<<")
	quit(0)
