## =============================================================================
## Bootstrap — Initial Game Startup Flow
## =============================================================================

extends Control

const MAIN_MENU_SCENE: String = "res://src/ui/menu/main_menu.tscn"
const FALLBACK_SCENE: String = "res://src/scenes/test/test_world.tscn"

@onready var loading_label: Label = $CanvasLayer/CenterContainer/VBoxContainer/StatusLabel
@onready var progress_bar: ProgressBar = $CanvasLayer/CenterContainer/VBoxContainer/ProgressBar

var _loading_complete: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_initialize_engine()
	_validate_autoloads()

	await get_tree().process_frame

	loading_label.text = "Loading Settings..."
	progress_bar.value = 15.0

	await _load_settings()

	loading_label.text = "Loading Save Data..."
	progress_bar.value = 35.0

	await _load_save_system()

	loading_label.text = "Initializing Audio..."
	progress_bar.value = 50.0

	await _initialize_audio()

	loading_label.text = "Initializing Game Systems..."
	progress_bar.value = 70.0

	await _initialize_game_systems()

	loading_label.text = "Loading Main Scene..."
	progress_bar.value = 90.0

	await _load_main_scene()

	progress_bar.value = 100.0
	loading_label.text = "Done"

func _initialize_engine() -> void:
	Engine.max_fps = 144
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	Logger.info("Bootstrap", "Engine initialized.")

func _validate_autoloads() -> void:
	var required_autoloads: Array[String] = [
		"Logger",
		"EventBus",
		"GameManager",
		"SceneManager",
		"SettingsManager",
		"InputManager",
		"AudioManager",
		"SaveManager",
		"TimeManager",
	]

	for autoload_name in required_autoloads:
		if not get_node_or_null("/root/" + autoload_name):
			push_error("Missing autoload: %s" % autoload_name)

	Logger.info("Bootstrap", "Autoload validation complete.")

func _load_settings() -> void:
	if SettingsManager:
		Logger.info("Bootstrap", "SettingsManager loaded.")

func _load_save_system() -> void:
	if SaveManager:
		Logger.info("Bootstrap", "SaveManager loaded.")

func _initialize_audio() -> void:
	if AudioManager:
		Logger.info("Bootstrap", "AudioManager initialized.")

func _initialize_game_systems() -> void:
	if GameManager:
		Logger.info("Bootstrap", "GameManager initialized.")

	if TimeManager:
		Logger.info("Bootstrap", "TimeManager initialized.")

	if InputManager:
		Logger.info("Bootstrap", "InputManager initialized.")

func _load_main_scene() -> void:
	var target_scene: String = ""

	if ResourceLoader.exists(MAIN_MENU_SCENE):
		target_scene = MAIN_MENU_SCENE
	elif ResourceLoader.exists(FALLBACK_SCENE):
		target_scene = FALLBACK_SCENE
	else:
		push_error("No valid startup scene found.")
		return

	Logger.info("Bootstrap", "Loading scene: %s" % target_scene)

	var err: Error = get_tree().change_scene_to_file(target_scene)

	if err != OK:
		push_error("Failed to load scene: %s" % target_scene)
