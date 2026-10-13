extends "res://dev-tools/smoke_test_3d.gd"
## Just the slot machine checks.
func _run() -> void:
	await _slot_checks(_gs())
