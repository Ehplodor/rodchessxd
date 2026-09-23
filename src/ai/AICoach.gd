extends Node
## AICoach.gd - Service d'explication pédagogique en langage naturel
## Intégré avec ModelCatalog pour supporter tous les modèles actuels (Gratuits, API, SLM Locaux)

signal coach_thinking_started
signal coach_response_received(response: String)
signal coach_response_with_meta(response: String, cost_label: String, elapsed_sec: float)
signal coach_response_detailed(response: String, reasoning: String, cost_label: String, elapsed_sec: float)
signal coach_error(error_msg: String)
signal coach_speech_started
signal coach_speech_finished
signal coach_speech_error(error_msg: String)

var http_client: HTTPRequest
var tts_http_client: HTTPRequest
var audio_player: AudioStreamPlayer
var is_speaking: bool = false
var _active_local_utterance_generation: int = 0
var current_query_start_time: float = 0.0
var active_query_model_id: String = ""

# Métriques de session
var session_queries_count: int = 0
var session_estimated_cost_usd: float = 0.0
var last_query_context: Dictionary = {}

func _ready() -> void:
	http_client = HTTPRequest.new()
	http_client.timeout = 30.0
	add_child(http_client)
	http_client.request_completed.connect(_on_request_completed)

	tts_http_client = HTTPRequest.new()
	tts_http_client.timeout = 25.0
	add_child(tts_http_client)
	tts_http_client.request_completed.connect(_on_tts_request_completed)

	audio_player = AudioStreamPlayer.new()
	audio_player.finished.connect(_on_audio_player_finished)
	add_child(audio_player)

	# Initialisation des rappels TTS natifs du système (DisplayServer)
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, _on_local_tts_started)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_local_tts_ended)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_local_tts_canceled)

func _send_http_request(url: String, headers: Array, body: String, provider_name: String) -> void:
	if http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		http_client.cancel_request()

	var err = http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		var err_str = "code d'erreur client interne %d" % err
		coach_error.emit("Impossible d'initialiser la requête vers %s (%s). Vérifiez la connexion de l'appareil." % [provider_name, err_str])
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

func _get_engine_manager() -> Node:
	if is_inside_tree():
		var t = get_tree()
		if t and t.root and t.root.has_node("EngineManager"):
			return t.root.get_node("EngineManager")
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		return tree.root.get_node("EngineManager")
	return null

## Méthode unifiée pour exécuter un prompt du coach (utilisée par CoachPanel2D et les raccourcis du plateau)
func execute_coach_prompt(
	perspective: String,
	label_text: String,
	query_text: String,
	prompt_type: String,
	request_audio: bool = false
) -> void:
	var gc = _get_game_controller()
	var game = gc.game if gc else null
	if game == null:
		return
	if gc:
		gc.get_or_create_game_id()

	var current_ply = gc.current_ply_index if gc else -1
	var fen = game.get_fen()
	var last_move_san = ""
	var extra_context = {
		"perspective": perspective,
		"prompt_type": prompt_type,
		"label_text": label_text,
		"request_audio": request_audio
	}

	if current_ply >= 0 and current_ply < game.move_history.size():
		var m = game.move_history[current_ply]
		last_move_san = m.san
		extra_context["last_move_natural"] = game.describe_move_natural(m)
		extra_context["last_move_uci"] = m.uci
		extra_context["quality"] = m.quality
		extra_context["cp_loss"] = m.centipawn_loss
		var info: Dictionary = game.ply_info(current_ply)
		extra_context["move_number"] = info["move_number"]
		extra_context["ply_index"] = current_ply
		extra_context["last_move_color"] = "white" if info["is_white"] else "black"
		extra_context["is_check"] = m.is_check
		extra_context["is_checkmate"] = m.is_checkmate
		extra_context["motifs"] = m.motifs
		extra_context["is_theory"] = m.is_theory
	else:
		extra_context["move_number"] = 1
		extra_context["ply_index"] = -1

	var eng = _get_engine_manager()
	var eval_cp = eng.eval_score_cp if eng else 0
	var best_move = eng.best_move_uci if eng else ""
	var pv = eng.pv_line if eng else []

	ask_coach(fen, last_move_san, eval_cp, best_move, pv, query_text, extra_context)

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
   - 🎯 **Diagnostic** : En 1 phrase percutante, qualifie l'impact du coup joué et résume l'état de l'évaluation du point de vue du camp conseillé (%s).
   - 💡 **Analyse & Réfutation** : En 1 ou 2 phrases concises, explique pourquoi ce coup est bon ou mauvais, ce qu'il permet ou néglige, et détaille le mécanisme de la variante calculée par le moteur (PV).
   - 📌 **Plan conseillé** : Donne 1 ou 2 conseils pratiques clairs et concrets pour guider le camp conseillé (%s).
4. RÈGLE D'OR DE LANGAGE NATUREL ET FLUIDITÉ ORALE :
   - Parle dans un langage NATUREL, fluide, vivant et oral, comme un vrai maître assis à côté du joueur.
   - Évite les tournures robotiques, les successions froides de coordonnées ou les styles télégraphiques.
   - Privilégie des phrases complètes, agréables à entendre et parfaites pour être restituées oralement par la synthèse vocale (ex: 'Ton Fou en g5 cloue dangereusement le Cavalier', 'Attention à la poussée e5 qui fissure ton centre').
   - Les coups et variantes doivent être intégrés naturellement dans le fil de la phrase avec leur sens humain.
5. RÈGLE D'OR DE CONCISION (LISIBILITÉ MOBILE) :
   - Sois ULTRA-CONCIS : 100 à 150 mots au total (format concis : 150 à 220 mots au total). Zéro bavardage ni politesse introductive. Va droit au but dès le premier mot.
   - Langue : Français soigné, direct, dynamique et motivant.
   - Notation : Notation algébrique standard (ex: 1. e4, 2... Cf6, 3. Fb5).
6. ACTIONS NATURELLES DÉCODÉES (AIDE AU CALCUL) :
   - Tous les coups d'échecs (dernier coup joué, meilleur coup recommandé et suite de coups calculée par Stockfish) te sont fournis DÉJÀ DÉCODÉS en actions humaines explicites (ex: 'Dame blanche en c3 prend la Tour noire en e3', 'Cavalier blanc se déplace de g1 en f3').
   - Appuie-toi sur ces actions déjà formulées pour expliquer les gains de matériel, les clouages, les fourchettes et les réfutations sans risque d'erreur sur l'identité des pièces ou des cases.
7. RÈGLE CRITIQUE D'ENTRÉE DIRECTE (ANTI-BROUILLON) :
   - Démarre DIRECTEMENT ton texte par la balise '🎯 **Diagnostic** :'.
   - INTERDICTION STRICTE : Ne commence JAMAIS par décoder l'échiquier rangée par rangée (aucun 'Rank 8:', 'Rank 7:', 'White Pawn...', etc.).
   - N'énumère pas la position : les pièces et coups utiles te sont déjà formulés en français dans la fiche technique. Concentre 100%% de ta réponse sur l'explication humaine des 3 rubriques.""" % [perspective_instruction, perspective_label, perspective_label]

	match personality:
		"blunder_hunter":
			system_prompt += "\n\nAdopte un ton direct, incisif et sans complaisance. Mets le doigt immédiatement sur la faille tactique, la sanction punitive et ce qui a été négligé."
		"kids_simple":
			system_prompt += "\n\nAdopte un ton très simple, amusant et imagé. Remplace le jargon technique par des métaphores visuelles concrètes ('le château du roi', 'le cavalier qui bondit au centre', 'la tour sur l'autoroute')."
		_:
			system_prompt += "\n\nAdopte un ton de mentor bienveillant, encourageant et constructif. Valorise les bonnes idées tout en expliquant les erreurs avec patience."

	var is_comeback = extra_context.get("prompt_type", "") == "comeback" or "remonter la pente" in user_question.to_lower()
	if is_comeback:
		system_prompt += "\n\n7. DIRECTIVE SPÉCIALE « REMONTER LA PENTE » (SANS SPOILER LE COUP DIRECT) :\n" \
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
- **Position FEN (Référence)** : `%s` (inutile de décoder les rangées, utilise directement les actions ci-dessous)
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

	# T1.4 — Motifs tactiques DÉTECTÉS LOCALEMENT (faits vérifiés, à expliquer et non à deviner).
	var motifs: Array = extra_context.get("motifs", [])
	if motifs is Array and not motifs.is_empty():
		var motif_labels: Array = []
		for motif in motifs:
			motif_labels.append(str(motif))
		user_prompt += "- **Motifs tactiques détectés (vérifiés par l'analyseur)** : %s. Utilise-les tels quels, ne les invente pas.\n" % ", ".join(motif_labels)

	# Extension de contexte : Séquence récente de coups (dynamique de jeu)
	var recent_moves_str = str(extra_context.get("recent_moves", ""))
	if recent_moves_str == "":
		var gc = _get_game_controller()
		if gc and gc.game and not gc.game.move_history.is_empty():
			var cur_ply = int(extra_context.get("ply_index", gc.current_ply_index))
			if cur_ply >= 0:
				var start_ply = maxi(0, cur_ply - 7)
				var moves_tokens: Array[String] = []
				for p in range(start_ply, cur_ply + 1):
					if p < gc.game.move_history.size():
						var mv = gc.game.move_history[p]
						var info: Dictionary = gc.game.ply_info(p)
						var num: int = info["move_number"]
						if info["is_white"]:
							moves_tokens.append("%d. %s" % [num, mv.san])
						else:
							if p == start_ply:
								moves_tokens.append("%d... %s" % [num, mv.san])
							else:
								moves_tokens.append(mv.san)
				if not moves_tokens.is_empty():
					recent_moves_str = " ".join(moves_tokens)
	if recent_moves_str != "":
		user_prompt += "- **Enchaînement récent des coups** : %s\n" % recent_moves_str

	# Extension de contexte : Détection d'ouverture
	var opening_name = str(extra_context.get("opening_name", ""))
	if opening_name == "":
		var gc_op = _get_game_controller()
		if gc_op and gc_op.game and gc_op.game.pgn_headers.has("Opening"):
			opening_name = str(gc_op.game.pgn_headers["Opening"])
	if opening_name != "":
		user_prompt += "- **Ouverture répertoriée** : %s\n" % opening_name

	# Extension de contexte : Dynamique récente d'évaluation
	if cp_loss > 150:
		user_prompt += "- **Dynamique récente** : Choc tactique brutal (perte de %.2f pions sur ce coup)\n" % (cp_loss / 100.0)
	elif cp_loss > 40:
		user_prompt += "- **Dynamique récente** : Légère dégradation de la position (imprécision)\n"
	elif abs(eval_cp) <= 25:
		user_prompt += "- **Dynamique récente** : Équilibre stratégique soutenu et haute tension\n"
	else:
		user_prompt += "- **Dynamique récente** : Trajectoire stable\n"

	user_prompt += "\n---\n"
	if user_question != "":
		user_prompt += "### 💬 QUESTION DU JOUEUR :\n\"%s\"\n\nRéponds précisément à la question en t'appuyant rigoureusement sur les données objectives ci-dessus." % user_question
	else:
		user_prompt += "### 🎯 MISSION DU COACH :\nAnalyse le coup joué, explique pourquoi le meilleur coup recommandé par Stockfish est supérieur et quel est le plan stratégique conseillé pour la suite."

	user_prompt += "\n\n⚠️ DIRECTIVE DE RESTITUTION STRICTE :\n" \
		+ "- Démarre DIRECTEMENT ton texte par '🎯 **Diagnostic** :'.\n" \
		+ "- Exprime-toi dans un style NATUREL, vivant, fluide et oral (idéal pour la synthèse vocale).\n" \
		+ "- INTERDICTION FORMELLE d'écrire un brouillon d'échiquier (pas de 'Rank 8', 'Rank 7', etc.).\n" \
		+ "- Respecte impérativement les 3 rubriques Markdown : 🎯 **Diagnostic**, 💡 **Analyse & Réfutation**, 📌 **Plan conseillé** (100 à 180 mots au total)."

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

## Détecte la phase de jeu (Ouverture, Milieu de jeu, Finale).
## Source unique : GamePhaseService (même définition que le rapport de partie, T1.3).
func _detect_game_phase(fen: String, move_number: int) -> String:
	var ply: int = maxi(0, move_number * 2 - 1)
	match GamePhaseService.phase_for(fen, ply, 0):
		"opening":
			return "Ouverture (Développement des pièces, contrôle du centre et mise en sécurité du roi)"
		"endgame":
			return "Finale (Activité des rois, poussée et promotion des pions passés)"
		_:
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

	var active_model_id = _get_setting("active_model_id", "openrouter/free")
	active_query_model_id = active_model_id

	var model_info = _find_model(active_model_id)
	var provider = model_info.get("provider", "openrouter")

	match provider:
		"native_slm":
			_request_native_slm(prompt_data, model_info)
		"ollama":
			_request_local_ollama(prompt_data, model_info)
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
	_send_http_request(url, headers, body, "SLM Local")

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
	_send_http_request(base_url, headers, body, "Ollama Local")

func _request_openrouter(prompt_data: Dictionary, model_info: Dictionary) -> void:
	var key = str(_get_setting("api_key_openrouter", "")).strip_edges()
	var model_id = model_info.get("id", "openrouter/free")
	var is_free = bool(model_info.get("free_tier", false)) or model_id.ends_with(":free") or model_id == "openrouter/free"

	# Si aucune clé n'est renseignée et qu'un modèle payant est sélectionné
	if key == "" and not is_free:
		_fallback_offline_explanation("OpenRouter")
		return

	var cat = _get_catalog()
	var is_reasoning = false
	if cat and cat.has_method("is_reasoning_model"):
		is_reasoning = cat.is_reasoning_model(model_id)
	else:
		var low = model_id.to_lower()
		is_reasoning = (
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

	var url = "https://openrouter.ai/api/v1/chat/completions"
	var body_dict = {
		"model": model_id,
		"messages": [
			{"role": "system", "content": prompt_data.get("system", "")},
			{"role": "user", "content": prompt_data.get("user", "")}
		],
		"max_tokens": 3000 if is_reasoning else 1800,
		"temperature": 0.3
	}

	if is_reasoning:
		# Configuration normalisée OpenRouter pour canaliser la réflexion sans débordement
		body_dict["reasoning"] = {
			"effort": "low",
			"exclude": false
		}
		body_dict["include_reasoning"] = true

	var body = JSON.stringify(body_dict)
	var headers = [
		"Content-Type: application/json",
		"HTTP-Referer: https://rodchessxd.app",
		"X-Title: RodChessXD"
	]
	if key != "":
		headers.append("Authorization: Bearer " + key)

	_send_http_request(url, headers, body, "OpenRouter")

func _request_groq(prompt_data: Dictionary, model_info: Dictionary) -> void:
	_request_openrouter(prompt_data, model_info)

func _request_gemini(prompt_data: Dictionary, model_info: Dictionary) -> void:
	_request_openrouter(prompt_data, model_info)

func _request_deepseek(prompt_data: Dictionary, model_info: Dictionary) -> void:
	_request_openrouter(prompt_data, model_info)

func _request_openai(prompt_data: Dictionary, model_info: Dictionary) -> void:
	_request_openrouter(prompt_data, model_info)

func _request_anthropic(prompt_data: Dictionary, model_info: Dictionary) -> void:
	_request_openrouter(prompt_data, model_info)

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
	reply += "🔑 **Pour activer les analyses en langage naturel avec [b]OpenRouter[/b]** (100%% gratuit, 0 € sans carte bancaire) :\n\n"
	reply += "1. Cliquez sur le badge [b]⚡ Modèle[/b] du Coach en haut (ou sur ⚙️ Paramètres).\n"
	reply += "2. Obtenez votre clé universelle en 30 secondes sur [b]https://openrouter.ai/keys[/b]\n"
	reply += "3. Collez-la dans le champ [i]Clé OpenRouter[/i] et testez-la en 1 clic !\n\n"
	reply += "💡 *Astuce : Vous pouvez aussi sélectionner un modèle 100% gratuit (:free) ou un SLM local hors-ligne (ex: Ollama).* "

	# 1. Archivage dans DatabaseManager pour le mode local
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
				"model_id": "stockfish_offline",
				"provider": provider_name,
				"user_question": last_query_context.get("user_question", ""),
				"response_text": reply.strip_edges(),
				"elapsed_sec": 0.05,
				"cost_label": "Mode Stockfish Local"
			}
			dm.add_coach_analysis(gid, coach_record)

	coach_response_received.emit(reply)
	coach_response_with_meta.emit(reply, "Mode Stockfish Local", 0.05)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var elapsed = (Time.get_ticks_msec() / 1000.0) - current_query_start_time

	if result != HTTPRequest.RESULT_SUCCESS:
		var err_name = "Erreur réseau inconnue"
		match result:
			HTTPRequest.RESULT_CANT_RESOLVE:
				err_name = "Résolution DNS impossible (vérifiez la connexion internet)"
			HTTPRequest.RESULT_CANT_CONNECT:
				err_name = "Impossible d'établir la connexion avec le serveur distant"
			HTTPRequest.RESULT_CONNECTION_ERROR:
				err_name = "Interruption ou instabilité de la connexion réseau"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				err_name = "Échec de négociation sécurisée TLS/SSL"
			HTTPRequest.RESULT_NO_RESPONSE:
				err_name = "Le serveur n'a renvoyé aucune réponse"
			HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
				err_name = "Taille maximale de réponse dépassée"
			HTTPRequest.RESULT_REQUEST_FAILED:
				err_name = "La requête HTTP a échoué"
			HTTPRequest.RESULT_TIMEOUT:
				err_name = "Délai d'attente dépassé (Timeout : le serveur IA met trop de temps à répondre)"
		coach_error.emit("Échec réseau (%s, code résultat %d)." % [err_name, result])
		return

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
		elif text.strip_edges() != "":
			err_detail = text.strip_edges().substr(0, 300)

		var msg = ""
		match response_code:
			401:
				msg = "Erreur HTTP 401 (Authentification requise) :\nClé API manquante, invalide ou expirée."
				if err_detail != "":
					msg += "\n\nMessage renvoyé par le fournisseur :\n" + err_detail
				msg += "\n\n👉 Cliquez sur le badge '⚡' du Coach (ou ⚙️ Paramètres) pour renseigner votre clé API valide."
			402:
				msg = "Erreur HTTP 402 (Crédits requis) :\nSolde insuffisant ou carte requise pour ce modèle payant."
				if err_detail != "":
					msg += "\n\nMessage du fournisseur :\n" + err_detail
			403:
				msg = "Erreur HTTP 403 (Accès refusé) :\nCe modèle ou ce point de terminaison n'est pas autorisé pour votre clé ou votre région."
				if err_detail != "":
					msg += "\n\nMessage du fournisseur :\n" + err_detail
			404:
				msg = "Erreur HTTP 404 (Modèle introuvable) :\nLe modèle '%s' n'existe pas ou a été retiré chez le fournisseur." % active_query_model_id
				if err_detail != "":
					msg += "\n\nDétail :\n" + err_detail
			429:
				msg = "Erreur HTTP 429 (Trop de requêtes / Quota temporaire atteint) :\nLe fournisseur IA limite la cadence des questions sur les modèles gratuits."
				if err_detail != "":
					msg += "\n\nMessage du fournisseur :\n" + err_detail
				msg += "\n\n👉 Patientez 5 à 10 secondes avant de relancer un prompt, ou sélectionnez un autre modèle gratuit dans le sélecteur (badge ⚡ en haut)."
			500, 502, 503, 504:
				msg = "Erreur HTTP %d (Panne ou surcharge du serveur IA) :\nLe service distant est temporairement indisponible." % response_code
				if err_detail != "":
					msg += "\n\nMessage du serveur :\n" + err_detail
				msg += "\n\n👉 Réessayez dans un court instant ou testez un autre modèle."
			_:
				msg = "Le serveur IA a répondu avec l'erreur HTTP %d." % response_code
				if err_detail != "":
					msg += "\n\nDétail :\n" + err_detail
		coach_error.emit(msg)
		return

	var text = body.get_string_from_utf8()
	var json = JSON.parse_string(text)
	if not json:
		var raw_prev = text.strip_edges().substr(0, 300)
		coach_error.emit("Réponse JSON invalide reçue du modèle.\nContenu reçu :\n%s" % raw_prev)
		return

	var answer = ""
	var reasoning_text = ""
	var finish_reason = ""

	# Parsing selon le format OpenRouter / OpenAI
	if json.has("choices") and json["choices"].size() > 0:
		var choice = json["choices"][0]
		finish_reason = str(choice.get("finish_reason", ""))
		if choice.has("message"):
			var msg_obj = choice["message"]
			if msg_obj.has("content") and msg_obj["content"] != null:
				answer = str(msg_obj["content"])
			if msg_obj.has("reasoning") and msg_obj["reasoning"] != null:
				reasoning_text = str(msg_obj["reasoning"]).strip_edges()
			elif msg_obj.has("reasoning_content") and msg_obj["reasoning_content"] != null:
				reasoning_text = str(msg_obj["reasoning_content"]).strip_edges()
	elif json.has("candidates") and json["candidates"].size() > 0: # Gemini direct
		var cand = json["candidates"][0]
		finish_reason = str(cand.get("finishReason", ""))
		if cand.has("content") and cand["content"].has("parts") and cand["content"]["parts"].size() > 0:
			answer = str(cand["content"]["parts"][0].get("text", ""))
	elif json.has("content") and json["content"] is Array and json["content"].size() > 0: # Anthropic direct
		answer = str(json["content"][0].get("text", ""))
	elif json.has("response"): # Ollama SLM
		answer = str(json["response"])

	# Détection et extraction des balises de réflexion (<think>, <thought>, etc.)
	var split_think = extract_reasoning_from_text(answer)
	if split_think.reasoning != "":
		if reasoning_text == "":
			reasoning_text = split_think.reasoning
		else:
			reasoning_text += "\n" + split_think.reasoning
		answer = split_think.content

	# Détection et extraction d'un éventuel brouillon FEN parasite (ex: 'Rank 8: ...') avant le 🎯 Diagnostic
	var diag_pos = answer.find("🎯")
	if diag_pos > 0:
		var preamble = answer.substr(0, diag_pos).strip_edges()
		if preamble.contains("Rank ") or preamble.contains("Pawn ") or preamble.contains("piece") or preamble.length() > 60:
			if reasoning_text == "":
				reasoning_text = preamble
			else:
				reasoning_text = (preamble + "\n\n" + reasoning_text).strip_edges()
			answer = answer.substr(diag_pos).strip_edges()

	# Récupération de secours si le modèle a été interrompu en pleine réflexion avant d'avoir écrit le contenu final
	var is_reasoning_only: bool = false
	if answer.strip_edges() == "" and reasoning_text != "":
		is_reasoning_only = true
		answer = "⚠️ *Le modèle a atteint sa limite de jetons pendant sa réflexion préliminaire. Voici sa réflexion brute :*\n\n" + reasoning_text
		reasoning_text = ""
	elif finish_reason == "length" and answer.strip_edges() != "":
		if not answer.ends_with(".") and not answer.ends_with("!") and not answer.ends_with("?"):
			answer += "\n\n*(Analyse écourtée par la limite de jetons du modèle)*"

	if answer != "":
		session_queries_count += 1
		var model_info = _find_model(active_query_model_id)
		var cat = _get_catalog()
		var cost_info = cat.get_cost_estimate(model_info) if cat else {}
		var query_usd: float = cost_info.get("per_query_usd", 0.0)
		session_estimated_cost_usd += query_usd

		var cost_label: String = cost_info.get("label_per_query", "Gratuit")

		# 1. ARCHIVAGE DANS DATABASEMANAGER (avec le raisonnement)
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
					"reasoning_text": reasoning_text.strip_edges(),
					"elapsed_sec": elapsed,
					"cost_label": cost_label
				}
				dm.add_coach_analysis(gid, coach_record)

		# 2. ÉMISSION DES SIGNAUX
		coach_response_received.emit(answer.strip_edges())
		coach_response_with_meta.emit(answer.strip_edges(), cost_label, elapsed)
		coach_response_detailed.emit(answer.strip_edges(), reasoning_text.strip_edges(), cost_label, elapsed)

		# 3. RESTITUTION ORALE (SI DEMANDÉE)
		var extra = last_query_context.get("extra_context", {})
		if extra.get("request_audio", false):
			if is_reasoning_only:
				coach_error.emit("Le modèle '%s' a épuisé ses jetons pendant sa réflexion préliminaire sans formuler de conseil final.\n\n💡 Conseils :\n• Choisissez un modèle plus direct ou plus véloce (ex: Google Gemini 2.5 Flash, DeepSeek V3) via le sélecteur de modèle.\n• Les modèles à réflexion (thinking) nécessitent parfois davantage de jetons pour conclure." % active_query_model_id)
			else:
				speak_text(answer.strip_edges())
	else:
		if finish_reason == "length":
			coach_error.emit("Le modèle '%s' a atteint sa limite de jetons ('finish_reason: length') avant de produire sa réponse.\n\n💡 Conseil : Choisissez un modèle plus véloce (ex: Google Gemini 2.5 Flash, DeepSeek V3) ou une question plus ciblée." % active_query_model_id)
		else:
			var raw_preview = text.strip_edges().substr(0, 350)
			coach_error.emit("Impossible d'extraire le texte de la réponse du modèle.\nRéponse brute reçue du serveur :\n%s" % raw_preview)

## Extrait et sépare les balises de réflexion (<think>, <thought>, etc.) du texte d'analyse final,
## y compris lorsque la balise fermante a été tronquée par la limite de tokens.
static func extract_reasoning_from_text(raw_text: String) -> Dictionary:
	var answer = raw_text
	var reasoning_text = ""

	var tags = [
		["<think>", "</think>"],
		["<thought>", "</thought>"],
		["<thinking>", "</thinking>"],
		["[THINKING]", "[/THINKING]"]
	]

	for pair in tags:
		var open_tag: String = pair[0]
		var close_tag: String = pair[1]

		if open_tag in answer:
			if close_tag in answer:
				var start_idx = answer.find(open_tag)
				var end_idx = answer.find(close_tag)
				if end_idx > start_idx:
					var extracted_think = answer.substr(start_idx + open_tag.length(), end_idx - (start_idx + open_tag.length())).strip_edges()
					if reasoning_text == "":
						reasoning_text = extracted_think
					else:
						reasoning_text += "\n" + extracted_think
					answer = (answer.substr(0, start_idx) + answer.substr(end_idx + close_tag.length())).strip_edges()
			else:
				# Balise ouvrante présente mais JAMAIS fermée (coupure par limite de tokens)
				var start_idx = answer.find(open_tag)
				var unclosed_think = answer.substr(start_idx + open_tag.length()).strip_edges()
				if reasoning_text == "":
					reasoning_text = unclosed_think
				else:
					reasoning_text += "\n" + unclosed_think
				answer = answer.substr(0, start_idx).strip_edges()

	return {
		"content": answer,
		"reasoning": reasoning_text
	}

# --- SYNTHÈSE VOCALE (TEXT-TO-SPEECH) OPENROUTER ---

## Nettoie le texte Markdown et les symboles pour une diction vocale fluide et naturelle.
## Coupe proprement à la fin d'une phrase complète avant max_chars pour respecter la limite du fournisseur TTS.
static func clean_text_for_speech(text: String, max_chars: int = 1500) -> String:
	var t = text
	# Si le texte est un avertissement de limite de réflexion brute sans conseil final, ne rien vocaliser
	if t.begins_with("⚠️ *Le modèle a atteint sa limite de jetons") or t.begins_with("⚠️ Le modèle a atteint sa limite"):
		return ""

	# Retirer les éventuelles balises de réflexion résiduelles
	var split_think = extract_reasoning_from_text(t)
	t = split_think.content

	# Normaliser la notation des coups d'échecs pour une prononciation naturelle (avant le nettoyage Markdown de #)
	t = t.replace("O-O-O", "Grand roque").replace("0-0-0", "Grand roque")
	t = t.replace("O-O", "Petit roque").replace("0-0", "Petit roque")
	t = t.replace("x", " prend ")
	t = t.replace("#", " échec et mat")
	t = t.replace("+", " échec")

	# Supprimer les en-têtes Markdown et le gras / italique
	t = t.replace("**", "").replace("*", "")
	t = t.replace("###", "").replace("##", "").replace("#", "")
	t = t.replace("`", "")
	t = t.replace("- ", " ")
	t = t.replace("_", " ")

	# Remplacer les rubriques types par des transitions vocales douces
	t = t.replace("Diagnostic :", "Diagnostic.")
	t = t.replace("Analyse & Réfutation :", "Analyse.")
	t = t.replace("Plan conseillé :", "Plan conseillé.")

	# Supprimer les emojis (plages Unicode communes)
	var regex = RegEx.new()
	regex.compile("[\\x{1F300}-\\x{1F9FF}|\\x{2600}-\\x{26FF}|\\x{2700}-\\x{27BF}]")
	t = regex.sub(t, "", true)

	# Normaliser les sauts de ligne et espaces
	t = t.replace("\r\n", "\n").replace("\r", "\n")
	t = t.replace("\n\n", ". ").replace("\n", ". ")
	while ".." in t:
		t = t.replace("..", ".")
	while "  " in t:
		t = t.replace("  ", " ")

	t = t.strip_edges()

	# Troncature propre à la fin d'une phrase complète si le texte dépasse max_chars
	if max_chars > 0 and t.length() > max_chars:
		var slice_candidate = t.substr(0, max_chars)
		var last_punct = -1
		for p in [". ", "! ", "? ", ".", "!", "?"]:
			var idx = slice_candidate.rfind(p)
			if idx > last_punct:
				last_punct = idx + (1 if not p.ends_with(" ") else 0)
		if last_punct > 150: # Au moins une phrase significative
			t = slice_candidate.substr(0, last_punct + 1).strip_edges()
		else:
			# Fallback sur le dernier espace
			var last_space = slice_candidate.rfind(" ")
			if last_space > 0:
				t = slice_candidate.substr(0, last_space).strip_edges() + "."
			else:
				t = slice_candidate.strip_edges() + "."

	return t

## Synthétise et prononce oralement le texte (100% local via DisplayServer ou cloud optionnel)
func speak_text(text: String, voice_gender: String = "") -> void:
	stop_speech()

	# Respect strict du réglage sonore global
	if not bool(_get_setting("sound_enabled", true)):
		return

	var clean_text = clean_text_for_speech(text)
	if clean_text.is_empty():
		return

	var gender = voice_gender
	if gender == "":
		gender = str(_get_setting("coach_voice_gender", "female"))

	var tts_model = str(_get_setting("coach_tts_model", "local_system")).strip_edges()
	if tts_model == "":
		tts_model = "local_system"

	# --- 1. MODE 100% LOCAL (DisplayServer) ---
	if tts_model == "local_system" or tts_model == "local":
		if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
			var voice_id = _select_local_voice_id(gender)
			if voice_id == "":
				# Si aucune voix n'est trouvée pour la langue, essayer la première voix disponible
				var any_voices = DisplayServer.tts_get_voices()
				if any_voices.size() > 0:
					voice_id = str(any_voices[0].get("id", ""))

			if voice_id != "":
				var vol = int(clamp(_get_setting("sound_volume", 0.8) * 100.0, 10.0, 100.0))
				_active_local_utterance_generation += 1
				DisplayServer.tts_speak(clean_text, voice_id, vol, 1.0, 1.0)
				is_speaking = true
				coach_speech_started.emit()
				return

			coach_speech_error.emit("Aucune voix de synthèse vocale locale n'a été détectée sur votre appareil.")
			return
		else:
			coach_speech_error.emit("La synthèse vocale locale n'est pas supportée par ce système d'exploitation.")
			return

	# --- 2. MODE CLOUD OPTIONNEL (ex: deepgram/flux-tts:free) ---
	var key = str(_get_setting("api_key_openrouter", "")).strip_edges()
	if key == "":
		coach_speech_error.emit("Une clé API OpenRouter est requise pour le moteur vocal distant.")
		return

	var url = "https://openrouter.ai/api/v1/audio/speech"
	var body_dict = {
		"model": tts_model,
		"input": clean_text,
		"response_format": "mp3"
	}

	if tts_model.contains("flux-tts"):
		var voice_name = "flux-marcelo-en" if gender == "male" else "flux-elise-en"
		body_dict["voice"] = voice_name
	elif tts_model.contains("aura-2"):
		var voice_name = "aura-2-hector-fr" if gender == "male" else "aura-2-agathe-fr"
		body_dict["voice"] = voice_name

	var body = JSON.stringify(body_dict)
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + key,
		"HTTP-Referer: https://rodchessxd.app",
		"X-Title: RodChessXD"
	]

	if tts_http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		tts_http_client.cancel_request()

	var err = tts_http_client.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		coach_speech_error.emit("Impossible d'initialiser la synthèse vocale distante (erreur %d)." % err)

## Sélectionne la meilleure voix système locale en fonction de la langue et du genre (Féminin/Masculin)
func _select_local_voice_id(gender: String) -> String:
	var all_voices = DisplayServer.tts_get_voices()
	if all_voices.is_empty():
		return ""

	var fr_candidates: Array[Dictionary] = []
	for v in all_voices:
		var lang = str(v.get("language", "")).to_lower()
		var v_id = str(v.get("id", "")).to_lower()
		var v_name = str(v.get("name", "")).to_lower()
		if lang.begins_with("fr") or "fr_fr" in lang or "fr-fr" in lang or "frfr" in v_id or "french" in v_name or "fr" in v_name:
			fr_candidates.append(v)

	var pool = fr_candidates if not fr_candidates.is_empty() else all_voices

	# Tri ou filtrage par genre
	for c in pool:
		var name_id = (str(c.get("name", "")) + " " + str(c.get("id", ""))).to_lower()
		if gender == "male":
			if "paul" in name_id or "thomas" in name_id or "nicolas" in name_id or "male" in name_id or "homme" in name_id or "hector" in name_id or "claude" in name_id or "david" in name_id:
				return str(c.get("id", ""))
		else: # female
			if "hortense" in name_id or "julie" in name_id or "audrey" in name_id or "amelie" in name_id or "female" in name_id or "femme" in name_id or "agathe" in name_id or "virginie" in name_id:
				return str(c.get("id", ""))

	# Si aucun genre spécifique n'est matché, retourner le premier candidat de la langue
	return str(pool[0].get("id", ""))

# --- RAPPELS TTS NATIFS (DisplayServer) ---

func _on_local_tts_started(_utterance_id: int) -> void:
	if not is_speaking:
		is_speaking = true
		coach_speech_started.emit()

func _on_local_tts_ended(_utterance_id: int) -> void:
	if is_speaking:
		is_speaking = false
		coach_speech_finished.emit()

func _on_local_tts_canceled(_utterance_id: int) -> void:
	# Ignore les annulations différées issues d'énonciations précédentes
	if is_speaking:
		is_speaking = false
		coach_speech_finished.emit()

# --- RAPPELS TTS DISTANT (HTTPRequest) ---

func _on_tts_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		coach_speech_error.emit("Échec de connexion au service vocal OpenRouter (code %d)." % result)
		return

	if response_code != 200:
		var err_detail = body.get_string_from_utf8().strip_edges().substr(0, 300)
		coach_speech_error.emit("Erreur lors de la génération vocale (HTTP %d) :\n%s" % [response_code, err_detail])
		return

	if body.is_empty():
		coach_speech_error.emit("Le service vocal n'a renvoyé aucun son.")
		return

	var stream = AudioStreamMP3.new()
	stream.data = body
	if stream.get_length() <= 0.0:
		coach_speech_error.emit("Impossible de décoder le fichier audio MP3 de la voix.")
		return

	audio_player.stream = stream
	audio_player.play()
	is_speaking = true
	coach_speech_started.emit()

func _on_audio_player_finished() -> void:
	is_speaking = false
	coach_speech_finished.emit()

func stop_speech() -> void:
	_active_local_utterance_generation += 1

	# 1. Arrêt du TTS local DisplayServer
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()

	# 2. Arrêt du lecteur audio MP3 distant
	if is_instance_valid(audio_player) and audio_player.playing:
		audio_player.stop()

	if is_speaking:
		is_speaking = false
		coach_speech_finished.emit()

	if is_instance_valid(tts_http_client) and tts_http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		tts_http_client.cancel_request()

