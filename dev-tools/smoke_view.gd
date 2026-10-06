extends "res://dev-tools/smoke_test_3d.gd"
## Just the first/third person checks, for a fast loop while working on them.
## The full smoke test runs them too.
##   godot --headless --path . -s res://dev-tools/smoke_view.gd

func _run() -> void:
	await _view_checks(_gs())
