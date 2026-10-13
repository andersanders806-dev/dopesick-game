extends SceneTree
## Walks the player along the street in a real window and measures, frame by
## frame, what the eye sees: how far the player moves on screen and in the
## world (interpolated, as drawn), how many physics ticks ran, and whether
## any passer-by jumps or blinks out. Prints a summary and writes
## .pilot/jitter.csv.
##
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/jitter_probe.gd -- [Low|Medium] [seconds] [action]

var _rows: PackedStringArray = []

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var preset_name := args[0] if args.size() > 0 else "Low"
	var secs := float(args[1]) if args.size() > 1 else 6.0
	var action := args[2] if args.size() > 2 else "move_right"
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	gfx.set_preset(gfx.PRESET_NAMES.find(preset_name))
	var mode := args[4] if args.size() > 4 else ""
	if mode == "fifo":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		Engine.max_fps = 0
	elif mode == "mailbox0":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_MAILBOX)
		Engine.max_fps = 0
	print("vsync ", DisplayServer.window_get_vsync_mode(), " max_fps ", Engine.max_fps, " refresh ", DisplayServer.screen_get_refresh_rate())
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = 14 * 60
	change_scene_to_file("res://world/City3D.tscn")
	for i in 240:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	var cam: Camera3D = player.camera
	for i in 30:
		await process_frame
	Input.action_press(action)
	var t0 := Time.get_ticks_usec()
	var last_t := t0
	var last_pos := Vector3.INF
	var last_screen := Vector2.INF
	var last_phys := Engine.get_physics_frames()
	var peds_last := {}
	var steps: Array = []
	var screen_steps: Array = []
	var dts: Array = []
	var ticks_hist := {}
	var ped_jumps := 0
	var ped_blinks := 0
	var settle := 0
	var frames_img: Array = []
	var grab := args.size() > 3 and args[3] == "frames"
	while Time.get_ticks_usec() - t0 < secs * 1e6:
		await process_frame
		await RenderingServer.frame_post_draw
		if grab and frames_img.size() < 150 and settle > 20:
			var im := root.get_texture().get_image()
			im.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			frames_img.append(im)
		var now := Time.get_ticks_usec()
		var dt := (now - last_t) / 1000.0
		last_t = now
		var phys := Engine.get_physics_frames()
		var ticks := phys - last_phys
		last_phys = phys
		var pos: Vector3 = player.get_global_transform_interpolated().origin
		var cxf: Transform3D = cam.get_global_transform_interpolated()
		var local := cxf.affine_inverse() * (pos + Vector3(0, 1.0, 0))
		var screen := Vector2(local.x / -local.z, local.y / -local.z) * 1000.0
		settle += 1
		if last_pos != Vector3.INF and settle > 20:
			var step := (pos - last_pos).length()
			steps.append(step)
			screen_steps.append((screen - last_screen).length())
			dts.append(dt)
			ticks_hist[ticks] = ticks_hist.get(ticks, 0) + 1
			_rows.append("%.2f,%d,%.4f,%.3f,%.2f,%.2f" % [dt, ticks, step, (screen - last_screen).length(), screen.x, screen.y])
		last_pos = pos
		last_screen = screen
		# Passers-by: a jump is >0.4 m in one drawn frame; a blink is going
		# invisible while still in the tree and near the player.
		var peds := {}
		for n in get_nodes_in_group("pedestrians") + get_nodes_in_group("npc"):
			if not n is Node3D:
				continue
			var p: Vector3 = (n as Node3D).get_global_transform_interpolated().origin
			peds[n.get_instance_id()] = [p, (n as Node3D).is_visible_in_tree()]
			var prev = peds_last.get(n.get_instance_id())
			if prev and settle > 20:
				if (p - prev[0]).length() > 0.4:
					ped_jumps += 1
					print("JUMP %s %.2f m" % [n.name, (p - prev[0]).length()])
				if prev[1] and not peds[n.get_instance_id()][1] and p.distance_to(pos) < 25.0:
					ped_blinks += 1
					print("BLINK %s" % n.name)
		peds_last = peds
	Input.action_release(action)
	for i in frames_img.size():
		frames_img[i].save_png(ProjectSettings.globalize_path("res://.pilot/frame_%03d.png" % i))
	var f := FileAccess.open(ProjectSettings.globalize_path("res://.pilot/jitter.csv"), FileAccess.WRITE)
	f.store_line("dt_ms,ticks,world_step,screen_step,sx,sy")
	for r in _rows:
		f.store_line(r)
	f.close()
	print("preset %s  frames %d  ticks/frame %s" % [preset_name, steps.size(), str(ticks_hist)])
	print("dt ms: %s" % _stats(dts))
	print("world step m: %s" % _stats(steps))
	print("screen step: %s" % _stats(screen_steps))
	print("ped jumps %d  blinks %d" % [ped_jumps, ped_blinks])
	quit()

func _stats(a: Array) -> String:
	if a.is_empty():
		return "-"
	var s := a.duplicate()
	s.sort()
	var mean := 0.0
	for v in a:
		mean += v
	mean /= a.size()
	var dev := 0.0
	for v in a:
		dev += (v - mean) * (v - mean)
	dev = sqrt(dev / a.size())
	return "mean %.4f  sd %.4f  min %.4f  p5 %.4f  p95 %.4f  max %.4f" % [mean, dev, s[0], s[int(s.size() * 0.05)], s[int(s.size() * 0.95)], s[-1]]
