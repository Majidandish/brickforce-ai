## =============================================================================
## Logger — Global Structured Logging System (Autoload Singleton)
## =============================================================================
## Purpose:
##   Centralised, levelled, categorised logging. Supports console output,
##   in-game debug console, and future file/remote log shipping.
##   Zero-cost in release builds via compile-time level gating.
##
## Levels: VERBOSE(0) DEBUG(1) INFO(2) WARN(3) ERROR(4) FATAL(5)
## =============================================================================

extends Node

# ── Log Levels ─────────────────────────────────────────────────────────────────
enum Level { VERBOSE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, FATAL = 5 }

const LEVEL_NAMES: Array[String] = ["VERBOSE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"]
const LEVEL_COLORS: Array[String] = [
	"#888888", # VERBOSE — grey
	"#44aaff", # DEBUG   — blue
	"#44ff88", # INFO    — green
	"#ffcc00", # WARN    — yellow
	"#ff4444", # ERROR   — red
	"#ff00ff", # FATAL   — magenta
]

# ── Configuration ──────────────────────────────────────────────────────────────
var _min_level: int       = Level.DEBUG if OS.is_debug_build() else Level.WARN
var _max_entries: int     = 2000
var _write_to_file: bool  = false
var _log_file_path: String = "user://logs/brickforce.log"
var _emit_to_event_bus: bool = true

# ── State ──────────────────────────────────────────────────────────────────────
var _entries: Array[Dictionary] = []
var _file: FileAccess = null
var _category_filters: Dictionary = {}  # category -> bool (true = show)


func _ready() -> void:
	name = "Logger"
	if _write_to_file:
		_open_log_file()
	info("Logger", "Logging system initialised. Min level: %s" % LEVEL_NAMES[_min_level])


# ── Public API ─────────────────────────────────────────────────────────────────

func verbose(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.VERBOSE, category, message, data)

func debug(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.DEBUG, category, message, data)

func info(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.INFO, category, message, data)

func warn(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.WARN, category, message, data)

func error(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.ERROR, category, message, data)

func fatal(category: String, message: String, data: Dictionary = {}) -> void:
	_log(Level.FATAL, category, message, data)
	# In release builds, FATAL writes a crash report before quitting.
	if not OS.is_debug_build():
		_write_crash_report(category, message, data)
		get_tree().quit(1)

## Set the minimum log level at runtime.
func set_min_level(level: Level) -> void:
	_min_level = level
	info("Logger", "Min log level changed to: %s" % LEVEL_NAMES[level])

## Filter to a specific category (empty string = show all).
func set_category_filter(category: String, enabled: bool) -> void:
	_category_filters[category] = enabled

## Return recent entries (optionally filtered by level or category).
func get_entries(
	min_level: int = Level.VERBOSE,
	category: String = ""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries:
		if entry.level < min_level:
			continue
		if category != "" and entry.category != category:
			continue
		result.append(entry)
	return result

## Clear all stored log entries.
func clear() -> void:
	_entries.clear()


# ── Internal ───────────────────────────────────────────────────────────────────

func _log(level: int, category: String, message: String, data: Dictionary) -> void:
	if level < _min_level:
		return
	if _category_filters.has(category) and not _category_filters[category]:
		return

	var entry: Dictionary = {
		"level":     level,
		"level_name": LEVEL_NAMES[level],
		"category":  category,
		"message":   message,
		"data":      data,
		"timestamp": Time.get_unix_time_from_system(),
		"time_str":  Time.get_time_string_from_system(),
	}

	# Store
	_entries.append(entry)
	if _entries.size() > _max_entries:
		_entries.pop_front()

	# Console
	var formatted: String = _format_entry(entry)
	if level >= Level.ERROR:
		push_error(formatted)
	elif level == Level.WARN:
		push_warning(formatted)
	else:
		print(formatted)

	# File
	if _write_to_file and _file:
		_file.store_line(formatted)

	# EventBus
	if _emit_to_event_bus and is_node_ready():
		# Defer to avoid circular calls during init
		EventBus.log_entry_added.emit(level, category, message)


func _format_entry(entry: Dictionary) -> String:
	var data_str: String = ""
	if not entry.data.is_empty():
		data_str = " | " + JSON.stringify(entry.data)
	return "[%s][%s][%s] %s%s" % [
		entry.time_str,
		entry.level_name.lpad(7),
		entry.category,
		entry.message,
		data_str,
	]


func _open_log_file() -> void:
	DirAccess.make_dir_recursive_absolute("user://logs")
	_file = FileAccess.open(_log_file_path, FileAccess.WRITE)
	if not _file:
		push_warning("Logger: could not open log file at " + _log_file_path)


func _write_crash_report(category: String, message: String, data: Dictionary) -> void:
	var path: String = "user://logs/crash_%d.txt" % int(Time.get_unix_time_from_system())
	DirAccess.make_dir_recursive_absolute("user://logs")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("=== BrickForce AI Crash Report ===\n")
		f.store_string("Time: %s\n" % Time.get_datetime_string_from_system())
		f.store_string("Category: %s\n" % category)
		f.store_string("Message: %s\n" % message)
		f.store_string("Data: %s\n" % JSON.stringify(data))
		f.store_string("\n--- Recent Log ---\n")
		for entry in get_entries(Level.DEBUG):
			f.store_line(_format_entry(entry))
		f.close()
