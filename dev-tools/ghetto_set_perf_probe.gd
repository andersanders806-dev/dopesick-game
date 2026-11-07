extends SceneTree
## The set's cost (task GW3): Ghetto Wars on Main Street, 12 stand-in enemies (the dead, until the gangsters
## are wired), the player walking a fixed route past the corner, measured for N seconds: FPS, GPU ms, frames
## over 33 ms. `baseline` frees the set for the difference; `full` also runs THE BUST (police, lightbars),
## the helicopter with its searchlight and a drive-by on repeat. Needs a window.
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/ghetto_set_perf_probe.gd -- [seconds=40] [Low|Medium|High] [baseline] [full]
var _vp: RID

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 40.0
	var preset := args[1] if args.size() > 1 else "Low"
	var baseline := args.has("baseline")
	var full := args.has("full")
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	gfx.set_preset(gfx.PRESET_NAMES.find(preset))
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 240:
		await process_frame
	gfx.set_process(false)
	root.scaling_3d_scale = 1.0
	var city := current_scene
	var block := city.get_node("ZombieBlock")
	var spawner: Node = block.spawner
	spawner.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	var set_ := city.get_node("GhettoSet")
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(2.0, 0.0, -1.0)
	for i in 12:
		spawner.spawn_one("walker", Vector3(4.0 + i * 2.2, 0.0, 0.5 + (i % 3) * 1.1))
	for z in get_nodes_in_group("zombies"):
		z.set_physics_process(false)
	if baseline:
		set_.queue_free()
	else:
		set_.set_wave(6)
		if full:
			set_.set_chapter("THE BUST")
			set_.heli.set_between_waves(true)
	for i in 400:
		await process_frame
	_vp = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	var frames := 0
	var over33 := 0
	var worst := 0.0
	var gpu_sum := 0.0
	var gpu_worst := 0.0
	var start := Time.get_ticks_msec()
	var end := start + int(seconds * 1000.0)
	var last := Time.get_ticks_usec()
	var shot := false
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		frames += 1
		zm.health = zm.MAX_HEALTH
		var t := (Time.get_ticks_msec() - start) / 1000.0
		var u := fposmod(t * 2.0, 60.0)
		player.global_position = Vector3(-10.0 + (u if u < 30.0 else 60.0 - u), 0.0, -1.0)
		player.velocity = Vector3.ZERO
		if full and not baseline and not set_.vehicles.is_driving() and int(t) % 9 == 0:
			set_.drive_by("main_east" if int(t / 9.0) % 2 == 0 else "main_west")
		if not shot and t > seconds * 0.5:
			shot = true
			root.get_texture().get_image().save_png("res://.pilot/gw3_perf_%s_%s.png" % [preset, "base" if baseline else ("full" if full else "set")])
			last = Time.get_ticks_usec()
			continue
		worst = maxf(worst, dt)
		over33 += 1 if dt > 33.4 else 0
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		gpu_sum += gpu
		gpu_worst = maxf(gpu_worst, gpu)
	print("PERF %s %s 12 stand-ins %.0fs: FPS %.1f, GPU avg %.2f worst %.2f ms, frames>33ms %d, worst frame %.1f ms" % [preset, "baseline" if baseline else ("set+bust+heli+drive-by" if full else "set"), seconds, frames / seconds, gpu_sum / frames, gpu_worst, over33, worst])
	quit()
