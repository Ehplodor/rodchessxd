class_name CliffMath
extends RefCounted
## CliffMath.gd — Couche mathématique pure pour CHESS-CLIFF (sans état, 100% statique).
## Implémente toutes les équations de Boltzmann, saillance cognitive, chute et classification.

const ChessPiece = preload("res://src/core/ChessPiece.gd")
const MoveQualityService = preload("res://src/ui/components/MoveQualityService.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")

## 1. Probabilité WDL (0.0 à 1.0) du point de vue du camp qui joue.
## Intègre le cas des mats forcés (+mat / -mat).
static func wdl(score_cp: int, mate_in: int = 0) -> float:
	if mate_in != 0:
		if mate_in > 0:
			# Nous matons dans mate_in coups -> proche de 1.0
			return clampf(1.0 - float(mate_in) / 1000.0, 0.95, 1.0)
		else:
			# Nous sommes matés dans abs(mate_in) coups -> proche de 0.0
			return clampf(float(absi(mate_in)) / 1000.0, 0.0, 0.05)
	
	if absi(score_cp) >= 30000:
		return 1.0 if score_cp > 0 else 0.0

	return clampf(MoveQualityService.win_percentage(score_cp) / 100.0, 0.0, 1.0)

## Valeur en points d'une pièce pour le calcul du ratio de capture.
static func piece_point_value(piece_type: int) -> float:
	match piece_type:
		ChessPiece.Type.PAWN:
			return 1.0
		ChessPiece.Type.KNIGHT, ChessPiece.Type.BISHOP:
			return 3.0
		ChessPiece.Type.ROOK:
			return 5.0
		ChessPiece.Type.QUEEN:
			return 9.0
		_:
			return 1.0

## 2. Saillance visuelle cognitive s(m).
## move_dict contient : is_check, captured_piece, piece, from_sq, to_sq, color.
static func saillance(move_dict: Dictionary) -> float:
	var is_check: bool = bool(move_dict.get("is_check", false))
	var captured: int = int(move_dict.get("captured_piece", ChessPiece.Type.NONE))
	var piece: int = int(move_dict.get("piece", ChessPiece.Type.PAWN))
	var from_sq: int = int(move_dict.get("from_sq", -1))
	var to_sq: int = int(move_dict.get("to_sq", -1))
	var color: int = int(move_dict.get("color", ChessPiece.PieceColor.WHITE))

	# Ratio de capture borné pour éviter une disproportion excessive par rapport à W_CHECK
	var capture_ratio := 0.0
	if captured != ChessPiece.Type.NONE and captured != 0:
		var val_tgt := piece_point_value(captured)
		var val_src := piece_point_value(piece)
		capture_ratio = clampf(val_tgt / maxf(1.0, val_src), 0.2, 2.0)

	# Avance / Recul
	var avance := 0.0
	var recul := 0.0
	if from_sq >= 0 and to_sq >= 0:
		var from_rank := from_sq / 8
		var to_rank := to_sq / 8
		var delta_rank := (to_rank - from_rank) if color == ChessPiece.PieceColor.WHITE else (from_rank - to_rank)
		var normalized := float(delta_rank) / 7.0
		if normalized > 0.0:
			avance = clampf(normalized, 0.0, 1.0)
		elif normalized < 0.0:
			recul = clampf(-normalized, 0.0, 1.0)

	var s := (CliffTypes.W_CHECK * (1.0 if is_check else 0.0)
		+ CliffTypes.W_CAPTURE * capture_ratio
		+ CliffTypes.W_FORWARD * avance
		- CliffTypes.W_BACKWARD * recul)
	return s

## 3. Valeur perçue intuitive d'un coup V_perçu(m) = WDL_statique(m) + saillance(m).
static func v_percu(wdl_static: float, s: float) -> float:
	return wdl_static + s

## 4. Appât / piège naturel Bait(m) = max(0, V_perçu(m) - WDL_deep(m)).
static func bait(v_percu_m: float, wdl_deep_m: float) -> float:
	return maxf(0.0, v_percu_m - wdl_deep_m)

## 5. Distribution Boltzmann P_humain(m) = exp(β·V_i) / Σ exp(β·V_j).
## Protégé contre les overflows numériques par soustraction du maximum.
static func p_humain_distribution(v_percu_all: Array) -> Array[float]:
	var result: Array[float] = []
	var n := v_percu_all.size()
	if n == 0:
		return result
	if n == 1:
		result.append(1.0)
		return result

	var max_v := -999999.0
	for v in v_percu_all:
		var f := float(v)
		if f > max_v:
			max_v = f

	var exp_vals: Array[float] = []
	var sum_exp := 0.0
	for v in v_percu_all:
		var e := exp(CliffTypes.BETA * (float(v) - max_v))
		exp_vals.append(e)
		sum_exp += e

	if sum_exp <= 0.000001:
		var uniform := 1.0 / float(n)
		for i in range(n):
			result.append(uniform)
		return result

	for e in exp_vals:
		result.append(e / sum_exp)
	return result

## 6. Détection de suite tactiquement forcée (échec, reprise, pièce en prise, tension).
static func is_suite_forcee(prev_was_check: bool, is_recapture: bool, material_en_prise: bool, tension_materielle: bool) -> bool:
	return prev_was_check or is_recapture or material_en_prise or tension_materielle

## 7. Probabilité de survie sur un demi-coup : P_SUITE_FORCEE si forcé,
## sinon somme des probabilités des coups viables M_ok.
## Si viable_p_sum < 0.0, fallback sur p_humain_best pour rétrocompatibilité.
static func p_survie(is_forcee: bool, p_humain_best: float, viable_p_sum: float = -1.0) -> float:
	if is_forcee:
		return CliffTypes.P_SUITE_FORCEE
	if viable_p_sum >= 0.0:
		return clampf(viable_p_sum, 0.0, 1.0)
	return clampf(p_humain_best, 0.0, 1.0)

## 7b. Retourne les indices des coups viables (écart WDL <= seuil tolérance).
static func get_viable_indices(wdl_all: Array, wdl_best: float) -> Array[int]:
	var viable: Array[int] = []
	for i in range(wdl_all.size()):
		if (wdl_best - float(wdl_all[i])) <= (CliffTypes.WDL_MOK_TOLERANCE + 0.0001):
			viable.append(i)
	return viable

## 8. Chute fatale Δ_chute = WDL_best - WDL_second.
static func delta_chute(wdl_best: float, wdl_second: float) -> float:
	return maxf(0.0, wdl_best - wdl_second)

## 9. Entropie de mobilité viable H_mob (Shannon en bits log2).
## Filtre les coups viables M_ok et calcule l'entropie de dispersion de P_humain.
static func h_mob(wdl_all: Array, wdl_best: float, p_humain_all: Array) -> float:
	var n := wdl_all.size()
	if n <= 1 or p_humain_all.size() != n:
		return 0.0

	var viable_indices := get_viable_indices(wdl_all, wdl_best)

	if viable_indices.size() <= 1:
		return 0.0

	var sum_p := 0.0
	for idx in viable_indices:
		sum_p += float(p_humain_all[idx])

	if sum_p <= 0.000001:
		return 0.0

	var entropy := 0.0
	var ln2 := log(2.0)
	for idx in viable_indices:
		var p_renorm := float(p_humain_all[idx]) / sum_p
		if p_renorm > 0.000001:
			entropy -= p_renorm * (log(p_renorm) / ln2)

	return maxf(0.0, entropy)

## 10. Probabilité de survie cumulée de la ligne Π P_survie(t).
static func p_survie_ligne(p_survie_array: Array) -> float:
	if p_survie_array.is_empty():
		return 1.0
	var prod := 1.0
	for p in p_survie_array:
		prod *= clampf(float(p), 0.0, 1.0)
	return clampf(prod, 0.0, 1.0)

## 10b. Survie locale sur horizon glissant H=4 demi-coups (évite l'effondrement à zéro).
static func p_survie_horizon_min(p_survie_array: Array, window_size: int = CliffTypes.HORIZON_PLIES) -> float:
	var n := p_survie_array.size()
	if n == 0:
		return 1.0
	if n <= window_size:
		return p_survie_ligne(p_survie_array)

	var min_window := 1.0
	for i in range(n - window_size + 1):
		var win_prod := 1.0
		for j in range(window_size):
			win_prod *= clampf(float(p_survie_array[i + j]), 0.0, 1.0)
		if win_prod < min_window:
			min_window = win_prod
	return clampf(min_window, 0.0, 1.0)

## 11. Indice composite de difficulté cognitive D ∈ [0, 100].
## Formule stabilisée : évite la division raide par zéro ou l'explosion quand H_mob = 0.
static func indice_d(delta_array: Array, p_survie_array: Array, bait_array: Array, h_mob_avg: float) -> int:
	var n := delta_array.size()
	if n == 0:
		return 0

	var sum_num := 0.0
	for i in range(n):
		var d_val := float(delta_array[i]) if i < delta_array.size() else 0.0
		var p_val := float(p_survie_array[i]) if i < p_survie_array.size() else 1.0
		var b_val := float(bait_array[i]) if i < bait_array.size() else 0.0
		sum_num += (CliffTypes.D_WEIGHT_CHUTE * d_val
			+ CliffTypes.D_WEIGHT_SURVIE * (1.0 - p_val)
			+ CliffTypes.D_WEIGHT_BAIT * b_val)

	var avg_num := sum_num / float(n)
	# Multiplicateur de restriction de mobilité : de 1.0 (large mobilité >= 1.5 bit) à 1.45 (coup unique H_mob = 0)
	var mob_mult := 1.0 + 0.30 * clampf(1.5 - h_mob_avg, 0.0, 1.5)
	var raw_d := (avg_num * mob_mult) / 1.15
	return clampi(int(round(raw_d)), 0, 100)

## 12. Classification par « piste » (matrice de décision classique).
static func classify_piste(p_ligne: float, delta_max: float, bait_max: float) -> CliffTypes.Piste:
	if p_ligne < CliffTypes.P_FIL_LO:
		return CliffTypes.Piste.CHAMP_DE_MINES
	if p_ligne < CliffTypes.P_CORNICHE_LO or (delta_max >= CliffTypes.DELTA_CORNICHE and p_ligne < CliffTypes.P_CHEMIN_LO):
		return CliffTypes.Piste.FIL_DU_RASOIR
	if p_ligne < CliffTypes.P_CHEMIN_LO or delta_max >= CliffTypes.DELTA_CORNICHE or bait_max >= CliffTypes.BAIT_THRESHOLD:
		return CliffTypes.Piste.CORNICHE
	if p_ligne < CliffTypes.P_AUTOROUTE:
		return CliffTypes.Piste.CHEMIN
	return CliffTypes.Piste.AUTOROUTE

## 13. Classification biunivoque basée sur l'indice D calibré (pour synchronisation de jauge UI).
static func classify_piste_by_d(d_score: int) -> CliffTypes.Piste:
	return CliffTypes.get_piste_from_d(d_score)
