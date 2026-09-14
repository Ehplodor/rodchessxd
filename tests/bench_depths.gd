extends SceneTree

var stdio: FileAccess

func send(cmd: String) -> void:
	stdio.store_string(cmd + "\n")
	stdio.flush()

func wait_for_bestmove() -> int:
	var t0 = Time.get_ticks_msec()
	while true:
		var line = stdio.get_line().strip_edges()
		if line.begins_with("bestmove "):
			return Time.get_ticks_msec() - t0
		if Time.get_ticks_msec() - t0 > 10000:
			return -1
	return -1

func _init() -> void:
	print("--- TEST PROFONDEURS STOCKFISH 18 ---")
	var exe_path = "C:/Dev/RodChessXD/bin/stockfish.exe"
	var pipe = OS.execute_with_pipe(exe_path, [], false)
	stdio = pipe.get("stdio")
	
	send("uci")
	OS.delay_msec(100)
	while true:
		var l = stdio.get_line().strip_edges()
		if l == "uciok":
			break

	send("setoption name MultiPV value 1")
	send("setoption name Threads value 2")
	send("setoption name Hash value 128")
	send("isready")
	while stdio.get_line().strip_edges() != "readyok":
		pass

	var fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

	for d in [10, 11, 12, 13, 14, 15, 16]:
		send("ucinewgame")
		send("position fen " + fen)
		send("go depth %d" % d)
		var ms = wait_for_bestmove()
		print("Depth=%2d -> %3d ms" % [d, ms])
	
	send("quit")
	quit(0)
