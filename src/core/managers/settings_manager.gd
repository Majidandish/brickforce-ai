## =============================================================================
## SettingsManager — Persistent Settings & Configuration (Autoload)
## =============================================================================
## Purpose:
##   Loads, saves, and validates all user preferences: graphics, audio,
##   controls, gameplay, and accessibility. Emits EventBus signals on every
##   change so subscribers auto-update without polling.
## =============================================================================

extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const SCHEMA_VERSION: int   = 1

# ── Default Settings Schema ─────────────────────────────────────────────────────
const DEFAULTS: Dictionary = {
	"meta": {
		"schema_version": SCHEMA_VERSION,
	},
	"graphics": {
		"window_mode":       0,    # 0=windowed 1=fullscreen 2=borderless
		"resolution_x":      1920,
		"resolution_y":      1080,
		"render_scale":      1.0,
		"msaa":              2,    # 0=off 1=2x 2=4x 3=8x
		"vsync":             1,
		"fps_limit":         0,    # 0 = unlimited
		"shadow_quality":    2,    # 0-3
		"texture_quality":   2,
		"foliage_density":   1.0,
		"view_distance":     500.0,
		"motion_blur":       false,
		"depth_of_field":    false,
		"ambient_occlusion": true,
		"bloom":             true,
	},
	"audio": {
		"master_volume":  1.0,
		"music_volume":   0.7,
		"sfx_volume":     1.0,
		"voice_volume":   1.0,
		"ambient_volume": 0.8,
		"mute_when_unfocused": true,
	},
	"gameplay": {
		"mouse_sensitivity": 0.3,
		"aim_sensitivity":   0.15,
		"controller_vibration": true,
		"aim_assist":        0,    # 0=off 1=light 2=full
		"crosshair_style":   0,
		"minimap_rotation":  false,
		"show_damage_numbers": true,
		"auto_pickup_ammo":  true,
		"squad_voice_commands": true,
		"camera_shake":      true,
		"hit_markers":       true,
		"kill_feed":         true,
		"language":          "en",
	},
	"accessibility": {
		"subtitles":         false,
		"subtitle_size":     1.0,
		"colorblind_mode":   0,    # 0=off 1=deuteranopia 2=protanopia 3=tritanopia
		"high_contrast_ui":  false,
		"reduce_motion":     false,
		"screen_reader":     false,
	},
	"controls": {
		# Keybind overrides stored as action->InputEvent serialized strings.
		"bindings": {},
	},
	"network": {
		"dedicated_server_url": "",
		"region":               "auto",
		"max_ping":             150,
	},
}

var _data: Dictionary = {}
var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	name = "SettingsManager"
	_load()
	Logger.info("SettingsManager", "Settings loaded.")
	_apply_all()


# ── Public API ─────────────────────────────────────────────────────────────────

## Get a setting value. Dot-path: get("graphics.vsync")
func get_value(path: String, default: Variant = null) -> Variant:
	var parts: Array = path.split(".")
	if parts.size() != 2:
		Logger.warn("SettingsManager", "Invalid path: %s" % path)
		return default
	var category: Dictionary = _data.get(parts[0], {})
	return category.get(parts[1], default)


## Set a setting value and immediately persist + broadcast.
func set_value(path: String, value: Variant) -> void:
	var parts: Array = path.split(".")
	if parts.size() != 2:
		Logger.warn("SettingsManager", "Invalid path: %s" % path)
		return
	var category: String = parts[0]
	var key: String = parts[1]
	if not _data.has(category):
		Logger.warn("SettingsManager", "Unknown category: %s" % category)
		return
	var old_val: Variant = _data[category].get(key)
	if old_val == value:
		return
	_data[category][key] = value
	_apply_setting(category, key, value)
	save()
	EventBus.settings_changed.emit(category, key, value)
	Logger.debug("SettingsManager", "Changed: %s = %s" % [path, str(value)])


## Get an entire category as a Dictionary.
func get_category(category: String) -> Dictionary:
	return _data.get(category, {}).duplicate()


## Reset a category to defaults.
func reset_category(category: String) -> void:
	if DEFAULTS.has(category):
		_data[category] = DEFAULTS[category].duplicate(true)
		_apply_category(category)
		save()
		Logger.info("SettingsManager", "Reset category: %s" % category)


## Reset everything to factory defaults.
func reset_all() -> void:
	_data = DEFAULTS.duplicate(true)
	_apply_all()
	save()
	Logger.info("SettingsManager", "All settings reset to defaults.")


## Persist settings to disk.
func save() -> void:
	for category in _data:
		for key in _data[category]:
			_config.set_value(category, key, _data[category][key])
	var err: Error = _config.save(SETTINGS_PATH)
	if err != OK:
		Logger.error("SettingsManager", "Failed to save settings: %d" % err)
	else:
		EventBus.game_saved.emit(-1)  # -1 = settings save, not match save


# ── Internal ───────────────────────────────────────────────────────────────────

func _load() -> void:
	_data = DEFAULTS.duplicate(true)
	var err: Error = _config.load(SETTINGS_PATH)
	if err != OK:
		Logger.info("SettingsManager", "No settings file found — using defaults.")
		return
	# Overlay saved values onto defaults.
	for category in _data:
		for key in _data[category]:
			if _config.has_section_key(category, key):
				_data[category][key] = _config.get_value(category, key)
	# Schema migration hook.
	var saved_version: int = _data.get("meta", {}).get("schema_version", 0)
	if saved_version < SCHEMA_VERSION:
		_migrate(saved_version)


func _migrate(from_version: int) -> void:
	Logger.info("SettingsManager", "Migrating settings from v%d to v%d" % [from_version, SCHEMA_VERSION])
	_data["meta"]["schema_version"] = SCHEMA_VERSION
	save()


func _apply_all() -> void:
	for category in _data:
		_apply_category(category)


func _apply_category(category: String) -> void:
	for key in _data[category]:
		_apply_setting(category, key, _data[category][key])


func _apply_setting(category: String, key: String, value: Variant) -> void:
	match category:
		"graphics":
			_apply_graphics(key, value)
		"audio":
			_apply_audio(key, value)
		"gameplay":
			_apply_gameplay(key, value)


func _apply_graphics(key: String, value: Variant) -> void:
	match key:
		"vsync":
			DisplayServer.window_set_vsync_mode(value as DisplayServer.VSyncMode)
		"fps_limit":
			Engine.max_fps = value as int
		"window_mode":
			match value:
				0: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"msaa":
			var vp: Viewport = get_viewport()
			if vp:
				vp.msaa_3d = value as Viewport.MSAA


func _apply_audio(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			AudioServer.set_bus_volume_db(
				AudioServer.get_bus_index("Master"),
				linear_to_db(value as float)
			)
		"music_volume":
			var idx: int = AudioServer.get_bus_index("Music")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value as float))
		"sfx_volume":
			var idx: int = AudioServer.get_bus_index("SFX")
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(value as float))


func _apply_gameplay(key: String, value: Variant) -> void:
	match key:
		"language":
			TranslationServer.set_locale(value as String)
			EventBus.language_changed.emit(value as String)
