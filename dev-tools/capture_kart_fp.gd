extends SceneTree
## Dev helper: the kart race from the driver's seat in a window -> <out>/kart_*.png (the grid, the countdown, flat
## out on the straight, the wheel over). Only one windowed Godot at a time.
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_kart_fp.gd -- [out_dir]
var out := ""

func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/kart_%s.png" % [out, label])

func _wait(s: float) -> void:
	await create_timer(s, true, false, true).timeout

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://.pilot")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("GameState").no_sickness = true
	change_scene_to_file("res://world/KartCenter3D.tscn")
	await _wait(2.0)
	var race = load("res://ui/KartRace.gd").new()
	root.add_child(race)
	race.start()
	await _wait(1.6)
	await _snap("grid")
	await _wait(2.6)
	await _snap("countdown")
	await _wait(2.5)
	Input.action_press("move_up", 1.0)
	for i in 5:
		await _wait(1.0)
		await _snap("straight%d" % i)
		var y: Dictionary = race._karts[0]
		print("t=", i, " pos=", y["pos"], " vel=", (y["vel"] as Vector3).length(), " cam=", race._camera.global_position, " fov=", race._camera.fov)
	# Wheel over to one side for a moment: the head leans and looks into the turn.
	Input.action_press("move_right", 1.0)
	await _wait(0.6)
	await _snap("turn")
	Input.action_release("move_up")
	Input.action_release("drift")
	Input.action_release("move_left")
	Input.action_release("move_right")
	quit()
