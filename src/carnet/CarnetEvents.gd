class_name CarnetEvents
extends RefCounted
## CarnetEvents.gd — LeCarnet, Étage 1 (§4.3 → §4.4.2 du plan).
##
## Couche SANS ÉTAT : transforme le signal brut du moteur (par coup) en « atomes »
## normalisés, étiquetés (9 familles) et notés (IS / IM). Ne connaît rien du joueur
## ni de l'historique : LeLive! et LeArena peuvent l'appeler en direct sans jamais
## toucher au carnet d'entraînement.
##
## Invariant : toutes les sorties sont des fonctions pures du dictionnaire d'entrée
## (aucun hasard, aucun réseau, aucun LLM). Un composant manquant vaut 0 : aucune
## surprise n'est jamais inventée.
##
## Contrat d'entrée de `annotate()` (§4.2 « par coup candidat ») :
##   game_id, ply, date_iso, couleur ("white"/"black"), couleur_joueur (optionnel),
##   mode_analyse (bool, autorise LeLive! à annoter les deux camps),
##   san, uci, piece (type ChessPiece), quality (ChessMove.Quality),
##   cp_loss, perte_winpct, eval_avant, eval_apres, win_before, win_after,
##   meilleur_coup_uci, pv (Array[String] de la meilleure ligne, position avant),
##   fen_avant, fen_apres, phase, dans_la_theorie, eco, ply_sortie_theorie,
##   multipv (Array[{score_cp, move}] position avant), pv_apres (PV après le coup),
##   shallow_top_moves (Array[String], top 3 de la passe peu profonde de l'appelant),
##   winpct_by_depth (Dictionary {depth: win% du camp qui joue}),
##   clock_sec, clock_initial_sec, nb_plies_partie, nb_coups_legaux.

const POLARITE_NEGATIVE := CarnetConfig.POLARITE_NEGATIVE
const POLARITE_POSITIVE := CarnetConfig.POLARITE_POSITIVE
const POLARITE_CURIEUSE := CarnetConfig.POLARITE_CURIEUSE

# ── API publique ────────────────────────────────────────────────────────────────

## Identité stable d'un atome (§4.3) : idempotence et dédoublonnage.
static func event_id_for(game_id: String, ply: int, couleur: String) -> String:
	return HashUtil.sha1_hex("%s:%d:%s" % [game_id, ply, couleur])

## Annote UN coup. Retourne {} si le coup n'est pas notable (la grande majorité des
## coups), sinon un atome sérialisable (§4.13).
static func annotate(coup: Dictionary) -> Dictionary:
	var fen_avant: String = str(coup.get("fen_avant", ""))
	if fen_avant == "":
		return {}

	var ply: int = int(coup.get("ply", 0))
	var couleur: String = _color_key(coup)
	var is_white_mover: bool = couleur == "white"
	var game_id: String = str(coup.get("game_id", ""))
	var couleur_joueur: String = str(coup.get("couleur_joueur", ""))
	var mode_analyse: bool = bool(coup.get("mode_analyse", false))

	var quality: int = int(coup.get("quality", ChessMove.Quality.NONE))
	var perte: float = _f(coup.get("perte_winpct", coup.get("winpct_loss", 0.0)))
	var cp_loss: int = int(coup.get("cp_loss", 0))
	var eval_avant: int = int(coup.get("eval_avant", 0))
	var eval_apres: int = int(coup.get("eval_apres", 0))
	var win_before: float = _f(coup.get("win_before", MoveQualityService.win_for(eval_avant, is_white_mover)))
	var win_after: float = _f(coup.get("win_after", MoveQualityService.win_for(eval_apres, is_white_mover)))
	var uci: String = str(coup.get("uci", ""))
	var meilleur: String = str(coup.get("meilleur_coup_uci", ""))
	var pv: Array = coup.get("pv", []) if coup.get("pv", []) is Array else []
	var fen_apres: String = str(coup.get("fen_apres", ""))
	var dans_theorie: bool = bool(coup.get("dans_la_theorie", coup.get("is_theory", false)))
	var phase: String = str(coup.get("phase", ""))
	var eco: String = str(coup.get("eco", ""))
	var ply_sortie_theorie: int = int(coup.get("ply_sortie_theorie", -1))
	var nb_plies_partie: int = int(coup.get("nb_plies_partie", -1))

	# Nombre de coups légaux : un coup forcé n'est jamais une faute (§4.3 A.1.5).
	var nb_legaux: int = int(coup.get("nb_coups_legaux", -1))
	var move_info := _move_info(fen_avant, uci)
	if nb_legaux < 0:
		nb_legaux = _legal_count(fen_avant)

	var features := _features(fen_avant, couleur, move_info)
	var schemas := compute_schemas(coup, {
		"played": move_info,
		"feat_before": features,
	})
	features["schemas"] = schemas
	var is_obvious := bool(move_info.get("obvious", false))
	var non_obvious := not is_obvious

	var multipv: Array = coup.get("multipv", []) if coup.get("multipv", []) is Array else []
	var alt_winpcts := _alternative_winpcts(multipv, is_white_mover)
	var second_gap := _second_gap(alt_winpcts, win_before)
	var pluralite_count := _count_within(alt_winpcts, win_before, CarnetConfig.PLURALITE_TOL_WINPCT)

	var markers := _markers(coup, fen_avant, uci, meilleur, pv, is_white_mover,
			win_before, win_after, eval_avant, eval_apres, quality, second_gap, pluralite_count,
			non_obvious, ply, dans_theorie)

	var indices := _indices(fen_avant, couleur, win_before, win_after, eval_avant,
			second_gap, pluralite_count, markers, coup)
	var is_value: float = _weighted(CarnetConfig.IS_WEIGHTS, {
		"ecart_naturalite": 1.0 if non_obvious else 0.0,
		"sacrifice": 1.0 if bool(markers["sacrifice"]) else 0.0,
		"unicite": indices["unicite"],
		"profondeur": 1.0 if bool(markers["trouvaille_profonde"]) else 0.0,
		"nouveaute": 1.0 if bool(markers["nouveaute"]) else 0.0,
		"volatilite": indices["volatilite"],
	})
	var im_value: float = _weighted(CarnetConfig.IM_WEIGHTS, {
		"instabilite": indices["instabilite"],
		"pluralite": indices["pluralite"],
		"compensation": indices["compensation"],
		"tension": indices["tension"],
	})

	var classification := _classify(coup, quality, perte, dans_theorie, nb_legaux, nb_plies_partie,
			couleur_joueur, couleur, mode_analyse, markers, is_value, im_value)
	if classification.is_empty():
		return {}

	var polarites: Array = classification["polarites"]
	var polarite: String = classification["polarite"]
	var categorie: String = classification["categorie"]

	return {
		"event_id": event_id_for(game_id, ply, couleur),
		"game_id": game_id,
		"ply": ply,
		"date_iso": str(coup.get("date_iso", "")),
		"couleur": couleur,
		"polarite": polarite,
		"polarites": polarites,
		"categorie": categorie,
		"brillant": bool(categorie == "brillant"),
		"surprise": bool(is_value >= CarnetConfig.IS_SURPRISE and polarite != POLARITE_NEGATIVE),
		"mystere": bool(im_value >= CarnetConfig.IM_MYSTERE),
		"qualite": _quality_key(quality),
		"quality": quality,
		"perte_winpct": perte,
		"cp_loss": cp_loss,
		"eval_avant": eval_avant,
		"eval_apres": eval_apres,
		"win_before": win_before,
		"win_after": win_after,
		"meilleur_coup": meilleur,
		"coup_uci": uci,
		"position_avant": fen_avant,
		"position_apres": fen_apres,
		"phase": phase,
		"eco": eco,
		"type_finale": str(features["type_finale"]),
		"regime": _regime(win_before),
		"schemas": schemas,
		"tranche": _tranche(ply),
		"dans_theorie": dans_theorie,
		"IS": is_value,
		"IM": im_value,
		"marqueurs": markers,
		"indices": indices,
		"features": features,
		"merite": _merite(categorie, is_value, features),
	}

## Construit les atomes d'une partie depuis la sortie de `GameAnalyzer`.
## `game_data` : {id, date, moves:[{san, uci, is_white}], source, eco, ...}
## `analysis`  : {evaluations:[move_record], opening:{eco,name,out_of_book_ply}, theory_plies}
static func annotate_game(game_data: Dictionary, analysis: Dictionary, options: Dictionary = {}) -> Array:
	var out: Array = []
	var moves: Array = game_data.get("moves", []) if game_data.get("moves", []) is Array else []
	var evals: Array = analysis.get("evaluations", []) if analysis.get("evaluations", []) is Array else []
	if moves.is_empty() or evals.is_empty():
		return out

	var opening: Dictionary = analysis.get("opening", {}) if analysis.get("opening", {}) is Dictionary else {}
	var theory_plies: int = int(analysis.get("theory_plies", opening.get("out_of_book_ply", 0)))
	var nb_plies: int = moves.size()
	var couleur_joueur: String = str(options.get("couleur_joueur", game_data.get("couleur_joueur", "")))
	var mode_analyse: bool = bool(options.get("mode_analyse", false))
	var date_iso: String = str(game_data.get("date", game_data.get("date_iso", "")))
	var game_id: String = str(game_data.get("id", ""))

	var sim := ChessGame.new()
	sim.load_fen(ChessGame.INITIAL_FEN)
	var prev_fen: String = ChessGame.INITIAL_FEN
	var prev_score: int = 20
	var prev_best: String = ""

	for i in range(mini(moves.size(), evals.size())):
		var mv: Dictionary = moves[i]
		var rec: Dictionary = evals[i]
		var uci: String = str(rec.get("uci", mv.get("uci", "")))
		var is_white: bool = bool(rec.get("is_white", mv.get("is_white", i % 2 == 0)))
		var fen_before: String = prev_fen
		var played := sim.find_move(uci)
		if played == null:
			break
		sim.make_move(played)
		var fen_after: String = sim.get_fen()

		var quality: int = int(rec.get("quality", ChessMove.Quality.NONE))
		var phase: String = GamePhaseService.phase_for(fen_before, i, theory_plies)
		var best_before: String = str(rec.get("best_alternative", prev_best))
		if best_before == "":
			best_before = prev_best

		var coup := {
			"game_id": game_id,
			"ply": i,
			"date_iso": date_iso,
			"couleur": "white" if is_white else "black",
			"couleur_joueur": couleur_joueur,
			"mode_analyse": mode_analyse,
			"san": str(rec.get("san", mv.get("san", ""))),
			"uci": uci,
			"piece": int(played.piece),
			"quality": quality,
			"cp_loss": int(rec.get("loss_cp", 0)),
			"perte_winpct": _f(rec.get("winpct_loss", 0.0)),
			"eval_avant": prev_score,
			"eval_apres": int(rec.get("score_cp", prev_score)),
			"win_before": _f(rec.get("win_before", MoveQualityService.win_for(prev_score, is_white))),
			"win_after": _f(rec.get("win_after", MoveQualityService.win_for(int(rec.get("score_cp", prev_score)), is_white))),
			"meilleur_coup_uci": best_before,
			"pv": [],
			"fen_avant": fen_before,
			"fen_apres": fen_after,
			"phase": phase,
			"dans_la_theorie": bool(rec.get("is_theory", i < theory_plies)),
			"eco": str(opening.get("eco", game_data.get("eco", ""))),
			"ply_sortie_theorie": theory_plies,
			"nb_plies_partie": nb_plies,
		}
		var atom := annotate(coup)
		if not atom.is_empty():
			out.append(atom)

		prev_fen = fen_after
		prev_score = int(rec.get("score_cp", prev_score))
		prev_best = str(rec.get("best_move", ""))

	return out

# ── Classification / polarité ────────────────────────────────────────────────────

static func _classify(
		_coup: Dictionary, quality: int, perte: float, dans_theorie: bool, nb_legaux: int,
		nb_plies_partie: int, couleur_joueur: String, couleur: String, mode_analyse: bool,
		markers: Dictionary, is_value: float, im_value: float) -> Dictionary:
	var polarites: Array = []

	# A.1 — Événement NÉGATIF (§4.3) : le coup du joueur qui coûte de la win%.
	var is_player_move := couleur_joueur == "" or couleur_joueur == couleur
	var is_fault_quality := quality in [ChessMove.Quality.INACCURACY, ChessMove.Quality.MISTAKE,
			ChessMove.Quality.BLUNDER, ChessMove.Quality.MISS]
	var long_enough := nb_plies_partie < 0 or nb_plies_partie >= CarnetConfig.MIN_PLIES_PARTIE
	var is_negative := is_player_move and is_fault_quality and perte >= CarnetConfig.WINPCT_INACCURACY \
			and not dans_theorie and nb_legaux > 1 and long_enough
	if is_negative:
		polarites.append(POLARITE_NEGATIVE)

	# A.2 — Événement POSITIF (§4.4.1) : bon coup + au moins un marqueur d'excellence.
	var is_good_quality := quality in [ChessMove.Quality.BEST, ChessMove.Quality.GREAT,
			ChessMove.Quality.BRILLIANT, ChessMove.Quality.EXCELLENT]
	var has_excellence := bool(markers["sacrifice"]) or bool(markers["coup_unique"]) \
			or bool(markers["trouvaille_profonde"]) or bool(markers["ressource_defensive"]) \
			or bool(markers["precision_critique"])
	var is_positive := is_good_quality and has_excellence and (is_player_move or mode_analyse)
	if is_positive:
		polarites.append(POLARITE_POSITIVE)

	# A.3 — Événement CURIEUX : surprise ou mystère, même sur un coup correct.
	var surprise := is_value >= CarnetConfig.IS_SURPRISE and not is_negative
	var mystere := im_value >= CarnetConfig.IM_MYSTERE
	if surprise or mystere:
		polarites.append(POLARITE_CURIEUSE)

	if polarites.is_empty():
		return {}

	var polarite: String = POLARITE_NEGATIVE if is_negative else (POLARITE_POSITIVE if is_positive else POLARITE_CURIEUSE)
	return {
		"polarites": polarites,
		"polarite": polarite,
		"categorie": _categorie(is_negative, is_positive, surprise, mystere, quality, markers),
	}

static func _categorie(is_negative: bool, is_positive: bool, surprise: bool, mystere: bool,
		quality: int, markers: Dictionary) -> String:
	if is_negative:
		return _quality_key(quality)
	if is_positive:
		var brilliant := quality == ChessMove.Quality.BRILLIANT \
				or (quality == ChessMove.Quality.GREAT and (bool(markers["sacrifice"]) or bool(markers["coup_unique"]))) \
				or bool(markers["sacrifice"])
		if brilliant:
			return "brillant"
		if bool(markers["trouvaille_profonde"]) or bool(markers["ressource_defensive"]) or bool(markers["coup_unique"]):
			return "trouvaille"
		if bool(markers["precision_critique"]):
			return "précis"
		return "bon"
	if surprise and mystere:
		return "surprise_mystere"
	if surprise:
		return "surprise"
	return "mystere"

static func _quality_key(q: int) -> String:
	match q:
		ChessMove.Quality.INACCURACY: return "imprécision"
		ChessMove.Quality.MISTAKE: return "erreur"
		ChessMove.Quality.BLUNDER: return "gaffe"
		ChessMove.Quality.MISS: return "occasion_manquée"
	return ""

# ── Marqueurs d'excellence (§4.4.1) ──────────────────────────────────────────────

static func _markers(coup: Dictionary, fen_avant: String, uci: String,
		meilleur: String, pv: Array, is_white: bool, win_before: float,
		win_after: float, eval_avant: int, eval_apres: int, quality: int, second_gap: float,
		pluralite_count: int, non_obvious: bool, ply: int, dans_theorie: bool) -> Dictionary:
	var sacrifice := _is_sacrifice(fen_avant, uci, pv, eval_avant, eval_apres, is_white, win_after)
	var is_best := uci != "" and uci == meilleur
	var unique := is_best and second_gap >= CarnetConfig.ONLY_MOVE_WINPCT

	var shallow_top: Array = coup.get("shallow_top_moves", []) if coup.get("shallow_top_moves", []) is Array else []
	var trouvaille := false
	if is_best and not shallow_top.is_empty():
		trouvaille = not (uci in shallow_top)

	var ressource := win_before <= 30.0 and unique and (win_after - win_before) >= CarnetConfig.ONLY_MOVE_WINPCT
	var precision := win_before >= CarnetConfig.VOLATILITE_EQ_MIN and win_before <= CarnetConfig.VOLATILITE_EQ_MAX \
			and is_best and pluralite_count <= 1 and second_gap >= CarnetConfig.ONLY_MOVE_WINPCT

	var nouveaute := false
	var ply_sortie: int = int(coup.get("ply_sortie_theorie", -1))
	if not dans_theorie and ply_sortie >= 0 and ply == ply_sortie and _is_good(quality):
		nouveaute = true

	return {
		"sacrifice": sacrifice,
		"coup_unique": unique,
		"trouvaille_profonde": trouvaille,
		"ressource_defensive": ressource,
		"precision_critique": precision,
		"nouveaute": nouveaute,
		"naturalite": 0.0 if non_obvious else 1.0,
	}

static func _is_good(q: int) -> bool:
	return q in [ChessMove.Quality.BEST, ChessMove.Quality.GREAT, ChessMove.Quality.BRILLIANT, ChessMove.Quality.EXCELLENT]

## Sacrifice LeCarnet (§4.4.1) : la balance matérielle du camp qui joue baisse de ≥ 2 pions
## dans la PV, sans que l'éval ne se dégrade au-delà de SAC_TOL_CP (ou en restant gagnante).
static func _is_sacrifice(fen_avant: String, uci: String, pv: Array, eval_avant: int, eval_apres: int,
		is_white: bool, win_after: float) -> bool:
	if fen_avant == "" or uci == "":
		return false
	var swing := _pv_material_swing(fen_avant, pv, is_white)
	if swing > -CarnetConfig.DEBALANCE_MAT:
		return false
	var mover_delta := _mover_cp_delta(eval_avant, eval_apres, is_white)
	return mover_delta >= -CarnetConfig.SAC_TOL_CP or win_after >= 70.0

# ── Indices de surprise / mystère (§4.4.2) ───────────────────────────────────────

static func _indices(fen_avant: String, couleur: String, win_before: float, win_after: float,
		eval_avant: int, second_gap: float, pluralite_count: int, markers: Dictionary,
		coup: Dictionary) -> Dictionary:
	# Volatilité : grand saut de win% uniquement si la position était équilibrée avant.
	var volatilite := 0.0
	if win_before >= CarnetConfig.VOLATILITE_EQ_MIN and win_before <= CarnetConfig.VOLATILITE_EQ_MAX:
		volatilite = clampf(absf(win_after - win_before) / CarnetConfig.VOLATILITE_DIV, 0.0, 1.0)

	# Unicité : écart de win% avec la 2e meilleure ligne.
	var unicite := 0.0
	if second_gap > CarnetConfig.NO_SECOND_LINE / 1000.0:
		unicite = clampf(second_gap / CarnetConfig.NATURALITE_DIV, 0.0, 1.0)

	# Instabilité : dispersion de la win% entre profondeurs (passe courte vs profonde).
	var instabilite := 0.0
	var by_depth = coup.get("winpct_by_depth", {})
	if by_depth is Dictionary and by_depth.size() >= 2:
		var mn := 999.0
		var mx := -999.0
		for k in by_depth.keys():
			var v := _f(by_depth[k])
			mn = minf(mn, v)
			mx = maxf(mx, v)
		instabilite = clampf((mx - mn) / CarnetConfig.INSTABILITE_DIV, 0.0, 1.0)

	# Pluralité : beaucoup de coups se valent (« jungle »).
	var pluralite := clampf(float(pluralite_count - 1) / CarnetConfig.PLURALITE_DIV, 0.0, 1.0)

	# Compensation : déséquilibre matériel alors que l'éval reste serrée.
	var balance: int = int(markers.get("_balance", _material_balance_fen(fen_avant, couleur)))
	var compensation := 0.0
	if absi(balance) >= CarnetConfig.DEBALANCE_MAT and absi(eval_avant) <= 100:
		compensation = clampf(float(absi(balance)) / (CarnetConfig.COMPENSATION_DIV * 100.0), 0.0, 1.0)

	# Tension : chemin étroit — un seul (ou aucun) coup conserve le résultat.
	var tension := 0.0
	if pluralite_count <= 1:
		tension = 1.0
	elif pluralite_count == 2:
		tension = 0.5

	return {
		"volatilite": volatilite,
		"unicite": unicite,
		"instabilite": instabilite,
		"pluralite": pluralite,
		"compensation": compensation,
		"tension": tension,
	}

# ── Features contextuelles (§4.4 familles 1-9) ───────────────────────────────────

static func _features(fen_avant: String, couleur: String, move_info: Dictionary) -> Dictionary:
	var color := ChessPiece.PieceColor.WHITE if couleur == "white" else ChessPiece.PieceColor.BLACK
	var game := ChessGame.new()
	var ok := fen_avant != "" and game.load_fen(fen_avant)
	var balance := 0
	var type_finale := "aucune"
	var structure := {"doubles": 0, "isoles": 0, "arrieres": 0}
	var roi_roque := false
	var droits := false
	var mineures_dev := 0
	var piece_letter := _piece_letter(int(move_info.get("piece", ChessPiece.Type.NONE)))
	if ok:
		balance = _material_balance(game.board, color)
		if GamePhaseService.is_endgame_fen(fen_avant):
			type_finale = _endgame_type(game.board)
		structure = _pawn_structure(game.board, color)
		roi_roque = _king_castled(game.board, color)
		droits = (game.castle_k_white or game.castle_q_white) if color == ChessPiece.PieceColor.WHITE \
				else (game.castle_k_black or game.castle_q_black)
		mineures_dev = _minors_developed(game.board, color)
	return {
		"materiel": balance,
		"type_finale": type_finale,
		"structure": structure,
		"roi_roque": roi_roque,
		"droits_roque": droits,
		"mineures_developpees": mineures_dev,
		"piece_bougee": piece_letter,
		"balance": balance,
		"schemas": [],
	}

static func _piece_letter(t: int) -> String:
	match t:
		ChessPiece.Type.PAWN: return "P"
		ChessPiece.Type.KNIGHT: return "C"
		ChessPiece.Type.BISHOP: return "F"
		ChessPiece.Type.ROOK: return "T"
		ChessPiece.Type.QUEEN: return "D"
		ChessPiece.Type.KING: return "R"
	return ""

static func _regime(win_before: float) -> String:
	if win_before >= 70.0:
		return "en_avance"
	if win_before <= 30.0:
		return "en_retard"
	return "équilibré"

static func _tranche(ply: int) -> String:
	var n := ply + 1
	if n <= 10:
		return "1-10"
	if n <= 20:
		return "11-20"
	if n <= 30:
		return "21-30"
	if n <= 40:
		return "31-40"
	return "41+"

static func _merite(categorie: String, is_value: float, features: Dictionary) -> float:
	var level := 0.0
	match categorie:
		"brillant": level = 1.0
		"trouvaille": level = 0.8
		"précis": level = 0.6
		"bon": level = 0.4
		_: return 0.0
	var criticite := 1.0 - clampf(absf(float(features.get("materiel", 0))) / 900.0, 0.0, 1.0)
	return clampf(CarnetConfig.MERIT_BRILLIANCE * level + CarnetConfig.MERIT_SURPRISE * (is_value / 100.0)
			+ CarnetConfig.MERIT_CRITICITE * criticite, 0.0, 1.0)

# ── Schémas déterministes (§4.4 famille 7) ───────────────────────────────────────

## Schémas calculables depuis fen + PV moteur. Remplis sur l'atome par le ledger/live.
## `ctx` peut fournir `played` (sortie de `_move_info`) et `feat_before` (sortie de
## `_features`) déjà calculés par `annotate()` pour éviter de re-parser la position.
static func compute_schemas(coup: Dictionary, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	var fen_avant: String = str(coup.get("fen_avant", ""))
	var uci: String = str(coup.get("uci", ""))
	var meilleur: String = str(coup.get("meilleur_coup_uci", ""))
	var pv: Array = coup.get("pv", []) if coup.get("pv", []) is Array else []
	var pv_apres: Array = coup.get("pv_apres", []) if coup.get("pv_apres", []) is Array else []
	var fen_apres: String = str(coup.get("fen_apres", ""))
	var couleur: String = _color_key(coup)
	var is_white: bool = couleur == "white"
	var ply: int = int(coup.get("ply", 0))

	var played = ctx.get("played", null)
	if not (played is Dictionary):
		played = _move_info(fen_avant, uci)
	var best := _move_info(fen_avant, meilleur)
	if played.is_empty() or best.is_empty():
		return out

	var feat_before = ctx.get("feat_before", null)
	if not (feat_before is Dictionary):
		feat_before = _features(fen_avant, couleur, played)
	# Structure d'après : calculée une seule fois, uniquement pour une poussée de pion.
	var feat_after := {}
	if fen_apres != "" and int(played.get("piece", ChessPiece.Type.NONE)) == ChessPiece.Type.PAWN:
		feat_after = _features(fen_apres, couleur, played)

	# capture_ratée : le meilleur coup était une capture gagnante, le joueur n'a pas capturé.
	if bool(best.get("capture", false)) and not bool(played.get("capture", false)):
		if _pv_material_swing(fen_avant, pv, is_white) >= 100:
			out.append("capture_ratée")

	# échec_manqué : le meilleur coup donnait échec ou mat.
	if (bool(best.get("check", false)) or bool(best.get("mate", false))) \
			and not (bool(played.get("check", false)) or bool(played.get("mate", false))):
		out.append("échec_manqué")

	# gain_tactique_manqué : le meilleur coup force un gain matériel ≥ 2 pions dans la PV.
	if uci != meilleur and _pv_material_swing(fen_avant, pv, is_white) >= CarnetConfig.DEBALANCE_MAT:
		out.append("gain_tactique_manqué")

	# pièce_en_prise : après le coup joué, la meilleure réponse adverse gagne ≥ 2 pions.
	if fen_apres != "" and not pv_apres.is_empty():
		var opp_gain := _pv_material_swing(fen_apres, pv_apres, not is_white)
		if opp_gain >= CarnetConfig.DEBALANCE_MAT:
			out.append("piece_en_prise")

	# dame_sortie_tôt : dame jouée au ply ≤ 20 avant développement des mineures.
	if int(played.get("piece", ChessPiece.Type.NONE)) == ChessPiece.Type.QUEEN and ply + 1 <= 20:
		var dev := int(feat_before.get("mineures_developpees", 0))
		if dev < 2:
			out.append("dame_sortie_tôt")

	# structure_pions : poussée de pion créant un doublon / isolé / arrière.
	if not feat_after.is_empty():
		var before: Dictionary = feat_before.get("structure", {})
		var after: Dictionary = feat_after.get("structure", {})
		if _structure_worsened(before, after):
			out.append("structure_pions")

	# sécurité_roi : roi non roqué face à une dame adverse, ou poussée de pion devant le roi.
	if not bool(feat_before.get("roi_roque", false)):
		if _king_zone_weak(fen_avant, couleur, uci):
			out.append("sécurité_roi")

	# roi_non_roqué : droits de roque perdus sans avoir roqué au 12e coup.
	if ply + 1 >= 24 and not bool(feat_before.get("roi_roque", false)) \
			and not bool(feat_before.get("droits_roque", false)):
		out.append("roi_non_roqué")

	# pression_temps : faute avec très peu de temps (horloge disponible seulement).
	var clock := _f(coup.get("clock_sec", -1.0))
	var clock0 := _f(coup.get("clock_initial_sec", -1.0))
	if clock >= 0.0 and clock0 > 0.0 and clock <= 0.1 * clock0:
		out.append("pression_temps")

	return out

# ── Calculs matériels / structurels ──────────────────────────────────────────────

static func _material_for(board: Array, color: int) -> int:
	var total := 0
	for sq in range(64):
		var p: Dictionary = board[sq]
		if int(p.get("color", ChessPiece.PieceColor.NONE)) == color \
				and int(p.get("type", ChessPiece.Type.NONE)) != ChessPiece.Type.KING:
			total += int(ChessPiece.VALUES.get(int(p.get("type", ChessPiece.Type.NONE)), 0))
	return total

static func _material_balance(board: Array, color: int) -> int:
	var opp := ChessPiece.PieceColor.BLACK if color == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	return _material_for(board, color) - _material_for(board, opp)

static func _material_balance_fen(fen: String, couleur: String) -> int:
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return 0
	return _material_balance(game.board, ChessPiece.PieceColor.WHITE if couleur == "white" else ChessPiece.PieceColor.BLACK)

static func _endgame_type(board: Array) -> String:
	var has_queen := false
	var has_rook := false
	var has_minor := false
	var has_pawn := false
	for sq in range(64):
		match int(board[sq].get("type", ChessPiece.Type.NONE)):
			ChessPiece.Type.QUEEN: has_queen = true
			ChessPiece.Type.ROOK: has_rook = true
			ChessPiece.Type.BISHOP, ChessPiece.Type.KNIGHT: has_minor = true
			ChessPiece.Type.PAWN: has_pawn = true
	if has_queen:
		return "dames"
	if has_rook and not has_minor:
		return "tours"
	if has_minor and not has_rook:
		return "mineures"
	if has_pawn and not has_rook and not has_minor:
		return "pions"
	return "mixte"

static func _pawn_structure(board: Array, color: int) -> Dictionary:
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var ranks := []
	for i in range(8):
		ranks.append([])
	for sq in range(64):
		var p: Dictionary = board[sq]
		if int(p.get("color", ChessPiece.PieceColor.NONE)) == color \
				and int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.PAWN:
			var f := sq % 8
			var r := int(sq / 8)
			counts[f] += 1
			ranks[f].append(r)

	var doubles := 0
	var isoles := 0
	var arrieres := 0
	for f in range(8):
		if counts[f] > 1:
			doubles += counts[f] - 1
		if counts[f] > 0:
			var has_left := f > 0 and counts[f - 1] > 0
			var has_right := f < 7 and counts[f + 1] > 0
			if not has_left and not has_right:
				isoles += 1
			else:
				arrieres += _backward_count(ranks, f, color)
	return {"doubles": doubles, "isoles": isoles, "arrieres": arrieres}

## Approximation déterministe : un pion est arriéré si aucun pion ami des files
## adjacentes n'est au même rang ou derrière lui, et la file est au moins semi-ouverte.
static func _backward_count(ranks: Array, f: int, color: int) -> int:
	var count := 0
	var is_white := color == ChessPiece.PieceColor.WHITE
	for r in ranks[f]:
		var supported := false
		for nf in [f - 1, f + 1]:
			if nf < 0 or nf > 7:
				continue
			for nr in ranks[nf]:
				if is_white:
					if nr <= r:
						supported = true
						break
				else:
					if nr >= r:
						supported = true
						break
			if supported:
				break
		if not supported:
			count += 1
	return count

static func _structure_worsened(before: Dictionary, after: Dictionary) -> bool:
	return int(after.get("doubles", 0)) > int(before.get("doubles", 0)) \
			or int(after.get("isoles", 0)) > int(before.get("isoles", 0)) \
			or int(after.get("arrieres", 0)) > int(before.get("arrieres", 0))

static func _king_castled(board: Array, color: int) -> bool:
	var targets := [6, 2] if color == ChessPiece.PieceColor.WHITE else [62, 58]
	for sq in targets:
		var p: Dictionary = board[sq]
		if int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.KING \
				and int(p.get("color", ChessPiece.PieceColor.NONE)) == color:
			return true
	return false

static func _king_square(board: Array, color: int) -> int:
	for sq in range(64):
		var p: Dictionary = board[sq]
		if int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.KING \
				and int(p.get("color", ChessPiece.PieceColor.NONE)) == color:
			return sq
	return -1

## Sécurité du roi : roi non roqué avec une dame adverse, ou poussée de pion sur/à
## côté de la file du roi.
static func _king_zone_weak(fen: String, couleur: String, uci: String) -> bool:
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return false
	var color := ChessPiece.PieceColor.WHITE if couleur == "white" else ChessPiece.PieceColor.BLACK
	var opp := ChessPiece.PieceColor.BLACK if color == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	var ks := _king_square(game.board, color)
	if ks < 0:
		return false
	var king_file := ks % 8
	var enemy_queen := false
	for sq in range(64):
		var p: Dictionary = game.board[sq]
		if int(p.get("color", ChessPiece.PieceColor.NONE)) == opp \
				and int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.QUEEN:
			enemy_queen = true
			break
	if enemy_queen:
		return true
	# Poussée de pion devant / à côté du roi.
	if uci.length() >= 4:
		var from := ChessMove.coord_to_square(uci.substr(0, 2))
		var piece := game.get_piece(from)
		if int(piece.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.PAWN:
			var from_file := from % 8
			if absi(from_file - king_file) <= 1:
				return true
	return false

static func _minors_developed(board: Array, color: int) -> int:
	var count := 0
	var home := 0 if color == ChessPiece.PieceColor.WHITE else 7
	var start_files: Array[int] = [1, 2, 5, 6]
	for f in start_files:
		var sq: int = home * 8 + int(f)
		var p: Dictionary = board[sq]
		if int(p.get("type", ChessPiece.Type.NONE)) == ChessPiece.Type.NONE \
				or int(p.get("color", ChessPiece.PieceColor.NONE)) != color:
			count += 1
	return count

# ── Helpers coup / matériel ──────────────────────────────────────────────────────

static func _move_info(fen: String, uci: String) -> Dictionary:
	if fen == "" or uci == "":
		return {}
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return {}
	var mv := game.find_move(uci)
	if mv == null:
		return {}
	var mover := mv.color
	var opponent := ChessPiece.PieceColor.BLACK if mover == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	game.make_move(mv)
	var gives_check := game.is_in_check(opponent)
	var mate := gives_check and game.get_legal_moves(opponent).is_empty()
	var obvious := int(mv.captured_piece) != ChessPiece.Type.NONE or mv.promotion != ChessPiece.Type.NONE \
			or mv.is_castling or gives_check
	return {
		"piece": int(mv.piece),
		"color": mover,
		"capture": int(mv.captured_piece) != ChessPiece.Type.NONE,
		"promotion": mv.promotion != ChessPiece.Type.NONE,
		"castling": mv.is_castling,
		"check": gives_check,
		"mate": mate,
		"obvious": obvious,
	}

## Bilan matériel net du camp `is_white` sur les 8 premiers plies d'une PV.
static func _pv_material_swing(fen: String, pv: Array, is_white: bool) -> int:
	if fen == "" or pv.is_empty():
		return 0
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return 0
	var color := ChessPiece.PieceColor.WHITE if is_white else ChessPiece.PieceColor.BLACK
	var total := 0
	var steps := 0
	for token in pv:
		if steps >= 8:
			break
		var mv := game.find_move(str(token))
		if mv == null:
			break
		if int(mv.captured_piece) != ChessPiece.Type.NONE:
			var val := int(ChessPiece.VALUES.get(int(mv.captured_piece), 0))
			if int(mv.color) == color:
				total += val
			else:
				total -= val
		game.make_move(mv)
		steps += 1
	return total

## Delta (cp) de l'éval du point de vue du camp qui joue.
static func _mover_cp_delta(eval_avant: int, eval_apres: int, is_white: bool) -> int:
	return (eval_apres - eval_avant) if is_white else (eval_avant - eval_apres)

static func _legal_count(fen: String) -> int:
	if fen == "":
		return 2
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return 2
	return game.get_legal_moves().size()

## Win% (du camp qui joue) de chaque ligne MultiPV, meilleure en premier.
static func _alternative_winpcts(multipv: Array, is_white: bool) -> Array:
	var out: Array = []
	for line in multipv:
		if line is Dictionary:
			out.append(MoveQualityService.win_for(int(line.get("score_cp", 0)), is_white))
	return out

static func _second_gap(alt_winpcts: Array, win_before: float) -> float:
	if alt_winpcts.size() < 2:
		return float(CarnetConfig.NO_SECOND_LINE)
	return win_before - float(alt_winpcts[1])

static func _count_within(alt_winpcts: Array, win_before: float, tol: float) -> int:
	var count := 0
	for w in alt_winpcts:
		if win_before - float(w) <= tol:
			count += 1
	return count

static func _weighted(weights: Dictionary, values: Dictionary) -> float:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k]) * float(values.get(k, 0.0))
	return clampf(100.0 * total, 0.0, 100.0)

static func _color_key(coup: Dictionary) -> String:
	var c := str(coup.get("couleur", ""))
	if c == "white" or c == "black":
		return c
	if coup.has("is_white"):
		return "white" if bool(coup["is_white"]) else "black"
	return "white" if int(coup.get("ply", 0)) % 2 == 0 else "black"

static func _f(v) -> float:
	return float(v) if v != null else 0.0
