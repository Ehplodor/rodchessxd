class_name CarnetLedger
extends RefCounted
## CarnetLedger.gd — LeCarnet, Étage 2 (§4.5 → §4.7 du plan).
##
## Compile les atomes (Étage 1) dans le temps et selon plusieurs dimensions :
## motifs faiblesses / forces / curiosités, compétences par dimension, profil (radar),
## tendance et indice de progression. Ne décide de RIEN (l'Étage 3 décide) ; ne mesure
## rien lui-même (l'Étage 1 mesure). Déterministe : à entrées égales, sortie égale.

const POLARITE_NEGATIVE := CarnetConfig.POLARITE_NEGATIVE
const POLARITE_POSITIVE := CarnetConfig.POLARITE_POSITIVE
const POLARITE_CURIEUSE := CarnetConfig.POLARITE_CURIEUSE

## Dimensions d'apprentissage agrégées (§4.0ter étage 2).
const DIMENSIONS := ["phase", "couleur", "registre", "ouverture", "type_finale", "regime"]

## Compile un ensemble d'atomes.
## `options` : { nb_parties (G), today_iso, recent_game_ids (optionnel) }.
static func compile(atoms: Array, options: Dictionary = {}) -> Dictionary:
	var G: int = int(options.get("nb_parties", 0))
	if G <= 0:
		G = _count_games(atoms)
	var today: String = str(options.get("today_iso", Time.get_date_string_from_system()))
	# Fenêtre « récente » globale (§4.7) : calculée une fois, réutilisée par chaque motif.
	var recent_ids := _recent_game_ids(atoms, options)
	var motif_options := {"recent_game_ids": recent_ids.keys()}

	var groups := _group_motifs(atoms, today, G)
	var motifs: Array = []
	for key in groups.keys():
		motifs.append(_build_motif(key, groups[key], G, today, motif_options))
	_apply_non_redundancy(motifs)
	_sort_motifs(motifs)

	var faiblesses: Array = []
	var forces: Array = []
	var curiosites: Array = []
	var emergeants: Array = []
	for m in motifs:
		var established: bool = bool(m["etabli"])
		if not established:
			if int(m["n"]) <= 2:
				emergeants.append(m)
			continue
		if bool(m.get("general", false)):
			continue
		match str(m["polarite"]):
			POLARITE_NEGATIVE: faiblesses.append(m)
			POLARITE_POSITIVE: forces.append(m)
			_: curiosites.append(m)

	var competences := _competeces(atoms, today)
	var profil := _profil(atoms, competences, faiblesses)

	return {
		"nb_atomes": atoms.size(),
		"nb_parties": G,
		"motifs": motifs,
		"faiblesses": faiblesses,
		"forces": forces,
		"curiosites": curiosites,
		"emergeants": emergeants,
		"competences": competences,
		"profil": profil,
		"tendance_globale": _tendance(atoms, options),
	}

# ── Agrégation des motifs (§4.5) ─────────────────────────────────────────────────

static func _group_motifs(atoms: Array, _today: String, _G: int) -> Dictionary:
	var groups := {}
	for atom in atoms:
		if not (atom is Dictionary):
			continue
		for m in _atom_motifs(atom):
			var key: String = "%s|%s|%s" % [m["famille"], m["cle"], m["polarite"]]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(atom)
	return groups

## Toutes les clés (famille, clé) portées par un atome (§4.4, 9 familles).
static func _atom_motifs(atom: Dictionary) -> Array:
	var out: Array = []
	var polarite: String = str(atom.get("polarite", ""))
	if polarite == "":
		return out
	var phase: String = str(atom.get("phase", ""))
	if phase != "":
		out.append(_key("phase", phase, polarite))
	var regime: String = str(atom.get("regime", ""))
	if regime != "":
		out.append(_key("regime", regime, polarite))
	var piece: String = str(atom.get("features", {}).get("piece_bougee", ""))
	if piece != "":
		out.append(_key("piece", piece, polarite))
	var eco: String = str(atom.get("eco", ""))
	if eco != "":
		out.append(_key("ouverture", eco, polarite))
	var finale: String = str(atom.get("type_finale", ""))
	if finale != "" and finale != "aucune":
		out.append(_key("type_finale", finale, polarite))
	var tranche: String = str(atom.get("tranche", ""))
	if tranche != "":
		out.append(_key("tranche", tranche, polarite))
	for sch in atom.get("schemas", []):
		out.append(_key("schema", str(sch), polarite))
		if str(sch) == "pression_temps":
			out.append(_key("temps", "pression_temps", polarite))
	if polarite == POLARITE_NEGATIVE:
		var qual: String = str(atom.get("qualite", ""))
		if qual != "":
			out.append(_key("qualite", qual, polarite))
	else:
		var cat: String = str(atom.get("categorie", ""))
		if cat != "":
			out.append(_key("categorie", cat, polarite))
	return out

static func _key(famille: String, cle: String, polarite: String) -> Dictionary:
	return {"famille": famille, "cle": cle, "polarite": polarite}

## Score d'un motif (§4.5) : 100 × K × (alpha × S + bêta × min(P / P_MAX, 1)).
static func _build_motif(key: String, atoms: Array, G: int, today: String, options: Dictionary = {}) -> Dictionary:
	var parts: PackedStringArray = key.split("|")
	var famille := parts[0] if parts.size() > 0 else ""
	var cle := parts[1] if parts.size() > 1 else ""
	var polarite := parts[2] if parts.size() > 2 else ""

	var n := atoms.size()
	var sum_w := 0.0
	var sum_ws := 0.0
	var ids: Array = []
	var jeux := {}
	for atom in atoms:
		var w := _recency_weight(atom, today)
		sum_w += w
		sum_ws += w * _severity(atom)
		ids.append(str(atom.get("event_id", "")))
		var gid := str(atom.get("game_id", ""))
		if gid != "":
			jeux[gid] = true
	var s_m := (sum_ws / sum_w) if sum_w > 0.0 else 0.0
	var p_m := float(n) / float(maxi(1, G))
	var k_m := float(n) / float(n + int(CarnetConfig.K_SHRINK))
	var score := 100.0 * k_m * (CarnetConfig.ALPHA * s_m
			+ CarnetConfig.BETA * minf(p_m / CarnetConfig.P_MAX, 1.0))
	var established := n >= CarnetConfig.MIN_N_ETABLIE and k_m >= CarnetConfig.K_ETABLIE and G >= 5
	return {
		"famille": famille,
		"cle": cle,
		"libelle": libelle(famille, cle),
		"polarite": polarite,
		"atomes": ids,
		"jeux": jeux.keys(),
		"n": n,
		"gravite_moy": s_m,
		"frequence": p_m,
		"confiance": k_m,
		"score": clampf(score, 0.0, 100.0),
		"etabli": established,
		"general": false,
		"tendance": _tendance(atoms, options),
	}

## Poids de récence d'un événement : w(e) = 0,5 ^ (âge_jours / 45).
static func _recency_weight(atom: Dictionary, today: String) -> float:
	var age := _age_days(str(atom.get("date_iso", "")), today)
	return pow(0.5, age / CarnetConfig.DEMI_VIE_JOURS)

## Gravité (négatif) ou mérite (positif) normalisé sur [0, 1] (§4.3, §4.4.1).
static func _severity(atom: Dictionary) -> float:
	if str(atom.get("polarite", "")) == POLARITE_POSITIVE:
		return clampf(float(atom.get("merite", 0.0)), 0.0, 1.0)
	return clampf(float(atom.get("perte_winpct", 0.0)) / CarnetConfig.S_MAX, 0.0, 1.0)

# ── Tendance (§4.7) ──────────────────────────────────────────────────────────────

static func _tendance(atoms: Array, options: Dictionary) -> String:
	var recent_ids := _recent_game_ids(atoms, options)
	if atoms.is_empty() or recent_ids.is_empty():
		return "indetermine"
	var n_recent := 0
	var n_old := 0
	var games_recent := {}
	var games_old := {}
	for atom in atoms:
		if not (atom is Dictionary):
			continue
		var gid: String = str(atom.get("game_id", ""))
		if gid in recent_ids:
			n_recent += 1
			games_recent[gid] = true
		else:
			n_old += 1
			games_old[gid] = true
	var g_recent := games_recent.size()
	var g_old := games_old.size()
	if g_old == 0:
		return "indetermine"
	var taux_recent := float(n_recent) / float(maxi(1, g_recent))
	var taux_old := float(n_old) / float(maxi(1, g_old))
	if taux_old <= 0.0:
		return "stable" if taux_recent <= 0.0 else "en_aggravation"
	if taux_recent <= CarnetConfig.AMELIORATION * taux_old:
		return "en_amelioration"
	if taux_recent >= CarnetConfig.AGGRAVATION * taux_old:
		return "en_aggravation"
	return "stable"

## Les RECENT_GAMES dernières parties distinctes (par date puis ordre d'insertion).
static func _recent_game_ids(atoms: Array, options: Dictionary) -> Dictionary:
	var provided: Array = options.get("recent_game_ids", []) if options.get("recent_game_ids", []) is Array else []
	var order: Array = []
	var seen := {}
	for atom in atoms:
		if not (atom is Dictionary):
			continue
		var gid: String = str(atom.get("game_id", ""))
		if gid == "" or seen.has(gid):
			continue
		seen[gid] = true
		order.append(gid)
	var result := {}
	if not provided.is_empty():
		for gid in provided:
			result[str(gid)] = true
		return result
	var start: int = maxi(0, order.size() - CarnetConfig.RECENT_GAMES)
	for i in range(start, order.size()):
		result[str(order[i])] = true
	return result

# ── Non-redondance (§4.6) ────────────────────────────────────────────────────────

## Si m2 est plus spécifique que m1 (atomes de m2 ⊂ atomes de m1) et |m2| ≥ 0,5·|m1|,
## m1 est rétrogradé (« général ») au profit de m2.
static func _apply_non_redundancy(motifs: Array) -> void:
	# Ensembles d'atomes précalculés une fois : évite une reconstruction O(m²).
	var id_sets: Array = []
	for motif in motifs:
		id_sets.append(_id_set(motif))
	for i in range(motifs.size()):
		var m1: Dictionary = motifs[i]
		if not bool(m1["etabli"]):
			continue
		var set1: Dictionary = id_sets[i]
		for j in range(motifs.size()):
			if i == j:
				continue
			var m2: Dictionary = motifs[j]
			if not bool(m2["etabli"]) or str(m2["polarite"]) != str(m1["polarite"]):
				continue
			var set2: Dictionary = id_sets[j]
			if set2.size() == 0 or set2.size() >= set1.size():
				continue
			if _is_subset(set2, set1) and float(set2.size()) >= 0.5 * float(set1.size()):
				m1["general"] = true
				break

static func _id_set(motif: Dictionary) -> Dictionary:
	var s := {}
	for id in motif.get("atomes", []):
		s[str(id)] = true
	return s

static func _is_subset(subset: Dictionary, superset: Dictionary) -> bool:
	if subset.size() > superset.size():
		return false
	for k in subset.keys():
		if not superset.has(k):
			return false
	return true

static func _sort_motifs(motifs: Array) -> void:
	motifs.sort_custom(func(a, b):
		var sa := float(a["score"])
		var sb := float(b["score"])
		if not is_equal_approx(sa, sb):
			return sa > sb
		var na := int(a["n"])
		var nb := int(b["n"])
		if na != nb:
			return na > nb
		var ka := "%s|%s" % [a["famille"], a["cle"]]
		var kb := "%s|%s" % [b["famille"], b["cle"]]
		return ka < kb
	)

# ── Compétences par dimension (§4.7, §4.11 A/B) ─────────────────────────────────

static func _competeces(atoms: Array, today: String) -> Array:
	var out: Array = []
	for dimension in DIMENSIONS:
		var buckets := {}
		for atom in atoms:
			if not (atom is Dictionary):
				continue
			var value := _dimension_value(atom, dimension)
			if value == "":
				continue
			if not buckets.has(value):
				buckets[value] = []
			buckets[value].append(atom)
		for value in buckets.keys():
			out.append(_build_competence(dimension, value, buckets[value], today))
	out.sort_custom(func(a, b):
		if str(a["dimension"]) != str(b["dimension"]):
			return str(a["dimension"]) < str(b["dimension"])
		return float(a["skill"]) < float(b["skill"])
	)
	return out

static func _dimension_value(atom: Dictionary, dimension: String) -> String:
	match dimension:
		"phase": return str(atom.get("phase", ""))
		"couleur": return str(atom.get("couleur", ""))
		"registre": return _registre(atom)
		"ouverture": return str(atom.get("eco", ""))
		"type_finale": return str(atom.get("type_finale", "")) if str(atom.get("type_finale", "")) != "aucune" else ""
		"regime": return str(atom.get("regime", ""))
	return ""

static func _registre(atom: Dictionary) -> String:
	var schemas: Array = atom.get("schemas", []) if atom.get("schemas", []) is Array else []
	for s in schemas:
		if str(s) in ["capture_ratée", "gain_tactique_manqué", "piece_en_prise", "échec_manqué"]:
			return "tactique"
	var cat: String = str(atom.get("categorie", ""))
	if cat in ["brillant", "trouvaille"]:
		return "tactique"
	return "positionnel"

static func _build_competence(dimension: String, cle: String, atoms: Array, _today: String) -> Dictionary:
	var n := atoms.size()
	var sum_gravity := 0.0
	var sum_merit := 0.0
	var sum_gravity_theorie := 0.0
	var n_theorie_total := 0
	var sum_gravity_pratique := 0.0
	var n_pratique_total := 0
	for atom in atoms:
		var g: float = _severity(atom) if str(atom.get("polarite", "")) == POLARITE_NEGATIVE else 0.0
		sum_gravity += g
		if str(atom.get("polarite", "")) == POLARITE_POSITIVE:
			sum_merit += float(atom.get("merite", 0.0))
		var contexte: String = str(atom.get("contexte", "pratique"))
		if contexte == "theorie":
			n_theorie_total += 1
			sum_gravity_theorie += g
		else:
			n_pratique_total += 1
			sum_gravity_pratique += g
	var skill := clampf(100.0 * (1.0 - sum_gravity / float(maxi(1, n)) + 0.15 * sum_merit / float(maxi(1, n))), 0.0, 100.0)
	var skill_theorie := -1.0
	if n_theorie_total > 0:
		skill_theorie = clampf(100.0 * (1.0 - sum_gravity_theorie / float(n_theorie_total)), 0.0, 100.0)
	var skill_pratique := -1.0
	if n_pratique_total > 0:
		skill_pratique = clampf(100.0 * (1.0 - sum_gravity_pratique / float(n_pratique_total)), 0.0, 100.0)
	var has_both := n_theorie_total > 0 and n_pratique_total > 0
	return {
		"dimension": dimension,
		"cle": cle,
		"skill": skill,
		"confiance": float(n) / float(n + int(CarnetConfig.K_SHRINK)),
		"n": n,
		"skill_theorie": skill_theorie,
		"skill_pratique": skill_pratique,
		"ecart": (skill_theorie - skill_pratique) if has_both else 0.0,
	}

# ── Profil (§4.7, §4.11 D) ───────────────────────────────────────────────────────

static func _profil(atoms: Array, competences: Array, faiblesses: Array) -> Dictionary:
	var radar := {}
	for c in competences:
		if int(c["n"]) < CarnetConfig.MIN_N_ETABLIE:
			continue
		radar["%s:%s" % [c["dimension"], c["cle"]]] = {
			"skill": c["skill"],
			"confiance": c["confiance"],
			"n": c["n"],
		}

	var top5: Array = []
	for m in faiblesses:
		top5.append(float(m["score"]))
		if top5.size() >= 5:
			break
	var indice := 100.0
	if not top5.is_empty():
		var total := 0.0
		for s in top5:
			total += s
		indice = clampf(100.0 - total / float(top5.size()), 0.0, 100.0)

	return {
		"competences": competences,
		"radar": radar,
		"indice_progression": indice,
		"moments_forts": _moments_forts(atoms),
	}

static func _moments_forts(atoms: Array, limit: int = 8) -> Array:
	var moments: Array = []
	for atom in atoms:
		if not (atom is Dictionary):
			continue
		if str(atom.get("polarite", "")) == POLARITE_POSITIVE or bool(atom.get("surprise", false)) or bool(atom.get("mystere", false)):
			moments.append(atom)
	moments.sort_custom(func(a, b):
		var ka := float(a.get("merite", 0.0)) + float(a.get("IS", 0.0)) / 100.0
		var kb := float(b.get("merite", 0.0)) + float(b.get("IS", 0.0)) / 100.0
		return ka > kb
	)
	return moments.slice(0, mini(limit, moments.size()))

# ── Helpers ──────────────────────────────────────────────────────────────────────

static func _count_games(atoms: Array) -> int:
	var games := {}
	for atom in atoms:
		if atom is Dictionary:
			games[str(atom.get("game_id", ""))] = true
	games.erase("")
	return games.size()

static func _age_days(date_iso: String, today_iso: String) -> float:
	var a := DateUtil.day_index(date_iso)
	var b := DateUtil.day_index(today_iso)
	if a < 0 or b < 0:
		return 0.0
	return maxf(0.0, float(b - a))

static func libelle(famille: String, cle: String) -> String:
	match famille:
		"phase": return "Phase : %s" % _phase_fr(cle)
		"regime": return "Régime : %s" % cle.replace("_", " ")
		"piece": return "Pièce : %s" % _piece_fr(cle)
		"ouverture": return "Ouverture : %s" % cle
		"type_finale": return "Finale : %s" % cle
		"schema": return "Schéma : %s" % cle.replace("_", " ")
		"tranche": return "Coups : %s" % cle
		"qualite": return "Faute : %s" % cle
		"categorie": return "Force : %s" % cle
		"temps": return "Temps : pression"
	return "%s / %s" % [famille, cle]

static func _phase_fr(phase: String) -> String:
	match phase:
		"opening": return "ouverture"
		"endgame": return "finale"
		_: return "milieu de jeu"

static func _piece_fr(letter: String) -> String:
	match letter:
		"P": return "pion"
		"C": return "cavalier"
		"F": return "fou"
		"T": return "tour"
		"D": return "dame"
		"R": return "roi"
	return letter
