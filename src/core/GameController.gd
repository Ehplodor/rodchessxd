extends Node
## GameController.gd - Singleton centralisant la partie en cours et la synchronisation UI

signal game_reset
signal position_changed
signal move_navigated(move_idx: int)
signal move_made(move: ChessMove)
signal square_selected(sq: int, legal_moves: Array[ChessMove])
signal square_deselected
signal play_sound_requested(sound_type: String)

enum PlayMode {
	ANALYSIS = 0,
	FREE_PLAY = 1,
	PLAY_VS_ENGINE = 2
}

var game: ChessGame
var current_ply_index: int = -1 # -1 = position de départ, 0 = 1er demi-coup, etc.
var selected_square: int = -1
var legal_destinations: Array[int] = []

var play_mode: PlayMode = PlayMode.ANALYSIS
var board_flipped: bool = false
var current_game_id: String = ""
var is_loading_game: bool = false

func _ready() -> void:
	game = ChessGame.new()
	game.board_changed.connect(_on_game_board_changed)
	game.move_made.connect(_on_game_move_made)
	var settings = _get_settings_manager()
	if settings:
		board_flipped = settings.get_setting("flip_board", false)

func _get_settings_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

func _get_engine_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("EngineManager"):
		return tree.root.get_node("EngineManager")
	return null

func _get_database_manager() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("DatabaseManager"):
		return tree.root.get_node("DatabaseManager")
	return null

func get_or_create_game_id() -> String:
	if current_game_id != "":
		return current_game_id
	var dm = _get_database_manager()
	if dm:
		current_game_id = dm.record_active_game(game)
	return current_game_id

func reset_to_initial() -> void:
	is_loading_game = true
	game.reset_board()
	game.load_fen(ChessGame.INITIAL_FEN)
	current_game_id = ""
	current_ply_index = -1
	selected_square = -1
	legal_destinations.clear()
	is_loading_game = false
	game_reset.emit()
	position_changed.emit()

func load_fen(fen: String) -> bool:
	is_loading_game = true
	selected_square = -1
	legal_destinations.clear()
	var success = game.load_fen(fen)
	is_loading_game = false
	if success:
		current_ply_index = -1
		var dm = _get_database_manager()
		if dm:
			current_game_id = dm.record_active_game(game, "Position FEN", "fen_import")
		game_reset.emit()
		position_changed.emit()
	return success

func load_pgn(pgn: String, known_game_id: String = "") -> bool:
	is_loading_game = true
	selected_square = -1
	legal_destinations.clear()
	var success = game.load_pgn(pgn)
	is_loading_game = false
	if success:
		current_ply_index = game.move_history.size() - 1
		if known_game_id != "":
			current_game_id = known_game_id
		else:
			var dm = _get_database_manager()
			if dm:
				current_game_id = dm.record_pgn_game(pgn, "pgn_import")
		game_reset.emit()
		position_changed.emit()
	return success

func select_square(sq: int) -> void:
	if selected_square == sq:
		deselect_square()
		return
	
	if selected_square != -1 and sq in legal_destinations:
		try_play_move(selected_square, sq)
		return

	var piece = game.get_piece(sq)
	if piece.type != ChessPiece.Type.NONE and piece.color == game.active_color:
		selected_square = sq
		var moves = game.get_legal_moves_for_square(sq)
		legal_destinations.clear()
		for m in moves:
			legal_destinations.append(m.to_sq)
		square_selected.emit(sq, moves)
	else:
		deselect_square()

func deselect_square() -> void:
	selected_square = -1
	legal_destinations.clear()
	square_deselected.emit()

func is_promotion_move(from_sq: int, to_sq: int) -> bool:
	if not game:
		return false
	var piece = game.get_piece(from_sq)
	if piece.type != ChessPiece.Type.PAWN:
		return false
	var r = to_sq / 8
	var prom_rank = 7 if piece.color == ChessPiece.PieceColor.WHITE else 0
	if r != prom_rank:
		return false
	var legal = game.get_legal_moves_for_square(from_sq)
	for m in legal:
		if m.to_sq == to_sq and m.promotion != ChessPiece.Type.NONE:
			return true
	return false

func try_play_move(from_sq: int, to_sq: int, promotion_type: int = ChessPiece.Type.NONE) -> bool:
	var target_prom = promotion_type
	var is_prom = is_promotion_move(from_sq, to_sq)
	if is_prom and target_prom == ChessPiece.Type.NONE:
		target_prom = ChessPiece.Type.QUEEN

	var legal = game.get_legal_moves_for_square(from_sq)
	for m in legal:
		if m.to_sq == to_sq:
			if is_prom:
				if m.promotion != target_prom:
					continue
			
			var move_made = game.make_move(m)
			if move_made:
				deselect_square()
				current_ply_index = game.move_history.size() - 1
				
				if m.is_check:
					play_sound_requested.emit("check")
				elif m.captured_piece != ChessPiece.Type.NONE or m.is_en_passant:
					play_sound_requested.emit("capture")
				else:
					play_sound_requested.emit("move")
				
				return true
	deselect_square()
	return false

func navigate_to_ply(ply_idx: int) -> void:
	var total_moves = game.move_history.size()
	ply_idx = clampi(ply_idx, -1, total_moves - 1)
	if ply_idx == current_ply_index:
		return
	
	deselect_square()
	current_ply_index = ply_idx
	game.restore_state(current_ply_index + 1)
	move_navigated.emit(current_ply_index)
	position_changed.emit()

func go_first_move() -> void:
	navigate_to_ply(-1)

func go_previous_move() -> void:
	navigate_to_ply(current_ply_index - 1)

func go_next_move() -> void:
	navigate_to_ply(current_ply_index + 1)

func go_last_move() -> void:
	navigate_to_ply(game.move_history.size() - 1)

func flip_board() -> void:
	board_flipped = not board_flipped
	var settings = _get_settings_manager()
	if settings:
		settings.set_setting("flip_board", board_flipped)
	position_changed.emit()

func _on_game_board_changed() -> void:
	position_changed.emit()

func _on_game_move_made(p_move: ChessMove) -> void:
	if not is_loading_game:
		current_ply_index = game.move_history.size() - 1
		move_made.emit(p_move)
