## =============================================================================
## StateIdle — AI Idle State
## =============================================================================
## Behaviour: Character stands in place, scanning environment.
##   Transitions out on: enemy spotted, noise heard, squad command.
##   Idles with randomised look-around to feel alive.
## =============================================================================

class_name StateIdle
extends AIStateBase

const IDLE_LOOK_INTERVAL_MIN: float = 2.0
const IDLE_LOOK_INTERVAL_MAX: float = 6.0

var _look_timer: float  = 0.0
var _next_look: float   = 3.0
var _look_target: Vector3 = Vector3.ZERO


func _init() -> void:
	state_name = "Idle"


func enter(data: Dictionary = {}) -> void:
	if agent and agent.nav_agent:
		agent.nav_agent.target_position = agent.global_position
	_schedule_next_look()
	Logger.verbose("StateIdle", "Agent %d entered Idle." % (agent.character_id if agent else -1))


func tick(delta: float) -> void:
	if not agent:
		return

	# Check perception.
	if agent.perception.primary_target:
		machine.transition_to("Alert", {
			"target_position": agent.perception.primary_target.global_position
		})
		return

	# Idle look-around.
	_look_timer += delta
	if _look_timer >= _next_look:
		_look_timer = 0.0
		_do_look_around()
		_schedule_next_look()


func exit() -> void:
	_look_timer = 0.0


# ── Internal ───────────────────────────────────────────────────────────────────

func _schedule_next_look() -> void:
	_next_look = randf_range(IDLE_LOOK_INTERVAL_MIN, IDLE_LOOK_INTERVAL_MAX)
	_look_target = agent.global_position + Vector3(
		randf_range(-1, 1), 0, randf_range(-1, 1)
	).normalized() * 5.0


func _do_look_around() -> void:
	if agent and _look_target != Vector3.ZERO:
		var look: Vector3 = Vector3(_look_target.x, agent.global_position.y, _look_target.z)
		agent.look_at(look, Vector3.UP)
