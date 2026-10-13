extends "res://dev-tools/smoke_test_3d.gd"
## Just the survival checks.
func _run() -> void:
	await _survival_checks(_gs())
