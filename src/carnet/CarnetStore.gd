class_name CarnetStore
extends RefCounted
## CarnetStore.gd — persistance et orchestration de LeCarnet, MULTI-PROFILS.
##
## Un profil = un carnet isolé. L'analyse moteur reste unique par partie (dans la
## partie) ; ce store ne conserve que ce qui dépend du joueur : atomes, table de
## synchronisation (fraîcheur/version) et état d'entraînement.
##
##   user://library/carnets/profiles/<profile_id>/
##       sync.json                 # game_id -> {perspective, analysis_version, atom_version}
##       trainer.json              # drills, SRS, série, compétences
##       atoms/<game_id>.json      # atomes du profil pour cette partie
##
## Idempotent : ré-ingérer une partie remplace ses atomes (et ses drills) ; le calcul de
## `sync_status` ne se base que sur les versions, jamais sur une horloge implicite.

const _PROFILES_DIR := DatabaseManagerClass.PROFILES_DIR

static func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DatabaseManager")
	return null

static func _resolve(profile_id: String) -> String:
	if profile_id != "":
		return profile_id
	return CarnetProfiles.active_id()

static func _dir(profile_id: String) -> String:
	return "%s/%s" % [_PROFILES_DIR, profile_id]

static func _sync_path(profile_id: String) -> String:
	return "%s/sync.json" % _dir(profile_id)

static func _trainer_path(profile_id: String) -> String:
	return "%s/trainer.json" % _dir(profile_id)

static func _atoms_dir(profile_id: String) -> String:
	return "%s/atoms" % _dir(profile_id)

static func _atom_path(profile_id: String, game_id: String) -> String:
	return "%s/%s.json" % [_atoms_dir(profile_id), game_id]

# ── Ingestion / suppression (§4.12) ──────────────────────────────────────────────

## Remplace les atomes d'une partie pour un profil (idempotent) et retire ses drills.
## `meta` : { date_iso, perspective ("white"/"black"), analysis_version }.
static func ingest_game(game_id: String, atoms: Array, meta: Dictionary = {}, profile_id: String = "") -> void:
	var db := _db()
	if db == null or game_id == "":
		return
	var pid := _resolve(profile_id)
	db.save_json_atomic(_atom_path(pid, game_id), {
		"schema_version": CarnetConfig.CARNET_SCHEMA_VERSION,
		"game_id": game_id,
		"perspective": str(meta.get("perspective", "")),
		"atoms": atoms,
	})

	var game: Dictionary = db.get_game(game_id)
	var analysis_version: int = int(meta.get("analysis_version", game.get("analysis_version", 0)))
	var sync := _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	var existing_entry: Dictionary = entries.get(game_id, {})
	var forced_perspective: String = str(meta.get("forced_perspective", existing_entry.get("perspective", "")))
	entries[game_id] = {
		"perspective": forced_perspective,
		"date_iso": DateUtil.normalize(str(meta.get("date_iso", game.get("date", "")))),
		"analysis_version": analysis_version,
		"atom_version": CarnetConfig.ATOM_VERSION,
		"atoms_count": atoms.size(),
		"synced_at": int(Time.get_unix_time_from_system()),
	}
	sync["entries"] = entries
	sync["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	db.save_json_atomic(_sync_path(pid), sync)

	_drop_game_drills(pid, game_id)

## Supprime une partie d'un profil : atomes, entrée de sync et drills associés.
## L'entrée sync est marquée "removed" (et non effacée) pour exclure la partie
## du rattachement automatique (`match_games`) sans casser la ré-importation globale.
static func remove_game(game_id: String, profile_id: String = "") -> void:
	var db := _db()
	if db == null:
		return
	var pid := _resolve(profile_id)
	db.remove_file(_atom_path(pid, game_id))
	var sync := _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	entries[game_id] = {"removed": true}
	sync["entries"] = entries
	db.save_json_atomic(_sync_path(pid), sync)
	_drop_game_drills(pid, game_id)

## Met à jour la perspective forcée d'une partie dans sync.json.
## `perspective` ∈ ["", "white", "black"] (vide = auto).
static func update_game_perspective(game_id: String, perspective: String, profile_id: String = "") -> void:
	var db := _db()
	if db == null or game_id == "":
		return
	var pid := _resolve(profile_id)
	var sync := _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	if not entries.has(game_id):
		entries[game_id] = {}
	var entry: Dictionary = entries[game_id]
	entry["perspective"] = perspective
	entries[game_id] = entry
	sync["entries"] = entries
	db.save_json_atomic(_sync_path(pid), sync)

## Recalcule algorithmiquement les atomes d'une partie depuis la Bibliothèque
## (sans relancer Stockfish si une analyse existe déjà). Met à jour le cache et le plan.
static func recalculate_game(game_id: String, profile_id: String = "", options: Dictionary = {}) -> Dictionary:
	var db := _db()
	if db == null or game_id == "":
		return {"ok": false, "error": "database_unavailable"}
	var pid := _resolve(profile_id)
	var game: Dictionary = db.get_game(game_id)
	if game.is_empty():
		return {"ok": false, "error": "game_not_found"}

	var analyses: Array = game.get("engine_analyses", []) if game.get("engine_analyses", []) is Array else []
	var analysis: Dictionary = {}
	for i in range(analyses.size() - 1, -1, -1):
		var a = analyses[i]
		if a is Dictionary and (a.get("evaluations", []) as Array).size() > 0:
			analysis = a
			break
	if analysis.is_empty():
		return {"ok": false, "error": "no_engine_analysis"}

	var profile: Dictionary = CarnetProfiles.get_profile(pid)
	var keys: Array = profile.get("player_keys", [])

	# Résolution de la perspective : préférence forcée dans sync.json d'abord, puis matching des noms
	var sync: Dictionary = _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	var forced_perspective := ""
	if entries.has(game_id):
		forced_perspective = str(entries[game_id].get("perspective", ""))
	var perspective := forced_perspective
	if perspective == "":
		var white := DatabaseManagerClass.normalize_player_key(str(game.get("white_name", "")))
		var black := DatabaseManagerClass.normalize_player_key(str(game.get("black_name", "")))
		if keys.has(white):
			perspective = "white"
		elif keys.has(black):
			perspective = "black"

	var white_name := str(game.get("white_name", "?"))
	var black_name := str(game.get("black_name", "?"))
	print("[Carnet] [Recalcul] Partie %s (%s vs %s) - Perspective: %s" % [
		game_id, white_name, black_name, perspective if perspective != "" else "auto"
	])

	var atoms := CarnetEvents.annotate_game(game, analysis, {
		"couleur_joueur": perspective,
		"mode_analyse": bool(options.get("mode_analyse", false)),
	})

	ingest_game(game_id, atoms, {
		"date_iso": str(game.get("date", "")),
		"perspective": perspective,
		"forced_perspective": forced_perspective,
		"analysis_version": int(game.get("analysis_version", 0)),
	}, pid)

	var ledger := compile("", -1, pid)
	var plan := refresh_plan("", {}, pid)
	print("[Carnet] [Recalcul] Partie %s terminée avec succès (%d atomes créés)." % [game_id, atoms.size()])

	return {
		"ok": true,
		"game_id": game_id,
		"atoms_count": atoms.size(),
		"perspective": perspective,
		"ledger": ledger,
		"plan": plan
	}

## Recalcule l'intégralité d'un Carnet à partir de la Bibliothèque.
## Rescanne toutes les parties matchées, ré-atomise chaque partie analysée,
## recompile le grand livre et régénère les exercices tout en préservant
## l'état d'apprentissage humain (répétitions SM-2 et séries).
static func recalculate_profile(profile_id: String = "", options: Dictionary = {}) -> Dictionary:
	var db := _db()
	if db == null:
		return {"ok": false, "error": "database_unavailable"}
	var pid := _resolve(profile_id)
	var profile := CarnetProfiles.get_profile(pid)
	if profile.is_empty():
		return {"ok": false, "error": "profile_not_found"}

	var matches := CarnetProfiles.match_games(profile)
	var processed_games: int = 0
	var total_atoms: int = 0
	var skipped_no_analysis: int = 0

	print("[Carnet] [Recalcul Profil '%s'] Début du recalcul synchrone (%d parties rattachées)..." % [pid, matches.size()])

	# Chargement unique en mémoire pour amortir les I/O et les syncs FS (notamment sur Web)
	var sync := _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	var trainer := _load_trainer(pid)
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var now := int(Time.get_unix_time_from_system())

	for i in range(matches.size()):
		var game_match: Dictionary = matches[i]
		var gid := str(game_match.get("game_id", ""))
		var game: Dictionary = db.get_game(gid)
		if game.is_empty():
			continue

		var white_name := str(game.get("white_name", "?"))
		var black_name := str(game.get("black_name", "?"))
		print("[Carnet] [Recalcul Profil] [%d/%d] Partie %s (%s vs %s)" % [
			i + 1, matches.size(), gid, white_name, black_name
		])

		var analyses: Array = game.get("engine_analyses", []) if game.get("engine_analyses", []) is Array else []
		var analysis: Dictionary = {}
		for j in range(analyses.size() - 1, -1, -1):
			var a = analyses[j]
			if a is Dictionary and (a.get("evaluations", []) as Array).size() > 0:
				analysis = a
				break
		if analysis.is_empty():
			print("[Carnet]   -> Ignorée : aucune analyse moteur disponible.")
			skipped_no_analysis += 1
			continue

		var perspective := str(game_match.get("perspective", ""))
		var atoms := CarnetEvents.annotate_game(game, analysis, {
			"couleur_joueur": perspective,
			"mode_analyse": bool(options.get("mode_analyse", false)),
		})

		# Écriture atomique du fichier d'atomes spécifique
		db.save_json_atomic(_atom_path(pid, gid), {
			"schema_version": CarnetConfig.CARNET_SCHEMA_VERSION,
			"game_id": gid,
			"perspective": perspective,
			"atoms": atoms,
		})

		var analysis_version: int = int(game.get("analysis_version", 0))
		var existing_entry: Dictionary = entries.get(gid, {})
		var forced_perspective: String = str(existing_entry.get("perspective", ""))
		entries[gid] = {
			"perspective": forced_perspective,
			"date_iso": DateUtil.normalize(str(game.get("date", ""))),
			"analysis_version": analysis_version,
			"atom_version": CarnetConfig.ATOM_VERSION,
			"atoms_count": atoms.size(),
			"synced_at": now,
		}

		# Purge des exercices non révisés pour cette partie en mémoire
		var kept_drills: Array = []
		for drill in drills:
			if drill is Dictionary:
				if str(drill.get("game_id", "")) == gid:
					var srs: Dictionary = drill.get("srs", {}) if drill.get("srs", {}) is Dictionary else {}
					var rep := int(srs.get("repetitions", drill.get("repetitions", 0)))
					var ivl := int(srs.get("intervalle", drill.get("intervalle", drill.get("interval", 0))))
					if rep > 0 or ivl > 0:
						kept_drills.append(drill)
				else:
					kept_drills.append(drill)
		drills = kept_drills

		processed_games += 1
		total_atoms += atoms.size()

	# Sauvegarde globale unique en fin de lot
	sync["entries"] = entries
	sync["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	db.save_json_atomic(_sync_path(pid), sync)

	trainer["drills"] = drills
	_save_trainer(pid, trainer)

	var ledger := compile("", -1, pid)
	var plan := refresh_plan("", {}, pid)

	print("[Carnet] [Recalcul Profil '%s'] Terminé : %d parties traitées, %d ignorées, %d atomes régénérés." % [
		pid, processed_games, skipped_no_analysis, total_atoms
	])

	return {
		"ok": true,
		"profile_id": pid,
		"matched_games": matches.size(),
		"processed_games": processed_games,
		"skipped_no_analysis": skipped_no_analysis,
		"total_atoms": total_atoms,
		"ledger": ledger,
		"plan": plan
	}

## Recalcule l'intégralité d'un Carnet de façon asynchrone (non-bloquante avec await process_frame).
## Permet à l'UI de rester totalement fluide, d'animer une modale de progression dynamique
## et d'éviter tout gel de l'application sous Windows ou Web.
static func recalculate_profile_async(profile_id: String = "", options: Dictionary = {}, on_progress: Callable = Callable()) -> Dictionary:
	var db := _db()
	if db == null:
		return {"ok": false, "error": "database_unavailable"}
	var pid := _resolve(profile_id)
	var profile := CarnetProfiles.get_profile(pid)
	if profile.is_empty():
		return {"ok": false, "error": "profile_not_found"}

	var matches := CarnetProfiles.match_games(profile)
	var total_matches := matches.size()
	var processed_games: int = 0
	var total_atoms: int = 0
	var skipped_no_analysis: int = 0

	print("[Carnet] [Recalcul Profil '%s'] Début du recalcul asynchrone (%d parties rattachées)..." % [pid, total_matches])

	var sync := _load_sync(pid)
	var entries: Dictionary = sync.get("entries", {})
	var trainer := _load_trainer(pid)
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var now := int(Time.get_unix_time_from_system())
	var tree := Engine.get_main_loop() as SceneTree

	for i in range(total_matches):
		var game_match: Dictionary = matches[i]
		var gid := str(game_match.get("game_id", ""))
		var game: Dictionary = db.get_game(gid)
		if game.is_empty():
			continue

		var white_name := str(game.get("white_name", "?"))
		var black_name := str(game.get("black_name", "?"))
		print("[Carnet] [Recalcul Profil] [%d/%d] Partie %s (%s vs %s)" % [
			i + 1, total_matches, gid, white_name, black_name
		])

		var analyses: Array = game.get("engine_analyses", []) if game.get("engine_analyses", []) is Array else []
		var analysis: Dictionary = {}
		for j in range(analyses.size() - 1, -1, -1):
			var a = analyses[j]
			if a is Dictionary and (a.get("evaluations", []) as Array).size() > 0:
				analysis = a
				break
		if analysis.is_empty():
			print("[Carnet]   -> Ignorée : aucune analyse moteur disponible.")
			skipped_no_analysis += 1
			if on_progress.is_valid():
				on_progress.call(i + 1, total_matches, gid, game, 0)
			if tree != null:
				await tree.process_frame
			continue

		var perspective := str(game_match.get("perspective", ""))
		var atoms := CarnetEvents.annotate_game(game, analysis, {
			"couleur_joueur": perspective,
			"mode_analyse": bool(options.get("mode_analyse", false)),
		})

		db.save_json_atomic(_atom_path(pid, gid), {
			"schema_version": CarnetConfig.CARNET_SCHEMA_VERSION,
			"game_id": gid,
			"perspective": perspective,
			"atoms": atoms,
		})

		var analysis_version: int = int(game.get("analysis_version", 0))
		var existing_entry: Dictionary = entries.get(gid, {})
		var forced_perspective: String = str(existing_entry.get("perspective", ""))
		entries[gid] = {
			"perspective": forced_perspective,
			"date_iso": DateUtil.normalize(str(game.get("date", ""))),
			"analysis_version": analysis_version,
			"atom_version": CarnetConfig.ATOM_VERSION,
			"atoms_count": atoms.size(),
			"synced_at": now,
		}

		var kept_drills: Array = []
		for drill in drills:
			if drill is Dictionary:
				if str(drill.get("game_id", "")) == gid:
					var srs: Dictionary = drill.get("srs", {}) if drill.get("srs", {}) is Dictionary else {}
					var rep := int(srs.get("repetitions", drill.get("repetitions", 0)))
					var ivl := int(srs.get("intervalle", drill.get("intervalle", drill.get("interval", 0))))
					if rep > 0 or ivl > 0:
						kept_drills.append(drill)
				else:
					kept_drills.append(drill)
		drills = kept_drills

		processed_games += 1
		total_atoms += atoms.size()

		if on_progress.is_valid():
			on_progress.call(i + 1, total_matches, gid, game, atoms.size())

		# Relâchement du frame principal : Godot redessine l'UI et traite les événements OS !
		if tree != null:
			await tree.process_frame

	sync["entries"] = entries
	sync["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	db.save_json_atomic(_sync_path(pid), sync)

	trainer["drills"] = drills
	_save_trainer(pid, trainer)

	var ledger := compile("", -1, pid)
	var plan := refresh_plan("", {}, pid)

	print("[Carnet] [Recalcul Profil '%s'] Terminé : %d parties traitées, %d ignorées, %d atomes régénérés." % [
		pid, processed_games, skipped_no_analysis, total_atoms
	])

	return {
		"ok": true,
		"profile_id": pid,
		"matched_games": total_matches,
		"processed_games": processed_games,
		"skipped_no_analysis": skipped_no_analysis,
		"total_atoms": total_atoms,
		"ledger": ledger,
		"plan": plan
	}

static func _drop_game_drills(profile_id: String, game_id: String) -> void:
	var trainer := _load_trainer(profile_id)
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var kept: Array = []
	for drill in drills:
		if drill is Dictionary:
			var gid := str(drill.get("game_id", ""))
			if gid == game_id:
				# Conserver l'exercice s'il a déjà été révisé en répétition espacée (SM-2)
				var srs: Dictionary = drill.get("srs", {}) if drill.get("srs", {}) is Dictionary else {}
				var rep := int(srs.get("repetitions", drill.get("repetitions", 0)))
				var ivl := int(srs.get("intervalle", drill.get("intervalle", drill.get("interval", 0))))
				if rep > 0 or ivl > 0:
					kept.append(drill)
					continue
			else:
				kept.append(drill)
	if kept.size() != drills.size():
		trainer["drills"] = kept
		_save_trainer(profile_id, trainer)

# ── Lecture ─────────────────────────────────────────────────────────────────────

## Tous les atomes d'un profil, aplatis (ordre stable : nom de fichier).
static func get_atoms(profile_id: String = "") -> Array:
	var db := _db()
	if db == null:
		return []
	var pid := _resolve(profile_id)
	var out: Array = []
	for file_name in _list_atom_files(pid):
		var payload: Dictionary = db.load_json("%s/%s" % [_atoms_dir(pid), file_name])
		for atom in payload.get("atoms", []):
			if atom is Dictionary:
				out.append(atom)
	return out

static func game_count(profile_id: String = "") -> int:
	return _list_atom_files(_resolve(profile_id)).size()

static func get_trainer_state(profile_id: String = "") -> Dictionary:
	return _load_trainer(_resolve(profile_id))

# ── Fraîcheur / synchronisation incrémentale ─────────────────────────────────────

## Classe les parties rattachées au profil en : connues (à jour), en attente (jamais
## atomisées) et périmées (analyse ou atomisation obsolète). C'est le delta que le
## runner de lot consomme.
static func sync_status(profile_id: String = "") -> Dictionary:
	var db := _db()
	var pid := _resolve(profile_id)
	var profile := CarnetProfiles.get_profile(pid)
	var matches := CarnetProfiles.match_games(profile)
	var entries: Dictionary = _load_sync(pid).get("entries", {})
	# Statut d'analyse lu depuis l'index en mémoire (pas de relecture disque par partie).
	var index_by_id := {}
	if db != null:
		for summary in db.games_index:
			if summary is Dictionary:
				index_by_id[str(summary.get("id", ""))] = summary
	var pending: Array = []
	var stale: Array = []
	var known: Array = []
	for match in matches:
		var gid := str(match.get("game_id", ""))
		var item: Dictionary = match.duplicate()
		var summary: Dictionary = index_by_id.get(gid, {})
		var analysis_version := int(summary.get("analysis_version", 0))
		var status := str(summary.get("analysis_status", "none"))
		if not entries.has(gid):
			item["reason"] = "never_atomized"
			pending.append(item)
			continue
		var entry: Dictionary = entries[gid]
		var entry_analysis := int(entry.get("analysis_version", -1))
		var entry_atom := int(entry.get("atom_version", -1))
		if status != "done":
			item["reason"] = "no_analysis"
			stale.append(item)
		elif entry_analysis != analysis_version:
			item["reason"] = "analysis_outdated"
			stale.append(item)
		elif entry_atom != CarnetConfig.ATOM_VERSION:
			item["reason"] = "atoms_outdated"
			stale.append(item)
		else:
			item["reason"] = "up_to_date"
			known.append(item)
	return {
		"profile_id": pid,
		"total": matches.size(),
		"known": known,
		"pending": pending,
		"stale": stale,
		"to_process": pending + stale,
	}

# ── Compilation & plan ───────────────────────────────────────────────────────────

static func compile(today_iso: String = "", nb_parties: int = -1, profile_id: String = "") -> Dictionary:
	var db := _db()
	if db == null:
		return CarnetLedger.compile([], {"nb_parties": 0})
	var pid := _resolve(profile_id)
	var atoms := get_atoms(pid)
	var trainer := _load_trainer(pid)
	var g: int = nb_parties
	if g < 0:
		g = maxi(game_count(pid), int(trainer.get("nb_parties", 0)))
	var options := {
		"nb_parties": g,
		"today_iso": today_iso if today_iso != "" else Time.get_date_string_from_system(),
		"recent_game_ids": _recent_game_ids(pid),
	}
	return CarnetLedger.compile(atoms, options)

static func refresh_plan(today_iso: String = "", options: Dictionary = {}, profile_id: String = "") -> Dictionary:
	var today := today_iso if today_iso != "" else Time.get_date_string_from_system()
	var pid := _resolve(profile_id)
	var atoms := get_atoms(pid)
	var ledger := compile(today, -1, pid)
	var trainer := _load_trainer(pid)
	var existing: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []

	var faiblesses: Array = ledger.get("faiblesses", []).duplicate()
	var forces: Array = ledger.get("forces", []).duplicate()
	var curiosites: Array = ledger.get("curiosites", []).duplicate()
	if faiblesses.is_empty():
		for m in ledger.get("emergeants", []):
			if str(m.get("polarite", "")) == CarnetConfig.POLARITE_NEGATIVE:
				faiblesses.append(m)
	if forces.is_empty():
		for m in ledger.get("emergeants", []):
			if str(m.get("polarite", "")) == CarnetConfig.POLARITE_POSITIVE:
				forces.append(m)

	var generated := CarnetTrainer.generate_drills(
			atoms, faiblesses, forces, curiosites)
	var merged := _merge_drills(existing, generated)

	var plan_options := options.duplicate()
	plan_options["today_iso"] = today
	plan_options["derniere_partie_id"] = _latest_game_id(pid)
	var plan := CarnetTrainer.build_plan(merged, plan_options)

	trainer["drills"] = merged
	trainer["dernier_plan_date"] = today
	trainer["competences"] = ledger.get("competences", [])
	trainer["nb_parties"] = maxi(game_count(pid), int(trainer.get("nb_parties", 0)))
	trainer["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	_save_trainer(pid, trainer)

	return {"ledger": ledger, "plan": plan, "drills": merged}

## Enregistre le résultat d'un drill : met à jour SM-2 et la série (si trouvé).
static func record_review(drill_id: String, note: int, today_iso: String = "", profile_id: String = "") -> Dictionary:
	var pid := _resolve(profile_id)
	var today := today_iso if today_iso != "" else Time.get_date_string_from_system()
	var trainer := _load_trainer(pid)
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var updated := {}
	for drill in drills:
		if drill is Dictionary and str(drill.get("drill_id", "")) == drill_id:
			CarnetTrainer.update_srs(drill, note, today)
			updated = drill
			break
	trainer["drills"] = drills
	if not updated.is_empty():
		var streak: Dictionary = {
			"serie": int(trainer.get("serie", 0)),
			"derniere_date": str(trainer.get("derniere_date", "")),
			"joker_disponible": int(trainer.get("joker_disponible", CarnetConfig.JOKER_PAR_SEMAINE)),
			"derniere_joker_date": str(trainer.get("derniere_joker_date", "")),
		}
		CarnetTrainer.update_streak(streak, today, true)
		trainer["serie"] = streak["serie"]
		trainer["derniere_date"] = streak["derniere_date"]
		trainer["joker_disponible"] = streak["joker_disponible"]
		trainer["derniere_joker_date"] = streak.get("derniere_joker_date", "")
	_save_trainer(pid, trainer)
	return updated

# ── Persistance interne ──────────────────────────────────────────────────────────

static func _load_sync(profile_id: String) -> Dictionary:
	var db := _db()
	var sync: Dictionary = db.load_json(_sync_path(profile_id)) if db != null else {}
	if not (sync.get("entries") is Dictionary):
		sync["entries"] = {}
	sync["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	return sync

static func _load_trainer(profile_id: String) -> Dictionary:
	var db := _db()
	var trainer: Dictionary = db.load_json(_trainer_path(profile_id)) if db != null else {}
	if not (trainer.get("drills") is Array):
		trainer["drills"] = []
	trainer["serie"] = int(trainer.get("serie", 0))
	trainer["joker_disponible"] = int(trainer.get("joker_disponible", CarnetConfig.JOKER_PAR_SEMAINE))
	trainer["schema_version"] = CarnetConfig.CARNET_SCHEMA_VERSION
	return trainer

static func _save_trainer(profile_id: String, trainer: Dictionary) -> void:
	var db := _db()
	if db != null:
		db.save_json_atomic(_trainer_path(profile_id), trainer)

static func _list_atom_files(profile_id: String) -> Array:
	var da := DirAccess.open(_atoms_dir(profile_id))
	if da == null:
		return []
	var out: Array = []
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not da.current_is_dir() and name.ends_with(".json"):
			out.append(name)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

static func _recent_game_ids(profile_id: String) -> Array:
	var db := _db()
	if db == null:
		return []
	var sync: Dictionary = _load_sync(profile_id).get("entries", {})
	var entries: Array = []
	for gid in sync.keys():
		entries.append({"id": str(gid), "date": str(sync[gid].get("date_iso", ""))})
	entries.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var out: Array = []
	var start: int = maxi(0, entries.size() - CarnetConfig.RECENT_GAMES)
	for i in range(start, entries.size()):
		out.append(entries[i]["id"])
	return out

static func _latest_game_id(profile_id: String) -> String:
	var db := _db()
	if db == null:
		return ""
	var sync: Dictionary = _load_sync(profile_id).get("entries", {})
	var best := ""
	var best_date := ""
	for gid in sync.keys():
		var d := str(sync[gid].get("date_iso", ""))
		if d >= best_date:
			best_date = d
			best = str(gid)
	return best

static func _merge_drills(existing: Array, generated: Array) -> Array:
	var by_key := {}
	var out: Array = []
	for drill in existing:
		if drill is Dictionary:
			by_key[_drill_key(drill)] = true
			out.append(drill)
	for drill in generated:
		if not (drill is Dictionary):
			continue
		var k := _drill_key(drill)
		if by_key.has(k):
			continue
		by_key[k] = true
		out.append(drill)
	return out

static func _drill_key(drill: Dictionary) -> String:
	return "%s|%s" % [str(drill.get("position", "")), str(drill.get("type", ""))]
