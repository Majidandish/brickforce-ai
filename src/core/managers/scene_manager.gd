## =============================================================================
## SceneManager — Async Scene Loading & Transition System (Autoload)
## =============================================================================
## Purpose:
##   Handles all scene transitions with async loading, progress reporting,
##   and customisable transition effects (fade, cut, cinematic bars).
##   Prevents double-loads and manages scene history for back-navigation.
## =============================================================================

extends Node

const TRANSITION_SCENE: String = "res://scenes/ui/transition_overlay.tscn"

enum TransitionType { NONE, FADE, SLIDE_LEFT, SLIDE_RIGHT, CINEMATIC }

## Emitted as 0.0→1.0 while a scene loads.
signal load_progress(progress: float)
signal scene_loaded(scene_path: String)
signal scene_unloaded(scene_path: String)
signal transition_started(type: TransitionType)
signal transition_finished()

var _current_scene_path: String = ""
var _scene_history: Array[String] = []
var _is_loading: bool = false
var _loader: ResourceLoader = null
var _pending_path: String = ""
var _pending_transition: TransitionType = TransitionType.FADE
var _transition_overlay: CanvasLayer = null


func _ready() -> void:
	name = "SceneManager"
	set_process(false)
	Logger.info("SceneManager", "Initialized.")


func _process(_delta: float) -> void:
	if not _is_loading:
		return
	_poll_loader()


# ── Public API ─────────────────────────────────────────────────────────────────

## Load a scene asynchronously with an optional transition.
func load_scene(
	path: String,
	transition: TransitionType = TransitionType.FADE,
	push_history: bool = true
) -> void:
	if _is_loading:
		Logger.warn("SceneManager", "Already loading a scene. Request ignored: %s" % path)
		return
	if path == _current_scene_path:
		Logger.warn("SceneManager", "Requested scene is already current: %s" % path)
		return

	Logger.info("SceneManager", "Loading scene: %s" % path)
	_pending_path = path
	_pending_transition = transition

	if push_history and _current_scene_path != "":
		_scene_history.push_back(_current_scene_path)

	_is_loading = true
	ResourceLoader.load_threaded_request(path)
	set_process(true)
	transition_started.emit(transition)
	_play_transition_out(transition)


## Go back to the previous scene in history.
func go_back(transition: TransitionType = TransitionType.FADE) -> void:
	if _scene_history.is_empty():
		Logger.warn("SceneManager", "No scene history to go back to.")
		return
	var prev: String = _scene_history.pop_back()
	load_scene(prev, transition, false)


## Load a scene immediately (synchronous — use sparingly).
func load_scene_immediate(path: String) -> void:
	Logger.info("SceneManager", "Immediate scene load: %s" % path)
	_swap_scene(load(path))


## Reload the current scene.
func reload_current() -> void:
	if _current_scene_path != "":
		load_scene(_current_scene_path, _pending_transition, false)


## Returns the currently active scene path.
func get_current_path() -> String:
	return _current_scene_path


# ── Internal ───────────────────────────────────────────────────────────────────

func _poll_loader() -> void:
	var status: ResourceLoader.ThreadLoadStatus = \
		ResourceLoader.load_threaded_get_status(_pending_path)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var progress: Array = []
			ResourceLoader.load_threaded_get_status(_pending_path, progress)
			var p: float = progress[0] if not progress.is_empty() else 0.0
			load_progress.emit(p)

		ResourceLoader.THREAD_LOAD_LOADED:
			var resource: Resource = ResourceLoader.load_threaded_get(_pending_path)
			_is_loading = false
			set_process(false)
			load_progress.emit(1.0)
			_swap_scene(resource)

		ResourceLoader.THREAD_LOAD_FAILED:
			_is_loading = false
			set_process(false)
			Logger.error("SceneManager", "Failed to load scene: %s" % _pending_path)

		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_is_loading = false
			set_process(false)
			Logger.error("SceneManager", "Invalid resource: %s" % _pending_path)


func _swap_scene(resource: Resource) -> void:
	var old_path: String = _current_scene_path
	get_tree().change_scene_to_packed(resource as PackedScene)
	_current_scene_path = _pending_path
	_pending_path = ""
	scene_unloaded.emit(old_path)
	scene_loaded.emit(_current_scene_path)
	_play_transition_in(_pending_transition)
	transition_finished.emit()
	Logger.info("SceneManager", "Scene active: %s" % _current_scene_path)


func _play_transition_out(_type: TransitionType) -> void:
	# TODO: Trigger animated overlay (fade-out etc.)
	pass


func _play_transition_in(_type: TransitionType) -> void:
	# TODO: Trigger animated overlay (fade-in etc.)
	pass
