## =============================================================================
## StateDead — AI Dead State (Terminal)
## =============================================================================
## Behaviour: Disable all AI processing. Play death animation.
##   No transitions out (character is removed by MatchManager).
## =============================================================================

class_name StateDead
extends AIStateBase


func _init() -> void:
	state_name = "Dead"


func enter(data: Dictionary = {}) -> void:
	if not agent:
		return
	# Disable navigation and physics.
	if agent.nav_agent:
		agent.nav_agent.target_position = agent.global_position
	agent.set_physics_process(false)
	# Release any held cover.
	CoverSystem.release_cover(agent)
	Logger.verbose("StateDead", "Agent %d dead." % agent.character_id)
	# Schedule removal from scene.
	TimeManager.register_timer(
		"ai_death_cleanup_%d" % agent.character_id,
		8.0,
		func():
			if is_instance_valid(agent):
				agent.queue_free()
	)


func tick(_delta: float) -> void:
	pass  # Terminal state — no processing.
