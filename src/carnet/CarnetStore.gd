class_name CarnetStore
extends RefCounted
## CarnetStore.gd — persistance et orchestration de LeCarnet (§4.12-4.13).
##
## Point d'entrée applicatif : ingère les atomes (Étage 1) par partie dans
## `DatabaseManager`, compile le carnet (Étage 2) et génère le plan du jour (Étage 3).
## Idempotent : ré-ingérer une partie remplace ses événements (clé event_id). Aucune
## horloge implicite en dehors de la date locale ; deux exécutions donnent le même plan.

const SCHEMA_VERSION := 1

static func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DatabaseManager")
	return null

# ── Ingestion / suppression (§4.12) ──────────────────────────────────────────────

## Remplace les atomes d'une partie (idempotent) et retire ses anciens drills.
static func ingest_game(game_id: String, atoms: Array, meta: Dictionary = {}) -> void:
	var db := _db()
	if db == null or game_id == "":
		return
	var carnet: Dictionary = db.get_carnet()
	var games: Dictionary = carnet.get("games", {})
	games[game_id] = {
		"date_iso": str(meta.get("date_iso", "")),
		"couleur_joueur": str(meta.get("couleur_joueur", "")),
		"result": str(meta.get("result", "")),
		"cadence": str(meta.get("cadence", "")),
		"atoms": atoms,
	}
	carnet["games"] = games
	_drop_game_drills(carnet, game_id)
	carnet["schema_version"] = SCHEMA_VERSION
	db.save_carnet(carnet)

## Supprime une partie, ses événements et ses drills, puis recalcule implicitement
## (le prochain `compile()` repart des atomes restants).
static func remove_game(game_id: String) -> void:
	var db := _db()
	if db == null:
		return
	var carnet: Dictionary = db.get_carnet()
	var games: Dictionary = carnet.get("games", {})
	games.erase(game_id)
	carnet["games"] = games
	_drop_game_drills(carnet, game_id)
	db.save_carnet(carnet)

static func _drop_game_drills(carnet: Dictionary, game_id: String) -> void:
	var trainer: Dictionary = carnet.get("trainer", {})
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var kept: Array = []
	for drill in drills:
		if drill is Dictionary and str(drill.get("game_id", "")) != game_id:
			kept.append(drill)
	trainer["drills"] = kept
	carnet["trainer"] = trainer

## Tous les atomes persistés, aplatis (ordre stable : date puis partie/ply).
static func get_atoms() -> Array:
	var db := _db()
	if db == null:
		return []
	return _atoms_from(db.get_carnet())

static func _atoms_from(carnet: Dictionary) -> Array:
	var out: Array = []
	var games: Dictionary = carnet.get("games", {})
	var ids: Array = games.keys()
	ids.sort()
	for gid in ids:
		var entry: Dictionary = games[gid]
		for atom in entry.get("atoms", []):
			if atom is Dictionary:
				out.append(atom)
	return out

static func game_count() -> int:
	var db := _db()
	if db == null:
		return 0
	return int(db.get_carnet().get("games", {}).size())

# ── Compilation & plan ───────────────────────────────────────────────────────────

## Compile le carnet complet (Étage 1 → Étage 2). `nb_parties` optionnel.
static func compile(today_iso: String = "", nb_parties: int = -1) -> Dictionary:
	var db := _db()
	if db == null:
		return CarnetLedger.compile([], {"nb_parties": 0})
	return _compile_from(db.get_carnet(), today_iso, nb_parties)

static func _compile_from(carnet: Dictionary, today_iso: String, nb_parties: int) -> Dictionary:
	var atoms := _atoms_from(carnet)
	var games: Dictionary = carnet.get("games", {})
	var g: int = nb_parties if nb_parties >= 0 else games.size()
	var options := {
		"nb_parties": g,
		"today_iso": today_iso if today_iso != "" else Time.get_date_string_from_system(),
		"recent_game_ids": _recent_game_ids(games),
	}
	return CarnetLedger.compile(atoms, options)

## Compile puis génère/maintient les drills et compose LePlan du jour (Étage 3).
static func refresh_plan(today_iso: String = "", options: Dictionary = {}) -> Dictionary:
	var today := today_iso if today_iso != "" else Time.get_date_string_from_system()
	var db := _db()
	var carnet: Dictionary = db.get_carnet() if db != null else {}
	var ledger := _compile_from(carnet, today, -1)
	var atoms := _atoms_from(carnet)
	var trainer: Dictionary = carnet.get("trainer", {})
	var existing: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []

	var generated := CarnetTrainer.generate_drills(
			atoms, ledger.get("faiblesses", []), ledger.get("forces", []), ledger.get("curiosites", []))
	var merged := _merge_drills(existing, generated)

	var plan_options := options.duplicate()
	plan_options["today_iso"] = today
	plan_options["derniere_partie_id"] = _latest_game_id(carnet)
	var plan := CarnetTrainer.build_plan(merged, plan_options)

	trainer["drills"] = merged
	trainer["dernier_plan_date"] = today
	trainer["competences"] = ledger.get("competences", [])
	trainer["serie"] = int(trainer.get("serie", 0))
	trainer["joker_disponible"] = int(trainer.get("joker_disponible", CarnetConfig.JOKER_PAR_SEMAINE))
	carnet["trainer"] = trainer
	carnet["schema_version"] = SCHEMA_VERSION
	if db != null:
		db.save_carnet(carnet)

	return {"ledger": ledger, "plan": plan, "drills": merged}

## Enregistre le résultat d'un drill : met à jour SM-2 et la série.
static func record_review(drill_id: String, note: int, today_iso: String = "") -> Dictionary:
	var db := _db()
	var today := today_iso if today_iso != "" else Time.get_date_string_from_system()
	if db == null:
		return {}
	var carnet: Dictionary = db.get_carnet()
	var trainer: Dictionary = carnet.get("trainer", {})
	var drills: Array = trainer.get("drills", []) if trainer.get("drills", []) is Array else []
	var updated := {}
	for drill in drills:
		if drill is Dictionary and str(drill.get("drill_id", "")) == drill_id:
			CarnetTrainer.update_srs(drill, note, today)
			updated = drill
			break
	trainer["drills"] = drills
	# N'incrémente la série que si le drill a réellement été trouvé et travaillé.
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
	carnet["trainer"] = trainer
	db.save_carnet(carnet)
	return updated

static func get_trainer_state() -> Dictionary:
	var db := _db()
	if db == null:
		return {}
	return db.get_carnet().get("trainer", {})

# ── Helpers ──────────────────────────────────────────────────────────────────────

static func _merge_drills(existing: Array, generated: Array) -> Array:
	var by_key := {}
	var out: Array = []
	for drill in existing:
		if drill is Dictionary:
			var k := _drill_key(drill)
			by_key[k] = true
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

static func _recent_game_ids(games: Dictionary) -> Array:
	var entries: Array = []
	for gid in games.keys():
		entries.append({"id": str(gid), "date": str(games[gid].get("date_iso", ""))})
	entries.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	var out: Array = []
	var start: int = maxi(0, entries.size() - CarnetConfig.RECENT_GAMES)
	for i in range(start, entries.size()):
		out.append(entries[i]["id"])
	return out

static func _latest_game_id(carnet: Dictionary) -> String:
	var games: Dictionary = carnet.get("games", {})
	var best := ""
	var best_date := ""
	for gid in games.keys():
		var d := str(games[gid].get("date_iso", ""))
		if d >= best_date:
			best_date = d
			best = str(gid)
	return best
