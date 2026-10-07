extends "res://dev-tools/smoke_test_3d.gd"
## Just the cutscene video checks.
func _run() -> void:
	await _cutscene_video_checks()
