class_name EngineAnalysisEntry
extends RefCounted
## EngineAnalysisEntry.gd — schéma unique de l'analyse moteur persistée dans
## DatabaseManager (`game.engine_analyses[]`).
##
## Source de vérité partagée par l'analyse classique (GameAnalyzer) et l'analyse
## unifiée CHESS-CLIFF, afin d'éviter toute dérive de champs entre les deux chemins
## d'archivage (ex. oubli d'un champ, valeurs par défaut divergentes).

## Profondeur d'analyse par défaut selon la plateforme (mobile plus léger).
static func default_depth() -> int:
	return 14 if (OS.has_feature("android") or OS.has_feature("ios")) else 18

## Construit l'entrée d'analyse archivée. `evaluations` est passée séparément car les
## deux appelants l'extraient du rapport. `cliff_data` n'est ajouté qu'en mode unifié.
static func build(report: Dictionary, evaluations: Array, depth: int, mode: String,
		engine_name: String = "Stockfish", cliff_data: Dictionary = {}) -> Dictionary:
	var entry := {
		"engine_name": engine_name,
		"depth": depth,
		"mode": mode,
		"white_accuracy": report.get("white_accuracy", 0.0),
		"black_accuracy": report.get("black_accuracy", 0.0),
		"white_estimated_elo": report.get("white_estimated_elo", 1500),
		"black_estimated_elo": report.get("black_estimated_elo", 1500),
		"white_elo_ci": report.get("white_elo_ci", 0),
		"black_elo_ci": report.get("black_elo_ci", 0),
		"white_ipr_elo": report.get("white_ipr_elo", report.get("white_estimated_elo", 1500)),
		"black_ipr_elo": report.get("black_ipr_elo", report.get("black_estimated_elo", 1500)),
		"white_complexity_avg": report.get("white_complexity_avg", 1.0),
		"black_complexity_avg": report.get("black_complexity_avg", 1.0),
		"has_clock_data": report.get("has_clock_data", false),
		"elo_comparison": report.get("elo_comparison", {}),
		"white_acpl": report.get("white_acpl", 0.0),
		"black_acpl": report.get("black_acpl", 0.0),
		"white_stats": report.get("white_stats", {}),
		"black_stats": report.get("black_stats", {}),
		"schema_version": report.get("schema_version", 1),
		"opening": report.get("opening", {}),
		"theory_plies": report.get("theory_plies", 0),
		"white_phase_stats": report.get("white_phase_stats", {}),
		"black_phase_stats": report.get("black_phase_stats", {}),
		"biggest_swings": report.get("biggest_swings", []),
		"evaluations": evaluations,
	}
	if not cliff_data.is_empty():
		entry["cliff_data"] = cliff_data
	return entry
