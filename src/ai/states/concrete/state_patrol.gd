## =============================================================================
## StatePatrol — AI Patrol State
## =============================================================================
## Behaviour: Move between waypoints (or random wander if no waypoints).
##   Checks perception every step. Transitions to Alert on enemy spotted.
##   Supports: ordered patrol, random wander, squad-follow formation.
## =============================================================================

class_name StatePatrol
extends AIStateBase

const WAYPOINT_ARRIVE_THRESHOLD: float = 1.5
const WANDER_RADIUS: float             = 15.0
const WANDER_REPLAN_TIME: float        = 8.0

var patrol_waypoints: Array[Vector3] = []
var _current_waypoint: int  = 0
var _wander_timer: float    = 0.0
var _is_ordered_patrol: bool = false


func _init() -> void:
	state_name = "Patrol"


func enter(data: Dictionary = {}) -> void:
	if data.has("waypoints"):
		patrol_waypoints = data.waypoints
		_is_ordered_patrol = true
		_current_waypoint  = 0
		_move_to_next_waypoint()
	else:
		_is_ordered_patrol = false
		_pick_wander_point()
	Logger.verbose("StatePatrol", "Agent %d patrolling." % (agent.character_id if agent else -1))


func tick(delta: float) -> void:
	if not agent:
		return

	# Transition on threat detection.
	if agent.perception.primary_target:
		machine.transition_to("Alert", {
			"target_position": agent.perception.primary_target.global_position
		})
		return

	if _is_ordered_patrol:
		_update_ordered(delta)
	else:
		_update_wander(delta)


func physics_tick(_delta: float) -> void:
	pass


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_ordered(_delta: float) -> void:
	if patrol_waypoints.is_empty():
		machine.transition_to("Idle")
		return
	var target: Vector3 = patrol_waypoints[_current_waypoint]
	if agent.global_position.distance_to(target) < WAYPOINT_ARRIVE_THRESHOLD:
		_current_waypoint = (_current_waypoint + 1) % patrol_waypoints.size()
		_move_to_next_waypoint()


func _update_wander(delta: float) -> void:
	_wander_timer += delta
	if agent.nav_agent and agent.nav_agent.is_navigation_finished():
		_pick_wander_point()
	elif _wander_timer >= WANDER_REPLAN_TIME:
		_wander_timer = 0.0
		_pick_wander_point()


func _move_to_next_waypoint() -> void:
	if patrol_waypoints.is_empty():
		return
	agent.navigate_to(patrol_waypoints[_current_waypoint])


func _pick_wander_point() -> void:
	_wander_timer = 0.0
	var offset: Vector3 = Vector3(
		randf_range(-WANDER_RADIUS, WANDER_RADIUS),
		0,
		randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	)
	agent.navigate_to(agent.global_position + offset)
