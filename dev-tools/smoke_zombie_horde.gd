extends "res://dev-tools/smoke_test_3d.gd"
## Just the bigger horde's checks (zombie mode, task Z4c): the adaptive alive cap, round sizes,
## the entrances all round the player, the ways in, the Richter 8.0 surge's logic.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_horde.gd
func _run() -> void:
	await _zombie_horde_checks(_gs())
