extends Area3D

const ItemModels := preload("res://items/ItemModels.gd")

@export var item_id: String = "cigs"
@export var theft_window: float = 1.0

## How far through the pick-up animation the item actually leaves the shelf
## (the hand reaches it about halfway).
const GRAB_POINT := 0.5

@onready var model_root: Node3D = $ModelRoot

func _ready() -> void:
	add_to_group("interactable")
	set_item_id(item_id)

func set_item_id(id: String) -> void:
	item_id = id
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	model_root.add_child(ItemModels.build(id))

func interact(player: Node) -> void:
	# Take it out of play immediately so it can't be stolen twice while the
	# grab animation is still reaching for it.
	remove_from_group("interactable")
	set_deferred("collision_layer", 0)
	SFX.play("steal")
	GameState.steal_item(item_id)
	if player.has_method("begin_theft_window"):
		player.begin_theft_window(theft_window)
	var grab_delay := 0.0
	if player.has_method("play_pickup"):
		grab_delay = player.play_pickup(global_position) * GRAB_POINT
	if grab_delay > 0.0:
		await get_tree().create_timer(grab_delay).timeout
	queue_free()
