extends "res://dev-tools/smoke_test_3d.gd"
## Just the camp checks.
func _run() -> void:
	await _camp_checks(_gs())
