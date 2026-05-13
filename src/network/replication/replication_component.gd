## =============================================================================
## ReplicationComponent — Per-Entity Network State Replication
## =============================================================================
## Architecture:
##   Attached to each replicated entity (characters, vehicles, pickups).
##   Provides: authority check, interpolation, state snapshot delta.
##
##   Modes:
##     LOCAL:  No replication. All mutations apply immediately.
##     LAN:    Delta snapshots sent at TICK_RATE.
##     ONLINE: Full snapshot + interpolation + lag compensation.
##
##   Uses a circular buffer of snapshots for interpolation and rollback.
##   Currently scaffolded for future online implementation.
##
## Usage:
##   If NetworkManager.mode == LOCAL: this component is a no-op.
##   In online mode: get_authority_state() / apply_remote_state() are used
##   by StateSync to build and consume snapshots.
## =============================================================================

class_name ReplicationComponent
extends Node

const SNAPSHOT_BUFFER_SIZE: int = 32
const INTERPOLATION_DELAY: float = 0.1   # Seconds behind latest snapshot.

signal authority_changed(is_authority: bool)
signal state_applied(tick: int)

# ── Configuration ──────────────────────────────────────────────────────────────
@export var replicated_properties: Array[String] = [
	"global_position", "global_rotation", "current_health",
	"current_armor", "is_alive", "is_downed",
]
@export var replication_tick_rate: int = 20

# ── State ──────────────────────────────────────────────────────────────────────
var entity_id: int      = -1
var is_authority: bool  = true    # True on server / offline.
var _snapshots: Array[Dictionary] = []
var _interp_time: float = 0.0
var _last_received_tick: int = 0


func _ready() -> void:
	name = "ReplicationComponent"
	# In LOCAL mode: this is effectively a no-op.
	if NetworkManager.mode == NetworkManager.NetworkMode.LOCAL:
		is_authority = true
		return
	is_authority = NetworkManager.is_server()
	if entity_id == -1:
		entity_id = get_parent().character_id if get_parent().has_method("character_id") else get_instance_id()
	StateSync.register_entity(entity_id, _get_authority_state, _apply_remote_state)
	Logger.debug("ReplicationComponent", "Entity %d registered. Authority=%s" % [entity_id, is_authority])


func _exit_tree() -> void:
	if NetworkManager.mode != NetworkManager.NetworkMode.LOCAL:
		StateSync.unregister_entity(entity_id)


func _process(delta: float) -> void:
	if is_authority or NetworkManager.mode == NetworkManager.NetworkMode.LOCAL:
		return
	_interpolate(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Set the network authority (server only).
func set_authority(authority: bool) -> void:
	if is_authority == authority:
		return
	is_authority = authority
	authority_changed.emit(authority)


## Returns true if this entity can be mutated (is authority or local).
func can_mutate() -> bool:
	return is_authority or NetworkManager.mode == NetworkManager.NetworkMode.LOCAL


## Force a snapshot (used for initial state on client join).
func force_snapshot(state: Dictionary) -> void:
	_push_snapshot(state)
	_apply_snapshot(state)


# ── Internal ───────────────────────────────────────────────────────────────────

func _get_authority_state() -> Dictionary:
	var state: Dictionary = { "tick": TimeManager.tick }
	var parent: Node = get_parent()
	for prop in replicated_properties:
		if parent.get(prop) != null:
			state[prop] = parent.get(prop)
	return state


func _apply_remote_state(state: Dictionary) -> void:
	_push_snapshot(state)
	_last_received_tick = state.get("tick", 0)


func _push_snapshot(state: Dictionary) -> void:
	state["timestamp"] = Time.get_unix_time_from_system()
	_snapshots.append(state)
	if _snapshots.size() > SNAPSHOT_BUFFER_SIZE:
		_snapshots.pop_front()


func _interpolate(delta: float) -> void:
	if _snapshots.size() < 2:
		return
	_interp_time += delta
	var now: float = Time.get_unix_time_from_system() - INTERPOLATION_DELAY
	# Find surrounding snapshots.
	for i in range(_snapshots.size() - 1):
		var s0: Dictionary = _snapshots[i]
		var s1: Dictionary = _snapshots[i + 1]
		if now >= s0.get("timestamp", 0.0) and now <= s1.get("timestamp", 0.0):
			var t: float = (now - s0.timestamp) / maxf(s1.timestamp - s0.timestamp, 0.001)
			_lerp_apply(s0, s1, t)
			return
	# Latest snapshot.
	_apply_snapshot(_snapshots[-1])


func _lerp_apply(s0: Dictionary, s1: Dictionary, t: float) -> void:
	var parent: Node = get_parent()
	if "global_position" in s0 and "global_position" in s1:
		parent.global_position = s0.global_position.lerp(s1.global_position, t)
	if "global_rotation" in s0 and "global_rotation" in s1:
		parent.global_rotation = s0.global_rotation.lerp(s1.global_rotation, t)
	state_applied.emit(_last_received_tick)


func _apply_snapshot(state: Dictionary) -> void:
	var parent: Node = get_parent()
	for prop in replicated_properties:
		if state.has(prop):
			# Only apply non-interpolated properties.
			if prop not in ["global_position", "global_rotation"]:
				parent.set(prop, state[prop])
	state_applied.emit(state.get("tick", 0))
