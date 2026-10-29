extends "res://dev-tools/smoke_test_3d.gd"
## Just the walk-in shop checks (open world, task 3).
func _run() -> void:
	await _walk_in_checks(_gs())
