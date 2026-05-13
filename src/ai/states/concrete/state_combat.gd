## =============================================================================
## StateCombat — AI Active Combat Engagement State
## =============================================================================
## Behaviour: Actively engage a known target. Strafe/reposition while firing.
##   Uses accuracy from CharacterData. Seeks cover periodically.
##   Transitions: → Cover (health low or suppressed), → Seek (target lost),
##               → Retreat (health critical), → Idle (no targets).
## =============================================================================

class_name StateCombat
extends AIStateBase

const FIRE_CHECK_INTERVAL: float   = 0.15
const REPOSITION_INTERVAL: float   = 3.5
const COVER_SEEK_HEALTH_THRESHOLD: float = 0.45
const RETREAT_HEALTH_THRESHOLD: float   = 0.20
const STRAFE_SPEED_MULT: float     = 0.7
const MAX_ENGAGEMENT_RANGE: float  = 40.0

var _fire_timer: float      = 0.0
var _reposition_timer: float = 0.0
var _strafing: bool          = false
var _strafe_dir: int         = 1  # -1 or 1.


func _init() -> void:
	state_name = "Combat"


func enter(data: Dictionary = {}) -> void:
	_fire_timer       = 0.0
	_reposition_timer = 0.0
	_strafing = false
	Logger.verbose("StateCombat", "Agent %d entering combat." % (agent.character_id if agent else -1))


func tick(delta: float) -> void:
	if not agent:
		return

	var target: CharacterBase = agent.current_target
	if not target or not target.is_alive:
		target = agent.perception.primary_target
		if not target:
			machine.transition_to("Idle")
			return
		agent.current_target = target

	# Health-based transitions.
	var hp_ratio: float = agent.get_health_ratio()
	if hp_ratio < RETREAT_HEALTH_THRESHOLD:
		machine.transition_to("Retreat")
		return
	if hp_ratio < COVER_SEEK_HEALTH_THRESHOLD:
		machine.transition_to("Cover", { "threat_position": target.global_position })
		return

	# Target lost.
	if not agent.perception.has_memory_of(target.character_id):
		machine.transition_to("Seek", { "last_known": agent.perception.get_last_known_position(target.character_id) })
		return

	# Range check — too far, close the distance.
	var dist: float = agent.global_position.distance_to(target.global_position)
	if dist > MAX_ENGAGEMENT_RANGE:
		agent.navigate_to(target.global_position)
		return

	# Firing logic.
	_fire_timer += delta
	if _fire_timer >= FIRE_CHECK_INTERVAL:
		_fire_timer = 0.0
		if agent.perception.can_see(target):
			agent.fire_at_target()

	# Reposition / strafe.
	_reposition_timer += delta
	if _reposition_timer >= REPOSITION_INTERVAL:
		_reposition_timer = 0.0
		_strafe_dir = -_strafe_dir
		_pick_reposition()


func _pick_reposition() -> void:
	if not agent or not agent.current_target:
		return
	var right: Vector3 = agent.global_basis.x * _strafe_dir * randf_range(3.0, 7.0)
	var forward: Vector3 = -agent.global_basis.z * randf_range(-2.0, 2.0)
	agent.navigate_to(agent.global_position + right + forward)
