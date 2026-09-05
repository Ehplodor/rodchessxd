extends SceneTree
## test_chess_com.gd - Test unitaire du service Chess.com et du chargement PGN

const ChessComService = preload("res://src/network/ChessComService.gd")
const ChessGame = preload("res://src/core/ChessGame.gd")

func _init() -> void:
	print("--- Running ChessComService integration test ---")
	
	var service = ChessComService.new()
	root.add_child(service)
	
	await create_timer(0.2).timeout
	
	var result_holder = {"received": false, "games": []}
	
	service.games_fetched.connect(func(games):
		print("Successfully fetched %d games from Chess.com!" % games.size())
		result_holder["received"] = true
		result_holder["games"] = games
	)
	
	service.fetch_error.connect(func(err):
		print("Fetch error: ", err)
	)
	
	print("Fetching recent games for user 'erik'...")
	service.fetch_player_games("erik", 5)
	
	var timeout = 0
	while not result_holder["received"] and timeout < 80:
		await create_timer(0.1).timeout
		timeout += 1

	assert(result_holder["received"] == true)
	var games_list: Array = result_holder["games"]
	assert(games_list.size() > 0)
	
	var sample_game = games_list[0]
	print("\nSample game details:")
	print(" - White: %s (%d)" % [sample_game["white_user"], sample_game["white_rating"]])
	print(" - Black: %s (%d)" % [sample_game["black_user"], sample_game["black_rating"]])
	print(" - Cadence: %s (%s)" % [sample_game["time_class"], sample_game["time_control"]])
	print(" - Result: %s" % sample_game["user_result"])
	
	# Test loading the fetched PGN into the game engine
	var game = ChessGame.new()
	var loaded = game.load_pgn(sample_game["pgn"])
	print("Game loaded into ChessGame engine? ", loaded)
	print("Total moves parsed: ", game.move_history.size())
	assert(loaded == true)
	assert(game.move_history.size() > 0)
	
	print("\nCHESS.COM INTEGRATION TEST PASSED 100% SUCCESSFULLY!")
	quit(0)
