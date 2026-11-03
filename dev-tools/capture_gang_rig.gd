extends SceneTree
## Contact sheet of the armed humans, for fitting the guns to the hands: each gun, standing and crouched, side /
## front / three-quarter views.   (windowed)
##   flatpak run org.godotengine.Godot --path . --resolution 800x600 -s res://dev-tools/capture_gang_rig.gd -- <out.png> [guns...]
var GangsterScript: GDScript
const CELL := Vector2i(300, 380)

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/gang_rig.png"
	var guns: Array = Array(args.slice(1)) if args.size() > 1 else ["pistol", "smg", "ar", "shotgun", "lmg"]
	var crouch := false
	if guns.has("crouch"):
		crouch = true
		guns.erase("crouch")
	await process_frame
	GangsterScript = load("res://npc/Gangster3D.gd")
	root.get_node("ZombieMode").begin_gangs()
	var vp := SubViewport.new()
	vp.size = CELL
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var holder := Node3D.new()
	vp.add_child(holder)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.27, 0.25)
	plane.material = fm
	floor_mesh.mesh = plane
	holder.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	holder.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.45, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	holder.add_child(env)
	var cam := Camera3D.new()
	holder.add_child(cam)
	cam.current = true
	cam.fov = 38.0
	var dummy := Node3D.new()
	dummy.add_to_group("player")
	holder.add_child(dummy)
	dummy.global_position = Vector3(0, 0, -30)
	var sheet := Image.create(CELL.x * 3, CELL.y * guns.size(), false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for gi in guns.size():
		var g = GangsterScript.new()
		g.configure("grunt", 1, rng)
		g.gun_id = guns[gi]
		g.gun = GangsterScript.GUNS[guns[gi]]
		g.set_meta("body", "Male_Adult_04")
		g.target = dummy
		holder.add_child(g)
		g.mode = GangsterScript.Mode.HOLD
		g.crouched = crouch
		g._facing = PI
		g._model_root.rotation.y = PI
		# (the body faces -Z: the dummy is there)
		for _w in 12:
			await physics_frame
		var sk: Skeleton3D = g._skeleton
		var c := Vector3(0, 0.95 if not crouch else 0.7, 0)
		for view in 3:
			# camera ring round the body's forward (-Z): side from +X, front from -Z
			var dirs: Array = [Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0.7, 0.15, -0.7)]
			cam.global_position = c + dirs[view].normalized() * 3.6 + Vector3(0, 0.2, 0)
			cam.look_at(c, Vector3.UP)
			for _w in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * view, CELL.y * gi))
		g.queue_free()
		await process_frame
	sheet.save_png(out)
	print("saved ", out)
	quit(0)
