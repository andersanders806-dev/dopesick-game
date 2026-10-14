extends "res://dev-tools/smoke_test_3d.gd"
## Just the fight checks.
func _run() -> void:
	await _fight_checks(_gs())
