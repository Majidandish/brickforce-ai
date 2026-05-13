## =============================================================================
## LootManager — Global Loot Distribution & Airdrop Controller (Autoload)
## =============================================================================
## Architecture:
##   Singleton that owns all loot tables, coordinates LootSpawner nodes,
##   manages airdrops, tracks picked-up items, and handles loot zone density.
##
##   LootSpawner scene nodes call LootManager.get_table() to get their
##   configured loot table resource, then roll it locally.
## =============================================================================

extends Node

const AIRDROP_INTERVAL_MIN: float = 120.0  # Seconds between airdrops.
const AIRDROP_INTERVAL_MAX: float = 240.0

signal airdrop_incoming(position: Vector3, eta: float)
signal airdrop_landed(position: Vector3, items: Array)
signal loot_table_registered(table_id: String)

## table_id -> LootTableData resource.
var _tables: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _airdrop_timer: float = 0.0
var _next_airdrop_at: float = 0.0
var _match_active: bool = false


func _ready() -> void:
	name = "LootManager"
	_rng.randomize()
	_register_default_tables()
	EventBus.match_started.connect(func(_c): _on_match_started())
	EventBus.match_ended.connect(func(_r): _on_match_ended())
	Logger.info("LootManager", "Initialized with %d tables." % _tables.size())


func _process(delta: float) -> void:
	if not _match_active:
		return
	_airdrop_timer += delta
	if _airdrop_timer >= _next_airdrop_at:
		_trigger_airdrop()


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a loot table.
func register_table(table: LootTableData) -> void:
	_tables[table.table_id] = table
	loot_table_registered.emit(table.table_id)


## Get a loot table by ID.
func get_table(table_id: String) -> LootTableData:
	return _tables.get(table_id, null)


## Roll a table and return items.
func roll_table(table_id: String) -> Array[Dictionary]:
	var table: LootTableData = get_table(table_id)
	if not table:
		Logger.warn("LootManager", "Table not found: %s" % table_id)
		return []
	return table.roll(_rng)


## Spawn a physical pickup at a world position.
func spawn_pickup(item_id: String, quantity: int, position: Vector3, parent: Node) -> InteractablePickup:
	var pickup: InteractablePickup = InteractablePickup.spawn_at(position, item_id, quantity, parent)
	return pickup


## Spawn all items from a loot roll at scattered positions.
func spawn_roll(table_id: String, center: Vector3, spread_radius: float, parent: Node) -> void:
	var items: Array[Dictionary] = roll_table(table_id)
	for item in items:
		var offset: Vector3 = Vector3(
			_rng.randf_range(-spread_radius, spread_radius),
			0.1,
			_rng.randf_range(-spread_radius, spread_radius)
		)
		spawn_pickup(item.get("item_id", ""), item.get("quantity", 1), center + offset, parent)

	EventBus.loot_spawned.emit("roll_%s" % table_id, center,
		items.map(func(i): return i.get("item_id", ""))
	)


## Queue an airdrop at a specific map position (called by MatchManager or event trigger).
func queue_airdrop(position: Vector3, table_id: String = "airdrop_tier2") -> void:
	var eta: float = 15.0
	airdrop_incoming.emit(position, eta)
	EventBus.airdrop_incoming.emit(position, eta)
	TimeManager.register_timer(
		"airdrop_%d" % int(Time.get_unix_time_from_system()),
		eta,
		func(): _land_airdrop(position, table_id)
	)
	Logger.info("LootManager", "Airdrop incoming at %s ETA %.0fs." % [str(position), eta])


# ── Internal ───────────────────────────────────────────────────────────────────

func _register_default_tables() -> void:
	var ground: LootTableData = LootTableData.new()
	ground.table_id   = "ground_common"
	ground.min_items  = 1
	ground.max_items  = 3
	ground.populate([
		{ "item_id": "medkit_basic",     "weight": 15.0, "min_qty": 1, "max_qty": 2 },
		{ "item_id": "bandage",          "weight": 25.0, "min_qty": 1, "max_qty": 5 },
		{ "item_id": "ammo_rifle",       "weight": 20.0, "min_qty": 20, "max_qty": 60 },
		{ "item_id": "ammo_pistol",      "weight": 18.0, "min_qty": 20, "max_qty": 40 },
		{ "item_id": "armor_vest_basic", "weight": 6.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "helmet_basic",     "weight": 5.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "energy_drink",     "weight": 10.0, "min_qty": 1, "max_qty": 2 },
	])
	register_table(ground)

	var crate: LootTableData = LootTableData.new()
	crate.table_id  = "crate_military"
	crate.min_items = 3
	crate.max_items = 6
	crate.populate([
		{ "item_id": "medkit_advanced",    "weight": 10.0, "min_qty": 1, "max_qty": 2 },
		{ "item_id": "armor_vest_enhanced","weight": 8.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "helmet_enhanced",    "weight": 7.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "ammo_rifle",         "weight": 15.0, "min_qty": 60, "max_qty": 120 },
		{ "item_id": "ammo_sniper",        "weight": 5.0,  "min_qty": 5, "max_qty": 15 },
		{ "item_id": "scope_4x",           "weight": 4.0,  "min_qty": 1, "max_qty": 1 },
		{ "item_id": "grenade_frag",       "weight": 6.0,  "min_qty": 1, "max_qty": 2 },
	])
	register_table(crate)

	var airdrop: LootTableData = LootTableData.new()
	airdrop.table_id  = "airdrop_tier2"
	airdrop.min_items = 5
	airdrop.max_items = 8
	airdrop.populate([
		{ "item_id": "medkit_military",   "weight": 5.0, "min_qty": 1, "max_qty": 2, "guaranteed": false },
		{ "item_id": "armor_vest_military","weight": 6.0, "min_qty": 1, "max_qty": 1 },
		{ "item_id": "helmet_military",   "weight": 5.0, "min_qty": 1, "max_qty": 1 },
		{ "item_id": "scope_8x",          "weight": 3.0, "min_qty": 1, "max_qty": 1 },
		{ "item_id": "ammo_sniper",       "weight": 8.0, "min_qty": 10, "max_qty": 20 },
		{ "item_id": "grenade_smoke",     "weight": 7.0, "min_qty": 2, "max_qty": 4 },
		{ "item_id": "backpack_tier3",    "weight": 4.0, "min_qty": 1, "max_qty": 1 },
	])
	register_table(airdrop)


func _trigger_airdrop() -> void:
	_airdrop_timer = 0.0
	_next_airdrop_at = _rng.randf_range(AIRDROP_INTERVAL_MIN, AIRDROP_INTERVAL_MAX)
	# Random position within current safe zone.
	var sm: Node = get_tree().root.find_child("MatchManager", true, false)
	var center: Vector3 = Vector3.ZERO
	if sm and sm.has_method("get_match_stats"):
		center = sm.safe_zone_center
	var angle: float  = _rng.randf() * TAU
	var dist: float   = _rng.randf_range(0, 100.0)
	var drop_pos: Vector3 = center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	queue_airdrop(drop_pos)


func _land_airdrop(position: Vector3, table_id: String) -> void:
	VFXManager.play("loot_drop_beacon", position)
	AudioManager.play_sfx_at("res://assets/audio/sfx/airdrop_land.ogg", position)
	var items: Array[Dictionary] = roll_table(table_id)
	var parent: Node = get_tree().current_scene
	for item in items:
		var offset: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), 0.1, _rng.randf_range(-1.0, 1.0))
		spawn_pickup(item.get("item_id", ""), item.get("quantity", 1), position + offset, parent)
	airdrop_landed.emit(position, items)
	EventBus.airdrop_landed.emit(position, items.map(func(i): return i.get("item_id", "")))
	Logger.info("LootManager", "Airdrop landed with %d items." % items.size())


func _on_match_started() -> void:
	_match_active       = true
	_airdrop_timer      = 0.0
	_next_airdrop_at    = _rng.randf_range(AIRDROP_INTERVAL_MIN, AIRDROP_INTERVAL_MAX)


func _on_match_ended() -> void:
	_match_active = false
