extends "res://world/WorldRoot3D.gd"

const ITEM_IDS := ["whiskey", "cigs", "charger", "batteries", "watch"]

# Each layout is 5 shelf-unit centers on the floor plane (x, z), index-matched
# to `shelves` / `item_slots` (ShelfA..E). Converted from Shop.gd's 2D layouts
# (40px per metre, nudged south so there's a walkway in front of the counter).
# Each item sits just in front of its shelf, so only the shelf spot is picked.
const SHELF_LAYOUTS := [
	[Vector2(-3.25, -0.2), Vector2(0.0, -0.2), Vector2(3.25, -0.2), Vector2(-1.75, 1.8), Vector2(1.75, 1.8)],
	[Vector2(-4.25, -0.95), Vector2(-0.6, -0.95), Vector2(2.9, -0.95), Vector2(-2.5, 1.55), Vector2(1.25, 1.55)],
	[Vector2(-3.5, -0.7), Vector2(1.5, -0.7), Vector2(-1.0, 0.8), Vector2(-3.5, 2.1), Vector2(1.5, 2.1)],
]
const ITEM_OFFSET := Vector3(0.0, 0.45, 0.5)

@onready var shopkeeper: Node3D = $Shopkeeper
@onready var police_spawn: Marker3D = $PoliceSpawn
@onready var item_slots: Array = [$ItemA, $ItemB, $ItemC, $ItemD, $ItemE]
@onready var shelves: Array = [$ShelfA, $ShelfB, $ShelfC, $ShelfD, $ShelfE]

func _ready() -> void:
	_randomize_layout()
	super._ready()
	shopkeeper.spotted_theft.connect(_on_spotted_theft)
	_shuffle_items()

func _randomize_layout() -> void:
	var layout: Array = SHELF_LAYOUTS.pick_random()
	for i in range(shelves.size()):
		var slot: Vector2 = layout[i]
		var pos := Vector3(slot.x, 0.0, slot.y)
		shelves[i].position = pos
		item_slots[i].position = pos + ITEM_OFFSET

func _shuffle_items() -> void:
	var ids := ITEM_IDS.duplicate()
	ids.shuffle()
	for i in range(item_slots.size()):
		item_slots[i].set_item_id(ids[i])

func _on_spotted_theft() -> void:
	if GameState.wanted:
		return
	var police := PoliceScene.instantiate()
	add_child(police)
	police.global_position = police_spawn.global_position
