## =============================================================================
## StateRetreat — AI Retreat / Fallback State
## =============================================================================
## Behaviour: Move away from threats to find safety and recover.
##   Broadcasts retreat to squad commander.
##   Transitions: → Cover (safe position found), → Idle (health recovered).
## =============================================================================

class_name StateRetreat
extends AIStateBase

const RETREAT_DISTANCE: float    = 20.0
const HEALTH_RECOVERY_THRESHOLD: float = 0.55
const RETREAT_TIMEOUT: float     = 10.0

var _retreat_timer: float = 0.0
var _retreat_target: Vector3 = Vector3.ZERO


func _init() -> void:
	state_name = "Retreat"


func enter(data: Dictionary = {}) -> void:
	_retreat_timer  = 0.0
	_retreat_target = data.get("direction", _calculate_retreat_target())
	if agent:
		agent.navigate_to(_retreat_target)
	EventBus.ai_retreating.emit(agent.character_id if agent else -1)
	Logger.verbose("StateRetreat", "Agent %d retreating." % (agent.character_id if agent else -1))


func tick(delta: float) -> void:
	if not agent:
		return

	_retreat_timer += delta

	# Health recovered → try to find cover or re-engage.
	if agent.get_health_ratio() >= HEALTH_RECOVERY_THRESHOLD:
		if agent.perception.primary_target:
			machine.transition_to("Cover", {
				"threat_position": agent.perception.primary_target.global_position
			})
		else:
			machine.transition_to("Idle")
		return

	# Timeout.
	if _retreat_timer >= RETREAT_TIMEOUT:
		machine.transition_to("Idle")
		return

	# Arrived at retreat point — keep retreating.
	if agent.nav_agent and agent.nav_agent.is_navigation_finished():
		_retreat_target = _calculate_retreat_target()
		agent.navigate_to(_retreat_target)


# ── Internal ───────────────────────────────────────────────────────────────────

func _calculate_retreat_target() -> Vector3:
	if not agent:
		return Vector3.ZERO
	var away_dir: Vector3 = Vector3.ZERO

	# Move away from known threats.
	for id in agent.perception.perceived_targets:
		var entry: Dictionary = agent.perception.perceived_targets[id]
		var threat_dir: Vector3 = (agent.global_position - entry.last_known_position).normalized()
		away_dir += threat_dir

	if away_dir.length() < 0.1:
		# No known threats — retreat backwards relative to facing.
		away_dir = agent.global_basis.z  # Backward.

	away_dir = away_dir.normalized()
	return agent.global_position + away_dir * RETREAT_DISTANCE
