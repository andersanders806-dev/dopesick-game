extends SceneTree
## Dev helper: two first-person beats for the fix-round sheet -> <out>/<mode>_*.png (one mode per run; a window).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_fix1.gd -- <out_dir> <guard|pusher|south>
## guard:  sprint straight at a shop guard from 6 m; the frame where the eyes are nearest, then the view a moment later.
## pusher: stand with your back to the dealer, press E: before, and after the view has turned to him.
var out := ""

func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, label])

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var args := OS.get_cmdline_user_args()
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	var gs := root.get_node("GameState")
	gs.start_run()
	gs.no_sickness = true
	gs.craving = 90.0
	gs.intro_pending = false
	gs.clock_running = false
	gs.clock = 14 * 60
	root.get_node("Graphics").set_preset(0)
	root.get_node("Survival").enabled = false
	if args[1] == "guard":
		change_scene_to_file("res://world/StoreConvenience3D.tscn")
		await _frames(90)
		var p := get_first_node_in_group("player") as Node3D
		var guard := get_nodes_in_group("guards")[0] as Node3D
		var gp := guard.global_position
		print("guard at ", gp)
		# Start 5 m from him on a line the room leaves clear, and face him.
		var space: PhysicsDirectSpaceState3D = current_scene.get_world_3d().direct_space_state
		var start := gp + Vector3(4.5, 0.0, 0.0)
		for k in 16:
			var a := TAU * k / 16.0
			var cand := gp + Vector3(cos(a), 0.0, sin(a)) * 5.0
			var floor_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(cand + Vector3(0, 1, 0), cand + Vector3(0, -1, 0), 1 | 16))
			var wall_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(cand + Vector3(0, 1.0, 0), gp + Vector3(0, 1.0, 0), 1))
			if not floor_hit.is_empty() and wall_hit.is_empty():
				start = cand
				break
		p.global_position = start
		p.reset_physics_interpolation()
		var to_g := gp - start
		p.set_look(atan2(-to_g.x, -to_g.z), 0.0)
		await _frames(10)
		Input.action_press("sprint")
		Input.action_press("move_up")
		var best := 99.0
		var shot := false
		for i in 150:
			await process_frame
			var d := Vector2(p.camera.global_position.x - gp.x, p.camera.global_position.z - gp.z).length()
			best = minf(best, d)
			if not shot and d < 1.2:
				shot = true
				await _snap("guard_nearest")
		Input.action_release("sprint")
		Input.action_release("move_up")
		print("nearest eye distance ", best)
		await _snap("guard_after")
	elif args[1] == "pusher":
		change_scene_to_file("res://world/City3D.tscn")
		await _frames(120)
		var pusher := current_scene.get_node("Pusher") as Area3D
		var waited := 0
		while waited < 1800 and not (pusher.state == pusher.State.POST and pusher.global_position.distance_to(Vector3(14.0, 0, -3.5)) < 3.0):
			await _frames(10)
			waited += 10
		var p := get_first_node_in_group("player") as Node3D
		p.global_position = pusher.global_position + Vector3(-1.4, 0.0, 0.0)
		p.reset_physics_interpolation()
		# Looking at his chest but a little off to the side: he is what E would use, and not yet in the middle.
		var to_d: Vector3 = pusher.global_position + Vector3(0, 1.1, 0) - p.camera.global_position
		p.set_look(atan2(-to_d.x, -to_d.z) + 0.16, atan2(to_d.y, Vector2(to_d.x, to_d.z).length()))
		await _frames(20)
		print("E would use: ", p._nearest_interactable())
		await _snap("pusher_before")
		p._try_interact()
		# The view turns over 0.4 s; the deal's menu opens over it a moment later.
		await _frames(30)
		# The deal's menu opens at once over the view: put it away to see where the view was left.
		for c in root.get_children():
			if c is CanvasLayer and (c.has_method("open") or c.has_method("open_with") or c.has_method("start")):
				c.queue_free()
		p.dialogue_active = false
		await _frames(4)
		await _snap("pusher_after")
	elif args[1] == "south":
		gs.set_raining(false)
		change_scene_to_file("res://world/City3D.tscn")
		await _frames(120)
		var p := get_first_node_in_group("player") as Node3D
		p.set_look(PI, 0.05)
		await _frames(30)
		await _snap("south_day")
		gs.clock = 21 * 60 + 30
		gs.clock_changed.emit(gs.clock)
		gs.craving = 90.0
		p.set_look(PI + 0.15, 0.3)
		await _frames(60)
		await _snap("south_night")
	quit()
