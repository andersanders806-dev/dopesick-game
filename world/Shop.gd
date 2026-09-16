extends "res://world/WorldRoot.gd"

const ITEM_IDS := ["whiskey", "cigs", "charger", "batteries", "watch"]

# Each layout is 5 shelf center positions, index-matched to `shelves` /
# `item_slots` (ShelfA..E). Item markers sit 9px above their shelf and the
# flanking product boxes 15px above, offset ±(33/23)px, in every layout —
# same relative offsets the original hand-placed scene used — so only the
# shelf position needs to be chosen per layout.
const SHELF_LAYOUTS := [
	[Vector2(110, 140), Vector2(240, 140), Vector2(370, 140), Vector2(170, 220), Vector2(310, 220)],
	[Vector2(70, 110), Vector2(215, 110), Vector2(345, 110), Vector2(140, 210), Vector2(290, 210)],
	[Vector2(100, 120), Vector2(300, 120), Vector2(200, 180), Vector2(100, 230), Vector2(300, 230)],
]

@onready var shopkeeper: Node2D = $Shopkeeper
@onready var police_spawn: Marker2D = $PoliceSpawn
@onready var item_slots: Array = [$ItemWhiskey, $ItemCigs, $ItemCharger, $ItemBatteries, $ItemWatch]
@onready var shelves: Array = [$ShelfA, $ShelfB, $ShelfC, $ShelfD, $ShelfE]
@onready var box_pairs := {0: [$BoxA1, $BoxA2], 2: [$BoxC1, $BoxC2], 4: [$BoxE1, $BoxE2]}

func _ready() -> void:
	_randomize_layout()
	super._ready()
	shopkeeper.spotted_theft.connect(_on_spotted_theft)
	_shuffle_items()

func _randomize_layout() -> void:
	var layout: Array = SHELF_LAYOUTS.pick_random()
	for i in range(shelves.size()):
		var slot: Vector2 = layout[i]
		shelves[i].position = slot
		item_slots[i].position = slot + Vector2(0, -9)
		if box_pairs.has(i):
			var boxes: Array = box_pairs[i]
			boxes[0].position = slot + Vector2(-33, -15)
			boxes[1].position = slot + Vector2(23, -15)

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
