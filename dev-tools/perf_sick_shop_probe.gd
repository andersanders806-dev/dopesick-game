extends SceneTree
## Perf probe for the corner shop in first person, sick, needs a real window (not --headless): GPU and CPU
## frame time looking round the shop on Medium. For the before/after of the sick-stealth branch: it only
## uses what the base has, so the same file runs on both.
##   flock /home/anders/dopesick-game/.perf.lock flatpak run org.godotengine.Godot --path . \
##     -s res://dev-tools/perf_sick_shop_probe.gd -- [craving]
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	gfx.set_preset(1)
	root.get_node("Survival").enabled = false
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = 14 * 60
	gs.no_sickness = false
	gs.craving = float(args[0]) if args.size() > 0 else 6.0
	change_scene_to_file("res://world/City3D.tscn")
	for i in 150:
		await process_frame
	var player := get_first_node_in_group("player")
	player.global_position = Vector3(3.5, 0.0, -9.0)
	for i in 120:
		await process_frame
	var rid := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu: Array = []
	var cpu: Array = []
	var frame_ms: Array = []
	var t_last := Time.get_ticks_usec()
	var yaws := [0.0, 90.0, 180.0, -90.0]
	for i in 600:
		player.set_look(deg_to_rad(yaws[(i / 150) % 4]), 0.0)
		await process_frame
		var now := Time.get_ticks_usec()
		if i > 20:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			frame_ms.append((now - t_last) / 1000.0)
		t_last = now
	var mean := func(a: Array) -> float:
		var s := 0.0
		for v in a:
			s += v
		return s / a.size()
	frame_ms.sort()
	print("PERF shop fp craving=%.0f gpu mean %.2f ms, cpu render %.2f ms, frame mean %.2f ms p95 %.2f ms (%.0f fps)" % [
		gs.craving, mean.call(gpu), mean.call(cpu), mean.call(frame_ms), frame_ms[int(frame_ms.size() * 0.95)], 1000.0 / mean.call(frame_ms)])
	quit()
