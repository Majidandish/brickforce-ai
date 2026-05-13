## =============================================================================
## AICharacter — AI-Controlled Character (extends CharacterBase)
## =============================================================================
## Purpose:
##   Full AI character with integrated StateMachine, PerceptionSystem,
##   NavAgent movement, cover system, and squad communication hooks.
##   Receives tactical commands from SquadAICommander and translates them
##   into low-level state machine transitions.
## =============================================================================

class_name AICharacter
extends CharacterBase

# ── Components ─────────────────────────────────────────────────────────────────
@onready var state_machine: AIStateMachine  = $AIStateMachine
@onready var perception: PerceptionSystem   = $PerceptionSystem
@onready var cover_detector: Area3D         = $CoverDetector

# ── Navigation ────────────────────────────────────────────────────────────────
const ARRIVAL_THRESHOLD: float = 0.5
const PATH_UPDATE_INTERVAL: float = 0.25

var _nav_target: Vector3    = Vector3.ZERO
var _path_timer: float      = 0.0
var _is_navigating: bool    = false

# ── Cover System ──────────────────────────────────────────────────────────────
var _current_cover: Node3D  = null
var _cover_position: Vector3 = Vector3.ZERO
var _peek_side: int          = 1   # -1 left, 1 right

# ── Combat State ──────────────────────────────────────────────────────────────
var current_target: CharacterBase = null
var _fire_timer: float       = 0.0
var _burst_active: bool      = false
var _suppress_target: CharacterBase = null

# ── Squad Reference ───────────────────────────────────────────────────────────
var squad_id: int           = -1
var squad_role: int         = 0


func _ready() -> void:
	super._ready()
	faction = character_data.faction if character_data else 2

	# Wire perception events to state machine.
	perception.initialize(self)
	perception.enemy_spotted.connect(_on_enemy_spotted)
	perception.enemy_lost.connect(_on_enemy_lost)

	# Start in idle state.
	state_machine.initialize(self, "Idle")
	Logger.info("AICharacter", "AI ready: %s (faction %d)" % [name, faction])


func _process(delta: float) -> void:
	super._process(delta)
	_update_navigation(delta)
	_update_combat(delta)


# ── Override: Movement ─────────────────────────────────────────────────────────

func _apply_movement(delta: float) -> void:
	if not _is_navigating:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)
		move_and_slide()
		return

	if not nav_agent or nav_agent.is_navigation_finished():
		_is_navigating = false
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position).normalized()
	direction.y = 0.0

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	# Face movement direction.
	if direction.length() > 0.1:
		var look_target: Vector3 = global_position + direction
		look_at(look_target, Vector3.UP)

	move_and_slide()


# ── Public Command Interface ───────────────────────────────────────────────────

## Called by SquadAICommander to issue tactical commands.
func receive_ai_command(command: String, data: Dictionary = {}) -> void:
	Logger.verbose("AICharacter", "%s received: %s %s" % [name, command, JSON.stringify(data)])
	match command:
		"engage":
			var target_id: int = data.get("target_id", -1)
			_find_and_engage(target_id)
		"flank_to":
			_navigate_to(data.get("flank_position", global_position))
			state_machine.transition_to("Flanking")
		"suppress":
			var target_id: int = data.get("target_id", -1)
			_find_and_suppress(target_id)
		"take_cover":
			state_machine.transition_to("Cover")
		"retreat":
			state_machine.transition_to("Retreat")
		"patrol_to":
			_navigate_to(data.get("position", global_position))
			state_machine.transition_to("Patrol")
		"hold_position":
			_is_navigating = false
			state_machine.transition_to("Idle")
		"revive_ally":
			state_machine.transition_to("Revive", data)
		"retreat_to_cover":
			state_machine.transition_to("Retreat")
		"move_to":
			_navigate_to(data.get("position", global_position))
		"support_cover":
			state_machine.transition_to("Idle")


## Navigate to a world position using NavigationAgent3D.
func navigate_to(target: Vector3) -> void:
	_navigate_to(target)


## Returns the current perceived primary threat.
func get_primary_target() -> CharacterBase:
	return perception.primary_target


## Returns true if this AI is currently in cover.
func is_in_cover() -> bool:
	return _current_cover != null


## Claim a cover node (called by cover system).
func claim_cover(cover_node: Node3D, cover_pos: Vector3) -> void:
	if _current_cover:
		release_cover()
	_current_cover  = cover_node
	_cover_position = cover_pos
	EventBus.ai_cover_claimed.emit(character_id, get_path_to(cover_node))


## Release current cover.
func release_cover() -> void:
	if _current_cover:
		EventBus.ai_cover_released.emit(character_id, get_path_to(_current_cover))
	_current_cover   = null
	_cover_position  = Vector3.ZERO


## Attempt to fire at the current target.
func fire_at_target() -> bool:
	if not active_weapon or not current_target or not current_target.is_alive:
		return false
	# Apply accuracy — skip shot randomly based on accuracy stat.
	var accuracy: float = character_data.accuracy if character_data else 0.7
	if randf() > accuracy:
		return false
	var dir: Vector3 = (current_target.global_position - global_position).normalized()
	return active_weapon.try_fire(dir)


# ── Internal ───────────────────────────────────────────────────────────────────

func _navigate_to(target: Vector3) -> void:
	_nav_target     = target
	_is_navigating  = true
	if nav_agent:
		nav_agent.target_position = target


func _update_navigation(delta: float) -> void:
	_path_timer += delta
	if _path_timer >= PATH_UPDATE_INTERVAL and _is_navigating:
		_path_timer = 0.0
		if nav_agent and nav_agent.is_target_reachable():
			nav_agent.target_position = _nav_target


func _update_combat(delta: float) -> void:
	if not current_target or not current_target.is_alive:
		current_target = perception.primary_target
		return
	# Face target.
	var look_pos: Vector3 = Vector3(current_target.global_position.x, global_position.y, current_target.global_position.z)
	look_at(look_pos, Vector3.UP)


func _find_and_engage(target_id: int) -> void:
	# Find target in perception memory.
	for id in perception.perceived_targets:
		var entry: Dictionary = perception.perceived_targets[id]
		if entry.target.character_id == target_id:
			current_target = entry.target
			state_machine.transition_to("Combat")
			return
	state_machine.transition_to("Seek")


func _find_and_suppress(target_id: int) -> void:
	for id in perception.perceived_targets:
		var entry: Dictionary = perception.perceived_targets[id]
		if entry.target.character_id == target_id:
			_suppress_target = entry.target
			state_machine.transition_to("Suppress")
			return


func _on_enemy_spotted(target: CharacterBase, pos: Vector3) -> void:
	current_target = target
	if state_machine.is_in_state("Idle") or state_machine.is_in_state("Patrol"):
		state_machine.transition_to("Alert", { "target_position": pos })
	# Notify squad commander.
	EventBus.ai_spotted_enemy.emit(character_id, target.character_id, pos)


func _on_enemy_lost(_target: CharacterBase, last_known: Vector3) -> void:
	if state_machine.is_in_state("Combat"):
		state_machine.transition_to("Seek", { "last_known": last_known })
	current_target = perception.primary_target


func _on_death(killer_id: int, _cause: String) -> void:
	release_cover()
	state_machine.transition_to("Dead")
