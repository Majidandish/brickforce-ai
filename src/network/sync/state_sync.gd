## =============================================================================
## StateSync — Multiplayer State Synchronisation Layer
## =============================================================================
## Purpose:
##   Manages authoritative state replication between server and clients.
##   Uses Godot 4's MultiplayerSynchronizer and MultiplayerSpawner
##   conventions. In LOCAL mode this is a no-op. In ONLINE/LAN mode,
##   snapshots are sent at a configurable tick rate.
##
##   Currently: scaffolded for future online migration.
##   To enable: set NetworkManager.mode = ONLINE and call start().
## =============================================================================

extends Node

const SYNC_TICK_RATE: int   = 20   # State updates per second.
const SNAPSHOT_BUFFER: int  = 32   # Number of snapshots to retain.

signal snapshot_applied(tick: int)
signal snapshot_sent(tick: int)

var _is_active: bool                 = false
var _sync_timer: float               = 0.0
var _snapshot_buffer: Array[Dictionary] = []
var _pending_inputs: Array[Dictionary]  = []

## Registered entities for synchronisation. entity_id -> sync data.
var _entities: Dictionary = {}


func _ready() -> void:
	name = "StateSync"
	NetworkManager.connection_established.connect(_on_connection_established)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	Logger.info("StateSync", "Initialized (inactive until connection).")


func _physics_process(delta: float) -> void:
	if not _is_active:
		return
	_sync_timer += delta
	if _sync_timer >= 1.0 / SYNC_TICK_RATE:
		_sync_timer = 0.0
		_tick_sync()


# ── Public API ─────────────────────────────────────────────────────────────────

## Register an entity for state sync.
## get_state_fn:   Callable() -> Dictionary  (returns serializable state)
## apply_state_fn: Callable(Dictionary) -> void
func register_entity(
	entity_id: int,
	get_state_fn: Callable,
	apply_state_fn: Callable
) -> void:
	_entities[entity_id] = {
		"id":    entity_id,
		"get":   get_state_fn,
		"apply": apply_state_fn,
	}


## Unregister an entity.
func unregister_entity(entity_id: int) -> void:
	_entities.erase(entity_id)


## Queue a player input for server processing.
func queue_input(input: Dictionary) -> void:
	input["tick"] = TimeManager.tick
	_pending_inputs.append(input)
	if _pending_inputs.size() > 60:
		_pending_inputs.pop_front()


## Apply a server snapshot received from the network.
func apply_snapshot(snapshot: Dictionary) -> void:
	var server_tick: int = snapshot.get("tick", 0)
	_apply_entity_states(snapshot.get("entities", {}))
	snapshot_applied.emit(server_tick)
	EventBus.state_sync_received.emit(snapshot)


## Get the latest local snapshot (for server broadcast or debug).
func get_current_snapshot() -> Dictionary:
	var entities_state: Dictionary = {}
	for id in _entities:
		entities_state[id] = _entities[id].get.call()
	return {
		"tick":     TimeManager.tick,
		"entities": entities_state,
		"time":     Time.get_unix_time_from_system(),
	}


# ── Internal ───────────────────────────────────────────────────────────────────

func _tick_sync() -> void:
	if NetworkManager.is_server():
		_server_broadcast()
	else:
		_client_send_inputs()


func _server_broadcast() -> void:
	var snapshot: Dictionary = get_current_snapshot()
	_snapshot_buffer.append(snapshot)
	if _snapshot_buffer.size() > SNAPSHOT_BUFFER:
		_snapshot_buffer.pop_front()

	# Broadcast to all peers (in online mode via RPC).
	# In LOCAL mode: no-op.
	if NetworkManager.mode != NetworkManager.NetworkMode.LOCAL:
		for peer_id in NetworkManager.get_peer_ids():
			rpc_id(peer_id, "_receive_snapshot", snapshot)

	snapshot_sent.emit(snapshot.tick)


func _client_send_inputs() -> void:
	if _pending_inputs.is_empty():
		return
	var inputs_to_send: Array = _pending_inputs.duplicate()
	_pending_inputs.clear()
	if NetworkManager.mode != NetworkManager.NetworkMode.LOCAL:
		rpc_id(1, "_receive_inputs", inputs_to_send)


func _apply_entity_states(states: Dictionary) -> void:
	for id_str in states:
		var id: int = int(id_str)
		if _entities.has(id):
			_entities[id].apply.call(states[id_str])


@rpc("authority", "call_remote", "unreliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	apply_snapshot(snapshot)


@rpc("any_peer", "call_remote", "unreliable")
func _receive_inputs(inputs: Array) -> void:
	# Server processes client inputs.
	for input in inputs:
		_process_client_input(input)


func _process_client_input(input: Dictionary) -> void:
	# TODO: validate and apply authoritative simulation.
	pass


func _on_connection_established() -> void:
	_is_active = NetworkManager.mode != NetworkManager.NetworkMode.LOCAL
	Logger.info("StateSync", "Active: %s" % _is_active)


func _on_disconnected(_reason: String) -> void:
	_is_active = false
	_entities.clear()
	_snapshot_buffer.clear()
