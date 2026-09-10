class_name GamePhaseService
extends RefCounted
## GamePhaseService.gd - Détermine la phase (ouverture / milieu / finale) d'une position.
## Facteur commun entre le rapport de partie (T1.3) et les métriques par phase.

const OPENING_MIN_PLIES := 10

## Phase pour un demi-coup donné. `ply` = index du demi-coup (0-based) ; les premiers
## plies de théorie (ou au moins 5 coups complets) comptent comme ouverture.
static func phase_for(fen: String, ply: int, out_of_book_ply: int = 0) -> String:
	if ply < maxi(out_of_book_ply, OPENING_MIN_PLIES):
		return "opening"
	if is_endgame_fen(fen):
		return "endgame"
	return "middlegame"

## Finale : plus de dames, ou matériel lourd (hors pions) très réduit.
static func is_endgame_fen(fen: String) -> bool:
	if fen == "":
		return false
	var parts := fen.split(" ")
	var board_str := parts[0] if parts.size() > 0 else ""
	var queens := 0
	var nonpawn_value := 0
	for c in board_str:
		match c.to_upper():
			"Q":
				queens += 1
				nonpawn_value += 9
			"R":
				nonpawn_value += 5
			"B", "N":
				nonpawn_value += 3
	return queens == 0 or nonpawn_value <= 12

static func phase_label_fr(phase: String) -> String:
	match phase:
		"opening": return "Ouverture"
		"endgame": return "Finale"
		_: return "Milieu de jeu"
