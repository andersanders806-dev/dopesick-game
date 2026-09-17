extends Area3D

## No single free-asset pack has all five of these specific props, so each
## id is mapped to the closest-shaped model from Kenney's Food Kit (CC0).
const MODELS := {
	"whiskey": preload("res://assets/kenney/food/wine-red.glb"),
	"cigs": preload("res://assets/kenney/food/candy-bar.glb"),
	"charger": preload("res://assets/kenney/food/bag.glb"),
	"batteries": preload("res://assets/kenney/food/can-small.glb"),
	"watch": preload("res://assets/kenney/food/soda-bottle.glb"),
}

@export var item_id: String = "whiskey"
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
		child.queue_free()
	if MODELS.has(id):
		model_root.add_child(MODELS[id].instantiate())

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
