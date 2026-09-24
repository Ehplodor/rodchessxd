class_name CliffTypes
extends RefCounted
## CliffTypes.gd — Enums, constantes, seuils et métadonnées d'affichage pour CHESS-CLIFF.
## Source unique de vérité pour la classification de complexité cognitive.

## ── Classification CLIFF par « piste » ─────────────────────────────────
## La piste est dérivée de l'indice D (voir get_piste_from_d et les seuils D_*_MAX).
enum Piste {
	AUTOROUTE = 0,      # 🟢 D < 25 — positions confortables
	CHEMIN = 1,         # 🔵 D ∈ [25, 50) — calcul modéré
	CORNICHE = 2,       # 🟠 D ∈ [50, 72) — corniche technique piégeuse
	FIL_DU_RASOIR = 3,  # 🔴 D ∈ [72, 88) — coup unique ou presque
	CHAMP_DE_MINES = 4  # ☠️ D ≥ 88 — survie quasi-impossible pour l'humain
}

## ── Saillance visuelle ────────────────────────────────────────────────
const W_CHECK := 0.15      # Un échec monopolise l'attention
const W_CAPTURE := 0.20    # Gain matériel évident
const W_FORWARD := 0.05    # Biais vers l'offensive
const W_BACKWARD := 0.10   # Recul = angle mort cognitif

## ── Boltzmann ─────────────────────────────────────────────────────────
const BETA := 12.0          # Température cognitive inverse par défaut (joueur ≈ 1600 Élo)
## β dépend du niveau : un joueur fort discrimine mieux les coups (β plus grand).
## β(Élo) = BETA + (Élo - BETA_ELO_REF) · BETA_PER_ELO, borné à [BETA_MIN, BETA_MAX].
const BETA_ELO_REF := 1600
const BETA_PER_ELO := 0.01
const BETA_MIN := 4.0
const BETA_MAX := 24.0

## ── Seuils de classification par piste ─────────────────────────────────
const P_AUTOROUTE := 0.65     # P_survie_ligne ≥ 0.65
const P_CHEMIN_LO := 0.40     # P_survie_ligne ∈ [0.40, 0.65)
const P_CORNICHE_LO := 0.15   # P_survie_ligne ∈ [0.15, 0.40)
const P_FIL_LO := 0.03        # P_survie_ligne ∈ [0.03, 0.15)
                               # P_survie_ligne < 0.03 → CHAMP_DE_MINES

const DELTA_CORNICHE := 0.30  # Δ_chute ≥ 0.30 → ravin (règle de l'Abysse)
const BAIT_THRESHOLD := 0.25  # Bait ≥ 0.25 → piège naturel
const WDL_MOK_TOLERANCE := 0.05 # Écart WDL max pour qu'un coup soit « viable » (H_mob)
## Perte WDL à partir de laquelle un coup « chute » (seuil d'erreur, 10 points de gain) :
## la survie mesure le risque d'erreur, pas celui d'une simple imprécision (5 points).
const WDL_FALL_TOLERANCE := 0.10
const DELTA_VITAL := 0.20       # Δ mesuré ≥ 0.20 avec un seul coup viable → coup unique vital

## ── Bornes WDL : les mats restent toujours au-delà de toute évaluation en cp ──
const WDL_CP_CEIL := 0.98       # Plafond d'une évaluation en centipions
const WDL_MATE_FLOOR := 0.985   # Mat gagnant le plus lointain (mat en MATE_HORIZON)
const MATE_HORIZON := 50        # Au-delà, tous les mats se valent

## ── Recherches moteur (3 requêtes par demi-coup) ────────────────────────
## Intuition : une recherche MultiPV couvrant TOUS les coups légaux à faible profondeur.
const INTUITION_TIMEOUT_MS := 600
## Vérification : les coups hors MultiPV sont sondés en UNE recherche « searchmoves »,
## par P_humain décroissante, jusqu'à couvrir PROBE_MASS de la masse humaine
## (au plus PROBE_MAX coups). Profondeur : max(PROBE_DEPTH, profondeur oracle / 2).
const PROBE_DEPTH := 8
const PROBE_MASS := 0.90
const PROBE_MAX := 8
const PROBE_TIMEOUT_MS := 1200

## ── Indice composite D ────────────────────────────────────────────────
const D_WEIGHT_CHUTE := 35.0
const D_WEIGHT_SURVIE := 40.0
const D_WEIGHT_BAIT := 25.0
## Multiplicateur de mobilité : 1 + D_MOB_GAIN · clamp(D_MOB_REF_BITS - H_mob, 0, D_MOB_REF_BITS)
## (de 1.0 pour ≥ 1.5 bit de choix viables à 1.45 pour un coup unique).
const D_MOB_GAIN := 0.30
const D_MOB_REF_BITS := 1.5
## Normalisation : un demi-coup « moyen difficile » (Δ≈0.5, P≈0.5, pas d'appât, H=0) ≈ D 50.
const D_NORMALIZER := 1.15
## Tension latente : D_latent = W_THREAT · menace + (1 - W_THREAT) · D_adverse_précédent
const D_LATENT_W_THREAT := 0.65
const D_LATENT_PRIOR := 15.0    # D adverse supposé avant le premier coup observé

## ── Couleurs et libellés UI ───────────────────────────────────────────
## Rampe de sévérité monotone (vert → bleu → ambre → rouge → magenta), lisible sur
## fond sombre comme clair. L'UI préfère DesignTokens.piste_color (variante par thème).
const PISTE_COLORS := {
	Piste.AUTOROUTE:       Color("#22c55e"),
	Piste.CHEMIN:          Color("#38bdf8"),
	Piste.CORNICHE:        Color("#f59e0b"),
	Piste.FIL_DU_RASOIR:   Color("#ef4444"),
	Piste.CHAMP_DE_MINES:  Color("#d946ef"),
}

const PISTE_ICONS := {
	Piste.AUTOROUTE:       "🟢",
	Piste.CHEMIN:          "🔵",
	Piste.CORNICHE:        "🟠",
	Piste.FIL_DU_RASOIR:   "🔴",
	Piste.CHAMP_DE_MINES:  "☠️",
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

## ── Zones de jauge historiques (segments par P_survie croissante) ─────
const GAUGE_ZONES := [P_FIL_LO, P_CORNICHE_LO, P_CHEMIN_LO]  # [0.03, 0.15, 0.40]

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

## ── Moments clés (Super-Analyse V3) ──────────────────────────────────
## Cliff n'est lancé que sur les demi-coups candidats, puis juge chaque moment.
enum MomentKind {
	ONLY_FOUND,   # 🧗 Seul coup tenable, trouvé, et difficile à voir
	ONLY_MISSED,  # 🧗 Seul coup tenable, manqué
	BAIT_TAKEN,   # 🍬 Le coup le plus tentant était le piège, et il a été joué
	CARELESS,     # 😴 Erreur dans une position facile (inattention)
	HARD_ERROR,   # ⚠️ Erreur dans une position exigeante
}

const MOMENT_ICONS := {
	MomentKind.ONLY_FOUND:  "🧗",
	MomentKind.ONLY_MISSED: "🧗",
	MomentKind.BAIT_TAKEN:  "🍬",
	MomentKind.CARELESS:    "😴",
	MomentKind.HARD_ERROR:  "⚠️",
}

const MOMENT_TITLES := {
	MomentKind.ONLY_FOUND:  "Coup unique trouvé",
	MomentKind.ONLY_MISSED: "Coup unique manqué",
	MomentKind.BAIT_TAKEN:  "Appât mordu",
	MomentKind.CARELESS:    "Inattention",
	MomentKind.HARD_ERROR:  "Position exigeante",
}

## Réussite (vert) ou échec (rouge) du camp qui jouait le moment.
static func moment_is_success(kind: int) -> bool:
	return kind == MomentKind.ONLY_FOUND

## Criblage : MultiPV 2 peu profonde sur chaque demi-coup hors théorie.
const SCREEN_DEPTH := 10
const SCREEN_TIMEOUT_MS := 800
## Candidat si perte ≥ MOMENT_LOSS_MIN points de gain, ou chemin étroit (écart 1re/2e ≥ DELTA_VITAL).
const MOMENT_LOSS_MIN := 5.0
const MOMENT_MAX_CANDIDATES := 12
## Erreur (≥ 10 points de gain perdus) : facile si survie ≥ MOMENT_EASY_SURVIVAL.
const MOMENT_ERROR_LOSS := 10.0
const MOMENT_EASY_SURVIVAL := 0.80
## Coup unique trouvé : n'est un « test réussi » que si la survie était < ce seuil.
const MOMENT_OBVIOUS_SURVIVAL := 0.70
## Coup unique manqué : « trouvable » si la survie était ≥ ce seuil.
const MOMENT_FINDABLE_SURVIVAL := 0.50
const MOMENT_BAIT_MIN := 0.10

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
