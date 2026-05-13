## =============================================================================
## APIManager — Backend API Abstraction Layer (Autoload)
## =============================================================================
## Purpose:
##   All backend calls flow through APIManager, which routes them to either
##   the LocalServer (offline fake backend) or a live HTTPRequest to a real
##   dedicated server / cloud function. Swapping backends requires zero
##   changes to callers.
##
## Backends:
##   LOCAL  → LocalServer (fully offline, in-process fake REST)
##   REMOTE → Real HTTP/WebSocket server at configured URL
## =============================================================================

extends Node

enum Backend { LOCAL, REMOTE }

const LOCAL_LATENCY_SIMULATE_MS: float = 40.0  # Simulated round-trip for LOCAL.

var backend: Backend = Backend.LOCAL
var _base_url: String = ""
var _auth_token: String = ""
var _pending_requests: Dictionary = {}   # request_id -> HTTPRequest node
var _request_id_counter: int = 0

signal request_completed(request_id: int, success: bool, data: Dictionary)
signal auth_token_refreshed()


func _ready() -> void:
	name = "APIManager"
	_base_url = SettingsManager.get_value("network.dedicated_server_url", "")
	if _base_url == "" or _base_url == "local":
		backend = Backend.LOCAL
	else:
		backend = Backend.REMOTE
	Logger.info("APIManager", "Backend: %s  URL: %s" % [Backend.keys()[backend], _base_url])


# ── Public API ─────────────────────────────────────────────────────────────────

## POST request. Returns a request_id. Listen to request_completed signal.
func post(endpoint: String, body: Dictionary, callback: Callable = Callable()) -> int:
	return _dispatch("POST", endpoint, body, callback)


## GET request.
func get_request(endpoint: String, callback: Callable = Callable()) -> int:
	return _dispatch("GET", endpoint, {}, callback)


## PUT request.
func put(endpoint: String, body: Dictionary, callback: Callable = Callable()) -> int:
	return _dispatch("PUT", endpoint, body, callback)


## DELETE request.
func delete(endpoint: String, callback: Callable = Callable()) -> int:
	return _dispatch("DELETE", endpoint, {}, callback)


## Set the auth token (e.g. after login).
func set_auth_token(token: String) -> void:
	_auth_token = token


## Switch backend at runtime (for dev/testing).
func set_backend(new_backend: Backend, url: String = "") -> void:
	backend = new_backend
	if url != "":
		_base_url = url
	Logger.info("APIManager", "Backend switched to: %s" % Backend.keys()[new_backend])


# ── Convenience Endpoints ─────────────────────────────────────────────────────

func auth_login(username: String, password: String, callback: Callable) -> int:
	return post("/auth/login", { "username": username, "password": password }, callback)

func auth_logout(callback: Callable) -> int:
	return post("/auth/logout", {}, callback)

func player_get_profile(player_id: String, callback: Callable) -> int:
	return get_request("/player/%s/profile" % player_id, callback)

func player_save_progress(data: Dictionary, callback: Callable) -> int:
	return post("/player/save", data, callback)

func shop_get_catalogue(callback: Callable) -> int:
	return get_request("/shop/catalogue", callback)

func shop_purchase(item_id: String, currency: String, callback: Callable) -> int:
	return post("/shop/purchase", { "item_id": item_id, "currency": currency }, callback)

func leaderboard_get(mode: String, callback: Callable) -> int:
	return get_request("/leaderboard/%s" % mode, callback)

func match_report(result: Dictionary, callback: Callable) -> int:
	return post("/match/report", result, callback)


# ── Internal ───────────────────────────────────────────────────────────────────

func _dispatch(method: String, endpoint: String, body: Dictionary, callback: Callable) -> int:
	_request_id_counter += 1
	var rid: int = _request_id_counter

	if backend == Backend.LOCAL:
		_dispatch_local(rid, method, endpoint, body, callback)
	else:
		_dispatch_remote(rid, method, endpoint, body, callback)

	return rid


func _dispatch_local(rid: int, method: String, endpoint: String, body: Dictionary, callback: Callable) -> void:
	# Route to in-process LocalServer with simulated latency.
	var response: Dictionary = LocalServer.handle_request(method, endpoint, body)
	TimeManager.register_timer(
		"api_%d" % rid,
		LOCAL_LATENCY_SIMULATE_MS / 1000.0,
		func():
			var success: bool = response.get("status", 500) < 400
			request_completed.emit(rid, success, response)
			if callback.is_valid():
				callback.call(success, response)
	)


func _dispatch_remote(rid: int, method: String, endpoint: String, body: Dictionary, callback: Callable) -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_pending_requests[rid] = http

	var url: String = _base_url.rstrip("/") + endpoint
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Accept: application/json",
	]
	if _auth_token != "":
		headers.append("Authorization: Bearer " + _auth_token)

	var body_str: String = JSON.stringify(body) if not body.is_empty() else ""
	var method_int: int = HTTPClient.METHOD_GET
	match method:
		"POST": method_int = HTTPClient.METHOD_POST
		"PUT":  method_int = HTTPClient.METHOD_PUT
		"DELETE": method_int = HTTPClient.METHOD_DELETE

	http.request_completed.connect(func(result, code, _headers, response_body):
		_pending_requests.erase(rid)
		http.queue_free()
		var success: bool = result == HTTPRequest.RESULT_SUCCESS and code < 400
		var data: Dictionary = {}
		if success:
			var json: JSON = JSON.new()
			if json.parse(response_body.get_string_from_utf8()) == OK:
				data = json.get_data()
		request_completed.emit(rid, success, data)
		if callback.is_valid():
			callback.call(success, data)
	)

	var err: Error = http.request(url, headers, method_int, body_str)
	if err != OK:
		Logger.error("APIManager", "HTTP request failed: %s %s (%d)" % [method, url, err])
		_pending_requests.erase(rid)
		http.queue_free()
