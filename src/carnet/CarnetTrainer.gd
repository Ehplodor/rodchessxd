class_name CarnetTrainer
extends RefCounted
## CarnetTrainer.gd — LeCarnet, Étage 3 (§4.8 → §4.11 du plan).
##
## Décide QUOI entraîner, QUAND et COMMENT : génération des drills depuis les preuves,
## répétition espacée SM-2, composition du plan du jour (LePlan), modèle de compétence
## (Élo-skill), écart théorie ↔ pratique, maîtrise, plateau, série/joker.
## Purement algorithmique : aucun LLM, aucun réseau. Déterministe à entrées égales.

# ── Génération des drills (§4.8) ─────────────────────────────────────────────────

## Génère les drills depuis les motifs compilés (Étage 2) et les atomes (Étage 1).
## Un drill = une preuve : position avant, réponse = meilleur coup, piège = coup joué.
static func generate_drills(atoms: Array, faiblesses: Array, forces: Array, curiosites: Array,
		_options: Dictionary = {}) -> Array:
	var by_id := {}
	for atom in atoms:
		if atom is Dictionary:
			by_id[str(atom.get("event_id", ""))] = atom

	var drills: Array = []
	var used_positions := {}

	# Drills de correction (faiblesses) — priorité à la gravité, puis à la récence.
	for motif in faiblesses:
		var proofs := _proofs_for(motif, by_id)
		proofs.sort_custom(func(a, b):
			var sa := float(a.get("perte_winpct", 0.0))
			var sb := float(b.get("perte_winpct", 0.0))
			if not is_equal_approx(sa, sb):
				return sa > sb
			var da := str(a.get("date_iso", ""))
			var db := str(b.get("date_iso", ""))
			if da != db:
				return da > db
			return str(a.get("event_id", "")) < str(b.get("event_id", ""))
		)
		var taken := 0
		for atom in proofs:
			if taken >= CarnetConfig.DRILLS_PER_MOTIF:
				break
			var drill := _make_drill(atom, motif, "correction", used_positions)
			if not drill.is_empty():
				drills.append(drill)
				taken += 1

	# Drills positifs / de curiosité (§4.8) — consolider une force, entretenir la motivation.
	for motif in forces + curiosites:
		var proofs := _proofs_for(motif, by_id)
		proofs.sort_custom(func(a, b):
			return float(a.get("merite", 0.0)) + float(a.get("IS", 0.0)) / 100.0 \
					> float(b.get("merite", 0.0)) + float(b.get("IS", 0.0)) / 100.0
		)
		var taken := 0
		for atom in proofs:
			if taken >= CarnetConfig.DRILLS_PER_MOTIF:
				break
			var drill := _make_drill(atom, motif, "curiosite", used_positions)
			if not drill.is_empty():
				drills.append(drill)
				taken += 1

	return drills

static func _proofs_for(motif: Dictionary, by_id: Dictionary) -> Array:
	var out: Array = []
	for id in motif.get("atomes", []):
		var atom = by_id.get(str(id), null)
		if atom is Dictionary:
			out.append(atom)
	return out

static func _make_drill(atom: Dictionary, motif: Dictionary, origine: String, used_positions: Dictionary) -> Dictionary:
	var position := str(atom.get("position_avant", ""))
	var best := str(atom.get("meilleur_coup", ""))
	if position == "" or best == "":
		return {}
	var side := str(atom.get("couleur", ""))
	var position_key := HashUtil.sha1_hex("%s|%s" % [position, side])
	if used_positions.has(position_key):
		return {}
	used_positions[position_key] = true

	var drill_type := _drill_type(atom, origine)
	var difficulte := _difficulty(atom)
	var event_id := str(atom.get("event_id", ""))
	var motif_key := "%s|%s" % [motif.get("famille", ""), motif.get("cle", "")]
	return {
		"drill_id": "dr_%s_%s" % [event_id.substr(0, 10), drill_type],
		"event_id": event_id,
		"motif": motif_key,
		"famille": str(motif.get("famille", "")),
		"dimension": _dimension_for(str(motif.get("famille", ""))),
		"polarite": str(atom.get("polarite", "")),
		"type": drill_type,
		"origine": origine,
		"position": position,
		"reponse_uci": best,
		"piege_uci": str(atom.get("coup_uci", "")),
		"pv": atom.get("pv", []) if atom.get("pv", []) is Array else [],
		"difficulte": difficulte,
		"game_id": str(atom.get("game_id", "")),
		"ply": int(atom.get("ply", -1)),
		"couleur": str(atom.get("couleur", "")),
		"date_iso": str(atom.get("date_iso", "")),
		"motif_score": float(motif.get("score", 0.0)),
		"gravite": float(atom.get("perte_winpct", 0.0)) / CarnetConfig.S_MAX \
				if str(atom.get("polarite", "")) == CarnetConfig.POLARITE_NEGATIVE else float(atom.get("merite", 0.0)),
		"contexte": "theorie" if origine == "curiosite" else "pratique",
		"srs": {
			"EF": CarnetConfig.EF_INIT,
			"intervalle": 0,
			"repetitions": 0,
			"lapses": 0,
			"echeance": "",
		},
		"derniere_note": -1,
		"reussites": 0,
		"maitrise": false,
	}

static func _drill_type(atom: Dictionary, origine: String) -> String:
	if origine == "curiosite":
		if bool(atom.get("mystere", false)):
			return "résous_le_mystère"
		return "trouve_la_brillance"
	if _best_is_forcing(str(atom.get("position_avant", "")), str(atom.get("meilleur_coup", ""))):
		return "trouve_le_coup"
	return "choix_binaire"

## Le meilleur coup est « forcé » s'il capture, donne échec/mat, promeut, ou force un gain.
static func _best_is_forcing(fen: String, best_uci: String) -> bool:
	if fen == "" or best_uci == "":
		return false
	var game := ChessGame.new()
	if not game.load_fen(fen):
		return false
	var mv := game.find_move(best_uci)
	if mv == null:
		return false
	if int(mv.captured_piece) != ChessPiece.Type.NONE or mv.promotion != ChessPiece.Type.NONE:
		return true
	var opponent := ChessPiece.PieceColor.BLACK if mv.color == ChessPiece.PieceColor.WHITE else ChessPiece.PieceColor.WHITE
	game.make_move(mv)
	return game.is_in_check(opponent)

## Difficulté (0-100) estimée par le moteur : écart à la 2e ligne, sacrifice, criticité.
static func _difficulty(atom: Dictionary) -> float:
	var markers: Dictionary = atom.get("marqueurs", {}) if atom.get("marqueurs", {}) is Dictionary else {}
	var second_gap := 0.0
	var indices: Dictionary = atom.get("indices", {}) if atom.get("indices", {}) is Dictionary else {}
	if bool(markers.get("coup_unique", false)):
		second_gap = CarnetConfig.ONLY_MOVE_WINPCT
	var d := 30.0 + 40.0 * clampf(second_gap / 40.0, 0.0, 1.0)
	if bool(markers.get("sacrifice", false)):
		d += 20.0
	d += 10.0 * clampf(float(atom.get("IM", 0.0)) / 100.0, 0.0, 1.0)
	d += 10.0 * clampf(float(indices.get("instabilite", 0.0)), 0.0, 1.0)
	return clampf(d, 0.0, 100.0)

static func _dimension_for(famille: String) -> String:
	match famille:
		"phase": return "phase"
		"type_finale": return "type_finale"
		"ouverture": return "ouverture"
		"regime": return "regime"
		"schema": return "registre"
	return famille

# ── Vérification d'une réponse (§4.8) ────────────────────────────────────────────

## Accepte la réponse si c'est le meilleur coup, ou si Stockfish local confirme une perte
## de win% ≤ WINPCT_TOL. `winpct_loss` est fourni par l'appelant (0 si non mesuré).
static func accept_answer(played_uci: String, reponse_uci: String, winpct_loss: float) -> bool:
	if played_uci != "" and played_uci == reponse_uci:
		return true
	return winpct_loss <= CarnetConfig.WINPCT_TOL

# ── Répétition espacée SM-2 (§4.9) ───────────────────────────────────────────────

## Applique une note 0-5 au drill et renvoie le drill mis à jour (échéance recalculée).
static func update_srs(drill: Dictionary, note: int, today_iso: String) -> Dictionary:
	note = clampi(note, 0, 5)
	var srs: Dictionary = drill.get("srs", {}).duplicate(true)
	var ef := float(srs.get("EF", CarnetConfig.EF_INIT))
	var rep := int(srs.get("repetitions", 0))
	var intervalle := int(srs.get("intervalle", 0))
	var lapses := int(srs.get("lapses", 0))

	if note < 3:
		rep = 0
		intervalle = 1
		ef = maxf(CarnetConfig.EF_MIN, ef - 0.2)
		lapses += 1
	else:
		rep += 1
		if rep == 1:
			intervalle = 1
		elif rep == 2:
			intervalle = 6
		else:
			intervalle = int(round(float(intervalle) * ef))
		var n := float(note)
		ef = clampf(ef + (0.1 - (5.0 - n) * (0.08 + (5.0 - n) * 0.02)), CarnetConfig.EF_MIN, CarnetConfig.EF_MAX)

	srs["EF"] = ef
	srs["repetitions"] = rep
	srs["intervalle"] = intervalle
	srs["lapses"] = lapses
	srs["echeance"] = add_days(today_iso, intervalle)
	drill["srs"] = srs
	drill["derniere_note"] = note
	if note >= 3:
		drill["reussites"] = int(drill.get("reussites", 0)) + 1
	return drill

# ── Modèle de compétence Élo-skill (§4.11 A) ────────────────────────────────────

## Met à jour une compétence (0-100) après un résultat de difficulté connue.
static func update_skill(state: Dictionary, difficulte: float, success: bool) -> Dictionary:
	var skill := float(state.get("skill", 50.0))
	var expected := 1.0 / (1.0 + pow(10.0, (difficulte - skill) / 400.0))
	var result := 1.0 if success else 0.0
	state["skill"] = clampf(skill + CarnetConfig.K_SKILL * (result - expected), 0.0, 100.0)
	state["n"] = int(state.get("n", 0)) + 1
	return state

## Écart théorie ↔ pratique (§4.11 B) : trois régimes pédagogiques.
static func ecart_theorie_pratique(competences: Array) -> Array:
	var out: Array = []
	for c in competences:
		if not (c is Dictionary):
			continue
		var skill_theorie := float(c.get("skill_theorie", -1.0))
		var skill_pratique := float(c.get("skill_pratique", -1.0))
		if skill_theorie < 0.0 or skill_pratique < 0.0:
			continue
		var ecart := skill_theorie - skill_pratique
		var regime := "acquis"
		if skill_theorie < 60.0 and skill_pratique < 60.0:
			regime = "ne_sait_pas"
		elif ecart >= CarnetConfig.ECART_THEORIE_PRATIQUE:
			regime = "sait_mais_n_applique_pas"
		elif skill_theorie < 60.0:
			regime = "acquis"
		out.append({
			"dimension": str(c.get("dimension", "")),
			"cle": str(c.get("cle", "")),
			"skill_theorie": skill_theorie,
			"skill_pratique": skill_pratique,
			"ecart": ecart,
			"regime": regime,
		})
	return out

# ── Composition du plan du jour — LePlan (§4.10) ─────────────────────────────────

## Compose la séance du jour. `drills` = drills générés (Étage 3), `options` peut fournir
## `session_size`, `positive_ratio`, `today_iso`, `derniere_partie_id`.
static func build_plan(drills: Array, options: Dictionary = {}) -> Dictionary:
	var today := str(options.get("today_iso", Time.get_date_string_from_system()))
	var session_size: int = int(options.get("session_size", CarnetConfig.SESSION_SIZE))
	var positive_target: int = int(round(float(session_size) * float(options.get("positive_ratio", CarnetConfig.POSITIVE_DRILL_RATIO))))
	var derniere_partie := str(options.get("derniere_partie_id", ""))

	var due: Array = []
	var nouveau: Array = []
	for drill in drills:
		if not (drill is Dictionary) or bool(drill.get("maitrise", false)):
			continue
		var srs: Dictionary = drill.get("srs", {})
		var rep := int(srs.get("repetitions", 0))
		if rep == 0:
			nouveau.append(drill)
		elif _echeance_due(str(srs.get("echeance", "")), today):
			due.append(drill)

	due.sort_custom(func(a, b): return _plan_less(a, b))

	var selected: Array = []
	var per_motif := {}
	var per_game := {}
	var positives := 0

	# 1) Un drill de révision ancienne (interleaving) en priorité.
	var revision := _pick_first(due, selected, per_motif, per_game, true)
	if not revision.is_empty():
		selected.append(revision)
		_tally(revision, per_motif, per_game)
		positives += 1 if str(revision.get("polarite", "")) != CarnetConfig.POLARITE_NEGATIVE else 0

	# 2) File due, en respectant les contraintes et la part de positifs.
	for drill in due:
		if selected.size() >= session_size:
			break
		if selected.has(drill):
			continue
		var is_positive := str(drill.get("polarite", "")) != CarnetConfig.POLARITE_NEGATIVE
		if is_positive and positives >= positive_target:
			continue
		if not _can_add(drill, per_motif, per_game):
			continue
		selected.append(drill)
		_tally(drill, per_motif, per_game)
		if is_positive:
			positives += 1

	# 3) Complément : drills neufs des meilleures faiblesses jamais travaillées.
	nouveau.sort_custom(func(a, b): return _plan_less(a, b))
	for drill in nouveau:
		if selected.size() >= session_size:
			break
		var is_positive := str(drill.get("polarite", "")) != CarnetConfig.POLARITE_NEGATIVE
		if is_positive and positives >= positive_target:
			continue
		if not _can_add(drill, per_motif, per_game):
			continue
		selected.append(drill)
		_tally(drill, per_motif, per_game)
		if is_positive:
			positives += 1

	# 4) Équilibre : on ne termine jamais sur une accumulation de fautes.
	if not derniere_partie.is_empty():
		_bubble_last_game_moment(selected, derniere_partie)

	var raisons: Array = []
	for drill in selected:
		raisons.append({
			"drill_id": str(drill.get("drill_id", "")),
			"motif": str(drill.get("motif", "")),
			"raison": _raison(drill),
		})

	return {
		"date": today,
		"drills": selected,
		"raisons": raisons,
		"est_jour_repos": selected.is_empty(),
		"nb_positifs": positives,
		"objectif": _objectif(selected),
	}

static func _plan_less(a: Dictionary, b: Dictionary) -> bool:
	var sa := float(a.get("motif_score", 0.0))
	var sb := float(b.get("motif_score", 0.0))
	if not is_equal_approx(sa, sb):
		return sa > sb
	var ea := str(a.get("srs", {}).get("echeance", ""))
	var eb := str(b.get("srs", {}).get("echeance", ""))
	if ea != eb:
		return (ea if ea != "" else "9999") < (eb if eb != "" else "9999")
	var ga := float(a.get("gravite", 0.0))
	var gb := float(b.get("gravite", 0.0))
	if not is_equal_approx(ga, gb):
		return ga > gb
	return str(a.get("event_id", "")) < str(b.get("event_id", ""))

static func _pick_first(due: Array, selected: Array, per_motif: Dictionary, per_game: Dictionary, prefer_reviewed: bool) -> Dictionary:
	for drill in due:
		if selected.has(drill):
			continue
		if prefer_reviewed and int(drill.get("srs", {}).get("repetitions", 0)) < 1:
			continue
		if _can_add(drill, per_motif, per_game):
			return drill
	return {}

static func _can_add(drill: Dictionary, per_motif: Dictionary, per_game: Dictionary) -> bool:
	var motif := str(drill.get("motif", ""))
	var game := str(drill.get("game_id", ""))
	if int(per_motif.get(motif, 0)) >= CarnetConfig.MAX_PER_MOTIF:
		return false
	if game != "" and int(per_game.get(game, 0)) >= 1:
		return false
	return true

static func _tally(drill: Dictionary, per_motif: Dictionary, per_game: Dictionary) -> void:
	var motif := str(drill.get("motif", ""))
	var game := str(drill.get("game_id", ""))
	per_motif[motif] = int(per_motif.get(motif, 0)) + 1
	if game != "":
		per_game[game] = int(per_game.get(game, 0)) + 1

## Fait remonter en fin de séance un moment fort de la dernière partie.
static func _bubble_last_game_moment(selected: Array, derniere_partie: String) -> void:
	for i in range(selected.size()):
		var drill: Dictionary = selected[i]
		if str(drill.get("game_id", "")) == derniere_partie \
				and str(drill.get("polarite", "")) != CarnetConfig.POLARITE_NEGATIVE:
			var moment = selected.pop_at(i)
			selected.append(moment)
			return

static func _raison(drill: Dictionary) -> String:
	if int(drill.get("srs", {}).get("repetitions", 0)) == 0:
		return "nouveau"
	return "révision"

static func _objectif(selected: Array) -> String:
	var motifs := {}
	for drill in selected:
		motifs[str(drill.get("motif", ""))] = true
	motifs.erase("")
	return "Travailler %d motif(s)" % motifs.size() if motifs.size() > 0 else ""

# ── Maîtrise, plateau, série/joker (§4.11 D) ─────────────────────────────────────

## Un motif est « acquis » si, sur MASTERY_WINDOW parties récentes, il n'apparaît plus
## et au moins MASTERY_DRILLS drills associés ont été réussis.
static func detect_mastery(motifs: Array, drills: Array, recent_game_ids: Array) -> Array:
	var recent := {}
	for gid in recent_game_ids:
		recent[str(gid)] = true
	var success_by_motif := {}
	for drill in drills:
		if not (drill is Dictionary):
			continue
		var key := str(drill.get("motif", ""))
		if int(drill.get("reussites", 0)) >= CarnetConfig.MASTERY_DRILLS:
			success_by_motif[key] = true
	var out: Array = []
	for m in motifs:
		if not (m is Dictionary) or not bool(m.get("etabli", false)):
			continue
		if str(m.get("polarite", "")) != CarnetConfig.POLARITE_NEGATIVE or bool(m.get("general", false)):
			continue
		var key := "%s|%s" % [m.get("famille", ""), m.get("cle", "")]
		var in_recent := false
		for gid in m.get("jeux", []):
			if recent.has(str(gid)):
				in_recent = true
				break
		if not in_recent and success_by_motif.has(key):
			out.append(key)
	return out

## Plateau : compétence stagnante sur PLATEAU_SEANCES mesures.
static func detect_plateau(skills_history: Array, epsilon: float = 1.0) -> bool:
	if skills_history.size() < CarnetConfig.PLATEAU_SEANCES:
		return false
	var window := skills_history.slice(skills_history.size() - CarnetConfig.PLATEAU_SEANCES, skills_history.size())
	var mn := 999.0
	var mx := -999.0
	for v in window:
		mn = minf(mn, float(v))
		mx = maxf(mx, float(v))
	return (mx - mn) < epsilon

## Série de jours consécutifs avec ≥ 1 drill, avec un joker algorithmique par semaine.
static func update_streak(state: Dictionary, today_iso: String, had_drill: bool) -> Dictionary:
	var serie := int(state.get("serie", 0))
	var derniere := str(state.get("derniere_date", ""))
	var joker_dispo := int(state.get("joker_disponible", CarnetConfig.JOKER_PAR_SEMAINE))
	var derniere_joker := str(state.get("derniere_joker_date", ""))
	# Le joker se recharge 7 jours après avoir été consommé.
	if joker_dispo < CarnetConfig.JOKER_PAR_SEMAINE and derniere_joker != "" \
			and DateUtil.day_index(today_iso) - DateUtil.day_index(derniere_joker) >= 7:
		joker_dispo = CarnetConfig.JOKER_PAR_SEMAINE
	if had_drill:
		if derniere == "":
			serie = 1
		elif derniere != today_iso:
			var gap := DateUtil.day_index(today_iso) - DateUtil.day_index(derniere)
			if gap == 1:
				serie += 1
			elif gap == 2 and joker_dispo > 0:
				joker_dispo -= 1
				state["derniere_joker_date"] = today_iso
				serie += 1
			else:
				serie = 1
		state["derniere_date"] = today_iso
	state["serie"] = serie
	state["joker_disponible"] = joker_dispo
	return state

# ── Helpers date / hash ──────────────────────────────────────────────────────────

static func _echeance_due(echeance: String, today: String) -> bool:
	if echeance == "":
		return false
	return DateUtil.day_index(echeance) <= DateUtil.day_index(today)

static func add_days(date_iso: String, days: int) -> String:
	return DateUtil.add_days(date_iso, days)
