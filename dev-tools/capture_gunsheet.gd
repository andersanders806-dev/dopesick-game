extends SceneTree
## Dev helper: all eight guns side by side, barrels to the right, in a window,
## to res://_caps/gunsheet.png (an orthographic camera fitted to the grid).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_gunsheet.gd
const GunModel := preload("res://weapons/GunModel.gd")
const IDS := ["pistol", "smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]
const CELL := Vector2(1.45, 0.8)

func _initialize() -> void:
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.environment.ambient_light_energy = 1.5
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-20, 70, 0)
	world.add_child(sun)
	var cols := 4
	var rows := 2
	for i in IDS.size():
		var gun: Node3D = GunModel.build(load("res://weapons/%s.tres" % IDS[i]))
		var col := i % cols
		var row := i / cols
		# The camera is on +X looking along -X: right on screen is -Z, so a barrel along -Z points right.
		gun.position = Vector3(0.0, (0.5 - row) * CELL.y, ((cols - 1) * 0.5 - col) * CELL.x)
		world.add_child(gun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var size := vp_size()
	cam.size = maxf(rows * CELL.y + 0.3, (cols * CELL.x + 0.3) * size.y / size.x)
	cam.position = Vector3(6, 0, 0)
	cam.environment = env.environment
	world.add_child(cam)
	cam.current = true
	cam.look_at(Vector3.ZERO, Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_caps/gunsheet.png"))
	quit()

func vp_size() -> Vector2:
	var s := root.get_visible_rect().size
	return s if s.x > 0 else Vector2(1280, 720)
