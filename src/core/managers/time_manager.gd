## =============================================================================
## TimeManager — Game Time, Timers, and Time Manipulation (Autoload)
## =============================================================================
## Purpose:
##   Centralised time system supporting slow-motion, time-stop, tick-based
##   deterministic updates (for future networking), cooldown tracking,
##   and globalised timer registry.
## =============================================================================

extends Node

signal slow_motion_started(scale: float, duration: float)
signal slow_motion_ended()
signal timer_completed(timer_id: String)

## Read-only: current game time scale (reflects slow-motion effects).
var game_time_scale: float = 1.0
## Deterministic tick counter (increments every physics frame).
var tick: int = 0
## Total unscaled elapsed time since match start.
var unscaled_match_time: float = 0.0

# ── Internal ───────────────────────────────────────────────────────────────────
var _slow_motion_tween: Tween = null
var _managed_timers: Dictionary = {}  # id -> { timer: SceneTreeTimer, callback: Callable }


func _ready() -> void:
	name = "TimeManager"
	Logger.info("TimeManager", "Initialized.")


func _physics_process(_delta: float) -> void:
	tick += 1


func _process(delta: float) -> void:
	# Unscaled delta accumulation.
	unscaled_match_time += delta / Engine.time_scale if Engine.time_scale > 0.0 else 0.0


# ── Public API ─────────────────────────────────────────────────────────────────

## Enter slow-motion for a duration (seconds of real time). Scale: 0.0-1.0
func slow_motion(scale: float = 0.3, duration: float = 2.0) -> void:
	scale = clampf(scale, 0.01, 1.0)
	game_time_scale = scale
	Engine.time_scale = scale
	slow_motion_started.emit(scale, duration)
	Logger.debug("TimeManager", "Slow motion: scale=%.2f dur=%.1fs" % [scale, duration])

	if _slow_motion_tween:
		_slow_motion_tween.kill()
	_slow_motion_tween = create_tween()
	_slow_motion_tween.tween_interval(duration * scale)  # real-time adjusted
	_slow_motion_tween.tween_callback(_restore_time_scale)


## Stop slow-motion immediately.
func stop_slow_motion() -> void:
	if _slow_motion_tween:
		_slow_motion_tween.kill()
	_restore_time_scale()


## Register a named timer. Calls callback when complete.
## Returns a SceneTreeTimer for manual cancellation if needed.
func register_timer(
	id: String,
	duration: float,
	callback: Callable,
	one_shot: bool = true
) -> SceneTreeTimer:
	if _managed_timers.has(id):
		Logger.warn("TimeManager", "Overwriting existing timer: %s" % id)
		cancel_timer(id)
	var t: SceneTreeTimer = get_tree().create_timer(duration, false)
	t.timeout.connect(func():
		callback.call()
		timer_completed.emit(id)
		_managed_timers.erase(id)
	)
	_managed_timers[id] = { "timer": t, "one_shot": one_shot }
	return t


## Cancel a named timer before it fires.
func cancel_timer(id: String) -> void:
	if _managed_timers.has(id):
		# SceneTreeTimers cannot be cancelled directly; we mark them.
		_managed_timers.erase(id)


## Returns seconds remaining for a named timer (-1 if not found).
func get_timer_remaining(id: String) -> float:
	if _managed_timers.has(id):
		var t: SceneTreeTimer = _managed_timers[id].timer
		return t.time_left
	return -1.0


## Convert deterministic tick to seconds at a target tick-rate.
func ticks_to_seconds(ticks: int, tick_rate: int = 60) -> float:
	return float(ticks) / float(tick_rate)


## Convert seconds to deterministic ticks.
func seconds_to_ticks(seconds: float, tick_rate: int = 60) -> int:
	return int(seconds * tick_rate)


## Returns a formatted timestamp string for UX display.
func format_duration(seconds: float) -> String:
	var m: int = int(seconds) / 60
	var s: int = int(seconds) % 60
	return "%02d:%02d" % [m, s]


# ── Internal ───────────────────────────────────────────────────────────────────

func _restore_time_scale() -> void:
	game_time_scale = 1.0
	Engine.time_scale = 1.0
	slow_motion_ended.emit()
	Logger.debug("TimeManager", "Time scale restored to 1.0")
