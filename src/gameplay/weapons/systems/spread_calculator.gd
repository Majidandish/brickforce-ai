## =============================================================================
## SpreadCalculator — Accurate Bullet Spread Simulation
## =============================================================================
## Architecture:
##   Combines all spread sources into a final bullet direction vector:
##     1. Base weapon spread (from WeaponData)
##     2. Recoil contribution (from RecoilSystem)
##     3. Movement spread (running = less accurate)
##     4. ADS spread reduction
##     5. Prone spread reduction
##     6. Jump/air spread penalty
##
##   Returns a perturbed direction vector for hitscan/projectile.
##   Pure function: no side effects, same input = same output.
## =============================================================================

class_name SpreadCalculator
extends RefCounted

const DEG_TO_HALF_TAN_SCALE: float = 0.01  # Converts degree spread to offset scale.

## Calculate the final spread-modified shot direction.
## Returns a normalised Vector3.
static func calculate(
	base_direction: Vector3,
	weapon_data: WeaponData,
	recoil_spread: float = 0.0,
	is_ads: bool = false,
	is_moving: bool = false,
	is_sprinting: bool = false,
	is_crouching: bool = false,
	is_airborne: bool = false,
	is_prone: bool = false,
) -> Vector3:
	var total_spread: float = _get_total_spread(
		weapon_data, recoil_spread, is_ads, is_moving,
		is_sprinting, is_crouching, is_airborne, is_prone
	)

	if total_spread <= 0.0:
		return base_direction

	return _apply_cone_spread(base_direction, total_spread)


## Returns total spread angle in degrees for UI display (crosshair size).
static func get_crosshair_spread(
	weapon_data: WeaponData,
	recoil_spread: float = 0.0,
	is_ads: bool = false,
	is_moving: bool = false,
	is_sprinting: bool = false,
	is_crouching: bool = false,
	is_airborne: bool = false,
	is_prone: bool = false,
) -> float:
	return _get_total_spread(
		weapon_data, recoil_spread, is_ads, is_moving,
		is_sprinting, is_crouching, is_airborne, is_prone
	)


# ── Internal ───────────────────────────────────────────────────────────────────

static func _get_total_spread(
	wd: WeaponData,
	recoil: float,
	ads: bool, moving: bool, sprinting: bool,
	crouching: bool, airborne: bool, prone: bool
) -> float:
	var base: float  = wd.base_spread if wd else 1.0

	# ADS multiplier (significantly reduces spread).
	if ads:
		base *= wd.ads_spread_multiplier if wd else 0.25

	# Recoil contribution.
	base += recoil

	# Stance modifiers.
	if prone:     base *= 0.4
	elif crouching: base *= 0.65
	if airborne:  base *= 2.2
	if sprinting: base *= 2.8
	elif moving:  base *= 1.4

	return maxf(base, 0.0)


static func _apply_cone_spread(direction: Vector3, spread_degrees: float) -> Vector3:
	# Convert spread angle to a random offset within a circle.
	var spread_rad: float = deg_to_rad(spread_degrees)
	var cone_radius: float = tan(spread_rad)

	# Random point in disc.
	var angle: float  = randf() * TAU
	var radius: float = sqrt(randf()) * cone_radius  # sqrt for uniform disc sampling.
	var offset_x: float = cos(angle) * radius
	var offset_y: float = sin(angle) * radius

	# Build a perpendicular basis from the direction.
	var up: Vector3    = Vector3.UP if abs(direction.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var right: Vector3 = direction.cross(up).normalized()
	var real_up: Vector3 = right.cross(direction).normalized()

	return (direction + right * offset_x + real_up * offset_y).normalized()
