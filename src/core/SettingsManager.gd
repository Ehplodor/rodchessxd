extends Node
## SettingsManager.gd - Gestionnaire de configuration persistant pour RodChessXD

signal settings_changed(key: String, value: Variant)

const CONFIG_PATH = "user://settings.cfg"

var config := ConfigFile.new()

# Valeurs par défaut
var settings := {
	"engine_threads": 2,
	"engine_hash_mb": 32,
	"engine_depth": 18,
	"engine_multipv": 2,
	"engine_path": "",
	"active_engine": "Stockfish",
	"board_theme": "dark_modern",
	"sound_enabled": true,
	"sound_volume": 0.8,
	"ai_provider": "free_cloud", # "local_slm", "free_cloud", "api_key"
	"ai_free_service": "gemini_free", # "gemini_free", "groq_free"
	"ai_api_service": "openai", # "openai", "anthropic", "deepseek", "gemini_paid"
	"api_key_openai": "",
	"api_key_gemini": "",
	"api_key_anthropic": "",
	"api_key_groq": "",
	"api_key_deepseek": "",
	"local_slm_url": "http://127.0.0.1:11434/api/generate", # Ollama / llama.cpp standard
	"coach_personality": "mentor", # "mentor", "blunder_hunter", "kids_simple"
	"flip_board": false
}

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var err = config.load(CONFIG_PATH)
	if err == OK:
		for key in settings.keys():
			if config.has_section_key("settings", key):
				settings[key] = config.get_value("settings", key, settings[key])
	else:
		save_settings()

func save_settings() -> void:
	for key in settings.keys():
		config.set_value("settings", key, settings[key])
	config.save(CONFIG_PATH)

func get_setting(key: String, default_val: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	return default_val

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	config.set_value("settings", key, value)
	config.save(CONFIG_PATH)
	settings_changed.emit(key, value)
