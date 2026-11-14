extends SceneTree
## Perf probe INSIDE a room scene, looking out through its door, first person, Low + laptop mode, withdrawal
## off. Needs a real window. The same file runs on any tree (it only uses what the base has):
##   flock /home/anders/dopesick-game/.gpu.lock flatpak run org.godotengine.Godot --path . \
##     -s res://dev-tools/perf_door_room_probe.gd -- --no-sick <SceneName> <HH> [scale=1.0]
## Stands 3 m in front of the door nearest the spawn (group "doors"), a slow sway; prints one PERF line.
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	var room := "StorePharmacy3D"
	var hour := 14
	var fixed_scale := 0.0
	for a in args:
		var s := str(a)
		if s.begins_with("scale="):
			fixed_scale = float(s.substr(6))
		elif s.is_valid_int():
			hour = int(s)
		elif not s.begins_with("--") and not s.begins_with("off="):
			room = s
	await process_frame
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	gfx.set_preset(0)
	gfx.set_laptop_mode(true)
	root.get_node("Survival").enabled = false
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = hour * 60
	change_scene_to_file("res://world/%s.tscn" % room)
	for i in 200:
		await process_frame
	var player := get_first_node_in_group("player") as Node3D
	player.dialogue_active = false
	var best: Node3D = null
	var bd := 1e9
	for d in get_nodes_in_group("doors"):
		var dd := (d as Node3D).global_position.distance_to(player.global_position)
		if dd < bd:
			bd = dd
			best = d
	var away := player.global_position - best.global_position
	away.y = 0.0
	away = away.normalized()
	player.global_position = Vector3(best.global_position.x + away.x * 3.0, player.global_position.y, best.global_position.z + away.z * 3.0)
	var yaw := atan2(away.x, away.z)
	player.set_look(yaw, 0.0)
	player.reset_physics_interpolation()
	for i in 120:
		await process_frame
	# off=light,street,sign,door,all: switch a group of the door's things off (a bisect; trunk has none of them).
	var offs := ""
	for a in args:
		if str(a).begins_with("off="):
			offs = str(a).substr(4)
	if offs != "":
		for n in current_scene.find_children("*", "", true, false):
			var nm := String(n.name)
			var hit := false
			if "light" in offs and nm == "ExitGlow":
				hit = true
			elif "street" in offs and nm == "Street" and n is MeshInstance3D:
				hit = true
			elif "sign" in offs and nm == "ExitSign":
				hit = true
			elif "door" in offs and (nm == "BarDoor" or nm == "StoreDoor"):
				hit = true
			if hit:
				n.visible = false
	var rid := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var gpu: Array[float] = []
	var frame_ms: Array[float] = []
	var scales := 0.0
	var t_last := Time.get_ticks_usec()
	for i in 900:
		player.set_look(yaw + 0.3 * sin(i * 0.02), -0.03)
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
	print("PERF door-room %s %02d:00 gpu mean %.2f ms | frame mean %.2f p95 %.2f max %.2f | >25ms %d of %d | scale %.2f" % [
		room, hour, gsum / gpu.size(), fsum / frame_ms.size(), frame_ms[int(frame_ms.size() * 0.95)], frame_ms[-1], slow, frame_ms.size(), scales / frame_ms.size()])
	quit()
