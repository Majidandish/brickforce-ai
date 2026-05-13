## =============================================================================
## CameraConfig — Data Resource for Camera Tuning
## =============================================================================

class_name CameraConfig
extends Resource

# ── FOV ────────────────────────────────────────────────────────────────────────
@export_group("FOV")
@export var default_fov: float      = 75.0
@export var ads_fov: float          = 55.0
@export var sprint_fov: float       = 80.0
@export var fov_lerp_speed: float   = 10.0

# ── Arm ────────────────────────────────────────────────────────────────────────
@export_group("Arm")
@export var default_arm_length: float  = 2.5
@export var ads_arm_length: float      = 0.8   # Pulls closer when aiming.
@export var min_arm_length: float      = 0.1
@export var collision_margin: float    = 0.1
@export var collision_lerp_speed: float = 15.0

# ── Look ───────────────────────────────────────────────────────────────────────
@export_group("Look")
@export var pitch_min: float   = -1.2    # ~-70 degrees in radians.
@export var pitch_max: float   = 1.0     # ~+57 degrees.
@export var sensitivity: float = 0.003
@export var ads_sensitivity_multiplier: float = 0.5
@export var controller_sensitivity: float = 3.0

# ── Shake ──────────────────────────────────────────────────────────────────────
@export_group("Shake")
@export var max_shake_degrees: float = 3.0
@export var trauma_decay: float      = 1.5

# ── Lean ──────────────────────────────────────────────────────────────────────
@export_group("Lean")
@export var lean_angle: float = 7.0

# ── Free Look ─────────────────────────────────────────────────────────────────
@export_group("Free Look")
@export var free_look_clamp: float = 120.0        # Max degrees.
@export var free_look_horizontal_offset: float = 0.5
