## =============================================================================
## ItemData — Data-Driven Item Configuration Resource
## =============================================================================
## Purpose:
##   Base resource for all lootable/usable items: consumables, attachments,
##   equipment, throwables, and crafting materials. Extend for specialised
##   item types (HealItemData, ArmorItemData, AttachmentData etc.)
## =============================================================================

class_name ItemData
extends Resource

# ── Item Types ─────────────────────────────────────────────────────────────────
enum ItemType {
	CONSUMABLE,    # Medkits, syringes, energy drinks.
	ATTACHMENT,    # Scopes, silencers, grips.
	EQUIPMENT,     # Vests, helmets, backpacks.
	THROWABLE,     # Grenades, smoke, flashbangs.
	AMMO,          # Ammo boxes/piles.
	MATERIAL,      # Crafting resources.
	KEY_ITEM,      # Story / quest items.
	COSMETIC,      # Skins, sprays (non-functional).
	CURRENCY_ITEM, # Gift boxes, tokens.
}

# ── Identity ───────────────────────────────────────────────────────────────────
@export var item_id: String                  = "item_default"
@export var display_name: String             = "Unknown Item"
@export var description: String              = ""
@export var item_type: ItemType              = ItemType.CONSUMABLE
@export var rarity: int                      = 0   # 0=common … 4=legendary

# ── Stack & Weight ────────────────────────────────────────────────────────────
@export var max_stack: int                   = 1
@export var weight: float                    = 0.5   # kg — for carry weight systems.
@export var is_droppable: bool               = true
@export var is_tradeable: bool               = true

# ── Use Effect ────────────────────────────────────────────────────────────────
@export_group("Use Effect")
@export var use_time: float                  = 1.0   # Seconds to use.
@export var can_use_while_moving: bool       = false
@export var can_use_while_downed: bool       = false
@export var heal_amount: float               = 0.0
@export var armor_restore: float             = 0.0
@export var speed_bonus: float               = 0.0
@export var speed_bonus_duration: float      = 0.0
@export var effect_id: String                = ""    # Status effect to apply.

# ── Visuals ───────────────────────────────────────────────────────────────────
@export_group("Visuals")
@export var icon: Texture2D                  = null
@export var world_scene: String              = ""    # 3D world pickup scene.
@export var color_tint: Color                = Color.WHITE

# ── Loot Table ────────────────────────────────────────────────────────────────
@export_group("Loot")
@export var loot_weight: float               = 1.0
@export var spawn_in_crates: bool            = true
@export var spawn_on_ground: bool            = true
@export var min_spawn_quantity: int          = 1
@export var max_spawn_quantity: int          = 1

# ── Economy ───────────────────────────────────────────────────────────────────
@export_group("Economy")
@export var shop_cost: int                   = 0
@export var shop_currency: String            = "gold"
@export var sell_value: int                  = 0
