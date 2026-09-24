class_name PlayerSide
extends RefCounted
## PlayerSide.gd — Camp joué par l'utilisateur dans la partie chargée.
## Ordre : profil Carnet actif (noms PGN) → réglage coach_perspective → échiquier retourné → Blancs.

const DatabaseManagerClass = preload("res://src/core/DatabaseManager.gd")
const CarnetProfiles = preload("res://src/carnet/CarnetProfiles.gd")

## Cœur pur (testable) : "white" ou "black".
static func resolve_from(white_name: String, black_name: String, player_keys: Array,
		coach_perspective: String, board_flipped: bool) -> String:
	var w := DatabaseManagerClass.normalize_player_key(white_name)
	var b := DatabaseManagerClass.normalize_player_key(black_name)
	if w != "" and player_keys.has(w):
		return "white"
	if b != "" and player_keys.has(b):
		return "black"
	if coach_perspective == "white" or coach_perspective == "black":
		return coach_perspective
	return "black" if board_flipped else "white"

static func resolve(game) -> String:
	var headers: Dictionary = game.pgn_headers if game != null else {}
	var keys: Array = []
	var profile := CarnetProfiles.get_profile(CarnetProfiles.active_id())
	if not profile.is_empty():
		keys = profile.get("player_keys", [])
	var root := (Engine.get_main_loop() as SceneTree).root
	var sm := root.get_node_or_null("SettingsManager")
	var gc := root.get_node_or_null("GameController")
	var coach := str(sm.get_setting("coach_perspective", "")) if sm != null else ""
	var flipped := bool(gc.board_flipped) if gc != null else false
	return resolve_from(str(headers.get("White", "")), str(headers.get("Black", "")), keys, coach, flipped)
