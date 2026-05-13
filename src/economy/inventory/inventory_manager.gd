## =============================================================================
## InventoryManager — Global Inventory & Item Registry (Autoload)
## =============================================================================
## Purpose:
##   Manages the player's persistent item collection (not match inventory).
##   Tracks owned items, quantities, equipment slots, and item metadata.
##   Communicates with ItemData resources for validation.
##   Match-time inventory (carried items) lives on the Character node.
## =============================================================================

extends Node

const MAX_STACK_SIZE: int = 999

signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)
signal item_equipped(item_id: String, slot: String)
signal item_unequipped(item_id: String, slot: String)
signal inventory_changed()

## slot_name -> item_id (null = empty)
var equipped_slots: Dictionary = {
	"primary":   "",
	"secondary": "",
	"sidearm":   "",
	"throwable": "",
	"helmet":    "",
	"vest":      "",
	"backpack":  "",
}

## item_id -> { quantity, data_ref, acquired_at }
var _items: Dictionary = {}


func _ready() -> void:
	name = "InventoryManager"
	SaveManager.register_serializer("inventory", _save, _load_data)
	EventBus.item_picked_up.connect(_on_item_picked_up)
	EventBus.item_dropped.connect(_on_item_dropped)
	Logger.info("InventoryManager", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Add items to the persistent inventory.
func add_item(item_id: String, quantity: int = 1) -> bool:
	if item_id == "" or quantity <= 0:
		return false
	if _items.has(item_id):
		_items[item_id].quantity = min(
			_items[item_id].quantity + quantity, MAX_STACK_SIZE
		)
	else:
		_items[item_id] = {
			"item_id":     item_id,
			"quantity":    quantity,
			"acquired_at": Time.get_unix_time_from_system(),
		}
	item_added.emit(item_id, quantity)
	inventory_changed.emit()
	Logger.debug("InventoryManager", "+%dx %s" % [quantity, item_id])
	return true


## Remove items. Returns true if successful.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	if not has_item(item_id, quantity):
		return false
	_items[item_id].quantity -= quantity
	if _items[item_id].quantity <= 0:
		_items.erase(item_id)
	item_removed.emit(item_id, quantity)
	inventory_changed.emit()
	return true


## Returns true if the player owns at least quantity of item_id.
func has_item(item_id: String, quantity: int = 1) -> bool:
	return _items.has(item_id) and _items[item_id].quantity >= quantity


## Get quantity owned of an item.
func get_quantity(item_id: String) -> int:
	return _items.get(item_id, {}).get("quantity", 0)


## Get all owned items as array of dictionaries.
func get_all_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _items:
		result.append(_items[id].duplicate())
	return result


## Get items of a specific type (by querying ItemData registry).
func get_items_by_type(item_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _items:
		# TODO: cross-reference ItemData resource registry.
		result.append(_items[id].duplicate())
	return result


## Equip an item to a slot. Returns false if item not owned or slot invalid.
func equip(item_id: String, slot: String) -> bool:
	if not has_item(item_id):
		Logger.warn("InventoryManager", "Cannot equip unowned item: %s" % item_id)
		return false
	if not equipped_slots.has(slot):
		Logger.warn("InventoryManager", "Invalid equipment slot: %s" % slot)
		return false
	var old: String = equipped_slots[slot]
	if old != "":
		item_unequipped.emit(old, slot)
		EventBus.item_unequipped.emit(0, old, slot)
	equipped_slots[slot] = item_id
	item_equipped.emit(item_id, slot)
	EventBus.item_equipped.emit(0, item_id, slot)
	inventory_changed.emit()
	return true


## Unequip an item from a slot.
func unequip(slot: String) -> void:
	if not equipped_slots.has(slot):
		return
	var old: String = equipped_slots[slot]
	if old != "":
		equipped_slots[slot] = ""
		item_unequipped.emit(old, slot)
		EventBus.item_unequipped.emit(0, old, slot)
		inventory_changed.emit()


## Returns the item equipped in a given slot (empty string = none).
func get_equipped(slot: String) -> String:
	return equipped_slots.get(slot, "")


## Returns true if the slot has an item equipped.
func is_slot_occupied(slot: String) -> bool:
	return equipped_slots.get(slot, "") != ""


# ── Internal ───────────────────────────────────────────────────────────────────

func _on_item_picked_up(owner_id: int, item_id: String, quantity: int) -> void:
	if owner_id == NetworkManager.local_peer_id:
		add_item(item_id, quantity)


func _on_item_dropped(owner_id: int, item_id: String, quantity: int, _position: Vector3) -> void:
	if owner_id == NetworkManager.local_peer_id:
		remove_item(item_id, quantity)


func _save() -> Dictionary:
	return {
		"items":    _items.duplicate(true),
		"equipped": equipped_slots.duplicate(),
	}


func _load_data(data: Dictionary) -> void:
	if data.has("items"):
		_items = data.items.duplicate(true)
	if data.has("equipped"):
		for slot in data.equipped:
			if equipped_slots.has(slot):
				equipped_slots[slot] = data.equipped[slot]
	Logger.info("InventoryManager", "Inventory loaded (%d items)." % _items.size())
