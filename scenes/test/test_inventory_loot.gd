## =============================================================================
## TestInventoryLoot — Match Inventory + Loot Table Integration Test
## =============================================================================

extends Node

const PASS: String = "[PASS]"
const FAIL: String = "[FAIL]"
var _results: Array[String] = []


func _ready() -> void:
	print("=== TEST: InventoryLoot ===")
	_test_match_inventory()
	_test_loot_table()
	_finish()


func _test_match_inventory() -> void:
	print("  -- MatchInventory --")
	var inv: MatchInventory = MatchInventory.new()
	add_child(inv)
	await get_tree().process_frame

	_record(inv._max_capacity == 6, "Default backpack capacity is 6")

	var added: int = inv.add_item("bandage", 3)
	_record(added == 3, "Add 3 bandages succeeds")
	_record(inv.get_quantity("bandage") == 3, "Quantity tracked correctly")

	var added2: int = inv.add_item("rifle_ammo", 30)
	_record(added2 == 30, "Ammo added to ammo pool")
	_record(inv.get_ammo("rifle_ammo") == 30, "Ammo pool correct")

	inv.upgrade_backpack(1)
	_record(inv._max_capacity == 10, "Backpack tier 1 = 10 slots")

	var removed: bool = inv.remove_item("bandage", 1)
	_record(removed, "Remove item returns true")
	_record(inv.get_quantity("bandage") == 2, "Quantity updated after remove")

	var has: bool = inv.has_item("bandage", 5)
	_record(not has, "has_item false when quantity insufficient")

	inv.quick_slots[0] = "bandage"
	_record(inv.quick_slots[0] == "bandage", "Quick slot assignment works")

	inv.queue_free()


func _test_loot_table() -> void:
	print("  -- LootTableData --")
	var table: LootTableData = LootTableData.new()
	table.table_id  = "test_table"
	table.min_items = 2
	table.max_items = 4
	table.populate([
		{ "item_id": "medkit_basic", "weight": 10.0, "min_qty": 1, "max_qty": 2 },
		{ "item_id": "ammo_rifle",   "weight": 20.0, "min_qty": 10, "max_qty": 30 },
		{ "item_id": "bandage",      "weight": 15.0, "min_qty": 1, "max_qty": 5 },
	])

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var roll: Array[Dictionary] = table.roll(rng)

	_record(roll.size() >= table.min_items and roll.size() <= table.max_items, "Roll count within bounds")
	_record(roll.size() > 0, "At least one item rolled")
	for item in roll:
		_record(item.has("item_id") and item.item_id != "", "Each item has item_id")
		_record(item.has("quantity") and item.quantity >= 1, "Each item has quantity >= 1")


func _record(passed: bool, description: String) -> void:
	var tag: String = PASS if passed else FAIL
	var msg: String = "%s %s" % [tag, description]
	_results.append(msg)
	print(msg)


func _finish() -> void:
	var total: int  = _results.size()
	var passed: int = _results.filter(func(r): return r.begins_with(PASS)).size()
	print("=== RESULT: %d/%d PASS ===" % [passed, total])
