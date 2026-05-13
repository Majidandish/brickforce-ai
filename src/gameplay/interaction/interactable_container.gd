## =============================================================================
## InteractableContainer — Loot Container (Crate, Box, Bag, Safe)
## =============================================================================
## Opens to reveal a list of loot items as individual pickups.
## State: closed → opening → open. One-shot.
## =============================================================================

class_name InteractableContainer
extends InteractableBase

@export var loot_items: Array[Dictionary] = []  # { item_id, quantity }
@export var open_animation: String        = "open"
@export var container_id: String          = ""

signal container_opened(container_id: String, opener_id: int)

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var _is_opened: bool = false


func _ready() -> void:
	super._ready()
	interact_type = InteractType.INSTANT
	prompt_text   = "Open"
	if container_id == "":
		container_id = "container_%d" % get_instance_id()
	one_shot = true


func can_interact(interactor: CharacterBase) -> bool:
	return not _is_opened and super.can_interact(interactor)


func _on_interact(interactor: CharacterBase) -> void:
	if _is_opened:
		return
	_is_opened = true

	if animation_player and animation_player.has_animation(open_animation):
		animation_player.play(open_animation)

	_spawn_loot()
	container_opened.emit(container_id, interactor.character_id)
	EventBus.container_opened.emit(container_id, interactor.character_id)
	Logger.info("InteractableContainer", "%s opened by %d" % [container_id, interactor.character_id])


func _spawn_loot() -> void:
	for item_data in loot_items:
		var pickup: InteractablePickup = InteractablePickup.new()
		pickup.item_id  = item_data.get("item_id", "")
		pickup.quantity = item_data.get("quantity", 1)
		var offset: Vector3 = Vector3(randf_range(-0.4, 0.4), 0.1, randf_range(-0.4, 0.4))
		get_parent().add_child(pickup)
		pickup.global_position = global_position + offset
