## =============================================================================
## PlayerCharacter — Human-Controlled Character (extends CharacterBase)
## =============================================================================
## Purpose:
##   The locally-controlled player. Reads from InputManager, drives the
##   3D camera, handles weapon swapping, interact traces, and broadcasts
##   all state changes through EventBus for network replication readiness.
## =============================================================================

class_name PlayerCharacter
extends CharacterBase

# ── Camera ─────────────────────────────────────────────────────────────────────
@onready var camera_pivot: Node3D        = $CameraPivot
@onready var camera: Camera3D            = $CameraPivot/Camera3D
@onready var interact_ray: RayCast3D     = $InteractRay
@onready var head: Node3D                = $Head

# ── Camera Settings ────────────────────────────────────────────────────────────
const CAMERA_PITCH_MIN: float = -80.0
const CAMERA_PITCH_MAX: float = 70.0
const AIM_FOV: float          = 55.0
const DEFAULT_FOV: float      = 75.0
const FOV_LERP_SPEED: float   = 10.0
const LEAN_ANGLE: float       = 8.0

var _camera_pitch: float   = 0.0
var _target_fov: float     = DEFAULT_FOV
var _is_firing: bool       = false
var _lean_direction: float = 0.0  # -1 left, 0 none, 1 right.

# ── Interact ───────────────────────────────────────────────────────────────────
const INTERACT_RANGE: float = 2.5

# ── Screen Shake ───────────────────────────────────────────────────────────────
var _shake_intensity: float = 0.0
var _shake_duration: float  = 0.0


func _ready() -> void:
	super._ready()
	faction       = 0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.fov    = DEFAULT_FOV

	GameManager.register_local_player(self)
	EventBus.screen_shake_requested.connect(_on_screen_shake)
	Logger.info("PlayerCharacter", "Player ready.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_look(event as InputEventMouseMotion)


func _process(delta: float) -> void:
	super._process(delta)
	_update_camera(delta)
	_update_interact()
	_handle_fire_input()
	_update_screen_shake(delta)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_handle_movement_input(delta)


# ── Override: Movement ─────────────────────────────────────────────────────────

func _apply_movement(delta: float) -> void:
	var move_vec: Vector2 = InputManager.get_move_vector()
	var direction: Vector3 = Vector3.ZERO

	direction += global_basis.z * -move_vec.y
	direction += global_basis.x * move_vec.x

	if direction.length() > 0.0:
		direction = direction.normalized()

	_update_speed_modifiers()
	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()


# ── Input Handlers ─────────────────────────────────────────────────────────────

func _handle_movement_input(delta: float) -> void:
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = character_data.jump_velocity if character_data else 5.0

	# Crouch
	if Input.is_action_just_pressed("crouch"):
		_toggle_crouch()

	# Sprint
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and not is_aiming

	# ADS
	var was_aiming: bool = is_aiming
	is_aiming = Input.is_action_pressed("aim") and active_weapon != null
	if is_aiming != was_aiming:
		_target_fov = AIM_FOV if is_aiming else DEFAULT_FOV

	# Reload
	if Input.is_action_just_pressed("reload") and active_weapon:
		active_weapon.try_reload()

	# Interact
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	# Inventory
	if Input.is_action_just_pressed("open_inventory"):
		EventBus.popup_opened.emit("inventory")

	# Squad command wheel
	if Input.is_action_just_pressed("squad_command"):
		EventBus.popup_opened.emit("squad_wheel")


func _handle_look(event: InputEventMouseMotion) -> void:
	var delta: Vector2 = InputManager.get_look_delta(is_aiming)
	rotate_y(-event.relative.x * delta.x * 0.001)
	_camera_pitch = clampf(_camera_pitch - event.relative.y * delta.y * 0.001,
		deg_to_rad(CAMERA_PITCH_MIN), deg_to_rad(CAMERA_PITCH_MAX))
	if camera_pivot:
		camera_pivot.rotation.x = _camera_pitch


func _handle_fire_input() -> void:
	if not active_weapon:
		return
	if Input.is_action_pressed("fire") and is_aiming:
		_is_firing = active_weapon.try_fire(-camera.global_basis.z)
	elif Input.is_action_just_released("fire"):
		_is_firing = false


func _update_camera(delta: float) -> void:
	if camera:
		camera.fov = lerpf(camera.fov, _target_fov, FOV_LERP_SPEED * delta)


func _update_interact() -> void:
	if not interact_ray or not interact_ray.is_colliding():
		return
	var hit: Node = interact_ray.get_collider()
	if hit and hit.has_method("get_interact_prompt"):
		EventBus.hud_show_requested.emit("interact_prompt")


func _try_interact() -> void:
	if not interact_ray or not interact_ray.is_colliding():
		return
	var hit: Node = interact_ray.get_collider()
	if hit and hit.has_method("interact"):
		hit.interact(self)


func _toggle_crouch() -> void:
	is_crouching = not is_crouching
	var target_scale_y: float = 0.6 if is_crouching else 1.0
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale:y", target_scale_y, 0.15)


func _update_speed_modifiers() -> void:
	current_speed = base_move_speed
	if is_crouching:  current_speed *= crouch_multiplier
	elif is_sprinting: current_speed *= sprint_multiplier
	if is_aiming:      current_speed *= aim_multiplier
	# Active weapon penalty.
	if active_weapon and active_weapon.weapon_data:
		var penalty: float = (
			active_weapon.weapon_data.ads_move_speed_penalty if is_aiming
			else active_weapon.weapon_data.move_speed_penalty
		)
		current_speed *= penalty


func _update_screen_shake(delta: float) -> void:
	if _shake_duration <= 0.0:
		return
	_shake_duration -= delta
	var offset: Vector2 = Vector2(
		randf_range(-1, 1), randf_range(-1, 1)
	) * _shake_intensity * (_shake_duration / max(_shake_duration, 0.001))
	if camera:
		camera.h_offset = offset.x * 0.1
		camera.v_offset = offset.y * 0.1
	if _shake_duration <= 0.0:
		if camera:
			camera.h_offset = 0.0
			camera.v_offset = 0.0


func _on_screen_shake(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration  = duration
