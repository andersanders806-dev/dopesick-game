extends SceneTree
## Perf probe for the corner shop in first person on Low (laptop mode), withdrawal off, standing inside
## looking at the street door (x 3.5, z -2.4) with a slow sway. Needs a real window. Same file runs on any
## tree (it only uses what the base has):
##   flock /home/anders/dopesick-game/.gpu.lock flatpak run org.godotengine.Godot --path . \
##     -s res://dev-tools/perf_door_shop_probe.gd -- --no-sick [day|night] [scale=1.0]
## Prints one PERF line: GPU mean, frame mean/p95, frames > 25 ms and the settled render scale.
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var night := "night" in args
	var fixed_scale := 0.0
	for a in args:
		if str(a).begins_with("scale="):
			fixed_scale = float(str(a).substr(6))
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
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
	for i in 240:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	player.global_position = Vector3(3.5, 0.0, -8.0)
	player.set_look(PI, 0.0)
	player.reset_physics_interpolation()
	for i in 180:
		await process_frame
	var rid := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu: Array[float] = []
	var frame_ms: Array[float] = []
	var scales := 0.0
	var t_last := Time.get_ticks_usec()
	var n := 900
	for i in n:
		player.set_look(PI + 0.35 * sin(i * 0.02), -0.05)
		if fixed_scale > 0.0:
			gfx.render_scale = fixed_scale
			root.scaling_3d_scale = fixed_scale
		await process_frame
		var now := Time.get_ticks_usec()
		if i > 30:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			frame_ms.append((now - t_last) / 1000.0)
			scales += root.scaling_3d_scale
		t_last = now
	var gsum := 0.0
	for g in gpu: gsum += g
	var fsum := 0.0
	var slow := 0
	for f in frame_ms:
		fsum += f
		if f > 25.0: slow += 1
	frame_ms.sort()
	print("PERF door-shop %s gpu mean %.2f ms | frame mean %.2f p95 %.2f max %.2f | >25ms %d of %d | scale %.2f" % [
		"night" if night else "day", gsum / gpu.size(), fsum / frame_ms.size(), frame_ms[int(frame_ms.size() * 0.95)], frame_ms[-1], slow, frame_ms.size(), scales / frame_ms.size()])
	quit()
