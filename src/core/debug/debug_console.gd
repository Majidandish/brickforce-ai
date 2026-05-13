## =============================================================================
## DebugConsole — In-Game Developer Console (Autoload)
## =============================================================================
## Purpose:
##   Quake-style developer console for runtime commands. Toggles with `~`.
##   Supports command registration by any system, tab-completion,
##   command history, and piping output to the Logger.
## =============================================================================

extends CanvasLayer

const MAX_HISTORY: int    = 200
const MAX_CMD_HISTORY: int = 50

signal command_registered(command: String)
signal console_opened()
signal console_closed()

var _is_open: bool = false
var _commands: Dictionary = {}        # name -> { desc, callable }
var _output_lines: Array[String] = []
var _cmd_history: Array[String] = []
var _history_idx: int = -1

# UI refs (populated after scene is set up — optional, console works headless)
var _container: Control = null
var _output_label: RichTextLabel = null
var _input_field: LineEdit = null


func _ready() -> void:
	name = "DebugConsole"
	layer = 128  # Always on top.
	_register_builtin_commands()
	EventBus.log_entry_added.connect(_on_log_entry)
	Logger.info("DebugConsole", "Developer console ready. Press ` to open.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_console"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _is_open:
		return
	# Navigate history.
	if _input_field and event is InputEventKey and event.pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_UP:
				_navigate_history(1)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_navigate_history(-1)
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_auto_complete()
				get_viewport().set_input_as_handled()


# ── Public API ─────────────────────────────────────────────────────────────────

## Toggle console visibility.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## Open the console.
func open() -> void:
	_is_open = true
	if _container:
		_container.show()
		_input_field.grab_focus()
	console_opened.emit()


## Close the console.
func close() -> void:
	_is_open = false
	if _container:
		_container.hide()
	console_closed.emit()


## Register a console command. callback: Callable(args: Array[String]) -> String
func register_command(name: String, description: String, callback: Callable) -> void:
	name = name.to_lower().strip_edges()
	_commands[name] = { "desc": description, "fn": callback }
	command_registered.emit(name)


## Unregister a command.
func unregister_command(name: String) -> void:
	_commands.erase(name.to_lower())


## Execute a raw command string.
func execute(raw: String) -> void:
	raw = raw.strip_edges()
	if raw.is_empty():
		return

	_cmd_history.push_front(raw)
	if _cmd_history.size() > MAX_CMD_HISTORY:
		_cmd_history.pop_back()
	_history_idx = -1

	_print_line("> " + raw, "#aaddff")
	EventBus.debug_command_issued.emit(raw, raw.split(" "))
	Logger.debug("DebugConsole", "Command: %s" % raw)

	var parts: PackedStringArray = raw.split(" ", false)
	if parts.is_empty():
		return

	var cmd_name: String = parts[0].to_lower()
	var args: Array[String] = []
	for i in range(1, parts.size()):
		args.append(parts[i])

	if not _commands.has(cmd_name):
		_print_line("Unknown command: '%s'. Type 'help' for a list." % cmd_name, "#ff8888")
		return

	var result: String = _commands[cmd_name].fn.call(args)
	if result != "":
		_print_line(result, "#ffffff")


## Print a line to the console output.
func print_line(text: String, color: String = "#dddddd") -> void:
	_print_line(text, color)


## Returns true if the console is currently open.
func is_open() -> bool:
	return _is_open


# ── Internal ───────────────────────────────────────────────────────────────────

func _print_line(text: String, color: String) -> void:
	var entry: String = "[color=%s]%s[/color]" % [color, text.xml_escape()]
	_output_lines.append(entry)
	if _output_lines.size() > MAX_HISTORY:
		_output_lines.pop_front()
	if _output_label:
		_output_label.clear()
		_output_label.append_text("\n".join(_output_lines))
		_output_label.scroll_to_line(_output_label.get_line_count() - 1)


func _navigate_history(direction: int) -> void:
	if _cmd_history.is_empty() or not _input_field:
		return
	_history_idx = clamp(_history_idx + direction, -1, _cmd_history.size() - 1)
	if _history_idx == -1:
		_input_field.text = ""
	else:
		_input_field.text = _cmd_history[_history_idx]
	_input_field.caret_column = _input_field.text.length()


func _auto_complete() -> void:
	if not _input_field:
		return
	var partial: String = _input_field.text.to_lower().strip_edges()
	var matches: Array[String] = []
	for cmd in _commands.keys():
		if cmd.begins_with(partial):
			matches.append(cmd)
	if matches.size() == 1:
		_input_field.text = matches[0] + " "
		_input_field.caret_column = _input_field.text.length()
	elif matches.size() > 1:
		_print_line("Matches: " + ", ".join(matches), "#aaaaaa")


func _on_log_entry(level: int, category: String, message: String) -> void:
	if level < Logger.Level.WARN:
		return
	var color: String = "#ffcc00" if level == Logger.Level.WARN else "#ff4444"
	_print_line("[%s] %s" % [category, message], color)


func _on_input_submitted(text: String) -> void:
	execute(text)
	if _input_field:
		_input_field.clear()


# ── Built-in Commands ──────────────────────────────────────────────────────────

func _register_builtin_commands() -> void:
	register_command("help", "List all commands.", func(args):
		var lines: Array[String] = ["Available commands:"]
		for name in _commands.keys():
			lines.append("  %-20s %s" % [name, _commands[name].desc])
		return "\n".join(lines)
	)

	register_command("clear", "Clear console output.", func(_args):
		_output_lines.clear()
		if _output_label: _output_label.clear()
		return ""
	)

	register_command("fps", "Show current FPS.", func(_args):
		return "FPS: %d" % Engine.get_frames_per_second()
	)

	register_command("perf", "Show performance stats.", func(_args):
		return PerformanceMonitor.get_hud_string()
	)

	register_command("pools", "Show object pool stats.", func(_args):
		var stats: Array[Dictionary] = ObjectPool.get_all_stats()
		if stats.is_empty(): return "No pools registered."
		var lines: Array[String] = []
		for s in stats:
			lines.append("  %s — active:%d idle:%d cap:%d" % [
				s.id, s.active, s.inactive, s.cap
			])
		return "\n".join(lines)
	)

	register_command("state", "Show current game state.", func(_args):
		return "GameState: %s  |  MatchTime: %.1fs" % [
			GameManager.STATE_NAMES[GameManager.current_state],
			GameManager.match_time,
		]
	)

	register_command("log_level", "Set log level (0-5).", func(args):
		if args.is_empty(): return "Usage: log_level <0-5>"
		Logger.set_min_level(int(args[0]) as Logger.Level)
		return "Log level set to %s" % Logger.LEVEL_NAMES[int(args[0])]
	)

	register_command("quit", "Quit the game.", func(_args):
		GameManager.quit_game()
		return ""
	)

	register_command("scene", "Load a scene by path.", func(args):
		if args.is_empty(): return "Usage: scene <res://path/to/scene.tscn>"
		SceneManager.load_scene(args[0])
		return "Loading: %s" % args[0]
	)

	register_command("give_currency", "Give currency. Usage: give_currency <type> <amount>", func(args):
		if args.size() < 2: return "Usage: give_currency <type> <amount>"
		CurrencyManager.add(args[0], int(args[1]))
		return "Granted %s x%s" % [args[1], args[0]]
	)

	register_command("god", "Toggle god mode for local player.", func(_args):
		var p = GameManager.local_player
		if not p: return "No local player."
		var flag: bool = not p.get_meta("god_mode", false)
		p.set_meta("god_mode", flag)
		return "God mode: %s" % ("ON" if flag else "OFF")
	)

	register_command("spawn_ai", "Spawn an AI agent at player position.", func(args):
		var type: String = args[0] if not args.is_empty() else "grunt"
		EventBus.debug_command_issued.emit("spawn_ai", [type])
		return "Spawning AI: %s" % type
	)

	register_command("time_scale", "Set engine time scale. Usage: time_scale <0.0-2.0>", func(args):
		if args.is_empty(): return "Usage: time_scale <0.0-2.0>"
		Engine.time_scale = clampf(float(args[0]), 0.01, 5.0)
		return "Time scale: %.2f" % Engine.time_scale
	)
