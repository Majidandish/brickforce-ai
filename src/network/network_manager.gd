## =============================================================================
## NetworkManager — Multiplayer Network Abstraction Layer (Autoload)
## =============================================================================
## Purpose:
##   Abstracts all networking behind a clean interface.
##   Currently runs in LOCAL mode (offline). Switching to ONLINE mode
##   plugs in ENetMultiplayerPeer / WebSocketMultiplayerPeer transparently.
##   Future: dedicated server migration requires only changing _backend.
##
## Modes:
##   LOCAL  — No network, single-machine offline/local-co-op.
##   LAN    — ENet peer-to-peer LAN discovery.
##   ONLINE — Dedicated server via ENet or WebSocket.
## =============================================================================

extends Node

enum NetworkMode { LOCAL, LAN, ONLINE }
enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, HOSTING, ERROR }

const DEFAULT_PORT: int  = 7777
const MAX_PLAYERS: int   = 16
const SERVER_TIMEOUT: float = 10.0

var mode: NetworkMode           = NetworkMode.LOCAL
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var local_peer_id: int          = 1   # 1 = server authority in offline mode.
var connected_peers: Dictionary = {}  # peer_id -> { id, name, ping, data }

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_established()
signal connection_failed(reason: String)
signal disconnected_from_server(reason: String)
signal latency_measured(peer_id: int, ms: int)


func _ready() -> void:
	name = "NetworkManager"
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Logger.info("NetworkManager", "Initialized in %s mode." % NetworkMode.keys()[mode])


# ── Public API ─────────────────────────────────────────────────────────────────

## Host a local game (LAN/offline).
func host(port: int = DEFAULT_PORT, max_peers: int = MAX_PLAYERS) -> Error:
	if mode == NetworkMode.LOCAL:
		_setup_offline_authority()
		return OK

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, max_peers)
	if err != OK:
		Logger.error("NetworkManager", "Host failed: %d" % err)
		connection_failed.emit("Failed to bind port %d" % port)
		return err

	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.HOSTING
	local_peer_id = 1
	Logger.info("NetworkManager", "Hosting on port %d (max %d peers)." % [port, max_peers])
	connection_established.emit()
	return OK


## Join a remote game.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if mode == NetworkMode.LOCAL:
		Logger.warn("NetworkManager", "Cannot join in LOCAL mode.")
		return ERR_UNAVAILABLE

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		Logger.error("NetworkManager", "Join failed: %d" % err)
		connection_failed.emit("Could not connect to %s:%d" % [address, port])
		return err

	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.CONNECTING
	Logger.info("NetworkManager", "Connecting to %s:%d…" % [address, port])
	return OK


## Disconnect from current session.
func disconnect_from_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	_reset_state()
	disconnected_from_server.emit("local_disconnect")
	EventBus.server_disconnected.emit("local_disconnect")
	Logger.info("NetworkManager", "Disconnected.")


## Set the network mode (call before host/join).
func set_mode(new_mode: NetworkMode) -> void:
	mode = new_mode
	Logger.info("NetworkManager", "Network mode: %s" % NetworkMode.keys()[new_mode])


## Returns true if this instance has server authority.
func is_server() -> bool:
	return multiplayer.is_server()


## Returns true if currently in an active session.
func is_connected_to_session() -> bool:
	return connection_state in [ConnectionState.CONNECTED, ConnectionState.HOSTING]


## Returns local peer ID.
func get_local_id() -> int:
	return multiplayer.get_unique_id()


## Broadcast reliable RPC to all peers (server authority).
func broadcast(method: String, args: Array = []) -> void:
	if not is_server():
		return
	rpc(method, args)


## Send unreliable state update (position sync etc.).
func send_unreliable(target_id: int, method: String, args: Array = []) -> void:
	rpc_id(target_id, method, args)


## Register a peer's metadata.
func register_peer_data(peer_id: int, data: Dictionary) -> void:
	connected_peers[peer_id] = data


## Get all connected peer IDs.
func get_peer_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in connected_peers:
		ids.append(id)
	return ids


# ── Internal ───────────────────────────────────────────────────────────────────

func _setup_offline_authority() -> void:
	var peer: OfflineMultiplayerPeer = OfflineMultiplayerPeer.new()
	multiplayer.multiplayer_peer = peer
	connection_state = ConnectionState.HOSTING
	local_peer_id = 1
	Logger.info("NetworkManager", "Offline authority established (LOCAL mode).")
	connection_established.emit()
	EventBus.server_connected.emit("local")


func _reset_state() -> void:
	connection_state = ConnectionState.DISCONNECTED
	connected_peers.clear()
	local_peer_id = 1


func _on_peer_connected(peer_id: int) -> void:
	connected_peers[peer_id] = { "id": peer_id, "ping": 0 }
	peer_connected.emit(peer_id)
	EventBus.peer_joined.emit(peer_id, {})
	Logger.info("NetworkManager", "Peer connected: %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	connected_peers.erase(peer_id)
	peer_disconnected.emit(peer_id)
	EventBus.peer_left.emit(peer_id)
	Logger.info("NetworkManager", "Peer disconnected: %d" % peer_id)


func _on_connected_to_server() -> void:
	connection_state = ConnectionState.CONNECTED
	local_peer_id = multiplayer.get_unique_id()
	connection_established.emit()
	EventBus.server_connected.emit("remote")
	Logger.info("NetworkManager", "Connected to server. Local ID: %d" % local_peer_id)


func _on_connection_failed() -> void:
	connection_state = ConnectionState.ERROR
	connection_failed.emit("Connection timed out or refused.")
	Logger.error("NetworkManager", "Connection failed.")


func _on_server_disconnected() -> void:
	_reset_state()
	disconnected_from_server.emit("server_dropped")
	EventBus.server_disconnected.emit("server_dropped")
	Logger.warn("NetworkManager", "Disconnected from server.")
