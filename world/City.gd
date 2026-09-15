extends "res://world/WorldRoot.gd"

const CAR_TINTS := [
	Color(1, 1, 1, 1),
	Color(0.55, 0.75, 1.1, 1),
	Color(0.65, 1.05, 0.6, 1),
	Color(1.1, 0.85, 0.4, 1),
]

@onready var car: TextureRect = $Car

func _ready() -> void:
	super._ready()
	car.self_modulate = CAR_TINTS[randi() % CAR_TINTS.size()]
