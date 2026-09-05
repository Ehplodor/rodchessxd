extends Node
## LocalSLMManager.gd - Contrôleur du processus d'inférence SLM local (Sidecar llama-server)
## Supervise le cycle de vie du serveur OpenAI-compatible local sur port 8085.

signal server_started(port: int, model_id: String)
signal server_stopped
signal server_error(error_msg: String)
signal server_ready

const DEFAULT_PORT = 8085
const LOCAL_API_URL = "http://127.0.0.1:%d/v1/chat/completions"
const HEALTH_URL = "http://127.0.0.1:%d/health"

var server_pid: int = -1
var is_running: bool = false
var active_model_id: String = ""
var active_model_path: String = ""
var current_port: int = DEFAULT_PORT

var http_health: HTTPRequest
var check_attempts: int = 0
var max_check_attempts: int = 20

func _ready() -> void:
	http_health = HTTPRequest.new()
	http_health.timeout = 2.0
	add_child(http_health)
	http_health.request_completed.connect(_on_health_completed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_server()

func _get_settings() -> Node:
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("SettingsManager"):
		return tree.root.get_node("SettingsManager")
	return null

## Retourne le chemin du binaire llama-server sur le système
func get_server_executable_path() -> String:
	# 1. Vérifier le paramètre personnalisé dans les réglages
	var sm = _get_settings()
	var custom = sm.get_setting("llama_server_path", "") if sm else ""
	if custom != "" and FileAccess.file_exists(custom):
		return custom

	# 2. Vérifier dans user://bin/
	var user_bin = OS.get_user_data_dir() + "/bin/llama-server.exe"
	if FileAccess.file_exists(user_bin):
		return user_bin

	# 3. Vérifier dans res://bin/
	var proj_bin = ProjectSettings.globalize_path("res://bin/llama-server.exe")
	if FileAccess.file_exists(proj_bin):
		return proj_bin

	# 4. Chemins développement usuels
	var dev_bin = "c:/Dev/RodChessXD/bin/llama-server.exe"
	if FileAccess.file_exists(dev_bin):
		return dev_bin

	return ""

## Vérifie si l'exécutable d'inférence est disponible
func is_inference_engine_available() -> bool:
	return get_server_executable_path() != ""

## Retourne l'URL de l'API OpenAI compatible pour les requêtes
func get_api_endpoint_url() -> String:
	return LOCAL_API_URL % current_port

## Démarre le serveur local avec le modèle GGUF spécifié
func start_server_for_model(model_id: String, port: int = DEFAULT_PORT) -> bool:
	if is_running and active_model_id == model_id:
		print("LocalSLMManager: Le serveur est déjà actif pour ce modèle.")
		return true

	# Arrêter l'ancien serveur s'il tournait sur un autre modèle
	if is_running:
		stop_server()

	# Récupérer le chemin du modèle GGUF via ModelDownloader
	var model_path = ""
	if Engine.has_singleton("ModelDownloader") or has_node("/root/ModelDownloader"):
		var downloader = get_node("/root/ModelDownloader")
		model_path = downloader.get_model_file_path(model_id)

	if model_path == "" or not FileAccess.file_exists(model_path):
		var err = "Fichier de modèle GGUF introuvable sur le disque pour %s." % model_id
		print("LocalSLMManager: ", err)
		server_error.emit(err)
		return false

	var exe = get_server_executable_path()
	if exe == "":
		var err = "Exécutable d'inférence (llama-server.exe) non trouvé dans bin/."
		print("LocalSLMManager: ", err)
		server_error.emit(err)
		return false

	current_port = port
	active_model_id = model_id
	active_model_path = model_path

	# Arguments de lancement optimisés pour processeur moderne
	# -c 2048 : contexte de 2048 tokens suffisant pour un coup d'échecs
	# -n 512 : génération maximale de 512 tokens
	# -t 4 : 4 threads CPU
	# --nobrowser : n'ouvre pas d'onglet navigateur automatique
	var args: PackedStringArray = [
		"-m", model_path,
		"--port", str(port),
		"-c", "2048",
		"-n", "512",
		"-t", "4",
		"--nobrowser"
	]

	print("LocalSLMManager: Lancement de %s avec %s sur port %d..." % [exe, model_path, port])
	server_pid = OS.create_process(exe, args, false)

	if server_pid <= 0:
		var err = "Échec du démarrage du processus llama-server (Code retour: %d)." % server_pid
		print("LocalSLMManager: ", err)
		server_error.emit(err)
		return false

	is_running = true
	print("LocalSLMManager: Processus démarré avec PID %d. Vérification de santé en cours..." % server_pid)
	server_started.emit(current_port, active_model_id)

	# Lancement de la boucle de sondage /health
	check_attempts = 0
	_check_server_health()
	return true

## Vérifie si le serveur répond sur /health
func _check_server_health() -> void:
	if not is_running:
		return
	check_attempts += 1
	var url = HEALTH_URL % current_port
	var err = http_health.request(url)
	if err != OK and check_attempts < max_check_attempts:
		await get_tree().create_timer(1.0).timeout
		_check_server_health()

func _on_health_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code == 200:
		print("LocalSLMManager: Serveur SLM prêt et opérationnel sur port %d !" % current_port)
		server_ready.emit()
	else:
		if check_attempts < max_check_attempts and is_running:
			await get_tree().create_timer(1.0).timeout
			_check_server_health()
		else:
			print("LocalSLMManager: Avertissement - Délai d'attente du serveur dépassé (Code: %d)." % response_code)

## Arrête proprement le processus local
func stop_server() -> void:
	if not is_running or server_pid <= 0:
		return

	print("LocalSLMManager: Extinction du serveur SLM (PID: %d)..." % server_pid)
	OS.kill(server_pid)
	server_pid = -1
	is_running = false
	active_model_id = ""
	active_model_path = ""
	server_stopped.emit()

## S'assure qu'un modèle donné est prêt à servir des requêtes
func ensure_model_running(model_id: String) -> bool:
	if is_running and active_model_id == model_id:
		return true
	return start_server_for_model(model_id)
