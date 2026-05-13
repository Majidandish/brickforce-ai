## =============================================================================
## MovementConfig — Data Resource for Character Movement Tuning
## =============================================================================
## Purpose:
##   All movement feel values live here. Create one .tres per character
##   archetype. Zero code changes for balance tweaks.
## =============================================================================

class_name MovementConfig
extends Resource

# ── Speeds (m/s) ───────────────────────────────────────────────────────────────
@export_group("Speeds")
@export var walk_speed: float         = 5.0
@export var sprint_speed: float       = 8.5
@export var crouch_speed: float       = 2.5
@export var prone_speed: float        = 1.2
@export var swim_speed: float         = 3.0
@export var aim_speed_multiplier: float = 0.65   # Multiplier while ADS.

# ── Acceleration ───────────────────────────────────────────────────────────────
@export_group("Acceleration")
@export var acceleration: float       = 12.0   # Ground.
@export var deceleration: float       = 18.0   # Ground.
@export var air_control: float        = 2.5    # Air.

# ── Jump ───────────────────────────────────────────────────────────────────────
@export_group("Jump")
@export var jump_velocity: float      = 5.5
@export var fall_gravity_multiplier: float = 1.8  # Extra gravity on fall arc.
@export var max_fall_speed: float     = -20.0
@export var coyote_time: float        = 0.12    # Jump grace after leaving ledge.
@export var jump_buffer_time: float   = 0.1     # Buffer before landing for input.
@export var hard_landing_threshold: float = 8.0  # Fall speed that triggers land FX.

# ── Slide ──────────────────────────────────────────────────────────────────────
@export_group("Slide")
@export var slide_duration: float         = 0.9
@export var slide_speed_multiplier: float = 1.3   # Boost on slide entry.
@export var slide_friction: float         = 3.5

# ── Vault ──────────────────────────────────────────────────────────────────────
@export_group("Vault")
@export var vault_max_height: float  = 1.2
@export var vault_duration: float    = 0.35

# ── Footsteps ─────────────────────────────────────────────────────────────────
@export_group("Footsteps")
@export var footstep_interval_walk: float   = 0.45
@export var footstep_interval_sprint: float = 0.28

# ── Collision Shape Scale ──────────────────────────────────────────────────────
@export_group("Collision")
@export var stand_capsule_height: float  = 1.8
@export var crouch_capsule_height: float = 1.1
@export var prone_capsule_height: float  = 0.5
