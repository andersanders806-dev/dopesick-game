extends "res://dev-tools/smoke_test_3d.gd"
## Just the schedule checks (open world, task 4): people with somewhere to
## be, passers-by, the beat cop's loop, the pusher's two posts.
func _run() -> void:
	await _schedules_checks(_gs())
