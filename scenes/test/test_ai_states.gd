## =============================================================================
## TestAIStates — AI State Machine Integration Test Script
## =============================================================================
## Tests: AIStateMachine transitions, StateIdle, StatePatrol, StateAlert,
##        PerceptionSystem threat detection, SquadAICommander command dispatch.
## =============================================================================

extends Node

const PASS: String = "[PASS]"
const FAIL: String = "[FAIL]"
var _results: Array[String] = []


func _ready() -> void:
	print("=== TEST: AIStates ===")
	_test_state_machine()
	_test_perception_system()
	_test_squad_commander()
	_finish()


func _test_state_machine() -> void:
	print("  -- AIStateMachine --")
	var sm: AIStateMachine = AIStateMachine.new()
	add_child(sm)
	await get_tree().process_frame

	# Manually add state children.
	var idle: StateIdle    = StateIdle.new()
	var patrol: StatePatrol = StatePatrol.new()
	sm.add_child(idle)
	sm.add_child(patrol)
	idle.machine   = sm
	patrol.machine = sm
	sm._states["Idle"]   = idle
	sm._states["Patrol"] = patrol
	await get_tree().process_frame

	sm.transition_to("Idle")
	_record(sm.get_current_state_name() == "Idle", "Initial transition to Idle")

	sm.transition_to("Patrol")
	_record(sm.get_current_state_name() == "Patrol", "Transition to Patrol")
	_record(not sm.is_in_state("Idle"), "Not in Idle after switching")

	sm.push_state("Idle")
	_record(sm.get_current_state_name() == "Idle", "Push state to Idle")
	_record(sm.state_stack.size() == 1, "State stack has 1 entry")

	sm.pop_state()
	_record(sm.get_current_state_name() == "Patrol", "Pop back to Patrol")

	sm.queue_free()


func _test_perception_system() -> void:
	print("  -- PerceptionSystem --")
	var ps: PerceptionSystem = PerceptionSystem.new()
	add_child(ps)
	await get_tree().process_frame

	_record(ps.perceived_targets.is_empty(), "No targets initially")
	_record(ps.primary_target == null, "No primary target initially")
	_record(ps.sight_range == 30.0, "Default sight range is 30m")

	ps.queue_free()


func _test_squad_commander() -> void:
	print("  -- SquadAICommander --")
	var cmdr: SquadAICommander = SquadAICommander.new()
	add_child(cmdr)
	await get_tree().process_frame

	cmdr.initialize(0, [], null)
	_record(cmdr.threat_level == 0, "Initial threat level is 0")
	_record(cmdr.current_objective == "roam", "Default objective is roam")

	cmdr.receive_command("hold", {})
	_record(cmdr.current_objective == "hold", "Command sets objective")

	cmdr.queue_free()


func _record(passed: bool, description: String) -> void:
	var tag: String = PASS if passed else FAIL
	var msg: String = "%s %s" % [tag, description]
	_results.append(msg)
	print(msg)


func _finish() -> void:
	var total: int  = _results.size()
	var passed: int = _results.filter(func(r): return r.begins_with(PASS)).size()
	print("=== RESULT: %d/%d PASS ===" % [passed, total])
