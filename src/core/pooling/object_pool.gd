## =============================================================================
## ObjectPool — Generic High-Performance Object Pool (Autoload)
## =============================================================================
## Purpose:
##   Pre-allocates and recycles Node instances to avoid GC pressure during
##   gameplay. Critical for bullets, VFX particles, damage numbers, AI
##   perception rays, and any high-frequency short-lived objects.
##
## Usage:
##   # Register:   ObjectPool.register("bullet", preload("res://..."), 64)
##   # Acquire:    var b = ObjectPool.acquire("bullet")
##   # Release:    ObjectPool.release("bullet", b)
## =============================================================================

extends Node

const DEFAULT_POOL_SIZE: int = 32
const MAX_OVERFLOW: int      = 128  # Max instances beyond pre-allocated cap.

signal pool_exhausted(pool_id: String)
signal pool_registered(pool_id: String, initial_size: int)

# ── Pool Entry Schema ──────────────────────────────────────────────────────────
# {
#   "scene":    PackedScene,
#   "parent":   Node,
#   "inactive": Array[Node],  -- available
#   "active":   Array[Node],  -- in use
#   "cap":      int,          -- max overflow cap
#   "created":  int,          -- total ever created
# }

var _pools: Dictionary = {}
var _pool_parent: Node


func _ready() -> void:
	name = "ObjectPool"
	_pool_parent = Node.new()
	_pool_parent.name = "_PoolStorage"
	add_child(_pool_parent)
	Logger.info("ObjectPool", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a pool. Call once at startup or scene load.
func register(
	id: String,
	scene: PackedScene,
	initial_size: int = DEFAULT_POOL_SIZE,
	cap: int = MAX_OVERFLOW,
	parent: Node = null
) -> void:
	if _pools.has(id):
		Logger.warn("ObjectPool", "Pool already registered: %s" % id)
		return

	var pool_parent: Node = parent if parent else _pool_parent
	var pool: Dictionary = {
		"scene":    scene,
		"parent":   pool_parent,
		"inactive": [],
		"active":   [],
		"cap":      cap,
		"created":  0,
	}
	_pools[id] = pool

	for i in initial_size:
		var instance: Node = _create_instance(id)
		instance.set_meta("pool_id", id)
		_deactivate(instance)
		pool.inactive.append(instance)

	pool_registered.emit(id, initial_size)
	Logger.info("ObjectPool", "Pool '%s' registered (%d instances)." % [id, initial_size])


## Acquire an instance from the pool. Returns null if exhausted beyond cap.
func acquire(id: String, position: Vector3 = Vector3.ZERO, parent: Node = null) -> Node:
	if not _pools.has(id):
		Logger.error("ObjectPool", "Unknown pool: %s" % id)
		return null

	var pool: Dictionary = _pools[id]
	var instance: Node

	if not pool.inactive.is_empty():
		instance = pool.inactive.pop_back()
	elif pool.created < pool.cap:
		instance = _create_instance(id)
		instance.set_meta("pool_id", id)
		Logger.debug("ObjectPool", "Pool '%s' overflow — created extra instance." % id)
	else:
		pool_exhausted.emit(id)
		Logger.warn("ObjectPool", "Pool '%s' exhausted (cap=%d)." % [id, pool.cap])
		return null

	pool.active.append(instance)
	_activate(instance, position, parent if parent else pool.parent)
	return instance


## Return an instance to the pool.
func release(instance: Node) -> void:
	if not instance.has_meta("pool_id"):
		Logger.warn("ObjectPool", "Releasing non-pooled node: %s" % instance.name)
		instance.queue_free()
		return

	var id: String = instance.get_meta("pool_id")
	if not _pools.has(id):
		Logger.warn("ObjectPool", "Pool not found for released node: %s" % id)
		return

	var pool: Dictionary = _pools[id]
	pool.active.erase(instance)
	_deactivate(instance)
	pool.inactive.append(instance)


## Release all active instances of a pool.
func release_all(id: String) -> void:
	if not _pools.has(id):
		return
	var pool: Dictionary = _pools[id]
	for instance in pool.active.duplicate():
		release(instance)


## Destroy a pool entirely (e.g. on scene change).
func destroy_pool(id: String) -> void:
	if not _pools.has(id):
		return
	var pool: Dictionary = _pools[id]
	for n in pool.inactive:
		n.queue_free()
	for n in pool.active:
		n.queue_free()
	_pools.erase(id)
	Logger.info("ObjectPool", "Pool '%s' destroyed." % id)


## Returns stats for a given pool.
func get_stats(id: String) -> Dictionary:
	if not _pools.has(id):
		return {}
	var pool: Dictionary = _pools[id]
	return {
		"id":       id,
		"active":   pool.active.size(),
		"inactive": pool.inactive.size(),
		"created":  pool.created,
		"cap":      pool.cap,
	}


## Returns stats for all pools (for debug overlay).
func get_all_stats() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _pools:
		result.append(get_stats(id))
	return result


# ── Internal ───────────────────────────────────────────────────────────────────

func _create_instance(id: String) -> Node:
	var pool: Dictionary = _pools[id]
	var instance: Node = pool.scene.instantiate()
	pool.parent.add_child(instance)
	pool.created += 1
	return instance


func _activate(instance: Node, position: Vector3, parent: Node) -> void:
	if instance.get_parent() != parent:
		if instance.get_parent():
			instance.reparent(parent)
		else:
			parent.add_child(instance)
	if instance is Node3D:
		(instance as Node3D).global_position = position
	instance.show()
	instance.set_process(true)
	instance.set_physics_process(true)
	if instance.has_method("on_pool_acquire"):
		instance.on_pool_acquire()


func _deactivate(instance: Node) -> void:
	instance.hide()
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("on_pool_release"):
		instance.on_pool_release()
	if instance.get_parent() and instance.get_parent() != _pool_parent:
		instance.reparent(_pool_parent)
