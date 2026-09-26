extends SceneTree
## Dev helper: first-person screenshots, for checking how the viewmodel,
## HUD and menus actually look (headless tests can't).
##   godot --path . -s res://dev-tools/capture_fps.gd -- <scene> <out.png> [mode]
## `mode`: "idle" (default), "fire" (mid-burst, muzzle flash up), "ads"
## (aimed down the sights), or "menu" (just render the scene as-is).
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[2] if args.size() > 2 else "idle"
	# The capture window may take keyboard focus from whatever else is
	# running; it must not act on (or grab) any of that input.
	root.gui_disable_input = true
	change_scene_to_file(args[0])
	# The scene swap lands a frame or two later; wait for the new player.
	var p: Node = null
	for i in 10:
		await process_frame
		p = get_first_node_in_group("player")
		if p:
			break
	if p:
		p.capture_mouse = false
		p.set_process_unhandled_input(false)
	for i in 30:
		await process_frame
	if p and mode != "menu":
		# Look across the room at about chest height.
		p.global_position = Vector3(0, 0, 1.5)
		p.set_look(0.0, -0.05)
		p.flashlight.visible = true
		if mode == "ads":
			p.weapon.force_aim = true
		for i in 30:
			await process_frame
		if mode == "fire":
			Input.action_press("fire")
			for i in 7:
				await physics_frame
			await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1])
	Input.action_release("fire")
	Input.action_release("aim")
	quit()
