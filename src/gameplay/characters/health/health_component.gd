## =============================================================================
## HealthComponent — Modular Health & Regeneration System
## =============================================================================
## Architecture:
##   Decoupled from CharacterBase. Can be attached to any Node3D entity
##   (character, vehicle, destructible prop). Manages health pools,
##   regeneration delays, over-shield, and temporary HP.
##
##   DamageInfo is a value object passed through the damage pipeline:
##     raw input → DamageProcessor (modifiers) → HealthComponent (apply).
##
##   Network-safe: health value is the authoritative state to replicate.
## =============================================================================

class_name HealthComponent
extends Node

# ── Signals ────────────────────────────────────────────────────────────────────
signal health_changed(old_hp: float, new_hp: float, max_hp: float)
signal killed(killer_id: int, cause: String)
signal downed(attacker_id: int)
signal revived(reviver_id: int)
signal regen_started()
signal regen_stopped()

# ── Configuration ──────────────────────────────────────────────────────────────
@export var max_health: float              = 100.0
@export var can_be_downed: bool            = true
@export var regen_enabled: bool            = false
@export var regen_per_second: float        = 5.0
@export var regen_delay: float             = 5.0   # Seconds after last hit.
@export var regen_threshold: float         = 0.75  # Only regen below this %.
@export var overshield_max: float          = 0.0   # Extra HP beyond max (bonus HP).

# ── State ──────────────────────────────────────────────────────────────────────
var current_health: float   = 100.0
var overshield: float       = 0.0
var is_alive: bool          = true
var is_downed: bool         = false
var is_immune: bool         = false   # True = no damage (cinematics, god mode).

var _regen_timer: float     = 0.0
var _is_regenerating: bool  = false


func _ready() -> void:
	name = "HealthComponent"
	current_health = max_health


func _process(delta: float) -> void:
	_update_regeneration(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Apply processed damage. Returns actual damage dealt.
func apply_damage(amount: float, attacker_id: int = -1, cause: String = "unknown") -> float:
	if not is_alive or is_immune or amount <= 0.0:
		return 0.0

	var old_hp: float = current_health
	var remaining: float = amount

	# Drain overshield first.
	if overshield > 0.0:
		var absorbed: float = minf(remaining, overshield)
		overshield  -= absorbed
		remaining   -= absorbed

	current_health = maxf(0.0, current_health - remaining)
	_stop_regen()
	health_changed.emit(old_hp, current_health, max_health)

	if current_health <= 0.0:
		if can_be_downed and not is_downed:
			_enter_downed(attacker_id)
		else:
			_die(attacker_id, cause)

	return amount - remaining + (old_hp - current_health)


## Heal the entity. Returns actual amount healed.
func heal(amount: float, allow_overheal: bool = false) -> float:
	if not is_alive or amount <= 0.0:
		return 0.0
	var old_hp: float = current_health
	var cap: float    = max_health + (overshield_max if allow_overheal else 0.0)
	current_health    = minf(current_health + amount, cap)
	var healed: float = current_health - old_hp
	if healed > 0.0:
		health_changed.emit(old_hp, current_health, max_health)
	return healed


## Add overshield (bonus HP).
func add_overshield(amount: float) -> void:
	overshield = minf(overshield + amount, overshield_max)


## Revive from downed state.
func revive(reviver_id: int = -1) -> void:
	if not is_downed:
		return
	is_downed      = false
	is_alive       = true
	current_health = max_health * 0.3
	health_changed.emit(0.0, current_health, max_health)
	revived.emit(reviver_id)


## Kill instantly.
func kill(cause: String = "forced") -> void:
	if not is_alive:
		return
	current_health = 0.0
	_die(-1, cause)


## Returns health ratio 0.0-1.0.
func get_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0


## Returns total effective HP (health + overshield).
func get_effective_hp() -> float:
	return current_health + overshield


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_regeneration(delta: float) -> void:
	if not regen_enabled or not is_alive or is_downed:
		return
	if current_health >= max_health * regen_threshold:
		return

	_regen_timer += delta
	if _regen_timer < regen_delay:
		return

	if not _is_regenerating:
		_is_regenerating = true
		regen_started.emit()

	var old_hp: float  = current_health
	current_health     = minf(current_health + regen_per_second * delta, max_health)
	if current_health != old_hp:
		health_changed.emit(old_hp, current_health, max_health)


func _stop_regen() -> void:
	_regen_timer = 0.0
	if _is_regenerating:
		_is_regenerating = false
		regen_stopped.emit()


func _enter_downed(attacker_id: int) -> void:
	is_downed = true
	downed.emit(attacker_id)
	EventBus.player_downed.emit(
		get_parent().character_id if get_parent().has_method("character_id") else -1,
		attacker_id
	)


func _die(killer_id: int, cause: String) -> void:
	is_alive   = false
	is_downed  = false
	killed.emit(killer_id, cause)
	EventBus.player_died.emit(
		get_parent().character_id if get_parent().has_method("character_id") else -1,
		killer_id, cause
	)
