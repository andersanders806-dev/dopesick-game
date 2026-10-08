extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _one_load_at_a_time_checks()
