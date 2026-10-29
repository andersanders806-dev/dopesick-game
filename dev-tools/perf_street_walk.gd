extends SceneTree
## Perf probe, needs a real window (not --headless): sprints back and forth
## along Main Street (x -60..60) on Low + laptop mode and counts frames
## > 25 ms, the GPU time and the dynamic-resolution scale it settled at.
## Runs on the master street as well as on the block, so the two compare.
##   flatpak run --socket=wayland org.godotengine.Godot --display-driver wayland \
##     --path . -s res://dev-tools/perf_street_walk.gd -- <day|night> <tp|fp> <seconds>
## Other windowed Godot processes share the iGPU and skew everything: give
## a file (env PERF_OTHERS_FILE) that holds the number of other windowed
## Godot processes, refreshed every second, and the CLEAN line only counts
## frames where it read 0 twice running.
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var night := args.size() > 0 and args[0] == "night"
	var fp := args.size() > 1 and args[1] == "fp"
	var secs := float(args[2]) if args.size() > 2 else 60.0
	await process_frame
	if "novsync" in args:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(fp)
	gfx.set_preset(0)
	gfx.set_laptop_mode(true)
	root.get_node("Survival").enabled = false
	root.get_node("Headlines").forced = "quiet"
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = (23 * 60) if night else (14 * 60)
	change_scene_to_file("res://world/City3D.tscn")
	if "watchmesh" in args:
		_watch_added = true
		node_added.connect(func(n: Node): _added.append([Engine.get_process_frames(), str(n.get_path()) + " <" + n.get_class() + ">" + (" mesh=" + str((n as MeshInstance3D).mesh.resource_path.get_file()) if n is MeshInstance3D and (n as MeshInstance3D).mesh != null else "")]))
		process_frame.connect(_check_mesh)
	var pre_last := Time.get_ticks_usec()
	for i in 240:
		await process_frame
		pre_last = _pre_hitch(pre_last, "load")
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	player.global_position = Vector3(-60, 0, -2.6)
	player.reset_physics_interpolation()
	for i in 30:
		await process_frame
		pre_last = _pre_hitch(pre_last, "settle")
	_experiments(args)
	# The game has the title screen's time to finish SceneLoader's background
	# prefetch; standing still here is what starts it, so let it finish
	# (otherwise its main-thread burst lands mid-walk as one 0.4-0.8 s frame).
	# "noprefetchwait" skips this.
	var sl := root.get_node_or_null("SceneLoader")
	if sl != null and not "noprefetchwait" in args:
		var w0 := Time.get_ticks_usec()
		while (not sl._queue.is_empty() or not sl._loading.is_empty()) and Time.get_ticks_usec() - w0 < 60e6:
			await process_frame
			pre_last = _pre_hitch(pre_last, "wait")
		print("prefetch wait %.1f s" % ((Time.get_ticks_usec() - w0) / 1e6))
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("taxi model cached: ", ResourceLoader.has_cached("res://assets/cars/taxi_crownvic.glb"))
	print("== %s %s %.0f s vsync %d  occl %s  nodes %d" % ["night" if night else "day", "FP" if fp else "TP", secs, DisplayServer.window_get_vsync_mode(), root.use_occlusion_culling, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var dts: Array[float] = []
	var clean: Array[float] = []
	var clean_gpu: Array[float] = []
	var others := 0
	var others_file := OS.get_environment("PERF_OTHERS_FILE")
	var frame_i := 0
	var quiet_prev := false
	var gpus: Array[float] = []
	var scales := 0.0
	var dir := 1.0
	# "scale=0.75" pins the render scale (the adaptive controller is overridden each frame)
	var fixed_scale := 0.0
	for a in args:
		if str(a).begins_with("scale="):
			fixed_scale = float(str(a).substr(6))
	var taxi_done := false
	var t0 := Time.get_ticks_usec()
	var last := t0
	var slow := 0
	var last_x := player.global_position.x
	var stuck_t := 0.0
	var nudge := 0
	while Time.get_ticks_usec() - t0 < secs * 1e6:
		if player.global_position.x > 60.0: dir = -1.0
		elif player.global_position.x < -60.0: dir = 1.0
		for a in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(a)
		Input.action_press("sprint")
		# Round a hydrant or a car: a few frames south, then on.
		if nudge > 0:
			nudge -= 1
			Input.action_press("move_down")
		if fp:
			player.set_look(-PI / 2 if dir > 0 else PI / 2, -0.1)
			Input.action_press("move_up")
		else:
			Input.action_press("move_right" if dir > 0 else "move_left")
		await process_frame
		if "taxinow" in args and not taxi_done and Time.get_ticks_usec() - t0 > 3e6:
			# A taxi model (loaded: the prefetch has run) appears ahead of the player
			taxi_done = true
			var tm: Node3D = (load("res://assets/cars/taxi_crownvic.glb") as PackedScene).instantiate()
			load("res://world/CarPaint.gd").dress(tm, -1, false)
			current_scene.add_child(tm)
			tm.global_position = player.global_position + Vector3(10.0 * dir, 0, 2.5)
			print("  taxi added at t=3 s, frame %d" % Engine.get_process_frames())
		if fixed_scale > 0.0:
			gfx.render_scale = fixed_scale
			root.scaling_3d_scale = fixed_scale
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		if absf(player.global_position.x - last_x) < 0.02:
			stuck_t += dt
		else:
			stuck_t = 0.0
		last_x = player.global_position.x
		if stuck_t > 300.0 and nudge == 0:
			nudge = 25
			stuck_t = 0.0
		dts.append(dt)
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		gpus.append(g)
		frame_i += 1
		if frame_i % 15 == 1:
			var q := FileAccess.get_file_as_string(others_file).strip_edges() if others_file != "" else "0"
			var quiet_now := q == "0"
			# clean = quiet at this and the last look (a quarter second apart)
			var was := quiet_prev
			quiet_prev = quiet_now
			others = 0 if (quiet_now and was) else 1
		if others == 0:
			clean.append(dt)
			clean_gpu.append(g)
		scales += root.scaling_3d_scale
		if dt >= 100.0:
			print("  HITCH frame %d %.0f ms at t=%.1f s pos %s proc %.0f phys %.0f gpu %.0f cpu_render %.0f objs %d res %d pipelines %s" % [Engine.get_process_frames(), dt, (now - t0) / 1e6, player.global_position.snapped(Vector3.ONE), Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, g, RenderingServer.viewport_get_measured_render_time_cpu(vp), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), _pipelines()])
		if dt > 25.0 and dt < 400.0:
			slow += 1
			print("  SLOW %.1f ms at %s gpu %.1f cpu_render %.1f proc %.1f" % [dt, player.global_position.snapped(Vector3.ONE), g, RenderingServer.viewport_get_measured_render_time_cpu(vp), Performance.get_monitor(Performance.TIME_PROCESS) * 1000])
	for a in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(a)
	var b := [0, 0, 0, 0, 0]
	for d in dts:
		b[0 if d < 14.0 else (1 if d < 19.0 else (2 if d < 25.0 else (3 if d < 40.0 else 4)))] += 1
	var ds := dts.duplicate()
	ds.sort()
	var gs2 := gpus.duplicate()
	gs2.sort()
	var gsum := 0.0
	for g in gpus: gsum += g
	print("RESULT frames %d (%.1f s): <14 %d  14-19 %d  19-25 %d  25-40 %d  >40 %d | >25 ms per minute: %.1f | median %.2f p99 %.2f max %.2f | gpu avg %.2f p99 %.2f max %.2f scale %.2f" % [dts.size(), (Time.get_ticks_usec() - t0) / 1e6, b[0], b[1], b[2], b[3], b[4], (b[3] + b[4]) * 60.0 / ((Time.get_ticks_usec() - t0) / 1e6), ds[ds.size() / 2], ds[int(ds.size() * 0.99)], ds[-1], gsum / gpus.size(), gs2[int(gs2.size() * 0.99)], gs2[-1], scales / dts.size()])
	var cs := clean.duplicate()
	cs.sort()
	var cg := 0.0
	for g in clean_gpu: cg += g
	var cslow := 0
	for d in clean:
		if d > 25.0 and d < 400.0: cslow += 1
	if clean.size() > 10:
		print("CLEAN (no other Godot running) frames %d (%.1f s): >25 ms %d = %.1f per minute | median %.2f p99 %.2f max %.2f | gpu avg %.2f" % [clean.size(), clean.size() * 0.01667, cslow, cslow * 3600.0 / clean.size(), cs[cs.size() / 2], cs[int(cs.size() * 0.99)], cs[-1], cg / clean_gpu.size()])
	else:
		print("CLEAN none")
	quit()

## Optional cost experiments (extra args): sunshadow off, lampshadow off,
## lamps off, nofade (props lose visibility_range fades), nolit (no omni/spot).
func _experiments(args: Array) -> void:
	var n_l := 0
	var stack: Array[Node] = [current_scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is DirectionalLight3D and "nosun" in args:
			n.shadow_enabled = false
		elif n is Light3D and not n is DirectionalLight3D:
			if "noshadow" in args:
				n.shadow_enabled = false
			if "nolamps" in args:
				n.visible = false
			n_l += 1
		if n is GeometryInstance3D and "nofade" in args:
			n.visibility_range_begin = 0.0
			n.visibility_range_end = 0.0
			n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	print("experiments %s lights %d" % [str(args.slice(3)), n_l])

## A frame of 100 ms or more before the walk starts (standing still), with the
## frame number: tells a hitch that belongs to the scene's own timeline from one
## the walking causes.
func _pre_hitch(last: int, phase: String) -> int:
	var now := Time.get_ticks_usec()
	if (now - last) / 1000.0 >= 100.0 and phase != "load":
		print("  PREHITCH %s frame %d %.0f ms | pipelines %s" % [phase, Engine.get_process_frames(), (now - last) / 1000.0, _pipelines()])
	return now

func _pipelines() -> String:
	var ri := RenderingServer
	return "mesh %d surface %d draw %d spec %d" % [ri.get_rendering_info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH), ri.get_rendering_info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE), ri.get_rendering_info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW), ri.get_rendering_info(ri.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)]

var _watch_added := false
var _added: Array = []
var _mesh_n := -1
func _check_mesh() -> void:
	var n := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)
	var f := Engine.get_process_frames()
	if _mesh_n >= 0 and n != _mesh_n:
		print("  MESHPIPE %d -> %d at frame %d; nodes added in the last 4 frames:" % [_mesh_n, n, f])
		for a in _added:
			if a[0] >= f - 4:
				print("     %d %s" % [a[0], a[1]])
	_mesh_n = n
	while _added.size() > 0 and _added[0][0] < f - 6:
		_added.pop_front()
