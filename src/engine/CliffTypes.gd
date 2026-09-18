class_name CliffTypes
extends RefCounted
## CliffTypes.gd — Enums, constantes, seuils et métadonnées d'affichage pour CHESS-CLIFF.
## Source unique de vérité pour la classification de complexité cognitive.

## ── Classification CLIFF par « piste » ─────────────────────────────────
enum Piste {
	AUTOROUTE = 0,      # 🟢 P_survie ≥ 0.65, Δ faible — positions confortables
	CHEMIN = 1,         # 🔵 P_survie ∈ [0.40, 0.65) — chemin balisé avec calcul modéré
	CORNICHE = 2,       # 🔴 P_survie ∈ [0.15, 0.40) ou Bait élevé — corniche technique piégeuse
	FIL_DU_RASOIR = 3,  # ⚫ Δ_chute ≥ 0.30 & P faible — seul coup unique sauvant la partie
	CHAMP_DE_MINES = 4  # ⚠️ P_survie < 0.03 — survie quasi-impossible pour l'humain
}

## ── Saillance visuelle ────────────────────────────────────────────────
const W_CHECK := 0.15      # Un échec monopolise l'attention
const W_CAPTURE := 0.20    # Gain matériel évident
const W_FORWARD := 0.05    # Biais vers l'offensive
const W_BACKWARD := 0.10   # Recul = angle mort cognitif

## ── Boltzmann ─────────────────────────────────────────────────────────
const BETA := 12.0          # Température cognitive inverse (constante, difficulté intrinsèque)
const P_SUITE_FORCEE := 0.95  # Probabilité de survie sur une suite forcée

## ── Seuils de classification par piste ─────────────────────────────────
const P_AUTOROUTE := 0.65     # P_survie_ligne ≥ 0.65
const P_CHEMIN_LO := 0.40     # P_survie_ligne ∈ [0.40, 0.65)
const P_CORNICHE_LO := 0.15   # P_survie_ligne ∈ [0.15, 0.40)
const P_FIL_LO := 0.03        # P_survie_ligne ∈ [0.03, 0.15)
                               # P_survie_ligne < 0.03 → CHAMP_DE_MINES

const DELTA_CORNICHE := 0.30  # Δ_chute ≥ 0.30 → position sur fil du rasoir
const BAIT_THRESHOLD := 0.25  # Bait ≥ 0.25 → piège naturel
const WDL_MOK_TOLERANCE := 0.05 # Écart WDL max pour qu'un coup soit « viable » (H_mob)

## ── Indice composite D ────────────────────────────────────────────────
const D_WEIGHT_CHUTE := 35.0
const D_WEIGHT_SURVIE := 40.0
const D_WEIGHT_BAIT := 25.0
const D_H_MOB_OFFSET := 0.2

## ── Couleurs et libellés UI ───────────────────────────────────────────
const PISTE_COLORS := {
	Piste.AUTOROUTE:       Color("#2ecc71"),  # Vert
	Piste.CHEMIN:          Color("#3498db"),  # Bleu
	Piste.CORNICHE:        Color("#e74c3c"),  # Rouge
	Piste.FIL_DU_RASOIR:   Color("#2c3e50"),  # Noir
	Piste.CHAMP_DE_MINES:  Color("#f39c12"),  # Ambre
}

const PISTE_ICONS := {
	Piste.AUTOROUTE:       "🟢",
	Piste.CHEMIN:          "🔵",
	Piste.CORNICHE:        "🔴",
	Piste.FIL_DU_RASOIR:   "⚫",
	Piste.CHAMP_DE_MINES:  "⚠️",
}

const PISTE_LETTERS := {
	Piste.AUTOROUTE:       "A",
	Piste.CHEMIN:          "B",
	Piste.CORNICHE:        "C",
	Piste.FIL_DU_RASOIR:   "F",
	Piste.CHAMP_DE_MINES:  "M",
}

const PISTE_LABELS := {
	Piste.AUTOROUTE:       "Autoroute",
	Piste.CHEMIN:          "Chemin balisé",
	Piste.CORNICHE:        "Corniche technique",
	Piste.FIL_DU_RASOIR:   "Fil du rasoir",
	Piste.CHAMP_DE_MINES:  "Champ de mines",
}

## Libellés courts (jauges, badges compacts).
const PISTE_SHORT := {
	Piste.AUTOROUTE:       "Auto.",
	Piste.CHEMIN:          "Chemin",
	Piste.CORNICHE:        "Corniche",
	Piste.FIL_DU_RASOIR:   "Rasoir",
	Piste.CHAMP_DE_MINES:  "Mines",
}

## ── Sémantique canonique ───────────────────────────────────────────────
## Toutes les métriques décrivent la « charge cognitive du camp au trait »
## dans la position résultante d'un demi-coup. Voir CliffLineReport.
const SEMANTICS := "charge_of_side_to_move"

## ── Seuils D et Horizon glissant (V2.3) ─────────────────────────────────
const D_AUTOROUTE_MAX := 25
const D_CHEMIN_MAX := 50
const D_CORNICHE_MAX := 72
const D_RASOIR_MAX := 88
const HORIZON_PLIES := 4

## ── Zones de jauge calibrées sur D (segments croissants de 0 à 100) ────
const GAUGE_D_ZONES := [D_AUTOROUTE_MAX, D_CHEMIN_MAX, D_CORNICHE_MAX, D_RASOIR_MAX]

## ── Zones de jauge historiques (segments par P_survie décroissante) ───
const GAUGE_ZONES := [P_FIL_LO, P_CORNICHE_LO, P_CHEMIN_LO]  # [0.03, 0.15, 0.40, 0.65]

static func get_piste_from_d(d_score: int) -> int:
	if d_score < D_AUTOROUTE_MAX:
		return Piste.AUTOROUTE
	if d_score < D_CHEMIN_MAX:
		return Piste.CHEMIN
	if d_score < D_CORNICHE_MAX:
		return Piste.CORNICHE
	if d_score < D_RASOIR_MAX:
		return Piste.FIL_DU_RASOIR
	return Piste.CHAMP_DE_MINES

static func get_piste_name(piste: int) -> String:
	return PISTE_LABELS.get(piste, "Inconnue")

static func get_piste_color(piste: int) -> Color:
	return PISTE_COLORS.get(piste, Color.WHITE)

static func get_piste_icon(piste: int) -> String:
	return PISTE_ICONS.get(piste, "⚪")

static func get_piste_letter(piste: int) -> String:
	return PISTE_LETTERS.get(piste, "?")

static func get_piste_short(piste: int) -> String:
	return PISTE_SHORT.get(piste, "?")

## ── Nature cognitive du coup (V2.4) ──────────────────────────────────
enum MoveNature {
	SAFE,    # 🟢 Libre / Large liberté
	FORCED,  # 🛡️ Suite forcée / Reprise mécanique
	ATTACK,  # ⚡ Attaque / Pression tactique infligée
	VITAL    # 🧗 Coup unique vital / Sentier étroit (Corniche)
}

const NATURE_ICONS := {
	MoveNature.SAFE:   "🟢",
	MoveNature.FORCED: "🛡️",
	MoveNature.ATTACK: "⚡",
	MoveNature.VITAL:  "🧗",
}

const NATURE_LABELS := {
	MoveNature.SAFE:   "Libre",
	MoveNature.FORCED: "Forcé",
	MoveNature.ATTACK: "Attaque",
	MoveNature.VITAL:  "Coup unique vital",
}

static func get_nature_icon(nature: int) -> String:
	return NATURE_ICONS.get(nature, "🟢")

static func get_nature_label(nature: int) -> String:
	return NATURE_LABELS.get(nature, "Libre")

## ── Indice de Surprise & Soulagement (V3.0) ──────────────────────────
## S = D_réel(t+1) - D_latent(t)
enum SurpriseNature {
	MIRACLE,   # 🪂🪂 S ≤ -40 : Bourde adverse majeure / Salut miraculeux
	RELIEF,    # 🪂 S ∈ [-40, -20) : Soulagement / L'adversaire rate le coche
	NORMAL,    # ⚪ S ∈ [-20, 20] : Continuité normale du duel
	SURPRISE,  # ⚡ S ∈ (20, 40] : Surprise tactique / Accélération inattendue
	SHOCK      # ⚡⚡ S > 40 : Coup de tonnerre / Choc psychologique majeur
}

const SURPRISE_ICONS := {
	SurpriseNature.MIRACLE:  "🪂🪂",
	SurpriseNature.RELIEF:   "🪂",
	SurpriseNature.NORMAL:   "",
	SurpriseNature.SURPRISE: "⚡",
	SurpriseNature.SHOCK:    "⚡⚡",
}

const SURPRISE_LABELS := {
	SurpriseNature.MIRACLE:  "Miracle inespéré",
	SurpriseNature.RELIEF:   "Soulagement",
	SurpriseNature.NORMAL:   "Continuité",
	SurpriseNature.SURPRISE: "Surprise tactique",
	SurpriseNature.SHOCK:    "Coup de tonnerre",
}

static func classify_surprise(delta_s: int) -> int:
	if delta_s > 40:
		return SurpriseNature.SHOCK
	elif delta_s > 20:
		return SurpriseNature.SURPRISE
	elif delta_s < -40:
		return SurpriseNature.MIRACLE
	elif delta_s < -20:
		return SurpriseNature.RELIEF
	return SurpriseNature.NORMAL

static func get_surprise_icon(surprise: int) -> String:
	return SURPRISE_ICONS.get(surprise, "")

static func get_surprise_label(surprise: int) -> String:
	return SURPRISE_LABELS.get(surprise, "Continuité")

static func get_surprise_name(surprise: int) -> String:
	return get_surprise_label(surprise)
