## =============================================================================
## StateAlert — AI Alert / Investigation State
## =============================================================================
## Behaviour: Something suspicious heard/spotted at a known position.
##   Move towards last known position to investigate.
##   Transitions: → Combat (confirmed enemy), → Seek (area reached, no target),
##               → Idle (timer expires without finding anything).
## =============================================================================

class_name StateAlert
extends AIStateBase

const ALERT_DURATION: float     = 12.0  # Give up after this long.
const ARRIVE_THRESHOLD: float   = 2.0

var target_position: Vector3 = Vector3.ZERO
var _alert_timer: float      = 0.0
var _arrived: bool           = false


func _init() -> void:
	state_name = "Alert"


func enter(data: Dictionary = {}) -> void:
	target_position = data.get("target_position", agent.global_position if agent else Vector3.ZERO)
	_alert_timer    = 0.0
	_arrived        = false
	if agent:
		agent.navigate_to(target_position)
	EventBus.ai_alerted.emit(
		agent.character_id if agent else -1, target_position
	)
	Logger.verbose("StateAlert", "Agent %d alerted at %s." % [
		agent.character_id if agent else -1, str(target_position)
	])


func tick(delta: float) -> void:
	if not agent:
		return

	_alert_timer += delta

	# Confirmed enemy.
	if agent.perception.primary_target:
		agent.current_target = agent.perception.primary_target
		machine.transition_to("Combat")
		return

	# Timeout.
	if _alert_timer >= ALERT_DURATION:
		machine.transition_to("Idle")
		return

	# Arrived at investigate point.
	if not _arrived and agent.global_position.distance_to(target_position) < ARRIVE_THRESHOLD:
		_arrived = true
		# Look around for a moment, then seek.
		TimeManager.register_timer(
			"alert_seek_%d" % agent.character_id,
			2.5,
			func(): machine.transition_to("Seek", { "last_known": target_position })
		)


func exit() -> void:
	_alert_timer = 0.0
	_arrived     = false
