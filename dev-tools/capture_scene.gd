extends SceneTree
## Dev helper: renders a scene for a few frames and saves a screenshot.
##   godot --path . -s res://dev-tools/capture_scene.gd -- <scene> <out.png> [frames] [mode]
## `mode` is either "overview" (a high, wide shot of the whole room) or
## "closeup:NodeName" (frames that node from the front, for checking how a
## character actually reads rather than how the room does).
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[2]) if args.size() > 2 else 40
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
