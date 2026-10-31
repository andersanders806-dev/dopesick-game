extends SceneTree
## Dev helper: the viewmodel alone on a plain backdrop, hip and aimed, with a
## centre cross, to .pilot/vm_<gun>_<pose>.png (quick loop for sights and hands).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_vm.gd -- pistol ar [reload]
const Viewmodel := preload("res://player/Viewmodel.gd")
const HIP := Vector3(0.15, -0.17, -0.36)

func _initialize() -> void:
	await process_frame
	var out := ProjectSettings.globalize_path("res://.pilot")
	var args: Array = Array(OS.get_cmdline_user_args())
	var reload := args.has("reload")
	var guns: Array = args.filter(func(a): return a != "reload")
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.8
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 70.0
	world.add_child(cam)
	cam.current = true
	var side := Camera3D.new()
	side.environment = env
	side.fov = 40.0
	world.add_child(side)
	# Something to look at: a post 12 m away at the centre of the view.
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.4, 1.8, 0.4)
	post.mesh = pm
	post.position = Vector3(0, 0, -12)
	world.add_child(post)
	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func():
		var c := cross.size * 0.5
		cross.draw_line(Vector2(c.x, c.y - 360), Vector2(c.x, c.y + 360), Color(0, 1, 0, 0.35))
		cross.draw_line(Vector2(c.x - 640, c.y), Vector2(c.x + 640, c.y), Color(0, 1, 0, 0.35)))
	var layer := CanvasLayer.new()
	layer.add_child(cross)
	root.add_child(layer)
	for id in guns:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var vm := Viewmodel.new()
		cam.add_child(vm)
		vm.setup(d)
		for pose in ["hip", "ads", "right", "top"]:
			if pose == "hip":
				vm.position = HIP
				vm.rotation = Vector3.ZERO
			elif pose == "right" or pose == "top":
				vm.position = HIP
				vm.rotation = Vector3.ZERO
			else:
				vm.position = vm.ads_position
				vm.rotation = Vector3(vm.ads_pitch, 0, 0)
			vm.aim_hands(vm.grip_l)
			if pose == "right":
				side.global_position = cam.global_position + vm.position + Vector3(0.6, 0.0, 0.0)
				side.look_at(cam.global_position + vm.position + Vector3(0, 0, 0.12), Vector3.UP)
				side.current = true
			elif pose == "top":
				side.global_position = cam.global_position + vm.position + Vector3(0.0, 0.6, 0.0)
				side.look_at(cam.global_position + vm.position + Vector3(0, 0, 0.12), Vector3.LEFT)
				side.current = true
			else:
				cam.current = true
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/vm_%s_%s.png" % [out, id, pose])
		if reload:
			vm.position = HIP
			vm.rotation = Vector3.ZERO
			vm.aim_hands(vm.magwell)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/vm_%s_mag.png" % [out, id])
		print("VM ", id, " box ", vm.box, " sight ", vm.sight_point, " pitch ", rad_to_deg(vm.ads_pitch), " ads ", vm.ads_position)
		vm.queue_free()
		await process_frame
	quit()
