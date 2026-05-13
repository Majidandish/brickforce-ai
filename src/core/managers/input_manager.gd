## =============================================================================
## InputManager — Unified Input Abstraction Layer (Autoload)
## =============================================================================
## Purpose:
##   Normalises keyboard, mouse, and gamepad input into a single interface.
##   Supports runtime rebinding, dead zones, aim curves, and action buffering.
##   All gameplay code queries InputManager, never Input directly.
## =============================================================================

extends Node

## Axis dead zone for analog sticks.
const DEFAULT_DEAD_ZONE: float = 0.2
## How many frames action presses are buffered for (input forgiveness).
const BUFFER_FRAMES: int = 6

## Emitted when a binding is changed at runtime.
signal binding_changed(action: String)

# ── State ──────────────────────────────────────────────────────────────────────
var _action_buffer: Dictionary = {}     # action -> frames_remaining
var _last_device: String = "keyboard"   # "keyboard" | "gamepad"
var _mouse_delta: Vector2 = Vector2.ZERO
var _mouse_sensitivity: float = 0.3
var _aim_sensitivity: float  = 0.15
var _controller_index: int = 0


func _ready() -> void:
	name = "InputManager"
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_mouse_sensitivity = SettingsManager.get_value("gameplay.mouse_sensitivity", 0.3)
	_aim_sensitivity   = SettingsManager.get_value("gameplay.aim_sensitivity", 0.15)
	EventBus.settings_changed.connect(_on_settings_changed)
	Logger.info("InputManager", "Initialized.")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_delta = (event as InputEventMouseMotion).relative
		_last_device = "keyboard"
	elif event is InputEventJoypadMotion or event is InputEventJoypadButton:
		_last_device = "gamepad"
	elif event is InputEventKey or event is InputEventMouseButton:
		_last_device = "keyboard"


func _process(_delta: float) -> void:
	# Drain buffer counters.
	for action in _action_buffer.keys():
		_action_buffer[action] -= 1
		if _action_buffer[action] <= 0:
			_action_buffer.erase(action)

	# Buffer newly pressed actions.
	for action in _get_all_actions():
		if Input.is_action_just_pressed(action):
			_action_buffer[action] = BUFFER_FRAMES

	_mouse_delta = Vector2.ZERO


# ── Public API ─────────────────────────────────────────────────────────────────

## Returns true if an action was pressed this frame or within the buffer window.
func is_action_buffered(action: String) -> bool:
	return _action_buffer.has(action)


## Consume a buffered action (call after responding to it).
func consume_buffer(action: String) -> void:
	_action_buffer.erase(action)


## Returns the mouse delta this frame, scaled by sensitivity.
func get_look_delta(is_aiming: bool = false) -> Vector2:
	var sens: float = _aim_sensitivity if is_aiming else _mouse_sensitivity
	if _last_device == "gamepad":
		var raw: Vector2 = Vector2(
			Input.get_joy_axis(_controller_index, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(_controller_index, JOY_AXIS_RIGHT_Y)
		)
		raw = _apply_dead_zone(raw, DEFAULT_DEAD_ZONE)
		return raw * sens * 10.0
	return _mouse_delta * sens


## Returns the movement vector (WASD / left stick), dead-zone applied.
func get_move_vector() -> Vector2:
	var vec: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)
	if _last_device == "gamepad":
		vec = Vector2(
			Input.get_joy_axis(_controller_index, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(_controller_index, JOY_AXIS_LEFT_Y)
		)
	return _apply_dead_zone(vec, DEFAULT_DEAD_ZONE)


## Returns the active input device type.
func get_active_device() -> String:
	return _last_device


## Remap an action to a new event at runtime.
func remap_action(action: String, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	binding_changed.emit(action)
	Logger.info("InputManager", "Rebound action: %s" % action)
	# Persist to SettingsManager
	var bindings: Dictionary = SettingsManager.get_value("controls.bindings", {})
	# Serialize to string — custom serializer needed for full round-trip.
	bindings[action] = event.as_text()
	SettingsManager.set_value("controls.bindings", bindings)


## Reset all bindings to project defaults.
func reset_all_bindings() -> void:
	InputMap.load_from_project_settings()
	SettingsManager.set_value("controls.bindings", {})
	Logger.info("InputManager", "Bindings reset to defaults.")


# ── Internal ───────────────────────────────────────────────────────────────────

func _apply_dead_zone(vec: Vector2, zone: float) -> Vector2:
	if vec.length() < zone:
		return Vector2.ZERO
	return vec.normalized() * ((vec.length() - zone) / (1.0 - zone))


func _get_all_actions() -> Array:
	return InputMap.get_actions()


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	Logger.info("InputManager", "Gamepad %d %s." % [device, "connected" if connected else "disconnected"])
	if connected:
		_controller_index = device
		_last_device = "gamepad"


func _on_settings_changed(category: String, key: String, value: Variant) -> void:
	if category != "gameplay":
		return
	match key:
		"mouse_sensitivity": _mouse_sensitivity = value as float
		"aim_sensitivity":   _aim_sensitivity   = value as float
