## =============================================================================
## StateSeek — AI Target Search State
## =============================================================================
## Behaviour: Move to last known position of a lost target. Sweep area.
##   Transitions: → Combat (target reacquired), → Patrol (search timeout).
## =============================================================================

class_name StateSeek
extends AIStateBase

const SEEK_TIMEOUT: float    = 15.0
const SWEEP_POINTS: int      = 3
const SWEEP_RADIUS: float    = 8.0
const ARRIVE_THRESHOLD: float = 1.5

var last_known: Vector3      = Vector3.ZERO
var _seek_timer: float       = 0.0
var _sweep_queue: Array[Vector3] = []
var _current_sweep: int      = 0


func _init() -> void:
	state_name = "Seek"


func enter(data: Dictionary = {}) -> void:
	last_known  = data.get("last_known", agent.global_position if agent else Vector3.ZERO)
	_seek_timer = 0.0
	_sweep_queue.clear()
	_current_sweep = 0
	_build_sweep_points()
	if agent:
		agent.navigate_to(last_known)
	Logger.verbose("StateSeek", "Agent %d seeking at %s." % [
		agent.character_id if agent else -1, str(last_known)
	])


func tick(delta: float) -> void:
	if not agent:
		return

	_seek_timer += delta

	# Reacquired target.
	if agent.perception.primary_target:
		agent.current_target = agent.perception.primary_target
		machine.transition_to("Combat")
		return

	# Timeout.
	if _seek_timer >= SEEK_TIMEOUT:
		machine.transition_to("Patrol")
		return

	# Sweep through points.
	if _current_sweep < _sweep_queue.size():
		var target: Vector3 = _sweep_queue[_current_sweep]
		if agent.global_position.distance_to(target) < ARRIVE_THRESHOLD:
			_current_sweep += 1
			if _current_sweep < _sweep_queue.size():
				agent.navigate_to(_sweep_queue[_current_sweep])
		# Face last known position while sweeping.
		var look: Vector3 = Vector3(last_known.x, agent.global_position.y, last_known.z)
		if agent.global_position.distance_to(look) > 0.5:
			agent.look_at(look, Vector3.UP)
	elif agent.nav_agent and agent.nav_agent.is_navigation_finished():
		# All sweep points done — give up.
		machine.transition_to("Patrol")


# ── Internal ───────────────────────────────────────────────────────────────────

func _build_sweep_points() -> void:
	# Build a fan of positions around the last known point.
	_sweep_queue.append(last_known)
	for i in SWEEP_POINTS:
		var angle: float = (TAU / SWEEP_POINTS) * i
		_sweep_queue.append(last_known + Vector3(
			cos(angle) * SWEEP_RADIUS, 0, sin(angle) * SWEEP_RADIUS
		))
