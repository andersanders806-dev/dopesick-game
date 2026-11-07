extends SceneTree
## Where Ghetto Wars' frame time goes (windowed, Low): fps, CPU process/physics ms, draw calls and primitives for
## an empty block, with the set hidden, with a crew standing, and with a crew fighting.
##   flock /home/anders/dopesick-game/.perf.lock flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/gang_perf_probe.gd -- [Low|Medium]
var block: Node
var player: Node3D

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	_main()

func measure(label: String, secs := 8.0) -> void:
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var fps_min := 999.0
	var proc := 0.0
	var phys := 0.0
	var n := 0
	var vp := root.get_viewport().get_viewport_rid()
	var calls := 0
	var prims := 0
	while (Time.get_ticks_msec() - t0) < secs * 1000.0:
		await process_frame
		frames += 1
		var f := Engine.get_frames_per_second()
		if frames > 20:
			fps_min = minf(fps_min, f)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		calls = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		prims = RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		n += 1
	var fps := frames / ((Time.get_ticks_msec() - t0) / 1000.0)
	print("PERF %-34s fps %5.1f (min %3.0f)  process %.1f ms  physics %.1f ms  draw calls %d  prims %dk  crew %d" % [label, fps, fps_min, proc / n * 1000.0, phys / n * 1000.0, calls, prims / 1000, get_nodes_in_group("gangsters").size()])

func _main() -> void:
	await process_frame
	var preset := String(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else "Low"
	var gfx := root.get_node("Graphics")
	gfx.set_preset(gfx.Preset[preset.to_upper()])
	var zm := root.get_node("ZombieMode")
	var dead := OS.get_cmdline_user_args().has("dead")
	if dead:
		zm.begin(true)
	else:
		zm.begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready or (not dead and (block.cover == null or block.cover.points.is_empty())):
		await process_frame
	block.spawner.enabled = false
	for g in get_nodes_in_group("gangsters"):
		g.free()
	player = get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(-14.0, 0, 1.2)
	player.set_look(-PI / 2.0, 0.0)
	for i in 240:
		zm.health = zm.MAX_HEALTH
		await process_frame
	print("PERF preset ", preset)
	await measure("empty block, full set")
	if dead:
		quit(0)
		return
	var env: Environment = block.city._env
	print("PERF env: volumetric_fog %s fog %s ssao %s ssil %s glow %s sdfgi %s ssr %s" % [env.volumetric_fog_enabled, env.fog_enabled, env.ssao_enabled, env.ssil_enabled, env.glow_enabled, env.sdfgi_enabled, env.ssr_enabled])
	var lights := get_nodes_in_group("__none__")
	var all_lights: Array = current_scene.find_children("*", "Light3D", true, false)
	var visible_l := all_lights.filter(func(l): return l.visible and l.is_visible_in_tree())
	var shadow_l := visible_l.filter(func(l): return l.shadow_enabled)
	print("PERF lights: %d total, %d visible, %d with shadows" % [all_lights.size(), visible_l.size(), shadow_l.size()])
	var by := {}
	for l in visible_l:
		var n: Node = l
		var key := "?"
		while n != null and n != current_scene:
			key = String(n.name)
			if n.get_parent() == current_scene or n.get_parent() == block.city:
				break
			n = n.get_parent()
		var k2 := "%s/%s" % [key, l.get_class()]
		by[k2] = int(by.get(k2, 0)) + 1
	print("PERF visible lights by owner: ", by)
	var ranges := {}
	for l in visible_l:
		if l is OmniLight3D:
			var r := int(round((l as OmniLight3D).omni_range))
			ranges[r] = int(ranges.get(r, 0)) + 1
	print("PERF omni ranges: ", ranges)
	quit(0)
	return
	if block.ghetto_set != null:
		block.ghetto_set.visible = false
		await measure("set hidden")
		block.ghetto_set.visible = true
	block.story.hud.visible = false
	await measure("story HUD hidden")
	block.story.hud.visible = true
	var gs: Array = []
	for i in 12:
		var g = block.spawner.spawn_one("grunt", Vector3(-14.0 + 12.0 + i * 1.5, 0, 1.0 + (i % 3) * 1.5), "", "smg")
		g.mode = g.Mode.HOLD
		g.set_physics_process(false)
		gs.append(g)
	for i in 120:
		await process_frame
	await measure("12 crew standing (AI off)")
	for g in gs:
		g.set_physics_process(true)
		g.mode = g.Mode.ADVANCE
	var keep := func():
		while true:
			zm.health = zm.MAX_HEALTH
			await process_frame
	keep.call()
	await measure("12 crew AI on")
	zm.round = 3
	block.spawner.enabled = true
	block.spawner.crew_name = "Dock Boys"
	zm.start_round()
	await measure("wave running (spawner, fx)", 20.0)
	quit(0)
