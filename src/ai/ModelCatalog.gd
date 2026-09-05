extends Node
## ModelCatalog.gd - Gestionnaire dynamique du catalogue de modèles LLM/SLM
## Permet la mise à jour légère en temps réel depuis le web, l'estimation des coûts et la détection locale.

signal catalog_updated(models_count: int)
signal catalog_update_failed(error_message: String)
signal local_ollama_detected(models: Array)

enum Modality {
	CLOUD_FREE,   # 100% gratuit, sans carte bancaire (Groq, Gemini Free, OpenRouter Free)
	API_PAID,     # Clé API personnelle pay-as-you-go ultra-éco (DeepSeek, GPT-4o-mini, Claude)
	LOCAL_SLM     # 100% hors-ligne sur l'appareil (SmolLM2, Qwen 2.5, Llama 3.2 via Ollama/GGUF)
}

const CACHE_PATH = "user://ai_models_catalog.json"
const OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
const OLLAMA_TAGS_URL = "http://127.0.0.1:11434/api/tags"

# Consommation moyenne pour 1 analyse complète de coup/position :
# ~500 tokens d'entrée (FEN + Stockfish eval + top 3 lignes PV + question)
# ~300 tokens de sortie (explication stratégique pédagogique de 2-3 paragraphes)
const ESTIMATED_INPUT_TOKENS_PER_QUERY = 500
const ESTIMATED_OUTPUT_TOKENS_PER_QUERY = 300

var models: Array[Dictionary] = []
var http_updater: HTTPRequest
var http_ollama: HTTPRequest
var is_updating: bool = false

const CATALOG_SCHEMA_VERSION = 20260905

func _ready() -> void:
	http_updater = HTTPRequest.new()
	add_child(http_updater)
	http_updater.request_completed.connect(_on_remote_catalog_received)

	http_ollama = HTTPRequest.new()
	add_child(http_ollama)
	http_ollama.request_completed.connect(_on_ollama_tags_received)

	load_catalog()

## Charge le catalogue depuis le cache local ou initialise avec les modèles de référence
func load_catalog() -> void:
	_load_default_curated_models()
	if FileAccess.file_exists(CACHE_PATH):
		var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			var json = JSON.parse_string(text)
			if json is Dictionary and int(json.get("version", 0)) == CATALOG_SCHEMA_VERSION:
				var cached_models = json.get("models", [])
				if cached_models is Array and cached_models.size() > 0:
					_merge_remote_models(cached_models)
	save_catalog()

## Modèles de référence testés et optimisés pour RodChessXD (Actualisés Septembre 2026)
func _load_default_curated_models() -> void:
	models = [
		# 1. CLOUD GRATUIT (Plug & Play - 0 € / Sans CB - Septembre 2026)
		{
			"id": "z-ai/glm-5.3-flash:free",
			"name": "GLM 5.3 Flash (Gratuit OpenRouter)",
			"provider": "openrouter",
			"modality": Modality.CLOUD_FREE,
			"description": "Natif multimodal, 18B actifs, approche Opus 4.8 sur le codage/tactique. Ultra-rapide et gratuit.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 131072,
			"recommended": true
		},
		{
			"id": "google/gemini-3.8-flash",
			"name": "Google Gemini 3.8 Flash (AI Studio Free Tier)",
			"provider": "gemini",
			"modality": Modality.CLOUD_FREE,
			"description": "Sorti le 2 sept 2026. Contexte massif 1M tokens, multimodalité texte/vision. Gratuit jusqu'à 15 req/min.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "minimax/minimax-m3:free",
			"name": "MiniMax M3 (Gratuit OpenRouter)",
			"provider": "openrouter",
			"modality": Modality.CLOUD_FREE,
			"description": "#5 des modèles les plus utilisés au monde sur OpenRouter. 1M de contexte, nativement multimodal et gratuit.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "nvidia/nemotron-3.5-lightning:free",
			"name": "NVIDIA Nemotron 3.5 Lightning (Gratuit)",
			"provider": "openrouter",
			"modality": Modality.CLOUD_FREE,
			"description": "Modèle 30B MoE (3B actifs) ultra-rapide optimisé par NVIDIA pour agents toujours actifs. Gratuit.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "openrouter/free",
			"name": "OpenRouter Auto-Free (:free)",
			"provider": "openrouter",
			"modality": Modality.CLOUD_FREE,
			"description": "Sélection automatique du meilleur modèle gratuit actif parmi les modèles du réseau OpenRouter.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 65536,
			"recommended": false
		},
		
		# 2. CLÉ API ÉCONOMIQUE & FRONTIER (BYOK - Pay-as-you-go - Septembre 2026)
		{
			"id": "deepseek/deepseek-v4-flash",
			"name": "DeepSeek V4 Flash",
			"provider": "deepseek",
			"modality": Modality.API_PAID,
			"description": "Sorti fin juil 2026. 284B total / 13B actifs MoE, 1M contexte. $0.22 in / $0.66 out / 1M. Rapport qualité/prix mondial imbattable (~0,29 € pour 1 000 coups).",
			"price_in_per_1m": 0.22,
			"price_out_per_1m": 0.66,
			"free_tier": false,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "deepseek/deepseek-v4-pro",
			"name": "DeepSeek V4 Pro (Frontier)",
			"provider": "deepseek",
			"modality": Modality.API_PAID,
			"description": "Sorti le 13 août 2026. 1.6T MoE. Égale Claude Opus 4.7 à 1/34e du prix ! Codeforces ELO 3206, LiveCodeBench 93.5 ($0.66 in / $1.98 out / 1M).",
			"price_in_per_1m": 0.66,
			"price_out_per_1m": 1.98,
			"free_tier": false,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "qwen/qwen-3.8-flash",
			"name": "Qwen 3.8 Flash (Alibaba)",
			"provider": "openrouter",
			"modality": Modality.API_PAID,
			"description": "Sorti le 24 août 2026. Poids ouverts, ultra-rapide ($0.15 in / $0.47 out / 1M). Moins de 0,20 € pour 1 000 analyses.",
			"price_in_per_1m": 0.15,
			"price_out_per_1m": 0.47,
			"free_tier": false,
			"context_length": 131072,
			"recommended": true
		},
		{
			"id": "z-ai/glm-5.3",
			"name": "GLM 5.3 Flagship (Z.ai)",
			"provider": "openrouter",
			"modality": Modality.API_PAID,
			"description": "Flagship Z.ai (18 août 2026) avec 1,31M contexte. $1.09 in / $3.43 out / 1M. Conçu pour le raisonnement approfondi.",
			"price_in_per_1m": 1.09,
			"price_out_per_1m": 3.43,
			"free_tier": false,
			"context_length": 1310000,
			"recommended": false
		},
		{
			"id": "moonshotai/kimi-k3",
			"name": "Kimi K3 (Moonshot AI)",
			"provider": "openrouter",
			"modality": Modality.API_PAID,
			"description": "Sorti le 16 juil 2026. 2.8T MoE, 1M contexte. #4 mondial de l'Artificial Analysis Index. Poids ouverts MIT ($3.00 in / $15.00 out / 1M).",
			"price_in_per_1m": 3.00,
			"price_out_per_1m": 15.00,
			"free_tier": false,
			"context_length": 1000000,
			"recommended": true
		},
		{
			"id": "anthropic/claude-fable-5.1",
			"name": "Claude Fable 5.1 (Anthropic)",
			"provider": "anthropic",
			"modality": Modality.API_PAID,
			"description": "Sorti le 3 sept 2026. N°1 mondial du Coding Agent Index (70.4). Cache read à 0.25$, 73.4% CursorBench. ($10.00 in / $50.00 out / 1M).",
			"price_in_per_1m": 10.00,
			"price_out_per_1m": 50.00,
			"free_tier": false,
			"context_length": 200000,
			"recommended": true
		},
		{
			"id": "openai/gpt-6-astra",
			"name": "GPT-6 Astra (OpenAI Frontier)",
			"provider": "openai",
			"modality": Modality.API_PAID,
			"description": "Sorti le 3 sept 2026. 1,05M contexte. 62.7% ARC-AGI-3. Efficacité de tokens 7.7x supérieure, ramenant le coût réel par tâche.",
			"price_in_per_1m": 10.00,
			"price_out_per_1m": 50.00,
			"free_tier": false,
			"context_length": 1050000,
			"recommended": false
		},

		# 3. SLM LOCAL HORS-LIGNE (Bibliothèque Ollama 2026)
		{
			"id": "ollama/glm-5.3-flash",
			"name": "GLM 5.3 Flash (Local Ollama / 18B actifs)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "Natif multimodal Z.ai avec 18B paramètres actifs. Approche Claude Opus 4.8 en local avec GPU 12-16 Go.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 65536,
			"recommended": true
		},
		{
			"id": "ollama/qwen3.8",
			"name": "Qwen 3.8 27B (Alibaba)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "Top modèle de la communauté (1,5M téléchargements). Excellente compréhension tactique et précision échiquéenne.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 32768,
			"recommended": true
		},
		{
			"id": "ollama/nemotron-3.5-lightning",
			"name": "NVIDIA Nemotron 3.5 Lightning (30B MoE)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "30B MoE avec seulement 3B actifs par token. Tourne comme un petit modèle avec l'intelligence d'un 30B.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 32768,
			"recommended": true
		},
		{
			"id": "ollama/muse-glimmer",
			"name": "Muse Glimmer 30B (Meta / Apache 2.0)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "Dernier modèle ouvert Meta sous Apache 2.0 pour agents locaux. Tourne sur un seul GPU.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 32768,
			"recommended": true
		},
		{
			"id": "ollama/laguna-xs-2.1",
			"name": "Laguna XS 2.1 (33B MoE / 3B actifs)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "Poolside 33B MoE conçu pour le raisonnement long terme et le code sur machine locale.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 16384,
			"recommended": false
		},
		{
			"id": "ollama/smollm2:1.7b",
			"name": "SmolLM2 1.7B (HuggingFace)",
			"provider": "ollama",
			"modality": Modality.LOCAL_SLM,
			"description": "Poids plume (~1 Go GGUF). Tourne à pleine vitesse sur processeur mobile ou machine sans GPU.",
			"price_in_per_1m": 0.0,
			"price_out_per_1m": 0.0,
			"free_tier": true,
			"context_length": 8192,
			"recommended": true
		}
	]

## Sauvegarde le catalogue dans le cache de l'utilisateur avec versioning de schéma
func save_catalog() -> void:
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		var payload = {
			"version": CATALOG_SCHEMA_VERSION,
			"updated_at": Time.get_datetime_string_from_system(true),
			"models": models
		}
		file.store_string(JSON.stringify(payload, "\t"))

## Calcule le coût estimé pour 1 coup et pour 1 000 coups
func get_cost_estimate(model_dict: Dictionary) -> Dictionary:
	var pin: float = float(model_dict.get("price_in_per_1m", 0.0))
	var pout: float = float(model_dict.get("price_out_per_1m", 0.0))

	if pin <= 0.0 and pout <= 0.0:
		return {
			"per_query_usd": 0.0,
			"per_1000_usd": 0.0,
			"label_per_query": "Gratuit (0,00 €)",
			"label_per_1000": "0,00 €"
		}

	# Coût en USD
	var cost_in = (ESTIMATED_INPUT_TOKENS_PER_QUERY / 1000000.0) * pin
	var cost_out = (ESTIMATED_OUTPUT_TOKENS_PER_QUERY / 1000000.0) * pout
	var total_query_usd = cost_in + cost_out
	var total_1000_usd = total_query_usd * 1000.0

	# Taux indicatif 1 USD ≈ 0.95 EUR
	var total_query_eur = total_query_usd * 0.95
	var total_1000_eur = total_1000_usd * 0.95

	return {
		"per_query_usd": total_query_usd,
		"per_1000_usd": total_1000_usd,
		"label_per_query": "~%.4f $ (~%.4f €)" % [total_query_usd, total_query_eur],
		"label_per_1000": "~%.2f $ (~%.2f €)" % [total_1000_usd, total_1000_eur]
	}

## Effectue une requête HTTP légère vers l'endpoint public d'OpenRouter pour mettre à jour les modèles et tarifs
func fetch_online_catalog() -> void:
	if is_updating:
		return
	is_updating = true
	var headers = ["User-Agent: RodChessXD/1.0"]
	var err = http_updater.request(OPENROUTER_MODELS_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_updating = false
		catalog_update_failed.emit("Impossible de contacter le serveur de catalogue.")

func _on_remote_catalog_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_updating = false
	if response_code != 200:
		catalog_update_failed.emit("Erreur HTTP %d lors de la mise à jour." % response_code)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json or not json.has("data") or not (json["data"] is Array):
		catalog_update_failed.emit("Format de catalogue distant invalide.")
		return

	var remote_list: Array = json["data"]
	_merge_remote_models(remote_list)
	save_catalog()
	var sm = _get_settings_manager()
	if sm:
		sm.set_setting("last_catalog_sync", Time.get_datetime_string_from_system(true))
	catalog_updated.emit(models.size())

func _get_settings_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

## Intègre les modèles récupérés dans notre catalogue sans écraser les configurations locales
func _merge_remote_models(remote_data: Array) -> void:
	var existing_ids = {}
	for m in models:
		existing_ids[m["id"]] = m

	var count_added = 0
	for item in remote_data:
		if not item is Dictionary:
			continue
		var raw_id: String = item.get("id", "")
		if raw_id == "":
			continue
		var name: String = item.get("name", raw_id)
		var description: String = item.get("description", "")
		var pin_raw = 0.0
		var pout_raw = 0.0
		if item.has("price_in_per_1m"):
			pin_raw = float(item.get("price_in_per_1m", 0.0))
			pout_raw = float(item.get("price_out_per_1m", 0.0))
		elif item.has("pricing"):
			var pricing = item.get("pricing", {})
			pin_raw = float(pricing.get("prompt", 0.0)) * 1000000.0
			pout_raw = float(pricing.get("completion", 0.0)) * 1000000.0
		
		var is_free = raw_id.ends_with(":free") or (pin_raw <= 0.0 and pout_raw <= 0.0) or bool(item.get("free_tier", false))

		# Filtrer les modèles particulièrement adaptés aux échecs / raisonnement
		var lower_id = raw_id.to_lower()
		var is_relevant = (
			lower_id.contains("deepseek") or
			lower_id.contains("llama") or
			lower_id.contains("qwen") or
			lower_id.contains("gemini") or
			lower_id.contains("gemma") or
			lower_id.contains("nemotron") or
			lower_id.contains("phi") or
			lower_id.contains("gpt-oss") or
			lower_id.contains("claude") or
			lower_id.contains("gpt-6") or
			lower_id.contains("fable") or
			lower_id.contains("astra") or
			lower_id.contains("muse") or
			lower_id.contains("kimi") or
			lower_id.contains("minimax") or
			lower_id.contains("laguna") or
			lower_id.contains("glm") or
			lower_id.contains("mistral") or
			is_free
		)

		if not is_relevant:
			continue

		var modality = Modality.CLOUD_FREE if is_free else Modality.API_PAID

		if existing_ids.has(raw_id):
			# Mise à jour des tarifs récents
			var existing = existing_ids[raw_id]
			existing["price_in_per_1m"] = pin_raw
			existing["price_out_per_1m"] = pout_raw
			existing["name"] = name
		else:
			# Nouveau modèle découvert
			models.append({
				"id": raw_id,
				"name": name,
				"provider": "openrouter",
				"modality": modality,
				"description": description.substr(0, 140) + ("..." if description.length() > 140 else ""),
				"price_in_per_1m": pin_raw,
				"price_out_per_1m": pout_raw,
				"free_tier": is_free,
				"context_length": item.get("context_length", 8192),
				"recommended": false
			})
			count_added += 1

## Détecte en local les modèles installés dans Ollama (127.0.0.1:11434)
func check_local_ollama_models() -> void:
	var err = http_ollama.request(OLLAMA_TAGS_URL, ["User-Agent: RodChessXD/1.0"], HTTPClient.METHOD_GET)
	if err != OK:
		local_ollama_detected.emit([])

func _on_ollama_tags_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		local_ollama_detected.emit([])
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json or not json.has("models") or not (json["models"] is Array):
		local_ollama_detected.emit([])
		return

	var detected = []
	for m in json["models"]:
		if m is Dictionary and m.has("name"):
			var model_name = m["name"]
			detected.append(model_name)
			
			# Ajouter au catalogue s'il n'y est pas encore
			var full_id = "ollama/" + model_name
			var found = false
			for existing in models:
				if existing["id"] == full_id:
					found = true
					break
			if not found:
				models.append({
					"id": full_id,
					"name": model_name + " (Local Ollama)",
					"provider": "ollama",
					"modality": Modality.LOCAL_SLM,
					"description": "Modèle local détecté sur votre machine. 100% hors-ligne.",
					"price_in_per_1m": 0.0,
					"price_out_per_1m": 0.0,
					"free_tier": true,
					"context_length": 8192,
					"recommended": true
				})
	
	save_catalog()
	local_ollama_detected.emit(detected)

## Trouve un modèle par son ID
func find_model_by_id(model_id: String) -> Dictionary:
	for m in models:
		if m["id"] == model_id:
			return m
	return {}

## Récupère les modèles filtrés par modalité
func get_models_by_modality(modality_filter: Modality) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m in models:
		if int(m.get("modality", 0)) == int(modality_filter):
			result.append(m)
	return result
