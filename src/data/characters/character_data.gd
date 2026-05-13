## =============================================================================
## CharacterData — Data-Driven Character Configuration Resource
## =============================================================================
## Purpose:
##   Holds all base stats, faction, AI personality, cosmetic references,
##   and ability definitions for a character archetype. One .tres per type.
## =============================================================================

class_name CharacterData
extends Resource

# ── Identity ───────────────────────────────────────────────────────────────────
@export var character_id: String             = "char_default"
@export var display_name: String             = "Unknown"
@export var description: String              = ""
@export var faction: int                     = 2      # 0=player 1=ally 2=enemy

# ── Vitals ─────────────────────────────────────────────────────────────────────
@export var max_health: float                = 100.0
@export var health_regen_per_sec: float      = 0.0
@export var base_armor: float                = 0.0
@export var revive_threshold: float          = 0.0   # HP% below which downed.

# ── Movement ──────────────────────────────────────────────────────────────────
@export var move_speed: float                = 5.0
@export var sprint_multiplier: float         = 1.7
@export var crouch_speed: float              = 2.5
@export var jump_velocity: float             = 5.0
@export var can_sprint: bool                 = true
@export var can_crouch: bool                 = true
@export var can_prone: bool                  = false

# ── AI Personality (used by AICharacter) ──────────────────────────────────────
@export_group("AI")
@export_enum("Passive","Defensive","Balanced","Aggressive","Flanker","Sniper","Support","Berserker")
var ai_personality: int                      = 2
@export var detection_range: float           = 30.0
@export var hearing_range: float             = 20.0
@export var reaction_time: float             = 0.4
@export var accuracy: float                  = 0.75    # 0.0-1.0
@export var cover_preference: float          = 0.8     # How likely to seek cover.
@export var aggression: float                = 0.5     # 0=flee 1=charge
@export var squad_cohesion: float            = 0.7     # How closely AI follows squad.

# ── Abilities ─────────────────────────────────────────────────────────────────
@export_group("Abilities")
@export var ability_ids: Array[String]       = []
@export var passive_ability_ids: Array[String] = []

# ── Loadout ───────────────────────────────────────────────────────────────────
@export_group("Default Loadout")
@export var default_primary: String          = ""
@export var default_secondary: String        = ""
@export var default_throwable: String        = ""

# ── Visuals ───────────────────────────────────────────────────────────────────
@export_group("Visuals")
@export var scene_path: String               = ""
@export var icon: Texture2D                  = null
@export var portrait: Texture2D              = null
@export var rarity: int                      = 0

# ── Audio ─────────────────────────────────────────────────────────────────────
@export_group("Audio")
@export var voice_bank: String               = ""
@export var footstep_set: String             = "default"

# ── Economy ───────────────────────────────────────────────────────────────────
@export_group("Economy")
@export var unlock_cost: int                 = 0
@export var unlock_currency: String          = "gold"
@export var is_default_unlocked: bool        = false
