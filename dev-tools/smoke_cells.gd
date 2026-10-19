extends "res://dev-tools/smoke_test_3d.gd"
## Just the cell checks (open world, task 2): sleep and wake, lights, the
## cutaway walls, occluders and MultiMesh props.
func _run() -> void:
	# Every switch's cost in the log.
	Engine.set_meta("cell_log", true)
	await _block_cells_checks(_gs())
