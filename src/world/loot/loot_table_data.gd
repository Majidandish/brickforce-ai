## =============================================================================
## LootTableData — Configurable Loot Table Resource
## =============================================================================
## Architecture:
##   Data-driven loot definition. Create .tres instances for:
##     - Zone-specific tables (city, military, field)
##     - Container types (crate, safe, supply drop)
##     - Enemy drop tables
##     - Airdrop tier tables
##
##   Weighted roll with rarity tiers. Min/max quantity per entry.
##   Guaranteed items (always spawn) and optional items (weighted chance).
## =============================================================================

class_name LootTableData
extends Resource

## A single loot entry.
class LootEntry:
	var item_id: String    = ""
	var weight: float      = 1.0
	var min_qty: int       = 1
	var max_qty: int       = 1
	var guaranteed: bool   = false
	var conditions: Array  = []  # Future: condition objects.

## Table Tiers: affects overall quality.
enum TableTier { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

@export var table_id: String           = "default"
@export var table_tier: TableTier      = TableTier.COMMON
@export var min_items: int             = 2
@export var max_items: int             = 5

## Serialized entries: Array of Dictionaries
## { item_id, weight, min_qty, max_qty, guaranteed }
@export var entries: Array[Dictionary] = []

## Tables that can be nested/rolled as part of this table.
@export var nested_tables: Array[String] = []


## Roll this table and return a list of { item_id, quantity } dicts.
func roll(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entry_count: int = rng.randi_range(min_items, max_items)

	# Guaranteed items first.
	for e in entries:
		if e.get("guaranteed", false):
			result.append({
				"item_id":  e.get("item_id", ""),
				"quantity": rng.randi_range(e.get("min_qty", 1), e.get("max_qty", 1)),
			})

	# Weighted random for the rest.
	var pool: Array[Dictionary] = entries.filter(func(e): return not e.get("guaranteed", false))
	var total_weight: float = 0.0
	for e in pool:
		total_weight += e.get("weight", 1.0)

	for i in entry_count:
		if pool.is_empty():
			break
		var roll: float = rng.randf() * total_weight
		var cumulative: float = 0.0
		for e in pool:
			cumulative += e.get("weight", 1.0)
			if roll <= cumulative:
				result.append({
					"item_id":  e.get("item_id", ""),
					"quantity": rng.randi_range(e.get("min_qty", 1), e.get("max_qty", 1)),
				})
				break

	return result


## Build from a simple array of { item_id, weight, min_qty, max_qty }.
func populate(entry_dicts: Array[Dictionary]) -> void:
	entries = entry_dicts.duplicate(true)
