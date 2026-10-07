extends "res://dev-tools/smoke_test_3d.gd"
## Just the chapter 2 polish checks.
func _run() -> void:
	await _polish_checks(_gs())
