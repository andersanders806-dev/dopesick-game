extends "res://world/WorldRoot3D.gd"

# Each layout is 6 floor spots (x, z), index-matched to `clutter`. Kept clear
# of the mattress, couch, phone crate, TV, both spawn points, and the door.
# The chair and box stack have collision; that's fine to move because this
# runs before WorldRoot3D bakes the navmesh.
const CLUTTER_LAYOUTS := [
	[Vector2(1.2, 1.0), Vector2(2.6, -3.0), Vector2(-2.8, -2.8), Vector2(0.5, 2.6), Vector2(-2.6, 2.9), Vector2(-3.1, -0.4)],
	[Vector2(-0.3, 2.2), Vector2(1.0, -3.0), Vector2(2.8, 2.6), Vector2(-2.6, -2.9), Vector2(1.8, 0.4), Vector2(-3.0, 0.0)],
	[Vector2(2.4, 1.9), Vector2(-2.8, -3.0), Vector2(0.6, -2.7), Vector2(-2.0, 2.6), Vector2(3.4, 2.9), Vector2(0.8, 1.0)],
]

const BULB_ENERGY := 1.8

@onready var clutter: Array = [$ChairOverturned, $BoxStack, $TrashA, $TrashB, $TrashC, $ClothesPile]
@onready var bulb_light: OmniLight3D = $BareBulb/Light
@onready var bulb_buzz: AudioStreamPlayer3D = $BareBulb/Buzz
@onready var bulb_crackle: AudioStreamPlayer3D = $BareBulb/Crackle

var _buzz_db: float

var _flicker_timer: float = 0.0

func _ready() -> void:
	_randomize_clutter()
	super._ready()
	_buzz_db = bulb_buzz.volume_db

func _randomize_clutter() -> void:
	var layout: Array = CLUTTER_LAYOUTS.pick_random()
	for i in range(clutter.size()):
		var spot: Vector2 = layout[i]
		clutter[i].position.x = spot.x
		clutter[i].position.z = spot.y

## The bare bulb mostly holds steady, then every so often browns out for a
## split second, like it's on bad wiring.
func _process(delta: float) -> void:
	_flicker_timer -= delta
	if _flicker_timer > 0.0:
		return
	if randf() < 0.15:
		bulb_light.light_energy = BULB_ENERGY * randf_range(0.2, 0.55)
		bulb_buzz.volume_db = _buzz_db - 12.0
		bulb_crackle.pitch_scale = randf_range(0.8, 1.2)
		bulb_crackle.play()
		_flicker_timer = randf_range(0.04, 0.12)
	else:
		bulb_light.light_energy = BULB_ENERGY
		bulb_buzz.volume_db = _buzz_db
		_flicker_timer = randf_range(0.3, 2.0)
