## =============================================================================
## InteractableBase — Abstract Interactable Entity
## =============================================================================
## Architecture:
##   All interactable world objects extend this. Provides a unified contract
##   for the InteractionSystem to call. Override _on_interact() for behaviour.
##   Supports: instant interact, hold-to-interact, conditional availability.
## =============================================================================

class_name InteractableBase
extends Node3D

# ── Interact Types ─────────────────────────────────────────────────────────────
enum InteractType { INSTANT, HOLD, TOGGLE }

# ── Configuration ──────────────────────────────────────────────────────────────
@export var interact_type: InteractType  = InteractType.INSTANT
@export var hold_duration: float         = 1.5   # For HOLD type.
@export var interact_range: float        = 2.5
@export var prompt_text: String          = "Interact"
@export var prompt_key_hint: String      = "E"
@export var is_enabled: bool             = true
@export var one_shot: bool               = false  # Disable after first use.

# ── Signals ────────────────────────────────────────────────────────────────────
signal interact_started(interactor: CharacterBase)
signal interact_completed(interactor: CharacterBase)
signal interact_cancelled(interactor: CharacterBase)
signal interact_progress_changed(progress: float)  # 0-1 for hold type.
signal enabled_changed(enabled: bool)

# ── State ──────────────────────────────────────────────────────────────────────
var _hold_progress: float   = 0.0
var _active_interactor: CharacterBase = null
var _is_used: bool          = false


func _ready() -> void:
	add_to_group("interactable")


# ── Public API ─────────────────────────────────────────────────────────────────

## Called by InteractionSystem when interact input begins.
func begin_interact(interactor: CharacterBase) -> bool:
	if not can_interact(interactor):
		return false
	_active_interactor = interactor
	interact_started.emit(interactor)
	if interact_type == InteractType.INSTANT:
		_complete(interactor)
	return true


## Called each frame while holding interact (for HOLD type).
func update_interact(interactor: CharacterBase, delta: float) -> void:
	if interact_type != InteractType.HOLD or _active_interactor != interactor:
		return
	_hold_progress = minf(_hold_progress + delta / hold_duration, 1.0)
	interact_progress_changed.emit(_hold_progress)
	if _hold_progress >= 1.0:
		_complete(interactor)


## Called when interact input is released early.
func cancel_interact(interactor: CharacterBase) -> void:
	if _active_interactor != interactor:
		return
	_hold_progress     = 0.0
	_active_interactor = null
	interact_cancelled.emit(interactor)


## Override to define interaction conditions.
func can_interact(interactor: CharacterBase) -> bool:
	if not is_enabled or _is_used:
		return false
	return true


## Enable / disable this interactable.
func set_enabled(value: bool) -> void:
	is_enabled = value
	enabled_changed.emit(value)


## Returns the prompt string to show on the HUD.
func get_prompt() -> String:
	return "[%s] %s" % [prompt_key_hint, prompt_text]


## Returns range for InteractionSystem distance check.
func get_interact_range() -> float:
	return interact_range


# ── Override ───────────────────────────────────────────────────────────────────
## Override this to implement the actual interaction effect.
func _on_interact(interactor: CharacterBase) -> void:
	pass


# ── Internal ───────────────────────────────────────────────────────────────────

func _complete(interactor: CharacterBase) -> void:
	_on_interact(interactor)
	_hold_progress     = 0.0
	_active_interactor = null
	interact_completed.emit(interactor)
	if one_shot:
		_is_used   = true
		is_enabled = false
		enabled_changed.emit(false)
