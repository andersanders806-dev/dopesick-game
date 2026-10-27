extends "res://dev-tools/smoke_test_3d.gd"
## Just the Dead Block weapon checks (zombie mode, task Z3): damage by part,
## ammo and reload, points, wall-buys, the mystery box, the upgrade machine, the
## ammo HUD. Zombies are dev-tools/test_zombie_double.gd, so this runs without
## the real ones.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_weapons.gd
func _run() -> void:
	await _zombie_weapons_checks(_gs())
