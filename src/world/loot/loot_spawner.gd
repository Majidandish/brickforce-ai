## =============================================================================
## LootSpawner — Data-Driven Procedural Loot Distribution System
## =============================================================================
## Purpose:
##   Spawns loot containers and ground items throughout the map using
##   weighted random loot tables, rarity tiers, and zone-based density.
##   Ensures balanced item distribution across the play area.
## =============================================================================

class_name LootSpawner
extends Node3D

@export var loot_table: Array[Dictionary] = []   # { item_id, weight, min_qty, max_qty }
@export var container_scene: PackedScene   = null
@export var density: float                 = 1.0  # Multiplier for spawn count.
@export var zone_id: String                = "default"

signal loot_spawned_at(position: Vector3, items: Array)
signal container_opened(container_id: String, opener_id: int)

var _spawned_containers: Array[Node3D] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	name = "LootSpawner"
	_rng.randomize()


# ── Public API ─────────────────────────────────────────────────────────────────

## Spawn loot across all designated spawn points (children named "SpawnPoint_*").
func spawn_all() -> void:
	var spawn_points: Array[Node3D] = _get_spawn_points()
	for point in spawn_points:
		if _rng.randf() > density:
			continue
		_spawn_at(point.global_position)
	Logger.info("LootSpawner", "Spawned loot in zone '%s' (%d points)." % [zone_id, spawn_points.size()])


## Spawn at a specific position.
func spawn_at_position(pos: Vector3) -> Dictionary:
	return _spawn_at(pos)


## Respawn all loot (e.g. after a wave or periodic refresh).
func respawn_all() -> void:
	_clear_all()
	spawn_all()


## Roll items from the loot table (used for containers and air drops).
func roll_items(count: int = 3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in count:
		var item: Dictionary = _weighted_roll()
		if not item.is_empty():
			result.append(item)
	return result


# ── Internal ───────────────────────────────────────────────────────────────────

func _spawn_at(pos: Vector3) -> Dictionary:
	var items: Array[Dictionary] = roll_items(_rng.randi_range(1, 4))
	if items.is_empty():
		return {}

	if container_scene:
		var container: Node3D = container_scene.instantiate()
		get_tree().current_scene.add_child(container)
		container.global_position = pos
		if container.has_method("initialize"):
			container.initialize(items)
		_spawned_containers.append(container)

	loot_spawned_at.emit(pos, items)
	var item_ids: Array = items.map(func(i): return i.get("item_id", ""))
	EventBus.loot_spawned.emit("loot_%d" % int(pos.x + pos.z), pos, item_ids)
	return { "position": pos, "items": items }


func _weighted_roll() -> Dictionary:
	if loot_table.is_empty():
		return _fallback_roll()

	var total_weight: float = 0.0
	for entry in loot_table:
		total_weight += entry.get("weight", 1.0)

	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry in loot_table:
		cumulative += entry.get("weight", 1.0)
		if roll <= cumulative:
			return {
				"item_id":  entry.get("item_id", ""),
				"quantity": _rng.randi_range(
					entry.get("min_qty", 1),
					entry.get("max_qty", 1)
				),
			}
	return {}


func _fallback_roll() -> Dictionary:
	# Built-in fallback loot table when no custom table is set.
	const FALLBACK: Array[Dictionary] = [
		{ "item_id": "medkit_basic",       "weight": 10.0, "min_qty": 1, "max_qty": 2 },
		{ "item_id": "ammo_rifle",         "weight": 15.0, "min_qty": 15, "max_qty": 30 },
		{ "item_id": "ammo_pistol",        "weight": 12.0, "min_qty": 20, "max_qty": 50 },
		{ "item_id": "armor_vest_basic",   "weight": 5.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "helmet_basic",       "weight": 5.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "bandage",            "weight": 20.0, "min_qty": 1, "max_qty": 5 },
		{ "item_id": "scope_2x",           "weight": 3.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "energy_drink",       "weight": 8.0,  "min_qty": 1, "max_qty": 2 },
	]
	var total: float = 0.0
	for e in FALLBACK:
		total += e.weight
	var roll: float = _rng.randf() * total
	var cum: float  = 0.0
	for e in FALLBACK:
		cum += e.weight
		if roll <= cum:
			return { "item_id": e.item_id, "quantity": _rng.randi_range(e.min_qty, e.max_qty) }
	return {}


func _get_spawn_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			points.append(child as Node3D)
	return points


func _clear_all() -> void:
	for container in _spawned_containers:
		if is_instance_valid(container):
			container.queue_free()
	_spawned_containers.clear()
