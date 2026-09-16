extends "res://world/WorldRoot3D.gd"

const CAR_COLORS := [
	Color(0.55, 0.08, 0.07),
	Color(0.12, 0.2, 0.42),
	Color(0.18, 0.3, 0.16),
	Color(0.62, 0.5, 0.2),
	Color(0.75, 0.75, 0.72),
]

@onready var car_body: MeshInstance3D = $Car/Body

func _ready() -> void:
	super._ready()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CAR_COLORS.pick_random()
	mat.metallic = 0.4
	mat.roughness = 0.35
	car_body.material_override = mat
