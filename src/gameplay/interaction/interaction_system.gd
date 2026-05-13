## =============================================================================
## InteractionSystem — World Interaction Detection & Processing
## =============================================================================
## Architecture:
##   Attached to a character. Uses a shaped overlap query to find nearby
##   interactables, picks the closest/most relevant, and manages the
##   interact state machine (available → started → held → completed).
##
##   Decoupled: reads input flags (not InputManager directly) so it works
##   for both player and AI characters.
## =============================================================================

class_name InteractionSystem
extends Node

const SCAN_INTERVAL: float    = 0.08   # Seconds between overlap scans.
const SCAN_RADIUS: float      = 3.5
const INTERACTION_LAYER: int  = 8      # Physics layer for interactables.

# ── Signals ────────────────────────────────────────────────────────────────────
signal target_changed(old_target: InteractableBase, new_target: InteractableBase)
signal interact_prompt_updated(prompt: String, visible: bool)
signal interact_completed(target: InteractableBase)

# ── State ──────────────────────────────────────────────────────────────────────
var owner_character: CharacterBase  = null
var current_target: InteractableBase = null
var _is_holding: bool               = false
var _scan_timer: float              = 0.0
var _nearby: Array[InteractableBase] = []


func _ready() -> void:
	name = "InteractionSystem"


func _process(delta: float) -> void:
	_update_scan(delta)
	if _is_holding and current_target:
		current_target.update_interact(owner_character, delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize with the owning character.
func initialize(character: CharacterBase) -> void:
	owner_character = character


## Call when interact input is pressed.
func on_interact_pressed() -> void:
	if not current_target:
		return
	if current_target.begin_interact(owner_character):
		_is_holding = (current_target.interact_type == InteractableBase.InteractType.HOLD)
		if not _is_holding:
			interact_completed.emit(current_target)
	else:
		Logger.debug("InteractionSystem", "Interact rejected by target.")


## Call when interact input is released.
func on_interact_released() -> void:
	if _is_holding and current_target:
		current_target.cancel_interact(owner_character)
	_is_holding = false


## Manually set a target (for AI characters that skip scan).
func force_target(target: InteractableBase) -> void:
	_set_target(target)


## Returns the current target interactable (null if none).
func get_target() -> InteractableBase:
	return current_target


## Returns whether there is an available interaction.
func has_target() -> bool:
	return current_target != null and current_target.can_interact(owner_character)


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_scan(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer < SCAN_INTERVAL:
		return
	_scan_timer = 0.0
	_scan_for_interactables()
	_select_best_target()


func _scan_for_interactables() -> void:
	if not owner_character:
		return
	var space: PhysicsDirectSpaceState3D = owner_character.get_world_3d().direct_space_state
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = SCAN_RADIUS

	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape     = shape
	params.transform = Transform3D(Basis(), owner_character.global_position)
	params.collision_mask = INTERACTION_LAYER

	var results: Array = space.intersect_shape(params, 16)
	_nearby.clear()
	for r in results:
		var node: Node = r.collider
		# Walk up to find InteractableBase.
		while node:
			if node is InteractableBase:
				if not _nearby.has(node):
					_nearby.append(node as InteractableBase)
				break
			node = node.get_parent()


func _select_best_target() -> void:
	if _nearby.is_empty():
		_set_target(null)
		return

	var best: InteractableBase = null
	var best_score: float      = INF
	var char_pos: Vector3      = owner_character.global_position

	for interactable in _nearby:
		if not is_instance_valid(interactable):
			continue
		if not interactable.can_interact(owner_character):
			continue
		var dist: float = char_pos.distance_to(interactable.global_position)
		if dist > interactable.get_interact_range():
			continue
		# Score = distance (lower = better), with dot product tiebreak.
		var dir: Vector3 = (interactable.global_position - char_pos).normalized()
		var facing: Vector3 = -owner_character.global_basis.z
		var alignment: float = (1.0 - dir.dot(facing)) * 0.5  # 0=perfectly aligned.
		var score: float = dist + alignment * 2.0
		if score < best_score:
			best_score = score
			best = interactable

	_set_target(best)


func _set_target(new_target: InteractableBase) -> void:
	if new_target == current_target:
		return
	var old: InteractableBase = current_target
	current_target = new_target
	target_changed.emit(old, new_target)

	if new_target:
		interact_prompt_updated.emit(new_target.get_prompt(), true)
		EventBus.hud_show_requested.emit("interact_prompt")
	else:
		interact_prompt_updated.emit("", false)
		EventBus.hud_hide_requested.emit("interact_prompt")
