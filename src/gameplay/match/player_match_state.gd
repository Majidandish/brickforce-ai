## =============================================================================
## PlayerMatchState — Per-Player Match Statistics Container
## =============================================================================
## Pure data class. Owned by MatchScoring. Serializable for API reporting.
## =============================================================================

class_name PlayerMatchState
extends RefCounted

var player_id: int      = -1
var display_name: String = ""
var score: int           = 0
var kills: int           = 0
var headshots: int       = 0
var assists: int         = 0
var revives: int         = 0
var damage_dealt: float  = 0.0
var damage_taken: float  = 0.0
var shots_fired: int     = 0
var shots_hit: int       = 0
var placement: int       = 999
var is_alive: bool       = true
var join_time: float     = 0.0
var death_time: float    = 0.0
var survival_seconds: float:
	get:
		if is_alive:
			return Time.get_unix_time_from_system() - join_time
		return death_time - join_time

## Accuracy ratio 0-1.
var accuracy: float:
	get:
		return float(shots_hit) / float(shots_fired) if shots_fired > 0 else 0.0


## Serialise to dictionary for API / save.
func to_dict() -> Dictionary:
	return {
		"player_id":      player_id,
		"display_name":   display_name,
		"score":          score,
		"kills":          kills,
		"headshots":      headshots,
		"assists":        assists,
		"revives":        revives,
		"damage_dealt":   int(damage_dealt),
		"damage_taken":   int(damage_taken),
		"shots_fired":    shots_fired,
		"shots_hit":      shots_hit,
		"accuracy":       snappedf(accuracy * 100.0, 0.1),
		"placement":      placement,
		"survival_secs":  int(survival_seconds),
		"is_alive":       is_alive,
	}


## XP reward based on performance.
func compute_xp_reward(base_xp: int = 100) -> int:
	var xp: int = base_xp
	xp += kills * 50
	xp += headshots * 25
	xp += assists * 20
	xp += revives * 30
	xp += int(damage_dealt * 0.05)
	xp += int(survival_seconds * 0.2)
	# Placement multiplier.
	var placement_mult: float = 1.0 + (1.0 / maxf(float(placement), 1.0))
	xp = int(float(xp) * placement_mult)
	return xp
