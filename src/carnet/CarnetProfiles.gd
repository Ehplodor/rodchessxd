class_name CarnetProfiles
extends RefCounted
## CarnetProfiles.gd — profils joueurs (carnets multiples) et rattachement des parties.
##
## Un profil = un carnet. Les parties restent partagées (`games/`) et l'analyse moteur
## est unique par partie ; seul le rattachement (profil ↔ partie ↔ perspective) est
## stocké ici. Permet d'entretenir plusieurs carnets sans réanalyser les parties.

const INDEX_PATH := "user://library/carnets/index.json"
const SCHEMA_VERSION := 1
const DEFAULT_PROFILE_ID := "default"
const DEFAULT_PROFILE_NAME := "Moi"

static func _db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_node_or_null("DatabaseManager")
	return null

# ── Persistance ─────────────────────────────────────────────────────────────────

static func _load() -> Dictionary:
	var db := _db()
	var data: Dictionary = db.load_json(INDEX_PATH) if db != null else {}
	if not data.has("profiles") or not (data.get("profiles") is Array):
		data["profiles"] = []
	if not data.has("active"):
		data["active"] = ""
	data["schema_version"] = SCHEMA_VERSION
	return data

static func _save(data: Dictionary) -> void:
	var db := _db()
	if db != null:
		db.save_json_atomic(INDEX_PATH, data)

static func list() -> Array:
	var profiles: Array = _load().get("profiles", [])
	return profiles

static func get_profile(profile_id: String) -> Dictionary:
	if profile_id == "":
		return {}
	for p in _load().get("profiles", []):
		if p is Dictionary and str(p.get("id", "")) == profile_id:
			return p
	return {}

static func _ensure_default() -> Dictionary:
	var data := _load()
	var profiles: Array = data.get("profiles", [])
	if profiles.is_empty():
		profiles.append(_make_profile(DEFAULT_PROFILE_ID, DEFAULT_PROFILE_NAME, "local", []))
		data["profiles"] = profiles
		data["active"] = DEFAULT_PROFILE_ID
		_save(data)
	return data

static func active_id() -> String:
	var data := _ensure_default()
	var active := str(data.get("active", ""))
	if active == "" or get_profile(active).is_empty():
		var profiles: Array = data.get("profiles", [])
		active = str(profiles[0].get("id", "")) if not profiles.is_empty() else DEFAULT_PROFILE_ID
		data["active"] = active
		_save(data)
	return active

static func set_active(profile_id: String) -> void:
	if get_profile(profile_id).is_empty():
		return
	var data := _load()
	data["active"] = profile_id
	_save(data)

# ── CRUD ────────────────────────────────────────────────────────────────────────

static func create(name: String, source: String = "local", player_keys: Array = []) -> String:
	var data := _ensure_default()
	var profiles: Array = data.get("profiles", [])
	var clean := name.strip_edges()
	if clean == "":
		clean = "Profil"
	var profile_id := "p_" + HashUtil.sha1_hex(clean.to_lower() + "|" + source).substr(0, 10)
	if not get_profile(profile_id).is_empty():
		return profile_id
	profiles.append(_make_profile(profile_id, clean, source, player_keys))
	data["profiles"] = profiles
	data["active"] = profile_id
	_save(data)
	return profile_id

static func update(profile_id: String, fields: Dictionary) -> void:
	var data := _load()
	var profiles: Array = data.get("profiles", [])
	for p in profiles:
		if p is Dictionary and str(p.get("id", "")) == profile_id:
			for k in fields.keys():
				p[k] = fields[k]
			break
	data["profiles"] = profiles
	_save(data)

## Supprime un profil (son dossier de carnet est retiré par CarnetStore si souhaité).
static func delete(profile_id: String) -> void:
	if profile_id == DEFAULT_PROFILE_ID:
		return
	var data := _load()
	var kept: Array = []
	for p in data.get("profiles", []):
		if p is Dictionary and str(p.get("id", "")) != profile_id:
			kept.append(p)
	data["profiles"] = kept
	if str(data.get("active", "")) == profile_id:
		data["active"] = str(kept[0].get("id", DEFAULT_PROFILE_ID)) if not kept.is_empty() else ""
	_save(data)

static func add_player_key(profile_id: String, key: String) -> void:
	var normalized := DatabaseManagerClass.normalize_player_key(key)
	if normalized == "":
		return
	var p := get_profile(profile_id)
	if p.is_empty():
		return
	var keys: Array = p.get("player_keys", [])
	if not keys.has(normalized):
		keys.append(normalized)
		update(profile_id, {"player_keys": keys})

# ── Rattachement partie ↔ profil ─────────────────────────────────────────────────

static func find_by_player_key(key: String) -> Dictionary:
	var k := DatabaseManagerClass.normalize_player_key(key)
	if k == "":
		return {}
	for p in list():
		if p is Dictionary and (p.get("player_keys", []) as Array).has(k):
			return p
	return {}

## Parties de l'index rattachables à ce profil, avec la perspective du joueur.
static func match_games(profile: Dictionary) -> Array:
	var db := _db()
	if db == null or profile.is_empty():
		return []
	var keys: Array = profile.get("player_keys", [])
	if keys.is_empty():
		return []
	var out: Array = []
	for summary in db.games_index:
		if not (summary is Dictionary):
			continue
		var gkeys: Array = summary.get("player_keys", [])
		var matched := false
		for k in keys:
			if gkeys.has(k):
				matched = true
				break
		if not matched:
			continue
		var white := DatabaseManagerClass.normalize_player_key(str(summary.get("white_name", "")))
		var black := DatabaseManagerClass.normalize_player_key(str(summary.get("black_name", "")))
		var perspective := ""
		if keys.has(white):
			perspective = "white"
		elif keys.has(black):
			perspective = "black"
		out.append({"game_id": str(summary.get("id", "")), "perspective": perspective})
	out.sort_custom(func(a, b): return str(a["game_id"]) < str(b["game_id"]))
	return out

# ── Utilitaires ──────────────────────────────────────────────────────────────────

static func _make_profile(id: String, name: String, source: String, player_keys: Array) -> Dictionary:
	var keys: Array = []
	for k in player_keys:
		var n := DatabaseManagerClass.normalize_player_key(str(k))
		if n != "" and not keys.has(n):
			keys.append(n)
	return {
		"id": id,
		"name": name,
		"source": source,
		"player_keys": keys,
		"created_at": int(Time.get_unix_time_from_system()),
	}

## Réinitialise profils + données de test (usage tests uniquement).
static func reset() -> void:
	var db := _db()
	if db != null:
		db.remove_file(INDEX_PATH)
	_remove_dir_recursive(DatabaseManagerClass.PROFILES_DIR)

static func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		DirAccess.remove_absolute(path)
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if name != "." and name != "..":
			if da.current_is_dir():
				_remove_dir_recursive(path + "/" + name)
			else:
				da.remove(name)
		name = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
