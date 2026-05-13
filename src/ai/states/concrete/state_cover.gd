## =============================================================================
## StateCover — AI Cover Seeking & Holding State
## =============================================================================
## Behaviour: Find and move to the best cover point relative to a threat.
##   Once in cover: peek, fire, duck back. Coordinate with squad.
##   Transitions: → Combat (health recovered, peeking regularly),
##               → Retreat (cover destroyed or no cover available).
## =============================================================================

class_name StateCover
extends AIStateBase

const PEEK_INTERVAL_MIN: float   = 2.0
const PEEK_INTERVAL_MAX: float   = 5.0
const PEEK_DURATION: float       = 1.2
const COVER_HOLD_TIMEOUT: float  = 15.0
const ARRIVE_THRESHOLD: float    = 0.8

var threat_position: Vector3    = Vector3.ZERO
var _cover_point: CoverPoint    = null
var _peek_timer: float          = 0.0
var _next_peek: float           = 3.0
var _is_peeking: bool           = false
var _hold_timer: float          = 0.0
var _moving_to_cover: bool      = true


func _init() -> void:
	state_name = "Cover"


func enter(data: Dictionary = {}) -> void:
	threat_position = data.get("threat_position", agent.global_position + Vector3.FORWARD * 10 if agent else Vector3.ZERO)
	_hold_timer    = 0.0
	_moving_to_cover = true
	_peek_timer    = 0.0
	_next_peek     = randf_range(PEEK_INTERVAL_MIN, PEEK_INTERVAL_MAX)
	_find_cover()
	Logger.verbose("StateCover", "Agent %d seeking cover." % (agent.character_id if agent else -1))


func tick(delta: float) -> void:
	if not agent:
		return

	_hold_timer += delta

	# Timeout — leave cover.
	if _hold_timer >= COVER_HOLD_TIMEOUT:
		_release_cover()
		machine.transition_to("Combat")
		return

	# Health recovered — rejoin combat.
	if agent.get_health_ratio() > 0.65 and not _moving_to_cover:
		_release_cover()
		machine.transition_to("Combat")
		return

	# Moving to cover.
	if _moving_to_cover:
		if not _cover_point:
			_find_cover()
			if not _cover_point:
				machine.transition_to("Retreat")
				return
		if agent.global_position.distance_to(_cover_point.global_position) < ARRIVE_THRESHOLD:
			_moving_to_cover = false
			EventBus.ai_reached_cover.emit(agent.character_id, _cover_point.get_path())
		return

	# In cover — peek management.
	_peek_timer += delta
	if not _is_peeking and _peek_timer >= _next_peek:
		_start_peek()
	elif _is_peeking and _peek_timer >= PEEK_DURATION:
		_end_peek()


func exit() -> void:
	_release_cover()
	_is_peeking = false


# ── Internal ───────────────────────────────────────────────────────────────────

func _find_cover() -> void:
	var new_cover: CoverPoint = CoverSystem.find_best_cover(agent, threat_position)
	if new_cover:
		CoverSystem.claim_cover(agent, new_cover)
		_cover_point = new_cover
		agent.navigate_to(new_cover.global_position)
		Logger.verbose("StateCover", "Agent %d moving to cover at %s." % [
			agent.character_id, str(new_cover.global_position)
		])
	else:
		Logger.debug("StateCover", "No cover found for agent %d." % agent.character_id)


func _release_cover() -> void:
	if agent:
		CoverSystem.release_cover(agent)
	_cover_point = null


func _start_peek() -> void:
	_is_peeking = true
	_peek_timer = 0.0
	_next_peek  = randf_range(PEEK_INTERVAL_MIN, PEEK_INTERVAL_MAX)
	# Fire at threat while peeking.
	if agent and agent.current_target and agent.current_target.is_alive:
		agent.fire_at_target()


func _end_peek() -> void:
	_is_peeking = false
	_peek_timer = 0.0
