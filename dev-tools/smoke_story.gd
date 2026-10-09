extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	await _story_checks(_gs())
	await _story_review_checks(_gs())
