## =============================================================================
## CosmeticManager — Cosmetic Unlocks & Customization (Autoload)
## =============================================================================
## Purpose:
##   Tracks unlocked cosmetics (skins, emotes, sprays, charms, banners).
##   Manages active equipped cosmetics per category. Integrates with
##   InventoryManager and ShopManager. Future: battle pass unlock chain.
## =============================================================================

extends Node

## Cosmetic categories.
enum CosmeticType {
	CHARACTER_SKIN,
	WEAPON_SKIN,
	EMOTE,
	SPRAY,
	BANNER,
	AVATAR_FRAME,
	PARACHUTE,
	VEHICLE_SKIN,
	KILL_EFFECT,
	VICTORY_POSE,
}

const TYPE_KEYS: Dictionary = {
	CosmeticType.CHARACTER_SKIN: "character_skin",
	CosmeticType.WEAPON_SKIN:    "weapon_skin",
	CosmeticType.EMOTE:          "emote",
	CosmeticType.SPRAY:          "spray",
	CosmeticType.BANNER:         "banner",
	CosmeticType.AVATAR_FRAME:   "avatar_frame",
	CosmeticType.PARACHUTE:      "parachute",
	CosmeticType.VEHICLE_SKIN:   "vehicle_skin",
	CosmeticType.KILL_EFFECT:    "kill_effect",
	CosmeticType.VICTORY_POSE:   "victory_pose",
}

signal cosmetic_unlocked(cosmetic_id: String, cosmetic_type: CosmeticType)
signal cosmetic_equipped(cosmetic_id: String, category: String)

## cosmetic_id -> CosmeticType
var _unlocked: Dictionary = {}
## category_key -> cosmetic_id
var _equipped: Dictionary = {}


func _ready() -> void:
	name = "CosmeticManager"
	_init_defaults()
	SaveManager.register_serializer("cosmetics", _save, _load_data)
	Logger.info("CosmeticManager", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Unlock a cosmetic (called after purchase or reward).
func unlock(cosmetic_id: String, cosmetic_type: CosmeticType) -> void:
	if _unlocked.has(cosmetic_id):
		return
	_unlocked[cosmetic_id] = cosmetic_type
	cosmetic_unlocked.emit(cosmetic_id, cosmetic_type)
	EventBus.cosmetic_unlocked.emit(cosmetic_id)
	Logger.info("CosmeticManager", "Unlocked: %s (%s)" % [cosmetic_id, TYPE_KEYS[cosmetic_type]])


## Returns true if a cosmetic is unlocked.
func is_unlocked(cosmetic_id: String) -> bool:
	return _unlocked.has(cosmetic_id)


## Equip a cosmetic in its category.
func equip(cosmetic_id: String) -> bool:
	if not is_unlocked(cosmetic_id):
		Logger.warn("CosmeticManager", "Cannot equip locked cosmetic: %s" % cosmetic_id)
		return false
	var ctype: CosmeticType = _unlocked[cosmetic_id]
	var category: String = TYPE_KEYS[ctype]
	_equipped[category] = cosmetic_id
	cosmetic_equipped.emit(cosmetic_id, category)
	Logger.debug("CosmeticManager", "Equipped [%s]: %s" % [category, cosmetic_id])
	return true


## Get currently equipped cosmetic for a category.
func get_equipped(category: String) -> String:
	return _equipped.get(category, "")


## Get all unlocked cosmetics of a type.
func get_unlocked_of_type(cosmetic_type: CosmeticType) -> Array[String]:
	var result: Array[String] = []
	for id in _unlocked:
		if _unlocked[id] == cosmetic_type:
			result.append(id)
	return result


## Get the full loadout as a dictionary (for applying to a character).
func get_active_loadout() -> Dictionary:
	return _equipped.duplicate()


## Returns total number of unlocked cosmetics.
func get_unlock_count() -> int:
	return _unlocked.size()


# ── Internal ───────────────────────────────────────────────────────────────────

func _init_defaults() -> void:
	# Default cosmetics unlocked for all players.
	unlock("skin_char_default",   CosmeticType.CHARACTER_SKIN)
	unlock("skin_weapon_default", CosmeticType.WEAPON_SKIN)
	_equipped[TYPE_KEYS[CosmeticType.CHARACTER_SKIN]] = "skin_char_default"
	_equipped[TYPE_KEYS[CosmeticType.WEAPON_SKIN]]    = "skin_weapon_default"


func _save() -> Dictionary:
	return {
		"unlocked": _unlocked.duplicate(),
		"equipped": _equipped.duplicate(),
	}


func _load_data(data: Dictionary) -> void:
	if data.has("unlocked"):
		for id in data.unlocked:
			_unlocked[id] = data.unlocked[id] as CosmeticType
	if data.has("equipped"):
		_equipped = data.equipped.duplicate()
	Logger.info("CosmeticManager", "Cosmetics loaded (%d unlocked)." % _unlocked.size())
