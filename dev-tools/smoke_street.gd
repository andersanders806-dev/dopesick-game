extends "res://dev-tools/smoke_test_3d.gd"
## Just the street checks.
func _run() -> void:
	await _street_checks(_gs())
