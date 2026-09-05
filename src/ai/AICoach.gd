extends Node
## AICoach.gd - Service d'explication pédagogique en langage naturel
## Intégré avec ModelCatalog pour supporter tous les modèles actuels (Gratuits, API, SLM Locaux)

signal coach_thinking_started
signal coach_response_received(response: String)
signal coach_response_with_meta(response: String, cost_label: String, elapsed_sec: float)
signal coach_error(error_msg: String)

var http_client: HTTPRequest
var current_query_start_time: float = 0.0
var active_query_model_id: String = ""

# Métriques de session
var session_queries_count: int = 0
var session_estimated_cost_usd: float = 0.0

func _ready() -> void:
	http_client = HTTPRequest.new()
	add_child(http_client)
	http_client.request_completed.connect(_on_request_completed)

## Construit le prompt structuré avec toutes les données objectives du moteur pour éliminer les hallucinations
func build_chess_prompt(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = ""
) -> String:
	var active_color_str = "Blancs"
	var parts = fen.split(" ")
	if parts.size() > 1 and parts[1] == "b":
		active_color_str = "Noirs"

	var eval_str = ("+%.2f" if eval_cp >= 0 else "%.2f") % (eval_cp / 100.0)
	var pv_str = " ".join(pv_line.slice(0, 5))
	var personality = SettingsManager.get_setting("coach_personality", "mentor")

	var system_instructions = """Tu es un Grand Maître International d'échecs et un entraîneur pédagogique d'élite.
Ton rôle est d'analyser la position d'échecs fournie et d'expliquer au joueur les concepts stratégiques et tactiques de manière claire, motivante et intelligible.
RÈGLES IMPORTANTES :
1. Ne calcule pas de coups toi-même au hasard : appuie-toi STRICTEMENT sur les données d'évaluation du moteur Stockfish fournies ci-dessous.
2. Explique le POURQUOI des coups : sécurité du roi, contrôle du centre, activité des pièces, structures de pions, menaces directes.
3. Reste concis (2 à 4 paragraphes percutants). Utilise des puces si nécessaire."""

	match personality:
		"blunder_hunter":
			system_instructions += "\nAdopte un ton direct centré sur la détection impitoyable des gaffes et des tactiques manquées."
		"kids_simple":
			system_instructions += "\nExplique avec des métaphores simples et ludiques accessibles à un enfant ou un débutant complet."
		_:
			system_instructions += "\nAdopte un ton de mentor bienveillant et instructif."

	var user_content = """Voici les données de la position :
- Position FEN : %s
- Trait au joueur : %s
- Dernier coup joué : %s
- Évaluation Stockfish : %s (en pions)
- Meilleur coup recommandé par Stockfish : %s
- Variante calculée (PV) : %s
""" % [fen, active_color_str, last_move_san if last_move_san != "" else "Position initiale", eval_str, best_move, pv_str]

	if user_question != "":
		user_content += "\nQuestion spécifique du joueur : " + user_question
	else:
		user_content += "\nMission du coach : Analyse la situation, explique pourquoi le meilleur coup est supérieur et quel est le plan stratégique conseillé."

	return system_instructions + "\n\n" + user_content

## Envoi de la demande au modèle actuellement sélectionné
func ask_coach(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = ""
) -> void:
	var prompt = build_chess_prompt(fen, last_move_san, eval_cp, best_move, pv_line, user_question)
	current_query_start_time = Time.get_ticks_msec() / 1000.0
	coach_thinking_started.emit()

	var active_model_id = SettingsManager.get_setting("active_model_id", "groq/llama-3.3-70b-versatile")
	active_query_model_id = active_model_id

	var model_info = ModelCatalog.find_model_by_id(active_model_id)
	var provider = model_info.get("provider", "groq")

	match provider:
		"ollama":
			_request_local_ollama(prompt, model_info)
		"groq":
			_request_groq(prompt, model_info)
		"gemini":
			_request_gemini(prompt, model_info)
		"openrouter":
			_request_openrouter(prompt, model_info)
		"deepseek":
			_request_deepseek(prompt, model_info)
		"openai":
			_request_openai(prompt, model_info)
		"anthropic":
			_request_anthropic(prompt, model_info)
		_:
			# Fallback automatique
			_request_groq(prompt, model_info)

# --- REQUÊTES VERS LES DIFFÉRENTS FOURNISSEURS ---

func _request_local_ollama(prompt: String, model_info: Dictionary) -> void:
	var raw_id = model_info.get("id", "ollama/smollm2:1.7b")
	var model_name = raw_id.replace("ollama/", "")
	var base_url = SettingsManager.get_setting("local_slm_url", "http://127.0.0.1:11434/api/generate")
	
	var body = JSON.stringify({
		"model": model_name,
		"prompt": prompt,
		"stream": false
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(base_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Impossible de contacter Ollama en local (%s). Vérifiez qu'Ollama est bien démarré." % base_url)

func _request_groq(prompt: String, model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_groq", "")
	if key == "":
		_fallback_offline_explanation("Groq")
		return

	var raw_id = model_info.get("id", "llama-3.3-70b-versatile").replace("groq/", "")
	var url = "https://api.groq.com/openai/v1/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": "Tu es un Grand Maître d'échecs pédagogue et analytique."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à Groq Cloud.")

func _request_gemini(prompt: String, _model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_gemini", "")
	if key == "":
		_fallback_offline_explanation("Google Gemini")
		return

	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + key
	var body = JSON.stringify({
		"contents": [{
			"parts": [{"text": prompt}]
		}]
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à Google Gemini.")

func _request_openrouter(prompt: String, model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_openrouter", "")
	var model_id = model_info.get("id", "meta-llama/llama-3.3-70b-instruct:free")
	
	var url = "https://openrouter.ai/api/v1/chat/completions"
	var body = JSON.stringify({
		"model": model_id,
		"messages": [
			{"role": "system", "content": "Tu es un Grand Maître d'échecs pédagogue."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"HTTP-Referer: https://rodchessxd.app",
		"X-Title: RodChessXD"
	]
	if key != "":
		headers.append("Authorization: Bearer " + key)
		
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à OpenRouter.")

func _request_deepseek(prompt: String, model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_deepseek", "")
	if key == "":
		coach_error.emit("Clé API DeepSeek manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "deepseek-chat").replace("deepseek/", "")
	var url = "https://api.deepseek.com/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": "Tu es un Grand Maître International d'échecs d'élite."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à DeepSeek.")

func _request_openai(prompt: String, model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_openai", "")
	if key == "":
		coach_error.emit("Clé API OpenAI manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "gpt-4o-mini").replace("openai/", "")
	var url = "https://api.openai.com/v1/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": "Tu es un coach d'échecs pédagogique."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à OpenAI.")

func _request_anthropic(prompt: String, model_info: Dictionary) -> void:
	var key = SettingsManager.get_setting("api_key_anthropic", "")
	if key == "":
		coach_error.emit("Clé API Anthropic manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "claude-3-5-haiku-20241022").replace("anthropic/", "")
	var url = "https://api.anthropic.com/v1/messages"
	var body = JSON.stringify({
		"model": raw_id,
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"x-api-key: " + key,
		"anthropic-version: 2023-06-01"
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à Anthropic.")

func _fallback_offline_explanation(provider_name: String) -> void:
	var reply = "🎓 **Coach RodChessXD (Mode Découverte)** :\n\n"
	reply += "Stockfish a analysé la position avec succès. "
	reply += "Pour débloquer les explications complètes en langage naturel avec %s (100%% gratuit), configurez simplement votre clé gratuite dans le **Hub IA** (cliquez sur le badge en haut à droite)." % provider_name
	coach_response_received.emit(reply)
	coach_response_with_meta.emit(reply, "Gratuit (0,00 €)", 0.05)

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var elapsed = (Time.get_ticks_msec() / 1000.0) - current_query_start_time

	if response_code != 200:
		coach_error.emit("Le serveur a répondu avec l'erreur HTTP %d." % response_code)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json:
		coach_error.emit("Réponse JSON invalide reçue du modèle.")
		return

	var answer = ""
	# Parsing selon le format du fournisseur
	if json.has("candidates") and json["candidates"].size() > 0: # Gemini
		var cand = json["candidates"][0]
		if cand.has("content") and cand["content"].has("parts") and cand["content"]["parts"].size() > 0:
			answer = cand["content"]["parts"][0].get("text", "")
	elif json.has("choices") and json["choices"].size() > 0: # OpenAI / Groq / DeepSeek / OpenRouter
		var choice = json["choices"][0]
		if choice.has("message") and choice["message"].has("content"):
			answer = choice["message"]["content"]
	elif json.has("content") and json["content"] is Array and json["content"].size() > 0: # Anthropic
		answer = json["content"][0].get("text", "")
	elif json.has("response"): # Ollama SLM
		answer = json["response"]

	if answer != "":
		session_queries_count += 1
		var model_info = ModelCatalog.find_model_by_id(active_query_model_id)
		var cost_info = ModelCatalog.get_cost_estimate(model_info)
		var query_usd: float = cost_info.get("per_query_usd", 0.0)
		session_estimated_cost_usd += query_usd

		var cost_label: String = cost_info.get("label_per_query", "Gratuit")
		coach_response_received.emit(answer.strip_edges())
		coach_response_with_meta.emit(answer.strip_edges(), cost_label, elapsed)
	else:
		coach_error.emit("Impossible d'extraire le texte de la réponse du modèle.")
