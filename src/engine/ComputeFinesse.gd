class_name ComputeFinesse
extends RefCounted
## ComputeFinesse.gd — Profils de finesse de calcul (CHESS-CLIFF V2.2).
##
## Chaque moteur de calcul indépendant (analyse de partie, Live, Oracle Cliff,
## Intuition Cliff, enveloppe de ligne) expose des réglages cohérents et
## monotones, pilotés par un palier global unique (slider 5 crans).
##
## Palier 0 = Éco (mobile modeste) … Palier 4 = Maximum (PC puissant).
## Les défauts plateforme sont appliqués par défaut_tier().

enum Tier { ECO = 0, RAPIDE = 1, EQUILIBRE = 2, APPROFONDI = 3, MAXIMUM = 4 }

const TIER_LABELS := ["Éco", "Rapide", "Équilibré", "Approfondi", "Maximum"]
const TIER_HINTS := [
	"Instantané, batterie préservée",
	"Quelques secondes",
	"Bon compromis (défaut mobile)",
	"Analyse sérieuse (défaut PC)",
	"Le plus profond possible",
]

## Table maîtresse (desktop). Les colonnes sont strictement croissantes.
const PROFILES := [
	# 0 Éco
	{
		"analysis_mode": "budget", "analysis_depth": 10,
		"budget_base_depth": 6, "budget_deep_depth": 10, "budget_max_deep": 3,
		"live_depth": 8, "live_multipv": 2,
		"oracle_depth": 10, "oracle_timeout": 1500, "oracle_multipv": 2,
		"shallow_depth": 1, "shallow_top_k": 4, "shallow_ucinewgame": false,
		"pv_max_plies": 4, "pv_fast_mode": true,
		"game_theory_plies": 12,
	},
	# 1 Rapide
	{
		"analysis_mode": "budget", "analysis_depth": 12,
		"budget_base_depth": 8, "budget_deep_depth": 12, "budget_max_deep": 4,
		"live_depth": 10, "live_multipv": 2,
		"oracle_depth": 12, "oracle_timeout": 2000, "oracle_multipv": 2,
		"shallow_depth": 1, "shallow_top_k": 6, "shallow_ucinewgame": false,
		"pv_max_plies": 6, "pv_fast_mode": true,
		"game_theory_plies": 10,
	},
	# 2 Équilibré (défaut mobile)
	{
		"analysis_mode": "budget", "analysis_depth": 14,
		"budget_base_depth": 10, "budget_deep_depth": 14, "budget_max_deep": 6,
		"live_depth": 12, "live_multipv": 3,
		"oracle_depth": 14, "oracle_timeout": 3000, "oracle_multipv": 3,
		"shallow_depth": 2, "shallow_top_k": 8, "shallow_ucinewgame": true,
		"pv_max_plies": 8, "pv_fast_mode": true,
		"game_theory_plies": 8,
	},
	# 3 Approfondi (défaut PC)
	{
		"analysis_mode": "budget", "analysis_depth": 18,
		"budget_base_depth": 12, "budget_deep_depth": 18, "budget_max_deep": 8,
		"live_depth": 14, "live_multipv": 3,
		"oracle_depth": 18, "oracle_timeout": 4000, "oracle_multipv": 3,
		"shallow_depth": 2, "shallow_top_k": 0, "shallow_ucinewgame": true,
		"pv_max_plies": 10, "pv_fast_mode": false,
		"game_theory_plies": 6,
	},
	# 4 Maximum
	{
		"analysis_mode": "depth", "analysis_depth": 22,
		"budget_base_depth": 14, "budget_deep_depth": 22, "budget_max_deep": 12,
		"live_depth": 16, "live_multipv": 4,
		"oracle_depth": 22, "oracle_timeout": 6000, "oracle_multipv": 4,
		"shallow_depth": 3, "shallow_top_k": 0, "shallow_ucinewgame": true,
		"pv_max_plies": 12, "pv_fast_mode": false,
		"game_theory_plies": 4,
	},
]

static func clamp_tier(t: int) -> int:
	return clampi(t, 0, PROFILES.size() - 1)

## Palier par défaut selon la plateforme.
static func default_tier() -> int:
	if OS.has_feature("android") or OS.has_feature("ios"):
		return Tier.EQUILIBRE
	if OS.has_feature("web"):
		return Tier.RAPIDE
	return Tier.APPROFONDI

## Palier effectif (plafonné sur Web / petits appareils).
static func effective_tier(t: int) -> int:
	var tier := clamp_tier(t)
	if OS.has_feature("web"):
		tier = mini(tier, Tier.EQUILIBRE)
	return tier

static func profile(t: int) -> Dictionary:
	return PROFILES[effective_tier(t)]

static func tier_label(t: int) -> String:
	return TIER_LABELS[clamp_tier(t)]

static func tier_hint(t: int) -> String:
	return TIER_HINTS[clamp_tier(t)]

# --- Options par moteur -------------------------------------------------

## E1 — Analyse globale de partie (GameAnalyzer).
static func game_analysis_opts(t: int) -> Dictionary:
	var p := profile(t)
	return {
		"mode": p["analysis_mode"],
		"depth": p["analysis_depth"],
		"base_depth": p["budget_base_depth"],
		"deep_depth": p["budget_deep_depth"],
		"max_deep": p["budget_max_deep"],
		"theory_plies": p["game_theory_plies"],
	}

## E2 — Évaluation Live continue.
static func live_opts(t: int) -> Dictionary:
	var p := profile(t)
	return {"depth": p["live_depth"], "multipv": p["live_multipv"]}

## E3 — Oracle Cliff (vérité profonde).
static func cliff_oracle_opts(t: int) -> Dictionary:
	var p := profile(t)
	return {"deep_depth": p["oracle_depth"], "timeout_ms": p["oracle_timeout"],
			"multipv": p["oracle_multipv"]}

## E4 — Intuition Cliff (regard depth 1 par coup légal).
static func cliff_intuition_opts(t: int) -> Dictionary:
	var p := profile(t)
	return {
		"shallow_depth": p["shallow_depth"],
		"top_k": p["shallow_top_k"],
		"ucinewgame": p["shallow_ucinewgame"],
	}

## E5 — Enveloppe de ligne Cliff (longueur + mode).
static func cliff_envelope_opts(t: int) -> Dictionary:
	var p := profile(t)
	return {"max_plies": p["pv_max_plies"], "fast_mode": p["pv_fast_mode"]}

## Applique le palier à SettingsManager (les clés deviennent les overrides experts).
static func apply_to_settings(sm: Node, t: int) -> void:
	if sm == null or not sm.has_method("set_setting"):
		return
	var p := profile(t)
	sm.set_setting("global_finesse_tier", clamp_tier(t))
	sm.set_setting("analysis_mode", p["analysis_mode"])
	sm.set_setting("analysis_depth", p["analysis_depth"])
	sm.set_setting("analysis_budget_base_depth", p["budget_base_depth"])
	sm.set_setting("analysis_budget_deep_depth", p["budget_deep_depth"])
	sm.set_setting("analysis_budget_max_deep", p["budget_max_deep"])
	sm.set_setting("engine_depth", p["live_depth"])
	sm.set_setting("engine_multipv", p["live_multipv"])

## Estimation grossière de la durée (min, max) en secondes pour une partie.
static func estimate_seconds(t: int, plies: int, mobile: bool) -> Vector2i:
	var p := profile(t)
	var n := maxi(1, plies)
	var oracle := float(p["oracle_timeout"]) / 1000.0 + 0.25
	var shallow_calls := float(p["shallow_top_k"]) if int(p["shallow_top_k"]) > 0 else 18.0
	var shallow := shallow_calls * 0.03
	var per_ply := oracle + shallow
	var total := per_ply * float(n) * (1.35 if mobile else 1.0)
	return Vector2i(int(maxf(2.0, total * 0.6)), int(maxf(5.0, total * 1.5)))

static func format_estimate(t: int, plies: int, mobile: bool) -> String:
	var est := estimate_seconds(t, plies, mobile)
	return "≈ %s – %s" % [_fmt(est.x), _fmt(est.y)]

static func _fmt(seconds: int) -> String:
	if seconds < 60:
		return "%d s" % seconds
	return "%d min" % int(round(float(seconds) / 60.0))
