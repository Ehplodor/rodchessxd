extends SceneTree

func _init() -> void:
	var exe_path = "C:/Dev/RodChessXD/bin/stockfish.exe"
	var pipe = OS.execute_with_pipe(exe_path, [], false)
	var stdio = pipe.get("stdio")
	stdio.store_string("uci\n")
	stdio.flush()
	while true:
		var line = stdio.get_line().strip_edges()
		if line.begins_with("option "):
			print(line)
		elif line == "uciok":
			break
	stdio.store_string("quit\n")
	stdio.flush()
	quit(0)
