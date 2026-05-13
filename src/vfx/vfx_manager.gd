## =============================================================================
## VFXManager — Visual Effects Orchestration System (Autoload)
## =============================================================================
## Purpose:
##   Spawns, pools, and manages all runtime VFX: muzzle flashes, explosions,
##   hit sparks, blood decals, bullet trails, environmental particles,
##   and screen post-processing effects. Integrates with ObjectPool.
## =============================================================================

extends Node

# ── VFX Catalogue ─────────────────────────────────────────────────────────────
# Maps VFX IDs to their scene resource paths.
const VFX_CATALOGUE: Dictionary = {
	"muzzle_flash_rifle":     "res://scenes/vfx/muzzle_flash_rifle.tscn",
	"muzzle_flash_pistol":    "res://scenes/vfx/muzzle_flash_pistol.tscn",
	"bullet_impact_concrete": "res://scenes/vfx/impact_concrete.tscn",
	"bullet_impact_metal":    "res://scenes/vfx/impact_metal.tscn",
	"bullet_impact_flesh":    "res://scenes/vfx/impact_flesh.tscn",
	"explosion_grenade":      "res://scenes/vfx/explosion_grenade.tscn",
	"explosion_vehicle":      "res://scenes/vfx/explosion_vehicle.tscn",
	"blood_spray":            "res://scenes/vfx/blood_spray.tscn",
	"smoke_grenade":          "res://scenes/vfx/smoke_grenade.tscn",
	"revive_aura":            "res://scenes/vfx/revive_aura.tscn",
	"safe_zone_edge":         "res://scenes/vfx/safe_zone_edge.tscn",
	"loot_drop_beacon":       "res://scenes/vfx/loot_drop_beacon.tscn",
	"kill_confirm":           "res://scenes/vfx/kill_confirm.tscn",
	"level_up_burst":         "res://scenes/vfx/level_up_burst.tscn",
}

# ── Decal Catalogue ───────────────────────────────────────────────────────────
const DECAL_CATALOGUE: Dictionary = {
	"bullet_hole_concrete": "res://scenes/vfx/decal_bullet_concrete.tscn",
	"bullet_hole_metal":    "res://scenes/vfx/decal_bullet_metal.tscn",
	"blood_splatter":       "res://scenes/vfx/decal_blood.tscn",
	"scorch_mark":          "res://scenes/vfx/decal_scorch.tscn",
}

const DECAL_LIFETIME: float = 30.0
const MAX_DECALS: int       = 256

signal vfx_spawned(vfx_id: String, position: Vector3)

var _decal_queue: Array[Node3D] = []  # Circular buffer for decal limit.
var _vfx_world_parent: Node3D


func _ready() -> void:
	name = "VFXManager"
	EventBus.vfx_play_requested.connect(play)
	EventBus.vfx_stop_requested.connect(stop_all_of_type)
	EventBus.decal_place_requested.connect(place_decal)
	_register_vfx_pools()
	Logger.info("VFXManager", "Initialized. %d VFX types registered." % VFX_CATALOGUE.size())


func _on_scene_loaded(scene_path: String) -> void:
	# Find the world vfx container in the new scene.
	_vfx_world_parent = get_tree().current_scene.find_child("VFXContainer", true, false)


# ── Public API ─────────────────────────────────────────────────────────────────

## Spawn a VFX at a world position. Auto-released when finished.
func play(
	vfx_id: String,
	position: Vector3 = Vector3.ZERO,
	rotation: Vector3 = Vector3.ZERO,
	parent: NodePath = NodePath("")
) -> Node3D:
	if not VFX_CATALOGUE.has(vfx_id):
		Logger.warn("VFXManager", "Unknown VFX: %s" % vfx_id)
		return null

	var instance: Node = ObjectPool.acquire(vfx_id, position)
	if not instance:
		return null

	var instance3d: Node3D = instance as Node3D
	instance3d.rotation = rotation

	# Auto-release when the particle system finishes.
	if instance.has_method("connect_finished"):
		instance.connect_finished(func(): ObjectPool.release(instance))
	else:
		# Fallback: release after a fixed duration.
		TimeManager.register_timer(
			"vfx_%d" % instance.get_instance_id(),
			3.0,
			func(): ObjectPool.release(instance)
		)

	vfx_spawned.emit(vfx_id, position)
	return instance3d


## Play VFX attached to a bone/node (follows the parent).
func play_attached(vfx_id: String, attach_to: Node3D, bone_name: String = "") -> Node3D:
	var instance: Node3D = play(vfx_id, attach_to.global_position)
	if instance and is_instance_valid(attach_to):
		instance.reparent(attach_to)
		instance.position = Vector3.ZERO
		if bone_name != "" and attach_to.has_method("get_bone_global_pose"):
			pass  # TODO: Skeleton3D bone attachment.
	return instance


## Stop (release) all active VFX of a given type.
func stop_all_of_type(vfx_id: String) -> void:
	ObjectPool.release_all(vfx_id)


## Place a decal at a surface hit point.
func place_decal(decal_id: String, position: Vector3, normal: Vector3) -> void:
	if not DECAL_CATALOGUE.has(decal_id):
		return
	var path: String = DECAL_CATALOGUE[decal_id]
	if not ResourceLoader.exists(path):
		return

	var decal_scene: PackedScene = load(path)
	var decal: Node3D = decal_scene.instantiate()

	var parent: Node = _vfx_world_parent if _vfx_world_parent else get_tree().current_scene
	parent.add_child(decal)
	decal.global_position = position
	decal.look_at(position + normal, Vector3.UP)

	# Enforce decal budget.
	_decal_queue.append(decal)
	if _decal_queue.size() > MAX_DECALS:
		var oldest: Node3D = _decal_queue.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	# Auto-expire.
	TimeManager.register_timer(
		"decal_%d" % decal.get_instance_id(),
		DECAL_LIFETIME,
		func():
			if is_instance_valid(decal):
				_decal_queue.erase(decal)
				decal.queue_free()
	)


## Screen-space effect: camera shake request (delegated to active camera).
func screen_shake(intensity: float = 1.0, duration: float = 0.3) -> void:
	EventBus.screen_shake_requested.emit(intensity, duration)


## Flash the screen a color (e.g. red for damage).
func screen_flash(color: Color = Color(1, 0, 0, 0.4), duration: float = 0.1) -> void:
	EventBus.hud_show_requested.emit("damage_flash")
	TimeManager.register_timer("screen_flash", duration, func():
		EventBus.hud_hide_requested.emit("damage_flash")
	)


## Trigger the crosshair hit flash.
func hit_marker(is_critical: bool = false) -> void:
	EventBus.crosshair_hit_flash_requested.emit(is_critical)


# ── Internal ───────────────────────────────────────────────────────────────────

func _register_vfx_pools() -> void:
	for vfx_id in VFX_CATALOGUE:
		var path: String = VFX_CATALOGUE[vfx_id]
		if ResourceLoader.exists(path):
			var scene: PackedScene = load(path)
			ObjectPool.register(vfx_id, scene, 8, 32)
		# else: placeholder — pool will be registered once asset is created.
