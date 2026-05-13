## =============================================================================
## HitZone — Physics Area for Body Part Hit Detection
## =============================================================================
## Architecture:
##   One HitZone per body part (head, chest, abdomen, left_arm, right_arm,
##   left_leg, right_leg). Each is an Area3D child of the Skeleton3D.
##   BallisticsSystem checks hit.collider for HitZone to determine
##   headshot, limb, or body hit multipliers.
##
##   Attach to a BoneAttachment3D on the matching skeleton bone.
## =============================================================================

class_name HitZone
extends Area3D

enum ZoneType { HEAD, CHEST, ABDOMEN, LEFT_ARM, RIGHT_ARM, LEFT_LEG, RIGHT_LEG }

const ZONE_MULTIPLIERS: Dictionary = {
	ZoneType.HEAD:      2.5,
	ZoneType.CHEST:     1.0,
	ZoneType.ABDOMEN:   0.9,
	ZoneType.LEFT_ARM:  0.75,
	ZoneType.RIGHT_ARM: 0.75,
	ZoneType.LEFT_LEG:  0.7,
	ZoneType.RIGHT_LEG: 0.7,
}

const ZONE_NAMES: Dictionary = {
	ZoneType.HEAD:      "head",
	ZoneType.CHEST:     "chest",
	ZoneType.ABDOMEN:   "abdomen",
	ZoneType.LEFT_ARM:  "left_arm",
	ZoneType.RIGHT_ARM: "right_arm",
	ZoneType.LEFT_LEG:  "left_leg",
	ZoneType.RIGHT_LEG: "right_leg",
}

@export var zone_type: ZoneType = ZoneType.CHEST

var owner_character: CharacterBase = null


func _ready() -> void:
	# Set meta for BallisticsSystem detection.
	set_meta("hit_zone", ZONE_NAMES.get(zone_type, "body"))
	set_meta("is_head_hitbox", zone_type == ZoneType.HEAD)
	set_meta("damage_multiplier", ZONE_MULTIPLIERS.get(zone_type, 1.0))
	collision_layer = 2   # Character hit layer.
	collision_mask  = 0   # Hit zones don't detect — they're detected.
	monitoring      = false
	monitorable     = true

	# Walk up to find owning character.
	var p: Node = get_parent()
	while p:
		if p is CharacterBase:
			owner_character = p as CharacterBase
			break
		p = p.get_parent()


## Get the damage multiplier for this zone.
func get_multiplier() -> float:
	return ZONE_MULTIPLIERS.get(zone_type, 1.0)


## Get the zone name string.
func get_zone_name() -> String:
	return ZONE_NAMES.get(zone_type, "body")


## Returns true if this is a headshot zone.
func is_headshot() -> bool:
	return zone_type == ZoneType.HEAD


## Build all standard hit zones as children of a parent node.
## Call once during character scene setup.
static func build_standard_zones(parent: Node3D, character: CharacterBase) -> void:
	const ZONE_CONFIGS: Array[Dictionary] = [
		{ "type": ZoneType.HEAD,      "size": Vector3(0.2, 0.25, 0.2), "offset": Vector3(0, 1.7, 0) },
		{ "type": ZoneType.CHEST,     "size": Vector3(0.4, 0.35, 0.25), "offset": Vector3(0, 1.35, 0) },
		{ "type": ZoneType.ABDOMEN,   "size": Vector3(0.35, 0.25, 0.22), "offset": Vector3(0, 1.05, 0) },
		{ "type": ZoneType.LEFT_ARM,  "size": Vector3(0.15, 0.35, 0.15), "offset": Vector3(-0.3, 1.3, 0) },
		{ "type": ZoneType.RIGHT_ARM, "size": Vector3(0.15, 0.35, 0.15), "offset": Vector3(0.3, 1.3, 0) },
		{ "type": ZoneType.LEFT_LEG,  "size": Vector3(0.18, 0.45, 0.18), "offset": Vector3(-0.18, 0.65, 0) },
		{ "type": ZoneType.RIGHT_LEG, "size": Vector3(0.18, 0.45, 0.18), "offset": Vector3(0.18, 0.65, 0) },
	]
	for cfg in ZONE_CONFIGS:
		var zone: HitZone           = HitZone.new()
		zone.zone_type              = cfg.type
		zone.owner_character        = character
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D         = BoxShape3D.new()
		box.size                    = cfg.size
		shape.shape                 = box
		shape.position              = cfg.offset
		zone.add_child(shape)
		parent.add_child(zone)
