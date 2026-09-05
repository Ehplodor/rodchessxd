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
func _get_settings() -> Node:
	if is_inside_tree():
		var t = get_tree()
		if t and t.root and t.root.has_node("SettingsManager"):
			return t.root.get_node("SettingsManager")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _get_catalog() -> Node:
	if is_inside_tree():
		var t = get_tree()
		if t and t.root and t.root.has_node("ModelCatalog"):
			return t.root.get_node("ModelCatalog")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("ModelCatalog"):
		return tree.root.get_node("ModelCatalog")
	return null

func _get_setting(key: String, default_val: Variant) -> Variant:
	var sm = _get_settings()
	if sm:
		return sm.get_setting(key, default_val)
	return default_val

func _find_model(model_id: String) -> Dictionary:
	var cat = _get_catalog()
	if cat:
		return cat.find_model_by_id(model_id)
	return {}

## Construit le dictionnaire de prompt structuré (system, user, full_text) avec analyse complète de la position
func build_prompt_data(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = "",
	extra_context: Dictionary = {}
) -> Dictionary:
	var active_color_str = "Blancs"
	var parts = fen.split(" ")
	if parts.size() > 1 and parts[1] == "b":
		active_color_str = "Noirs"

	var move_num: int = int(extra_context.get("move_number", 1))
	var game_phase: String = _detect_game_phase(fen, move_num)
	var mat_info: Dictionary = _compute_material_balance(fen)
	var eval_desc: String = _format_eval_description(eval_cp)
	
	var quality_int: int = int(extra_context.get("quality", 0))
	var cp_loss: int = int(extra_context.get("cp_loss", 0))
	var quality_label: String = _format_quality_label(quality_int, cp_loss)

	var pv_clean: Array[String] = []
	for p in pv_line.slice(0, 6):
		pv_clean.append(str(p))
	var pv_str = " ".join(pv_clean) if pv_clean.size() > 0 else "Variante directe selon Stockfish"

	var personality = extra_context.get("personality", _get_setting("coach_personality", "mentor"))

	# --- 1. SYSTEM INSTRUCTIONS (RÈGLES D'OR & MISSION) ---
	var system_prompt = """Tu es RodCoach, Grand Maître International d'échecs et entraîneur pédagogique d'élite au sein de l'application RodChessXD.
Ton rôle est d'analyser les positions d'échecs pour faire progresser le joueur, en traduisant les calculs bruts de l'ordinateur en explications humaines lumineuses, logiques et immédiatement mémorables.

RÈGLES D'OR DE RIGUEUR TACTIQUE (ANTI-HALLUCINATION) :
1. VÉRITÉ TERRAIN STRICTE (ZÉRO CALCUL INVENTÉ) :
   - Tu ne dois JAMAIS calculer de coups toi-même à l'aveugle : appuie-toi STRICTEMENT sur les données d'évaluation du moteur Stockfish fournies dans la fiche technique.
   - L'évaluation en pions, le meilleur coup et la suite tactique PV constituent la VÉRITÉ ABSOLUE du jeu. Tu ne dois jamais les contredire ni inventer des pièces imaginaires.
2. EXPLICATION DU « POURQUOI » (LE SENS ÉCHIQUÉEN PROFOND) :
   - Traduis les chiffres en principes concrets :
     * Motifs tactiques : clouages relatifs/absolus, fourchettes, attaques doubles, pièces non défendues, déviations, surcharges, échecs à la découverte, rayons X, mats du couloir.
     * Principes stratégiques : contrôle des cases centrales (e4, d4, e5, d5), sécurité du roi et statut du roque, colonnes ouvertes/semi-ouvertes pour les tours, avant-postes protégés pour les cavaliers, affaiblissement de cases de même couleur, paire de fous, structure de pions (pions doublés, isolés, arriérés, passés).
3. STRUCTURE DE RÉPONSE OBLIGATOIRE (LISIBLE SUR SMARTPHONE) :
   Formate systématiquement ta réponse avec ces 3 rubriques courtes et aérées en Markdown :
   - 🎯 **Diagnostic** : En 1 ou 2 phrases percutantes, qualifie l'impact du coup joué et résume l'état de l'évaluation.
   - 💡 **Analyse & Réfutation** : Explique pourquoi ce coup est bon ou mauvais, ce qu'il permet ou néglige, et détaille le mécanisme de la variante calculée par le moteur (PV).
   - 📌 **Plan conseillé** : Donne 1 ou 2 conseils pratiques clairs et concrets pour les prochains coups.
4. TON ET VOCABULAIRE :
   - Langue : Français soigné, dynamique et motivant.
   - Notation : Notation algébrique standard (ex: 1. e4, 2... Cf6, 3. Fb5).
   - Format concis : 150 à 250 mots au total (2 à 4 paragraphes percutants)."""

	match personality:
		"blunder_hunter":
			system_prompt += "\n\nAdopte un ton direct, incisif et sans complaisance. Mets le doigt immédiatement sur la faille tactique, la sanction punitive et ce qui a été négligé."
		"kids_simple":
			system_prompt += "\n\nAdopte un ton très simple, amusant et imagé. Remplace le jargon technique par des métaphores visuelles concrètes ('le château du roi', 'le cavalier qui bondit au centre', 'la tour sur l'autoroute')."
		_:
			system_prompt += "\n\nAdopte un ton de mentor bienveillant, encourageant et constructif. Valorise les bonnes idées tout en expliquant les erreurs avec patience."

	# --- 2. USER CONTENT (FICHE D'ANALYSE DE LA POSITION) ---
	var user_prompt = """### 📋 FICHE TECHNIQUE DE LA POSITION (Stockfish 18)
- **Position FEN** : `%s`
- **Trait au jeu** : %s
- **Phase de la partie** : %s
- **Équilibre matériel** : %s
- **Dernier coup joué** : %s
- **Qualification du coup** : %s
- **Évaluation Stockfish** : %s
- **Meilleur coup recommandé par Stockfish** : `%s`
- **Variante calculée (PV)** : `%s`
""" % [
		fen,
		active_color_str,
		game_phase,
		mat_info.get("summary", "Égalité"),
		last_move_san if last_move_san != "" else "Position initiale",
		quality_label,
		eval_desc,
		best_move if best_move != "" else "N/A",
		pv_str
	]

	if extra_context.get("is_check", false):
		user_prompt += "- **Alerte immédiate** : Le Roi est actuellement en ÉCHEC !\n"
	if extra_context.get("is_checkmate", false):
		user_prompt += "- **Alerte immédiate** : ÉCHEC ET MAT !\n"

	user_prompt += "\n---\n"
	if user_question != "":
		user_prompt += "### 💬 QUESTION DU JOUEUR :\n\"%s\"\n\nRéponds précisément à la question en t'appuyant rigoureusement sur les données objectives ci-dessus." % user_question
	else:
		user_prompt += "### 🎯 MISSION DU COACH :\nAnalyse le coup joué, explique pourquoi le meilleur coup recommandé par Stockfish est supérieur et quel est le plan stratégique conseillé pour la suite."

	var full_text = system_prompt + "\n\n" + user_prompt

	return {
		"system": system_prompt,
		"user": user_prompt,
		"full_text": full_text
	}

## Retourne le prompt complet sous forme de chaîne de caractères (compatibilité)
func build_chess_prompt(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = "",
	extra_context: Dictionary = {}
) -> String:
	var data = build_prompt_data(fen, last_move_san, eval_cp, best_move, pv_line, user_question, extra_context)
	return data.get("full_text", "")

## Calcule la balance et le décompte matériel exact depuis le FEN
func _compute_material_balance(fen: String) -> Dictionary:
	var parts = fen.split(" ")
	if parts.is_empty():
		return {"summary": "Information matérielle non disponible", "diff": 0}
	
	var board_str = parts[0]
	var white_pts = 0
	var black_pts = 0

	for ch in board_str:
		match ch:
			"P": white_pts += 1
			"N": white_pts += 3
			"B": white_pts += 3
			"R": white_pts += 5
			"Q": white_pts += 9
			"p": black_pts += 1
			"n": black_pts += 3
			"b": black_pts += 3
			"r": black_pts += 5
			"q": black_pts += 9

	var diff = white_pts - black_pts
	var desc = ""
	if diff == 0:
		desc = "Égalité matérielle (%d pts contre %d pts)" % [white_pts, black_pts]
	elif diff > 0:
		desc = "Avantage matériel Blancs (+%d pts - Blancs: %d pts vs Noirs: %d pts)" % [diff, white_pts, black_pts]
	else:
		desc = "Avantage matériel Noirs (+%d pts - Noirs: %d pts vs Blancs: %d pts)" % [abs(diff), black_pts, white_pts]

	return {
		"summary": desc,
		"white_pts": white_pts,
		"black_pts": black_pts,
		"diff": diff
	}

## Détecte la phase de jeu (Ouverture, Milieu de jeu, Finale)
func _detect_game_phase(fen: String, move_number: int) -> String:
	var parts = fen.split(" ")
	if parts.is_empty():
		return "Milieu de jeu"
	
	var board_str = parts[0]
	var non_pawn_pieces = 0
	for ch in board_str:
		if ch in ["Q", "R", "B", "N", "q", "r", "b", "n"]:
			non_pawn_pieces += 1

	if move_number > 0 and move_number <= 10 and non_pawn_pieces >= 14:
		return "Ouverture (Développement des pièces, contrôle du centre et mise en sécurité du roi)"
	elif non_pawn_pieces <= 4 or (not ("Q" in board_str or "q" in board_str) and non_pawn_pieces <= 6):
		return "Finale (Activité des rois, poussée et promotion des pions passés)"
	else:
		return "Milieu de jeu (Manoeuvres tactiques, avant-postes, attaques sur les faiblesses)"

## Formate la description humaine de l'évaluation Stockfish
func _format_eval_description(eval_cp: int) -> String:
	if eval_cp >= 10000:
		return "Mat forcé pour les Blancs !"
	elif eval_cp <= -10000:
		return "Mat forcé pour les Noirs !"
	
	var val = eval_cp / 100.0
	if abs(eval_cp) <= 25:
		return "0.00 (Position d'égalité stricte)"
	elif eval_cp > 25 and eval_cp <= 80:
		return "+%.2f pions (Léger avantage Blancs)" % val
	elif eval_cp > 80 and eval_cp <= 200:
		return "+%.2f pions (Avantage net et durable pour les Blancs)" % val
	elif eval_cp > 200:
		return "+%.2f pions (Avantage décisif et gagnant pour les Blancs)" % val
	elif eval_cp < -25 and eval_cp >= -80:
		return "%.2f pions (Léger avantage Noirs)" % val
	elif eval_cp < -80 and eval_cp >= -200:
		return "%.2f pions (Avantage net et durable pour les Noirs)" % val
	else:
		return "%.2f pions (Avantage décisif et gagnant pour les Noirs)" % val

## Formate l'étiquette qualitative du coup
func _format_quality_label(quality: int, cp_loss: int) -> String:
	match quality:
		1: # BEST
			return "Meilleur coup (★) • Choix numéro 1 du moteur"
		2: # BRILLIANT
			return "Coup brillant (!!) • Coup spectaculaire maintenant ou créant un gain forcé"
		3: # GREAT
			return "Grand coup (!) • Coup critique unique préservant l'avantage"
		4: # EXCELLENT
			return "Excellent coup (✓) • Pratiquement équivalent au meilleur coup"
		5: # GOOD
			return "Bon coup • Choix solide et naturel"
		6: # INACCURACY
			return "Imprécision (?!) • Perte de %.2f pions par rapport au coup optimal" % (cp_loss / 100.0)
		7: # MISTAKE
			return "Erreur (?) • Perte de %.2f pions (dégrade sensiblement la position)" % (cp_loss / 100.0)
		8: # BLUNDER
			return "Gaffe critique (??) • Perte majeure de %.2f pions (renverse le sort de la partie)" % (cp_loss / 100.0)
		9: # MISS
			return "Occasion manquée • A laissé passer un gain ou une tactique décisive"
		_:
			if cp_loss > 200:
				return "Gaffe probable (??) • Perte de %.2f pions" % (cp_loss / 100.0)
			elif cp_loss > 90:
				return "Erreur probable (?) • Perte de %.2f pions" % (cp_loss / 100.0)
			elif cp_loss > 35:
				return "Imprécision (?!) • Perte de %.2f pions" % (cp_loss / 100.0)
			else:
				return "Coup joué dans la partie"

## Envoi de la demande au modèle actuellement sélectionné
func ask_coach(
	fen: String,
	last_move_san: String,
	eval_cp: int,
	best_move: String,
	pv_line: Array,
	user_question: String = "",
	extra_context: Dictionary = {}
) -> void:
	var prompt_data = build_prompt_data(fen, last_move_san, eval_cp, best_move, pv_line, user_question, extra_context)
	current_query_start_time = Time.get_ticks_msec() / 1000.0
	coach_thinking_started.emit()

	var active_model_id = _get_setting("active_model_id", "z-ai/glm-5.3-flash:free")
	active_query_model_id = active_model_id

	var model_info = _find_model(active_model_id)
	var provider = model_info.get("provider", "openrouter")

	match provider:
		"ollama":
			_request_local_ollama(prompt_data, model_info)
		"groq":
			_request_groq(prompt_data, model_info)
		"gemini":
			_request_gemini(prompt_data, model_info)
		"openrouter":
			_request_openrouter(prompt_data, model_info)
		"deepseek":
			_request_deepseek(prompt_data, model_info)
		"openai":
			_request_openai(prompt_data, model_info)
		"anthropic":
			_request_anthropic(prompt_data, model_info)
		_:
			_request_openrouter(prompt_data, model_info)

# --- REQUÊTES VERS LES DIFFÉRENTS FOURNISSEURS ---

func _request_local_ollama(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var raw_id = model_info.get("id", "ollama/glm-5.3-flash")
	var model_name = raw_id.replace("ollama/", "")
	var base_url = _get_setting("local_slm_url", "http://127.0.0.1:11434/api/generate")
	
	var body = JSON.stringify({
		"model": model_name,
		"system": prompt_data.get("system", ""),
		"prompt": prompt_data.get("user", ""),
		"stream": false
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(base_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Impossible de contacter Ollama en local (%s). Vérifiez qu'Ollama est bien démarré." % base_url)

func _request_groq(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_groq", "")
	if key == "":
		_fallback_offline_explanation("Groq")
		return

	var raw_id = model_info.get("id", "llama-3.3-70b-versatile").replace("groq/", "")
	var url = "https://api.groq.com/openai/v1/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à Groq Cloud.")

func _request_gemini(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_gemini", "")
	if key == "":
		_fallback_offline_explanation("Google Gemini")
		return

	var model_name = model_info.get("id", "gemini-2.0-flash").replace("google/", "")
	if model_name.ends_with(":free"):
		model_name = model_name.replace(":free", "")
	var url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [model_name, key]
	var body = JSON.stringify({
		"system_instruction": {
			"parts": [{"text": prompt_data.get("system", "")}]
		},
		"contents": [{
			"parts": [{"text": prompt_data.get("user", "")}]
		}]
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à Google Gemini.")

func _request_openrouter(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_openrouter", "")
	var model_id = model_info.get("id", "z-ai/glm-5.3-flash:free")
	
	var url = "https://openrouter.ai/api/v1/chat/completions"
	var body = JSON.stringify({
		"model": model_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
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

func _request_deepseek(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_deepseek", "")
	if key == "":
		coach_error.emit("Clé API DeepSeek manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "deepseek-chat").replace("deepseek/", "")
	var url = "https://api.deepseek.com/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à DeepSeek.")

func _request_openai(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_openai", "")
	if key == "":
		coach_error.emit("Clé API OpenAI manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "gpt-4o-mini").replace("openai/", "")
	var url = "https://api.openai.com/v1/chat/completions"
	var body = JSON.stringify({
		"model": raw_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		]
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key
	]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à OpenAI.")

func _request_anthropic(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_anthropic", "")
	if key == "":
		coach_error.emit("Clé API Anthropic manquante. Rendez-vous dans le Hub IA pour l'ajouter.")
		return

	var raw_id = model_info.get("id", "claude-3-5-haiku-20241022").replace("anthropic/", "")
	var url = "https://api.anthropic.com/v1/messages"
	var body = JSON.stringify({
		"model": raw_id,
		"max_tokens": 1024,
		"system": prompt_data.get("system", ""),
		"messages": [
			{"role": "user", "content": prompt_data.get("user", "")}
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
		var model_info = _find_model(active_query_model_id)
		var cat = _get_catalog()
		var cost_info = cat.get_cost_estimate(model_info) if cat else {}
		var query_usd: float = cost_info.get("per_query_usd", 0.0)
		session_estimated_cost_usd += query_usd

		var cost_label: String = cost_info.get("label_per_query", "Gratuit")
		coach_response_received.emit(answer.strip_edges())
		coach_response_with_meta.emit(answer.strip_edges(), cost_label, elapsed)
	else:
		coach_error.emit("Impossible d'extraire le texte de la réponse du modèle.")
