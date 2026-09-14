extends SceneTree

var stdio: FileAccess

func send(cmd: String) -> void:
	stdio.store_string(cmd + "\n")
	stdio.flush()

func eval_fen(fen: String, depth: int = 16) -> Dictionary:
	send("position fen " + fen)
	send("go depth %d" % depth)
	var best_move = ""
	var score_cp = 0
	var mate_in = 0
	var pv: Array[String] = []
	var t0 = Time.get_ticks_msec()
	while true:
		var line = stdio.get_line().strip_edges()
		if line.begins_with("info ") and line.contains(" score ") and line.contains(" depth %d " % depth):
			var tokens = line.split(" ", false)
			var pv_idx = tokens.find("pv")
			if pv_idx != -1:
				pv.clear()
				for j in range(pv_idx + 1, mini(tokens.size(), pv_idx + 8)):
					pv.append(tokens[j])
			var sc_idx = tokens.find("cp")
			if sc_idx != -1 and sc_idx + 1 < tokens.size():
				score_cp = tokens[sc_idx + 1].to_int()
			var mate_idx = tokens.find("mate")
			if mate_idx != -1 and mate_idx + 1 < tokens.size():
				mate_in = tokens[mate_idx + 1].to_int()
				score_cp = 10000 if mate_in > 0 else -10000
		elif line.begins_with("bestmove "):
			var parts = line.split(" ")
			if parts.size() > 1:
				best_move = parts[1]
			break
		if Time.get_ticks_msec() - t0 > 10000:
			break
	
	# Inversion du score selon le trait (pour Stockfish blanc vs noir)
	var white_to_move = true
	var fen_parts = fen.split(" ")
	if fen_parts.size() > 1 and fen_parts[1] == "b":
		white_to_move = false
	var norm_cp = score_cp if white_to_move else -score_cp
	var norm_mate = mate_in if white_to_move else -mate_in
	
	return {
		"score_cp": norm_cp,
		"mate_in": norm_mate,
		"best_move": best_move,
		"depth": depth,
		"pv_line": pv,
		"multipv_lines": [{
			"rank": 1,
			"depth": depth,
			"score_cp": norm_cp,
			"mate_in": norm_mate,
			"best_move": best_move,
			"fen": fen,
			"pv": pv
		}],
		"timed_out": false,
		"cancelled": false
	}

func _init() -> void:
	print("--- GÉNÉRATION DE LA TABLE D'OUVERTURES PRÉ-CALCULÉES ---")
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
	send("setoption name Threads value 4")
	send("setoption name Hash value 128")
	send("isready")
	while stdio.get_line().strip_edges() != "readyok":
		pass

	var fens = [
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
		"rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1",
		"rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq c3 0 1",
		"rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1",
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
		"rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
		"rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
		"rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
		"rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2",
		"rnbqkbnr/ppp1pppp/3p4/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
		"rnbqkbnr/pppppp1p/6p1/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2",
		"rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2",
		"rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq d6 0 2",
		"rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 1 2",
		"rnbqkbnr/pppp1ppp/4p3/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2",
		"rnbqkbnr/ppppp1pp/8/5p2/3P4/8/PPP1PPPP/RNBQKBNR w KQkq f6 0 2",
		"rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
		"r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
		"r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
		"r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
		"r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b KQkq d3 0 3",
		"rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2",
		"rnbqkbnr/pp2pppp/3p4/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3",
		"r1bqkbnr/pp1ppppp/2n5/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
		"rnbqkbnr/pp1p1ppp/4p3/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3",
		"rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2",
		"rnbqkb1r/pppp1ppp/4pn2/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3",
		"rnbqkb1r/pppppp1p/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3",
		"rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b KQkq c3 0 2",
		"rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3",
		"rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w KQkq - 0 3",
		"rnbqkbnr/ppp1pppp/8/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 1 2",
		"rnbqkb1r/ppp1pppp/5n2/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 2 3",
		"rnbqkb1r/ppp1pppp/5n2/3p4/3P1B2/5N2/PPP1PPPP/RN1QKB1R b KQkq - 3 3"
	]

	var results = {}
	for fen in fens:
		var ev = eval_fen(fen, 16)
		results[fen] = ev
		print("FEN: %s -> %s (score=%+d, d=%d)" % [fen, ev.best_move, ev.score_cp, ev.depth])

	var f = FileAccess.open("res://src/engine/opening_eval_table.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "\t"))
	f.close()
	print("Table sauvegardée dans res://src/engine/opening_eval_table.json !")
	
	send("quit")
	quit(0)
