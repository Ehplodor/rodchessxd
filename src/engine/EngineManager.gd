extends Node
## EngineManager.gd - Contrôleur de moteur d'échecs UCI asynchrone et gestionnaire de téléchargements

signal engine_ready
signal evaluation_updated(score_cp: int, mate_in: int, depth: int, best_move: String, pv_line: Array, multipv_lines: Array)
signal engine_error(error_msg: String)
signal download_progress(engine_name: String, percentage: float)
signal download_completed(engine_name: String)

var is_engine_running: bool = false
var is_evaluating: bool = false
var engine_process_id: int = -1
var process_pipe: Dictionary = {}

var current_fen: String = ""
var eval_score_cp: int = 0
var eval_mate_in: int = 0
var eval_depth: int = 0
var best_move_uci: String = ""
var pv_line: Array[String] = []
var multipv_lines: Array[Dictionary] = []

var engine_thread: Thread
var should_stop_thread: bool = false
var command_mutex: Mutex
var command_queue: Array[String] = []

# Moteurs et réseaux téléchargeables
const DOWNLOADABLE_ENGINES = {
	"Maia 1100 (Humain Débutant)": {
		"filename": "maia-1100.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/models/maia-1100.pb.gz",
		"desc": "Prédit les coups joués par des joueurs humains de ~1100 ELO."
	},
	"Maia 1500 (Humain Intermédiaire)": {
		"filename": "maia-1500.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/models/maia-1500.pb.gz",
		"desc": "Prédit les coups joués par des joueurs humains de ~1500 ELO."
	},
	"Maia 1900 (Humain Avancé)": {
		"filename": "maia-1900.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/models/maia-1900.pb.gz",
		"desc": "Prédit les coups joués par des joueurs de club avancés ~1900 ELO."
	}
}

func _ready() -> void:
	command_mutex = Mutex.new()
	_ensure_engine_directories()
	call_deferred("start_engine")

func _ensure_engine_directories() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("engines"):
		dir.make_dir("engines")

func _get_engine_executable_path() -> String:
	# 1. Vérifier si un chemin personnalisé est configuré
	var custom_path = SettingsManager.get_setting("engine_path", "")
	if custom_path != "" and FileAccess.file_exists(custom_path):
		return custom_path
	
	# 2. Vérifier dans user://engines/
	var user_stockfish = OS.get_user_data_dir() + "/engines/stockfish.exe"
	if FileAccess.file_exists(user_stockfish):
		return user_stockfish

	# 3. Vérifier dans res://bin/ (packagé avec l'application)
	var project_bin = ProjectSettings.globalize_path("res://bin/stockfish.exe")
	if FileAccess.file_exists(project_bin):
		return project_bin

	# 4. Chemins système typiques sur Windows
	var dev_path = "c:/Dev/RodChessXD/bin/stockfish.exe"
	if FileAccess.file_exists(dev_path):
		return dev_path

	return ""

func start_engine() -> bool:
	if is_engine_running:
		return true

	var exe_path = _get_engine_executable_path()
	if exe_path == "":
		print("EngineManager: Aucun exécutable de moteur trouvé.")
		engine_error.emit("Moteur d'échecs non trouvé.")
		return false

	print("EngineManager: Lancement de Stockfish depuis ", exe_path)
	
	# Utilisation de OS.execute_with_pipe pour communication bidirectionnelle non bloquante
	process_pipe = OS.execute_with_pipe(exe_path, [])
	if process_pipe.is_empty() or not process_pipe.has("stdio"):
		print("EngineManager: Échec d'exécution du sous-processus moteur.")
		engine_error.emit("Impossible de démarrer le moteur UCI.")
		return false

	is_engine_running = true

	# Démarrage du thread de lecture des réponses UCI
	should_stop_thread = false
	engine_thread = Thread.new()
	engine_thread.start(_engine_reader_loop)

	# Initialisation UCI
	send_command("uci")
	var threads = SettingsManager.get_setting("engine_threads", 2)
	var hash_mb = SettingsManager.get_setting("engine_hash_mb", 32)
	send_command("setoption name Threads value %d" % threads)
	send_command("setoption name Hash value %d" % hash_mb)
	send_command("isready")
	send_command("ucinewgame")

	engine_ready.emit()
	return true

func send_command(cmd: String) -> void:
	if not is_engine_running or not process_pipe.has("stdio"):
		return
	var stdio: FileAccess = process_pipe["stdio"]
	if stdio and stdio.is_open():
		command_mutex.lock()
		stdio.store_line(cmd)
		stdio.flush()
		command_mutex.unlock()

func evaluate_position(fen: String, depth: int = -1) -> void:
	if not is_engine_running:
		return
	
	if depth <= 0:
		depth = SettingsManager.get_setting("engine_depth", 18)
	
	current_fen = fen
	is_evaluating = true
	
	send_command("stop")
	send_command("position fen " + fen)
	send_command("go depth %d" % depth)

func stop_evaluation() -> void:
	if is_evaluating:
		send_command("stop")
		is_evaluating = false

func _engine_reader_loop() -> void:
	var stdio: FileAccess = process_pipe.get("stdio", null)
	if not stdio:
		return

	while not should_stop_thread and is_engine_running:
		if stdio.is_open():
			var line = stdio.get_line()
			if line != "":
				_parse_engine_line(line)
		else:
			break
		OS.delay_msec(5)

func _parse_engine_line(line: String) -> void:
	# Exemple de ligne : info depth 18 seldepth 22 multipv 1 score cp 45 nodes 84523 pv e2e4 e7e5 ...
	if line.begins_with("info "):
		var tokens = line.split(" ", false)
		var i = 1
		var depth = 0
		var score_cp = eval_score_cp
		var mate_in = 0
		var pv: Array[String] = []

		while i < tokens.size():
			match tokens[i]:
				"depth":
					if i + 1 < tokens.size():
						depth = tokens[i + 1].to_int()
						i += 1
				"score":
					if i + 2 < tokens.size():
						if tokens[i + 1] == "cp":
							score_cp = tokens[i + 2].to_int()
							mate_in = 0
							i += 2
						elif tokens[i + 1] == "mate":
							mate_in = tokens[i + 2].to_int()
							# En centipions, un mat est représenté par ±10000
							score_cp = 10000 if mate_in > 0 else -10000
							i += 2
				"pv":
					# Tous les tokens suivants sont les coups de la ligne principale
					for j in range(i + 1, tokens.size()):
						pv.append(tokens[j])
					break
			i += 1

		# Inversion du score selon le trait (Stockfish donne le score du point de vue du camp qui a le trait)
		# Dans notre interface, on convertit toujours le score du point de vue des Blancs (+ = avantage Blancs)
		var white_to_move = true
		if current_fen != "":
			var fen_parts = current_fen.split(" ")
			if fen_parts.size() > 1 and fen_parts[1] == "b":
				white_to_move = false

		var normalized_cp = score_cp if white_to_move else -score_cp

		if depth > 0:
			eval_depth = depth
			eval_score_cp = normalized_cp
			eval_mate_in = mate_in
			pv_line = pv
			if pv.size() > 0:
				best_move_uci = pv[0]
			
			_emit_evaluation_deferred.call_deferred(normalized_cp, mate_in, depth, best_move_uci, pv_line, multipv_lines)

	elif line.begins_with("bestmove "):
		var parts = line.split(" ", false)
		if parts.size() > 1:
			best_move_uci = parts[1]
		is_evaluating = false

func _emit_evaluation_deferred(score_cp: int, mate_in: int, depth: int, best_move: String, pv: Array, multipv: Array) -> void:
	evaluation_updated.emit(score_cp, mate_in, depth, best_move, pv, multipv)

func _exit_tree() -> void:
	stop_engine()

func stop_engine() -> void:
	if is_engine_running:
		should_stop_thread = true
		send_command("quit")
		is_engine_running = false
		if engine_thread and engine_thread.is_started():
			engine_thread.wait_to_finish()
