extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _smooth_quick_checks(_gs())
