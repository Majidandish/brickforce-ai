## =============================================================================
## AnimationController — Character Animation State Machine Bridge
## =============================================================================
## Architecture:
##   Connects game state to AnimationTree parameters. Uses a data-driven
##   parameter mapping so animation logic lives in the AnimationTree,
##   not in code. Code only sets parameters; Godot blend trees handle blending.
##
##   Layer system:
##     Layer 0 (Base): locomotion (idle/walk/sprint/crouch/prone/airborne)
##     Layer 1 (Upper): weapon handling (idle/aim/fire/reload/equip)
##     Layer 2 (Additive): hit reactions, breathing, sway
##
##   All parameters are typed enums → float values for the blend tree.
##   Network: parameters are NOT replicated; each client plays locally.
## =============================================================================

class_name AnimationController
extends Node

# ── AnimationTree Parameter Keys ──────────────────────────────────────────────
const PARAM_MOVE_SPEED:      String = "parameters/base_blend/blend_position"
const PARAM_IS_GROUNDED:     String = "parameters/base_blend/grounded"
const PARAM_IS_CROUCHING:    String = "parameters/base_blend/crouching"
const PARAM_IS_PRONE:        String = "parameters/base_blend/prone"
const PARAM_MOVEMENT_DIR:    String = "parameters/base_blend/strafe"
const PARAM_AIR_TIME:        String = "parameters/air_blend/air_time"

const PARAM_WEAPON_STATE:    String = "parameters/upper_blend/weapon_state"
const PARAM_IS_AIMING:       String = "parameters/upper_blend/aiming"
const PARAM_FIRE_SHOT:       String = "parameters/upper_blend/fire_oneshot"
const PARAM_RELOAD_TRIGGER:  String = "parameters/upper_blend/reload_trigger"
const PARAM_EQUIP_TRIGGER:   String = "parameters/upper_blend/equip_trigger"
const PARAM_WEAPON_TYPE:     String = "parameters/upper_blend/weapon_type"

const PARAM_HIT_DIRECTION:   String = "parameters/additive_blend/hit_dir"
const PARAM_HIT_TRIGGER:     String = "parameters/additive_blend/hit_trigger"
const PARAM_BREATHING:       String = "parameters/additive_blend/breathing"

# ── Weapon Type Constants (blend tree float) ──────────────────────────────────
enum WeaponAnimType { NONE, RIFLE, PISTOL, SHOTGUN, SNIPER, MELEE, THROWABLE }

# ── References ────────────────────────────────────────────────────────────────
@onready var anim_tree: AnimationTree = $AnimationTree
var owner_character: CharacterBase    = null
var movement: MovementComponent       = null
var weapon_handler: WeaponHandler     = null

# ── State Cache ────────────────────────────────────────────────────────────────
var _prev_speed: float    = 0.0
var _breathing_time: float = 0.0
const BREATHING_SPEED: float = 0.8
const BREATHING_AMP: float   = 0.4


func _ready() -> void:
	name = "AnimationController"


func _process(delta: float) -> void:
	if not anim_tree or not anim_tree.active:
		return
	_update_locomotion()
	_update_upper_body()
	_update_additive(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with the owning character and its sub-components.
func initialize(
	character: CharacterBase,
	move_comp: MovementComponent,
	wh: WeaponHandler
) -> void:
	owner_character = character
	movement        = move_comp
	weapon_handler  = wh

	if anim_tree:
		anim_tree.active = true

	# Connect weapon events.
	if weapon_handler:
		weapon_handler.weapon_drawn.connect(_on_weapon_drawn)
		weapon_handler.weapon_holstered.connect(_on_weapon_holstered)
		weapon_handler.ammo_changed.connect(_on_ammo_changed)


## Trigger fire animation (called by weapon on shot).
func play_fire() -> void:
	_set_param(PARAM_FIRE_SHOT, true)


## Trigger reload animation.
func play_reload() -> void:
	_set_param(PARAM_RELOAD_TRIGGER, true)


## Trigger hit reaction in a direction.
func play_hit(direction: Vector3) -> void:
	var local_dir: Vector3 = owner_character.global_basis.inverse() * direction
	var angle: float = atan2(local_dir.x, local_dir.z)
	_set_param(PARAM_HIT_DIRECTION, angle)
	_set_param(PARAM_HIT_TRIGGER, true)


## Force a specific weapon animation type.
func set_weapon_type(weapon_type: WeaponAnimType) -> void:
	_set_param(PARAM_WEAPON_TYPE, float(weapon_type))


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_locomotion() -> void:
	if not movement:
		return

	var speed_ratio: float = movement.get_speed_ratio()
	_set_param(PARAM_MOVE_SPEED, speed_ratio)
	_set_param(PARAM_IS_GROUNDED, movement.is_grounded)
	_set_param(PARAM_IS_CROUCHING, movement.is_crouching)
	_set_param(PARAM_IS_PRONE, movement.is_prone)
	_set_param(PARAM_AIR_TIME, movement.air_time)

	# Strafe direction (for sidestep blend).
	if owner_character:
		var vel: Vector3 = movement.horizontal_velocity
		if vel.length() > 0.1:
			var local_vel: Vector3 = owner_character.global_basis.inverse() * vel
			_set_param(PARAM_MOVEMENT_DIR, Vector2(local_vel.x, -local_vel.z).normalized())


func _update_upper_body() -> void:
	if not owner_character:
		return
	_set_param(PARAM_IS_AIMING, owner_character.is_aiming)


func _update_additive(delta: float) -> void:
	# Breathing idle sway.
	if not movement or not movement.is_moving():
		_breathing_time += delta
		var breath: float = sin(_breathing_time * BREATHING_SPEED) * BREATHING_AMP
		_set_param(PARAM_BREATHING, breath)
	else:
		_breathing_time = 0.0
		_set_param(PARAM_BREATHING, 0.0)


func _set_param(param: String, value: Variant) -> void:
	if anim_tree:
		anim_tree.set(param, value)


func _on_weapon_drawn(weapon: WeaponBase, _slot: String) -> void:
	_set_param(PARAM_EQUIP_TRIGGER, true)
	if weapon.weapon_data:
		var atype: WeaponAnimType = _weapon_data_to_anim_type(weapon.weapon_data)
		set_weapon_type(atype)


func _on_weapon_holstered(_weapon: WeaponBase, _slot: String) -> void:
	set_weapon_type(WeaponAnimType.NONE)


func _on_ammo_changed(_slot: String, _current: int, _reserve: int) -> void:
	pass  # Ammo numbers handled by HUD.


func _weapon_data_to_anim_type(wd: WeaponData) -> WeaponAnimType:
	match wd.weapon_class:
		0: return WeaponAnimType.RIFLE     # Assault Rifle
		1: return WeaponAnimType.RIFLE     # SMG
		2: return WeaponAnimType.SNIPER
		3: return WeaponAnimType.SHOTGUN
		4: return WeaponAnimType.PISTOL
		5: return WeaponAnimType.MELEE
		6: return WeaponAnimType.THROWABLE
		_: return WeaponAnimType.RIFLE
