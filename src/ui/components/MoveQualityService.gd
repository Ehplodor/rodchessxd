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

## ── Complexité positionnelle (moteur ELO avancé, points 1/2/4 du plan) ──
## Source unique des seuils : GameAnalyzer (pondération ELO) et Carnet lisent ici.
## Poids réduit : coup forcé (unique légal) — peu de mérite à le trouver.
const COMPLEXITY_FORCED := 0.25
## Poids réduit : recapture évidente sur la case de la capture adverse précédente.
const COMPLEXITY_TRIVIAL_RECAPTURE := 0.35
## Poids neutre : position « plurielle » (plusieurs coups équivalents, risque de gaffe faible).
const COMPLEXITY_NEUTRAL := 0.85
## Poids de base d'un coup unique critique (Δ 2e ligne ≥ WINPCT_ONLY_MOVE).
const COMPLEXITY_UNIQUE_BASE := 1.0
## Diviseur du bonus héroïque : Δ 2e ligne / 30 → jusqu'à +1.0 (soit 2.0× au total).
const COMPLEXITY_HERO_DIVISOR := 30.0
const COMPLEXITY_MIN := 0.25
const COMPLEXITY_MAX := 2.0

## Indice de complexité d'un demi-coup C ∈ [COMPLEXITY_MIN, COMPLEXITY_MAX].
## - `legal_moves_count` : nb de coups légaux avant le coup (-1 si inconnu).
## - `is_recapture` : capture de reprise évidente sur la case de la capture adverse.
## - `second_gap_winpct` : écart de win% (points) entre la 1re et la 2e ligne MultiPV
##   (point de vue du camp qui joue) ; < 0 si la 2e ligne est inconnue.
static func move_complexity(legal_moves_count: int, is_recapture: bool, second_gap_winpct: float) -> float:
	if legal_moves_count >= 0 and legal_moves_count <= 1:
		return COMPLEXITY_FORCED
	if is_recapture:
		return COMPLEXITY_TRIVIAL_RECAPTURE
	if second_gap_winpct >= WINPCT_ONLY_MOVE:
		return minf(COMPLEXITY_MAX, COMPLEXITY_UNIQUE_BASE + minf(1.0, second_gap_winpct / COMPLEXITY_HERO_DIVISOR))
	return COMPLEXITY_NEUTRAL

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
	var material := material_before
	# Le coup joué peut lui-même capturer : créditer avant de suivre la PV (sinon
	# un échange égal type Qxd8 Rxd8 serait vu comme un sacrifice).
	if int(played.captured_piece) != ChessPiece.Type.NONE:
		material += int(ChessPiece.VALUES.get(int(played.captured_piece), 0))
	game.make_move(played)

	# Suivi incrémental du matériel du camp qui a joué (pas de rescan 64 cases par ply).
	var threshold: int = int(ChessPiece.VALUES[ChessPiece.Type.PAWN])
	var steps := 0
	for token in pv:
		if steps >= 6:
			break
		if steps == 0 and str(token) == played_uci:
			steps += 1
			continue
		var mv := game.find_move(str(token))
		if mv == null:
			break
		if int(mv.captured_piece) != ChessPiece.Type.NONE:
			var captured_value: int = int(ChessPiece.VALUES.get(int(mv.captured_piece), 0))
			if int(mv.color) == mover_color:
				material += captured_value
			else:
				material -= captured_value
		game.make_move(mv)
		if material_before - material >= threshold:
			return true
		steps += 1

	return false

static func _material_for(game: ChessGame, color: int) -> int:
	var total := 0
	for sq in range(64):
		var piece: Dictionary = game.board[sq]
		if int(piece.get("color", ChessPiece.PieceColor.NONE)) == color:
			total += int(ChessPiece.VALUES.get(int(piece.get("type", ChessPiece.Type.NONE)), 0))
	return total
