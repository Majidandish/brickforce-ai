## =============================================================================
## PerformanceMonitor — Runtime Performance Profiling (Autoload)
## =============================================================================
## Purpose:
##   Tracks FPS, memory, draw calls, physics time, and custom system
##   metrics. Issues warnings through EventBus when thresholds are breached.
##   All data is accessible to the DebugConsole overlay.
## =============================================================================

extends Node

const SAMPLE_INTERVAL: float = 0.5   # seconds between metric snapshots
const FPS_WARNING_THRESHOLD: float   = 30.0
const MEMORY_WARNING_MB: float       = 1800.0  # warn at 1.8 GB
const HISTORY_SIZE: int              = 120      # 1 minute at 0.5s interval

signal metrics_updated(snapshot: Dictionary)

var _timer: float = 0.0
var _history: Array[Dictionary] = []
var _custom_metrics: Dictionary = {}  # name -> Callable that returns float


func _ready() -> void:
	name = "PerformanceMonitor"
	Logger.info("PerformanceMonitor", "Initialized.")


func _process(delta: float) -> void:
	_timer += delta
	if _timer < SAMPLE_INTERVAL:
		return
	_timer = 0.0
	var snap: Dictionary = _take_snapshot()
	_history.append(snap)
	if _history.size() > HISTORY_SIZE:
		_history.pop_front()
	metrics_updated.emit(snap)
	_check_warnings(snap)


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a custom metric sampler.
## callback: Callable() -> float
func register_metric(name: String, callback: Callable) -> void:
	_custom_metrics[name] = callback


## Deregister a custom metric.
func unregister_metric(name: String) -> void:
	_custom_metrics.erase(name)


## Get the latest snapshot.
func get_latest() -> Dictionary:
	return _history.back() if not _history.is_empty() else {}


## Get metric history as array of snapshots.
func get_history() -> Array[Dictionary]:
	return _history.duplicate()


## Compute average of a metric key over the history.
func get_average(key: String) -> float:
	if _history.is_empty():
		return 0.0
	var total: float = 0.0
	for snap in _history:
		total += snap.get(key, 0.0)
	return total / _history.size()


## Returns a formatted string for the debug HUD.
func get_hud_string() -> String:
	var s: Dictionary = get_latest()
	if s.is_empty():
		return "No data yet"
	return (
		"FPS: %d  |  Frame: %.2fms  |  Physics: %.2fms\n"
		+ "RAM: %.1f MB  |  VRAM: %.1f MB  |  Draw Calls: %d\n"
		+ "Objects: %d  |  Nodes: %d  |  Orphans: %d"
	) % [
		s.get("fps", 0),
		s.get("frame_time_ms", 0.0),
		s.get("physics_time_ms", 0.0),
		s.get("static_memory_mb", 0.0),
		s.get("video_memory_mb", 0.0),
		s.get("draw_calls", 0),
		s.get("object_count", 0),
		s.get("node_count", 0),
		s.get("orphan_count", 0),
	]


# ── Internal ───────────────────────────────────────────────────────────────────

func _take_snapshot() -> Dictionary:
	var snap: Dictionary = {
		"timestamp":       Time.get_unix_time_from_system(),
		"fps":             int(Engine.get_frames_per_second()),
		"frame_time_ms":   Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_time_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"video_memory_mb":  Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"draw_calls":      int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"object_count":    int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count":      int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_count":    int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"physics_bodies":  int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"pool_stats":      ObjectPool.get_all_stats(),
	}
	for name in _custom_metrics:
		snap[name] = _custom_metrics[name].call()
	return snap


func _check_warnings(snap: Dictionary) -> void:
	if snap.fps < FPS_WARNING_THRESHOLD and snap.fps > 0:
		EventBus.performance_warning.emit("FPS", "Low FPS detected", float(snap.fps))
	if snap.static_memory_mb > MEMORY_WARNING_MB:
		EventBus.performance_warning.emit("RAM", "High memory usage", snap.static_memory_mb)
