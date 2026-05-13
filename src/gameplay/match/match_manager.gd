## =============================================================================
## MatchManager — Battle Royale Match Lifecycle Controller
## =============================================================================
## Purpose:
##   Owns the complete match lifecycle: lobby → plane drop → active match
##   → safe zone cycles → endgame. Coordinates all subsystems: spawn,
##   loot, safe zone, squad AI, kill tracking, and results generation.
##   Authoritative on server; replicated to clients via NetworkManager.
## =============================================================================

class_name MatchManager
extends Node

# ── Match Phases ───────────────────────────────────────────────────────────────
enum MatchPhase {
	INACTIVE,
	LOBBY,
	COUNTDOWN,
	DROP_PHASE,    # Players in drop plane.
	LANDING,       # Parachute / landing window.
	EARLY_GAME,    # Full safe zone, looting phase.
	MID_GAME,      # First zone shrink.
	LATE_GAME,     # Second+ zone shrink, high intensity.
	FINAL_CIRCLE,  # Tiny zone, last squads.
	ENDING,        # Victory screen playing.
}

const PHASE_NAMES: Dictionary = {
	MatchPhase.INACTIVE:     "INACTIVE",
	MatchPhase.LOBBY:        "LOBBY",
	MatchPhase.COUNTDOWN:    "COUNTDOWN",
	MatchPhase.DROP_PHASE:   "DROP_PHASE",
	MatchPhase.LANDING:      "LANDING",
	MatchPhase.EARLY_GAME:   "EARLY_GAME",
	MatchPhase.MID_GAME:     "MID_GAME",
	MatchPhase.LATE_GAME:    "LATE_GAME",
	MatchPhase.FINAL_CIRCLE: "FINAL_CIRCLE",
	MatchPhase.ENDING:       "ENDING",
}

# ── Zone Shrink Schedule ───────────────────────────────────────────────────────
# Each entry: { wait: seconds, shrink_duration: seconds, end_radius: meters, damage_per_sec }
const ZONE_SCHEDULE: Array[Dictionary] = [
	{ "wait": 180.0, "shrink": 120.0, "radius": 500.0, "damage": 1.0 },
	{ "wait": 90.0,  "shrink": 90.0,  "radius": 250.0, "damage": 2.0 },
	{ "wait": 60.0,  "shrink": 60.0,  "radius": 100.0, "damage": 4.0 },
	{ "wait": 30.0,  "shrink": 45.0,  "radius": 30.0,  "damage": 8.0 },
	{ "wait": 15.0,  "shrink": 30.0,  "radius": 5.0,   "damage": 15.0 },
]

# ── Signals ───────────────────────────────────────────────────────────────────
signal phase_changed(old: MatchPhase, new_phase: MatchPhase)
signal player_eliminated(player_id: int, killer_id: int, placement: int)
signal match_result_ready(result: Dictionary)
signal zone_update(center: Vector3, current_radius: float, target_radius: float, time_remaining: float)

# ── Configuration ──────────────────────────────────────────────────────────────
@export var max_players: int    = 60
@export var squad_size: int     = 4
@export var lobby_countdown: float = 10.0

# ── State ──────────────────────────────────────────────────────────────────────
var current_phase: MatchPhase   = MatchPhase.INACTIVE
var match_id: String            = ""
var start_timestamp: float      = 0.0
var alive_count: int            = 0
var eliminated_order: Array[Dictionary] = []  # [{ player_id, killer_id, time, placement }]

# ── Zone ───────────────────────────────────────────────────────────────────────
var safe_zone_center: Vector3   = Vector3.ZERO
var safe_zone_radius: float     = 1000.0
var next_zone_center: Vector3   = Vector3.ZERO
var next_zone_radius: float     = 500.0
var zone_phase_index: int       = 0
var zone_timer: float           = 0.0
var is_zone_shrinking: bool     = false
var zone_shrink_progress: float = 0.0

# ── Kill Tracking ──────────────────────────────────────────────────────────────
var kill_table: Dictionary      = {}  # player_id -> kill_count
var damage_table: Dictionary    = {}  # player_id -> total_damage

# ── Internal ───────────────────────────────────────────────────────────────────
var _phase_timer: float         = 0.0
var _registered_characters: Dictionary = {}  # character_id -> CharacterBase
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	name = "MatchManager"
	EventBus.player_died.connect(_on_player_died)
	EventBus.kill_registered.connect(_on_kill_registered)
	EventBus.hit_registered.connect(_on_hit_registered)
	Logger.info("MatchManager", "Initialized.")


func _process(delta: float) -> void:
	if current_phase == MatchPhase.INACTIVE:
		return
	_update_phase_timer(delta)
	_update_zone(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Start a new match with the given config (from GameManager.active_match_config).
func start_match(config: Dictionary) -> void:
	match_id        = "match_%d" % int(Time.get_unix_time_from_system())
	start_timestamp = Time.get_unix_time_from_system()
	alive_count     = config.get("player_count", 1)
	zone_phase_index = 0
	eliminated_order.clear()
	kill_table.clear()
	damage_table.clear()
	_rng.randomize()
	safe_zone_center = _random_zone_center(1000.0)
	safe_zone_radius = 1000.0
	_calculate_next_zone()

	GameManager.active_match = self
	_transition_to(MatchPhase.COUNTDOWN)
	EventBus.match_started.emit(config)
	Logger.info("MatchManager", "Match started: %s" % match_id)


## Register a character entity in this match.
func register_character(character: CharacterBase) -> void:
	_registered_characters[character.character_id] = character


## Force end the match (e.g. all players eliminated or dev command).
func force_end() -> void:
	_end_match()


## Returns the match elapsed time in seconds.
func get_elapsed_time() -> float:
	if start_timestamp <= 0.0:
		return 0.0
	return Time.get_unix_time_from_system() - start_timestamp


## Returns whether a given world position is inside the safe zone.
func is_in_safe_zone(world_pos: Vector3) -> bool:
	return world_pos.distance_to(safe_zone_center) <= safe_zone_radius


## Get the kill count for a player.
func get_kills(player_id: int) -> int:
	return kill_table.get(player_id, 0)


## Get match stats snapshot.
func get_match_stats() -> Dictionary:
	return {
		"match_id":      match_id,
		"phase":         PHASE_NAMES[current_phase],
		"elapsed":       get_elapsed_time(),
		"alive":         alive_count,
		"zone_radius":   safe_zone_radius,
		"kill_table":    kill_table.duplicate(),
		"damage_table":  damage_table.duplicate(),
	}


# ── Internal ───────────────────────────────────────────────────────────────────

func _transition_to(phase: MatchPhase) -> void:
	var old: MatchPhase = current_phase
	current_phase = phase
	_phase_timer = 0.0
	Logger.info("MatchManager", "Phase: %s → %s" % [PHASE_NAMES[old], PHASE_NAMES[phase]])
	EventBus.phase_changed.emit(PHASE_NAMES[old], PHASE_NAMES[phase])
	phase_changed.emit(old, phase)
	_on_phase_enter(phase)


func _on_phase_enter(phase: MatchPhase) -> void:
	match phase:
		MatchPhase.COUNTDOWN:
			TimeManager.register_timer("match_countdown", lobby_countdown, func():
				_transition_to(MatchPhase.DROP_PHASE)
			)
		MatchPhase.DROP_PHASE:
			TimeManager.register_timer("drop_phase", 20.0, func():
				_transition_to(MatchPhase.LANDING)
			)
		MatchPhase.LANDING:
			TimeManager.register_timer("landing", 15.0, func():
				_transition_to(MatchPhase.EARLY_GAME)
			)
		MatchPhase.EARLY_GAME:
			zone_timer = ZONE_SCHEDULE[0].wait
		MatchPhase.ENDING:
			TimeManager.register_timer("ending", 8.0, func():
				_end_match()
			)


func _update_phase_timer(delta: float) -> void:
	_phase_timer += delta


func _update_zone(delta: float) -> void:
	if current_phase not in [MatchPhase.EARLY_GAME, MatchPhase.MID_GAME,
		MatchPhase.LATE_GAME, MatchPhase.FINAL_CIRCLE]:
		return

	if is_zone_shrinking:
		var schedule: Dictionary = ZONE_SCHEDULE[zone_phase_index]
		zone_shrink_progress = min(zone_shrink_progress + delta / schedule.shrink, 1.0)
		safe_zone_radius = lerp(
			ZONE_SCHEDULE[max(0, zone_phase_index - 1) if zone_phase_index > 0 else 0].get("radius", 1000.0),
			schedule.radius,
			zone_shrink_progress
		)
		safe_zone_center = lerp(safe_zone_center, next_zone_center, zone_shrink_progress * 0.1)
		zone_update.emit(safe_zone_center, safe_zone_radius, next_zone_radius, 0.0)
		EventBus.safe_zone_shrinking.emit(safe_zone_center, safe_zone_radius, 0.0)

		_apply_zone_damage(delta)

		if zone_shrink_progress >= 1.0:
			is_zone_shrinking = false
			zone_phase_index += 1
			if zone_phase_index < ZONE_SCHEDULE.size():
				zone_timer = ZONE_SCHEDULE[zone_phase_index].wait
				_calculate_next_zone()
	else:
		zone_timer -= delta
		if zone_timer <= 0.0 and zone_phase_index < ZONE_SCHEDULE.size():
			is_zone_shrinking = true
			zone_shrink_progress = 0.0


func _apply_zone_damage(delta: float) -> void:
	if zone_phase_index >= ZONE_SCHEDULE.size():
		return
	var dmg: float = ZONE_SCHEDULE[zone_phase_index].damage * delta
	for id in _registered_characters:
		var ch: CharacterBase = _registered_characters[id]
		if is_instance_valid(ch) and ch.is_alive:
			if not is_in_safe_zone(ch.global_position):
				ch.take_damage(dmg, -1, "safe_zone")
				EventBus.safe_zone_tick_damage.emit(dmg)


func _calculate_next_zone() -> void:
	if zone_phase_index >= ZONE_SCHEDULE.size():
		return
	next_zone_radius = ZONE_SCHEDULE[zone_phase_index].radius
	next_zone_center = _random_zone_center(safe_zone_radius * 0.4)


func _random_zone_center(max_offset: float) -> Vector3:
	var angle: float = _rng.randf() * TAU
	var dist: float  = _rng.randf() * max_offset
	return safe_zone_center + Vector3(cos(angle) * dist, 0, sin(angle) * dist)


func _on_player_died(player_id: int, killer_id: int, _cause: String) -> void:
	alive_count = max(0, alive_count - 1)
	eliminated_order.append({
		"player_id": player_id,
		"killer_id": killer_id,
		"time":      get_elapsed_time(),
		"placement": alive_count + 1,
	})
	player_eliminated.emit(player_id, killer_id, alive_count + 1)
	Logger.info("MatchManager", "Player %d eliminated. Remaining: %d" % [player_id, alive_count])

	if alive_count <= 1:
		_transition_to(MatchPhase.ENDING)


func _on_kill_registered(killer_id: int, _victim_id: int, _weapon: String) -> void:
	kill_table[killer_id] = kill_table.get(killer_id, 0) + 1


func _on_hit_registered(_target: int, attacker_id: int, damage: float, _pos: Vector3, _bone: String) -> void:
	damage_table[attacker_id] = damage_table.get(attacker_id, 0.0) + damage


func _end_match() -> void:
	var winner_id: int = -1
	for id in _registered_characters:
		var ch: CharacterBase = _registered_characters[id]
		if is_instance_valid(ch) and ch.is_alive:
			winner_id = ch.character_id
			break

	var result: Dictionary = {
		"match_id":          match_id,
		"winner_id":         winner_id,
		"duration":          get_elapsed_time(),
		"kill_table":        kill_table.duplicate(),
		"damage_table":      damage_table.duplicate(),
		"elimination_order": eliminated_order.duplicate(),
		"player_count":      _registered_characters.size(),
	}

	match_result_ready.emit(result)
	EventBus.match_ended.emit(result)
	GameManager.transition_to(GameManager.GameState.RESULTS_SCREEN)
	APIManager.match_report(result, Callable())
	Logger.info("MatchManager", "Match ended. Winner: %d  Duration: %.1fs" % [winner_id, result.duration])
