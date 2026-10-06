extends "res://dev-tools/smoke_test_3d.gd"
## Just the PS5 controller checks, for a fast loop while working on them.
## The full smoke test runs them too.
##   godot --headless --path . -s res://dev-tools/smoke_controller.gd

func _run() -> void:
	await _controller_checks(_gs())
