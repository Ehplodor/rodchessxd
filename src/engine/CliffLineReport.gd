class_name CliffLineReport
extends RefCounted
## CliffLineReport.gd — Conteneur et helpers pour le rapport d'analyse CHESS-CLIFF.

const CliffTypes = preload("res://src/engine/CliffTypes.gd")

var data: Dictionary = {}

func _init(p_data: Dictionary = {}) -> void:
	data = p_data

func get_plies() -> Array:
	return data.get("plies", [])

func get_plies_count() -> int:
	return get_plies().size()

func get_ply(index: int) -> Dictionary:
	var plies: Array = get_plies()
	if index >= 0 and index < plies.size():
		return plies[index]
	return {}

func get_piste_for_ply(index: int) -> int:
	var p = get_ply(index)
	return int(p.get("piste", CliffTypes.Piste.AUTOROUTE))

func get_summary(side: String) -> Dictionary:
	if side.to_lower() == "white":
		return data.get("summary_white", {})
	elif side.to_lower() == "black":
		return data.get("summary_black", {})
	return {}

func get_summary_white() -> Dictionary:
	return get_summary("white")

func get_summary_black() -> Dictionary:
	return get_summary("black")

func to_dict() -> Dictionary:
	return data.duplicate(true)

static func from_dict(d: Dictionary) -> CliffLineReport:
	var copy := d.duplicate(true)
	# Rétrocompatibilité : normalise les champs des anciens rapports V1
	var plies: Array = copy.get("plies", [])
	for p in plies:
		if p is Dictionary:
			if not p.has("move_uci") and p.has("played_uci"):
				p["move_uci"] = p["played_uci"]
			if not p.has("fen_after") and p.has("fen"):
				p["fen_after"] = p["fen"]
			if not p.has("step") and p.has("ply"):
				p["step"] = p["ply"]
	return CliffLineReport.new(copy)

## Métadonnées de provenance : la ligne Stockfish réellement étudiée.
## { "fen": String, "depth": int, "rank": int, "engine": String }
func get_source_meta() -> Dictionary:
	return data.get("source_meta", {})

## Sémantique des résumés (cf. CliffTypes.SEMANTICS).
func get_semantics() -> String:
	return str(data.get("semantics", CliffTypes.SEMANTICS))

## Levier tactique au demi-coup index : pression infligée - effort consenti
func get_tactical_leverage(index: int) -> int:
	var p := get_ply(index)
	return int(p.get("leverage", int(p.get("pression_d", 0)) - int(p.get("indice_d", 0))))

## Retourne le premier point de rupture critique s'il existe dans la ligne/partie
func get_rupture_point() -> Dictionary:
	var plies: Array = get_plies()
	for i in range(plies.size()):
		var p: Dictionary = plies[i]
		var delta: float = float(p.get("delta_chute", 0.0))
		var survie: float = float(p.get("p_survie", 1.0))
		if delta >= 0.35 or survie < 0.05:
			return {"index": i, "ply_data": p}
	return {}

## Vrai si ce rapport porte sur une autre position/profondeur que celles demandées
## (carte périmée après une mise à jour du Live ou un changement de ligne).
func is_stale_against(fen: String, depth: int) -> bool:
	var meta := get_source_meta()
	if meta.is_empty():
		return false
	var src_fen := str(meta.get("fen", ""))
	var src_depth := int(meta.get("depth", -1))
	if fen != "" and src_fen != "" and src_fen != fen:
		return true
	if depth > 0 and src_depth > 0 and depth > src_depth:
		return true
	return false

## Génère un résumé narratif synthétique de la confrontation cognitive.
func get_narrative_summary() -> String:
	var sw = get_summary_white()
	var sb = get_summary_black()
	if sw.is_empty() or sb.is_empty():
		return "Analyse CLIFF non disponible."

	var pw: int = int(sw.get("global_piste", CliffTypes.Piste.AUTOROUTE))
	var pb: int = int(sb.get("global_piste", CliffTypes.Piste.AUTOROUTE))
	var name_w := CliffTypes.get_piste_name(pw)
	var name_b := CliffTypes.get_piste_name(pb)
	var icon_w := CliffTypes.get_piste_icon(pw)
	var icon_b := CliffTypes.get_piste_icon(pb)

	var rupture := get_rupture_point()
	var rupture_suffix := ""
	if not rupture.is_empty():
		var r_idx: int = int(rupture.get("index", 0))
		var r_ply: Dictionary = rupture.get("ply_data", {})
		var r_san: String = str(r_ply.get("san", r_ply.get("move_uci", "?")))
		rupture_suffix = " · Décrochage critique au coup %s (coup #%d)" % [r_san, r_idx + 1]

	if pw == pb:
		var dw: int = int(sw.get("indice_d", 0))
		var db: int = int(sb.get("indice_d", 0))
		if absi(dw - db) >= 15:
			var harder := "les Blancs" if dw > db else "les Noirs"
			var easier := "les Noirs" if dw > db else "les Blancs"
			return "Même piste (%s %s), mais la charge est nettement plus lourde pour %s (D=%d) que pour %s (D=%d)%s." % [
				icon_w, name_w, harder, maxi(dw, db), easier, mini(dw, db), rupture_suffix
			]
		if not rupture.is_empty():
			var r_side := "les Blancs" if bool(rupture.get("ply_data", {}).get("is_white", true)) else "les Noirs"
			return "Ligne sous tension : %s subissent un décrochage critique au coup %s (coup #%d)." % [
				r_side, str(rupture.get("ply_data", {}).get("san", "?")), int(rupture.get("index", 0)) + 1
			]
		return "Confrontation équilibrée : les deux camps évoluent sur une %s %s." % [icon_w, name_w]
	else:
		return "Asymétrie cognitive : les Blancs évoluent sur une %s %s tandis que les Noirs font face à une %s %s%s." % [
			icon_w, name_w, icon_b, name_b, rupture_suffix
		]
