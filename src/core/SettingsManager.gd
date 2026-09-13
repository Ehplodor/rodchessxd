extends Node
## SettingsManager.gd - Gestionnaire de configuration persistant pour RodChessXD

signal settings_changed(key: String, value: Variant)

const CONFIG_PATH = "user://settings.cfg"

var config := ConfigFile.new()

# Valeurs par défaut
var settings := {
	"engine_threads": 2,
	"engine_hash_mb": 32,
	"engine_depth": 16,
	"analysis_depth": 18,
	"analysis_mode": "dynamic", # "depth", "time", "dynamic"
	"analysis_time_per_move": 0.3, # secondes par coup en mode time
	"analysis_dynamic_base": 0.15, # temps de base en mode dynamique (secondes)
	"analysis_dynamic_max": 0.8, # plafond en mode dynamique (secondes)
	"engine_multipv": 3,
	"engine_path": "",
	"active_engine": "Stockfish",
	"board_theme": "emerald",
	"sound_enabled": true,
	"sound_volume": 0.8,
	"ai_provider": "free_cloud", # "local_slm", "free_cloud", "api_key"
	"ai_free_service": "gemini_free", # "gemini_free", "groq_free"
	"ai_api_service": "deepseek", # "openai", "anthropic", "deepseek", "gemini_paid"
	"active_model_id": "z-ai/glm-5.3-flash:free",
	"api_key_openai": "",
	"api_key_gemini": "",
	"api_key_anthropic": "",
	"api_key_groq": "",
	"api_key_deepseek": "",
	"api_key_openrouter": "",
	"last_catalog_sync": "",
	"local_slm_url": "http://127.0.0.1:11434/api/generate", # Ollama / llama.cpp standard
	"coach_personality": "mentor", # "mentor", "blunder_hunter", "kids_simple"
	"flip_board": false,
	"show_move_hints": true,
	"app_theme_mode": "dark", # "dark", "light"
	"carnet_analysis_speed": "fast" # "fast", "balanced", "deep"
}

func _ready() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		settings["engine_depth"] = 12
		settings["analysis_depth"] = 14
		settings["engine_multipv"] = 2
	load_settings()
	DesignTokens.apply_theme_mode(settings.get("app_theme_mode", "dark"))

func load_settings() -> void:
	if _use_local_storage() and _load_from_local_storage():
		DesignTokens.apply_theme_mode(settings.get("app_theme_mode", "dark"))
		return
	# Stockage de repli : ConfigFile user:// (natif) — sur Web sert de migration
	# vers localStorage pour les données antérieures.
	var loaded := _load_from_config_file()
	if _use_local_storage():
		_save_to_local_storage() # migration / création des réglages par défaut
	else:
		if not loaded:
			save_settings()
	DesignTokens.apply_theme_mode(settings.get("app_theme_mode", "dark"))

func _load_from_config_file() -> bool:
	var err = config.load(CONFIG_PATH)
	if err != OK:
		return false
	for key in settings.keys():
		if config.has_section_key("settings", key):
			settings[key] = config.get_value("settings", key, settings[key])
	return true

func save_settings() -> void:
	if _use_local_storage():
		_save_to_local_storage()
		return
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(CONFIG_PATH)

## Sur Web (PWA), les réglages sont stockés dans localStorage : persistance
## synchrone et fiable, identique PC/mobile (contrairement à l'IndexedDB de
## user:// dont l'écriture peut ne pas être suivie par un rechargement mobile).
func _use_local_storage() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge")

func _save_to_local_storage() -> void:
	if not _use_local_storage():
		return
	var json_text: String = JSON.stringify(settings)
	var js_literal: String = JSON.stringify(json_text)
	JavaScriptBridge.eval("window.localStorage.setItem('rodchess_settings', %s);" % js_literal)

func _load_from_local_storage() -> bool:
	if not _use_local_storage():
		return false
	var raw := str(JavaScriptBridge.eval("window.localStorage.getItem('rodchess_settings') || ''"))
	if raw == "":
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var dict := parsed as Dictionary
	for key in settings.keys():
		if dict.has(key):
			settings[key] = dict[key]
	return true

func get_setting(key: String, default_val: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	return default_val

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if _use_local_storage():
		_save_to_local_storage()
	else:
		config.set_value("settings", key, value)
		config.save(CONFIG_PATH)
	settings_changed.emit(key, value)
