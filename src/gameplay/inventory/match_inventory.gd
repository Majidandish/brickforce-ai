## =============================================================================
## MatchInventory — In-Match Carried Inventory (Per-Character)
## =============================================================================
## Architecture:
##   Manages items a character carries during a match. Separate from
##   the persistent InventoryManager (cosmetics/unlock system).
##   Grid-based with configurable capacity (backpack tier changes cap).
##   Exposes stacks per slot, ammo tracking, and quick-slot assignment.
##
##   Network-safe: replicated via get_state() / apply_state().
## =============================================================================

class_name MatchInventory
extends Node

const AMMO_TYPES: Array[String] = [
	"rifle_ammo", "pistol_ammo", "shotgun_ammo", "sniper_ammo",
	"smg_ammo", "lmg_ammo", "explosive_ammo",
]

# ── Capacity tiers (backpack level → max item slots) ──────────────────────────
const BACKPACK_CAPACITY: Dictionary = { 0: 6, 1: 10, 2: 14, 3: 20 }

signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal capacity_changed(used: int, max_cap: int)
signal ammo_changed(ammo_type: String, amount: int)

var owner_character: CharacterBase = null

## item_id -> quantity
var items: Dictionary  = {}
## ammo_type -> count
var ammo: Dictionary   = {}
## Consumable quick slots: 0-3 -> item_id
var quick_slots: Dictionary = { 0: "", 1: "", 2: "", 3: "" }

var backpack_tier: int = 0
var _max_capacity: int = BACKPACK_CAPACITY[0]


func _ready() -> void:
	name = "MatchInventory"
	# Initialise ammo pools.
	for t in AMMO_TYPES:
		ammo[t] = 0


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with owning character.
func initialize(character: CharacterBase) -> void:
	owner_character = character


## Add items. Returns actual quantity added (may be partial if capacity hit).
func add_item(item_id: String, quantity: int = 1) -> int:
	if item_id == "":
		return 0

	# Ammo is tracked separately (unlimited-ish stacks).
	if item_id in AMMO_TYPES:
		return _add_ammo(item_id, quantity)

	var free_capacity: int = _max_capacity - _get_used_slots()
	if free_capacity <= 0:
		return 0

	var to_add: int = mini(quantity, free_capacity)
	items[item_id] = items.get(item_id, 0) + to_add
	item_added.emit(item_id, to_add)
	capacity_changed.emit(_get_used_slots(), _max_capacity)
	EventBus.item_picked_up.emit(
		owner_character.character_id if owner_character else -1, item_id, to_add
	)
	return to_add


## Remove items. Returns true if successful.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id in AMMO_TYPES:
		return _remove_ammo(item_id, quantity)
	if not has_item(item_id, quantity):
		return false
	items[item_id] -= quantity
	if items[item_id] <= 0:
		items.erase(item_id)
	item_removed.emit(item_id, quantity)
	capacity_changed.emit(_get_used_slots(), _max_capacity)
	return true


## Check if this item can be added.
func can_add(item_id: String, quantity: int = 1) -> bool:
	if item_id in AMMO_TYPES:
		return true
	return _get_used_slots() + quantity <= _max_capacity


## Check if the inventory has enough of an item.
func has_item(item_id: String, quantity: int = 1) -> bool:
	if item_id in AMMO_TYPES:
		return ammo.get(item_id, 0) >= quantity
	return items.get(item_id, 0) >= quantity


## Get quantity of an item.
func get_quantity(item_id: String) -> int:
	if item_id in AMMO_TYPES:
		return ammo.get(item_id, 0)
	return items.get(item_id, 0)


## Get ammo count for a type.
func get_ammo(ammo_type: String) -> int:
	return ammo.get(ammo_type, 0)


## Use ammo (removes from pool). Returns actual amount consumed.
func consume_ammo(ammo_type: String, amount: int) -> int:
	var available: int = ammo.get(ammo_type, 0)
	var consumed: int  = mini(amount, available)
	if consumed > 0:
		ammo[ammo_type] -= consumed
		ammo_changed.emit(ammo_type, ammo[ammo_type])
	return consumed


## Drop an item at the character's position.
func drop_item(item_id: String, quantity: int = 1) -> void:
	if not remove_item(item_id, quantity):
		return
	if owner_character:
		InteractablePickup.spawn_at(
			owner_character.global_position + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5)),
			item_id, quantity, owner_character.get_parent()
		)
		EventBus.item_dropped.emit(
			owner_character.character_id, item_id, quantity, owner_character.global_position
		)


## Upgrade backpack tier (increases capacity).
func upgrade_backpack(tier: int) -> void:
	backpack_tier  = clampi(tier, 0, 3)
	_max_capacity  = BACKPACK_CAPACITY[backpack_tier]
	capacity_changed.emit(_get_used_slots(), _max_capacity)


## Assign an item to a quick slot.
func assign_quick_slot(slot: int, item_id: String) -> void:
	if quick_slots.has(slot):
		quick_slots[slot] = item_id


## Use the item in a quick slot.
func use_quick_slot(slot: int) -> bool:
	var item_id: String = quick_slots.get(slot, "")
	if item_id == "" or not has_item(item_id):
		return false
	return _use_item(item_id)


## Use an item directly.
func use_item(item_id: String) -> bool:
	return _use_item(item_id)


## Get all items as a flat dict.
func get_all_items() -> Dictionary:
	return items.duplicate()


## Get all ammo.
func get_all_ammo() -> Dictionary:
	return ammo.duplicate()


## Returns capacity info.
func get_capacity_info() -> Dictionary:
	return { "used": _get_used_slots(), "max": _max_capacity, "tier": backpack_tier }


## Serialise for replication / save.
func get_state() -> Dictionary:
	return {
		"items":       items.duplicate(),
		"ammo":        ammo.duplicate(),
		"quick_slots": quick_slots.duplicate(),
		"backpack_tier": backpack_tier,
	}


## Apply received state.
func apply_state(state: Dictionary) -> void:
	items       = state.get("items", {}).duplicate()
	ammo        = state.get("ammo", {}).duplicate()
	quick_slots = state.get("quick_slots", quick_slots).duplicate()
	upgrade_backpack(state.get("backpack_tier", 0))


# ── Internal ───────────────────────────────────────────────────────────────────

func _get_used_slots() -> int:
	var total: int = 0
	for id in items:
		total += items[id]
	return total


func _add_ammo(ammo_type: String, amount: int) -> int:
	ammo[ammo_type] = ammo.get(ammo_type, 0) + amount
	ammo_changed.emit(ammo_type, ammo[ammo_type])
	return amount


func _remove_ammo(ammo_type: String, amount: int) -> bool:
	if ammo.get(ammo_type, 0) < amount:
		return false
	ammo[ammo_type] -= amount
	ammo_changed.emit(ammo_type, ammo[ammo_type])
	return true


func _use_item(item_id: String) -> bool:
	# TODO: Look up ItemData resource and apply effect.
	if not remove_item(item_id, 1):
		return false
	EventBus.item_used.emit(
		owner_character.character_id if owner_character else -1, item_id
	)
	Logger.debug("MatchInventory", "Used item: %s" % item_id)
	return true
