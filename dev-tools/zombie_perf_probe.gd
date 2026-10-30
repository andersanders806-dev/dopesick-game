extends SceneTree
## The horde's performance gate (Task Z2): 20 zombies chasing the player down
## Main Street on Low, measured for N seconds: FPS, GPU ms (average and worst),
## frames over 33 ms, CPU ms per frame. Needs a window.
##
##   flatpak run org.godotengine.Godot --path . --socket=wayland --display-driver wayland \
##     -s res://dev-tools/zombie_perf_probe.gd -- [seconds=60] [Low|Medium|High] [zombies=20] [baseline] [route] [rounds]
## `baseline` runs the same street with no zombies, for the difference.
## `route` walks the player along the same fixed path down Main Street, with the
## same camera, in either run (so a baseline and a horde run can be compared
## frame for frame).
## `rounds` measures the spawn phase: the real spawner runs rounds 1-3 (fast,
## the dead are put down within 10 m of the player or after 5 s, so the rounds end) and the clock
## starts BEFORE the first one is let out, so first-use loads, shader
## compiles and the spawn itself show as frame hitches. With `baseline` the
## spawner stays off: the same route and window without a single zombie.
## The performance gate (14 ms GPU, no frame > 33 ms) is NOT met by this
## script saying so: compare a `baseline route` run with a `route` run (>= 3
## each, median) and read the difference.

var _vp_rid: RID

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 60.0
	var preset_name := args[1] if args.size() > 1 else "Low"
	var count := int(args[2]) if args.size() > 2 else 20
	var baseline := args.has("baseline")
	# near: the whole horde starts on top of the player; exp=<x>: switch a cost off to measure it.
	var near := args.has("near")
	var experiment := ""
	for a in args:
		if a.begins_with("exp="):
			experiment = a.substr(4)
	var route := args.has("route")
	var rounds_mode := args.has("rounds")
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	gfx.set_preset(gfx.PRESET_NAMES.find(preset_name))
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 240:
		await process_frame
	# No adaptive scale hiding the cost, a fixed full-resolution render.
	gfx.set_process(false)
	root.scaling_3d_scale = 1.0
	var city := current_scene
	var spawner: Node = city.get_node("ZombieBlock").spawner
	spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(-8.0, 0.0, -1.0)
	spawner.round_no = 8
	if not baseline and not rounds_mode:
		for i in count:
			# A column down Main Street: from 10 m to 60 m either side.
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := -8.0 + side * (10.0 + (i / 2) * 5.0)
			var kind := "runner" if i % 3 == 0 else "walker"
			var at := Vector3(clampf(x, -70.0, 70.0), 0.0, 1.0 + (i % 3) * 0.8)
			if near:
				at = player.global_position + Vector3(cos(i * 0.7), 0.0, sin(i * 0.7)) * (3.0 + (i % 4) * 0.8)
			spawner.spawn_one(kind, at)
		for z in get_nodes_in_group("zombies"):
			if experiment == "nophys":
				z.set_physics_process(false)
			elif experiment == "nohit":
				for p in z.hitboxes:
					z.hitboxes[p].queue_free()
			elif experiment == "disabled":
				z.process_mode = Node.PROCESS_MODE_DISABLED
			elif experiment == "noshape":
				z._shape.disabled = true
			elif experiment == "noanim":
				z._anim_player.pause()
			elif experiment == "noshadow":
				for mi in z.model.find_children("*", "MeshInstance3D", true, false):
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	for i in 120:
		await process_frame
	var frames := 0
	var over33 := 0
	var over20 := 0
	var worst := 0.0
	var gpu_sum := 0.0
	var gpu_worst := 0.0
	var cpu_sum := 0.0
	var phys_sum := 0.0
	var spawn_flag := [false]
	var spawn_worst := 0.0
	var spawn_frames := 0
	var spawn_over33 := 0
	var start_ms := Time.get_ticks_msec()
	if rounds_mode and not baseline:
		# Measuring has begun; now the first of the dead is let out.
		spawner.spawned.connect(func(_z): spawn_flag[0] = true)
		spawner.worst_spawn_usec = 0
		spawner.time_scale = 0.25
		spawner.enabled = true
		zm.round = 0
		zm.start_round()
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	var shot_at := Time.get_ticks_msec() + int(seconds * 500.0)
	var shot := false
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		frames += 1
		if not shot and Time.get_ticks_msec() > shot_at:
			shot = true
			root.get_texture().get_image().save_png("res://.pilot/zhorde_%s.png" % ("base" if baseline else "horde"))
			# (Saving the picture is a stall of its own: not counted.)
			last = Time.get_ticks_usec()
			continue
		if route:
			# A triangle wave down Main Street at a walk.
			var t := (Time.get_ticks_msec() - start_ms) / 1000.0
			var u := fposmod(t * 2.4, 128.0)
			player.global_position = Vector3(-40.0 + (u if u < 64.0 else 128.0 - u), 0.0, -1.0)
			player.velocity = Vector3.ZERO
		if rounds_mode and not baseline:
			for z in get_nodes_in_group("zombies"):
				if not z.has_meta("born"):
					z.set_meta("born", Time.get_ticks_msec())
				if z.global_position.distance_to(player.global_position) < 10.0 or Time.get_ticks_msec() - int(z.get_meta("born")) > 5000:
					z.take_hit("torso", 1.0e6, Vector3.FORWARD, null)
			if spawn_flag[0]:
				spawn_flag[0] = false
				spawn_frames += 1
				spawn_worst = maxf(spawn_worst, dt)
				if dt > 33.4:
					spawn_over33 += 1
		worst = maxf(worst, dt)
		if dt > 33.4:
			over33 += 1
		if dt > 20.0:
			over20 += 1
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
		gpu_sum += gpu
		gpu_worst = maxf(gpu_worst, gpu)
		cpu_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var alive := get_nodes_in_group("zombies").size()
	print("PERF %s %s%s zombies=%d alive_at_end=%d %.0fs" % [preset_name, "baseline" if baseline else "horde", " rounds" if rounds_mode else "", count, alive, seconds])
	print("  FPS         %.1f  (%d frames)" % [frames / seconds, frames])
	print("  GPU ms      avg %.2f  worst %.2f" % [gpu_sum / frames, gpu_worst])
	print("  CPU ms      process %.2f  physics %.2f" % [cpu_sum / frames, phys_sum / frames])
	print("  frame ms    worst %.1f   > 20 ms: %d   > 33 ms: %d" % [worst, over20, over33])
	print("  draw calls  %d   objects %d" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	if rounds_mode and not baseline:
		print("  spawn phase round %d reached, %d dead let out; spawn call worst %.1f ms; frames that spawned: worst %.1f ms, > 33 ms: %d of %d"
			% [zm.round, spawn_frames, spawner.worst_spawn_usec / 1000.0, spawn_worst, spawn_over33, spawn_frames])
	if route:
		print("  (route: fixed walk along Main Street, same camera in baseline and horde runs)")
	print("  (this probe measures; the 14 ms GPU / 33 ms frame gate is judged from baseline-vs-horde medians, not from one run)")
	zm.leave()
	quit()
