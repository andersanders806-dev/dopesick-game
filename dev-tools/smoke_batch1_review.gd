extends "res://dev-tools/smoke_test_3d.gd"
## Just the batch 1 review fixes, for a fast loop.
func _run() -> void:
	await _batch1_review_checks(_gs())
