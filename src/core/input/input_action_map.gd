## =============================================================================
## InputActionMap — Rebindable Action Mapping Table
## =============================================================================
## Architecture:
##   Maps logical actions → physical keys/buttons. Supports:
##     - Keyboard + Mouse (desktop)
##     - Controller (gamepad)
##     - Custom rebinding (saved in SettingsManager)
##
##   Decouples game code from Godot's InputMap so actions can be
##   remapped at runtime without modifying project.godot.
##
##   All gameplay systems use InputManager.is_action_pressed("fire")
##   NOT Input.is_key_pressed(KEY_CTRL).
## =============================================================================

class_name InputActionMap
extends Resource

## action_name -> { key: int, mouse_button: int, gamepad_button: int }
@export var bindings: Dictionary = {}

const DEFAULT_BINDINGS: Dictionary = {
	"move_forward":  { "key": KEY_W,    "gamepad": JOY_BUTTON_INVALID },
	"move_back":     { "key": KEY_S,    "gamepad": JOY_BUTTON_INVALID },
	"move_left":     { "key": KEY_A,    "gamepad": JOY_BUTTON_INVALID },
	"move_right":    { "key": KEY_D,    "gamepad": JOY_BUTTON_INVALID },
	"sprint":        { "key": KEY_SHIFT,"gamepad": JOY_BUTTON_LEFT_STICK },
	"jump":          { "key": KEY_SPACE,"gamepad": JOY_BUTTON_A },
	"crouch":        { "key": KEY_C,    "gamepad": JOY_BUTTON_B },
	"fire":          { "mouse": MOUSE_BUTTON_LEFT,  "gamepad": JOY_BUTTON_RIGHT_SHOULDER },
	"aim":           { "mouse": MOUSE_BUTTON_RIGHT, "gamepad": JOY_BUTTON_LEFT_SHOULDER },
	"reload":        { "key": KEY_R,    "gamepad": JOY_BUTTON_X },
	"interact":      { "key": KEY_E,    "gamepad": JOY_BUTTON_Y },
	"swap_weapon":   { "key": KEY_Q,    "gamepad": JOY_BUTTON_DPAD_LEFT },
	"weapon_slot_1": { "key": KEY_1,    "gamepad": JOY_BUTTON_INVALID },
	"weapon_slot_2": { "key": KEY_2,    "gamepad": JOY_BUTTON_INVALID },
	"weapon_slot_3": { "key": KEY_3,    "gamepad": JOY_BUTTON_INVALID },
	"grenade":       { "key": KEY_G,    "gamepad": JOY_BUTTON_DPAD_DOWN },
	"open_map":      { "key": KEY_M,    "gamepad": JOY_BUTTON_SELECT },
	"open_inventory":{ "key": KEY_TAB,  "gamepad": JOY_BUTTON_DPAD_UP },
	"pause":         { "key": KEY_ESCAPE,"gamepad": JOY_BUTTON_START },
	"squad_command": { "key": KEY_Z,    "gamepad": JOY_BUTTON_INVALID },
	"prone":         { "key": KEY_X,    "gamepad": JOY_BUTTON_INVALID },
	"lean_left":     { "key": KEY_Q,    "gamepad": JOY_BUTTON_INVALID },
	"lean_right":    { "key": KEY_E,    "gamepad": JOY_BUTTON_INVALID },
	"use_item_1":    { "key": KEY_F1,   "gamepad": JOY_BUTTON_INVALID },
	"use_item_2":    { "key": KEY_F2,   "gamepad": JOY_BUTTON_INVALID },
	"free_look":     { "key": KEY_ALT,  "gamepad": JOY_BUTTON_INVALID },
	"fire_mode":     { "key": KEY_V,    "gamepad": JOY_BUTTON_INVALID },
	"melee":         { "key": KEY_F,    "gamepad": JOY_BUTTON_RIGHT_STICK },
	"call_for_help": { "key": KEY_H,    "gamepad": JOY_BUTTON_INVALID },
}


## Load defaults.
func reset_to_default() -> void:
	bindings = DEFAULT_BINDINGS.duplicate(true)


## Rebind an action.
func rebind(action: String, binding_dict: Dictionary) -> void:
	bindings[action] = binding_dict
	Logger.info("InputActionMap", "Rebound: %s → %s" % [action, JSON.stringify(binding_dict)])


## Serialise for SettingsManager.
func to_dict() -> Dictionary:
	return bindings.duplicate(true)


## Apply from saved settings.
func from_dict(data: Dictionary) -> void:
	for action in data:
		bindings[action] = data[action]
