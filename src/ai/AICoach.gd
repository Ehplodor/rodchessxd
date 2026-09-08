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
var last_query_context: Dictionary = {}

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

func _get_game_controller() -> Node:
	if is_inside_tree():
		var t = get_tree()
		if t and t.root and t.root.has_node("GameController"):
			return t.root.get_node("GameController")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		return tree.root.get_node("GameController")
	return null

func _get_database_manager() -> Node:
	if is_inside_tree():
		var t = get_tree()
		if t and t.root and t.root.has_node("DatabaseManager"):
			return t.root.get_node("DatabaseManager")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("DatabaseManager"):
		return tree.root.get_node("DatabaseManager")
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

	# Perspective demandée (Point de vue Blancs / Noirs / Neutre)
	var perspective = extra_context.get("perspective", _get_setting("coach_perspective", "white"))
	var perspective_label = "Blancs (⚪)"
	var perspective_instruction = ""
	if perspective == "black":
		perspective_label = "Noirs (⚫)"
		perspective_instruction = """RÈGLE D'OR DE POINT DE VUE (PERSPECTIVE OBLIGATOIRE) :
Tu es EXCLUSIVEMENT le coach et le conseiller personnel du JOUEUR AVEC LES NOIRS.
- Tous tes diagnostics, tes conseils stratégiques, tes alertes de sécurité et tes plans d'action doivent être formulés DU POINT DE VUE DES NOIRS.
- Explique ce que les Noirs ont bien ou mal fait, quelles menaces pèsent sur les Noirs, comment les Noirs doivent réfuter les Blancs et quel est le meilleur plan pour les Noirs.
- Même si le trait est aux Blancs, adresse-toi toujours au joueur Noir pour lui expliquer comment anticiper la réplique adverse !"""
	elif perspective == "neutral":
		perspective_label = "Neutre / Arbitre (⚖️)"
		perspective_instruction = """RÈGLE DE POINT DE VUE (ARBITRE / ANALYSTE NEUTRE) :
Tu es un analyste impartial et objectif. Présente les forces, faiblesses, opportunités et plans des Blancs et des Noirs de manière équilibrée."""
	else:
		perspective_label = "Blancs (⚪)"
		perspective_instruction = """RÈGLE D'OR DE POINT DE VUE (PERSPECTIVE OBLIGATOIRE) :
Tu es EXCLUSIVEMENT le coach et le conseiller personnel du JOUEUR AVEC LES BLANCS.
- Tous tes diagnostics, tes conseils stratégiques, tes alertes de sécurité et tes plans d'action doivent être formulés DU POINT DE VUE DES BLANCS.
- Explique ce que les Blancs ont bien ou mal fait, quelles menaces pèsent sur les Blancs, comment les Blancs doivent réfuter les Noirs et quel est le meilleur plan pour les Blancs.
- Même si le trait est aux Noirs, adresse-toi toujours au joueur Blanc pour lui expliquer comment anticiper la réplique adverse !"""

	# Déterminer qui a joué le dernier coup
	var last_move_desc = "Position initiale (aucun coup joué)"
	if last_move_san != "":
		var last_move_is_white = true
		if extra_context.has("last_move_color"):
			last_move_is_white = (extra_context["last_move_color"] == "white")
		elif extra_context.has("ply_index"):
			last_move_is_white = (int(extra_context["ply_index"]) % 2 == 0)
		else:
			# Si le trait est aux Noirs, c'est que les Blancs viennent de jouer
			last_move_is_white = (active_color_str == "Noirs")

		var author_str = "Blancs" if last_move_is_white else "Noirs"
		var natural_action = extra_context.get("last_move_natural", "")
		if natural_action != "":
			last_move_desc = "%s (%s - joué par les %s)" % [last_move_san, natural_action, author_str]
		else:
			last_move_desc = "%s (joué par les %s)" % [last_move_san, author_str]

	# --- 1. SYSTEM INSTRUCTIONS (RÈGLES D'OR & MISSION) ---
	var system_prompt = """Tu es RodCoach, Grand Maître International d'échecs et entraîneur pédagogique d'élite au sein de l'application RodChessXD.
Ton rôle est d'analyser les positions d'échecs pour faire progresser le joueur, en traduisant les calculs bruts de l'ordinateur en explications humaines lumineuses, logiques et immédiatement mémorables.

%s

RÈGLES DE RIGUEUR TACTIQUE (ANTI-HALLUCINATION) :
1. VÉRITÉ TERRAIN STRICTE (ZÉRO CALCUL INVENTÉ) :
   - Tu ne dois JAMAIS calculer de coups toi-même à l'aveugle : appuie-toi STRICTEMENT sur les données d'évaluation du moteur Stockfish fournies dans la fiche technique.
   - L'évaluation en pions, le meilleur coup et la suite tactique PV constituent la VÉRITÉ ABSOLUE du jeu. Tu ne dois jamais les contredire ni inventer des pièces imaginaires.
2. EXPLICATION DU « POURQUOI » (LE SENS ÉCHIQUÉEN PROFOND) :
   - Traduis les chiffres en principes concrets :
     * Motifs tactiques : clouages relatifs/absolus, fourchettes, attaques doubles, pièces non défendues, déviations, surcharges, échecs à la découverte, rayons X, mats du couloir.
     * Principes stratégiques : contrôle des cases centrales (e4, d4, e5, d5), sécurité du roi et statut du roque, colonnes ouvertes/semi-ouvertes pour les tours, avant-postes protégés pour les cavaliers, affaiblissement de cases de même couleur, paire de fous, structure de pions (pions doublés, isolés, arriérés, passés).
3. STRUCTURE DE RÉPONSE OBLIGATOIRE (LISIBLE SUR SMARTPHONE) :
   Formate systématiquement ta réponse avec ces 3 rubriques courtes et aérées en Markdown :
   - 🎯 **Diagnostic** : En 1 ou 2 phrases percutantes, qualifie l'impact du coup joué et résume l'état de l'évaluation du point de vue du camp conseillé (%s).
   - 💡 **Analyse & Réfutation** : Explique pourquoi ce coup est bon ou mauvais, ce qu'il permet ou néglige, et détaille le mécanisme de la variante calculée par le moteur (PV).
   - 📌 **Plan conseillé** : Donne 1 ou 2 conseils pratiques clairs et concrets pour guider le camp conseillé (%s).
4. TON ET VOCABULAIRE :
   - Langue : Français soigné, dynamique et motivant.
   - Notation : Notation algébrique standard (ex: 1. e4, 2... Cf6, 3. Fb5).
   - Format concis : 150 à 220 mots au total (2 à 4 paragraphes percutants).
5. ACTIONS NATURELLES DÉCODÉES (AIDE AU CALCUL) :
   - Tous les coups d'échecs (dernier coup joué, meilleur coup recommandé et suite de coups calculée par Stockfish) te sont fournis DÉJÀ DÉCODÉS en actions humaines explicites (ex: 'Dame blanche en c3 prend la Tour noire en e3', 'Cavalier blanc se déplace de g1 en f3').
   - Appuie-toi sur ces actions déjà formulées pour expliquer les gains de matériel, les clouages, les fourchettes et les réfutations sans risque d'erreur sur l'identité des pièces ou des cases.""" % [perspective_instruction, perspective_label, perspective_label]

	match personality:
		"blunder_hunter":
			system_prompt += "\n\nAdopte un ton direct, incisif et sans complaisance. Mets le doigt immédiatement sur la faille tactique, la sanction punitive et ce qui a été négligé."
		"kids_simple":
			system_prompt += "\n\nAdopte un ton très simple, amusant et imagé. Remplace le jargon technique par des métaphores visuelles concrètes ('le château du roi', 'le cavalier qui bondit au centre', 'la tour sur l'autoroute')."
		_:
			system_prompt += "\n\nAdopte un ton de mentor bienveillant, encourageant et constructif. Valorise les bonnes idées tout en expliquant les erreurs avec patience."

	var is_comeback = extra_context.get("prompt_type", "") == "comeback" or "remonter la pente" in user_question.to_lower()
	if is_comeback:
		system_prompt += "\n\n6. DIRECTIVE SPÉCIALE « REMONTER LA PENTE » (SANS SPOILER LE COUP DIRECT) :\n" \
			+ "- Le camp conseillé (%s) est sous pression ou cherche à renverser la tendance.\n" % perspective_label \
			+ "- RÈGLE STRICTE : Tu as l'interdiction de lui révéler directement le coup exact ('Jouez %s') ou d'écrire la solution sous forme de recette toute faite.\n" % best_move \
			+ "- À la place, donne-lui les clés fondamentales pour remonter la pente par lui-même :\n" \
			+ "  * Attitude et combativité : ne rien céder, compliquer au maximum chaque décision adverse.\n" \
			+ "  * Défense active et contre-jeu : sortir de la passivité, activer les pièces endormies, ouvrir des contre-chances.\n" \
			+ "  * Cibles adverses : repérer les faiblesses structurelles, pièces non protégées ou roi ennemi mal abrité.\n" \
			+ "  * Complications et pièges : orienter sa réflexion tactique vers les zones à exploiter sans lui dicter le coup."

	# Décodage naturel du meilleur coup et de la variante calculée
	var best_move_desc = "N/A"
	if best_move != "":
		var bm_natural = ChessGame.describe_move_from_fen(fen, best_move)
		if bm_natural != "" and bm_natural != best_move:
			best_move_desc = "`%s` (%s)" % [best_move, bm_natural]
		else:
			best_move_desc = "`%s`" % best_move

	var pv_natural_text = ChessGame.format_pv_natural_text(fen, pv_line, 6)

	# --- 2. USER CONTENT (FICHE D'ANALYSE DE LA POSITION) ---
	var user_prompt = """### 📋 FICHE TECHNIQUE DE LA POSITION (Stockfish 18)
- **Perspective d'analyse demandée** : %s (Conseiller ce camp en priorité)
- **Dernier coup joué** : %s
- **Trait actuel au jeu** : %s
- **Position FEN** : `%s`
- **Phase de la partie** : %s
- **Équilibre matériel** : %s
- **Qualification du coup** : %s
- **Évaluation Stockfish** : %s
- **Meilleur coup recommandé par Stockfish** : %s
- **Variante tactique calculée par Stockfish (enchaînement coup par coup)** :
%s
""" % [
		perspective_label,
		last_move_desc,
		active_color_str,
		fen,
		game_phase,
		mat_info.get("summary", "Égalité"),
		quality_label,
		eval_desc,
		best_move_desc,
		pv_natural_text
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
	last_query_context = {
		"fen": fen,
		"last_move_san": last_move_san,
		"eval_cp": eval_cp,
		"best_move": best_move,
		"pv_line": pv_line,
		"user_question": user_question,
		"extra_context": extra_context
	}
	var prompt_data = build_prompt_data(fen, last_move_san, eval_cp, best_move, pv_line, user_question, extra_context)
	current_query_start_time = Time.get_ticks_msec() / 1000.0
	coach_thinking_started.emit()

	var active_model_id = _get_setting("active_model_id", "z-ai/glm-5.3-flash:free")
	active_query_model_id = active_model_id

	var model_info = _find_model(active_model_id)
	var provider = model_info.get("provider", "openrouter")

	match provider:
		"native_slm":
			_request_native_slm(prompt_data, model_info)
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

func _request_native_slm(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var model_id = model_info.get("id", "native_slm/smollm2-360m")
	
	# 1. Vérifier si le modèle GGUF est installé
	var downloader = null
	if Engine.has_singleton("ModelDownloader") or has_node("/root/ModelDownloader"):
		downloader = get_node("/root/ModelDownloader")
	
	if downloader and not downloader.is_model_installed(model_id):
		coach_error.emit("Le modèle %s n'est pas encore téléchargé.\n👉 Ouvrez le Hub de Modèles pour l'installer en 1 clic (100%% gratuit, hors-ligne)." % model_info.get("name", "SLM"))
		return

	# 2. Vérifier si LocalSLMManager est disponible
	var slm_mgr = null
	if Engine.has_singleton("LocalSLMManager") or has_node("/root/LocalSLMManager"):
		slm_mgr = get_node("/root/LocalSLMManager")
	
	if not slm_mgr:
		_fallback_offline_explanation("SLM Local Autonome")
		return

	# 3. Vérifier si l'exécutable d'inférence est disponible
	if not slm_mgr.is_inference_engine_available():
		_fallback_offline_explanation("SLM Local (Moteur non configuré)")
		return

	# 4. S'assurer que le serveur tourne pour ce modèle
	if not slm_mgr.ensure_model_running(model_id):
		coach_error.emit("Impossible de démarrer le serveur SLM local pour %s." % model_id)
		return

	var url = slm_mgr.get_api_endpoint_url()
	var body = JSON.stringify({
		"model": model_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		],
		"max_tokens": 512,
		"temperature": 0.5
	})
	var headers = ["Content-Type: application/json"]
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de communication avec le serveur SLM local (%s)." % url)

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
	if key.strip_edges() == "":
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
	if key.strip_edges() == "":
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
	if key.strip_edges() == "":
		_fallback_offline_explanation("OpenRouter")
		return

	var model_id = model_info.get("id", "z-ai/glm-5.3-flash:free")
	
	var url = "https://openrouter.ai/api/v1/chat/completions"
	var body = JSON.stringify({
		"model": model_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		],
		"max_tokens": 750,
		"temperature": 0.5
	})
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
		"HTTP-Referer: https://rodchessxd.app",
		"X-Title: RodChessXD"
	]
		
	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_error.emit("Erreur de connexion à OpenRouter.")

func _request_deepseek(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = _get_setting("api_key_deepseek", "")
	if key.strip_edges() == "":
		_fallback_offline_explanation("DeepSeek")
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
	if key.strip_edges() == "":
		_fallback_offline_explanation("OpenAI")
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
	if key.strip_edges() == "":
		_fallback_offline_explanation("Anthropic")
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
	var last_move = last_query_context.get("last_move_san", "")
	var eval_cp = last_query_context.get("eval_cp", 0)
	var best_move = last_query_context.get("best_move", "")
	var pv = last_query_context.get("pv_line", [])

	var reply = "🎓 **Coach RodChessXD (Mode Découverte & Stockfish)** :\n\n"
	if last_move != "":
		reply += "• **Dernier coup analysé** : [b]`%s`[/b]\n" % last_move
	if best_move != "":
		reply += "• **Calcul Stockfish** : Meilleur coup recommandé [b]`%s`[/b] (%s)\n" % [best_move, _format_eval_description(eval_cp)]
	if pv.size() > 1:
		var pv_str = ""
		for i in range(mini(pv.size(), 4)):
			pv_str += str(pv[i]) + " "
		reply += "• **Ligne principale** : `%s`\n" % pv_str.strip_edges()

	reply += "\n---\n"
	reply += "🔑 **Pour activer les explications complètes en langage naturel** avec [b]%s[/b] (100%% gratuit, 0 € sans carte bancaire) :\n\n" % provider_name
	reply += "1. Cliquez sur le badge [b]⚡[/b] du Coach en haut (ou sur ⚙️ Paramètres).\n"
	if provider_name == "OpenRouter":
		reply += "2. Obtenez une clé gratuite en 30s sur [b]https://openrouter.ai/keys[/b]\n"
		reply += "3. Collez-la dans le champ [i]Clé OpenRouter[/i] et validez.\n\n"
	elif provider_name == "Google Gemini":
		reply += "2. Obtenez une clé gratuite en 30s sur [b]https://aistudio.google.com[/b]\n"
		reply += "3. Collez-la dans le champ [i]Clé Google Gemini[/i] et validez.\n\n"
	elif provider_name == "Groq":
		reply += "2. Obtenez une clé gratuite en 30s sur [b]https://console.groq.com/keys[/b]\n"
		reply += "3. Collez-la dans le champ [i]Clé Groq[/i] et validez.\n\n"
	else:
		reply += "2. Renseignez votre clé API dans le champ correspondant et validez.\n\n"
	reply += "💡 *Astuce : Vous pouvez aussi lancer un modèle local 100% hors-ligne (ex: Ollama) sans aucune clé requise !*"

	coach_response_received.emit(reply)
	coach_response_with_meta.emit(reply, "Mode Stockfish Local", 0.05)

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var elapsed = (Time.get_ticks_msec() / 1000.0) - current_query_start_time

	if response_code != 200:
		var text = body.get_string_from_utf8()
		var err_detail = ""
		var json = JSON.parse_string(text)
		if json is Dictionary and json.has("error"):
			var err_obj = json["error"]
			if err_obj is Dictionary and err_obj.has("message"):
				err_detail = String(err_obj["message"])
			elif err_obj is String:
				err_detail = err_obj

		if response_code == 401:
			var msg = "Erreur HTTP 401 (Authentification requise) :\nClé API manquante ou invalide."
			if err_detail != "":
				msg += "\nMessage du fournisseur : " + err_detail
			msg += "\n\n👉 Cliquez sur le badge '⚡' du Coach (ou ⚙️ Paramètres) pour renseigner votre clé API valide."
			coach_error.emit(msg)
		elif response_code == 429:
			var msg = "Erreur HTTP 429 (Limite de requêtes atteinte / Quota)."
			if err_detail != "":
				msg += "\nMessage du fournisseur : " + err_detail
			msg += "\n\nPatientez quelques instants ou choisissez un autre modèle dans le sélecteur."
			coach_error.emit(msg)
		elif response_code == 403:
			var msg = "Erreur HTTP 403 (Accès refusé)."
			if err_detail != "":
				msg += "\nMessage du fournisseur : " + err_detail
			coach_error.emit(msg)
		else:
			var msg = "Le serveur a répondu avec l'erreur HTTP %d." % response_code
			if err_detail != "":
				msg += " (%s)" % err_detail
			coach_error.emit(msg)
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

		# Archivage automatique dans DatabaseManager
		var dm = _get_database_manager()
		var gc = _get_game_controller()
		if dm and gc:
			var gid = gc.get_or_create_game_id()
			if gid != "":
				var extra = last_query_context.get("extra_context", {})
				var coach_record = {
					"ply_index": extra.get("ply_index", gc.current_ply_index),
					"move_number": extra.get("move_number", 1),
					"move_san": last_query_context.get("last_move_san", ""),
					"perspective": extra.get("perspective", _get_setting("coach_perspective", "white")),
					"model_id": active_query_model_id,
					"provider": model_info.get("provider", "openrouter"),
					"user_question": last_query_context.get("user_question", ""),
					"response_text": answer.strip_edges(),
					"elapsed_sec": elapsed,
					"cost_label": cost_label
				}
				dm.add_coach_analysis(gid, coach_record)
	else:
		coach_error.emit("Impossible d'extraire le texte de la réponse du modèle.")
