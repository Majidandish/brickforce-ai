## =============================================================================
## SaveManager — Save/Load Game Progress System (Autoload)
## =============================================================================
## Purpose:
##   Manages multiple save slots with versioned JSON data, encryption
##   support, auto-save, and corruption recovery via backup files.
##   All game systems register serializers to participate in saves.
## =============================================================================

extends Node

const SAVE_DIR: String      = "user://saves/"
const BACKUP_SUFFIX: String = ".bak"
const MAX_SLOTS: int        = 5
const SCHEMA_VERSION: int   = 1
const AUTO_SAVE_INTERVAL: float = 120.0  # seconds

## Set true to encrypt saves (requires an encryption key).
const ENCRYPT_SAVES: bool = false
const ENCRYPTION_KEY: String = ""  # TODO: inject via env or key server.

signal save_completed(slot: int)
signal load_completed(slot: int, data: Dictionary)
signal save_failed(slot: int, reason: String)
signal load_failed(slot: int, reason: String)
signal auto_saved(slot: int)

var _active_slot: int = 0
var _save_data: Dictionary = {}
var _serializers: Dictionary = {}  # system_key -> { save: Callable, load: Callable }
var _auto_save_timer: float = 0.0
var _auto_save_enabled: bool = true


func _ready() -> void:
	name = "SaveManager"
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	Logger.info("SaveManager", "Initialized. Save dir: %s" % SAVE_DIR)


func _process(delta: float) -> void:
	if not _auto_save_enabled or not GameManager.is_in_match():
		return
	_auto_save_timer += delta
	if _auto_save_timer >= AUTO_SAVE_INTERVAL:
		_auto_save_timer = 0.0
		save(_active_slot)
		auto_saved.emit(_active_slot)


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a system for serialization.
## save_fn: Callable() -> Dictionary
## load_fn: Callable(data: Dictionary) -> void
func register_serializer(key: String, save_fn: Callable, load_fn: Callable) -> void:
	_serializers[key] = { "save": save_fn, "load": load_fn }
	Logger.debug("SaveManager", "Serializer registered: %s" % key)


## Save game to a slot.
func save(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS:
		Logger.error("SaveManager", "Invalid save slot: %d" % slot)
		return

	var data: Dictionary = _collect_save_data()
	data["meta"] = {
		"schema_version": SCHEMA_VERSION,
		"timestamp":      Time.get_unix_time_from_system(),
		"datetime":       Time.get_datetime_string_from_system(),
		"slot":           slot,
		"play_time":      GameManager.match_time,
	}

	var path: String = _slot_path(slot)
	var err: Error = _write_save(path, data)
	if err == OK:
		_active_slot = slot
		save_completed.emit(slot)
		EventBus.game_saved.emit(slot)
		Logger.info("SaveManager", "Game saved to slot %d." % slot)
	else:
		save_failed.emit(slot, "Write failed: %d" % err)
		Logger.error("SaveManager", "Save failed for slot %d: %d" % [slot, err])


## Load game from a slot.
func load_slot(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		Logger.error("SaveManager", "Invalid slot: %d" % slot)
		return false

	var path: String = _slot_path(slot)
	var data: Dictionary = _read_save(path)

	if data.is_empty():
		# Try backup.
		data = _read_save(path + BACKUP_SUFFIX)
		if data.is_empty():
			load_failed.emit(slot, "No save data found.")
			return false
		Logger.warn("SaveManager", "Loaded from backup for slot %d." % slot)

	var schema: int = data.get("meta", {}).get("schema_version", 0)
	if schema < SCHEMA_VERSION:
		data = _migrate_save(data, schema)

	_apply_save_data(data)
	_active_slot = slot
	_save_data = data
	load_completed.emit(slot, data)
	EventBus.game_loaded.emit(slot)
	Logger.info("SaveManager", "Slot %d loaded." % slot)
	return true


## Delete a save slot.
func delete_slot(slot: int) -> void:
	var path: String = _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + BACKUP_SUFFIX):
		DirAccess.remove_absolute(path + BACKUP_SUFFIX)
	Logger.info("SaveManager", "Slot %d deleted." % slot)


## Get metadata for all slots (for the save selection UI).
func get_all_slot_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in MAX_SLOTS:
		var meta: Dictionary = get_slot_metadata(i)
		meta["slot"] = i
		result.append(meta)
	return result


## Get metadata for a single slot without loading full data.
func get_slot_metadata(slot: int) -> Dictionary:
	var path: String = _slot_path(slot)
	if not FileAccess.file_exists(path):
		return { "exists": false }
	var data: Dictionary = _read_save(path)
	var meta: Dictionary = data.get("meta", {})
	meta["exists"] = true
	return meta


## Returns the currently active slot index.
func get_active_slot() -> int:
	return _active_slot


## Enable or disable auto-save.
func set_auto_save(enabled: bool) -> void:
	_auto_save_enabled = enabled


# ── Internal ───────────────────────────────────────────────────────────────────

func _collect_save_data() -> Dictionary:
	var data: Dictionary = {}
	for key in _serializers:
		data[key] = _serializers[key].save.call()
	return data


func _apply_save_data(data: Dictionary) -> void:
	for key in _serializers:
		if data.has(key):
			_serializers[key].load.call(data[key])


func _slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%02d.save" % slot


func _write_save(path: String, data: Dictionary) -> Error:
	# Backup existing file before overwriting.
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, path + BACKUP_SUFFIX)

	var json_str: String = JSON.stringify(data, "\t")
	var f: FileAccess

	if ENCRYPT_SAVES and ENCRYPTION_KEY != "":
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.WRITE, ENCRYPTION_KEY)
	else:
		f = FileAccess.open(path, FileAccess.WRITE)

	if not f:
		return FileAccess.get_open_error()

	f.store_string(json_str)
	f.close()
	return OK


func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var f: FileAccess
	if ENCRYPT_SAVES and ENCRYPTION_KEY != "":
		f = FileAccess.open_encrypted_with_pass(path, FileAccess.READ, ENCRYPTION_KEY)
	else:
		f = FileAccess.open(path, FileAccess.READ)

	if not f:
		return {}

	var json: JSON = JSON.new()
	var content: String = f.get_as_text()
	f.close()

	if json.parse(content) != OK:
		Logger.error("SaveManager", "Corrupt save file: %s" % path)
		return {}

	return json.get_data()


func _migrate_save(data: Dictionary, from_version: int) -> Dictionary:
	Logger.info("SaveManager", "Migrating save from v%d to v%d" % [from_version, SCHEMA_VERSION])
	# Add migration logic per version increment here.
	data["meta"]["schema_version"] = SCHEMA_VERSION
	return data
