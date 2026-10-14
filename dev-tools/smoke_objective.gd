extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _objective_checks(_gs())
