## =============================================================================
## ComponentSystem — ECS-Inspired Component Registry
## =============================================================================
## Purpose:
##   Lightweight component registry allowing entities to attach/detach
##   behaviours at runtime without deep inheritance chains.
##   Components are plain GDScript classes with a defined interface.
##   Bridges the gap between Godot's node tree and pure ECS patterns.
##
## Usage:
##   var health_comp = ComponentSystem.get_component(entity_id, "Health")
##   ComponentSystem.attach(entity_id, HealthComponent.new(entity))
## =============================================================================

extends Node

## component_name -> ComponentBase class
var _registry: Dictionary = {}

## entity_id -> { component_name -> ComponentBase instance }
var _entity_components: Dictionary = {}

signal component_attached(entity_id: int, component_name: String)
signal component_detached(entity_id: int, component_name: String)


func _ready() -> void:
	name = "ComponentSystem"
	Logger.info("ComponentSystem", "ECS component registry ready.")


func _process(delta: float) -> void:
	# Tick all active components.
	for entity_id in _entity_components:
		for comp_name in _entity_components[entity_id]:
			var comp: ComponentBase = _entity_components[entity_id][comp_name]
			if comp.is_active:
				comp.tick(delta)


# ── Public API ─────────────────────────────────────────────────────────────────

## Register a component class by name.
func register_component_type(name: String, comp_class: Script) -> void:
	_registry[name] = comp_class
	Logger.debug("ComponentSystem", "Component type registered: %s" % name)


## Attach a component instance to an entity.
func attach(entity_id: int, component: ComponentBase) -> void:
	if not _entity_components.has(entity_id):
		_entity_components[entity_id] = {}
	var comp_name: String = component.component_name
	if _entity_components[entity_id].has(comp_name):
		detach(entity_id, comp_name)
	_entity_components[entity_id][comp_name] = component
	component.on_attach()
	component_attached.emit(entity_id, comp_name)
	Logger.verbose("ComponentSystem", "Attached '%s' to entity %d." % [comp_name, entity_id])


## Detach a component from an entity.
func detach(entity_id: int, component_name: String) -> void:
	if not has_component(entity_id, component_name):
		return
	var comp: ComponentBase = _entity_components[entity_id][component_name]
	comp.on_detach()
	_entity_components[entity_id].erase(component_name)
	component_detached.emit(entity_id, component_name)


## Get a component instance from an entity. Returns null if not found.
func get_component(entity_id: int, component_name: String) -> ComponentBase:
	if not _entity_components.has(entity_id):
		return null
	return _entity_components[entity_id].get(component_name, null)


## Check if an entity has a component.
func has_component(entity_id: int, component_name: String) -> bool:
	return _entity_components.has(entity_id) and _entity_components[entity_id].has(component_name)


## Get all components for an entity.
func get_all_components(entity_id: int) -> Dictionary:
	return _entity_components.get(entity_id, {}).duplicate()


## Remove all components from an entity (call on entity death/unload).
func clear_entity(entity_id: int) -> void:
	if not _entity_components.has(entity_id):
		return
	for comp_name in _entity_components[entity_id]:
		_entity_components[entity_id][comp_name].on_detach()
	_entity_components.erase(entity_id)
	Logger.verbose("ComponentSystem", "Entity %d cleared from ECS." % entity_id)


## Query all entities that have a given component.
func query(component_name: String) -> Array[int]:
	var result: Array[int] = []
	for entity_id in _entity_components:
		if _entity_components[entity_id].has(component_name):
			result.append(entity_id)
	return result
