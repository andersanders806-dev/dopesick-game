extends "res://dev-tools/smoke_test_3d.gd"
## Just the dead's checks (zombie mode, task Z2b): spawning and caps, the hit
## zones, the navmesh, barricades.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_dead.gd
func _run() -> void:
	await _zombie_dead_checks(_gs())
