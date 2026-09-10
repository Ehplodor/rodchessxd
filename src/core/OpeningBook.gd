class_name OpeningBook
extends RefCounted
## OpeningBook.gd - Identification d'ouverture / sortie de théorie (T1.2).
## Table ECO/ouvertures embarquée (texte JSON, pas de binaire polyglot).
## IMPORTANT : ne jamais lancer d'erreur bloquante si la table est absente.

const DATA_PATH := "res://assets/openings/eco_openings.json"

static var _cache: Array = []
static var _loaded := false

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = []
	if not FileAccess.file_exists(DATA_PATH):
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and entry.has("moves"):
				_cache.append(entry)

## Plus longue correspondance de préfixe sur la suite de coups (UCI).
## Retourne {eco, name, out_of_book_ply}.
static func identify(moves_uci: Array) -> Dictionary:
	_load()
	var best: Dictionary = {}
	var best_len := 0
	for entry in _cache:
		var seq := str(entry.get("moves", "")).split(" ", false)
		if seq.is_empty():
			continue
		var ok := true
		for i in range(seq.size()):
			if i >= moves_uci.size() or str(moves_uci[i]) != str(seq[i]):
				ok = false
				break
		if ok and seq.size() > best_len:
			best = entry
			best_len = seq.size()
	if best.is_empty():
		return {"eco": "", "name": "", "out_of_book_ply": 0}
	return {
		"eco": str(best.get("eco", "")),
		"name": str(best.get("name", "")),
		"out_of_book_ply": best_len
	}
