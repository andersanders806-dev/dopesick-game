extends "res://world/WorldRoot3D.gd"

# Each layout is 5 floor spots (x, z), index-matched to `clutter` (Trashcan,
# BoxOpen, BoxClosed, BottleA, BottleB). Kept clear of the bed, phone table,
# TV, and the door out. Purely decorative -- none of these have collision,
# so moving them never affects the navmesh.
const CLUTTER_LAYOUTS := [
	[Vector2(-4.5, 0.6), Vector2(1.6, -3.3), Vector2(2.4, -3.3), Vector2(0.9, 2.6), Vector2(1.4, 2.9)],
	[Vector2(-4.5, 2.2), Vector2(-1.2, -3.2), Vector2(-4.4, 0.8), Vector2(3.2, 2.7), Vector2(3.6, 2.4)],
	[Vector2(0.4, -3.2), Vector2(-4.4, 1.2), Vector2(-3.8, 2.8), Vector2(-0.6, 0.9), Vector2(2.2, 2.8)],
]

@onready var clutter: Array = [$Trashcan, $BoxOpen, $BoxClosed, $BottleA, $BottleB]

func _ready() -> void:
	_randomize_clutter()
	super._ready()

func _randomize_clutter() -> void:
	var layout: Array = CLUTTER_LAYOUTS.pick_random()
	for i in range(clutter.size()):
		var spot: Vector2 = layout[i]
		clutter[i].position.x = spot.x
		clutter[i].position.z = spot.y
