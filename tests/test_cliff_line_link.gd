extends SceneTree
## tests/test_cliff_line_link.gd — Lien avec les lignes Stockfish : aperçu non
## destructif, calque Rayons X, méta de ligne et badge de piste.

const ChessGame = preload("res://src/core/ChessGame.gd")
const CliffTypes = preload("res://src/engine/CliffTypes.gd")

var _failures := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

func _init() -> void:
	print("--- Cliff <-> Stockfish lines link test ---")
	await process_frame
	var main = load("res://src/ui/Main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.25).timeout

	var gc = root.get_node_or_null("GameController")
	_check(gc != null and main.cliff_dock != null, "Main + CliffLiveDock prêts")
	if gc == null:
		quit(1)
		return

	gc.reset_to_initial()
	gc.load_pgn("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6")
	var before: int = gc.game.move_history.size()
	_check(before == 6, "6 demi-coups chargés")

	var em = root.get_node_or_null("EngineManager")
	if em != null:
		em.stop_evaluation()
	await create_timer(0.1).timeout

	var sm = root.get_node_or_null("SettingsManager")
	if sm != null:
		sm.set_setting("cliff_xray_enabled", true)

	# Pas de Super Live : aperçu + Rayons X, sans altérer la partie.
	var fen_after := "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
	var step := {
		"step": 0, "move_uci": "e2e4", "san": "e4", "fen_after": fen_after,
		"is_white": true, "piste": CliffTypes.Piste.CORNICHE,
		"indice_d": 42, "delta_chute": 0.12, "bait": 0.3, "p_survie": 0.4,
		"best_move": "g1f3", "bait_move_uci": "d2d4", "mines": [{"sq": 27, "weight": 0.6}]
	}
	main.is_cliff_live_active = true
	main._on_cliff_super_live_step(0, "e2e4", fen_after, step)
	await process_frame
	_check(main.chess_board.is_previewing(), "aperçu actif pendant le Super Live")
	_check(main.chess_board.is_cliff_overlay_active(), "calque Rayons X actif")
	_check(gc.game.move_history.size() == before, "historique préservé (%d)" % gc.game.move_history.size())

	main.is_cliff_live_active = false
	main.chess_board.clear_preview_fen()
	main.chess_board.clear_cliff_overlay()
	await process_frame
	_check(not main.chess_board.is_previewing() and not main.chess_board.is_cliff_overlay_active(),
			"aperçu/calque nettoyés")

	# Lignes Stockfish : méta de provenance + badge de piste par ligne.
	var panel = main.engine_lines_panel
	panel.set_lines([{
		"rank": 1, "depth": 16, "score_cp": -50, "mate_in": 0,
		"best_move": "e2e4", "fen": fen_after, "pv": ["e2e4", "e7e5"]
	}], "SF", 16)
	await process_frame
	var meta: Dictionary = panel.get_context_meta(2)
	_check(int(meta.get("rank", 0)) == 2, "méta de ligne : rang transmis")
	_check(str(meta.get("engine", "")) == "SF", "méta de ligne : moteur transmis")
	panel.set_line_pistes({1: {"piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 55,
			"delta": 0.2, "bait": 0.3, "p_survie": 0.1}})
	await process_frame
	_check(panel._row_badges[0].visible, "badge de piste affiché sur la ligne #1")

	# --- Persistance + sémantique du badge par coup ---
	var report := {
		"semantics": CliffTypes.SEMANTICS,
		"source_meta": {"fen": fen_after, "depth": 16, "rank": 1, "engine": "SF"},
		"summary_white": {"global_piste": CliffTypes.Piste.CHEMIN, "indice_d": 20,
				"p_survie_ligne": 0.5, "max_delta_chute": 0.05, "max_bait": 0.1},
		"summary_black": {"global_piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 50,
				"p_survie_ligne": 0.2, "max_delta_chute": 0.3, "max_bait": 0.4},
		"plies": [
			{"ply": 0, "move_uci": "e7e5", "san": "e5", "fen_after": fen_after, "is_white": false,
					"piste": CliffTypes.Piste.CHAMP_DE_MINES, "indice_d": 50, "delta_chute": 0.3,
					"bait": 0.4, "p_survie": 0.2},
			{"ply": 1, "move_uci": "g1f3", "san": "Nf3", "fen_after": fen_after, "is_white": true,
					"piste": CliffTypes.Piste.CHEMIN, "indice_d": 20, "delta_chute": 0.05,
					"bait": 0.1, "p_survie": 0.5}
		]
	}
	main._apply_cliff_data_to_moves(report)
	# Sémantique canonique V2.3 : chaque coup t reflète directement l'effort consenti pour le jouer (plies[t]).
	_check(gc.game.move_history[0].cliff_piste == CliffTypes.Piste.CHAMP_DE_MINES,
			"badge du 1er coup = difficulté de la position initiale")
	_check(gc.game.move_history[1].cliff_piste == CliffTypes.Piste.CHEMIN,
			"badge du 2e coup = difficulté de la position après le 1er coup")

	main._archive_cliff_report(report)
	var dm = root.get_node_or_null("DatabaseManager")
	if dm != null and gc.current_game_id != "":
		_check(dm.get_game(gc.current_game_id).has("cliff_data"), "rapport Cliff persisté au niveau partie")
	else:
		_check(false, "DatabaseManager / id de partie indisponible")

	# --- Rejeu non destructif ---
	main._cliff_last_report = report
	main._cliff_replay_interval = 0.5
	main._on_cliff_replay_toggled(true)
	await create_timer(0.1).timeout
	_check(main.chess_board.is_previewing(), "rejeu : aperçu appliqué à l'échiquier")
	main._on_cliff_replay_toggled(false)
	await create_timer(0.6).timeout
	_check(gc.game.move_history.size() == before,
			"rejeu non destructif (historique %d/%d)" % [gc.game.move_history.size(), before])
	main.chess_board.clear_preview_fen()

	if sm != null:
		sm.set_setting("cliff_xray_enabled", false)
	main.queue_free()
	if _failures == 0:
		print("ALL CLIFF LINE LINK TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CLIFF LINE LINK TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
