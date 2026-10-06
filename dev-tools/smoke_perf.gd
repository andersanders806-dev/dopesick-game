extends "res://dev-tools/smoke_test_3d.gd"
## Just the performance checks.
func _run() -> void:
	await _perf_checks(_gs())
