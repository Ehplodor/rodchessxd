class_name CarnetConfig
extends RefCounted
## CarnetConfig.gd — T-source unique des constantes réglables de LeCarnet (§4.14 du plan).
## Aucune de ces valeurs ne doit être dupliquée ailleurs : les trois étages (Events,
## Ledger, Trainer) lisent ici. Modifier une constante ici suffit à recalibrer le Carnet.

# ── Garde-fous globaux ─────────────────────────────────────────────────────────
## Nombre minimal de plies pour qu'une partie soit analysable (§4.2, §4.15).
const MIN_PLIES_PARTIE := 10

## Polarity values (single source shared by Events, Ledger and Trainer).
const POLARITE_NEGATIVE := "négatif"
const POLARITE_POSITIVE := "positif"
const POLARITE_CURIEUSE := "curieux"

# ── Négatif / agrégation (§4.3, §4.5, §4.7) ─────────────────────────────────────
## Seuil de perte de win% au-delà duquel un coup est un événement négatif.
## Aliasé sur le classifieur de référence pour éviter toute dérive de calibration.
const WINPCT_INACCURACY := MoveQualityService.WINPCT_INACCURACY
## Perte de win% considérée comme gravité maximale : s(f) = min(perte / S_MAX, 1).
const S_MAX := 40.0
## Demi-vie de récence en jours : un événement de 45 j compte moitié (w = 0,5^(âge/45)).
const DEMI_VIE_JOURS := 45.0
## Retenue bayésienne : K = n / (n + K_SHRINK) → 4 occurrences ⇒ 0,50.
const K_SHRINK := 4.0
## Pondération du score : alpha × gravité + bêta × fréquence.
const ALPHA := 0.6
const BETA := 0.4
## Fréquence par partie à partir de laquelle le terme de fréquence est saturé.
const P_MAX := 0.5
## Occurrences minimales (et K ≥ 0,43) pour qu'un motif soit « établi ».
const MIN_N_ETABLIE := 3
## Seuil de confiance de motif établi. La borne exacte 3/7 ≈ 0,4286 (n = 3) est
## arrondie ici à 0,42 pour honorer « n ≥ 3 » sans exclure la 3e occurrence.
const K_ETABLIE := 0.42
## Nombre de parties récentes pour le calcul de tendance (§4.7).
const RECENT_GAMES := 20
## Seuils de tendance : récent ≤ 0,6 × ancien = amélioration ; ≥ 1,5 × = aggravation.
const AMELIORATION := 0.6
const AGGRAVATION := 1.5

# ── Positif / surprise / mystère (§4.4.1, §4.4.2) ───────────────────────────────
## Écart de win% avec la 2e ligne au-delà duquel le coup est « seul coup ».
## Aliasé sur le classifieur de référence (le score de qualité vient de lui).
const ONLY_MOVE_WINPCT := MoveQualityService.WINPCT_ONLY_MOVE
## Tolérance d'évaluation (cp) pour qu'un sacrifice reste « acceptable ».
const SAC_TOL_CP := 50
## Passe peu profonde (trouvaille profonde) et profondeur de référence — fournies par
## l'appelant qui produit `shallow_top_moves`/`winpct_by_depth`.
## Fenêtre de position « équilibrée » pour la volatilité de surprise.
const VOLATILITE_EQ_MIN := 25.0
const VOLATILITE_EQ_MAX := 75.0
## Déséquilibre matériel (cp) à partir duquel on parle de compensation (2 pions).
const DEBALANCE_MAT := 200
## Distance (win%) à la meilleure ligne pour compter les coups « pluralité / tension ».
const PLURALITE_TOL_WINPCT := 5.0
## Seuils de décision surprise / mystère.
const IS_SURPRISE := 60.0
const IM_MYSTERE := 65.0
## Poids de l'indice de surprise IS = 100 × Σ poids·composante (§4.4.2).
const IS_WEIGHTS := {
	"ecart_naturalite": 0.25,
	"sacrifice": 0.20,
	"unicite": 0.20,
	"profondeur": 0.15,
	"nouveaute": 0.10,
	"volatilite": 0.10,
}
## Poids de l'indice de mystère IM = 100 × Σ poids·composante (§4.4.2).
const IM_WEIGHTS := {
	"instabilite": 0.35,
	"pluralite": 0.25,
	"compensation": 0.20,
	"tension": 0.20,
}
## Diviseurs de normalisation des composantes IS/IM.
const NATURALITE_DIV := 20.0
const VOLATILITE_DIV := 30.0
const INSTABILITE_DIV := 25.0
const PLURALITE_DIV := 5.0
const COMPENSATION_DIV := 4.0
## Poids du mérite d'une force : m(e) = 0,5·niveau + 0,3·IS/100 + 0,2·criticité (§4.4.1).
const MERIT_BRILLIANCE := 0.5
const MERIT_SURPRISE := 0.3
const MERIT_CRITICITE := 0.2

# ── Drills / plan (§4.8 → §4.10) ────────────────────────────────────────────────
const DRILLS_PER_MOTIF := 4
## Tolérance de win% pour accepter une réponse utilisateur qui n'est pas le meilleur coup.
const WINPCT_TOL := 3.0
const SESSION_SIZE := 5
const MAX_PER_MOTIF := 2
## Part de la séance provenant des drills positifs / de curiosité.
const POSITIVE_DRILL_RATIO := 0.20
const EF_INIT := 2.5
const EF_MIN := 1.3
const EF_MAX := 2.8

# ── Apprentissage / compétence (§4.11) ──────────────────────────────────────────
const K_SKILL := 12.0
## Fenêtre de difficulté désirable (taux de réussite visé).
const DIFFICULTE_CIBLE_MIN := 0.70
const DIFFICULTE_CIBLE_MAX := 0.85
## Nombre de séances de stagnation avant de changer de format (plateau).
const PLATEAU_SEANCES := 6
## Écart théorie ↔ pratique à partir duquel le signal pédagogique est affirmé.
const ECART_THEORIE_PRATIQUE := 8.0
const MASTERY_WINDOW := 10
const MASTERY_DRILLS := 3
const JOKER_PAR_SEMAINE := 1

# ── Divers ──────────────────────────────────────────────────────────────────────
## Sentinelle « pas de 2e ligne connue » (cohérente avec MoveQualityService).
const NO_SECOND_LINE := -999999

## Version de l'algorithme d'atomisation (Étage 1). À incrémenter pour forcer la
## reconstruction des atomes d'un carnet après un changement de détection/scoring.
const ATOM_VERSION := 1
## Version du schéma des fichiers de profil (sync/atoms/trainer).
const CARNET_SCHEMA_VERSION := 1

# ── Vitesse d'analyse moteur du Carnet ──────────────────────────────────────────
const ANALYSIS_SPEED_FAST := "fast"
const ANALYSIS_SPEED_BALANCED := "balanced"
const ANALYSIS_SPEED_DEEP := "deep"

const ANALYSIS_SPEED_PRESETS := {
	ANALYSIS_SPEED_FAST: {
		"label": "⚡ Rapide",
		"desc": "Idéal pour les grands carnets (~1 à 3 s / partie)",
		"depth": 8,
		"dynamic_base": 0.05,
		"dynamic_max": 0.20,
		"time_per_move": 0.08,
	},
	ANALYSIS_SPEED_BALANCED: {
		"label": "⚖️ Standard",
		"desc": "Équilibré (~5 à 8 s / partie)",
		"depth": 12,
		"dynamic_base": 0.10,
		"dynamic_max": 0.40,
		"time_per_move": 0.15,
	},
	ANALYSIS_SPEED_DEEP: {
		"label": "🎯 Approfondie",
		"desc": "Précision maximale (~15 à 25 s / partie)",
		"depth": 16,
		"dynamic_base": 0.20,
		"dynamic_max": 0.80,
		"time_per_move": 0.30,
	},
}

static func get_analysis_speed_config(preset: String = "") -> Dictionary:
	var key := preset
	if key == "" or not ANALYSIS_SPEED_PRESETS.has(key):
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root and tree.root.has_node("SettingsManager"):
			var sm = tree.root.get_node("SettingsManager")
			key = str(sm.get_setting("carnet_analysis_speed", ANALYSIS_SPEED_FAST))
		else:
			key = ANALYSIS_SPEED_FAST
	if not ANALYSIS_SPEED_PRESETS.has(key):
		key = ANALYSIS_SPEED_FAST
	var cfg: Dictionary = ANALYSIS_SPEED_PRESETS[key].duplicate(true)
	cfg["speed"] = key
	if OS.has_feature("android") or OS.has_feature("ios"):
		cfg["depth"] = maxi(6, int(cfg.get("depth", 8)) - 2)
	return cfg
