class_name MoveQualityService
## M3/T0 — Taxonomie de qualité de coup partagée (pas d'échelle parallèle, cf. Annexe B).
## Classification par **perte de probabilité de gain (win%)** (T0.2), plus robuste que la
## perte brute en centipions : un coup qui lâche 200 cp dans une position déjà gagnante
## n'est pas une gaffe. Les symboles/couleurs restent centralisés sur `ChessMove.quality_to_*`.

## Perte (cp) au-delà de laquelle une "mini-barre" serait saturée (seuil gaffe).
const MAX_BAR_LOSS := 200

## Seuils de perte de win% (points de %) entre l'évaluation avant et après le coup.
## Valeurs par défaut type Lichess, ajustables (calibration beta).
const WINPCT_INACCURACY := 10.0
const WINPCT_MISTAKE := 20.0
const WINPCT_BLUNDER := 30.0

## Écart de win% entre le meilleur coup et la 2e meilleure ligne à partir duquel le
## meilleur coup est considéré « seul coup préservant le résultat » (GREAT).
const WINPCT_ONLY_MOVE := 15.0

## Ratio 0..1 d'une perte cp (saturé au seuil de la gaffe) pour la mini-barre.
static func loss_ratio(loss_cp: int) -> float:
	return clampf(float(loss_cp) / float(MAX_BAR_LOSS), 0.0, 1.0)

## Groupe "sévérité" d'un coup (pour filtres/liste) :
## 0 = normal/positif (NONE, GOOD, EXCELLENT, GREAT, BEST, BRILLIANT)
## 1 = imprécision ?! , 2 = erreur ? , 3 = gaffe ?? / occasion manquée X
static func group(q: int) -> int:
	match q:
		ChessMove.Quality.INACCURACY:
			return 1
		ChessMove.Quality.MISTAKE:
			return 2
		ChessMove.Quality.BLUNDER, ChessMove.Quality.MISS:
			return 3
		_:
			return 0

## Vrai si le coup est une imprécision/erreur/gaffe.
static func is_problem(q: int) -> bool:
	return group(q) > 0

## Conversion centipions -> probabilité de gain (modèle sigmoïde standard FIDE/Lichess),
## du point de vue des Blancs (100 = Blancs gagnants).
static func win_percentage(score_cp: int) -> float:
	if absi(score_cp) >= EvalFormatter.MATE_CP:
		return 100.0 if score_cp > 0 else 0.0
	return 100.0 / (1.0 + exp(-0.00368208 * float(score_cp)))

## Probabilité de gain du camp donné (0..100) pour un score orienté Blancs.
static func win_for(score_cp: int, is_white: bool) -> float:
	var wp := win_percentage(score_cp)
	return wp if is_white else (100.0 - wp)

## Perte de probabilité de gain (>= 0) pour le camp qui vient de jouer.
static func winpct_loss(win_before: float, win_after: float) -> float:
	return maxf(0.0, win_before - win_after)

## Classification d'un coup joué.
## - `is_white` : camp qui vient de jouer (oriente la win%).
## - `score_before` / `score_after` : évaluations en centipions, point de vue Blancs.
## - `best_second_score_before` : éval (Blancs) de la 2e meilleure ligne dans la position
##   AVANT le coup, si connue (MultiPV) ; sentinelle `NO_SECOND_LINE` sinon.
## - `is_sacrifice` : calculé via `is_sacrifice()` (T0.3).
const NO_SECOND_LINE := -999999

static func classify(
		played_uci: String,
		best_uci: String,
		score_before: int,
		score_after: int,
		loss_cp: int,
		is_white: bool,
		is_sacrifice: bool = false,
		best_second_score_before: int = NO_SECOND_LINE
	) -> int:
	var win_before := win_for(score_before, is_white)
	var win_after := win_for(score_after, is_white)

	if played_uci != "" and played_uci == best_uci:
		if is_sacrifice and win_after < 95.0:
			return ChessMove.Quality.BRILLIANT
		if best_second_score_before != NO_SECOND_LINE:
			var win_second := win_for(best_second_score_before, is_white)
			if win_before - win_second >= WINPCT_ONLY_MOVE and win_before >= 35.0:
				return ChessMove.Quality.GREAT
		return ChessMove.Quality.BEST

	var drop := winpct_loss(win_before, win_after)
	if drop >= WINPCT_BLUNDER:
		# Occasion de gain nette gâchée = MISS ; sinon gaffe classique.
		return ChessMove.Quality.MISS if win_before >= 70.0 else ChessMove.Quality.BLUNDER
	if drop >= WINPCT_MISTAKE:
		return ChessMove.Quality.MISTAKE
	if drop >= WINPCT_INACCURACY:
		return ChessMove.Quality.INACCURACY
	if loss_cp <= 15:
		return ChessMove.Quality.EXCELLENT
	return ChessMove.Quality.GOOD

## Détecte un sacrifice : le camp qui joue accepte une perte matérielle nette
## (>= 1 pion) sur les premiers coups de la ligne principale, tout en gardant le
## meilleur coup du moteur. Cf. T0.3.
static func is_sacrifice(fen_before: String, played_uci: String, pv: Array) -> bool:
	if played_uci == "" or fen_before == "":
		return false
	var game := ChessGame.new()
	if not game.load_fen(fen_before):
		return false
	var mover_color := game.active_color
	var material_before := _material_for(game, mover_color)
	var played := game.find_move(played_uci)
	if played == null:
		return false
	game.make_move(played)
	var min_material := _material_for(game, mover_color)

	var steps := 0
	for token in pv:
		if steps >= 6:
			break
		if str(token) == played_uci and steps == 0:
			steps += 1
			continue
		var mv := game.find_move(str(token))
		if mv == null:
			break
		game.make_move(mv)
		min_material = mini(min_material, _material_for(game, mover_color))
		steps += 1

	return (material_before - min_material) >= ChessPiece.VALUES[ChessPiece.Type.PAWN]

static func _material_for(game: ChessGame, color: int) -> int:
	var total := 0
	for sq in range(64):
		var piece: Dictionary = game.board[sq]
		if int(piece.get("color", ChessPiece.PieceColor.NONE)) == color:
			total += int(ChessPiece.VALUES.get(int(piece.get("type", ChessPiece.Type.NONE)), 0))
	return total
