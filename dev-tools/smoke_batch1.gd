extends "res://dev-tools/smoke_test_3d.gd"
## Just batch 1's checks (belongings, pawn tickets, rent, court), for a fast
## loop while working on them. The full smoke test runs them too.
##   godot --headless --path . -s res://dev-tools/smoke_batch1.gd

func _run() -> void:
	await _batch1_checks(_gs())
