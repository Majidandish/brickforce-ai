## =============================================================================
## SquadAICommander — Tactical Squad AI Decision Layer
## =============================================================================
## Purpose:
##   Mass Effect-inspired squad AI command layer. Evaluates squad state,
##   threat assessment, zone position, and member health to issue real-time
##   tactical commands to individual AI agents.
##
##   Responsibilities:
##     - Threat prioritisation across the squad
##     - Cover assignment and flanking routing
##     - Suppression, revive, and retreat coordination
##     - Formation management based on situation
##     - Adaptive difficulty scaling
## =============================================================================

class_name SquadAICommander
extends Node

const UPDATE_INTERVAL: float = 0.5   # Tactical evaluation every 0.5s

signal command_broadcast(command: String, data: Dictionary)
signal formation_changed(formation: String)
signal threat_level_changed(level: int)

## The squad this commander owns.
var squad_id: int = -1
var _members: Array[CharacterBase] = []
var _leader: CharacterBase = null

## Tactical state.
var threat_level: int         = 0   # 0=none 1=low 2=medium 3=high 4=critical
var current_objective: String = "roam"
var objective_position: Vector3 = Vector3.ZERO
var known_threats: Array[CharacterBase] = []

# ── Internal ───────────────────────────────────────────────────────────────────
var _update_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	name = "SquadAICommander"
	_rng.randomize()


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_evaluate_situation()


# ── Public API ─────────────────────────────────────────────────────────────────

## Initialize commander with squad members.
func initialize(id: int, members: Array[CharacterBase], leader: CharacterBase) -> void:
	squad_id  = id
	_members  = members
	_leader   = leader
	Logger.info("SquadAICommander", "Commander ready for squad %d (%d members)." % [id, members.size()])


## Receive an external command (from player or SquadManager).
func receive_command(command: String, data: Dictionary = {}) -> void:
	current_objective = command
	if data.has("position"):
		objective_position = data.position
	Logger.debug("SquadAICommander", "Squad %d received command: %s" % [squad_id, command])
	_execute_command(command, data)


## Report a spotted threat (called by member PerceptionSystems).
func report_threat(threat: CharacterBase, spotter: CharacterBase) -> void:
	if threat not in known_threats:
		known_threats.append(threat)
	_update_threat_level()
	Logger.debug("SquadAICommander", "Threat reported by %d: target %d" % [
		spotter.character_id, threat.character_id
	])


## Report a member's health status.
func report_health(member: CharacterBase) -> void:
	if member.get_health_ratio() < 0.3:
		_handle_low_health_member(member)


# ── Internal — Situation Evaluation ───────────────────────────────────────────

func _evaluate_situation() -> void:
	_clean_known_threats()
	_update_threat_level()
	_check_members()

	match current_objective:
		"roam":    _evaluate_roam()
		"attack":  _evaluate_attack()
		"defend":  _evaluate_defend()
		"retreat": _evaluate_retreat()
		"hold":    pass  # Static — no re-evaluation needed.


func _evaluate_roam() -> void:
	if known_threats.is_empty():
		if _update_timer == 0.0:  # Just evaluated.
			_command_patrol()
	else:
		_transition_to_combat()


func _evaluate_attack() -> void:
	if known_threats.is_empty():
		current_objective = "roam"
		return
	var primary: CharacterBase = _get_priority_threat()
	if primary:
		_assign_roles_for_attack(primary)


func _evaluate_defend() -> void:
	if known_threats.size() > 2:
		_command_all("take_cover", { "urgency": "high" })


func _evaluate_retreat() -> void:
	_command_all("retreat", { "direction": _get_retreat_direction() })


# ── Internal — Command Dispatch ────────────────────────────────────────────────

func _execute_command(command: String, data: Dictionary) -> void:
	match command:
		"attack":   _transition_to_combat()
		"defend":   _command_all("take_cover", data)
		"retreat":  _command_all("retreat", data)
		"hold":     _command_all("hold_position", data)
		"flank":    _command_flank(data.get("target", null))
		"revive":   _command_revive()
		"move_to":  _command_all("move_to", data)


func _transition_to_combat() -> void:
	current_objective = "attack"
	var primary: CharacterBase = _get_priority_threat()
	if not primary:
		return
	_assign_roles_for_attack(primary)


func _assign_roles_for_attack(target: CharacterBase) -> void:
	var alive: Array[CharacterBase] = _get_alive_members()
	if alive.is_empty():
		return

	# Leader engages directly.
	if is_instance_valid(_leader) and _leader.is_alive:
		_command_member(_leader, "engage", { "target_id": target.character_id })

	# Second member flanks.
	if alive.size() >= 2:
		var flanker: CharacterBase = alive[1]
		var flank_pos: Vector3 = _calculate_flank_position(target.global_position, flanker.global_position)
		_command_member(flanker, "flank_to", {
			"flank_position": flank_pos,
			"target_id": target.character_id,
		})

	# Third member suppresses.
	if alive.size() >= 3:
		_command_member(alive[2], "suppress", { "target_id": target.character_id })

	# Fourth member supports / covers.
	if alive.size() >= 4:
		_command_member(alive[3], "support_cover", { "watch_direction": target.global_position })


func _command_patrol() -> void:
	var patrol_point: Vector3 = objective_position + Vector3(
		_rng.randf_range(-15.0, 15.0), 0, _rng.randf_range(-15.0, 15.0)
	)
	_command_all("patrol_to", { "position": patrol_point })


func _command_flank(target: CharacterBase) -> void:
	if not target:
		return
	for m in _get_alive_members():
		var flank_pos: Vector3 = _calculate_flank_position(target.global_position, m.global_position)
		_command_member(m, "flank_to", { "flank_position": flank_pos, "target_id": target.character_id })


func _command_revive() -> void:
	var downed: CharacterBase = _get_downed_member()
	if not downed:
		return
	var closest: CharacterBase = _get_closest_alive_member(downed.global_position)
	if closest:
		_command_member(closest, "revive_ally", { "target_id": downed.character_id })


func _command_all(command: String, data: Dictionary = {}) -> void:
	for m in _get_alive_members():
		_command_member(m, command, data)
	command_broadcast.emit(command, data)


func _command_member(member: CharacterBase, command: String, data: Dictionary) -> void:
	if member.has_method("receive_ai_command"):
		member.receive_ai_command(command, data)


# ── Internal — Helpers ─────────────────────────────────────────────────────────

func _handle_low_health_member(member: CharacterBase) -> void:
	_command_member(member, "retreat_to_cover", {})
	var support: CharacterBase = _get_closest_alive_member(member.global_position, [member])
	if support:
		_command_member(support, "provide_cover", { "protect_id": member.character_id })


func _get_priority_threat() -> CharacterBase:
	var best: CharacterBase = null
	var best_score: float   = -1.0
	var leader_pos: Vector3 = _leader.global_position if _leader else Vector3.ZERO
	for t in known_threats:
		if not is_instance_valid(t) or not t.is_alive:
			continue
		var dist: float    = leader_pos.distance_to(t.global_position)
		var hp_fac: float  = 1.0 - t.get_health_ratio()
		var score: float   = hp_fac + (1.0 / max(dist, 1.0))
		if score > best_score:
			best_score = score
			best = t
	return best


func _get_alive_members() -> Array[CharacterBase]:
	var alive: Array[CharacterBase] = []
	for m in _members:
		if is_instance_valid(m) and m.is_alive and not m.is_downed:
			alive.append(m)
	return alive


func _get_downed_member() -> CharacterBase:
	for m in _members:
		if is_instance_valid(m) and m.is_downed:
			return m
	return null


func _get_closest_alive_member(pos: Vector3, exclude: Array[CharacterBase] = []) -> CharacterBase:
	var closest: CharacterBase = null
	var min_dist: float = INF
	for m in _get_alive_members():
		if m in exclude:
			continue
		var d: float = m.global_position.distance_to(pos)
		if d < min_dist:
			min_dist = d
			closest  = m
	return closest


func _clean_known_threats() -> void:
	for i in range(known_threats.size() - 1, -1, -1):
		var t: CharacterBase = known_threats[i]
		if not is_instance_valid(t) or not t.is_alive:
			known_threats.remove_at(i)


func _update_threat_level() -> void:
	var old: int = threat_level
	threat_level = clampi(known_threats.size(), 0, 4)
	if threat_level != old:
		threat_level_changed.emit(threat_level)


func _calculate_flank_position(target_pos: Vector3, flanker_pos: Vector3) -> Vector3:
	var perp: Vector3 = (target_pos - flanker_pos).cross(Vector3.UP).normalized()
	return target_pos + perp * _rng.randf_range(6.0, 12.0)


func _get_retreat_direction() -> Vector3:
	if _leader:
		return -_leader.global_basis.z
	return Vector3.BACK
