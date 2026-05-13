## =============================================================================
## DevTools — Runtime Developer Overlay & Tooling (Autoload)
## =============================================================================
## Purpose:
##   Renders a lightweight developer HUD over the game showing FPS, memory,
##   AI state, physics debug, and pool stats. Toggleable subsystems.
##   Only active in debug builds unless explicitly enabled.
## =============================================================================

extends CanvasLayer

const OVERLAY_REFRESH: float = 0.25  # Seconds between HUD text updates.

signal hud_toggled(visible: bool)

var _hud_enabled: bool       = OS.is_debug_build()
var _physics_debug: bool     = false
var _ai_debug: bool          = false
var _nav_debug: bool         = false
var _collision_debug: bool   = false
var _timer: float            = 0.0

# UI refs — created procedurally so this works without a scene.
var _label: Label


func _ready() -> void:
	name = "DevTools"
	layer = 127

	_label = Label.new()
	_label.name = "DevHUD"
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.6))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)

	_label.visible = _hud_enabled
	_register_dev_commands()
	Logger.info("DevTools", "Dev overlay ready. F3=toggle HUD.")


func _process(delta: float) -> void:
	if not _hud_enabled:
		return
	_timer += delta
	if _timer < OVERLAY_REFRESH:
		return
	_timer = 0.0
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F3:
				toggle_hud()
			KEY_F4:
				toggle_physics_debug()
			KEY_F5:
				pass  # Reserved for reload (handled elsewhere)
			KEY_F6:
				toggle_ai_debug()


# ── Public API ─────────────────────────────────────────────────────────────────

func toggle_hud() -> void:
	_hud_enabled = not _hud_enabled
	_label.visible = _hud_enabled
	hud_toggled.emit(_hud_enabled)


func toggle_physics_debug() -> void:
	_physics_debug = not _physics_debug
	get_viewport().debug_draw = (
		Viewport.DEBUG_DRAW_WIREFRAME if _physics_debug else Viewport.DEBUG_DRAW_DISABLED
	)
	Logger.debug("DevTools", "Physics debug: %s" % _physics_debug)


func toggle_ai_debug() -> void:
	_ai_debug = not _ai_debug
	EventBus.debug_command_issued.emit("ai_debug_toggle", [str(_ai_debug)])
	Logger.debug("DevTools", "AI debug overlay: %s" % _ai_debug)


func is_ai_debug_enabled() -> bool:
	return _ai_debug


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	var p: Node = GameManager.local_player
	var player_info: String = ""
	if p and p is Node3D:
		var pos: Vector3 = (p as Node3D).global_position
		player_info = "\nPlayer: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

	_label.text = (
		PerformanceMonitor.get_hud_string()
		+ player_info
		+ "\nState: " + GameManager.STATE_NAMES[GameManager.current_state]
		+ "\nTick: " + str(TimeManager.tick)
		+ "  MatchTime: " + TimeManager.format_duration(GameManager.match_time)
	)


func _register_dev_commands() -> void:
	DebugConsole.register_command("hud", "Toggle dev HUD.", func(_args): toggle_hud(); return "HUD toggled.")
	DebugConsole.register_command("physics_debug", "Toggle physics wireframe.", func(_args): toggle_physics_debug(); return "Physics debug toggled.")
	DebugConsole.register_command("ai_debug", "Toggle AI debug overlay.", func(_args): toggle_ai_debug(); return "AI debug toggled.")
