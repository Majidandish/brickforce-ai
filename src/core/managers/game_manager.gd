## =============================================================================
## GameManager — Master Game State Machine (Autoload Singleton)
## =============================================================================
## Purpose:
##   Owns the authoritative game state. Controls transitions between
##   MainMenu, Loading, Match, Pause, GameOver, and more.
##   All systems query GameManager for global context.
## =============================================================================

extends Node

# ── Game States ────────────────────────────────────────────────────────────────
enum GameState {
	NONE,
	SPLASH,
	MAIN_MENU,
	LOADING,
	IN_MATCH,
	PAUSED,
	GAME_OVER,
	RESULTS_SCREEN,
	SETTINGS,
	SHOP,
	CUTSCENE,
}

const STATE_NAMES: Dictionary = {
	GameState.NONE:           "NONE",
	GameState.SPLASH:         "SPLASH",
	GameState.MAIN_MENU:      "MAIN_MENU",
	GameState.LOADING:        "LOADING",
	GameState.IN_MATCH:       "IN_MATCH",
	GameState.PAUSED:         "PAUSED",
	GameState.GAME_OVER:      "GAME_OVER",
	GameState.RESULTS_SCREEN: "RESULTS_SCREEN",
	GameState.SETTINGS:       "SETTINGS",
	GameState.SHOP:           "SHOP",
	GameState.CUTSCENE:       "CUTSCENE",
}

# ── Runtime State ──────────────────────────────────────────────────────────────
var current_state: GameState = GameState.NONE
var previous_state: GameState = GameState.NONE
var _state_stack: Array[GameState] = []

## Active match configuration (set before entering IN_MATCH).
var active_match_config: Dictionary = {}
## Running match session reference (set by MatchManager).
var active_match: Node = null
## Local player entity reference.
var local_player: Node = null
## Frame counter for deterministic systems.
var frame_tick: int = 0
## Elapsed match time in seconds.
var match_time: float = 0.0

# ── Signals ────────────────────────────────────────────────────────────────────
signal state_changed(old: GameState, new_state: GameState)
signal match_config_set(config: Dictionary)
signal local_player_set(player: Node)


func _ready() -> void:
	name = "GameManager"
	Logger.info("GameManager", "Initialized.")
	_transition_to(GameState.SPLASH)


func _process(delta: float) -> void:
	frame_tick += 1
	if current_state == GameState.IN_MATCH:
		match_time += delta


# ── Public API ─────────────────────────────────────────────────────────────────

## Transition to a new state. Validates the transition is legal.
func transition_to(new_state: GameState) -> void:
	if not _is_transition_legal(current_state, new_state):
		Logger.warn("GameManager", "Illegal state transition: %s → %s" % [
			STATE_NAMES[current_state], STATE_NAMES[new_state]
		])
		return
	_transition_to(new_state)


## Push state onto stack (e.g. opening Settings from Main Menu).
func push_state(new_state: GameState) -> void:
	_state_stack.push_back(current_state)
	_transition_to(new_state)


## Pop state from stack and restore.
func pop_state() -> void:
	if _state_stack.is_empty():
		Logger.warn("GameManager", "pop_state called on empty stack.")
		return
	var restore: GameState = _state_stack.pop_back()
	_transition_to(restore)


## Configure the next match before starting it.
func set_match_config(config: Dictionary) -> void:
	active_match_config = config.duplicate(true)
	Logger.info("GameManager", "Match config set.", config)
	match_config_set.emit(active_match_config)


## Register the local player node.
func register_local_player(player: Node) -> void:
	local_player = player
	local_player_set.emit(player)
	Logger.info("GameManager", "Local player registered: %s" % player.name)


## Returns true if the game is currently in an active match.
func is_in_match() -> bool:
	return current_state == GameState.IN_MATCH


## Returns true if the game is paused.
func is_paused() -> bool:
	return current_state == GameState.PAUSED


## Pause/unpause toggle.
func toggle_pause() -> void:
	if current_state == GameState.IN_MATCH:
		transition_to(GameState.PAUSED)
	elif current_state == GameState.PAUSED:
		transition_to(GameState.IN_MATCH)


## Emergency quit to main menu — cleans up match state.
func quit_to_main_menu() -> void:
	_cleanup_match()
	_state_stack.clear()
	_transition_to(GameState.MAIN_MENU)


## Hard exit the application.
func quit_game() -> void:
	Logger.info("GameManager", "Application quit requested.")
	_cleanup_match()
	get_tree().quit()


# ── Internal ───────────────────────────────────────────────────────────────────

func _transition_to(new_state: GameState) -> void:
	var old: GameState = current_state
	previous_state = old
	current_state = new_state

	Logger.info("GameManager", "State: %s → %s" % [
		STATE_NAMES[old], STATE_NAMES[new_state]
	])

	_on_state_exit(old)
	_on_state_enter(new_state)
	state_changed.emit(old, new_state)
	EventBus.phase_changed.emit(STATE_NAMES[old], STATE_NAMES[new_state])


func _on_state_enter(state: GameState) -> void:
	match state:
		GameState.LOADING:
			Engine.time_scale = 1.0
		GameState.IN_MATCH:
			Engine.time_scale = 1.0
			match_time = 0.0
		GameState.PAUSED:
			Engine.time_scale = 0.0
			EventBus.match_paused.emit("player_pause")
		GameState.GAME_OVER:
			Engine.time_scale = 0.3  # Slow-motion effect
		GameState.MAIN_MENU:
			match_time = 0.0


func _on_state_exit(state: GameState) -> void:
	match state:
		GameState.PAUSED:
			Engine.time_scale = 1.0
			EventBus.match_resumed.emit()
		GameState.IN_MATCH:
			pass  # MatchManager handles cleanup via its own signal


func _cleanup_match() -> void:
	match_time = 0.0
	active_match_config = {}
	active_match = null
	local_player = null


func _is_transition_legal(from: GameState, to: GameState) -> bool:
	# Define valid transitions (whitelist approach).
	const VALID: Dictionary = {
		GameState.NONE:           [GameState.SPLASH],
		GameState.SPLASH:         [GameState.MAIN_MENU],
		GameState.MAIN_MENU:      [GameState.LOADING, GameState.SETTINGS, GameState.SHOP],
		GameState.LOADING:        [GameState.IN_MATCH, GameState.MAIN_MENU],
		GameState.IN_MATCH:       [GameState.PAUSED, GameState.GAME_OVER, GameState.MAIN_MENU],
		GameState.PAUSED:         [GameState.IN_MATCH, GameState.SETTINGS, GameState.MAIN_MENU],
		GameState.GAME_OVER:      [GameState.RESULTS_SCREEN, GameState.MAIN_MENU],
		GameState.RESULTS_SCREEN: [GameState.MAIN_MENU, GameState.LOADING],
		GameState.SETTINGS:       [GameState.MAIN_MENU, GameState.PAUSED],
		GameState.SHOP:           [GameState.MAIN_MENU],
		GameState.CUTSCENE:       [GameState.IN_MATCH, GameState.MAIN_MENU],
	}
	var allowed: Array = VALID.get(from, [])
	return to in allowed
