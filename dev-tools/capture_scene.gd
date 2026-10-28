extends SceneTree
## Dev helper: renders a scene for a few frames and saves a screenshot.
##   godot --path . -s res://dev-tools/capture_scene.gd -- <scene> <out.png> [frames] [mode] [hour]
## `mode` is either "overview" (a high, wide shot of the whole room),
## "closeup:NodeName" (frames that node from the front, for checking how a
## character actually reads rather than how the room does),
## "player:x,z" (stands the player there and shoots through their own
## camera -- what you see walking the block), or "aerial:x,z,height" (a
## steep shot down over a part of the block). `hour` sets the clock (0-23)
## before the scene loads, so the same spot can be checked by day and night.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[2]) if args.size() > 2 else 40
	await process_frame
	# A look at the level, not at withdrawal: no shaking, no blur.
	root.get_node("GameState").no_sickness = true
	if args.size() > 4:
		# A sandboxed run: don't save over the player's game.
		Engine.set_meta("sandbox", true)
		await process_frame
		# The game's own camera, whatever settings.cfg says.
		root.get_node("Graphics").set_first_person(false)
		var gs := root.get_node("GameState")
		gs.clock_running = false
		gs.clock = int(args[4]) * 60
	change_scene_to_file(args[0])
	for i in frames:
		await process_frame
	var mode := args[3] if args.size() > 3 else ""
	if mode == "overview":
		_place_camera(Vector3(0, 11, 7.5), Vector3(-55, 0, 0), 60.0)
	elif mode.begins_with("closeup:"):
		var target := current_scene.find_child(mode.split(":")[1], true, false) as Node3D
		if target:
			var p: Vector3 = target.global_position
			_place_camera(p + Vector3(0, 1.4, 2.6), Vector3(-14, 0, 0), 45.0)
	elif mode.begins_with("player:"):
		var xz := mode.split(":")[1].split(",")
		var player := get_first_node_in_group("player") as Node3D
		player.global_position = Vector3(float(xz[0]), 0, float(xz[1]))
		player.reset_physics_interpolation()
		for i in 30:
			await process_frame
	elif mode.begins_with("aerial:"):
		var v := mode.split(":")[1].split(",")
		_place_camera(Vector3(float(v[0]), float(v[2]), float(v[1]) + float(v[2]) * 0.55), Vector3(-62, 0, 0), 55.0)
	if mode != "":
		for i in 5:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	quit()

func _place_camera(pos: Vector3, rot_deg: Vector3, fov: float) -> void:
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.global_position = pos
	cam.rotation_degrees = rot_deg
	cam.fov = fov
	cam.current = true
