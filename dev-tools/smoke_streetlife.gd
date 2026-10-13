extends "res://dev-tools/smoke_test_3d.gd"
## Just the street life checks.
func _run() -> void:
	await _street_life_checks(_gs())
