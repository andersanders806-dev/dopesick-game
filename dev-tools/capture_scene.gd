extends SceneTree
## Dev helper: renders a scene for a few frames and saves a screenshot.
##   godot --path . -s res://dev-tools/capture_scene.gd -- <scene> <out.png> [frames] [overview]
## Pass "overview" as the 4th arg to swap the follow camera for a high, wide
## shot of the whole room.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[2]) if args.size() > 2 else 40
	change_scene_to_file(args[0])
	for i in frames:
		await process_frame
	if args.size() > 3 and args[3] == "overview":
		var cam := Camera3D.new()
		current_scene.add_child(cam)
		cam.position = Vector3(0, 11, 7.5)
		cam.rotation_degrees = Vector3(-55, 0, 0)
		cam.fov = 60.0
		cam.current = true
		for i in 5:
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	quit()
