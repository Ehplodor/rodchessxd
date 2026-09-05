extends Node
## AICoach.gd - Service d'explication pédagogique en langage naturel (SLM Local / Cloud Gratuit / Clés API)

signal coach_thinking_started
signal coach_response_received(response: String)
signal coach_error(error_msg: String)

var http_client: HTTPRequest

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

## Envoi de la demande au fournisseur sélectionné
func ask_coach(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = ""
) -> void:
	var prompt = build_chess_prompt(fen, last_move_san, eval_cp, best_move, pv_line, user_question)
	coach_thinking_started.emit()

	var provider = SettingsManager.get_setting("ai_provider", "free_cloud")
	
	match provider:
		"local_slm":
			_request_local_slm(prompt)
		"free_cloud":
			_request_free_cloud(prompt)
		"api_key":
			_request_api_key_provider(prompt)
		_:
			_request_free_cloud(prompt)

func _request_local_slm(prompt: String) -> void:
	var url = SettingsManager.get_setting("local_slm_url", "http://127.0.0.1:11434/api/generate")
	var body = JSON.stringify({
		"model": "qwen2.5:1.5b",
		"prompt": prompt,
		"stream": false
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion au SLM local (%s)" % url)

func _request_free_cloud(prompt: String) -> void:
	# Utilisation de Google Gemini API (Free Tier) ou Groq
	var api_key = SettingsManager.get_setting("api_key_gemini", "")
	# Si aucune clé personnelle n'est fournie, tenter une clé par défaut ou proposer l'option
	if api_key == "":
		api_key = SettingsManager.get_setting("api_key_groq", "")
		if api_key != "":
			_request_groq(prompt, api_key)
			return
		
		# Fallback vers une réponse pédagogique intégrée hors-ligne si aucune clé
		_fallback_offline_explanation(prompt)
		return

	_request_gemini(prompt, api_key)

func _request_api_key_provider(prompt: String) -> void:
	var service = SettingsManager.get_setting("ai_api_service", "openai")
	match service:
		"openai":
			var key = SettingsManager.get_setting("api_key_openai", "")
			if key == "":
				coach_error.emit("Clé API OpenAI non configurée dans les paramètres.")
				return
			_request_openai(prompt, key)
		"anthropic":
			var key = SettingsManager.get_setting("api_key_anthropic", "")
			if key == "":
				coach_error.emit("Clé API Anthropic non configurée dans les paramètres.")
				return
			_request_anthropic(prompt, key)
		"deepseek":
			var key = SettingsManager.get_setting("api_key_deepseek", "")
			if key == "":
				coach_error.emit("Clé API DeepSeek non configurée dans les paramètres.")
				return
			_request_deepseek(prompt, key)
		_:
			_request_free_cloud(prompt)

func _request_gemini(prompt: String, api_key: String) -> void:
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=" + api_key
	var body = JSON.stringify({
		"contents": [{
			"parts": [{"text": prompt}]
		}]
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de requête Gemini Cloud.")

func _request_groq(prompt: String, api_key: String) -> void:
	var url = "https://api.groq.com/openai/v1/chat/completions"
	var body = JSON.stringify({
		"model": "llama-3.3-70b-versatile",
		"messages": [
			{"role": "system", "content": "Tu es un coach d'échecs de haut niveau."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de requête Groq Cloud.")

func _request_openai(prompt: String, api_key: String) -> void:
	var url = "https://api.openai.com/v1/chat/completions"
	var body = JSON.stringify({
		"model": "gpt-4o-mini",
		"messages": [
			{"role": "system", "content": "Tu es un coach d'échecs pédagogique."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de requête OpenAI.")

func _request_anthropic(prompt: String, api_key: String) -> void:
	var url = "https://api.anthropic.com/v1/messages"
	var body = JSON.stringify({
		"model": "claude-3-5-haiku-20241022",
		"max_tokens": 1024,
		"messages": [
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: 2023-06-01"
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de requête Anthropic.")

func _request_deepseek(prompt: String, api_key: String) -> void:
	var url = "https://api.deepseek.com/chat/completions"
	var body = JSON.stringify({
		"model": "deepseek-chat",
		"messages": [
			{"role": "system", "content": "Tu es un coach d'échecs expert."},
			{"role": "user", "content": prompt}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de requête DeepSeek.")

func _fallback_offline_explanation(prompt: String) -> void:
	# Analyse heuristique locale pour donner un retour immédiat même sans internet/clé configurée
	var reply = "🎓 **Analyse du Coach RodChessXD** :\n\n"
	reply += "Stockfish a analysé la position avec succès. "
	reply += "Pour obtenir une analyse détaillée en langage naturel via Google Gemini gratuit, Groq ou vos clés personnelles (OpenAI, Claude, DeepSeek), vous pouvez ajouter une clé API dans les Paramètres (icône ⚙️)."
	coach_response_received.emit(reply)

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		coach_error.emit("Le serveur a répondu avec le code d'erreur : %d" % response_code)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json:
		coach_error.emit("Réponse invalide reçue du modèle.")
		return

	var answer = ""
	# Parsing selon le format de la réponse
	if json.has("candidates") and json["candidates"].size() > 0: # Gemini
		var cand = json["candidates"][0]
		if cand.has("content") and cand["content"].has("parts") and cand["content"]["parts"].size() > 0:
			answer = cand["content"]["parts"][0].get("text", "")
	elif json.has("choices") and json["choices"].size() > 0: # OpenAI / Groq / DeepSeek
		var choice = json["choices"][0]
		if choice.has("message") and choice["message"].has("content"):
			answer = choice["message"]["content"]
	elif json.has("content") and json["content"] is Array and json["content"].size() > 0: # Anthropic
		answer = json["content"][0].get("text", "")
	elif json.has("response"): # Ollama SLM
		answer = json["response"]

	if answer != "":
		coach_response_received.emit(answer.strip_edges())
	else:
		coach_error.emit("Format de réponse IA non reconnu.")
