extends SceneTree
## tests/test_chesscom_bulk_import.gd — Phase F : import bulk Chess.com (tests automatisés headless).

const ChessComService = preload("res://src/network/ChessComService.gd")
const CarnetPresenter = preload("res://src/ui/carnet/CarnetPresenter.gd")
const ChessComBulkImportModal = preload("res://src/ui/carnet/components/ChessComBulkImportModal.gd")

var _failures := 0
var _db: Node = null
var _ran := false

func _init() -> void:
	print("--- Running ChessCom Bulk Import tests ---")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_db = root.get_node_or_null("DatabaseManager")
	if _db == null:
		printerr("DatabaseManager autoload introuvable")
		quit(1)
		return true

	_test_parse_month_games()
	_test_cleanup_chesscom_service()
	_test_cancel_bulk_import()
	_test_modal_ui()

	if _failures == 0:
		print("ALL CHESSCOM BULK IMPORT TESTS PASSED SUCCESSFULLY!")
	else:
		printerr("CHESSCOM BULK IMPORT TESTS FAILED: %d" % _failures)
	quit(0 if _failures == 0 else 1)
	return true

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)

# ── Tests _parse_month_games ─────────────────────────────────────────────────────

func _test_parse_month_games() -> void:
	var service = ChessComService.new()
	root.add_child(service)
	service.current_username = "testplayer"

	var sample_json := {
		"games": [
			{
				"url": "https://www.chess.com/game/1",
				"pgn": "[Event \"Test\"]\n[White \"TestPlayer\"]\n[Black \"Opponent\"]\n[Date \"2026.08.23\"]\n[Result \"1-0\"]\n\n1. e4 e5 1-0",
				"white": {"username": "TestPlayer", "rating": 1500, "result": "win"},
				"black": {"username": "Opponent", "rating": 1600, "result": "loss"},
				"time_class": "rapid",
				"time_control": "600+5",
				"end_time": 1724457600,
				"rules": "chess"
			},
			{
				"url": "https://www.chess.com/game/2",
				"pgn": "[Event \"Test\"]\n[White \"Opponent\"]\n[Black \"TestPlayer\"]\n[Date \"2026.08.23\"]\n[Result \"0-1\"]\n\n1. d4 d5 0-1",
				"white": {"username": "Opponent", "rating": 1600, "result": "loss"},
				"black": {"username": "TestPlayer", "rating": 1500, "result": "win"},
				"time_class": "blitz",
				"time_control": "180+2",
				"end_time": 1724457700,
				"rules": "chess"
			},
			{
				"url": "https://www.chess.com/game/3",
				"pgn": "",
				"white": {"username": "TestPlayer", "rating": 1500, "result": "draw"},
				"black": {"username": "Opponent", "rating": 1600, "result": "draw"},
				"time_class": "bullet",
				"time_control": "60+1",
				"end_time": 1724457800,
				"rules": "chess"
			}
		]
	}

	var games = service._parse_month_games(sample_json, 50)
	_check(games.size() == 2, "jeux sans PGN ignorés (2/3 conservés)")

	var g0 = games[0]
	_check(str(g0.get("white_user", "")) == "Opponent", "white_user correct (ordre inverse)")
	_check(str(g0.get("black_user", "")) == "TestPlayer", "black_user correct (ordre inverse)")
	_check(int(g0.get("white_rating", 0)) == 1600, "white_rating correct (ordre inverse)")
	_check(int(g0.get("black_rating", 0)) == 1500, "black_rating correct (ordre inverse)")
	_check(str(g0.get("time_class", "")) == "blitz", "time_class correct (ordre inverse)")
	_check(str(g0.get("user_result", "")) == "win", "user_result = win (noirs)")
	_check(str(g0.get("score", "")) == "0-1", "score correct (ordre inverse)")

	var g1 = games[1]
	_check(str(g1.get("white_user", "")) == "TestPlayer", "white_user correct")
	_check(str(g1.get("black_user", "")) == "Opponent", "black_user correct")
	_check(int(g1.get("white_rating", 0)) == 1500, "white_rating correct")
	_check(int(g1.get("black_rating", 0)) == 1600, "black_rating correct")
	_check(str(g1.get("time_class", "")) == "rapid", "time_class correct")
	_check(str(g1.get("user_result", "")) == "win", "user_result = win (blancs)")
	_check(str(g1.get("score", "")) == "1-0", "score correct")

	service.queue_free()

# ── Tests _cleanup_chesscom_service ─────────────────────────────────────────────

func _test_cleanup_chesscom_service() -> void:
	var presenter: CarnetPresenter = CarnetPresenter.new()

	# Test cleanup with null service
	presenter._cleanup_chesscom_service()
	_check(presenter._chesscom_service == null, "cleanup avec null ne crash pas")

	# Test cleanup with valid service
	var service = ChessComService.new()
	root.add_child(service)
	presenter._chesscom_service = service
	presenter._cleanup_chesscom_service()
	_check(presenter._chesscom_service == null, "service libéré après cleanup")

	# Test cleanup with invalid (freed) service
	var invalid_service = ChessComService.new()
	root.add_child(invalid_service)
	invalid_service.queue_free()
	await create_timer(0.1).timeout
	presenter._chesscom_service = invalid_service
	presenter._cleanup_chesscom_service()
	_check(presenter._chesscom_service == null, "cleanup avec service invalide ne crash pas")

# ── Tests cancel_bulk_import ─────────────────────────────────────────────────────

func _test_cancel_bulk_import() -> void:
	var presenter: CarnetPresenter = CarnetPresenter.new()

	# Without active service: should not crash
	presenter.cancel_bulk_import()
	_check(presenter._chesscom_service == null, "cancel sans service ne crash pas")

	# With active service
	var service = ChessComService.new()
	root.add_child(service)
	presenter._chesscom_service = service
	presenter.cancel_bulk_import()
	_check(presenter._chesscom_service == null, "service annulé et nettoyé")

# ── Tests modal UI ──────────────────────────────────────────────────────────────

func _test_modal_ui() -> void:
	var presenter: CarnetPresenter = CarnetPresenter.new()
	var modal = ChessComBulkImportModal.new()
	root.add_child(modal)
	modal.open(presenter)

	_check(modal.exclusive == true, "modale exclusive")
	_check(modal._username_edit != null, "champ pseudo présent")
	_check(modal._months_spin != null, "spin mois présent")
	_check(modal._max_games_spin != null, "spin max parties présent")
	_check(modal._profile_name_edit != null, "champ nom carnet présent")
	_check(modal._progress_bar != null, "barre progression présente")
	_check(modal._months_spin.value == 12, "mois par défaut = 12")
	_check(modal._max_games_spin.value == 500, "max parties par défaut = 500")

	modal._username_edit.text = "hikaru"
	modal._on_username_changed("hikaru")
	_check(modal._profile_name_edit.text == "Chess.com • hikaru", "nom carnet auto depuis pseudo")

	modal.queue_free()
