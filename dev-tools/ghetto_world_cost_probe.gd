extends SceneTree
## GPU cost of what is in Ghetto Wars' night, by switching one thing off at a time (Low preset, 1280x720, no dynamic
## resolution), in two views; prints the ms each costs. Run it alone on the machine:
##   flock /home/anders/dopesick-game/.perf.lock flatpak run org.godotengine.Godot --path . -s res://dev-tools/ghetto_world_cost_probe.gd -- --no-sick
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	gfx.set_preset(gfx.PRESET_NAMES.find("Low"))
	root.get_node("ZombieMode").begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 240: await process_frame
	gfx.set_process(false)
	root.scaling_3d_scale = 1.0
	var city := current_scene
	var block := city.get_node("ZombieBlock")
	block.spawner.enabled = false
	for z in get_nodes_in_group("zombies"): z.free()
	for c in root.get_children():
		if c is CanvasLayer and c != root.get_node("SceneLoader"): c.visible = false
	var set_ := city.get_node("GhettoSet")
	get_first_node_in_group("player").global_position = Vector3(-60, 0, 0)
	var cam := Camera3D.new()
	cam.fov = 75
	city.add_child(cam)
	cam.make_current()
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var env: Environment = city._env
	var moon := city.get_node("Moon") as DirectionalLight3D
	var facades := city.get_node("Facades") as Node3D
	var lights: Array = city.find_children("*", "Light3D", true, false).filter(func(l): return not (l is DirectionalLight3D) and not set_.is_ancestor_of(l))
	var decals: Array = city.find_children("*", "Decal", true, false).filter(func(d): return not set_.is_ancestor_of(d))
	var views := {"street": [Vector3(0, 1.65, 0.5), Vector3(40, 1.5, 0.5)], "north": [Vector3(26, 1.65, 1.5), Vector3(36, 1.5, -4)]}
	var saved := {"ssao": env.ssao_enabled, "ssil": env.ssil_enabled, "glow": env.glow_enabled, "fog": env.fog_enabled, "vol": env.volumetric_fog_enabled, "sdfgi": env.sdfgi_enabled, "ssr": env.ssr_enabled}
	var cfgs := ["all", "no_set", "no_set+moon_shadow", "no_set+ssao_ssil", "no_set+glow", "no_set+fog", "no_set+facades", "no_set+city_lights", "no_set+decals", "nothing_3d"]
	var res := {}
	for vname in views:
		for cfg in cfgs:
			set_.visible = cfg == "all"
			moon.shadow_enabled = not cfg.ends_with("moon_shadow")
			env.ssao_enabled = saved["ssao"] and not cfg.ends_with("ssao_ssil")
			env.ssil_enabled = saved["ssil"] and not cfg.ends_with("ssao_ssil")
			env.glow_enabled = saved["glow"] and not cfg.ends_with("glow")
			env.fog_enabled = saved["fog"] and not cfg.ends_with("fog")
			facades.visible = not cfg.ends_with("facades") and cfg != "nothing_3d"
			for l in lights: if is_instance_valid(l): l.visible = not cfg.ends_with("city_lights") and cfg != "nothing_3d"
			for d in decals: if is_instance_valid(d): d.visible = not cfg.ends_with("decals")
			for c in city.get_children():
				if c.name.begins_with("Cell_"): (c as Node3D).visible = cfg != "nothing_3d"
			cam.global_position = views[vname][0]
			cam.look_at(views[vname][1], Vector3.UP)
			for i in 30: await process_frame
			var sum := 0.0
			for i in 60:
				await process_frame
				sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			res["%s/%s" % [vname, cfg]] = sum / 60.0
	for k in res: print("PERF ", k, " ", snappedf(res[k], 0.01), " ms")
	print("PERF env ", saved)
	quit()
