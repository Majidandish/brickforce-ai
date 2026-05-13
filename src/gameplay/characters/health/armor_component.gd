## =============================================================================
## ArmorComponent — Layered Armor Absorption System
## =============================================================================
## Architecture:
##   Three armor slots: helmet, vest, backpack (damage absorption only).
##   Each slot has durability that degrades with hits.
##   Armor tiers: 0=none, 1=basic(30%), 2=enhanced(50%), 3=military(65%).
##
##   Called by DamageProcessor before damage reaches HealthComponent.
##   Returns the reduced damage amount after absorption.
## =============================================================================

class_name ArmorComponent
extends Node

enum ArmorTier { NONE, BASIC, ENHANCED, MILITARY }

const TIER_ABSORPTION: Dictionary = {
	ArmorTier.NONE:     0.0,
	ArmorTier.BASIC:    0.30,
	ArmorTier.ENHANCED: 0.50,
	ArmorTier.MILITARY: 0.65,
}

const TIER_MAX_DURABILITY: Dictionary = {
	ArmorTier.NONE:     0.0,
	ArmorTier.BASIC:    100.0,
	ArmorTier.ENHANCED: 200.0,
	ArmorTier.MILITARY: 300.0,
}

signal armor_changed(slot: String, old_dur: float, new_dur: float, tier: ArmorTier)
signal armor_broken(slot: String)

# ── Slots ──────────────────────────────────────────────────────────────────────
var helmet_tier: ArmorTier       = ArmorTier.NONE
var helmet_durability: float     = 0.0
var vest_tier: ArmorTier         = ArmorTier.NONE
var vest_durability: float       = 0.0


func _ready() -> void:
	name = "ArmorComponent"


# ── Public API ─────────────────────────────────────────────────────────────────

## Process incoming damage through armor. Returns the reduced damage.
## is_headshot: whether to use helmet instead of vest.
func process_damage(raw_damage: float, is_headshot: bool = false) -> float:
	var slot: String  = "helmet" if is_headshot else "vest"
	var tier: ArmorTier = helmet_tier if is_headshot else vest_tier
	var durability: float = helmet_durability if is_headshot else vest_durability

	if tier == ArmorTier.NONE or durability <= 0.0:
		return raw_damage

	var absorption: float = TIER_ABSORPTION[tier]
	var absorbed: float   = raw_damage * absorption
	var reduced: float    = raw_damage - absorbed

	# Durability degrades.
	var dur_damage: float = absorbed * 0.5
	_apply_durability_damage(slot, dur_damage, tier)

	return reduced


## Equip armor in a slot.
func equip_armor(slot: String, tier: ArmorTier) -> void:
	match slot:
		"helmet":
			helmet_tier       = tier
			helmet_durability = TIER_MAX_DURABILITY[tier]
		"vest":
			vest_tier       = tier
			vest_durability = TIER_MAX_DURABILITY[tier]
	Logger.debug("ArmorComponent", "Equipped %s tier %d." % [slot, tier])


## Repair armor (medstation or repair kit).
func repair(slot: String, amount: float) -> void:
	match slot:
		"helmet":
			var old: float    = helmet_durability
			helmet_durability = minf(helmet_durability + amount, TIER_MAX_DURABILITY[helmet_tier])
			armor_changed.emit(slot, old, helmet_durability, helmet_tier)
		"vest":
			var old: float  = vest_durability
			vest_durability = minf(vest_durability + amount, TIER_MAX_DURABILITY[vest_tier])
			armor_changed.emit(slot, old, vest_durability, vest_tier)


## Returns total effective armor (0.0-1.0) for UI display.
func get_combined_absorption() -> float:
	var vest_abs: float   = TIER_ABSORPTION.get(vest_tier, 0.0)
	var helmet_abs: float = TIER_ABSORPTION.get(helmet_tier, 0.0)
	return (vest_abs + helmet_abs) * 0.5


## Get durability ratio for a slot.
func get_durability_ratio(slot: String) -> float:
	match slot:
		"helmet":
			var max_dur: float = TIER_MAX_DURABILITY.get(helmet_tier, 1.0)
			return helmet_durability / max_dur if max_dur > 0.0 else 0.0
		"vest":
			var max_dur: float = TIER_MAX_DURABILITY.get(vest_tier, 1.0)
			return vest_durability / max_dur if max_dur > 0.0 else 0.0
	return 0.0


## Serialise for network / save.
func get_state() -> Dictionary:
	return {
		"helmet_tier": helmet_tier,
		"helmet_dur":  helmet_durability,
		"vest_tier":   vest_tier,
		"vest_dur":    vest_durability,
	}


## Apply deserialised state.
func apply_state(state: Dictionary) -> void:
	helmet_tier       = state.get("helmet_tier", ArmorTier.NONE) as ArmorTier
	helmet_durability = state.get("helmet_dur", 0.0)
	vest_tier         = state.get("vest_tier", ArmorTier.NONE) as ArmorTier
	vest_durability   = state.get("vest_dur", 0.0)


# ── Internal ───────────────────────────────────────────────────────────────────

func _apply_durability_damage(slot: String, amount: float, tier: ArmorTier) -> void:
	match slot:
		"helmet":
			var old: float    = helmet_durability
			helmet_durability = maxf(0.0, helmet_durability - amount)
			armor_changed.emit(slot, old, helmet_durability, tier)
			if helmet_durability <= 0.0:
				helmet_tier = ArmorTier.NONE
				armor_broken.emit(slot)
		"vest":
			var old: float  = vest_durability
			vest_durability = maxf(0.0, vest_durability - amount)
			armor_changed.emit(slot, old, vest_durability, tier)
			if vest_durability <= 0.0:
				vest_tier = ArmorTier.NONE
				armor_broken.emit(slot)
