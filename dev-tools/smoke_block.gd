extends "res://dev-tools/smoke_test_3d.gd"
## Just the block layout checks (open world, task 1).
func _run() -> void:
	await _block_layout_checks(_gs())
