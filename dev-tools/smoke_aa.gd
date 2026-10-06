extends "res://dev-tools/smoke_test_3d.gd"
## Just the anti-aliasing checks.
func _run() -> void:
	await _aa_checks(_gs())
