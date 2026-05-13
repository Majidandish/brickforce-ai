## =============================================================================
## BallisticsSystem — Hitscan & Projectile Hit Processing
## =============================================================================
## Architecture:
##   Centralised hit processing for all weapon fire modes:
##     - Hitscan: immediate raycast, damage applied this frame.
##     - Projectile: spawns a physics projectile (future).
##     - Pellet: shotgun-style multi-ray.
##
##   Responsible for:
##     - Hit zone detection (head/chest/limb)
##     - Damage falloff by range
##     - Penetration (shooting through thin surfaces)
##     - Surface type detection (concrete/metal/flesh)
##     - Spawning hit VFX + decals
##
##   Server-authoritative. Client predicts locally for responsiveness,
##   but server validates and applies actual damage.
## =============================================================================

class_name BallisticsSystem
extends RefCounted

const MAX_PENETRATION_THICKNESS: float = 0.15  # Surfaces thinner than this are penetrated.
const SURFACE_LAYER_WORLD: int         = 1
const SURFACE_LAYER_CHARACTER: int     = 2

## Process a hitscan shot. Returns array of HitResult dictionaries.
static func process_hitscan(
	origin: Vector3,
	direction: Vector3,
	weapon_data: WeaponData,
	shooter_id: int,
	space_state: PhysicsDirectSpaceState3D,
	exclude_nodes: Array = [],
) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var max_range: float = weapon_data.range if weapon_data else 200.0
	var penetration_left: int = 1  # Number of surfaces that can be penetrated.

	var from: Vector3 = origin
	var to:   Vector3 = origin + direction * max_range

	while penetration_left >= 0:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = SURFACE_LAYER_WORLD | SURFACE_LAYER_CHARACTER
		query.exclude = exclude_nodes

		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			break

		var result: Dictionary = _process_hit(hit, weapon_data, shooter_id, from)
		results.append(result)
		_spawn_hit_vfx(result)

		if result.get("penetrated", false):
			from = hit.position + direction * 0.02  # Step past the surface.
			penetration_left -= 1
			exclude_nodes.append(hit.collider)
		else:
			break

	return results


## Process a shotgun spread (multiple pellets).
static func process_pellets(
	origin: Vector3,
	base_direction: Vector3,
	weapon_data: WeaponData,
	shooter_id: int,
	space_state: PhysicsDirectSpaceState3D,
	exclude_nodes: Array = [],
) -> Array[Dictionary]:
	var all_results: Array[Dictionary] = []
	var pellets: int = weapon_data.pellet_count if weapon_data else 1
	for i in pellets:
		var spread_dir: Vector3 = SpreadCalculator.calculate(
			base_direction, weapon_data, 0.0, false, false, false, false, false
		)
		var hits: Array[Dictionary] = process_hitscan(
			origin, spread_dir, weapon_data, shooter_id, space_state, exclude_nodes.duplicate()
		)
		all_results.append_array(hits)
	return all_results


# ── Internal ───────────────────────────────────────────────────────────────────

static func _process_hit(
	hit: Dictionary,
	weapon_data: WeaponData,
	shooter_id: int,
	shot_origin: Vector3,
) -> Dictionary:
	var collider: Node = hit.collider
	var hit_point: Vector3  = hit.position
	var hit_normal: Vector3 = hit.normal
	var bone_name: String   = ""
	var is_character: bool  = false
	var is_headshot: bool   = false
	var is_limb: bool       = false

	# Hit zone detection.
	if collider.has_meta("hit_zone"):
		bone_name  = collider.get_meta("hit_zone", "body")
		is_headshot = bone_name == "head"
		is_limb     = bone_name in ["left_arm", "right_arm", "left_leg", "right_leg"]
		is_character = true

	# Distance-based damage falloff.
	var dist: float  = shot_origin.distance_to(hit_point)
	var damage: float = _calculate_damage(weapon_data, dist, is_headshot, is_limb)

	# Apply to target.
	var target_character: CharacterBase = null
	if is_character:
		var parent: Node = collider.get_parent()
		while parent:
			if parent is CharacterBase:
				target_character = parent as CharacterBase
				break
			parent = parent.get_parent()

	if target_character:
		target_character.take_damage(damage, shooter_id, "bullet", hit_point, bone_name)

	# Penetration check (thin surfaces).
	var surface_type: String = _detect_surface(collider)
	var penetrated: bool = (
		surface_type in ["wood", "drywall", "glass"]
		and not is_character
	)

	return {
		"hit_point":     hit_point,
		"hit_normal":    hit_normal,
		"collider":      collider,
		"bone":          bone_name,
		"is_character":  is_character,
		"is_headshot":   is_headshot,
		"is_limb":       is_limb,
		"damage":        damage,
		"distance":      dist,
		"surface":       surface_type,
		"penetrated":    penetrated,
		"target":        target_character,
		"shooter_id":    shooter_id,
	}


static func _calculate_damage(
	wd: WeaponData, dist: float, headshot: bool, limb: bool
) -> float:
	if not wd:
		return 25.0

	# Falloff: linear from wd.range * 0.5 to wd.range.
	var falloff_start: float = wd.range * 0.5
	var damage: float = wd.damage
	if dist > falloff_start:
		var t: float = (dist - falloff_start) / (wd.range - falloff_start)
		damage = lerpf(wd.damage, wd.damage * 0.4, clampf(t, 0.0, 1.0))

	if headshot: damage *= wd.headshot_multiplier
	elif limb:   damage *= wd.limb_multiplier

	return maxf(damage, 1.0)


static func _detect_surface(collider: Node) -> String:
	if collider.has_meta("surface_type"):
		return collider.get_meta("surface_type")
	return "concrete"


static func _spawn_hit_vfx(result: Dictionary) -> void:
	var surface: String = result.get("surface", "concrete")
	var point: Vector3  = result.get("hit_point", Vector3.ZERO)
	var normal: Vector3 = result.get("hit_normal", Vector3.UP)

	if result.get("is_character", false):
		VFXManager.play("bullet_impact_flesh", point)
		if result.get("is_headshot", false):
			VFXManager.hit_marker(true)
		else:
			VFXManager.hit_marker(false)
	else:
		match surface:
			"metal":  VFXManager.play("bullet_impact_metal", point)
			_:        VFXManager.play("bullet_impact_concrete", point)
		VFXManager.place_decal("bullet_hole_concrete", point, normal)
