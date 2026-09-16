extends SceneTree
## Dev helper: renders a scene for a few frames and saves a screenshot.
##   godot --path . -s res://dev-tools/capture_scene.gd -- <scene> <out.png> [frames]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[2]) if args.size() > 2 else 40
	change_scene_to_file(args[0])
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	quit()
