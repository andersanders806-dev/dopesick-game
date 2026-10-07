extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _lean_checks(_gs())
	_step_down_checks()
