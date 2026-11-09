extends Area3D

const ItemModels := preload("res://items/ItemModels.gd")

@export var item_id: String = "cigs"
@export var theft_window: float = 1.0

## How far through the pick-up animation the item actually leaves the shelf
## (the hand reaches it about halfway).
const GRAB_POINT := 0.5

@onready var model_root: Node3D = $ModelRoot

## How loud it is when something slips out of shaking hands and hits the floor (m).
const DROP_NOISE_M := 7.0
var _layer := 0
var dropped := false

func _ready() -> void:
	add_to_group("interactable")
	_layer = collision_layer
	set_item_id(item_id)

func set_item_id(id: String) -> void:
	item_id = id
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	model_root.add_child(ItemModels.build(id))

func interact(player: Node) -> void:
	# Shaking hands (player/Player3D.gd): the grab can go wrong, and then nothing is taken.
	var fumbled: bool = player.has_method("roll_fumble") and player.roll_fumble()
	# Take it out of play immediately so it can't be stolen twice while the
	# grab animation is still reaching for it.
	remove_from_group("interactable")
	set_deferred("collision_layer", 0)
	SFX.play("steal")
	if fumbled:
		await _fumble(player)
		return
	GameState.steal_item(item_id)
	if player.has_method("begin_theft_window"):
		player.begin_theft_window(theft_window)
	var grab_delay := 0.0
	if player.has_method("play_pickup"):
		grab_delay = player.play_pickup(global_position) * GRAB_POINT
	if grab_delay > 0.0:
		await get_tree().create_timer(grab_delay).timeout
	queue_free()

## The hand opens and it falls: out of the grab, down to the floor with a clatter that carries (a
## noise for the guards), and there to be picked up again.
func _fumble(player: Node) -> void:
	if player.has_method("begin_theft_window"):
		player.begin_theft_window(theft_window)
	var grab_delay := 0.0
	if player.has_method("play_pickup"):
		grab_delay = player.play_pickup(global_position) * GRAB_POINT
	if grab_delay > 0.0:
		await get_tree().create_timer(grab_delay).timeout
	if not is_inside_tree():
		return
	var hands: Node = player.get("story_hands")
	if hands != null:
		hands.fumble()
	if player.has_method("kick"):
		player.kick(0.35)
	# Slips toward the player's side of the shelf, not through it, and falls to the floor they stand on.
	var toward: Vector3 = (player.global_position - global_position)
	toward.y = 0.0
	var land := global_position + toward.normalized() * 0.35
	var floor_y: float = player.global_position.y + 0.06
	land.y = floor_y
	var tw := create_tween()
	tw.tween_property(self, "global_position:x", land.x, 0.32)
	tw.parallel().tween_property(self, "global_position:z", land.z, 0.32)
	tw.parallel().tween_property(self, "global_position:y", floor_y, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model_root, "rotation_degrees:x", 80.0, 0.32)
	await tw.finished
	if not is_inside_tree():
		return
	SFX.play_at("drop", global_position, -5.0, randf_range(0.9, 1.15))
	GameState.emit_noise(global_position, DROP_NOISE_M, "drop")
	dropped = true
	collision_layer = _layer
	add_to_group("interactable")
