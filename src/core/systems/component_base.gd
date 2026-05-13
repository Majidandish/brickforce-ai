## =============================================================================
## ComponentBase — Abstract Base for ECS Components
## =============================================================================
## Purpose:
##   All gameplay components extend this. Provides a unified interface for
##   attach/detach lifecycle, tick, and entity reference.
## =============================================================================

class_name ComponentBase
extends RefCounted

## Unique component type name (e.g. "Health", "Stamina", "Stealth").
var component_name: String = "Unnamed"
## Whether this component ticks each frame.
var is_active: bool = true
## Reference to the owning entity node.
var entity: Node = null


## Called when attached to an entity.
func on_attach() -> void:
	pass


## Called when detached or entity cleared.
func on_detach() -> void:
	pass


## Called every frame while is_active = true.
func tick(_delta: float) -> void:
	pass
