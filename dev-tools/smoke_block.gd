extends "res://dev-tools/smoke_test_3d.gd"
## Just the block checks (open world, task 1), in a fresh process: the
## first-load check only means something before anything else has loaded.
func _run() -> void:
	await _block_cold_load_checks(_gs())
	await _block_layout_checks(_gs())
