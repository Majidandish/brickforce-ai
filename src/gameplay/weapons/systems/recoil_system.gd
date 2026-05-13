## =============================================================================
## RecoilSystem — Weapon Recoil Simulation
## =============================================================================
## Architecture:
##   Produces a recoil impulse (pitch, yaw) each shot. Recovers over time.
##   Two separate systems:
##     1. Visual recoil — affects camera only (purely cosmetic, client-side).
##     2. Accuracy recoil — affects spread calculation (affects hit position).
##
##   Pattern: all values come from WeaponData. Supports unique recoil
##   patterns (sniper kick vs. SMG rapid drift) via configurable curves.
##
## Usage:
##   recoil.record_shot(weapon_data)
##   var kick = recoil.get_visual_kick()   → add to camera pitch/yaw
##   var spread = recoil.get_accuracy_spread()  → passed to SpreadCalculator
## =============================================================================

class_name RecoilSystem
extends Node

# ── Signals ────────────────────────────────────────────────────────────────────
signal recoil_applied(vertical: float, horizontal: float)

# ── State ──────────────────────────────────────────────────────────────────────
var _shot_count: int            = 0   # Shots in current burst (resets on pause).
var _visual_kick_v: float       = 0.0  # Vertical (pitch) visual kick.
var _visual_kick_h: float       = 0.0  # Horizontal (yaw) visual kick.
var _accuracy_spread: float     = 0.0
var _recovery_timer: float      = 0.0
var _fire_pause_timer: float    = 0.0  # How long since last shot.
var _pattern_index: int         = 0   # Current position in recoil pattern.

# ── Config (from WeaponData each shot) ────────────────────────────────────────
var _vertical_kick: float    = 1.0
var _horizontal_kick: float  = 0.4
var _recovery_rate: float    = 3.0
var _shot_reset_time: float  = 0.4   # Seconds after last shot to reset pattern.
var _is_ads: bool            = false

## Optional custom recoil pattern (x=horizontal, y=vertical offsets per shot).
## If empty, uses random within kick range.
var custom_pattern: Array[Vector2] = []


func _ready() -> void:
	name = "RecoilSystem"


func _process(delta: float) -> void:
	_update_recovery(delta)
	_update_fire_pause(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Call this on every shot. Weapon data provides per-shot stats.
func record_shot(weapon_data: WeaponData, is_ads: bool = false) -> void:
	_is_ads = is_ads
	_vertical_kick    = weapon_data.vertical_recoil
	_horizontal_kick  = weapon_data.horizontal_recoil
	_recovery_rate    = weapon_data.recoil_recovery
	_shot_reset_time  = 0.4

	var ads_mult: float = 0.6 if is_ads else 1.0

	var kick_v: float
	var kick_h: float

	if not custom_pattern.is_empty() and _pattern_index < custom_pattern.size():
		var p: Vector2 = custom_pattern[_pattern_index]
		kick_v = p.y * ads_mult
		kick_h = p.x * ads_mult
		_pattern_index += 1
	else:
		kick_v = _vertical_kick * ads_mult
		kick_h = randf_range(-_horizontal_kick, _horizontal_kick) * ads_mult

	# Progressive recoil — subsequent shots kick more.
	var buildup: float = 1.0 + (_shot_count * 0.08)
	kick_v *= minf(buildup, 2.5)

	_visual_kick_v    = minf(_visual_kick_v + kick_v, 15.0)
	_visual_kick_h    = clampf(_visual_kick_h + kick_h, -8.0, 8.0)
	_accuracy_spread += weapon_data.spread_per_shot
	_fire_pause_timer  = 0.0
	_shot_count       += 1

	recoil_applied.emit(_visual_kick_v, _visual_kick_h)
	Logger.verbose("RecoilSystem", "Shot %d: v=%.2f h=%.2f" % [_shot_count, kick_v, kick_h])


## Returns visual camera kick (pitch and yaw angles in degrees).
func get_visual_kick() -> Vector2:
	return Vector2(_visual_kick_h, -_visual_kick_v)


## Returns the spread contribution from recoil (added to base weapon spread).
func get_accuracy_spread() -> float:
	return _accuracy_spread


## Force reset (weapon switch, etc.)
func reset() -> void:
	_shot_count       = 0
	_visual_kick_v    = 0.0
	_visual_kick_h    = 0.0
	_accuracy_spread  = 0.0
	_pattern_index    = 0
	_fire_pause_timer = 0.0


## Set ADS state (reduces recoil).
func set_ads(is_ads: bool) -> void:
	_is_ads = is_ads


# ── Internal ───────────────────────────────────────────────────────────────────

func _update_recovery(delta: float) -> void:
	if _visual_kick_v <= 0.0 and _visual_kick_h == 0.0 and _accuracy_spread <= 0.0:
		return
	var rate: float = _recovery_rate * delta
	_visual_kick_v    = maxf(0.0, _visual_kick_v - rate * 3.0)
	_visual_kick_h    = move_toward(_visual_kick_h, 0.0, rate * 2.0)
	_accuracy_spread  = maxf(0.0, _accuracy_spread - rate)


func _update_fire_pause(delta: float) -> void:
	_fire_pause_timer += delta
	if _fire_pause_timer >= _shot_reset_time:
		_shot_count    = 0
		_pattern_index = 0
