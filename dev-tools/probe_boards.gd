extends SceneTree
## Dev helper (SHIP 16 B2 fix 1, I3): for every wall board of Dead Block, how many of its nine points are hidden from a
## metre in front; and, along a line (`--line=x0,z0,dx,dz,n` start, ray direction, steps of 1 m), where a board would be
## clear. Headless is fine:
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/probe_boards.gd -- --line=-80,-3,0,-1,160
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	root.get_node("ZombieMode").begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	for b in block.wall_buys:
		print("BOARD ", b.data.id, " hidden=", block.board_hidden_points(b.global_transform), " at ", b.global_position)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--line="):
			var v := a.substr(7).split(",")
			var o := Vector3(float(v[0]), 1.3, float(v[1]))
			var dir := Vector3(float(v[2]), 0.0, float(v[3]))
			var step := Vector3(dir.z, 0.0, -dir.x).abs() if false else Vector3(abs(dir.z), 0.0, abs(dir.x))
			var run := ""
			for i in int(v[4]):
				var from := o + step * float(i)
				var t: Transform3D = block._snap(from, dir, block.WALL_GAP)
				var hit: bool = (t.origin - from).length() < 13.0
				var n: int = block.board_hidden_points(t) if hit else 99
				print("LINE ", from, " -> ", t.origin, " hidden=", n)
	quit()
