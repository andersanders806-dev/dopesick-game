extends "res://dev-tools/smoke_test_3d.gd"
## Just the shoulder camera checks (harbour Task H1).
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_camera.gd
func _run() -> void:
	await _camera_checks(_gs())
