## =============================================================================
## PerceptionSystem — AI Sensory Processing (Sight, Sound, Memory)
## =============================================================================
## Purpose:
##   Gives AI agents realistic sensory capabilities. Performs efficient
##   cone-of-sight raycasts, sound propagation checks, memory decay for
##   last-known positions, and threat prioritisation scoring.
##   Designed to run on a staggered timer to avoid per-frame ray cost.
## =============================================================================

class_name PerceptionSystem
extends Node

const SIGHT_CHECK_INTERVAL: float = 0.12   # seconds between sight updates
const MEMORY_DECAY_TIME: float    = 8.0    # seconds before target forgotten
const THREAT_DECAY_RATE: float    = 0.2    # threat score decay per second

signal enemy_spotted(target: CharacterBase, position: Vector3)
signal enemy_lost(target: CharacterBase, last_known: Vector3)
signal noise_heard(origin: Vector3, intensity: float)

## Owning AI character.
var owner_agent: CharacterBase = null

## Populated from CharacterData.
var sight_range: float   = 30.0
var fov_degrees: float   = 110.0
var hearing_range: float = 20.0
var reaction_time: float = 0.4
var accuracy: float      = 0.8

## Currently spotted targets: target_id -> PerceivedTarget
var perceived_targets: Dictionary = {}

## Threat scores: target_id -> float (higher = more dangerous)
var threat_scores: Dictionary = {}

## Best current target (highest threat, in sight).
var primary_target: CharacterBase = null

# ── Internal ───────────────────────────────────────────────────────────────────
var _sight_timer: float = 0.0
var _space_state: PhysicsDirectSpaceState3D = null


func _ready() -> void:
	name = "PerceptionSystem"
	EventBus.explosion_occurred.connect(_on_explosion)


func _physics_process(delta: float) -> void:
	_sight_timer += delta
	if _sight_timer >= SIGHT_CHECK_INTERVAL:
		_sight_timer = 0.0
		_run_sight_check()

	_decay_memory(delta)
	_update_primary_target()


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with the owning agent.
func initialize(agent: CharacterBase) -> void:
	owner_agent  = agent
	if agent.character_data:
		sight_range   = agent.character_data.detection_range
		hearing_range = agent.character_data.hearing_range
		reaction_time = agent.character_data.reaction_time
		accuracy      = agent.character_data.accuracy
	_space_state  = get_world_3d().direct_space_state


## Report a heard sound (called by SoundPropagation system or grenades).
func hear_sound(origin: Vector3, intensity: float) -> void:
	if owner_agent == null:
		return
	var dist: float = owner_agent.global_position.distance_to(origin)
	if dist > hearing_range * intensity:
		return
	noise_heard.emit(origin, intensity)
	Logger.verbose("PerceptionSystem", "Agent %d heard noise at dist %.1f" % [
		owner_agent.character_id, dist
	])


## Check if a specific target is in sight right now.
func can_see(target: CharacterBase) -> bool:
	if not is_instance_valid(target) or not target.is_alive:
		return false
	return _check_sight_to(target)


## Returns the last known position of a target.
func get_last_known_position(target_id: int) -> Vector3:
	if perceived_targets.has(target_id):
		return perceived_targets[target_id].last_known_position
	return Vector3.INF


## Returns true if we have any memory of a target (even if lost).
func has_memory_of(target_id: int) -> bool:
	return perceived_targets.has(target_id)


## Force-clear memory of a specific target.
func forget(target_id: int) -> void:
	if perceived_targets.has(target_id):
		var target: CharacterBase = perceived_targets[target_id].target
		perceived_targets.erase(target_id)
		threat_scores.erase(target_id)
		enemy_lost.emit(target, Vector3.ZERO)
		EventBus.ai_lost_target.emit(owner_agent.character_id if owner_agent else -1, Vector3.ZERO)


# ── Internal ───────────────────────────────────────────────────────────────────

func _run_sight_check() -> void:
	if not owner_agent or not owner_agent.is_alive:
		return
	var potential_targets: Array = _get_potential_targets()

	for target in potential_targets:
		if not is_instance_valid(target) or not target.is_alive:
			continue
		if not owner_agent.is_enemy_of(target):
			continue

		if _check_sight_to(target):
			_register_sighting(target)


func _check_sight_to(target: CharacterBase) -> bool:
	var origin: Vector3 = owner_agent.global_position + Vector3(0, 1.7, 0)  # Eye height
	var target_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var dist: float = origin.distance_to(target_pos)

	# Range check.
	if dist > sight_range:
		return false

	# FOV check.
	var dir_to_target: Vector3 = (target_pos - origin).normalized()
	var forward: Vector3 = -owner_agent.global_basis.z
	var angle: float = rad_to_deg(acos(forward.dot(dir_to_target)))
	if angle > fov_degrees * 0.5:
		return false

	# Raycast occlusion check.
	if not _space_state:
		return true
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, target_pos)
	query.exclude = [owner_agent]
	query.collision_mask = 1  # World geometry only
	var result: Dictionary = _space_state.intersect_ray(query)
	return result.is_empty()  # Empty = no occlusion = can see.


func _register_sighting(target: CharacterBase) -> void:
	var target_id: int = target.character_id
	var was_known: bool = perceived_targets.has(target_id)

	perceived_targets[target_id] = {
		"target":             target,
		"last_known_position": target.global_position,
		"last_seen_time":     Time.get_unix_time_from_system(),
		"in_sight":           true,
	}

	# Threat scoring: closer + lower health enemy = higher threat.
	var dist: float     = owner_agent.global_position.distance_to(target.global_position)
	var hp_factor: float = 1.0 - target.get_health_ratio()
	threat_scores[target_id] = (1.0 - dist / sight_range) * 0.5 + hp_factor * 0.5

	if not was_known:
		enemy_spotted.emit(target, target.global_position)
		EventBus.ai_spotted_enemy.emit(
			owner_agent.character_id, target_id, target.global_position
		)


func _decay_memory(delta: float) -> void:
	var now: float = Time.get_unix_time_from_system()
	for id in perceived_targets.keys():
		var entry: Dictionary = perceived_targets[id]
		var elapsed: float = now - entry.last_seen_time
		if elapsed > MEMORY_DECAY_TIME:
			var target: CharacterBase = entry.target
			perceived_targets.erase(id)
			threat_scores.erase(id)
			if is_instance_valid(target):
				enemy_lost.emit(target, entry.last_known_position)
				EventBus.ai_lost_target.emit(
					owner_agent.character_id if owner_agent else -1,
					entry.last_known_position
				)
		else:
			# Decay in-sight flag over time.
			entry.in_sight = elapsed < SIGHT_CHECK_INTERVAL * 2.0
		# Decay threat score.
		if threat_scores.has(id):
			threat_scores[id] = max(0.0, threat_scores[id] - THREAT_DECAY_RATE * delta)


func _update_primary_target() -> void:
	var best_id: int    = -1
	var best_score: float = -1.0
	for id in threat_scores:
		if threat_scores[id] > best_score:
			best_score = threat_scores[id]
			best_id    = id
	if best_id >= 0 and perceived_targets.has(best_id):
		primary_target = perceived_targets[best_id].target
	else:
		primary_target = null


func _get_potential_targets() -> Array:
	# Sphere-cast for nearby characters (uses Godot physics layer).
	if not _space_state:
		return []
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = sight_range
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = Transform3D(Basis(), owner_agent.global_position)
	params.collision_mask = 2 | 4  # Player + Enemy layers
	var results: Array = _space_state.intersect_shape(params, 32)
	var targets: Array = []
	for r in results:
		if r.collider is CharacterBase and r.collider != owner_agent:
			targets.append(r.collider)
	return targets


func _on_explosion(origin: Vector3, _radius: float, _damage: float) -> void:
	hear_sound(origin, 2.0)
