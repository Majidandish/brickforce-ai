## =============================================================================
## InputContext — Input Context & Action Mapping Layer
## =============================================================================
## Architecture:
##   Named input contexts define which actions are active at a time.
##   Only one context is active per character (stack-based).
##   Contexts: "gameplay", "menu", "vehicle", "downed", "spectator", "cutscene"
##
##   Prevents: firing weapons while in menus, interacting while driving, etc.
##   The InputManager reads from the active context to filter actions.
## =============================================================================

class_name InputContext
extends Resource

# ── Standard Context Names ────────────────────────────────────────────────────
const CTX_GAMEPLAY:   String = "gameplay"
const CTX_MENU:       String = "menu"
const CTX_VEHICLE:    String = "vehicle"
const CTX_DOWNED:     String = "downed"
const CTX_SPECTATOR:  String = "spectator"
const CTX_CUTSCENE:   String = "cutscene"
const CTX_ADS:        String = "ads"

# ── Configuration ──────────────────────────────────────────────────────────────
@export var context_name: String              = "gameplay"
@export var allowed_actions: Array[String]    = []   # Empty = all allowed.
@export var blocked_actions: Array[String]    = []
@export var capture_mouse: bool               = true
@export var allow_pause: bool                 = true

# ── Built-in context definitions ──────────────────────────────────────────────
static func gameplay() -> InputContext:
	var ctx: InputContext  = InputContext.new()
	ctx.context_name       = CTX_GAMEPLAY
	ctx.capture_mouse      = true
	ctx.allow_pause        = true
	return ctx

static func menu() -> InputContext:
	var ctx: InputContext  = InputContext.new()
	ctx.context_name       = CTX_MENU
	ctx.blocked_actions    = ["fire", "reload", "sprint", "jump", "crouch", "aim", "interact"]
	ctx.capture_mouse      = false
	ctx.allow_pause        = true
	return ctx

static func downed() -> InputContext:
	var ctx: InputContext  = InputContext.new()
	ctx.context_name       = CTX_DOWNED
	ctx.allowed_actions    = ["look", "crawl", "call_for_help"]
	ctx.capture_mouse      = true
	ctx.allow_pause        = false
	return ctx

static func cutscene() -> InputContext:
	var ctx: InputContext  = InputContext.new()
	ctx.context_name       = CTX_CUTSCENE
	ctx.blocked_actions    = []
	ctx.allowed_actions    = ["skip"]
	ctx.capture_mouse      = false
	ctx.allow_pause        = false
	return ctx


## Check if an action is allowed in this context.
func is_action_allowed(action: String) -> bool:
	if action in blocked_actions:
		return false
	if not allowed_actions.is_empty() and action not in allowed_actions:
		return false
	return true
