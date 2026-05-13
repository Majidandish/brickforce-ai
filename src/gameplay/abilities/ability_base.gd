## =============================================================================
## AbilityBase — Abstract Ability / Active Skill System
## =============================================================================
## Purpose:
##   Foundation for all character abilities: active skills, passives,
##   tactical gadgets, and squad commands. Handles cooldowns, resource cost,
##   charge stacking, and networked activation.
## =============================================================================

class_name AbilityBase
extends Node

enum AbilityType { ACTIVE, PASSIVE, TOGGLE, CHARGED }

# ── Configuration ──────────────────────────────────────────────────────────────
@export var ability_id: String          = "ability_default"
@export var display_name: String        = "Unknown Ability"
@export var description: String         = ""
@export var ability_type: AbilityType   = AbilityType.ACTIVE
@export var cooldown: float             = 10.0
@export var cast_time: float            = 0.0    # 0 = instant.
@export var resource_cost: float        = 0.0
@export var charges: int                = 1      # Max charge stacks.
@export var range: float                = 0.0    # 0 = self-cast.
@export var icon: Texture2D             = null

# ── Runtime State ──────────────────────────────────────────────────────────────
var owner_character: CharacterBase = null
var current_charges: int          = 1
var cooldown_remaining: float     = 0.0
var is_active_toggle: bool        = false
var is_casting: bool              = false

signal ability_activated(ability_id: String)
signal ability_cancelled(ability_id: String)
signal cooldown_complete(ability_id: String)
signal charge_changed(current: int, max_charges: int)


func _ready() -> void:
	current_charges = charges


func _process(delta: float) -> void:
	_update_cooldown(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Attempt to activate the ability.
func try_activate(target: Variant = null) -> bool:
	if not can_activate():
		return false
	if cast_time > 0.0:
		_start_cast(target)
	else:
		_activate(target)
	return true


## Returns true if the ability can be activated right now.
func can_activate() -> bool:
	if cooldown_remaining > 0.0:
		return false
	if current_charges <= 0:
		return false
	if is_casting:
		return false
	if not _check_resource_cost():
		return false
	return true


## Cancel a cast in progress.
func cancel() -> void:
	if is_casting:
		is_casting = false
		ability_cancelled.emit(ability_id)


## Force reset cooldown (dev tool / game event).
func reset_cooldown() -> void:
	cooldown_remaining = 0.0
	if current_charges < charges:
		current_charges += 1
	charge_changed.emit(current_charges, charges)


## Get cooldown progress 0.0-1.0 (1.0 = ready).
func get_cooldown_progress() -> float:
	if cooldown <= 0.0:
		return 1.0
	return 1.0 - (cooldown_remaining / cooldown)


# ── Overrideable ───────────────────────────────────────────────────────────────

## Override this to implement the ability effect.
func _on_activate(_target: Variant) -> void:
	pass


## Override to define what "ready" means for passive abilities.
func _on_passive_tick(_delta: float) -> void:
	pass


# ── Internal ───────────────────────────────────────────────────────────────────

func _activate(target: Variant) -> void:
	_spend_charge()
	_spend_resource()
	_on_activate(target)
	_start_cooldown()
	ability_activated.emit(ability_id)


func _start_cast(target: Variant) -> void:
	is_casting = true
	TimeManager.register_timer(
		"cast_%s_%d" % [ability_id, get_instance_id()],
		cast_time,
		func(): _finish_cast(target)
	)


func _finish_cast(target: Variant) -> void:
	is_casting = false
	_activate(target)


func _start_cooldown() -> void:
	cooldown_remaining = cooldown


func _update_cooldown(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = max(0.0, cooldown_remaining - delta)
		if cooldown_remaining == 0.0:
			if current_charges < charges:
				current_charges += 1
				charge_changed.emit(current_charges, charges)
			cooldown_complete.emit(ability_id)
	if ability_type == AbilityType.PASSIVE:
		_on_passive_tick(delta)


func _spend_charge() -> void:
	current_charges = max(0, current_charges - 1)
	charge_changed.emit(current_charges, charges)


func _spend_resource() -> void:
	pass  # TODO: hook into character stamina/energy system.


func _check_resource_cost() -> bool:
	return true  # TODO: validate against character resources.
