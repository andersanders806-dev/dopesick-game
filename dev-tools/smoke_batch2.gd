extends "res://dev-tools/smoke_test_3d.gd"
## Just batch 2's checks (the alley, bad batch, Tasha), for a fast loop
## while working on them. The full smoke test runs them too.
##   godot --headless --path . -s res://dev-tools/smoke_batch2.gd

func _run() -> void:
	await _batch2_checks(_gs())
