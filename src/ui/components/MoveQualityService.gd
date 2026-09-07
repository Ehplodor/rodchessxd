class_name MoveQualityService
## M3 — Taxonomie de qualité de coup partagée (pas d'échelle parallèle, cf. Annexe B).
## Seuils identiques à `GameAnalyzer._classify_move` : ≤15 EXCELLENT, ≤40 GOOD,
## ≤90 INACCURACY, ≤200 MISTAKE, >200 BLUNDER (et 1er moteur → BEST / BRILLIANT).
## Les symboles/couleurs restent centralisés sur `ChessMove.quality_to_*`.

## Perte (cp) au-delà de laquelle une "mini-barre" serait saturée (seuil gaffe).
const MAX_BAR_LOSS := 200

## Ratio 0..1 d'une perte cp (saturé au seuil de la gaffe) pour la mini-barre.
static func loss_ratio(loss_cp: int) -> float:
	return clampf(float(loss_cp) / float(MAX_BAR_LOSS), 0.0, 1.0)

## Groupe "sévérité" d'un coup (pour filtres/liste) :
## 0 = normal/positif (NONE, GOOD, EXCELLENT, GREAT, BEST, BRILLIANT)
## 1 = imprécision ?! , 2 = erreur ? , 3 = gaffe ??
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
