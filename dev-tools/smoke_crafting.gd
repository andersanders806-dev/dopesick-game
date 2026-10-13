extends "res://dev-tools/smoke_test_3d.gd"
## Just the crafting checks.
func _run() -> void:
	await _crafting_checks(_gs())
