## =============================================================================
## AIStateMachine — Hierarchical Finite State Machine for AI Agents
## =============================================================================
## Purpose:
##   Stack-based HFSM managing AI behaviour states. States are independent
##   nodes that implement enter/exit/tick/physics_tick hooks. The machine
##   handles transitions, state history, and debug visualisation.
##
## States: Idle, Patrol, Alert, Seek, Combat, Cover, Flanking, Retreat,
##         Revive, Dead, Downed, Looting, SquadFollow, Berserk
## =============================================================================

class_name AIStateMachine
extends Node

signal state_changed(old_state: String, new_state: String)

## The owning AI agent (AICharacter).
var agent: CharacterBase = null
## Currently active state node.
var current_state: AIStateBase = null
## State history stack (for returning to previous behaviour).
var state_stack: Array[AIStateBase] = []
## All registered states.
var _states: Dictionary = {}  # name -> AIStateBase


func _ready() -> void:
	name = "AIStateMachine"
	# Collect child state nodes.
	for child in get_children():
		if child is AIStateBase:
			_states[child.state_name] = child
			child.machine = self
	Logger.debug("AIStateMachine", "Loaded %d states." % _states.size())


func _process(delta: float) -> void:
	if current_state:
		current_state.tick(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_tick(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with an agent reference and enter the default state.
func initialize(ai_agent: CharacterBase, default_state: String = "Idle") -> void:
	agent = ai_agent
	transition_to(default_state)


## Transition to a named state.
func transition_to(state_name: String, data: Dictionary = {}) -> void:
	if not _states.has(state_name):
		Logger.warn("AIStateMachine", "Unknown state: %s" % state_name)
		return

	var old_name: String = current_state.state_name if current_state else "None"

	if current_state:
		current_state.exit()

	current_state = _states[state_name]
	current_state.enter(data)

	state_changed.emit(old_name, state_name)
	EventBus.ai_state_changed.emit(
		agent.character_id if agent else -1, old_name, state_name
	)
	Logger.verbose("AIStateMachine", "Agent %d: %s → %s" % [
		agent.character_id if agent else -1, old_name, state_name
	])


## Push state onto stack (e.g. briefly investigate noise, then return to patrol).
func push_state(state_name: String, data: Dictionary = {}) -> void:
	if current_state:
		state_stack.push_back(current_state)
	transition_to(state_name, data)


## Return to the previous stacked state.
func pop_state() -> void:
	if state_stack.is_empty():
		transition_to("Idle")
		return
	var prev: AIStateBase = state_stack.pop_back()
	transition_to(prev.state_name)


## Returns the current state name.
func get_current_state_name() -> String:
	return current_state.state_name if current_state else "None"


## Returns true if currently in a given state.
func is_in_state(state_name: String) -> bool:
	return current_state != null and current_state.state_name == state_name
