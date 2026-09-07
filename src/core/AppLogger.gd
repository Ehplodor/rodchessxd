extends Node
## AppLogger — journal local en fichier (jalon M8 « Observabilité », essai beta).
## Objectif KISS : un fichier par session (`user://logs/rodchess_*.log`), rotation
## de 5 fichiers, écriture séquentielle, export du chemin pour le beta.
## Sert aussi à journaliser la navigation temporelle (jalon M2) afin de diagnostiquer
## sur téléphone réel d'éventuels soucis d'animation / de scrub.

const LOG_DIR := "user://logs"
const MAX_FILES := 5

var session_id := ""
var _path := ""
var _file: FileAccess = null

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	session_id = "%04x%04x" % [rng.randi() & 0xFFFF, rng.randi() & 0xFFFF]
	_ensure_log_dir()
	_open_file()
	_write_header()
	_prune()

func _ensure_log_dir() -> void:
	if DirAccess.dir_exists_absolute(LOG_DIR):
		return
	DirAccess.make_dir_recursive_absolute(LOG_DIR)

func _open_file() -> void:
	var t := Time.get_datetime_dict_from_system()
	var fname := "rodchess_%04d-%02d-%02d_%02d-%02d-%02d.log" % [
		t.year, t.month, t.day, t.hour, t.minute, t.second]
	_path = "%s/%s" % [LOG_DIR, fname]
	_file = FileAccess.open(_path, FileAccess.WRITE)

## Garde 5 fichiers max (le fichier courant est le plus récent, jamais supprimé).
func _prune() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	var logs: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".log"):
			logs.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	logs.sort()
	while logs.size() > MAX_FILES:
		var oldest: String = logs.pop_front()
		if oldest != _path.get_file():
			dir.remove(oldest)

func _write_header() -> void:
	if _file == null:
		return
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	_file.store_line("# RodChessXD log — session %s" % session_id)
	_file.store_line("# version=%s | os=%s (%s) | device=%s" % [
		ver, OS.get_name(), Engine.get_architecture_name(), OS.get_processor_name()])
	_file.store_line("# début %s" % Time.get_datetime_string_from_system(false, true))
	_file.flush()

func log(tag: String, msg: String) -> void:
	if _file == null:
		return
	_file.store_line("[%s] [%s] %s" % [
		Time.get_datetime_string_from_system(false, true), tag, msg])
	_file.flush()

## Renvoie le chemin du fichier de logs courant (utilisé par l'export beta).
func export_logs() -> String:
	if _file:
		_file.flush()
	return _path

## Résumé version / moteur / appareil / session, affiché dans « À propos ».
func info_line() -> String:
	var ver: String = str(ProjectSettings.get_setting("application/config/version", "?"))
	return "RodChessXD v%s\nMoteur : Stockfish\nOS : %s (%s)\nAppareil : %s\nSession : %s" % [
		ver, OS.get_name(), Engine.get_architecture_name(), OS.get_processor_name(), session_id]
