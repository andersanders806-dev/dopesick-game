extends "res://dev-tools/smoke_test_3d.gd"
## Just the car checks (task C): the real models, old paint, wheels that
## turn, parked cars, and the wrecks in Dead Block.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_cars.gd
func _run() -> void:
	await _car_checks(_gs())
