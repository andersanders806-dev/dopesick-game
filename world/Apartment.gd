extends "res://world/WorldRoot.gd"

# Each layout is 6 top-left positions for the room's floor clutter, index-
# matched to `clutter` (TrashA, TrashB, ClothesPile, BottlesPile, Ashtray,
# PillBottle). Kept clear of the Bed, Phone, TV, and the door out. Wall
# stains stay put since they're painted onto a specific wall surface.
const CLUTTER_LAYOUTS := [
	[Vector2(200, 250), Vector2(260, 40), Vector2(150, 100), Vector2(320, 225), Vector2(108, 100), Vector2(122, 99)],
	[Vector2(60, 240), Vector2(300, 120), Vector2(350, 180), Vector2(170, 230), Vector2(280, 60), Vector2(300, 62)],
	[Vector2(350, 60), Vector2(60, 180), Vector2(280, 220), Vector2(60, 100), Vector2(200, 230), Vector2(214, 230)],
]

@onready var clutter: Array = [$TrashA, $TrashB, $ClothesPile, $BottlesPile, $Ashtray, $PillBottle]

func _ready() -> void:
	_randomize_clutter()
	super._ready()

func _randomize_clutter() -> void:
	var layout: Array = CLUTTER_LAYOUTS.pick_random()
	for i in range(clutter.size()):
		clutter[i].position = layout[i]
