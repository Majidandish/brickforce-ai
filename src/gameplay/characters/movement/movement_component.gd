## =============================================================================
## MovementComponent — Modular Character Movement System
## =============================================================================
## Architecture:
##   Self-contained component attached to a CharacterBody3D.
##   Reads from MovementConfig (data resource) for all speed/acceleration values.
##   Outputs a final velocity each physics frame via calculate_velocity().
##   Supports: walk, sprint, crouch, prone, slide, vault, ledge grab, swim.
##
##   Network-safe: velocity calculation is deterministic — same inputs
##   always produce the same velocity. The owning character is responsible
##   for calling move_and_slide().
##
## Usage:
##   @onready var movement: MovementComponent = $MovementComponent
##   movement.initialize(character_body, config)
##   velocity = movement.calculate_velocity(delta, input_vec, flags)
## =============================================================================

class_name MovementComponent
extends Node

# ── Movement States ────────────────────────────────────────────────────────────
enum MoveState {
	IDLE,
	WALK,
	SPRINT,
	CROUCH_IDLE,
	CROUCH_WALK,
	PRONE,
	SLIDE,
	IN_AIR,
	LANDING,
	VAULT,
	LEDGE_GRAB,
	SWIMMING,
	DOWNED,
}

const STATE_NAMES: Dictionary = {
	MoveState.IDLE:        "Idle",
	MoveState.WALK:        "Walk",
	MoveState.SPRINT:      "Sprint",
	MoveState.CROUCH_IDLE: "CrouchIdle",
	MoveState.CROUCH_WALK: "CrouchWalk",
	MoveState.PRONE:       "Prone",
	MoveState.SLIDE:       "Slide",
	MoveState.IN_AIR:      "InAir",
	MoveState.LANDING:     "Landing",
	MoveState.VAULT:       "Vault",
	MoveState.LEDGE_GRAB:  "LedgeGrab",
	MoveState.SWIMMING:    "Swimming",
	MoveState.DOWNED:      "Downed",
}

# ── Signals ────────────────────────────────────────────────────────────────────
signal state_changed(old: MoveState, new_state: MoveState)
signal landed(fall_speed: float)
signal jumped()
signal slide_started()
signal slide_ended()
signal vaulted(obstacle: Node3D)
signal footstep(surface_material: String)

# ── References ────────────────────────────────────────────────────────────────
var body: CharacterBody3D = null
var config: MovementConfig = null

# ── Runtime State ─────────────────────────────────────────────────────────────
var current_state: MoveState = MoveState.IDLE
var previous_state: MoveState = MoveState.IDLE

var horizontal_velocity: Vector3 = Vector3.ZERO
var vertical_velocity: float     = 0.0
var is_grounded: bool            = false
var was_grounded: bool           = false
var air_time: float              = 0.0
var slide_timer: float           = 0.0
var slide_velocity: Vector3      = Vector3.ZERO
var coyote_timer: float          = 0.0
var jump_buffer_timer: float     = 0.0
var footstep_timer: float        = 0.0

# ── Flags (set externally each frame) ─────────────────────────────────────────
var flag_sprint: bool   = false
var flag_crouch: bool   = false
var flag_prone: bool    = false
var flag_jump: bool     = false
var flag_slide: bool    = false  # Sprint + crouch simultaneously.
var flag_aim: bool      = false

# ── Internal ───────────────────────────────────────────────────────────────────
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _surface_normal: Vector3 = Vector3.UP
var _speed_multiplier: float = 1.0  # External speed modifier (zone slow, debuffs…)
var _footstep_surface: String = "concrete"


func _ready() -> void:
	name = "MovementComponent"


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize the component with the owning body and optional config.
func initialize(owner_body: CharacterBody3D, movement_config: MovementConfig = null) -> void:
	body   = owner_body
	config = movement_config if movement_config else MovementConfig.new()
	Logger.debug("MovementComponent", "Initialized for %s." % owner_body.name)


## Calculate and return the final velocity for this frame.
## Call this in the owner's _physics_process, then use body.move_and_slide().
func calculate_velocity(delta: float, input_direction: Vector2) -> Vector3:
	if not body:
		return Vector3.ZERO

	was_grounded = is_grounded
	is_grounded  = body.is_on_floor()

	_update_timers(delta)
	_update_state(input_direction)
	_update_horizontal(delta, input_direction)
	_update_vertical(delta)
	_update_footsteps(delta)

	return Vector3(horizontal_velocity.x, vertical_velocity, horizontal_velocity.z)


## Apply an external impulse (knockback, explosion, etc.)
func add_impulse(impulse: Vector3) -> void:
	horizontal_velocity += Vector3(impulse.x, 0, impulse.z)
	vertical_velocity   += impulse.y


## Clamp horizontal speed (for zone slow, water, etc.)
func set_speed_multiplier(mult: float) -> void:
	_speed_multiplier = clampf(mult, 0.0, 2.0)


## Returns normalised speed ratio (0=idle, 1=sprint).
func get_speed_ratio() -> float:
	if not config:
		return 0.0
	return horizontal_velocity.length() / config.sprint_speed


## Returns true if the character is moving horizontally.
func is_moving() -> bool:
	return horizontal_velocity.length_squared() > 0.01


## Returns current state name string.
func get_state_name() -> String:
	return STATE_NAMES.get(current_state, "Unknown")


## Force a state transition (for external systems — use sparingly).
func force_state(state: MoveState) -> void:
	_transition(state)


# ── Internal — State Machine ───────────────────────────────────────────────────

func _update_state(input: Vector2) -> void:
	var new_state: MoveState = _evaluate_next_state(input)
	if new_state != current_state:
		_transition(new_state)


func _evaluate_next_state(input: Vector2) -> MoveState:
	# Priority order — highest priority first.
	if not body.is_alive if body.has_method("is_alive") else false:
		return MoveState.DOWNED

	if current_state == MoveState.VAULT:
		return MoveState.VAULT  # Managed by VaultComponent.

	if current_state == MoveState.LEDGE_GRAB:
		return MoveState.LEDGE_GRAB

	if not is_grounded and coyote_timer <= 0.0:
		return MoveState.IN_AIR

	if current_state == MoveState.SLIDE:
		if slide_timer > 0.0:
			return MoveState.SLIDE
		return MoveState.CROUCH_IDLE  # Slide ends into crouch.

	# Slide: sprint + crouch input while moving.
	if flag_sprint and flag_crouch and input.length() > 0.1 and is_grounded:
		if current_state == MoveState.SPRINT:
			return MoveState.SLIDE

	if flag_prone:
		return MoveState.PRONE

	if flag_crouch:
		return MoveState.CROUCH_IDLE if input.length() < 0.1 else MoveState.CROUCH_WALK

	if flag_sprint and input.length() > 0.1:
		return MoveState.SPRINT

	if input.length() > 0.1:
		return MoveState.WALK

	return MoveState.IDLE


func _transition(new_state: MoveState) -> void:
	var old: MoveState = current_state
	previous_state = old
	current_state  = new_state

	# Exit actions.
	match old:
		MoveState.SLIDE:  _on_slide_end()
		MoveState.IN_AIR: _on_landing()

	# Enter actions.
	match new_state:
		MoveState.SLIDE:  _on_slide_start()
		MoveState.IN_AIR:
			if is_grounded: coyote_timer = config.coyote_time

	state_changed.emit(old, new_state)
	EventBus.character_state_changed.emit(
		body.character_id if body.has_method("character_id") else -1,
		STATE_NAMES[old], STATE_NAMES[new_state]
	)


# ── Internal — Horizontal Movement ────────────────────────────────────────────

func _update_horizontal(delta: float, input: Vector2) -> void:
	var target_speed: float = _get_target_speed() * _speed_multiplier
	var accel: float        = _get_acceleration()
	var decel: float        = config.deceleration

	if current_state == MoveState.SLIDE:
		_update_slide(delta)
		return

	var wish_dir: Vector3 = Vector3.ZERO
	if input.length() > 0.1 and body:
		wish_dir  = -body.global_basis.z * input.y
		wish_dir += body.global_basis.x * input.x
		wish_dir  = wish_dir.normalized()

	if wish_dir.length() > 0.01:
		horizontal_velocity = horizontal_velocity.lerp(wish_dir * target_speed, accel * delta)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, decel * delta)

	# Air friction — much less control while airborne.
	if not is_grounded and current_state == MoveState.IN_AIR:
		horizontal_velocity = horizontal_velocity.lerp(
			wish_dir * target_speed, config.air_control * delta
		)


func _update_slide(delta: float) -> void:
	slide_timer = max(0.0, slide_timer - delta)
	# Maintain slide momentum with slight friction.
	slide_velocity = slide_velocity.lerp(Vector3.ZERO, config.slide_friction * delta)
	horizontal_velocity = slide_velocity
	# Allow steering during slide (reduced).
	if slide_timer <= 0.0:
		_transition(MoveState.CROUCH_IDLE)


func _get_target_speed() -> float:
	match current_state:
		MoveState.SPRINT:       return config.sprint_speed
		MoveState.WALK:         return config.walk_speed
		MoveState.CROUCH_WALK:  return config.crouch_speed
		MoveState.PRONE:        return config.prone_speed
		MoveState.IN_AIR:       return config.walk_speed
		MoveState.SWIMMING:     return config.swim_speed
		_:                      return 0.0


func _get_acceleration() -> float:
	if not is_grounded:
		return config.air_control
	match current_state:
		MoveState.SPRINT: return config.acceleration * 1.2
		_:                return config.acceleration


# ── Internal — Vertical / Gravity ─────────────────────────────────────────────

func _update_vertical(delta: float) -> void:
	if is_grounded:
		air_time     = 0.0
		vertical_velocity = -0.5  # Keep grounded.

		# Jump buffering.
		if jump_buffer_timer > 0.0:
			_execute_jump()
			jump_buffer_timer = 0.0
		elif flag_jump:
			_execute_jump()
	else:
		air_time += delta
		# Gravity — stronger when falling for better game feel.
		var grav_scale: float = config.fall_gravity_multiplier if vertical_velocity < 0.0 else 1.0
		vertical_velocity -= _gravity * grav_scale * delta
		vertical_velocity  = max(vertical_velocity, config.max_fall_speed)

		# Coyote jump.
		if flag_jump and coyote_timer > 0.0:
			_execute_jump()
			coyote_timer = 0.0
		elif flag_jump:
			jump_buffer_timer = config.jump_buffer_time


func _execute_jump() -> void:
	vertical_velocity = config.jump_velocity
	jumped.emit()
	EventBus.character_jumped.emit(body.character_id if body.has_method("character_id") else -1)


# ── Internal — Slide ───────────────────────────────────────────────────────────

func _on_slide_start() -> void:
	slide_velocity = horizontal_velocity * config.slide_speed_multiplier
	slide_timer    = config.slide_duration
	slide_started.emit()
	AudioManager.play_sfx_at("res://assets/audio/sfx/slide_start.ogg",
		body.global_position if body else Vector3.ZERO)


func _on_slide_end() -> void:
	slide_velocity = Vector3.ZERO
	slide_ended.emit()


# ── Internal — Landing ────────────────────────────────────────────────────────

func _on_landing() -> void:
	var fall_speed: float = abs(vertical_velocity)
	landed.emit(fall_speed)
	if fall_speed > config.hard_landing_threshold:
		VFXManager.play("dust_land", body.global_position if body else Vector3.ZERO)
		AudioManager.play_sfx_at("res://assets/audio/sfx/land_hard.ogg",
			body.global_position if body else Vector3.ZERO)


# ── Internal — Footsteps ──────────────────────────────────────────────────────

func _update_footsteps(delta: float) -> void:
	if not is_grounded or not is_moving():
		footstep_timer = 0.0
		return
	var step_interval: float = config.footstep_interval_sprint if current_state == MoveState.SPRINT \
		else config.footstep_interval_walk
	footstep_timer += delta
	if footstep_timer >= step_interval:
		footstep_timer = 0.0
		footstep.emit(_footstep_surface)
		AudioManager.play_sfx_at(
			"res://assets/audio/sfx/footstep_%s.ogg" % _footstep_surface,
			body.global_position if body else Vector3.ZERO
		)


# ── Internal — Timers ─────────────────────────────────────────────────────────

func _update_timers(delta: float) -> void:
	coyote_timer      = max(0.0, coyote_timer - delta)
	jump_buffer_timer = max(0.0, jump_buffer_timer - delta)

	if not is_grounded and was_grounded:
		coyote_timer = config.coyote_time

	if flag_jump and not is_grounded:
		jump_buffer_timer = config.jump_buffer_time
