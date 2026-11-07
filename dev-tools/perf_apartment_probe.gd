extends SceneTree
## Perf probe for the flat in first person, needs a real window (not --headless): GPU and frame time on Low,
## looking round the room. DOPESICK_NO_DRESS=1 leaves out world/ApartmentDress.gd for the before/after.
##   flock /home/anders/dopesick-game/.perf.lock flatpak run org.godotengine.Godot --path . \
##     -s res://dev-tools/perf_apartment_probe.gd -- <fp|tp> [preset 0-3]
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var fp := args.size() == 0 or args[0] != "tp"
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(fp)
	gfx.set_preset(int(args[1]) if args.size() > 1 else 0)
	gfx.set_laptop_mode(true)
	root.get_node("Survival").enabled = false
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = 22 * 60 + 30
	gs.no_sickness = true
	change_scene_to_file("res://world/Apartment3D.tscn")
	for i in 120:
		await process_frame
	var rid := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu: Array = []
	var cpu: Array = []
	var player := get_first_node_in_group("player")
	var yaws := [0.0, 90.0, 180.0, -90.0]
	for i in 480:
		if fp and player:
			player.set_look(deg_to_rad(yaws[(i / 120) % 4]), 0.0)
		await process_frame
		if i > 20:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	gpu.sort()
	var mean := 0.0
	for g in gpu:
		mean += g
	mean /= gpu.size()
	var cm := 0.0
	for c in cpu:
		cm += c
	cm /= cpu.size()
	print("PERF %s preset=%s dress=%s gpu mean %.2f ms p95 %.2f ms, cpu render mean %.2f ms, render scale %.2f" % [
		"fp" if fp else "tp", gfx.PRESET_NAMES[gfx.preset], "off" if OS.has_environment("DOPESICK_NO_DRESS") else "on",
		mean, gpu[int(gpu.size() * 0.95)], cm, gfx.render_scale])
	quit()
