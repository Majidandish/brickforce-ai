## =============================================================================
## SquadManager — Squad Formation, Role Assignment & Coordination
## =============================================================================
## Purpose:
##   Creates and manages squads of characters. Assigns tactical roles
##   (leader, flanker, support, sniper). Provides the API for issuing squad
##   commands that the AI Commander translates into individual behaviours.
## =============================================================================

extends Node

const MAX_SQUAD_SIZE: int = 4

enum SquadRole { LEADER, ASSAULT, SUPPORT, FLANKER, SNIPER, MEDIC }

const ROLE_NAMES: Dictionary = {
	SquadRole.LEADER:  "LEADER",
	SquadRole.ASSAULT: "ASSAULT",
	SquadRole.SUPPORT: "SUPPORT",
	SquadRole.FLANKER: "FLANKER",
	SquadRole.SNIPER:  "SNIPER",
	SquadRole.MEDIC:   "MEDIC",
}

signal squad_formed(squad: Dictionary)
signal squad_dissolved(squad_id: int)
signal command_issued(squad_id: int, command: String, data: Dictionary)

# squad_id -> {
#   id, members: [{ character, role }], leader_id, formation, objective
# }
var _squads: Dictionary = {}
var _next_squad_id: int = 0


func _ready() -> void:
	name = "SquadManager"
	Logger.info("SquadManager", "Initialized.")


# ── Public API ─────────────────────────────────────────────────────────────────

## Create a new squad from a list of CharacterBase nodes.
func form_squad(members: Array[CharacterBase]) -> int:
	if members.is_empty():
		Logger.warn("SquadManager", "Cannot form squad: no members.")
		return -1

	var id: int = _next_squad_id
	_next_squad_id += 1

	var member_data: Array[Dictionary] = []
	for i in members.size():
		var role: SquadRole = _assign_role(i, members[i])
		member_data.append({ "character": members[i], "role": role })

	var squad: Dictionary = {
		"id":        id,
		"members":   member_data,
		"leader_id": members[0].character_id,
		"formation": "wedge",
		"objective": "roam",
		"objective_data": {},
	}

	_squads[id] = squad
	squad_formed.emit(squad)
	EventBus.squad_formed.emit(id, members.map(func(m): return m.character_id))
	Logger.info("SquadManager", "Squad %d formed (%d members)." % [id, members.size()])
	return id


## Dissolve a squad.
func dissolve_squad(squad_id: int) -> void:
	if not _squads.has(squad_id):
		return
	_squads.erase(squad_id)
	squad_dissolved.emit(squad_id)
	EventBus.squad_dissolved.emit(squad_id)
	Logger.info("SquadManager", "Squad %d dissolved." % squad_id)


## Issue a tactical command to a squad.
## Commands: "attack", "defend", "retreat", "flank", "revive", "hold", "move_to"
func issue_command(squad_id: int, command: String, data: Dictionary = {}) -> void:
	if not _squads.has(squad_id):
		Logger.warn("SquadManager", "Unknown squad: %d" % squad_id)
		return
	_squads[squad_id].objective      = command
	_squads[squad_id].objective_data = data
	command_issued.emit(squad_id, command, data)
	EventBus.squad_command_issued.emit(squad_id, command, data)
	Logger.debug("SquadManager", "Squad %d command: %s %s" % [squad_id, command, JSON.stringify(data)])


## Get formation positions for squad members relative to leader.
func get_formation_positions(squad_id: int) -> Array[Vector3]:
	if not _squads.has(squad_id):
		return []
	var squad: Dictionary = _squads[squad_id]
	return _calculate_formation(squad.formation, squad.members.size())


## Add a member to an existing squad.
func add_member(squad_id: int, character: CharacterBase) -> bool:
	if not _squads.has(squad_id):
		return false
	var squad: Dictionary = _squads[squad_id]
	if squad.members.size() >= MAX_SQUAD_SIZE:
		return false
	var role: SquadRole = _assign_role(squad.members.size(), character)
	squad.members.append({ "character": character, "role": role })
	EventBus.squad_member_added.emit(squad_id, character.character_id)
	return true


## Remove a member from a squad.
func remove_member(squad_id: int, character_id: int) -> void:
	if not _squads.has(squad_id):
		return
	var squad: Dictionary = _squads[squad_id]
	for i in range(squad.members.size() - 1, -1, -1):
		if squad.members[i].character.character_id == character_id:
			squad.members.remove_at(i)
			EventBus.squad_member_removed.emit(squad_id, character_id)
			break
	if squad.members.is_empty():
		dissolve_squad(squad_id)
	elif squad.leader_id == character_id and not squad.members.is_empty():
		squad.leader_id = squad.members[0].character.character_id


## Get all squads.
func get_all_squads() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _squads:
		result.append(_squads[id])
	return result


## Get a squad by ID.
func get_squad(squad_id: int) -> Dictionary:
	return _squads.get(squad_id, {})


## Find which squad a character belongs to.
func get_squad_of(character_id: int) -> int:
	for squad_id in _squads:
		for m in _squads[squad_id].members:
			if m.character.character_id == character_id:
				return squad_id
	return -1


# ── Internal ───────────────────────────────────────────────────────────────────

func _assign_role(index: int, character: CharacterBase) -> SquadRole:
	# Role assignment based on index and character data personality.
	if index == 0:
		return SquadRole.LEADER
	if character.character_data:
		match character.character_data.ai_personality:
			5: return SquadRole.SNIPER    # "Sniper" personality
			6: return SquadRole.MEDIC     # "Support" personality
			4: return SquadRole.FLANKER   # "Flanker" personality
	match index:
		1: return SquadRole.ASSAULT
		2: return SquadRole.FLANKER
		3: return SquadRole.SUPPORT
	return SquadRole.ASSAULT


func _calculate_formation(formation: String, member_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	match formation:
		"wedge":
			positions = [Vector3.ZERO, Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(0, 0, -4)]
		"line":
			for i in member_count:
				positions.append(Vector3((i - member_count / 2.0) * 2.0, 0, 0))
		"column":
			for i in member_count:
				positions.append(Vector3(0, 0, -i * 2.0))
		"diamond":
			positions = [Vector3(0, 0, 2), Vector3(-2, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, -2)]
		"spread":
			for i in member_count:
				var angle: float = (TAU / member_count) * i
				positions.append(Vector3(cos(angle) * 4.0, 0, sin(angle) * 4.0))
	return positions.slice(0, member_count)
