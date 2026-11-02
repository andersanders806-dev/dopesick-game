extends "res://dev-tools/smoke_test_3d.gd"
## Just the Dead Block first-person feel checks (zombie mode, task Z4): aiming
## down the sights, recoil, hitmarker, slide, the viewmodel and its arms, every
## action's sound, and the horde-cost changes of step 0.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_fp.gd
func _run() -> void:
	await _zombie_fp_checks(_gs())
