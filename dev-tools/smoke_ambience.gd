extends "res://dev-tools/smoke_test_3d.gd"
## Just the place-ambience checks.
func _run() -> void:
	await _ambience_checks(_gs())
