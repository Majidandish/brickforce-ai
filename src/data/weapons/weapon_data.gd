## =============================================================================
## WeaponData — Data-Driven Weapon Configuration Resource
## =============================================================================
## Purpose:
##   Godot Resource holding ALL stats for a weapon. Create one .tres file
##   per weapon variant. No code changes needed to add new weapons.
##   Supports full localization keys for names/descriptions.
## =============================================================================

class_name WeaponData
extends Resource

# ── Identity ───────────────────────────────────────────────────────────────────
@export var weapon_id: String                = "weapon_default"
@export var display_name: String             = "Unknown Weapon"
@export var description: String              = ""
@export_enum("Assault Rifle", "SMG", "Sniper", "Shotgun", "Pistol", "Melee", "Grenade", "LMG", "Marksman")
var weapon_class: int                        = 0

# ── Combat ─────────────────────────────────────────────────────────────────────
@export var damage: float                    = 35.0
@export var headshot_multiplier: float       = 2.5
@export var limb_multiplier: float           = 0.75
@export var armor_penetration: float         = 0.0   # 0.0-1.0
@export var range: float                     = 200.0  # meters
@export var rpm: int                         = 600    # rounds per minute
@export var default_fire_mode: int           = 2      # See WeaponBase.FireMode
@export var available_fire_modes: Array[int] = [2]
@export var burst_count: int                 = 3

# ── Spread & Recoil ────────────────────────────────────────────────────────────
@export var base_spread: float               = 0.3
@export var spread_per_shot: float           = 0.5
@export var spread_recovery: float           = 3.0
@export var vertical_recoil: float           = 1.0
@export var horizontal_recoil: float         = 0.4
@export var recoil_recovery: float           = 0.15
@export var ads_spread_multiplier: float     = 0.25  # Spread when aiming.

# ── Ammo ───────────────────────────────────────────────────────────────────────
@export var mag_size: int                    = 30
@export var reserve_max: int                 = 180
@export var ammo_type: String                = "rifle_ammo"
@export var reload_time: float               = 2.4
@export var is_hitscan: bool                 = true
@export var projectile_speed: float          = 0.0   # 0 = hitscan only
@export var pellet_count: int                = 1     # >1 for shotguns.

# ── Handling ───────────────────────────────────────────────────────────────────
@export var equip_time: float                = 0.6
@export var ads_time: float                  = 0.25   # Aim-down-sights time.
@export var move_speed_penalty: float        = 0.9    # Multiplier while holding.
@export var ads_move_speed_penalty: float    = 0.65

# ── Attachments ────────────────────────────────────────────────────────────────
@export var attachment_slots: Array[String]  = ["scope", "muzzle", "grip", "stock", "magazine"]
@export var max_attachments: int             = 3

# ── Audio / VFX ───────────────────────────────────────────────────────────────
@export_file("*.ogg","*.wav","*.mp3") var fire_sound: String    = ""
@export_file("*.ogg","*.wav","*.mp3") var reload_sound: String  = ""
@export_file("*.ogg","*.wav","*.mp3") var empty_sound: String   = ""
@export_file("*.ogg","*.wav","*.mp3") var equip_sound: String   = ""
@export var muzzle_flash_id: String                             = "muzzle_flash_rifle"
@export var impact_vfx_id: String                               = "bullet_impact_concrete"

# ── Visuals ────────────────────────────────────────────────────────────────────
@export var scene_path: String              = ""
@export var icon: Texture2D                 = null
@export var rarity: int                     = 0   # 0=common 1=uncommon 2=rare 3=epic 4=legendary

# ── Economy ────────────────────────────────────────────────────────────────────
@export var loot_weight: float             = 1.0  # Spawn probability weight.
@export var shop_cost: int                 = 0    # 0 = not in shop.
@export var shop_currency: String          = "gold"
