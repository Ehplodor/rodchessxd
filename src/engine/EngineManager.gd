extends Node
## EngineManager.gd - Contrôleur de moteur d'échecs UCI asynchrone et gestionnaire de téléchargements

signal engine_ready
signal evaluation_updated(score_cp: int, mate_in: int, depth: int, best_move: String, pv_line: Array, multipv_lines: Array)
signal engine_error(error_msg: String)
signal download_progress(engine_name: String, percentage: float)
signal download_completed(engine_name: String)
signal download_failed(engine_name: String, error_msg: String)
signal engine_profile_changed(profile_id: String)
signal evaluation_finished(best_move: String, score_cp: int, depth: int)

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
## Accumulateur MultiPV par rang (1..N) pendant une évaluation, protégé par state_mutex.
var _multipv_accum: Dictionary = {}
## Valeur MultiPV réellement demandée au moteur (1 = désactivé).
var _multipv_requested: int = 1

## Cache LRU d'évaluation de positions pour réponses instantanées (0 ms)
const EVAL_CACHE_MAX_ENTRIES: int = 1500
var _eval_cache: Dictionary = {}
var _eval_cache_keys: Array[String] = []

## Retourne la clé FEN canonique sans les compteurs de demi-coups ni le numéro de coup (sauf règle des 50 coups >= 80)
static func get_canonical_fen(fen: String) -> String:
	var parts = fen.strip_edges().split(" ")
	if parts.size() >= 4:
		var base = "%s %s %s %s" % [parts[0], parts[1], parts[2], parts[3]]
		if parts.size() >= 5 and parts[4].to_int() >= 80:
			base += " " + parts[4]
		return base
	return fen.strip_edges()

func get_cached_eval(fen: String, min_depth: int, min_multipv: int = 1) -> Dictionary:
	var c_fen := get_canonical_fen(fen)
	state_mutex.lock()
	if _eval_cache.has(c_fen):
		var entry: Dictionary = _eval_cache[c_fen]
		var c_depth: int = int(entry.get("depth", 0))
		var c_mpv_lines: Array = entry.get("multipv_lines", [])
		var c_mpv_count: int = maxi(1, c_mpv_lines.size())
		if c_depth >= min_depth:
			# Même si la position a été analysée avec moins de lignes MultiPV que demandé,
			# on renvoie la meilleure ligne principale (rank 1) immédiatement pour un
			# affichage 0 ms instantané du meilleur coup, du score et de la barre.
			var copy := entry.duplicate(true)
			state_mutex.unlock()
			return copy
	state_mutex.unlock()
	return {}

func store_cached_eval(fen: String, data: Dictionary) -> void:
	if fen.is_empty() or data.is_empty():
		return
	var c_fen := get_canonical_fen(fen)
	state_mutex.lock()
	if not _eval_cache.has(c_fen):
		if _eval_cache_keys.size() >= EVAL_CACHE_MAX_ENTRIES:
			var oldest: String = _eval_cache_keys.pop_front()
			_eval_cache.erase(oldest)
		_eval_cache_keys.append(c_fen)
	_eval_cache[c_fen] = data.duplicate(true)
	state_mutex.unlock()

func clear_eval_cache() -> void:
	state_mutex.lock()
	_eval_cache.clear()
	_eval_cache_keys.clear()
	state_mutex.unlock()

var engine_thread: Thread
var should_stop_thread: bool = false
var command_mutex: Mutex
var state_mutex: Mutex
var command_queue: Array[String] = []

var boot_thread: Thread
var _booting := false
var _is_intentionally_stopping: bool = false

# Moteurs et réseaux téléchargeables
const DOWNLOADABLE_ENGINES = {
	"Maia 1100 (Humain Débutant)": {
		"filename": "maia-1100.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-1100.pb.gz",
		"desc": "Prédit les coups joués par des joueurs humains de ~1100 ELO."
	},
	"Maia 1500 (Humain Intermédiaire)": {
		"filename": "maia-1500.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-1500.pb.gz",
		"desc": "Prédit les coups joués par des joueurs humains de ~1500 ELO."
	},
	"Maia 1900 (Humain Avancé)": {
		"filename": "maia-1900.pb.gz",
		"url": "https://github.com/CSSLab/maia-chess/raw/master/maia_weights/maia-1900.pb.gz",
		"desc": "Prédit les coups joués par des joueurs de club avancés ~1900 ELO."
	}
}

# Source de téléchargement officielle du binaire Stockfish (URL vérifiée le 06/09/2026).
const STOCKFISH_RELEASE_URL = "https://github.com/official-stockfish/Stockfish/releases/download/sf_19/stockfish-android-arm64-universal.tar.gz"

# Source officielle lc0 pour Windows CPU (URL vérifiée le 06/09/2026, contenu : lc0.exe + dnnl.dll + mimalloc*.dll).
const LC0_WINDOWS_RELEASE_URL = "https://github.com/LeelaChessZero/lc0/releases/download/v0.32.1/lc0-v0.32.1-windows-cpu-dnnl.zip"

# Fichiers de réseau Maia téléchargeables (moteur lc0 requis pour les exécuter).
const MAIA_NET_FILES: Array[String] = ["maia-1100.pb.gz", "maia-1500.pb.gz", "maia-1900.pb.gz"]

var install_http: HTTPRequest = null
var _installing_engine := false
var _install_kind := ""
var _install_display := ""
var _install_cache_path := ""
var _install_inner_match := ""
var _install_target_name := ""
var _install_last_bytes := 0
var cancel_eval_requested := false
var _received_any_output := false
var _log_first_raw_line := true
var _started_msec := 0

# Barrière UCI : après `stop`, Stockfish peut encore produire quelques lignes
# `info` avant son `bestmove`. Elles ne doivent jamais contaminer le calcul
# suivant, particulièrement dans le worker Web mono-moteur.
var _stop_pending := false
var _ignore_next_bestmove := false
var _evaluation_generation := 0
var _readyok_serial := 0
var _async_analysis_session_active := false

# Correctif démarrage Live : n'émettre `engine_ready` qu'après la poignée de main UCI.
var _handshake_ready := false
var _pending_live_fen := ""
var _engine_ready_emitted := false

# Throttling UI : évite de surcharger le thread principal à chaque ligne UCI info
var _last_eval_emit_ms: int = 0
var _last_emitted_depth: int = 0

# Transport Android via plugin natif "RodChessUci" (ProcessBuilder) quand il est présent.
var _use_plugin := false
var _plugin_handle: Object = null
var _plugin_connected := false
var _current_engine_path := ""

# Transport Web/Wasm via JavaScriptBridge pour le Web Worker Stockfish.
var _use_wasm := false
var _wasm_callback = null

func _init() -> void:
	command_mutex = Mutex.new()
	state_mutex = Mutex.new()
	_preseed_initial_eval()

## Pré-remplit le cache avec les positions canoniques d'ouverture (temps de calcul 0.00 ms garanti au démarrage)
func _preseed_initial_eval() -> void:
	# 1. Table pré-calculée des ouvertures standard (36 positions canoniques à depth 16)
	const OPENING_TABLE_PATH = "res://src/engine/opening_eval_table.json"
	if FileAccess.file_exists(OPENING_TABLE_PATH):
		var f := FileAccess.open(OPENING_TABLE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				for fen_key in parsed:
					var data: Dictionary = parsed[fen_key]
					store_cached_eval(str(fen_key), data)

	# 2. Position initiale universelle (depth 18) : stockée en dernier pour rester
	#    autoritative (la table d'ouvertures peut la contenir à une profondeur moindre).
	store_cached_eval(ChessGame.INITIAL_FEN, {
		"score_cp": 35,
		"mate_in": 0,
		"best_move": "e2e4",
		"depth": 18,
		"pv_line": ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"],
		"multipv_lines": [{
			"rank": 1,
			"depth": 18,
			"score_cp": 35,
			"mate_in": 0,
			"best_move": "e2e4",
			"fen": ChessGame.INITIAL_FEN,
			"pv": ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"]
		}],
		"timed_out": false,
		"cancelled": false
	})

func _ready() -> void:
	if command_mutex == null:
		command_mutex = Mutex.new()
	if state_mutex == null:
		state_mutex = Mutex.new()
	_preseed_initial_eval()
	_ensure_engine_directories()
	_provision_bundled_engine_files()
	install_http = HTTPRequest.new()
	install_http.use_threads = true
	add_child(install_http)
	install_http.request_completed.connect(_on_engine_install_completed)
	call_deferred("_ensure_engine_started")

func _process(_delta: float) -> void:
	# Correctif Live : émettre `engine_ready` sur le thread principal dès la fin du handshake.
	if _handshake_ready and not _engine_ready_emitted:
		_engine_ready_emitted = true
		_emit_engine_ready_deferred()
	if is_engine_running and not should_stop_thread and _started_msec > 0 and not _received_any_output and Time.get_ticks_msec() - _started_msec > 15000:
		_handle_engine_dead("Le moteur d'échecs ne répond pas (aucune sortie UCI en 15 s depuis « %s »). Binaire probablement non exécutable sur cet appareil (architecture/noexec) ou processus suspendu." % _current_engine_path)
	if _installing_engine and install_http != null:
		var total := install_http.get_body_size()
		var current := install_http.get_downloaded_bytes()
		if total > 0:
			var pct := clampf((float(current) / float(total)) * 100.0, 0.0, 100.0)
			download_progress.emit(_install_display, pct)
	elif _engine_ready_emitted and _received_any_output:
		# Moteur démarré et aucun téléchargement : passer en veille (0% CPU au repos)
		set_process(false)

func _ensure_engine_directories() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("engines"):
		dir.make_dir("engines")

## Copie au premier lancement les fichiers embarqués de res://bin/ (DLL lc0 et réseaux Maia)
## vers user://engines/. Les DLL sont chargées depuis le dossier de l'exe lc0 et ne sont
## jamais extraites par _find_binary_path (seul le binaire l'était) ; les réseaux Maia doivent
## exister sous leur nom attendu pour que is_maia_net_installed() les détecte. Synchronous et
## idempotent : ne recopie que les fichiers absents. Windows hors-éditeur uniquement.
func _provision_bundled_engine_files() -> void:
	if OS.get_name() != "Windows" or OS.has_feature("editor"):
		return
	var bundled_files := PackedStringArray([
		"lc0.exe",
		"dnnl.dll",
		"mimalloc-override.dll",
		"mimalloc-redirect.dll",
		"maia-1100.pb.gz",
		"maia-1500.pb.gz",
		"maia-1900.pb.gz",
	])
	var engines_dir := OS.get_user_data_dir() + "/engines/"
	for f in bundled_files:
		if not FileAccess.file_exists("res://bin/" + f):
			continue
		var dst := engines_dir + f
		if FileAccess.file_exists(dst):
			continue
		if _copy_file_bytes("res://bin/" + f, dst):
			print("EngineManager: Fichier embarqué provisionné : ", f)
		else:
			print("EngineManager: Échec du provisionnement de ", f)

func get_engine_profile() -> String:
	var p: String = SettingsManager.get_setting("engine_profile", "stockfish")
	if p != "stockfish" and p != "maia_lc0":
		p = "stockfish"
	return p

func get_maia_net_filename() -> String:
	var fn: String = SettingsManager.get_setting("maia_net", "maia-1500.pb.gz")
	if not MAIA_NET_FILES.has(fn):
		fn = "maia-1500.pb.gz"
	return fn

func is_lc0_profile() -> bool:
	return get_engine_profile() == "maia_lc0"

func get_active_maia_net_path() -> String:
	var p := OS.get_user_data_dir() + "/engines/" + get_maia_net_filename()
	if not FileAccess.file_exists(p):
		return ""
	return p

func is_maia_net_installed(fn: String) -> bool:
	return FileAccess.file_exists(OS.get_user_data_dir() + "/engines/" + fn)

func is_lc0_binary_present() -> bool:
	var custom: String = SettingsManager.get_setting("lc0_path", "")
	if custom != "" and FileAccess.file_exists(custom):
		return true
	var names: PackedStringArray
	if OS.has_feature("android"):
		names = PackedStringArray(["lc0"])
	elif OS.get_name() == "Windows":
		names = PackedStringArray(["lc0.exe"])
	else:
		names = PackedStringArray(["lc0"])
	for n in names:
		if FileAccess.file_exists(OS.get_user_data_dir() + "/engines/" + n):
			return true
		if FileAccess.file_exists("res://bin/" + n):
			return true
	return false

func _stockfish_binary_names() -> PackedStringArray:
	if OS.has_feature("android"):
		return PackedStringArray(["stockfish", "libstockfish.so"])
	if OS.get_name() == "Windows":
		return PackedStringArray(["stockfish.exe"])
	return PackedStringArray(["stockfish", "libstockfish.so"])

func _engine_binary_names() -> PackedStringArray:
	if is_lc0_profile():
		if OS.has_feature("android"):
			return PackedStringArray(["lc0"])
		if OS.get_name() == "Windows":
			return PackedStringArray(["lc0.exe"])
		return PackedStringArray(["lc0"])
	return _stockfish_binary_names()

func _custom_engine_path() -> String:
	var key := "lc0_path" if is_lc0_profile() else "engine_path"
	return SettingsManager.get_setting(key, "")

func _find_binary_path(names: PackedStringArray, custom_key: String) -> String:
	# 1. Vérifier si un chemin personnalisé est configuré
	var custom_path = SettingsManager.get_setting(custom_key, "")
	if custom_path != "" and FileAccess.file_exists(custom_path):
		return custom_path

	# 1bis. Android : privilégier une copie exécutable déjà présente dans user://engines
	# (issue d'une auto-réparation ou d'un téléchargement), puis la lib native embarquée dans
	# l'APK (libstockfish.so en jniLibs, extraite par l'installeur dans nativeLibraryDir).
	if OS.has_feature("android"):
		for n in names:
			var user_engine = OS.get_user_data_dir() + "/engines/" + n
			if FileAccess.file_exists(user_engine):
				return user_engine
		for dir in _android_engine_dirs():
			var native_engine := _find_engine_file_in_dir(dir, names)
			if native_engine != "":
				# Défensif : restaure les droits d'exécution si un OEM les a retirés (no-op en lecture seule).
				_make_executable(native_engine)
				return native_engine

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
	if not OS.has_feature("android"):
		var dev_path = "c:/Dev/RodChessXD/bin/" + names[0]
		if FileAccess.file_exists(dev_path):
			return dev_path

	return ""

func _get_engine_executable_path() -> String:
	return _find_binary_path(_engine_binary_names(), _custom_engine_path())

## Répertoires candidats contenant le moteur natif embarqué dans l'APK (Android uniquement).
func _android_engine_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	# Répertoire réel des bibliothèques natives (nativeLibraryDir), localisé via /proc/self/maps.
	# OS.get_executable_path() est inutilisable ici : sur Android il retourne le chemin du
	# processus hôte (ex. /system/bin/app_process64), pas celui des libs de l'APK.
	var native_dir := _android_native_lib_dir()
	if native_dir != "":
		dirs.append(native_dir)
	# Repli : voisinage de l'exécutable (éditeur Android, exports exotiques).
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir != "" and not dirs.has(exe_dir):
		dirs.append(exe_dir)
		dirs.append(exe_dir.path_join("lib/arm64-v8a"))
	return dirs

func _android_native_lib_dir() -> String:
	var f := FileAccess.open("/proc/self/maps", FileAccess.READ)
	if f == null:
		print("EngineManager: /proc/self/maps illisible via FileAccess (open null).")
		return ""
	var maps := f.get_as_text()
	f.close()
	if maps.is_empty():
		print("EngineManager: /proc/self/maps lu mais VIDE (taille 0 via le backend fichiers JAndroid).")
		return ""
	var dir := _native_lib_dir_from_maps(maps)
	if dir == "":
		var marker_lines := 0
		for line in maps.split("\n", false):
			if line.find("libgodot_android.so") != -1 or line.find("libc++_shared.so") != -1:
				marker_lines += 1
		print("EngineManager: native dir non résolu dans /proc/self/maps (lignes marqueur=%d). Extrait maps: %s" % [marker_lines, maps.substr(0, 400)])
	return dir

## Extrait le répertoire des bibliothèques natives depuis le contenu de /proc/self/maps,
## en repérant libgodot_android.so (toujours chargée, extraite dans nativeLibraryDir).
## Fonction pure : testable hors Android.
static func _native_lib_dir_from_maps(maps: String) -> String:
	for line in maps.split("\n", false):
		if line.find("libgodot_android.so") == -1 and line.find("libc++_shared.so") == -1:
			continue
		var slash := line.find("/")
		if slash == -1:
			continue
		var path := line.substr(slash).strip_edges()
		# Chemin de la forme "base.apk!lib/arm64-v8a/..." = lib mappée depuis l'APK
		# (extractNativeLibs=false) : aucun fichier exécutable n'existe sur le disque.
		if path == "" or path.contains("!"):
			continue
		return path.get_base_dir()
	return ""

func _extract_engine_to_user_dir(name: String) -> String:
	var src = "res://bin/" + name
	var dst = OS.get_user_data_dir() + "/engines/" + name
	if not _copy_file_bytes(src, dst):
		return ""
	_make_executable(dst)
	return dst if FileAccess.file_exists(dst) else ""

## Copie un fichier en blocs de 1 Mo. Fonctionne pour res:// (assets Android/PCK) comme pour les
## chemins absolus du système de fichiers. Retourne true si la totalité a été copiée.
func _copy_file_bytes(src_path: String, dst_path: String) -> bool:
	var src_file = FileAccess.open(src_path, FileAccess.READ)
	if src_file == null:
		return false
	var dst_file = FileAccess.open(dst_path, FileAccess.WRITE)
	if dst_file == null:
		src_file.close()
		return false
	while not src_file.eof_reached():
		var chunk = src_file.get_buffer(1 << 20)
		dst_file.store_buffer(chunk)
	src_file.close()
	dst_file.close()
	return FileAccess.file_exists(dst_path)

## Vérification rapide : le fichier doit commencer par la magie ELF et être une classe 64 bits.
## Évite de lancer (et de faire échouer) un fichier vide, tronqué ou d'un mauvais type.
func _is_elf_binary(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var head := f.get_buffer(6)
	f.close()
	return head.size() == 6 \
		and head[0] == 0x7f and head[1] == 0x45 and head[2] == 0x4c and head[3] == 0x46 \
		and head[4] == 2

## Retourne e_machine du binaire ELF (offset 18, little-endian). -1 si illisible.
func _elf_machine(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	f.seek(18)
	var b := f.get_buffer(2)
	f.close()
	if b.size() != 2:
		return -1
	return int(b[0]) | (int(b[1]) << 8)

## e_machine attendu pour l'ABI Android courante (183=AArch64, 62=x86_64, 3=i386, 40=ARM).
func _expected_elf_machine() -> int:
	if OS.has_feature("x86_64"):
		return 62
	if OS.has_feature("arm64-v8a") or OS.has_feature("arm64"):
		return 183
	if OS.has_feature("x86"):
		return 3
	if OS.has_feature("armeabi-v7a") or OS.has_feature("armeabi"):
		return 40
	return -1

## Libellé lisible d'un e_machine ELF pour les messages d'erreur.
func _elf_machine_label(machine: int) -> String:
	match machine:
		183:
			return "arm64 (AArch64)"
		62:
			return "x86_64"
		3:
			return "x86 (32 bits)"
		40:
			return "ARM (32 bits)"
		_:
			return "architecture %d" % machine

## Cherche un moteur dans un répertoire : d'abord les noms exacts, puis tout fichier dont le nom
## commence par "stockfish"/"libstockfish" (tolère les variantes comme libstockfish.so.19).
func _find_engine_file_in_dir(dir_path: String, names: PackedStringArray) -> String:
	if dir_path == "":
		return ""
	for n in names:
		var candidate := dir_path.path_join(n)
		if FileAccess.file_exists(candidate):
			return candidate
	var da := DirAccess.open(dir_path)
	if da == null:
		return ""
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir() and (entry.begins_with("stockfish") or entry.begins_with("libstockfish")):
			da.list_dir_end()
			var found := dir_path.path_join(entry)
			if FileAccess.file_exists(found):
				return found
		entry = da.get_next()
	da.list_dir_end()
	return ""

## Auto-réparation Android : si l'exécution échoue depuis le nativeLibraryDir (droits, OEM,
## SELinux...), copie le binaire vers user://engines où l'exécution d'un fichier applicatif est
## toujours autorisée, lui applique chmod 755 et mémorise ce chemin pour les lancements suivants.
func _recover_engine_to_user_dir(src_path: String) -> String:
	var names := _engine_binary_names()
	var base_name := src_path.get_file()
	var is_engine_name := base_name.begins_with("stockfish") or base_name.begins_with("libstockfish") \
		or base_name.begins_with("lc0")
	if not is_engine_name:
		base_name = names[0]
	var engines_dir := OS.get_user_data_dir() + "/engines"
	var dst_path := engines_dir + "/" + base_name
	if not _copy_file_bytes(src_path, dst_path):
		print("EngineManager: Échec de la copie de récupération ", src_path, " -> ", dst_path)
		return ""
	_make_executable(dst_path)
	if not FileAccess.file_exists(dst_path):
		return ""
	var key := "lc0_path" if is_lc0_profile() else "engine_path"
	SettingsManager.set_setting(key, dst_path)
	return dst_path

## Diagnostic Android : liste les noms de moteur présents dans res://bin/ (assets de l'APK).
func _android_res_bin_candidates() -> String:
	var present := PackedStringArray()
	for n in _stockfish_binary_names():
		if FileAccess.file_exists("res://bin/" + n):
			present.append(n)
	return "[%s]" % ", ".join(present)

## Convertit un chemin absolu situé dans le répertoire de données de l'app en chemin "user://".
## Nécessaire pour chmod : Godot route les chemins "user://" vers FileAccessUnix (qui implémente
## chmod), tandis qu'un chemin absolu /data/... passe par le backend fichiers JAndroid qui ne le fait pas.
func _user_scheme_path(p_path: String) -> String:
	var ud := OS.get_user_data_dir()
	if p_path.begins_with(ud):
		return "user://" + p_path.substr(ud.length()).trim_prefix("/")
	return p_path

## Donne les droits d'exécution (rwxr-xr-x) à un binaire extrait/téléchargé (no-op sous Windows).
func _make_executable(path: String) -> void:
	if OS.get_name() == "Windows" or not FileAccess.file_exists(path):
		return
	const PERMS_755: int = FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER \
		| FileAccess.UNIX_READ_GROUP | FileAccess.UNIX_EXECUTE_GROUP \
		| FileAccess.UNIX_READ_OTHER | FileAccess.UNIX_EXECUTE_OTHER
	var chmod_path := _user_scheme_path(path)
	var err := FileAccess.set_unix_permissions(chmod_path, PERMS_755)
	if err != OK:
		print("EngineManager: chmod impossible sur ", chmod_path, " (err=", err, ")")

func is_engine_available() -> bool:
	state_mutex.lock()
	var running = is_engine_running
	state_mutex.unlock()
	return running

func has_engine_binary() -> bool:
	if OS.has_feature("web"):
		return true
	if _current_engine_path != "" and FileAccess.file_exists(_current_engine_path):
		return true
	if OS.has_feature("android") and Engine.has_singleton("RodChessUci"):
		var p = _plugin_handle if _plugin_handle != null else Engine.get_singleton("RodChessUci")
		if p != null:
			var native_dir := str(p.getNativeLibraryDir())
			if native_dir != "" and FileAccess.file_exists(native_dir.path_join("libstockfish.so")):
				return true
	return _find_binary_path(_stockfish_binary_names(), "engine_path") != ""

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

func get_stockfish_download_available() -> bool:
	# Le binaire officiel téléchargeable est arm64 : ne le proposer que sur un appareil arm64.
	return OS.has_feature("android") and OS.has_feature("arm64-v8a")

func is_stockfish_download_active() -> bool:
	return _installing_engine and _install_kind == "stockfish"

func install_stockfish_engine() -> bool:
	if is_engine_available():
		return false
	if not get_stockfish_download_available():
		engine_error.emit("Téléchargement de Stockfish non disponible sur cette plateforme.")
		return false
	if _installing_engine:
		return true

	_install_kind = "stockfish"
	_install_display = "Stockfish 19 (Android)"
	_install_cache_path = OS.get_user_data_dir() + "/engines/stockfish-android-arm64-universal.tar.gz"
	_install_inner_match = "stockfish-android-arm64-universal"
	_install_target_name = "stockfish"
	return _start_engine_download(STOCKFISH_RELEASE_URL)

func get_lc0_download_available() -> bool:
	return not is_lc0_binary_present() and not OS.has_feature("android") and OS.get_name() == "Windows"

func is_lc0_download_active() -> bool:
	return _installing_engine and _install_kind == "lc0_win"

func install_lc0_engine() -> bool:
	if is_lc0_binary_present():
		return false
	if not get_lc0_download_available():
		engine_error.emit("Le téléchargement de lc0 n'est proposé que sur Windows de bureau.")
		return false
	if _installing_engine:
		return true

	_install_kind = "lc0_win"
	_install_display = "lc0 (Windows CPU)"
	_install_cache_path = OS.get_user_data_dir() + "/engines/lc0-windows.zip"
	_install_inner_match = ""
	_install_target_name = ""
	return _start_engine_download(LC0_WINDOWS_RELEASE_URL)

func _start_engine_download(url: String) -> bool:
	_installing_engine = true
	_install_last_bytes = 0
	set_process(true)
	install_http.download_file = _install_cache_path
	var err = install_http.request(url)
	if err != OK:
		_installing_engine = false
		install_http.download_file = ""
		_cleanup_install_cache()
		engine_error.emit("Impossible de lancer le téléchargement de %s (%d)." % [_install_display, err])
		return false
	download_progress.emit(_install_display, 0.0)
	print("EngineManager: Téléchargement de ", _install_display, " en cours...")
	return true

func _on_engine_install_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	install_http.download_file = ""
	var display = _install_display
	var kind = _install_kind
	if not _installing_engine:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_installing_engine = false
		_cleanup_install_cache()
		var msg = "Échec du téléchargement de %s (HTTP %d)." % [display, response_code]
		print("EngineManager: ", msg)
		engine_error.emit(msg)
		download_failed.emit(display, msg)
		return

	var installed := false
	if kind == "lc0_win":
		installed = _extract_lc0_windows_zip(_install_cache_path)
	else:
		var out = OS.get_user_data_dir() + "/engines/" + _install_target_name
		installed = _extract_tar_gz_engine(_install_cache_path, out, _install_inner_match) != ""
	_cleanup_install_cache()
	_installing_engine = false
	if not installed:
		var msg = "Extraction de %s impossible (archive invalide)." % display
		print("EngineManager: ", msg)
		engine_error.emit(msg)
		download_failed.emit(display, msg)
		return
	print("EngineManager: ", display, " installé.")
	if kind != "lc0_win":
		var installed_path = OS.get_user_data_dir() + "/engines/" + _install_target_name
		_make_executable(installed_path)
		print("EngineManager: Droits d'exécution appliqués sur ", installed_path)
	download_completed.emit(display)
	start_engine()

func _extract_lc0_windows_zip(zip_path: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var wanted := {
		"lc0.exe": true,
		"dnnl.dll": true,
		"mimalloc-override.dll": true,
		"mimalloc-redirect.dll": true
	}
	var ok := false
	for entry in reader.get_files():
		if reader.file_exists(entry):
			var name := entry.get_file()
			if not wanted.has(name):
				continue
			var data := reader.read_file(entry)
			if data.size() == 0:
				continue
			var f := FileAccess.open(OS.get_user_data_dir() + "/engines/" + name, FileAccess.WRITE)
			if f == null:
				continue
			f.store_buffer(data)
			f.close()
			ok = true
	reader.close()
	return ok

func _cleanup_install_cache() -> void:
	if _install_cache_path != "" and FileAccess.file_exists(_install_cache_path):
		DirAccess.remove_absolute(_install_cache_path)
	_install_cache_path = ""

func _gunzip_bytes(data: PackedByteArray) -> PackedByteArray:
	if data.size() < 8:
		return PackedByteArray()
	var out_size := int(data.decode_u32(data.size() - 4))
	if out_size <= 0:
		return PackedByteArray()
	return data.decompress(out_size, 3)

func _parse_octal_ascii(bytes: PackedByteArray) -> int:
	var value := 0
	for i in bytes.size():
		var b := int(bytes[i])
		if b >= 48 and b <= 55:
			value = (value * 8) + (b - 48)
		elif b == 0 or b == 32:
			continue
		else:
			break
	return value

func _extract_tar_gz_engine(gz_path: String, out_path: String, inner_match: String) -> String:
	var gz := FileAccess.get_file_as_bytes(gz_path)
	if gz.is_empty():
		return ""
	var tar := _gunzip_bytes(gz)
	if tar.is_empty():
		return ""
	var pos := 0
	while pos + 512 <= tar.size():
		var header := tar.slice(pos, pos + 512)
		var name_bytes := header.slice(0, 100)
		var nul := -1
		for b in name_bytes.size():
			if int(name_bytes[b]) == 0:
				nul = b
				break
		if nul == -1:
			nul = name_bytes.size()
		var name := name_bytes.slice(0, nul).get_string_from_ascii()
		if name.is_empty():
			break
		var typeflag := int(header[156])
		var size := _parse_octal_ascii(header.slice(124, 136))
		var data_start := pos + 512
		var padded := (size + 511) & ~511
		var is_regular := typeflag == 0 or typeflag == 48 or typeflag == 55 or typeflag == 49
		if is_regular and (inner_match == "" or name.find(inner_match) != -1):
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			if f == null:
				return ""
			var written := 0
			while written < size:
				var chunk_size := mini(1 << 20, size - written)
				f.store_buffer(tar.slice(data_start + written, data_start + written + chunk_size))
				written += chunk_size
			f.close()
			# Android : un fichier écrit via FileAccess n'est pas exécutable par défaut.
			_make_executable(out_path)
			return out_path
		pos = data_start + padded
	return ""

func _engine_display_name() -> String:
	if is_lc0_profile():
		return "lc0 + Maia (%s)" % get_maia_net_filename()
	return "Stockfish"

func _engine_missing_hint() -> String:
	if is_lc0_profile():
		return "Placez un binaire lc0 (\"lc0\" ou \"lc0.exe\") dans user://engines/ ou res://bin/."
	if OS.has_feature("android"):
		return "Aucun binaire moteur pour cet appareil (%s) dans le nativeLibraryDir de l'APK, user://engines/ ni res://bin/. Réinstallez l'APK (extraction native) ou utilisez l'Engine Hub." % ("arm64" if _expected_elf_machine() == 183 else "x86_64")
	return "Placez \"stockfish.exe\" dans bin/ ou user://engines/."

func start_engine() -> bool:
	_is_intentionally_stopping = false
	set_process(true)
	if is_engine_running:
		return true
	if _booting:
		return false

	if OS.has_feature("web"):
		return _start_wasm_engine()

	var is_lc0 = is_lc0_profile()
	var exe_path = _get_engine_executable_path()
	_current_engine_path = exe_path
	# Sur Android, le moteur embarqué dans nativeLibraryDir est la source la plus fiable
	# (exécutable par le domaine SELinux de l'app). Il sert de repli même quand la découverte
	# par /proc/self/maps échoue.
	var is_native_lib_engine := false
	if OS.has_feature("android") and Engine.has_singleton("RodChessUci"):
		if _plugin_handle == null:
			_plugin_handle = Engine.get_singleton("RodChessUci")
			_connect_plugin_signals()
		var native_dir := ""
		if _plugin_handle != null and not is_lc0:
			# has_method() ne reflète pas les méthodes des singletons de plugin : appel direct.
			native_dir = str(_plugin_handle.getNativeLibraryDir())
		print("EngineManager: repli native — singleton=", _plugin_handle != null, " nativeDir='", native_dir, "'")
		if native_dir != "":
			var native_candidate := native_dir.path_join("libstockfish.so")
			if exe_path == "":
				exe_path = native_candidate
				is_native_lib_engine = true
			elif FileAccess.file_exists(native_candidate):
				exe_path = native_candidate
				is_native_lib_engine = true
	_current_engine_path = exe_path
	if exe_path == "":
		var hint = _engine_missing_hint()
		if OS.has_feature("android"):
			# Diagnostic : affiche où la recherche a échoué pour faciliter le dépannage sur appareil.
			print("EngineManager: Aucun exécutable de moteur trouvé. nativeLibraryDir='", _android_native_lib_dir(), "' user='", OS.get_user_data_dir(), "/engines' res://bin='", _android_res_bin_candidates(), "'")
		print("EngineManager: Aucun exécutable de moteur trouvé. ", hint)
		engine_error.emit("Moteur d'échecs non trouvé. %s" % hint)
		return false

	var launch_args: PackedStringArray = []
	if is_lc0:
		var net_path = get_active_maia_net_path()
		if net_path == "":
			var msg = "Réseau Maia introuvable. Téléchargez d'abord le réseau %s dans l'Engine Hub." % get_maia_net_filename()
			engine_error.emit(msg)
			return false
		launch_args.append("--threads=%d" % SettingsManager.get_setting("engine_threads", 2))
		launch_args.append("--weights=" + net_path)

	if OS.has_feature("android") and not is_native_lib_engine:
		# Répare un binaire resté sans droit d'exécution (issu d'une version antérieure de l'app).
		_make_executable(exe_path)
		if not _is_elf_binary(exe_path):
			var bad_msg = "Le moteur trouvé (%s) n'est pas un binaire ELF 64 bits valide. Binaire endommagé ou mauvais type embarqué." % exe_path
			print("EngineManager: ", bad_msg)
			engine_error.emit(bad_msg)
			return false
		var expected := _expected_elf_machine()
		var machine := _elf_machine(exe_path)
		if expected != -1 and machine != -1 and machine != expected:
			var arch_label := _elf_machine_label(expected)
			var wrong_label := _elf_machine_label(machine)
			# Nettoie un éventuel binaire téléchargé pour une autre architecture (ex: arm64 sur émulateur x86_64).
			if exe_path.begins_with(OS.get_user_data_dir()):
				DirAccess.remove_absolute(exe_path)
				print("EngineManager: Binaire ", wrong_label, " incompatible (", exe_path, ") supprimé de user://engines.")
			var arch_msg = "Le moteur est un binaire %s, mais cet appareil exécute %s. Pour l'émulateur x86_64, seul un Stockfish compilé pour Android x86_64 fonctionnerait ; sur téléphone arm64 utilisez la version arm64." % [wrong_label, arch_label]
			print("EngineManager: ", arch_msg)
			engine_error.emit(arch_msg)
			return false

	print("EngineManager: Lancement de ", _engine_display_name(), " depuis ", exe_path)

	# Transport privilégié sur Android : plugin natif "RodChessUci" (ProcessBuilder / posix_spawn).
	# OS.execute_with_pipe repose sur un fork() non fiable depuis le processus Godot multi-threadé
	# (enfant zombie avant exec, aucune sortie lue) — le plugin contourne ce problème.
	_use_plugin = false
	if OS.has_feature("android") and Engine.has_singleton("RodChessUci"):
		_plugin_handle = Engine.get_singleton("RodChessUci")
		_connect_plugin_signals()
		# Priorité au moteur embarqué dans nativeLibraryDir : extrait par l'installeur, il est
		# exécutable par le domaine SELinux de l'app (les fichiers de user://engines ne le sont
		# pas sur certains ROM/versions → EACCES).
		var launch_path: String = exe_path
		var plugin_started := bool(_plugin_handle.startEngine(launch_path, launch_args))
		if not plugin_started and not is_native_lib_engine:
			var native_dir := str(_plugin_handle.getNativeLibraryDir())
			if native_dir != "":
				var native_candidate := native_dir.path_join("libstockfish.so")
				print("EngineManager: repli nativeLibraryDir: ", native_candidate)
				if bool(_plugin_handle.startEngine(native_candidate, launch_args)):
					launch_path = native_candidate
					_current_engine_path = native_candidate
					plugin_started = true
		if not plugin_started:
			engine_error.emit("Impossible de démarrer le moteur UCI via le plugin Android (%s)." % launch_path)
			return false
		_use_plugin = true
		should_stop_thread = false
		process_pipe = {}
		print("EngineManager: moteur lancé via le plugin Android RodChessUci (", launch_path, ").")

	if not _use_plugin:
		# Utilisation de OS.execute_with_pipe pour communication bidirectionnelle (bureau, et
		# repli Android si le plugin est absent). blocking=false : pipes non bloquants.
		process_pipe = OS.execute_with_pipe(exe_path, launch_args, false)

		# Auto-réparation Android : si l'exécution échoue depuis le nativeLibraryDir, on copie le
		# binaire dans user://engines (chmod 755) et on relance depuis cette copie privée exécutable.
		if (process_pipe.is_empty() or not process_pipe.has("stdio")) and OS.has_feature("android") \
				and not exe_path.begins_with(OS.get_user_data_dir()):
			print("EngineManager: Échec d'exécution depuis ", exe_path, " — tentative de récupération vers user://engines.")
			var recovered := _recover_engine_to_user_dir(exe_path)
			if recovered != "":
				print("EngineManager: Moteur relancé depuis la copie privée ", recovered)
				exe_path = recovered
				_current_engine_path = recovered
				process_pipe = OS.execute_with_pipe(exe_path, launch_args, false)

		if process_pipe.is_empty() or not process_pipe.has("stdio"):
			var exec_hint = " Vérifiez que le binaire est un exécutable arm64 valide pour Android." if OS.has_feature("android") else " Vérifiez le chemin du moteur."
			print("EngineManager: Échec d'exécution du sous-processus moteur (", exe_path, ").", exec_hint)
			engine_error.emit("Impossible de démarrer le moteur UCI (%s).%s" % [exe_path, exec_hint])
			return false

	state_mutex.lock()
	is_engine_running = true
	_handshake_ready = false
	_pending_live_fen = ""
	_engine_ready_emitted = false
	state_mutex.unlock()
	_received_any_output = false
	_log_first_raw_line = true
	_started_msec = Time.get_ticks_msec()
	if _use_plugin:
		print("EngineManager: en attente de la sortie UCI (plugin).")
	else:
		print("EngineManager: pid=", process_pipe.get("pid", -1), " en attente de la sortie UCI.")

		# Démarrage du thread de lecture des réponses UCI
		should_stop_thread = false
		engine_thread = Thread.new()
		engine_thread.start(_engine_reader_loop)

	# Initialisation UCI
	send_command("uci")
	if not is_lc0:
		send_command("setoption name Threads value %d" % SettingsManager.get_setting("engine_threads", SettingsManager.get_default_engine_threads()))
		send_command("setoption name Hash value %d" % SettingsManager.get_setting("engine_hash_mb", SettingsManager.get_default_engine_hash()))
		send_command("setoption name UCI_AnalyseMode value true")
		_multipv_requested = default_multipv()
		send_command("setoption name MultiPV value %d" % _multipv_requested)
	send_command("isready")
	send_command("ucinewgame")

	return true

func set_engine_profile(profile_id: String, maia_filename: String = "") -> bool:
	if profile_id != "stockfish" and profile_id != "maia_lc0":
		return false
	if profile_id == "maia_lc0":
		if maia_filename == "" or not MAIA_NET_FILES.has(maia_filename):
			maia_filename = get_maia_net_filename()
		SettingsManager.set_setting("maia_net", maia_filename)
	SettingsManager.set_setting("engine_profile", profile_id)
	if is_engine_running:
		stop_engine()
	clear_eval_cache()
	engine_profile_changed.emit(profile_id)
	return start_engine()

## Redémarre proprement le moteur pour appliquer les modifications de configuration
func restart_engine() -> bool:
	clear_eval_cache()
	if is_engine_running:
		stop_engine()
	return start_engine()

## Applique les paramètres modifiés et relance l'évaluation sur la position courante
func apply_engine_settings() -> void:
	if is_engine_running:
		restart_engine()
	else:
		start_engine()
	var tree = Engine.get_main_loop() as SceneTree
	if tree and tree.root and tree.root.has_node("GameController"):
		var gc = tree.root.get_node("GameController")
		if gc and gc.game:
			evaluate_position(gc.game.get_fen())

func is_engine_profile_active(profile_id: String) -> bool:
	return get_engine_profile() == profile_id

func get_engine_display_name() -> String:
	return _engine_display_name()

## MultiPV par défaut : 1 sur toutes les plateformes pour réactivité maximale (x3 plus rapide que 3 lignes).
func default_multipv() -> int:
	var fallback := 1
	var n := int(SettingsManager.get_setting("engine_multipv", fallback))
	return clampi(n, 1, 5)

## Demande au moteur d'analyser N lignes. `reset` vide les lignes accumulées.
func set_multipv(n: int, reset: bool = true) -> void:
	var value := clampi(n, 1, 5)
	if value == _multipv_requested and not reset:
		return
	_multipv_requested = value
	if is_engine_running:
		send_command("setoption name MultiPV value %d" % value)
	if reset:
		state_mutex.lock()
		multipv_lines = []
		_multipv_accum = {}
		state_mutex.unlock()

## Réinitialise les accumulateurs d'évaluation (MultiPV, mate) pour une nouvelle position.
func _reset_eval_accumulators() -> void:
	multipv_lines = []
	_multipv_accum = {}
	eval_depth = 0
	eval_score_cp = 0
	eval_mate_in = 0
	best_move_uci = ""
	pv_line.clear()

func send_command(cmd: String) -> void:
	if not is_engine_running:
		return
	if _use_wasm:
		if ClassDB.class_exists("JavaScriptBridge"):
			var js_cmd := cmd.c_escape()
			JavaScriptBridge.eval("if (window.RodChessUci) { window.RodChessUci.sendCommand(\"%s\"); }" % js_cmd)
		return
	if _use_plugin and _plugin_handle != null:
		_plugin_handle.sendCommand(cmd)
		return
	if not process_pipe.has("stdio"):
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
	# Correctif démarrage Live : différer tant que la poignée de main UCI n'est pas finie.
	state_mutex.lock()
	var handshake_ok := _handshake_ready
	if not handshake_ok:
		_pending_live_fen = fen
	state_mutex.unlock()
	if not handshake_ok:
		return
	# Une analyse complète Web possède le worker UCI de façon exclusive. Les
	# requêtes Live différées (navigation, réglages, modales) sont ignorées jusqu'à
	# la fin de la session au lieu d'interrompre son calcul courant.
	if _async_analysis_session_active:
		return
	
	if depth <= 0:
		var default_depth = 12 if (OS.has_feature("android") or OS.has_feature("ios")) else 16
		depth = SettingsManager.get_setting("engine_depth", default_depth)

	# Réponse instantanée si la position est déjà en cache (0 ms)
	var cached := get_cached_eval(fen, depth, _multipv_requested)
	if not cached.is_empty():
		state_mutex.lock()
		var was_eval = is_evaluating
		_evaluation_generation += 1
		current_fen = fen
		is_evaluating = false
		best_move_uci = str(cached.get("best_move", ""))
		eval_depth = int(cached.get("depth", depth))
		eval_score_cp = int(cached.get("score_cp", 0))
		eval_mate_in = int(cached.get("mate_in", 0))
		pv_line.clear()
		for p in cached.get("pv_line", []):
			pv_line.append(str(p))
		multipv_lines.clear()
		for line_dict in cached.get("multipv_lines", []):
			if line_dict is Dictionary:
				multipv_lines.append(line_dict)
		if multipv_lines.is_empty() and best_move_uci != "":
			multipv_lines.append({
				"rank": 1,
				"depth": eval_depth,
				"score_cp": eval_score_cp,
				"mate_in": eval_mate_in,
				"best_move": best_move_uci,
				"fen": fen,
				"pv": pv_line.duplicate()
			})
		if was_eval:
			_ignore_next_bestmove = true
		var gen := _evaluation_generation
		state_mutex.unlock()
		if was_eval:
			send_command("stop")
		var emit_args = [eval_score_cp, eval_mate_in, eval_depth, best_move_uci, pv_line, multipv_lines.duplicate(true), gen]
		_emit_evaluation_deferred.call_deferred(emit_args)
		_emit_evaluation_finished_deferred.call_deferred(best_move_uci, eval_score_cp, eval_depth)
		return

	state_mutex.lock()
	if current_fen == fen and is_evaluating:
		state_mutex.unlock()
		return
	var was_evaluating = is_evaluating
	_evaluation_generation += 1
	current_fen = fen
	is_evaluating = true
	_last_eval_emit_ms = 0
	_last_emitted_depth = 0
	_reset_eval_accumulators()
	if was_evaluating:
		_ignore_next_bestmove = true
	state_mutex.unlock()

	if was_evaluating:
		send_command("stop")
	send_command("position fen " + fen)
	send_command("go depth %d" % depth)

func stop_evaluation() -> void:
	state_mutex.lock()
	var must_stop = is_evaluating
	if must_stop:
		is_evaluating = false
		current_fen = ""
		_stop_pending = true
		_ignore_next_bestmove = false
		_evaluation_generation += 1
	state_mutex.unlock()
	if must_stop:
		send_command("stop")

func interrupt_evaluation() -> void:
	state_mutex.lock()
	var must_stop = is_evaluating
	cancel_eval_requested = true
	is_evaluating = false
	current_fen = ""
	if must_stop:
		_stop_pending = true
		_ignore_next_bestmove = false
		_evaluation_generation += 1
	state_mutex.unlock()
	if must_stop:
		send_command("stop")

## Attend le `bestmove` qui clôt réellement un `stop`, sans bloquer le rendu.
func _wait_for_evaluation_stop_async(timeout_ms: int = 2000) -> bool:
	var tree = Engine.get_main_loop() as SceneTree
	var started_at = Time.get_ticks_msec()
	while true:
		state_mutex.lock()
		var is_stopping = _stop_pending
		state_mutex.unlock()
		if not is_stopping:
			return true
		if Time.get_ticks_msec() - started_at >= timeout_ms:
			return false
		if tree:
			await tree.process_frame
		else:
			OS.delay_msec(10)
	return false

func _wait_for_readyok_async(previous_serial: int, timeout_ms: int = 2000) -> bool:
	var tree = Engine.get_main_loop() as SceneTree
	var started_at = Time.get_ticks_msec()
	while true:
		state_mutex.lock()
		var has_readyok = _readyok_serial > previous_serial
		state_mutex.unlock()
		if has_readyok:
			return true
		if Time.get_ticks_msec() - started_at >= timeout_ms:
			return false
		if tree:
			await tree.process_frame
		else:
			OS.delay_msec(10)
	return false

## Prépare une analyse Web isolée : plus aucun Live en transit et hash UCI neuve.
func prepare_for_async_analysis(timeout_ms: int = 2000) -> bool:
	if not is_engine_available() or not _engine_io_available():
		return false
	_async_analysis_session_active = true
	if is_evaluating:
		stop_evaluation()
	if not await _wait_for_evaluation_stop_async(timeout_ms):
		_async_analysis_session_active = false
		return false

	state_mutex.lock()
	_evaluation_generation += 1
	current_fen = ""
	var ready_serial = _readyok_serial
	state_mutex.unlock()
	send_command("ucinewgame")
	send_command("isready")
	var is_ready = await _wait_for_readyok_async(ready_serial, timeout_ms)
	if not is_ready:
		_async_analysis_session_active = false
	return is_ready

func finish_async_analysis_session() -> void:
	_async_analysis_session_active = false

## Vrai si un canal de communication moteur est disponible (plugin Android, Wasm Web OU pipe OS.execute).
func _engine_io_available() -> bool:
	if _use_wasm:
		return is_engine_running
	if _use_plugin and _plugin_handle != null:
		return bool(_plugin_handle.isEngineRunning())
	return process_pipe.has("stdio")

## Évaluation asynchrone non-bloquante avec await (idéale pour Web / WASM et UI fluide sans thread)
func evaluate_position_async(fen: String, depth: int = 10, timeout_ms: int = 1500, movetime_ms: int = -1) -> Dictionary:
	if not is_engine_available() or not _engine_io_available():
		return {"score_cp": 0, "best_move": "", "depth": 0, "timed_out": false, "error": "engine_unavailable"}

	# Vérification du cache instantané (0 ms)
	var req_mpv := 1 if movetime_ms > 0 else _multipv_requested
	var cached := get_cached_eval(fen, depth, req_mpv)
	if not cached.is_empty():
		return cached

	if movetime_ms > 0:
		timeout_ms = maxi(timeout_ms, movetime_ms + 600)

	var tree = Engine.get_main_loop() as SceneTree

	# Si une évaluation était déjà en cours, on l'interrompt et on attend son
	# `bestmove` : ne jamais envoyer une position au milieu d'un `stop` UCI.
	if is_evaluating:
		stop_evaluation()
	if not await _wait_for_evaluation_stop_async(timeout_ms):
		return {"score_cp": 0, "best_move": "", "depth": 0, "timed_out": false, "error": "engine_stop_timeout"}

	state_mutex.lock()
	_evaluation_generation += 1
	current_fen = fen
	is_evaluating = true
	best_move_uci = ""
	eval_depth = 0
	eval_score_cp = 0
	cancel_eval_requested = false
	_reset_eval_accumulators()
	state_mutex.unlock()

	send_command("position fen " + fen)
	if movetime_ms > 0 and depth > 0:
		send_command("go depth %d movetime %d" % [depth, movetime_ms])
	elif movetime_ms > 0:
		send_command("go movetime %d" % movetime_ms)
	else:
		send_command("go depth %d" % depth)

	var start_t = Time.get_ticks_msec()
	var cancelled := false
	var timed_out := false

	while is_evaluating:
		if cancel_eval_requested:
			cancelled = true
			break
		if Time.get_ticks_msec() - start_t >= timeout_ms:
			timed_out = true
			break
		if tree:
			await tree.process_frame
		else:
			OS.delay_msec(10)

	if cancelled:
		state_mutex.lock()
		is_evaluating = false
		cancel_eval_requested = false
		state_mutex.unlock()
	elif timed_out:
		stop_evaluation()
		await _wait_for_evaluation_stop_async(600)

	state_mutex.lock()
	var result = {
		"score_cp": eval_score_cp,
		"mate_in": eval_mate_in,
		"best_move": best_move_uci,
		"depth": eval_depth,
		"timed_out": timed_out,
		"cancelled": cancelled,
		"pv_line": pv_line.duplicate(),
		"multipv_lines": multipv_lines.duplicate(true)
	}
	state_mutex.unlock()
	if not timed_out and not cancelled and result.get("depth", 0) >= depth:
		store_cached_eval(fen, result)
	return result

## Évaluation synchrone robuste pour l'analyse globale de partie (GameAnalyzer)
func evaluate_position_sync(fen: String, depth: int = 10, timeout_ms: int = 1500, movetime_ms: int = -1) -> Dictionary:
	if not is_engine_available() or not _engine_io_available():
		return {"score_cp": 0, "best_move": "", "depth": 0, "timed_out": false, "error": "engine_unavailable"}

	# Vérification du cache instantané (0 ms)
	var req_mpv := 1 if movetime_ms > 0 else _multipv_requested
	var cached := get_cached_eval(fen, depth, req_mpv)
	if not cached.is_empty():
		return cached

	if movetime_ms > 0:
		timeout_ms = maxi(timeout_ms, movetime_ms + 600)

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
	eval_score_cp = 0
	cancel_eval_requested = false
	_reset_eval_accumulators()
	state_mutex.unlock()

	send_command("position fen " + fen)
	if movetime_ms > 0 and depth > 0:
		send_command("go depth %d movetime %d" % [depth, movetime_ms])
	elif movetime_ms > 0:
		send_command("go movetime %d" % movetime_ms)
	else:
		send_command("go depth %d" % depth)

	var elapsed = 0
	var cancelled := false
	var timed_out := false
	while is_evaluating and elapsed < timeout_ms:
		if cancel_eval_requested:
			cancelled = true
			break
		OS.delay_msec(15)
		elapsed += 15

	if cancelled:
		state_mutex.lock()
		is_evaluating = false
		cancel_eval_requested = false
		state_mutex.unlock()
	else:
		timed_out = is_evaluating
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
		"mate_in": eval_mate_in,
		"best_move": best_move_uci,
		"depth": eval_depth,
		"timed_out": timed_out,
		"cancelled": cancelled,
		"pv_line": pv_line.duplicate(),
		"multipv_lines": multipv_lines.duplicate(true)
	}
	state_mutex.unlock()
	if not timed_out and not cancelled and result.get("depth", 0) >= depth:
		store_cached_eval(fen, result)
	return result

## Connecte une fois les signaux du plugin Android vers ce script.
func _connect_plugin_signals() -> void:
	if _plugin_handle == null or _plugin_connected:
		return
	if _plugin_handle.has_signal("uci_line"):
		_plugin_handle.connect("uci_line", _on_plugin_uci_line)
		_plugin_handle.connect("uci_err", _on_plugin_uci_err)
		_plugin_handle.connect("engine_exited", _on_plugin_engine_exited)
		_plugin_connected = true

func _on_plugin_uci_line(line: String) -> void:
	if not (_use_plugin and is_engine_running):
		return
	if _log_first_raw_line:
		_log_first_raw_line = false
		print("EngineManager: [brut] ", line.substr(0, 160))
	_parse_engine_line(line)

func _on_plugin_uci_err(line: String) -> void:
	if not (_use_plugin and is_engine_running):
		return
	print("EngineManager: [stderr] ", line.substr(0, 200))

func _on_plugin_engine_exited(exit_code: int) -> void:
	print("EngineManager: [plugin] engine_exited code=%d (intentional=%s, running=%s)" % [exit_code, _is_intentionally_stopping, is_engine_running])
	if _is_intentionally_stopping or exit_code == 0 or exit_code == 143:
		return
	if _use_plugin and is_engine_running and not should_stop_thread:
		call_deferred("_handle_engine_dead", "Le processus moteur s'est arrêté (code %d)." % exit_code)

func _engine_reader_loop() -> void:
	var stdio: FileAccess = process_pipe.get("stdio", null)
	if not stdio:
		return

	# Pipes non bloquants : on lit par blocs et on découpe nous-mêmes sur les '\n'
	# (le get_line() bloquant ne reçoit pas la sortie du sous-processus sur Android).
	var line_buffer := ""
	while not should_stop_thread and is_engine_available():
		if stdio.is_open():
			var chunk := stdio.get_buffer(1 << 12)
			if chunk.size() > 0:
				line_buffer += chunk.get_string_from_utf8()
				while true:
					var nl := line_buffer.find("\n")
					if nl == -1:
						break
					var raw := line_buffer.substr(0, nl)
					line_buffer = line_buffer.substr(nl + 1)
					var line := raw.strip_edges()
					if line != "":
						if _log_first_raw_line:
							_log_first_raw_line = false
							print("EngineManager: [brut] ", line.substr(0, 160))
						_parse_engine_line(line)
			elif stdio.eof_reached():
				if line_buffer.strip_edges() != "":
					var tail := line_buffer.strip_edges()
					if _log_first_raw_line:
						_log_first_raw_line = false
						print("EngineManager: [brut] ", tail.substr(0, 160))
					_parse_engine_line(tail)
				break
			else:
				OS.delay_msec(2)
		else:
			break

	if not should_stop_thread:
		var reason = "Le processus moteur s'est arrêté inopinément (binaire « %s » non exécutable ou arrêté)." % _current_engine_path
		if not _received_any_output:
			reason += " Aucune sortie UCI reçue avant l'arrêt."
		call_deferred("_handle_engine_dead", reason)

func _handle_engine_dead(msg: String) -> void:
	state_mutex.lock()
	if not is_engine_running or should_stop_thread:
		state_mutex.unlock()
		return
	is_engine_running = false
	is_evaluating = false
	state_mutex.unlock()
	print("EngineManager: ", msg)

	# Arrête le processus moteur s'il est encore vivant (transport plugin).
	if _use_plugin and _plugin_handle != null:
		_plugin_handle.stopEngine()

	# Android : si le processus s'est arrêté avant toute sortie UCI, le binaire du nativeLibraryDir
	# n'est probablement pas exécutable sur cet appareil. On tente une auto-réparation en copiant
	# le binaire dans user://engines (chmod 755) avant d'annoncer l'erreur.
	if OS.has_feature("android") and not _received_any_output and not _booting:
		if _try_android_self_heal():
			return

	engine_error.emit(msg)

## Relance le moteur depuis une copie exécutable privée (user://engines) quand le binaire extrait
## dans le nativeLibraryDir ne démarre pas. Retourne true si un redémarrage a été tenté.
func _try_android_self_heal() -> bool:
	var src := _current_engine_path
	if src == "" or src.begins_with(OS.get_user_data_dir()):
		return false
	var recovered := _recover_engine_to_user_dir(src)
	if recovered == "":
		return false
	print("EngineManager: Auto-réparation — copie exécutable créée à ", recovered)
	return start_engine()

func _parse_engine_line(line: String) -> void:
	_received_any_output = true
	# Exemple de ligne : info depth 18 seldepth 22 multipv 1 score cp 45 nodes 84523 pv e2e4 e7e5 ...
	if line.begins_with("info "):
		# Filtrage ultra-rapide : ignorer immédiatement les lignes sans évaluation (currmove, nodes, etc.)
		if not line.contains(" score "):
			return
		var tokens = line.split(" ", false)
		var i = 1
		var depth = 0
		state_mutex.lock()
		if _stop_pending:
			state_mutex.unlock()
			return
		var score_cp = eval_score_cp
		var current_fen_snapshot = current_fen
		var generation = _evaluation_generation
		state_mutex.unlock()
		var mate_in = 0
		var pv: Array[String] = []
		var rank := 1
		var has_score := false

		while i < tokens.size():
			match tokens[i]:
				"multipv":
					if i + 1 < tokens.size():
						rank = maxi(1, tokens[i + 1].to_int())
						i += 1
				"depth":
					if i + 1 < tokens.size():
						depth = tokens[i + 1].to_int()
						i += 1
				"score":
					if i + 2 < tokens.size():
						has_score = true
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
		var normalized_mate = mate_in if white_to_move else -mate_in

		if has_score:
			var line_rec := {
				"rank": rank,
				"depth": depth,
				"score_cp": normalized_cp,
				"mate_in": normalized_mate,
				"best_move": pv[0] if pv.size() > 0 else "",
				"fen": current_fen_snapshot,
				"pv": pv.duplicate()
			}
			state_mutex.lock()
			if _stop_pending or generation != _evaluation_generation:
				state_mutex.unlock()
				return
			_multipv_accum[rank] = line_rec
			var ranks := _multipv_accum.keys()
			ranks.sort()
			var lines: Array[Dictionary] = []
			for r in ranks:
				lines.append(_multipv_accum[r])
			multipv_lines = lines
			if rank == 1:
				eval_depth = maxi(depth, 1 if normalized_mate != 0 else 0)
				eval_score_cp = normalized_cp
				eval_mate_in = normalized_mate
				pv_line = pv
				if pv.size() > 0:
					best_move_uci = pv[0]

			# Throttling de l'émission UI : max ~12 Hz (80 ms) ou progression de profondeur / mat
			var now_ms = Time.get_ticks_msec()
			var should_emit = (normalized_mate != 0) \
					or (eval_depth > _last_emitted_depth) \
					or (now_ms - _last_eval_emit_ms >= 80)

			if should_emit:
				_last_eval_emit_ms = now_ms
				_last_emitted_depth = eval_depth
				var emit_args = [eval_score_cp, eval_mate_in, eval_depth, best_move_uci, pv_line, multipv_lines.duplicate(true), generation]
				state_mutex.unlock()
				_emit_evaluation_deferred.call_deferred(emit_args)
			else:
				state_mutex.unlock()

	elif line.begins_with("bestmove "):
		var parts = line.split(" ", false)
		state_mutex.lock()
		if _stop_pending:
			_stop_pending = false
			is_evaluating = false
			current_fen = ""
			state_mutex.unlock()
			return
		if _ignore_next_bestmove:
			_ignore_next_bestmove = false
			state_mutex.unlock()
			return
		if parts.size() > 1:
			best_move_uci = parts[1]
		# Si bestmove est "(none)", la position est terminale (mat ou pat)
		if best_move_uci == "(none)":
			if eval_score_cp == 0 and eval_mate_in != 0:
				eval_score_cp = 10000 if eval_mate_in > 0 else -10000
		is_evaluating = false
		var b_move = best_move_uci
		var s_cp = eval_score_cp
		var d = eval_depth
		var c_fen = current_fen
		var m_in = eval_mate_in
		var pv_c = pv_line.duplicate()
		var mpv_c = multipv_lines.duplicate(true)
		state_mutex.unlock()
		if c_fen != "" and d > 0 and not pv_c.is_empty():
			if mpv_c.is_empty() and b_move != "":
				mpv_c = [{
					"rank": 1,
					"depth": d,
					"score_cp": s_cp,
					"mate_in": m_in,
					"best_move": b_move,
					"fen": c_fen,
					"pv": pv_c
				}]
			store_cached_eval(c_fen, {
				"score_cp": s_cp,
				"mate_in": m_in,
				"best_move": b_move,
				"depth": d,
				"pv_line": pv_c,
				"multipv_lines": mpv_c,
				"timed_out": false,
				"cancelled": false
			})
		if b_move != "" and d > 0:
			_emit_evaluation_finished_deferred.call_deferred(b_move, s_cp, d)
	elif line == "readyok":
		state_mutex.lock()
		_readyok_serial += 1
		var first_ready := not _handshake_ready
		if first_ready:
			_handshake_ready = true
		state_mutex.unlock()

func _emit_evaluation_finished_deferred(b_move: String, s_cp: int, d: int) -> void:
	evaluation_finished.emit(b_move, s_cp, d)

func _emit_evaluation_deferred(emit_args: Array) -> void:
	state_mutex.lock()
	var is_current = not _stop_pending and emit_args.size() >= 7 and int(emit_args[6]) == _evaluation_generation
	state_mutex.unlock()
	if not is_current:
		return
	evaluation_updated.emit(emit_args[0], emit_args[1], emit_args[2], emit_args[3], emit_args[4], emit_args[5])

## Émet `engine_ready` une fois la poignée de main UCI terminée, puis rejoue la
## demande Live mise en attente (correctif démarrage Live).
func _emit_engine_ready_deferred() -> void:
	state_mutex.lock()
	var pending := _pending_live_fen
	_pending_live_fen = ""
	# Réarme l'état d'évaluation pour que le rejeu Live ne soit pas avalé par la garde
	# `current_fen == fen and is_evaluating`.
	current_fen = ""
	is_evaluating = false
	state_mutex.unlock()
	engine_ready.emit()
	if pending != "":
		evaluate_position(pending)

func _exit_tree() -> void:
	stop_engine()

func stop_engine() -> void:
	if is_engine_running:
		_is_intentionally_stopping = true
		should_stop_thread = true
		send_command("quit")
		if _use_wasm:
			if ClassDB.class_exists("JavaScriptBridge"):
				JavaScriptBridge.eval("if (window.RodChessUci) { window.RodChessUci.stopEngine(); }")
		elif _use_plugin and _plugin_handle != null:
			_plugin_handle.stopEngine()
		state_mutex.lock()
		is_engine_running = false
		_pending_live_fen = ""
		_stop_pending = false
		_ignore_next_bestmove = false
		state_mutex.unlock()
		if not _use_wasm and not _use_plugin and engine_thread and engine_thread.is_started():
			engine_thread.wait_to_finish()

func _start_wasm_engine() -> bool:
	if not ClassDB.class_exists("JavaScriptBridge"):
		engine_error.emit("JavaScriptBridge non disponible dans cet environnement Web.")
		return false

	print("EngineManager: Démarrage du moteur Web Stockfish (Wasm/Worker)...")
	_wasm_callback = JavaScriptBridge.create_callback(_on_wasm_uci_line)
	var window = JavaScriptBridge.get_interface("window")
	if not window or not window.RodChessUci:
		engine_error.emit("Module window.RodChessUci introuvable dans la page HTML.")
		return false

	var ok = window.RodChessUci.init(_wasm_callback)
	if not ok:
		engine_error.emit("Impossible d'initialiser le Web Worker Stockfish.")
		return false

	_use_wasm = true
	state_mutex.lock()
	is_engine_running = true
	_handshake_ready = false
	_pending_live_fen = ""
	_engine_ready_emitted = false
	state_mutex.unlock()

	_received_any_output = false
	_log_first_raw_line = true
	_started_msec = Time.get_ticks_msec()

	send_command("uci")
	send_command("isready")
	send_command("ucinewgame")

	print("EngineManager: moteur Web Stockfish Wasm démarré et prêt.")
	return true

func _on_wasm_uci_line(args: Array) -> void:
	if args.is_empty():
		return
	var line: String = str(args[0])
	if _log_first_raw_line:
		_log_first_raw_line = false
		print("EngineManager: [Wasm brut] ", line.substr(0, 160))
	_parse_engine_line(line)
