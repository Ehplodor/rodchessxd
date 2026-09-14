extends Node
## ModelDownloader.gd - Gestionnaire de téléchargement in-app de modèles SLM locaux (GGUF)
## Téléchargement streamé directement sur disque (user://models/) sans impacter la mémoire vive.

signal download_progress(model_id: String, received_bytes: int, total_bytes: int, percentage: float, speed_mb_s: float)
signal download_completed(model_id: String, file_path: String)
signal download_failed(model_id: String, error_msg: String)
signal model_deleted(model_id: String)

const MODELS_DIR = "user://models/"

## Catalogue des modèles SLM officiellement téléchargeables
const DOWNLOADABLE_SLM = {
	"native_slm/smollm2-360m": {
		"id": "native_slm/smollm2-360m",
		"name": "SmolLM2 360M Instruct (Recommandé)",
		"filename": "smollm2-360m-instruct-q4_k_m.gguf",
		"size_bytes": 240832512, # ~229 Mo
		"size_label": "~229 Mo",
		"ram_required": "~500 Mo",
		"description": "Ultra-compact et rapide. Idéal pour CPU modestes et smartphones. Excellente vivacité.",
		"url": "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf",
		"provider": "native_slm"
	},
	"native_slm/qwen2.5-0.5b": {
		"id": "native_slm/qwen2.5-0.5b",
		"name": "Qwen 2.5 0.5B Instruct",
		"filename": "qwen2.5-0.5b-instruct-q4_k_m.gguf",
		"size_bytes": 417857536, # ~398 Mo
		"size_label": "~398 Mo",
		"ram_required": "~850 Mo",
		"description": "Compréhension stratégique remarquable et français impeccable pour sa taille.",
		"url": "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2_5-0_5b-instruct-q4_k_m.gguf",
		"provider": "native_slm"
	},
	"native_slm/smollm2-1.7b": {
		"id": "native_slm/smollm2-1.7b",
		"name": "SmolLM2 1.7B Instruct (Grand Modèle)",
		"filename": "smollm2-1.7b-instruct-q4_k_m.gguf",
		"size_bytes": 1098907648, # ~1.05 Go
		"size_label": "~1.05 Go",
		"ram_required": "~2.2 Go",
		"description": "Explications haut de gamme, nuances pédagogiques profondes et vocabulaire riche.",
		"url": "https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf",
		"provider": "native_slm"
	}
}

var http_downloader: HTTPRequest
var current_download_id: String = ""
var current_target_path: String = ""
var is_downloading: bool = false

var last_bytes: int = 0
var last_time_msec: int = 0
var current_speed_mb_s: float = 0.0

func _ready() -> void:
	_ensure_models_directory()
	http_downloader = HTTPRequest.new()
	http_downloader.use_threads = true
	add_child(http_downloader)
	http_downloader.request_completed.connect(_on_download_completed)
	set_process(false)

func _process(_delta: float) -> void:
	if not is_downloading or not http_downloader:
		return

	var current_bytes = http_downloader.get_downloaded_bytes()
	var total_bytes = http_downloader.get_body_size()

	# Si get_body_size() retourne -1, se baser sur la taille connue du catalogue
	if total_bytes <= 0 and DOWNLOADABLE_SLM.has(current_download_id):
		total_bytes = DOWNLOADABLE_SLM[current_download_id].get("size_bytes", 0)

	var now = Time.get_ticks_msec()
	var time_diff = now - last_time_msec
	if time_diff >= 500: # Calculer la vitesse toutes les 500 ms
		var bytes_diff = current_bytes - last_bytes
		current_speed_mb_s = (bytes_diff / 1048576.0) / (time_diff / 1000.0)
		last_bytes = current_bytes
		last_time_msec = now

	var percentage: float = 0.0
	if total_bytes > 0:
		percentage = clamp((float(current_bytes) / float(total_bytes)) * 100.0, 0.0, 100.0)

	download_progress.emit(current_download_id, current_bytes, total_bytes, percentage, current_speed_mb_s)

func _ensure_models_directory() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("models"):
		dir.make_dir("models")

## Vérifie si un modèle est déjà installé en local
func is_model_installed(model_id: String) -> bool:
	if not DOWNLOADABLE_SLM.has(model_id):
		return false
	var fn = DOWNLOADABLE_SLM[model_id]["filename"]
	var path = MODELS_DIR + fn
	return FileAccess.file_exists(path)

## Retourne le chemin absolu sur disque d'un modèle installé
func get_model_file_path(model_id: String) -> String:
	if not is_model_installed(model_id):
		return ""
	var fn = DOWNLOADABLE_SLM[model_id]["filename"]
	return OS.get_user_data_dir() + "/models/" + fn

## Retourne la liste des IDs des modèles actuellement installés
func get_installed_models() -> Array[String]:
	var list: Array[String] = []
	for m_id in DOWNLOADABLE_SLM.keys():
		if is_model_installed(m_id):
			list.append(m_id)
	return list

## Lance le téléchargement d'un modèle
func start_download(model_id: String) -> bool:
	if is_downloading:
		print("ModelDownloader: Téléchargement déjà en cours pour ", current_download_id)
		return false

	if not DOWNLOADABLE_SLM.has(model_id):
		download_failed.emit(model_id, "Modèle introuvable dans le catalogue.")
		return false

	var info = DOWNLOADABLE_SLM[model_id]
	var url = info["url"]
	var fn = info["filename"]
	current_target_path = MODELS_DIR + fn
	current_download_id = model_id

	# Utiliser download_file pour que Godot écrive directement sur disque
	http_downloader.download_file = current_target_path
	last_bytes = 0
	last_time_msec = Time.get_ticks_msec()
	current_speed_mb_s = 0.0
	is_downloading = true
	set_process(true)

	print("ModelDownloader: Démarrage du téléchargement de %s vers %s..." % [info["name"], current_target_path])
	var headers = [
		"User-Agent: RodChessXD-Downloader/1.0"
	]
	var err = http_downloader.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		is_downloading = false
		set_process(false)
		http_downloader.download_file = ""
		download_failed.emit(model_id, "Erreur de lancement de la requête réseau (%d)." % err)
		return false

	return true

## Annule le téléchargement en cours et supprime le fichier partiel
func cancel_download() -> void:
	if not is_downloading:
		return
	
	http_downloader.cancel_request()
	is_downloading = false
	set_process(false)
	http_downloader.download_file = ""

	# Nettoyer le fichier partiel
	if FileAccess.file_exists(current_target_path):
		DirAccess.remove_absolute(current_target_path)

	var cancelled_id = current_download_id
	current_download_id = ""
	current_target_path = ""
	download_failed.emit(cancelled_id, "Téléchargement annulé par l'utilisateur.")

## Supprime un modèle installé pour libérer de l'espace disque
func delete_model(model_id: String) -> bool:
	if not is_model_installed(model_id):
		return false

	var fn = DOWNLOADABLE_SLM[model_id]["filename"]
	var full_path = MODELS_DIR + fn
	var err = DirAccess.remove_absolute(full_path)
	if err == OK:
		print("ModelDownloader: Modèle %s supprimé avec succès." % model_id)
		model_deleted.emit(model_id)
		return true
	return false

## Callback fin de téléchargement HTTP
func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	is_downloading = false
	set_process(false)
	http_downloader.download_file = ""

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		# Nettoyage si échec
		if FileAccess.file_exists(current_target_path):
			DirAccess.remove_absolute(current_target_path)
		var err_msg = "Erreur HTTP %d (Résultat: %d)" % [response_code, result]
		print("ModelDownloader: Échec - ", err_msg)
		download_failed.emit(current_download_id, err_msg)
		current_download_id = ""
		current_target_path = ""
		return

	print("ModelDownloader: Téléchargement réussi pour ", current_download_id)
	download_completed.emit(current_download_id, current_target_path)
	current_download_id = ""
	current_target_path = ""
