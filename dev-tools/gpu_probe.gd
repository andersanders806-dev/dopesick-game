extends SceneTree
## Where the GPU time goes on the street: stands the player on the block at
## Low, holds the render scale at 1.0, and measures the average GPU frame
## time with each kind of thing switched off in turn.
##
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/gpu_probe.gd -- [Low] [HH]

var _vp_rid: RID

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var preset_name := args[0] if args.size() > 0 else "Low"
	var hour := int(args[1]) if args.size() > 1 else 14
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	gfx.set_preset(gfx.PRESET_NAMES.find(preset_name))
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = hour * 60
	change_scene_to_file("res://world/City3D.tscn")
	for i in 300:
		await process_frame
	gfx.set_process(false)  # no adaptive scale, no shadow budget
	root.scaling_3d_scale = 1.0
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	var city := current_scene
	var base := await _gpu()
	print("BASE  %.2f ms  (scale 1.0, %s, %02d:00)" % [base, preset_name, hour])
	var tests := {
		"directional shadow": func(on): for l in city.find_children("*", "DirectionalLight3D", true, false): l.shadow_enabled = on,
		"omni/spot lights": func(on): for l in city.find_children("*", "Light3D", true, false): if not l is DirectionalLight3D: l.visible = on,
		"decals": func(on): for d in city.find_children("*", "Decal", true, false): d.visible = on,
		"particles": func(on): for p in city.find_children("*", "GPUParticles3D", true, false): p.visible = on,
		"label3d": func(on): for p in city.find_children("*", "Label3D", true, false): p.visible = on,
		"fog": func(on): _env(city).fog_enabled = on,
		"people": func(on): for n in city.find_children("*", "Skeleton3D", true, false): if is_instance_valid(n) and n.get_parent() is Node3D: n.get_parent().visible = on,
		"fxaa": func(on): root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED,
	}
	for name in tests:
		var f: Callable = tests[name]
		var before := root.screen_space_aa
		var b1 := await _gpu()
		f.call(false)
		var t := await _gpu()
		f.call(true)
		root.screen_space_aa = before
		var b2 := await _gpu()
		var b := (b1 + b2) * 0.5
		print("  without %-20s %.2f ms vs %.2f  (saves %.2f)" % [name, t, b, b - t])
	# Every remaining top-level child, hidden one at a time.
	var rows := []
	for c in city.get_children():
		if c is Node3D and c.visible and c.get_child_count() > 0:
			var b1 := await _gpu()
			c.visible = false
			var t := await _gpu()
			c.visible = true
			rows.append([b1 - t, c.name])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows.slice(0, 12):
		print("  node %-28s saves %.2f ms" % [r[1], r[0]])
	print("info: lights %d, meshes %d, draw calls %d" % [city.find_children("*", "Light3D", true, false).size(),
		city.find_children("*", "MeshInstance3D", true, false).size(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	quit()

func _env(city: Node) -> Environment:
	for w in city.find_children("*", "WorldEnvironment", true, false):
		return (w as WorldEnvironment).environment
	return Environment.new()

func _gpu() -> float:
	for i in 10:
		await process_frame
	var acc := 0.0
	for i in 60:
		await process_frame
		acc += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	return acc / 60.0
