extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _lean_checks(_gs())
	await _low_checks(_gs())
	_scaler_checks()
