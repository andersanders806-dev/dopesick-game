extends "res://dev-tools/smoke_test_3d.gd"
## Just the world-art checks.
func _run() -> void:
	await _world_art_checks(_gs())
