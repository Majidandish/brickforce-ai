## =============================================================================
## DamageProcessor — Damage Modifier Pipeline
## =============================================================================
## Architecture:
##   All incoming damage flows through this processor before reaching
##   HealthComponent. Modifiers are stacked in priority order:
##
##   Raw Damage
##     → Damage Type Resistance (fire/explosive/bullet)
##     → Armor Absorption (ArmorComponent)
##     → Status Effect Multipliers (vulnerable, shielded)
##     → God Mode / Immunity Check
##     → Apply to HealthComponent
##
##   Returns a DamageResult with the final applied damage and metadata.
##
##   Network: server applies damage; clients predict locally.
## =============================================================================

class_name DamageProcessor
extends Node

# ── Damage Types ───────────────────────────────────────────────────────────────
enum DamageType {
	BULLET,
	EXPLOSIVE,
	FIRE,
	POISON,
	SAFE_ZONE,
	MELEE,
	FALL,
	FORCED,
}

const TYPE_NAMES: Dictionary = {
	DamageType.BULLET:    "bullet",
	DamageType.EXPLOSIVE: "explosive",
	DamageType.FIRE:      "fire",
	DamageType.POISON:    "poison",
	DamageType.SAFE_ZONE: "safe_zone",
	DamageType.MELEE:     "melee",
	DamageType.FALL:      "fall",
	DamageType.FORCED:    "forced",
}

signal damage_processed(result: Dictionary)

# ── Resistances (additive, 0.0 = full, 1.0 = immune) ─────────────────────────
var resistances: Dictionary = {
	"bullet":    0.0,
	"explosive": 0.0,
	"fire":      0.0,
	"poison":    0.0,
	"safe_zone": 0.0,
	"melee":     0.0,
	"fall":      0.0,
}

# ── Multipliers (from status effects) ────────────────────────────────────────
var _vulnerability: float = 0.0  # Extra damage taken.
var _damage_reduction: float = 0.0  # Damage absorbed.

# ── References ────────────────────────────────────────────────────────────────
@onready var health: HealthComponent = null
@onready var armor: ArmorComponent   = null


func _ready() -> void:
	name = "DamageProcessor"
	# Find sibling components.
	health = get_parent().find_child("HealthComponent", false, false)
	armor  = get_parent().find_child("ArmorComponent", false, false)


# ── Public API ─────────────────────────────────────────────────────────────────

## Main entry point for all incoming damage.
func receive_damage(info: Dictionary) -> Dictionary:
	var raw: float        = info.get("amount", 0.0)
	var attacker: int     = info.get("attacker_id", -1)
	var cause: String     = info.get("cause", "unknown")
	var is_headshot: bool = info.get("is_headshot", false)
	var type_str: String  = info.get("type", "bullet")

	if raw <= 0.0:
		return {}

	# Immunity / god mode.
	if health and (health.is_immune or not health.is_alive):
		return {}
	if get_parent().has_meta("god_mode") and get_parent().get_meta("god_mode", false):
		return {}

	# 1. Apply resistance.
	var resistance: float = resistances.get(type_str, 0.0)
	var after_resistance: float = raw * (1.0 - clampf(resistance, 0.0, 1.0))

	# 2. Apply armor.
	var after_armor: float = after_resistance
	if armor:
		after_armor = armor.process_damage(after_resistance, is_headshot)

	# 3. Apply status multipliers.
	after_armor *= (1.0 + _vulnerability)
	after_armor *= (1.0 - clampf(_damage_reduction, 0.0, 0.9))

	# 4. Apply to health.
	var actual: float = 0.0
	if health:
		actual = health.apply_damage(after_armor, attacker, cause)

	var result: Dictionary = {
		"raw_damage":      raw,
		"applied_damage":  actual,
		"blocked_by_armor": after_resistance - after_armor,
		"attacker_id":     attacker,
		"cause":           cause,
		"is_headshot":     is_headshot,
		"type":            type_str,
	}

	damage_processed.emit(result)
	EventBus.hit_registered.emit(
		get_parent().character_id if get_parent().has_method("character_id") else -1,
		attacker, actual, info.get("hit_point", Vector3.ZERO), info.get("bone", "")
	)

	return result


## Add/remove a resistance modifier.
func set_resistance(damage_type: String, value: float) -> void:
	resistances[damage_type] = clampf(value, 0.0, 1.0)


## Set temporary vulnerability (damage multiplier increase).
func set_vulnerability(multiplier: float) -> void:
	_vulnerability = maxf(0.0, multiplier)


## Set damage reduction (e.g. from shield ability).
func set_damage_reduction(reduction: float) -> void:
	_damage_reduction = clampf(reduction, 0.0, 0.9)
