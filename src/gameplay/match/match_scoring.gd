## =============================================================================
## MatchScoring — Battle Royale Scoring & XP Calculation System
## =============================================================================
## Architecture:
##   Listens to EventBus signals for kills, assists, damage, survival time,
##   and placement to build a per-player score ledger.
##   At match end, computes final scores and XP rewards via APIManager.
##
##   Score categories (configurable via ScoringConfig resource):
##     Kill, Headshot bonus, Assist, Revive, Damage dealt (per 100 dmg),
##     Survival time (per minute), Placement bonus.
##
##   Network: Authoritative on server. Score updates broadcast on change.
## =============================================================================

class_name MatchScoring
extends Node

# ── Score Constants ────────────────────────────────────────────────────────────
const SCORE_KILL:          int = 100
const SCORE_HEADSHOT:      int = 50
const SCORE_ASSIST:        int = 40
const SCORE_REVIVE:        int = 60
const SCORE_DAMAGE_PER100: int = 10   # Per 100 damage dealt.
const SCORE_SURVIVAL_PER_MIN: int = 5  # Per minute survived.
const PLACEMENT_BONUSES: Dictionary = {
	1: 500, 2: 300, 3: 200, 4: 150, 5: 100,
	10: 50, 20: 20, 30: 10,
}

signal score_updated(player_id: int, new_score: int, delta: int)
signal leaderboard_updated(leaderboard: Array)

# ── State ──────────────────────────────────────────────────────────────────────
## player_id -> PlayerMatchState
var _player_states: Dictionary = {}
var _match_start_time: float   = 0.0
var _is_active: bool           = false


func _ready() -> void:
	name = "MatchScoring"
	EventBus.match_started.connect(_on_match_started)
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.kill_registered.connect(_on_kill)
	EventBus.headshot_registered.connect(_on_headshot)
	EventBus.hit_registered.connect(_on_damage_dealt)
	EventBus.player_revived.connect(_on_revive)
	EventBus.player_died.connect(_on_player_died)
	Logger.info("MatchScoring", "Initialized.")


func _process(_delta: float) -> void:
	pass


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a player for tracking.
func register_player(player_id: int, display_name: String = "") -> void:
	if _player_states.has(player_id):
		return
	var state: PlayerMatchState = PlayerMatchState.new()
	state.player_id    = player_id
	state.display_name = display_name
	state.join_time    = Time.get_unix_time_from_system()
	_player_states[player_id] = state
	Logger.debug("MatchScoring", "Registered player %d." % player_id)


## Add score to a player with a reason tag.
func add_score(player_id: int, amount: int, reason: String = "") -> void:
	if not _player_states.has(player_id):
		return
	var state: PlayerMatchState = _player_states[player_id]
	state.score += amount
	score_updated.emit(player_id, state.score, amount)
	Logger.verbose("MatchScoring", "Player %d +%d score [%s] = %d total" % [
		player_id, amount, reason, state.score
	])
	_broadcast_leaderboard()


## Get a player's current state snapshot.
func get_player_state(player_id: int) -> PlayerMatchState:
	return _player_states.get(player_id, null)


## Get sorted leaderboard (by score descending).
func get_leaderboard() -> Array[PlayerMatchState]:
	var list: Array[PlayerMatchState] = []
	for id in _player_states:
		list.append(_player_states[id])
	list.sort_custom(func(a, b): return a.score > b.score)
	return list


## Finalise scoring at match end. Returns full result dictionary.
func compute_final_results(elimination_order: Array[Dictionary]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var total_players: int = _player_states.size()

	for i in elimination_order.size():
		var entry: Dictionary = elimination_order[i]
		var pid: int = entry.get("player_id", -1)
		var state: PlayerMatchState = _player_states.get(pid)
		if not state:
			continue
		var placement: int = entry.get("placement", total_players)
		_apply_placement_bonus(pid, placement)
		_apply_survival_bonus(pid, entry.get("time", 0.0))
		results.append(state.to_dict())

	# Winner.
	for id in _player_states:
		var state: PlayerMatchState = _player_states[id]
		if state.is_alive:
			state.placement = 1
			_apply_placement_bonus(id, 1)
			results.append(state.to_dict())

	results.sort_custom(func(a, b): return a.get("placement", 999) < b.get("placement", 999))
	return results


# ── Internal ───────────────────────────────────────────────────────────────────

func _on_match_started(_config: Dictionary) -> void:
	_player_states.clear()
	_match_start_time = Time.get_unix_time_from_system()
	_is_active = true


func _on_match_ended(result: Dictionary) -> void:
	_is_active = false


func _on_kill(killer_id: int, _victim_id: int, _weapon: String) -> void:
	add_score(killer_id, SCORE_KILL, "kill")
	if _player_states.has(killer_id):
		_player_states[killer_id].kills += 1


func _on_headshot(victim_id: int, shooter_id: int) -> void:
	add_score(shooter_id, SCORE_HEADSHOT, "headshot")
	if _player_states.has(shooter_id):
		_player_states[shooter_id].headshots += 1


func _on_damage_dealt(_victim_id: int, attacker_id: int, damage: float, _pos: Vector3, _bone: String) -> void:
	if not _is_active:
		return
	if _player_states.has(attacker_id):
		var state: PlayerMatchState = _player_states[attacker_id]
		state.damage_dealt += damage
		# Award score per 100 damage.
		var prev_hundreds: int = int(state.damage_dealt - damage) / 100
		var new_hundreds: int  = int(state.damage_dealt) / 100
		if new_hundreds > prev_hundreds:
			add_score(attacker_id, (new_hundreds - prev_hundreds) * SCORE_DAMAGE_PER100, "damage")


func _on_revive(revived_id: int, reviver_id: int) -> void:
	add_score(reviver_id, SCORE_REVIVE, "revive")
	if _player_states.has(reviver_id):
		_player_states[reviver_id].revives += 1


func _on_player_died(player_id: int, _killer_id: int, _cause: String) -> void:
	if _player_states.has(player_id):
		_player_states[player_id].is_alive = false
		_player_states[player_id].death_time = Time.get_unix_time_from_system()


func _apply_placement_bonus(player_id: int, placement: int) -> void:
	var bonus: int = 0
	for threshold in PLACEMENT_BONUSES:
		if placement <= int(threshold):
			bonus = maxi(bonus, PLACEMENT_BONUSES[threshold])
	if bonus > 0:
		add_score(player_id, bonus, "placement_%d" % placement)
	if _player_states.has(player_id):
		_player_states[player_id].placement = placement


func _apply_survival_bonus(player_id: int, survival_seconds: float) -> void:
	var minutes: int = int(survival_seconds / 60.0)
	if minutes > 0:
		add_score(player_id, minutes * SCORE_SURVIVAL_PER_MIN, "survival")


func _broadcast_leaderboard() -> void:
	var board: Array = get_leaderboard().map(func(s): return {
		"player_id": s.player_id,
		"name":      s.display_name,
		"score":     s.score,
		"kills":     s.kills,
	})
	leaderboard_updated.emit(board)
	EventBus.leaderboard_updated.emit(board)
