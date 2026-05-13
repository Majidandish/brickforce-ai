## =============================================================================
## AIStateBase — Abstract Base for All AI States
## =============================================================================
## Purpose:
##   Interface contract for every state in the AIStateMachine.
##   Each concrete state (Idle, Patrol, Combat, Cover, etc.) extends this.
## =============================================================================

class_name AIStateBase
extends Node

## Unique name identifying this state.
var state_name: String = "Unnamed"
## Back-reference to the owning state machine.
var machine: AIStateMachine = null

## Shortcut to the AI agent (character).
var agent: CharacterBase:
	get: return machine.agent if machine else null

## Called when entering this state.
func enter(_data: Dictionary = {}) -> void:
	pass

## Called when leaving this state.
func exit() -> void:
	pass

## Called every process frame while active.
func tick(_delta: float) -> void:
	pass

## Called every physics frame while active.
func physics_tick(_delta: float) -> void:
	pass
