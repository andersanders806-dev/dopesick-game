extends "res://dev-tools/smoke_test_3d.gd"
## Just the first-person-only checks (SHIP 3): no view choice, a room entered looking into it, aim picks what E
## uses, people kept out of your face, hiding crouches the eyes, the kart race from the driver's seat.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_fp_only.gd
func _run() -> void:
	await _fp_only_checks(_gs())
