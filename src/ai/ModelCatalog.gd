extends Node
## ModelCatalog.gd - Gestionnaire dynamique du catalogue de modèles OpenRouter & SLM Locaux
## Permet la mise à jour en temps réel depuis le web, l'estimation des coûts, le test de clé API et la recherche par critères.

signal catalog_updated(models_count: int)
signal catalog_update_failed(error_message: String)
signal local_ollama_detected(models: Array)
signal key_test_completed(success: bool, info: Dictionary, message: String)

enum Modality {
	CLOUD_FREE,   # 100% gratuit, sans carte bancaire (OpenRouter Free)
	API_PAID,     # Clé API personnelle pay-as-you-go ultra-éco (OpenRouter BYOK)
	LOCAL_SLM     # 100% hors-ligne sur l'appareil (SmolLM2, Qwen 2.5, Llama 3.2 via Ollama/GGUF)
}

const CACHE_PATH = "user://ai_models_catalog.json"
const DEFAULT_MODEL_ID = "openrouter/free"
const DatabaseManagerClass = preload("res://src/core/DatabaseManager.gd")
const OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
const OPENROUTER_AUTH_KEY_URL = "https://openrouter.ai/api/v1/auth/key"
const OLLAMA_TAGS_URL = "http://127.0.0.1:11434/api/tags"

# Catégories de classification pour la recherche et les filtres
const CATEGORY_ALL = "all"
const CATEGORY_FREE = "free"
const CATEGORY_REASONING = "reasoning"
const CATEGORY_FAST_ECO = "fast_eco"
const CATEGORY_FRONTIER = "frontier"
const CATEGORY_LOCAL = "local"

# Consommation moyenne pour 1 analyse complète de coup/position :
# ~500 tokens d'entrée (FEN + Stockfish eval + top 3 lignes PV + question)
# ~300 tokens de sortie (explication stratégique pédagogique de 2-3 paragraphes)
const ESTIMATED_INPUT_TOKENS_PER_QUERY = 500
const ESTIMATED_OUTPUT_TOKENS_PER_QUERY = 300

const CATALOG_SCHEMA_VERSION = 20260916

var models: Array[Dictionary] = []
var http_updater: HTTPRequest
var http_ollama: HTTPRequest
var http_key_tester: HTTPRequest
var is_updating: bool = false
var is_testing_key: bool = false

func _ready() -> void:
	http_updater = HTTPRequest.new()
	add_child(http_updater)
	http_updater.request_completed.connect(_on_remote_catalog_received)

	http_ollama = HTTPRequest.new()
	add_child(http_ollama)
	http_ollama.request_completed.connect(_on_ollama_tags_received)

	http_key_tester = HTTPRequest.new()
	add_child(http_key_tester)
	http_key_tester.request_completed.connect(_on_key_test_completed)

	load_catalog()

func _get_default_model() -> Dictionary:
	return {
		"id": DEFAULT_MODEL_ID,
		"name": "OpenRouter Auto-Free",
		"provider": "openrouter",
		"modality": Modality.CLOUD_FREE,
		"description": "Routeur automatique et gratuit d'OpenRouter. Sélectionne dynamiquement le meilleur modèle gratuit disponible sans carte bancaire ni clé payante.",
		"price_in_per_1m": 0.0,
		"price_out_per_1m": 0.0,
		"pricing": {
			"prompt": "0",
			"completion": "0"
		},
		"free_tier": true,
		"context_length": 131072,
		"is_reasoning": false,
		"recommended": true
	}

## Aucun modèle pré-chargé en dur : seul le routeur gratuit initial est présent.
func _load_default_curated_models() -> void:
	models = [_get_default_model()]

## Charge le catalogue depuis le cache local ou initialise avec le seul modèle initial
func load_catalog() -> void:
	if FileAccess.file_exists(CACHE_PATH):
		var file = FileAccess.open(CACHE_PATH, FileAccess.READ)
		if file:
			var text = file.get_as_text()
			file = null
			var json = JSON.parse_string(text)
			if json is Dictionary and int(json.get("version", 0)) == CATALOG_SCHEMA_VERSION:
				var cached_models = json.get("models", [])
				if cached_models is Array and cached_models.size() > 0:
					models.clear()
					for m in cached_models:
						if m is Dictionary:
							models.append(m)
					_ensure_default_router_present()
					return
	_load_default_curated_models()
	save_catalog()

func _ensure_default_router_present() -> void:
	for m in models:
		if m.get("id", "") == DEFAULT_MODEL_ID:
			return
	models.insert(0, _get_default_model())

## Sauvegarde le catalogue dans le cache avec synchronisation système (IndexedDB sur Web)
func save_catalog() -> void:
	var file = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file:
		var payload = {
			"version": CATALOG_SCHEMA_VERSION,
			"updated_at": Time.get_datetime_string_from_system(true),
			"models": models
		}
		file.store_string(JSON.stringify(payload, "\t"))
		file.flush()
		file = null
		DatabaseManagerClass.sync_filesystem()

## Calcule le coût estimé pour 1 coup et pour 1 000 coups
func get_cost_estimate(model_dict: Dictionary) -> Dictionary:
	var pin: float = float(model_dict.get("price_in_per_1m", -1.0))
	var pout: float = float(model_dict.get("price_out_per_1m", -1.0))

	if pin < 0.0 or pout < 0.0:
		if model_dict.has("pricing"):
			var p = model_dict.get("pricing", {})
			pin = float(p.get("prompt", 0.0)) * 1000000.0
			pout = float(p.get("completion", 0.0)) * 1000000.0
		else:
			pin = 0.0
			pout = 0.0

	var m_id = str(model_dict.get("id", ""))
	if m_id == DEFAULT_MODEL_ID or m_id.ends_with(":free") or (pin <= 0.0 and pout <= 0.0):
		return {
			"per_query_usd": 0.0,
			"per_1000_usd": 0.0,
			"label_per_query": "Gratuit (0,00 €)",
			"label_per_1000": "0,00 €"
		}

	var cost_in = (ESTIMATED_INPUT_TOKENS_PER_QUERY / 1000000.0) * pin
	var cost_out = (ESTIMATED_OUTPUT_TOKENS_PER_QUERY / 1000000.0) * pout
	var total_query_usd = cost_in + cost_out
	var total_1000_usd = total_query_usd * 1000.0
	var total_query_eur = total_query_usd * 0.95
	var total_1000_eur = total_1000_usd * 0.95

	return {
		"per_query_usd": total_query_usd,
		"per_1000_usd": total_1000_usd,
		"label_per_query": "~%.4f $ (~%.4f €)" % [total_query_usd, total_query_eur],
		"label_per_1000": "~%.2f $ (~%.2f €)" % [total_1000_usd, total_1000_eur]
	}

## Effectue une requête HTTP vers l'endpoint public d'OpenRouter pour charger tous les modèles
func fetch_online_catalog() -> void:
	if is_updating:
		return
	is_updating = true
	var headers = ["User-Agent: RodChessXD/1.0"]
	var err = http_updater.request(OPENROUTER_MODELS_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_updating = false
		catalog_update_failed.emit("Impossible de contacter le serveur OpenRouter.")

func _on_remote_catalog_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_updating = false
	if response_code != 200:
		catalog_update_failed.emit("Erreur HTTP %d lors de la mise à jour OpenRouter." % response_code)
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

## Intègre les modèles récupérés depuis l'API OpenRouter (GET /api/v1/models)
func _merge_remote_models(remote_data: Array) -> void:
	var preserved_local: Array[Dictionary] = []
	for m in models:
		var prov = str(m.get("provider", ""))
		if prov == "ollama" or prov == "native_slm":
			preserved_local.append(m)

	models.clear()
	models.append(_get_default_model())

	for item in remote_data:
		if not (item is Dictionary):
			continue
		var raw_id: String = item.get("id", "").strip_edges()
		if raw_id == "" or raw_id == DEFAULT_MODEL_ID:
			continue

		var name: String = item.get("name", raw_id)
		var description: String = item.get("description", "")
		var ctx_len: int = int(item.get("context_length", 8192))
		var params: Array = item.get("supported_parameters", [])
		var arch: Dictionary = item.get("architecture", {})

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
		var lower_id = raw_id.to_lower()
		var lower_desc = description.to_lower()

		var is_reasoning = (
			lower_id.contains("reasoning") or
			lower_id.contains("r1") or
			lower_id.contains("qwq") or
			lower_id.contains("o1") or
			lower_id.contains("o3") or
			lower_id.contains("thinking") or
			"reasoning" in params or
			"include_reasoning" in params or
			lower_desc.contains("chain-of-thought") or
			lower_desc.contains("reasoning model") or
			lower_desc.contains("thinking process")
		)

		var modality = Modality.CLOUD_FREE if is_free else Modality.API_PAID

		models.append({
			"id": raw_id,
			"name": name,
			"provider": "openrouter",
			"modality": modality,
			"description": description.substr(0, 160) + ("..." if description.length() > 160 else ""),
			"price_in_per_1m": pin_raw,
			"price_out_per_1m": pout_raw,
			"free_tier": is_free,
			"is_reasoning": is_reasoning,
			"context_length": ctx_len,
			"supported_parameters": params,
			"architecture": arch,
			"recommended": is_free or is_reasoning or (lower_id.contains("flash") and pin_raw < 0.20)
		})

	# Réintégrer les modèles locaux détectés
	for local_m in preserved_local:
		var found = false
		for m in models:
			if m["id"] == local_m["id"]:
				found = true
				break
		if not found:
			models.append(local_m)

## Détecte en local les modèles installés dans Ollama (127.0.0.1:11434)
func detect_local_ollama_models() -> void:
	check_local_ollama_models()

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
					"category": CATEGORY_LOCAL,
					"is_reasoning": false,
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

## Récupère les modèles filtrés par modalité (compatibilité)
func get_models_by_modality(modality_filter: Modality) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for m in models:
		if int(m.get("modality", 0)) == int(modality_filter):
			result.append(m)
	return result

## Indique si un modèle produit des étapes de raisonnement (Reasoning / Thinking)
func is_reasoning_model(model_id: String) -> bool:
	var m = find_model_by_id(model_id)
	if not m.is_empty():
		if m.get("is_reasoning", false):
			return true
		var params = m.get("supported_parameters", [])
		if "reasoning" in params or "include_reasoning" in params:
			return true
	var low = model_id.to_lower()
	return (
		low.contains("r1") or
		low.contains("qwq") or
		low.contains("o1") or
		low.contains("o3") or
		low.contains("thinking") or
		low.contains("reasoning") or
		low.contains("reasoner") or
		low.contains("ling") or
		low.contains("thought")
	)

## Recherche et filtrage multi-critères CUMULABLES des modèles
## filters_arg peut être un String ("all", "free"...) ou un Array (["free", "reasoning"]...)
func search_models(query: String = "", filters_arg: Variant = [], sort_mode: String = "recommended") -> Array[Dictionary]:
	var active_filters: Array = []
	if filters_arg is String:
		if filters_arg != "" and filters_arg != "all":
			active_filters = [filters_arg]
	elif filters_arg is Array:
		for f in filters_arg:
			var s = str(f)
			if s != "" and s != "all" and not active_filters.has(s):
				active_filters.append(s)

	var q = query.strip_edges().to_lower()
	var filtered: Array[Dictionary] = []

	for m in models:
		# Filtres cumulables basés sur les données réelles et génériques du modèle (sans tags en dur)
		if not _matches_cumulative_filters(m, active_filters):
			continue

		# Filtre de recherche textuelle (id, name, description)
		if q != "":
			var name_match = m.get("name", "").to_lower().contains(q)
			var id_match = m.get("id", "").to_lower().contains(q)
			var desc_match = m.get("description", "").to_lower().contains(q)
			if not (name_match or id_match or desc_match):
				continue

		filtered.append(m)

	# Tri des résultats
	match sort_mode:
		"price_asc":
			filtered.sort_custom(func(a, b):
				return float(a.get("price_in_per_1m", 0.0)) < float(b.get("price_in_per_1m", 0.0))
			)
		"price_desc":
			filtered.sort_custom(func(a, b):
				return float(a.get("price_in_per_1m", 0.0)) > float(b.get("price_in_per_1m", 0.0))
			)
		"context_desc":
			filtered.sort_custom(func(a, b):
				return int(a.get("context_length", 0)) > int(b.get("context_length", 0))
			)
		_: # "recommended"
			filtered.sort_custom(func(a, b):
				var rec_a = 1 if a.get("recommended", false) else 0
				var rec_b = 1 if b.get("recommended", false) else 0
				if rec_a != rec_b:
					return rec_a > rec_b
				return a.get("name", "") < b.get("name", "")
			)

	return filtered

func _matches_cumulative_filters(m: Dictionary, active_filters: Array) -> bool:
	if active_filters.is_empty():
		return true

	var m_id = str(m.get("id", ""))
	var pin = float(m.get("price_in_per_1m", 0.0))
	var is_free = bool(m.get("free_tier", false)) or m_id.ends_with(":free") or m_id == DEFAULT_MODEL_ID or pin <= 0.0
	var is_reas = is_reasoning_model(m_id) or bool(m.get("is_reasoning", false))
	var prov = str(m.get("provider", ""))
	var is_local = (prov == "ollama" or prov == "native_slm" or int(m.get("modality", 0)) == Modality.LOCAL_SLM)

	for f in active_filters:
		match f:
			CATEGORY_FREE, "free":
				if not is_free:
					return false
			CATEGORY_REASONING, "reasoning":
				if not is_reas:
					return false
			CATEGORY_FAST_ECO, "fast_eco":
				if is_free or pin >= 1.0 or is_local:
					return false
			CATEGORY_FRONTIER, "frontier":
				var low_id = m_id.to_lower()
				var is_flagship = (
					pin >= 1.0 or
					low_id.contains("claude-3") or
					low_id.contains("gpt-4") or
					low_id.contains("o1") or
					low_id.contains("o3") or
					low_id.contains("gemini-2.0-pro") or
					low_id.contains("deepseek-r1")
				)
				if not is_flagship or is_local:
					return false
			CATEGORY_LOCAL, "local":
				if not is_local:
					return false

	return true

## Teste en direct la validité d'une clé OpenRouter via l'endpoint officiel /api/v1/auth/key
func test_openrouter_key(api_key: String) -> void:
	if is_testing_key:
		return
	var key_clean = api_key.strip_edges()
	if key_clean == "":
		key_test_completed.emit(false, {}, "Aucune clé OpenRouter saisie.")
		return

	is_testing_key = true
	if http_key_tester.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_key_tester.cancel_request()

	var headers = [
		"Authorization: Bearer " + key_clean,
		"User-Agent: RodChessXD/1.0",
		"HTTP-Referer: https://rodchessxd.app"
	]
	var err = http_key_tester.request(OPENROUTER_AUTH_KEY_URL, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_testing_key = false
		key_test_completed.emit(false, {}, "Impossible d'initialiser le test réseau vers OpenRouter.")

func _on_key_test_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_testing_key = false
	if response_code == 200:
		var text = body.get_string_from_utf8()
		var json = JSON.parse_string(text)
		if json is Dictionary and json.has("data") and json["data"] is Dictionary:
			var d: Dictionary = json["data"]
			var is_free = bool(d.get("is_free_tier", false))
			var usage = float(d.get("usage", 0.0))
			var rem = d.get("limit_remaining", null)
			var limit = d.get("limit", null)

			var msg = "Clé OpenRouter valide !"
			if is_free:
				msg += " Compte Gratuit (modèles :free disponibles sans frais)."
			elif rem != null:
				msg += " Solde disponible : $%.2f (Consommé : $%.2f)" % [float(rem), usage]
			elif limit != null:
				msg += " Limite : $%.2f (Consommé : $%.2f)" % [float(limit), usage]
			else:
				msg += " Consommation cumulée : $%.2f" % usage

			key_test_completed.emit(true, d, msg)
			return
		key_test_completed.emit(true, {}, "Clé OpenRouter valide et active !")
	elif response_code == 401:
		key_test_completed.emit(false, {}, "Clé OpenRouter invalide ou expirée (HTTP 401).")
	elif response_code == 403:
		key_test_completed.emit(false, {}, "Accès refusé pour cette clé OpenRouter (HTTP 403).")
	elif response_code == 429:
		key_test_completed.emit(false, {}, "Quota temporaire atteint sur cette clé (HTTP 429).")
	else:
		key_test_completed.emit(false, {}, "Réponse inattendue d'OpenRouter (HTTP %d)." % response_code)
