## =============================================================================
## StateRevive — AI Revive Ally State
## =============================================================================
## Behaviour: Move to a downed squad mate and revive them.
##   Interrupts if under fire. Priority: revive > combat.
## =============================================================================

class_name StateRevive
extends AIStateBase

const REVIVE_RANGE: float      = 1.5
const REVIVE_DURATION: float   = 4.0
const ABORT_ON_DAMAGE: bool    = true

var target_ally_id: int       = -1
var _target_ally: CharacterBase = null
var _revive_timer: float      = 0.0
var _reviving: bool           = false


func _init() -> void:
	state_name = "Revive"


func enter(data: Dictionary = {}) -> void:
	target_ally_id  = data.get("target_id", -1)
	_revive_timer   = 0.0
	_reviving       = false
	_target_ally    = _find_ally(target_ally_id)
	if _target_ally and agent:
		agent.navigate_to(_target_ally.global_position)
	Logger.verbose("StateRevive", "Agent %d going to revive %d." % [
		agent.character_id if agent else -1, target_ally_id
	])


func tick(delta: float) -> void:
	if not agent or not _target_ally:
		machine.transition_to("Idle")
		return

	# If ally is already revived or dead.
	if not _target_ally.is_downed:
		machine.transition_to("Idle")
		return

	# Abort if under fire (enemy spotted while reviving).
	if ABORT_ON_DAMAGE and agent.perception.primary_target:
		machine.transition_to("Combat")
		return

	var dist: float = agent.global_position.distance_to(_target_ally.global_position)
	if dist > REVIVE_RANGE:
		if agent.nav_agent and agent.nav_agent.is_navigation_finished():
			agent.navigate_to(_target_ally.global_position)
		return

	# In range — perform revive.
	_reviving = true
	_revive_timer += delta
	if _revive_timer >= REVIVE_DURATION:
		_target_ally.revive(agent.character_id)
		EventBus.player_revived.emit(_target_ally.character_id, agent.character_id)
		machine.transition_to("Idle")


func exit() -> void:
	_reviving     = false
	_revive_timer = 0.0


# ── Internal ───────────────────────────────────────────────────────────────────

func _find_ally(id: int) -> CharacterBase:
	var all: Array = get_tree().get_nodes_in_group("characters") if agent else []
	for n in all:
		if n is CharacterBase and (n as CharacterBase).character_id == id:
			return n as CharacterBase
	return null
