extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _gameplay3_checks(_gs())
