## =============================================================================
## WeaponBase — Universal Weapon Component System (Base Class)
## =============================================================================
## Purpose:
##   Foundation for all weapons. Handles fire modes, recoil, spread,
##   ammo management, reload state machines, and projectile/hitscan dispatch.
##   Designed as a composable Node3D attached to a character's hand bone.
##   Network-ready: authoritative fire/reload calls via RPC-safe methods.
##
## Extend for: RifleWeapon, ShotgunWeapon, SniperWeapon, GrenadeWeapon, etc.
## =============================================================================

class_name WeaponBase
extends Node3D

# ── Configuration ──────────────────────────────────────────────────────────────
@export var weapon_data: WeaponData

# ── Node References ────────────────────────────────────────────────────────────
@onready var muzzle_point: Marker3D   = $MuzzlePoint
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var raycast: RayCast3D       = $RayCast3D

# ── Fire Modes ─────────────────────────────────────────────────────────────────
enum FireMode { SEMI, BURST, AUTO, BOLT_ACTION, PUMP }

# ── Reload States ─────────────────────────────────────────────────────────────
enum ReloadState { IDLE, RELOADING, INTERRUPTED }

# ── Runtime State ─────────────────────────────────────────────────────────────
var owner_character: CharacterBase = null
var weapon_id: String     = ""
var current_ammo: int     = 0
var reserve_ammo: int     = 0
var fire_mode: FireMode   = FireMode.AUTO
var reload_state: ReloadState = ReloadState.IDLE
var is_equipped: bool     = false
var can_fire: bool        = true

# ── Internal Timers ────────────────────────────────────────────────────────────
var _fire_cooldown: float   = 0.0
var _burst_shots_left: int  = 0
var _burst_timer: float     = 0.0
var _reload_timer: float    = 0.0
var _current_spread: float  = 0.0   # Accumulated spread (bloom).

# ── Signals ───────────────────────────────────────────────────────────────────
signal fired(position: Vector3, direction: Vector3)
signal reloaded()
signal reload_started()
signal ammo_changed(current: int, reserve: int)
signal weapon_empty()
signal weapon_equipped(character: CharacterBase)
signal weapon_unequipped()


func _ready() -> void:
	_initialize_from_data()
	Logger.debug("WeaponBase", "Weapon ready: %s" % weapon_id)


func _process(delta: float) -> void:
	_update_fire_cooldown(delta)
	_update_reload(delta)
	_update_spread(delta)
	if _burst_shots_left > 0:
		_update_burst(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Attempt to fire. Called by character input or AI.
func try_fire(direction: Vector3 = Vector3.FORWARD) -> bool:
	if not can_fire or _fire_cooldown > 0.0:
		return false
	if reload_state == ReloadState.RELOADING:
		return false
	if current_ammo <= 0:
		_on_empty()
		return false

	match fire_mode:
		FireMode.SEMI:      _fire_once(direction)
		FireMode.AUTO:      _fire_once(direction)
		FireMode.BURST:     _start_burst(direction)
		FireMode.BOLT_ACTION: _fire_once(direction)
		FireMode.PUMP:      _fire_once(direction)

	return true


## Attempt to reload. Returns false if already full or reloading.
func try_reload() -> bool:
	if reload_state == ReloadState.RELOADING:
		return false
	if reserve_ammo <= 0:
		return false
	if current_ammo == weapon_data.mag_size if weapon_data else 30:
		return false
	_start_reload()
	return true


## Interrupt a reload (e.g. on fire while reloading in a pump shotgun).
func interrupt_reload() -> void:
	if reload_state == ReloadState.RELOADING:
		reload_state = ReloadState.INTERRUPTED
		_reload_timer = 0.0
		Logger.debug("WeaponBase", "Reload interrupted: %s" % weapon_id)


## Equip this weapon (called by character when switching).
func equip(character: CharacterBase) -> void:
	owner_character = character
	is_equipped     = true
	show()
	if animation_player and animation_player.has_animation("equip"):
		animation_player.play("equip")
	weapon_equipped.emit(character)


## Unequip (holster) this weapon.
func unequip() -> void:
	interrupt_reload()
	is_equipped     = false
	hide()
	weapon_unequipped.emit()


## Add ammo to reserve.
func add_ammo(amount: int) -> int:
	var cap: int  = (weapon_data.reserve_max if weapon_data else 240)
	var added: int = min(amount, cap - reserve_ammo)
	reserve_ammo  += added
	ammo_changed.emit(current_ammo, reserve_ammo)
	return added


## Get ammo state.
func get_ammo_state() -> Dictionary:
	return { "current": current_ammo, "reserve": reserve_ammo, "mag_size": _mag_size() }


## Switch fire mode (cycles through available modes).
func cycle_fire_mode() -> void:
	if not weapon_data or weapon_data.available_fire_modes.size() <= 1:
		return
	var modes: Array = weapon_data.available_fire_modes
	var current_idx: int = modes.find(fire_mode)
	fire_mode = modes[(current_idx + 1) % modes.size()]
	Logger.info("WeaponBase", "Fire mode: %s → %s" % [FireMode.keys()[fire_mode], weapon_id])


# ── Overrideable ───────────────────────────────────────────────────────────────

## Override for custom projectile / hitscan behavior.
func _perform_shot(direction: Vector3) -> void:
	if weapon_data and weapon_data.is_hitscan:
		_perform_hitscan(direction)
	else:
		_spawn_projectile(direction)


## Override for custom muzzle flash / animation.
func _on_fire_fx() -> void:
	VFXManager.play("muzzle_flash_rifle", muzzle_point.global_position, muzzle_point.global_rotation)
	AudioManager.play_sfx_at(weapon_data.fire_sound if weapon_data else "res://assets/audio/sfx/rifle_fire.ogg",
		muzzle_point.global_position)
	EventBus.weapon_fired.emit(
		owner_character.character_id if owner_character else -1,
		weapon_id,
		muzzle_point.global_position,
		muzzle_point.global_basis.z
	)


# ── Internal ───────────────────────────────────────────────────────────────────

func _initialize_from_data() -> void:
	if not weapon_data:
		return
	weapon_id    = weapon_data.weapon_id
	fire_mode    = weapon_data.default_fire_mode as FireMode
	current_ammo = weapon_data.mag_size
	reserve_ammo = weapon_data.reserve_max
	ammo_changed.emit(current_ammo, reserve_ammo)


func _fire_once(direction: Vector3) -> void:
	var spread_dir: Vector3 = _apply_spread(direction)
	_perform_shot(spread_dir)
	_on_fire_fx()
	current_ammo  -= 1
	_fire_cooldown = 60.0 / float(weapon_data.rpm if weapon_data else 600)
	_current_spread = min(_current_spread + (weapon_data.spread_per_shot if weapon_data else 0.5), 5.0)
	ammo_changed.emit(current_ammo, reserve_ammo)
	fired.emit(muzzle_point.global_position, spread_dir)

	if animation_player and animation_player.has_animation("fire"):
		animation_player.play("fire")


func _start_burst(direction: Vector3) -> void:
	_burst_shots_left = weapon_data.burst_count if weapon_data else 3
	_fire_once(direction)
	_burst_shots_left -= 1


func _update_burst(delta: float) -> void:
	_burst_timer -= delta
	if _burst_timer <= 0.0 and _burst_shots_left > 0 and current_ammo > 0:
		var burst_delay: float = 60.0 / float((weapon_data.rpm if weapon_data else 600) * 2)
		_burst_timer = burst_delay
		var dir: Vector3 = -global_basis.z
		_fire_once(dir)
		_burst_shots_left -= 1


func _start_reload() -> void:
	reload_state  = ReloadState.RELOADING
	_reload_timer = weapon_data.reload_time if weapon_data else 2.0
	reload_started.emit()
	if animation_player and animation_player.has_animation("reload"):
		animation_player.play("reload")
	EventBus.weapon_reloaded.emit(
		owner_character.character_id if owner_character else -1, weapon_id
	)
	AudioManager.play_sfx_at(
		weapon_data.reload_sound if weapon_data else "",
		global_position
	)
	Logger.debug("WeaponBase", "Reload started: %s" % weapon_id)


func _update_reload(delta: float) -> void:
	if reload_state != ReloadState.RELOADING:
		return
	_reload_timer -= delta
	if _reload_timer <= 0.0:
		_finish_reload()


func _finish_reload() -> void:
	var needed: int  = _mag_size() - current_ammo
	var actual: int  = min(needed, reserve_ammo)
	current_ammo    += actual
	reserve_ammo    -= actual
	reload_state     = ReloadState.IDLE
	ammo_changed.emit(current_ammo, reserve_ammo)
	reloaded.emit()
	Logger.debug("WeaponBase", "Reload complete: %s (%d/%d)" % [weapon_id, current_ammo, reserve_ammo])


func _update_fire_cooldown(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = max(0.0, _fire_cooldown - delta)


func _update_spread(delta: float) -> void:
	var recovery: float = weapon_data.spread_recovery if weapon_data else 2.0
	_current_spread = max(0.0, _current_spread - recovery * delta)


func _apply_spread(direction: Vector3) -> Vector3:
	var base_spread: float = weapon_data.base_spread if weapon_data else 0.5
	var total: float = base_spread + _current_spread
	var rand_x: float = randf_range(-total, total) * 0.01
	var rand_y: float = randf_range(-total, total) * 0.01
	return (direction + Vector3(rand_x, rand_y, 0.0)).normalized()


func _perform_hitscan(direction: Vector3) -> void:
	if not raycast:
		return
	raycast.target_position = direction * (weapon_data.range if weapon_data else 200.0)
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var hit_node: Node = raycast.get_collider()
		var hit_point: Vector3 = raycast.get_collision_point()
		var hit_normal: Vector3 = raycast.get_collision_normal()
		var damage: float = weapon_data.damage if weapon_data else 25.0
		var is_headshot: bool = hit_node.has_meta("is_head_hitbox") and hit_node.get_meta("is_head_hitbox")
		if is_headshot:
			damage *= (weapon_data.headshot_multiplier if weapon_data else 2.5)
			EventBus.headshot_registered.emit(
				hit_node.get_parent().character_id if hit_node.get_parent() is CharacterBase else -1,
				owner_character.character_id if owner_character else -1
			)

		if hit_node.get_parent() is CharacterBase:
			var target: CharacterBase = hit_node.get_parent() as CharacterBase
			target.take_damage(damage, owner_character.character_id if owner_character else -1, "bullet", hit_point, hit_node.name)
			VFXManager.play("bullet_impact_flesh", hit_point)
		else:
			VFXManager.play("bullet_impact_concrete", hit_point)
			VFXManager.place_decal("bullet_hole_concrete", hit_point, hit_normal)


func _spawn_projectile(_direction: Vector3) -> void:
	# TODO: Acquire from ObjectPool and launch.
	pass


func _on_empty() -> void:
	weapon_empty.emit()
	AudioManager.play_sfx_at("res://assets/audio/sfx/weapon_empty_click.ogg", global_position)


func _mag_size() -> int:
	return weapon_data.mag_size if weapon_data else 30
