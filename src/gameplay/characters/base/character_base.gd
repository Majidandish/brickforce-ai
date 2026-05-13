## =============================================================================
## CharacterBase — Universal Character Foundation (Base Class)
## =============================================================================
## Purpose:
##   Root class for ALL characters: player, AI squad mates, and enemies.
##   Implements the ECS-inspired component model: health, movement, status
##   effects, equipment slots, and faction logic are modular and overrideable.
##   Network-ready: all state changes go through authoritative methods.
##
## Extend this for: PlayerCharacter, AICharacter, BossCharacter, etc.
## =============================================================================

class_name CharacterBase
extends CharacterBody3D

# ── Configuration Resource ─────────────────────────────────────────────────────
@export var character_data: CharacterData

# ── Node References (set in scene) ────────────────────────────────────────────
@onready var skeleton: Skeleton3D         = $Skeleton3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var hitbox_root: Node3D          = $Hitboxes
@onready var equipment_root: Node3D       = $Equipment
@onready var vfx_root: Node3D             = $VFX
@onready var audio_root: Node3D           = $Audio
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# ── Identity ───────────────────────────────────────────────────────────────────
var character_id: int    = -1  # Unique runtime ID
var peer_id: int         = -1  # Network peer ID (1 = server/offline)
var faction: int         = 0   # 0=player 1=ally 2=enemy 3=neutral

# ── Vital Stats ───────────────────────────────────────────────────────────────
var max_health: float    = 100.0
var current_health: float = 100.0
var max_armor: float     = 0.0
var current_armor: float = 0.0
var is_alive: bool       = true
var is_downed: bool      = false   # Knocked but revivable.
var is_immune: bool      = false   # God mode / cinematic.

# ── Movement ──────────────────────────────────────────────────────────────────
var base_move_speed: float   = 5.0
var sprint_multiplier: float = 1.7
var crouch_multiplier: float = 0.55
var aim_multiplier: float    = 0.65
var current_speed: float     = 5.0
var gravity: float           = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching: bool       = false
var is_sprinting: bool       = false
var is_aiming: bool          = false
var is_prone: bool           = false

# ── Equipment ─────────────────────────────────────────────────────────────────
var primary_weapon: Node      = null
var secondary_weapon: Node    = null
var active_weapon: Node       = null
var held_items: Dictionary    = {}   # slot -> Node

# ── Status Effects ─────────────────────────────────────────────────────────────
var status_effects: Array[Dictionary] = []
# Each: { id, type, value, duration, remaining, source_id }

# ── Signals ───────────────────────────────────────────────────────────────────
signal health_changed(old_hp: float, new_hp: float)
signal armor_changed(old_armor: float, new_armor: float)
signal died(killer_id: int, cause: String)
signal downed(attacker_id: int)
signal revived(reviver_id: int)
signal weapon_changed(old_weapon: Node, new_weapon: Node)
signal status_effect_added(effect: Dictionary)
signal status_effect_removed(effect_id: String)


func _ready() -> void:
	_initialize_from_data()
	_setup_components()
	Logger.debug("CharacterBase", "Character ready: ID=%d faction=%d" % [character_id, faction])


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_process_gravity(delta)
	_process_status_effects(delta)
	_apply_movement(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Apply damage. Handles armor absorption, downed state, and death.
func take_damage(amount: float, attacker_id: int = -1, cause: String = "unknown", hit_point: Vector3 = Vector3.ZERO, bone: String = "") -> void:
	if not is_alive or is_immune:
		return

	# God mode check (dev tool).
	if get_meta("god_mode", false):
		return

	# Armor absorption (armor absorbs 60% of damage).
	var armor_absorbed: float = 0.0
	if current_armor > 0.0:
		armor_absorbed = min(amount * 0.6, current_armor)
		current_armor  = max(0.0, current_armor - armor_absorbed)
		armor_changed.emit(current_armor + armor_absorbed, current_armor)

	var actual_damage: float = amount - armor_absorbed
	var old_hp: float        = current_health
	current_health           = max(0.0, current_health - actual_damage)

	health_changed.emit(old_hp, current_health)
	EventBus.player_took_damage.emit(character_id, actual_damage, cause)
	EventBus.hit_registered.emit(character_id, attacker_id, actual_damage, hit_point, bone)
	EventBus.damage_number_requested.emit(hit_point, actual_damage, false)
	VFXManager.play("blood_spray", hit_point)

	if current_health <= 0.0:
		if _can_be_downed():
			_enter_downed_state(attacker_id)
		else:
			_die(attacker_id, cause)


## Heal the character. Cannot exceed max_health.
func heal(amount: float, source: String = "medkit") -> void:
	if not is_alive:
		return
	var old_hp: float  = current_health
	current_health     = min(max_health, current_health + amount)
	health_changed.emit(old_hp, current_health)
	EventBus.player_healed.emit(character_id, current_health - old_hp)


## Restore armor.
func restore_armor(amount: float) -> void:
	var old: float   = current_armor
	current_armor    = min(max_armor, current_armor + amount)
	armor_changed.emit(old, current_armor)


## Add a status effect (stun, poison, burn, slow…).
func apply_status_effect(effect: Dictionary) -> void:
	# Remove existing instance of same type.
	remove_status_effect(effect.get("id", ""))
	var e: Dictionary = effect.duplicate()
	e["remaining"] = e.get("duration", 1.0)
	status_effects.append(e)
	status_effect_added.emit(e)
	Logger.debug("CharacterBase", "Status effect applied: %s" % e.get("id", "?"))


## Remove a status effect by ID.
func remove_status_effect(effect_id: String) -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		if status_effects[i].get("id", "") == effect_id:
			var removed: Dictionary = status_effects[i]
			status_effects.remove_at(i)
			status_effect_removed.emit(effect_id)
			Logger.debug("CharacterBase", "Status effect removed: %s" % effect_id)
			return


## Revive from downed state.
func revive(reviver_id: int) -> void:
	if not is_downed:
		return
	is_downed      = false
	is_alive       = true
	current_health = max_health * 0.3  # Revive at 30% HP.
	health_changed.emit(0.0, current_health)
	revived.emit(reviver_id)
	EventBus.player_revived.emit(character_id, reviver_id)
	Logger.info("CharacterBase", "Revived: %d by %d" % [character_id, reviver_id])


## Equip a weapon node into the active slot.
func equip_weapon(weapon: Node, slot: String = "primary") -> void:
	var old: Node   = active_weapon
	active_weapon   = weapon
	weapon_changed.emit(old, weapon)
	EventBus.weapon_switched.emit(character_id, old.name if old else "", weapon.name if weapon else "")


## Get normalized health (0.0-1.0).
func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


## Returns true if this character is an enemy of another.
func is_enemy_of(other: CharacterBase) -> bool:
	if faction == 3 or other.faction == 3:
		return false  # Neutral faction — never enemies.
	return faction != other.faction


# ── Overrideable Hooks ─────────────────────────────────────────────────────────
## Called every physics frame — override in subclasses for unique movement.
func _apply_movement(_delta: float) -> void:
	pass


## Override to provide custom death behavior.
func _on_death(_killer_id: int, _cause: String) -> void:
	pass


## Override to allow/deny downed state (e.g. enemies don't get downed).
func _can_be_downed() -> bool:
	return faction == 0 or faction == 1


# ── Internal ───────────────────────────────────────────────────────────────────

func _initialize_from_data() -> void:
	if not character_data:
		return
	max_health       = character_data.max_health
	current_health   = character_data.max_health
	max_armor        = character_data.base_armor
	base_move_speed  = character_data.move_speed
	sprint_multiplier = character_data.sprint_multiplier
	faction          = character_data.faction


func _setup_components() -> void:
	current_speed = base_move_speed


func _process_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = max(velocity.y, 0.0)


func _process_status_effects(delta: float) -> void:
	for i in range(status_effects.size() - 1, -1, -1):
		var effect: Dictionary = status_effects[i]
		effect["remaining"] -= delta
		_apply_status_effect_tick(effect, delta)
		if effect.remaining <= 0.0:
			remove_status_effect(effect.get("id", ""))


func _apply_status_effect_tick(effect: Dictionary, delta: float) -> void:
	match effect.get("type", ""):
		"poison":  take_damage(effect.get("value", 2.0) * delta, effect.get("source_id", -1), "poison")
		"burn":    take_damage(effect.get("value", 5.0) * delta, effect.get("source_id", -1), "fire")
		"heal_over_time": heal(effect.get("value", 5.0) * delta, "regen")
		"slow":   current_speed = base_move_speed * (1.0 - effect.get("value", 0.3))


func _enter_downed_state(attacker_id: int) -> void:
	is_downed      = true
	current_health = 0.0
	downed.emit(attacker_id)
	EventBus.player_downed.emit(character_id, attacker_id)
	Logger.info("CharacterBase", "Character downed: %d" % character_id)


func _die(killer_id: int, cause: String) -> void:
	is_alive       = false
	is_downed      = false
	current_health = 0.0
	died.emit(killer_id, cause)
	EventBus.player_died.emit(character_id, killer_id, cause)
	EventBus.kill_registered.emit(killer_id, character_id, active_weapon.name if active_weapon else "unknown")
	_on_death(killer_id, cause)
	Logger.info("CharacterBase", "Character died: %d killed by %d (%s)" % [character_id, killer_id, cause])
