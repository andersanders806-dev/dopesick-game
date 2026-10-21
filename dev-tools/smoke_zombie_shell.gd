extends "res://dev-tools/smoke_test_3d.gd"
## Just the Dead Block shell checks (zombie mode, task Z1): rounds, points,
## the zombie block, the game-over screen, the title entry, and the story
## left byte-identical.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_shell.gd
func _run() -> void:
	await _zombie_shell_checks(_gs())
