extends "res://dev-tools/smoke_test_3d.gd"
## Just the cast checks.
func _run() -> void:
	await _cast_checks(_gs())
