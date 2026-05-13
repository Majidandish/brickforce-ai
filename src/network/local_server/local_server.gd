## =============================================================================
## LocalServer — Offline Fake Backend (Autoload via APIManager)
## =============================================================================
## Purpose:
##   Simulates a REST API server entirely in-process. Handles all API routes
##   that would normally hit a cloud backend. Stores data in Godot's user://
##   directory. Enables full offline play and rapid dev iteration without
##   needing a real server.
##
##   When a real backend is ready, APIManager.set_backend(REMOTE, url)
##   bypasses this entirely — zero code changes needed in callers.
## =============================================================================

extends Node

const DATA_DIR: String = "user://local_server/"

# In-memory DB — loaded from disk on startup, flushed on writes.
var _db: Dictionary = {
	"players":      {},
	"sessions":     {},
	"leaderboards": {},
	"shop":         {},
	"inventory":    {},
}

var _route_handlers: Dictionary = {}  # "METHOD /path" -> Callable


func _ready() -> void:
	name = "LocalServer"
	DirAccess.make_dir_recursive_absolute(DATA_DIR)
	_load_db()
	_register_routes()
	_seed_shop_catalogue()
	Logger.info("LocalServer", "Fake backend ready (%d routes)." % _route_handlers.size())


# ── Core Dispatch ──────────────────────────────────────────────────────────────

## Called by APIManager to handle a LOCAL backend request.
func handle_request(method: String, endpoint: String, body: Dictionary) -> Dictionary:
	var key: String = method.to_upper() + " " + _normalize_endpoint(endpoint)

	# Try exact match first, then wildcard patterns.
	if _route_handlers.has(key):
		var response: Dictionary = _route_handlers[key].call(endpoint, body)
		Logger.verbose("LocalServer", "%s %s → %d" % [method, endpoint, response.get("status", 200)])
		return response

	# Pattern matching (e.g. GET /player/:id/profile)
	for pattern in _route_handlers.keys():
		var params: Dictionary = _match_route(pattern, key)
		if not params.is_empty():
			return _route_handlers[pattern].call(endpoint, body, params)

	Logger.warn("LocalServer", "No route: %s %s" % [method, endpoint])
	return _error(404, "Route not found: %s %s" % [method, endpoint])


# ── Route Registration ─────────────────────────────────────────────────────────

func _register_routes() -> void:
	_route("POST /auth/login",        _handle_auth_login)
	_route("POST /auth/logout",       _handle_auth_logout)
	_route("GET /player/:id/profile", _handle_player_profile)
	_route("POST /player/save",       _handle_player_save)
	_route("GET /shop/catalogue",     _handle_shop_catalogue)
	_route("POST /shop/purchase",     _handle_shop_purchase)
	_route("GET /leaderboard/:mode",  _handle_leaderboard)
	_route("POST /match/report",      _handle_match_report)
	_route("GET /health",             func(_e, _b, _p={}): return _ok({ "status": "healthy" }))


func _route(pattern: String, handler: Callable) -> void:
	_route_handlers[pattern] = handler


# ── Route Handlers ─────────────────────────────────────────────────────────────

func _handle_auth_login(_endpoint: String, body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	var username: String = body.get("username", "player")
	if not _db.players.has(username):
		_db.players[username] = _create_default_player(username)
		_flush_table("players")
	var token: String = "local_token_%s_%d" % [username, int(Time.get_unix_time_from_system())]
	_db.sessions[token] = username
	return _ok({ "token": token, "player": _db.players[username] })


func _handle_auth_logout(_endpoint: String, _body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	return _ok({ "message": "Logged out." })


func _handle_player_profile(endpoint: String, _body: Dictionary, params: Dictionary = {}) -> Dictionary:
	var id: String = params.get("id", "")
	if _db.players.has(id):
		return _ok(_db.players[id])
	return _error(404, "Player not found: %s" % id)


func _handle_player_save(_endpoint: String, body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	var player_id: String = body.get("player_id", "local_player")
	if _db.players.has(player_id):
		_db.players[player_id].merge(body, true)
	else:
		_db.players[player_id] = body
	_flush_table("players")
	return _ok({ "saved": true })


func _handle_shop_catalogue(_endpoint: String, _body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	return _ok({ "items": _db.shop.values() })


func _handle_shop_purchase(_endpoint: String, body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	var item_id: String = body.get("item_id", "")
	if not _db.shop.has(item_id):
		return _error(404, "Item not found: %s" % item_id)
	var item: Dictionary = _db.shop[item_id]
	return _ok({ "purchased": true, "item": item })


func _handle_leaderboard(_endpoint: String, _body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	var entries: Array = []
	for pid in _db.players:
		var p: Dictionary = _db.players[pid]
		entries.append({
			"player_id": pid,
			"name":      p.get("display_name", pid),
			"kills":     p.get("stats", {}).get("total_kills", 0),
			"wins":      p.get("stats", {}).get("wins", 0),
		})
	entries.sort_custom(func(a, b): return a.kills > b.kills)
	return _ok({ "entries": entries.slice(0, 100) })


func _handle_match_report(_endpoint: String, body: Dictionary, _p: Dictionary = {}) -> Dictionary:
	var pid: String = body.get("player_id", "local_player")
	if _db.players.has(pid):
		var stats: Dictionary = _db.players[pid].get("stats", {})
		stats["matches_played"] = stats.get("matches_played", 0) + 1
		if body.get("won", false):
			stats["wins"] = stats.get("wins", 0) + 1
		stats["total_kills"] = stats.get("total_kills", 0) + body.get("kills", 0)
		_db.players[pid]["stats"] = stats
		_flush_table("players")
	return _ok({ "recorded": true })


# ── Helpers ────────────────────────────────────────────────────────────────────

func _create_default_player(username: String) -> Dictionary:
	return {
		"id":           username,
		"display_name": username,
		"level":        1,
		"xp":           0,
		"currency":     { "gold": 1000, "gems": 50, "battle_points": 0 },
		"inventory":    [],
		"cosmetics":    [],
		"stats": {
			"matches_played": 0,
			"wins":           0,
			"total_kills":    0,
			"total_damage":   0.0,
		},
		"created_at":   Time.get_datetime_string_from_system(),
	}


func _seed_shop_catalogue() -> void:
	if not _db.shop.is_empty():
		return
	var items: Array[Dictionary] = [
		{ "id": "skin_rifle_desert", "name": "Desert Rifle Skin", "cost": 500, "currency": "gold", "type": "cosmetic" },
		{ "id": "skin_char_ghost",   "name": "Ghost Operative",   "cost": 200, "currency": "gems", "type": "cosmetic" },
		{ "id": "ammo_pack_large",   "name": "Large Ammo Pack",   "cost": 100, "currency": "gold", "type": "consumable" },
		{ "id": "medkit_advanced",   "name": "Advanced Medkit",   "cost": 150, "currency": "gold", "type": "consumable" },
	]
	for item in items:
		_db.shop[item.id] = item
	_flush_table("shop")


func _ok(data: Dictionary) -> Dictionary:
	return { "status": 200, "data": data }


func _error(code: int, message: String) -> Dictionary:
	return { "status": code, "error": message }


func _normalize_endpoint(ep: String) -> String:
	return ep.rstrip("/") if ep != "/" else "/"


func _match_route(pattern: String, key: String) -> Dictionary:
	var p_parts: PackedStringArray = pattern.split(" ")
	var k_parts: PackedStringArray = key.split(" ")
	if p_parts.size() != 2 or k_parts.size() != 2:
		return {}
	if p_parts[0] != k_parts[0]:
		return {}
	var pp: PackedStringArray = p_parts[1].split("/")
	var kp: PackedStringArray = k_parts[1].split("/")
	if pp.size() != kp.size():
		return {}
	var params: Dictionary = {}
	for i in pp.size():
		if pp[i].begins_with(":"):
			params[pp[i].substr(1)] = kp[i]
		elif pp[i] != kp[i]:
			return {}
	return params if not params.is_empty() else { "_matched": true }


func _load_db() -> void:
	for table in _db.keys():
		var path: String = DATA_DIR + table + ".json"
		if FileAccess.file_exists(path):
			var f: FileAccess = FileAccess.open(path, FileAccess.READ)
			if f:
				var json: JSON = JSON.new()
				if json.parse(f.get_as_text()) == OK:
					_db[table] = json.get_data()
				f.close()


func _flush_table(table: String) -> void:
	var path: String = DATA_DIR + table + ".json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_db[table], "\t"))
		f.close()
