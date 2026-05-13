## =============================================================================
## ThirdPersonCamera — Production Third-Person Camera System
## =============================================================================
## Architecture:
##   Two-pivot design:
##     1. YawPivot  — rotates on Y axis (left/right) — child of character root.
##     2. PitchPivot — rotates on X axis (up/down).
##     3. Camera3D — offset behind pitch pivot, with collision pull-in.
##
##   Features:
##     - Smooth spring-arm style collision (no clipping through walls)
##     - ADS / Aim FOV blend
##     - Camera shake (trauma-based decay)
##     - Lean tilt
##     - Free-look mode
##     - Combat zoom (closer when targeting)
##     - Sensitivity curves (configurable)
##
##   Network-safe: camera is a pure client-side view — never replicated.
## =============================================================================

class_name ThirdPersonCamera
extends Node3D

@export var config: CameraConfig

# ── Node References ─────────────────────────────────────────────────────────── 
@onready var pitch_pivot: Node3D = $PitchPivot
@onready var camera: Camera3D   = $PitchPivot/Camera3D
@onready var arm_end: Marker3D  = $PitchPivot/ArmEnd   # Desired camera position.

# ── State ──────────────────────────────────────────────────────────────────────
var yaw: float        = 0.0
var pitch: float      = 0.0
var _current_fov: float = 75.0
var _target_fov: float  = 75.0
var _arm_length: float  = 0.0   # Actual arm length (collision pulled).
var _trauma: float      = 0.0   # Camera shake accumulator (0-1).
var _shake_offset: Vector3 = Vector3.ZERO
var _is_ads: bool     = false
var _lean: float      = 0.0   # -1 left, 0 none, 1 right.
var _free_look: bool  = false
var _free_look_yaw: float = 0.0
var _owner_character: CharacterBase = null


func _ready() -> void:
	if not config:
		config = CameraConfig.new()
	_arm_length  = config.default_arm_length
	_current_fov = config.default_fov
	_target_fov  = config.default_fov
	if camera:
		camera.fov = _current_fov
	EventBus.screen_shake_requested.connect(_on_screen_shake_requested)


func _process(delta: float) -> void:
	_update_fov(delta)
	_update_collision()
	_update_shake(delta)
	_update_lean(delta)
	_apply_position()


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with the owning character node.
func initialize(character: CharacterBase) -> void:
	_owner_character = character


## Apply mouse/stick look delta. Call from character's _unhandled_input.
func add_look_input(delta_yaw: float, delta_pitch: float) -> void:
	if _free_look:
		_free_look_yaw = clampf(_free_look_yaw + delta_yaw,
			-config.free_look_clamp, config.free_look_clamp)
		return
	yaw   += delta_yaw
	pitch  = clampf(pitch + delta_pitch, config.pitch_min, config.pitch_max)
	rotation.y = yaw


## Enter / exit ADS mode.
func set_ads(aiming: bool) -> void:
	if _is_ads == aiming:
		return
	_is_ads     = aiming
	_target_fov = config.ads_fov if aiming else config.default_fov


## Set lean direction (-1, 0, 1).
func set_lean(direction: float) -> void:
	_lean = clampf(direction, -1.0, 1.0)


## Enable free-look (look around without rotating character).
func set_free_look(enabled: bool) -> void:
	_free_look = enabled
	if not enabled:
		_free_look_yaw = 0.0


## Trigger a camera shake. trauma: 0.0-1.0 (1 = maximum shake).
func add_trauma(trauma: float) -> void:
	_trauma = minf(_trauma + trauma, 1.0)


## Returns the forward direction from the camera (for aiming).
func get_aim_direction() -> Vector3:
	return -camera.global_basis.z if camera else Vector3.FORWARD


## Returns camera's global position.
func get_camera_position() -> Vector3:
	return camera.global_position if camera else global_position


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_fov(delta: float) -> void:
	_current_fov = lerpf(_current_fov, _target_fov, config.fov_lerp_speed * delta)
	if camera:
		camera.fov = _current_fov


func _update_collision() -> void:
	if not arm_end or not camera:
		return
	# Raycast from pivot origin to desired camera position.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = pitch_pivot.global_position
	var to:   Vector3 = arm_end.global_position

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World geometry layer only.
	if _owner_character:
		query.exclude = [_owner_character]

	var result: Dictionary = space.intersect_ray(query)
	var target_arm: float  = config.default_arm_length

	if not result.is_empty():
		var hit_dist: float = from.distance_to(result.position)
		target_arm = hit_dist - config.collision_margin

	_arm_length = lerpf(_arm_length, maxf(target_arm, config.min_arm_length),
		config.collision_lerp_speed * get_process_delta_time())


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		_shake_offset = Vector3.ZERO
		return

	var shake: float = _trauma * _trauma  # Quadratic for nicer falloff.
	var max_shake: float = config.max_shake_degrees
	_shake_offset = Vector3(
		randf_range(-max_shake, max_shake),
		randf_range(-max_shake, max_shake),
		0.0
	) * shake

	_trauma = maxf(0.0, _trauma - config.trauma_decay * delta)


func _update_lean(delta: float) -> void:
	if not camera:
		return
	var target_roll: float = deg_to_rad(config.lean_angle * _lean)
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, 10.0 * delta)

	# Free-look horizontal offset.
	var target_free_offset: float = _free_look_yaw / config.free_look_clamp * config.free_look_horizontal_offset
	camera.h_offset = lerpf(camera.h_offset, target_free_offset, 8.0 * delta)


func _apply_position() -> void:
	if not pitch_pivot:
		return
	pitch_pivot.rotation.x = pitch

	# Apply shake to pitch pivot.
	if _trauma > 0.0:
		pitch_pivot.rotation_degrees.x += _shake_offset.x
		rotation_degrees.y += _shake_offset.y

	# Apply arm length.
	if camera and arm_end:
		var arm_dir: Vector3 = (arm_end.global_position - pitch_pivot.global_position).normalized()
		camera.global_position = pitch_pivot.global_position + arm_dir * _arm_length


func _on_screen_shake_requested(intensity: float, _duration: float) -> void:
	add_trauma(intensity * 0.5)
