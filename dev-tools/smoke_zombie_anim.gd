extends "res://dev-tools/smoke_test_3d.gd"
## Just the zombie animation checks (task Z2a): the AnimationLibrary, every
## alias resolving, fallbacks when a clip is missing, feet planted.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_anim.gd
func _run() -> void:
	await _zombie_anim_checks(_gs())
