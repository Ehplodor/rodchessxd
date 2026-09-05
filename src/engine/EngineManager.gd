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
var state_mutex: Mutex
var command_queue: Array[String] = []

var boot_thread: Thread
var _booting := false

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
	state_mutex = Mutex.new()
	_ensure_engine_directories()
	call_deferred("_ensure_engine_started")

func _ensure_engine_directories() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("engines"):
		dir.make_dir("engines")

func _engine_binary_names() -> PackedStringArray:
	if OS.has_feature("android"):
		return PackedStringArray(["stockfish", "libstockfish.so"])
	if OS.get_name() == "Windows":
		return PackedStringArray(["stockfish.exe"])
	return PackedStringArray(["stockfish", "libstockfish.so"])

func _get_engine_executable_path() -> String:
	var is_android = OS.has_feature("android")
	var names = _engine_binary_names()

	# 1. Vérifier si un chemin personnalisé est configuré
	var custom_path = SettingsManager.get_setting("engine_path", "")
	if custom_path != "" and FileAccess.file_exists(custom_path):
		return custom_path

	# 2. Vérifier dans user://engines/ (binaire réellement présent sur le disque)
	for n in names:
		var user_engine = OS.get_user_data_dir() + "/engines/" + n
		if FileAccess.file_exists(user_engine):
			return user_engine

	# 3. Vérifier dans res://bin/ (binaire embarqué avec l'application)
	for n in names:
		var res_bin = "res://bin/" + n
		if FileAccess.file_exists(res_bin):
			var globalized = ProjectSettings.globalize_path(res_bin)
			if FileAccess.file_exists(globalized):
				return globalized
			return _extract_engine_to_user_dir(n)

	# 4. Chemins de développement (uniquement sur bureau, jamais sur mobile)
	if not is_android:
		var dev_path = "c:/Dev/RodChessXD/bin/" + names[0]
		if FileAccess.file_exists(dev_path):
			return dev_path

	return ""

func _extract_engine_to_user_dir(name: String) -> String:
	var src = "res://bin/" + name
	var dst = OS.get_user_data_dir() + "/engines/" + name
	var src_file = FileAccess.open(src, FileAccess.READ)
	if src_file == null:
		return ""
	var dst_file = FileAccess.open(dst, FileAccess.WRITE)
	if dst_file == null:
		src_file.close()
		return ""
	while not src_file.eof_reached():
		var chunk = src_file.get_buffer(1 << 20)
		dst_file.store_buffer(chunk)
	src_file.close()
	dst_file.close()
	return dst if FileAccess.file_exists(dst) else ""

func is_engine_available() -> bool:
	state_mutex.lock()
	var running = is_engine_running
	state_mutex.unlock()
	return running

func _pending_extraction_name() -> String:
	if SettingsManager.get_setting("engine_path", "") != "":
		return ""
	for n in _engine_binary_names():
		if FileAccess.file_exists(OS.get_user_data_dir() + "/engines/" + n):
			return ""
	for n in _engine_binary_names():
		if FileAccess.file_exists("res://bin/" + n):
			var globalized = ProjectSettings.globalize_path("res://bin/" + n)
			if not FileAccess.file_exists(globalized):
				return n
	return ""

func _ensure_engine_started() -> void:
	var extract_name = _pending_extraction_name()
	if extract_name == "":
		start_engine()
		return
	_booting = true
	boot_thread = Thread.new()
	boot_thread.start(_extract_engine_thread.bind(extract_name))

func _extract_engine_thread(name: String) -> void:
	_extract_engine_to_user_dir(name)
	call_deferred("_on_engine_extracted")

func _on_engine_extracted() -> void:
	_booting = false
	if boot_thread and boot_thread.is_started():
		boot_thread.wait_to_finish()
	if not is_engine_running:
		start_engine()

func _engine_missing_hint() -> String:
	if OS.has_feature("android"):
		return "Placez un binaire Stockfish arm64 nommé \"stockfish\" dans user://engines/ (ou libstockfish.so dans bin/)."
	return "Placez \"stockfish.exe\" dans bin/ ou user://engines/."

func start_engine() -> bool:
	if is_engine_running:
		return true
	if _booting:
		return false

	var exe_path = _get_engine_executable_path()
	if exe_path == "":
		var hint = _engine_missing_hint()
		print("EngineManager: Aucun exécutable de moteur trouvé. ", hint)
		engine_error.emit("Moteur d'échecs non trouvé. %s" % hint)
		return false

	print("EngineManager: Lancement de Stockfish depuis ", exe_path)
	
	# Utilisation de OS.execute_with_pipe pour communication bidirectionnelle non bloquante
	process_pipe = OS.execute_with_pipe(exe_path, [])
	if process_pipe.is_empty() or not process_pipe.has("stdio"):
		var exec_hint = " Vérifiez que le binaire est un exécutable arm64 valide pour Android." if OS.has_feature("android") else " Vérifiez le chemin du moteur."
		print("EngineManager: Échec d'exécution du sous-processus moteur (", exe_path, ").", exec_hint)
		engine_error.emit("Impossible de démarrer le moteur UCI (%s).%s" % [exe_path, exec_hint])
		return false

	state_mutex.lock()
	is_engine_running = true
	state_mutex.unlock()

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
	
	state_mutex.lock()
	current_fen = fen
	is_evaluating = true
	state_mutex.unlock()
	
	send_command("stop")
	send_command("position fen " + fen)
	send_command("go depth %d" % depth)

func stop_evaluation() -> void:
	if is_evaluating:
		send_command("stop")
		state_mutex.lock()
		is_evaluating = false
		state_mutex.unlock()

## Évaluation synchrone robuste pour l'analyse globale de partie (GameAnalyzer)
func evaluate_position_sync(fen: String, depth: int = 10, timeout_ms: int = 1500) -> Dictionary:
	if not is_engine_available() or not process_pipe.has("stdio"):
		return {"score_cp": 0, "best_move": "", "depth": 0, "timed_out": false, "error": "engine_unavailable"}

	# Si une évaluation était déjà en cours, on l'interrompt proprement
	if is_evaluating:
		send_command("stop")
		var stop_wait = 10
		while is_evaluating and stop_wait > 0:
			OS.delay_msec(10)
			stop_wait -= 1

	state_mutex.lock()
	current_fen = fen
	is_evaluating = true
	best_move_uci = ""
	eval_depth = 0
	state_mutex.unlock()

	send_command("position fen " + fen)
	send_command("go depth %d" % depth)

	var elapsed = 0
	while is_evaluating and elapsed < timeout_ms:
		OS.delay_msec(15)
		elapsed += 15

	var timed_out = is_evaluating
	if timed_out:
		send_command("stop")
		var settle_wait = 20
		while is_evaluating and settle_wait > 0:
			OS.delay_msec(15)
			settle_wait -= 1
		if is_evaluating:
			state_mutex.lock()
			is_evaluating = false
			state_mutex.unlock()

	state_mutex.lock()
	var result = {
		"score_cp": eval_score_cp,
		"best_move": best_move_uci,
		"depth": eval_depth,
		"timed_out": timed_out
	}
	state_mutex.unlock()
	return result

func _engine_reader_loop() -> void:
	var stdio: FileAccess = process_pipe.get("stdio", null)
	if not stdio:
		return

	while not should_stop_thread and is_engine_available():
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
		state_mutex.lock()
		var score_cp = eval_score_cp
		var current_fen_snapshot = current_fen
		state_mutex.unlock()
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
		if current_fen_snapshot != "":
			var fen_parts = current_fen_snapshot.split(" ")
			if fen_parts.size() > 1 and fen_parts[1] == "b":
				white_to_move = false

		var normalized_cp = score_cp if white_to_move else -score_cp

		if depth > 0:
			state_mutex.lock()
			eval_depth = depth
			eval_score_cp = normalized_cp
			eval_mate_in = mate_in
			pv_line = pv
			if pv.size() > 0:
				best_move_uci = pv[0]
			var emit_args = [normalized_cp, mate_in, depth, best_move_uci, pv_line, multipv_lines]
			state_mutex.unlock()
			_emit_evaluation_deferred.call_deferred(emit_args)

	elif line.begins_with("bestmove "):
		var parts = line.split(" ", false)
		state_mutex.lock()
		if parts.size() > 1:
			best_move_uci = parts[1]
		is_evaluating = false
		state_mutex.unlock()

func _emit_evaluation_deferred(emit_args: Array) -> void:
	evaluation_updated.emit(emit_args[0], emit_args[1], emit_args[2], emit_args[3], emit_args[4], emit_args[5])

func _exit_tree() -> void:
	stop_engine()

func stop_engine() -> void:
	if is_engine_running:
		should_stop_thread = true
		send_command("quit")
		state_mutex.lock()
		is_engine_running = false
		state_mutex.unlock()
		if engine_thread and engine_thread.is_started():
			engine_thread.wait_to_finish()
