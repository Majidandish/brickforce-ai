## =============================================================================
## InteractablePickup — World Pickup Item
## =============================================================================
## Represents a physical item in the world that can be picked up.
## Used for ground loot, ammo, and consumables.
## =============================================================================

class_name InteractablePickup
extends InteractableBase

@export var item_id: String      = ""
@export var quantity: int        = 1
@export var auto_pickup: bool    = false  # If true, picks up on touch.
@export var highlight_mesh: MeshInstance3D = null

signal picked_up(item_id: String, quantity: int, character: CharacterBase)

var _bobble_time: float = 0.0
const BOBBLE_SPEED: float = 1.5
const BOBBLE_HEIGHT: float = 0.08
const ROTATE_SPEED: float  = 0.8


func _ready() -> void:
	super._ready()
	interact_type = InteractType.INSTANT
	prompt_text   = "Pick Up"
	if item_id != "":
		prompt_text = "Pick Up %s" % item_id.replace("_", " ").capitalize()


func _process(delta: float) -> void:
	# Bobbing animation.
	_bobble_time += delta
	position.y = sin(_bobble_time * BOBBLE_SPEED) * BOBBLE_HEIGHT
	rotation.y += ROTATE_SPEED * delta


func _on_interact(interactor: CharacterBase) -> void:
	if item_id == "":
		return
	# Add to match inventory.
	var inventory: MatchInventory = interactor.find_child("MatchInventory", false, false)
	if inventory:
		var accepted: int = inventory.add_item(item_id, quantity)
		if accepted > 0:
			picked_up.emit(item_id, accepted, interactor)
			EventBus.item_picked_up.emit(interactor.character_id, item_id, accepted)
			queue_free()
	else:
		Logger.warn("InteractablePickup", "Character has no MatchInventory: %s" % interactor.name)


func can_interact(interactor: CharacterBase) -> bool:
	if not super.can_interact(interactor):
		return false
	# Check if character can carry the item.
	var inventory: MatchInventory = interactor.find_child("MatchInventory", false, false)
	if not inventory:
		return false
	return inventory.can_add(item_id, quantity)


## Spawn a pickup at a world position from item_id + quantity.
static func spawn_at(pos: Vector3, item: String, qty: int, parent: Node) -> InteractablePickup:
	var pickup: InteractablePickup = InteractablePickup.new()
	pickup.item_id  = item
	pickup.quantity = qty
	parent.add_child(pickup)
	pickup.global_position = pos
	return pickup
