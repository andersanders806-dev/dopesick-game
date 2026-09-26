extends SceneTree
## Stealth balance simulator. For each store, plays N trials of the naive
## approach -- walk in, walk straight to a random item, grab it, walk straight
## back out -- through real movement and the real guards, and reports how
## often the theft was spotted. A careful player watching the vision cones
## does better; this measures the floor of how dangerous each store is.
##   godot --headless --path . --fixed-fps 60 -s res://dev-tools/balance_sim.gd -- [trials]

const STORES := ["StoreSupermarket3D", "StoreConvenience3D", "StorePharmacy3D", "StoreLiquor3D", "StoreElectronics3D"]

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var trials := int(args[0]) if args.size() > 0 else 20
	var gs := root.get_node("GameState")
	var t0 := Time.get_ticks_msec()
	# Counted from the alarm itself: an arrest moves you to the jail, which
	# clears the wanted flag, so checking it afterwards would miss those.
	var spotted := [false]
	gs.wanted_changed.connect(func(w): if w: spotted[0] = true)
	for store_name in STORES:
		var caught := 0
		for t in trials:
			gs.wanted = false
			gs.in_custody = false
			gs.inventory.clear()
			spotted[0] = false
			var previous := current_scene
			change_scene_to_file("res://world/%s.tscn" % store_name)
			# Wait for the *new* instance (the same store reloads each trial).
			while current_scene == null or current_scene == previous or current_scene.name != store_name or get_first_node_in_group("player") == null:
				await process_frame
			for i in 5:
				await physics_frame
			var store := current_scene
			var player := get_first_node_in_group("player") as Node3D
			var item: Node3D = store.item_slots.pick_random()
			var entrance: Vector3 = player.global_position
			await _walk(player, item.global_position, func(): return is_instance_valid(player) and player._nearest_interactable() == item)
			if is_instance_valid(player):
				player._try_interact()
			for i in 50:
				await physics_frame
			await _walk(player, entrance, func(): return is_instance_valid(player) and player.global_position.distance_to(entrance) < 0.6)
			for i in 20:
				await physics_frame
			if spotted[0]:
				caught += 1
			# If they were arrested, let the jail finish loading first.
			while gs.in_custody:
				await process_frame
			for cop in get_nodes_in_group("police"):
				cop.queue_free()
			gs.set_wanted(false)
		print("%-20s caught %2d / %d  (%3d%%)" % [store_name, caught, trials, round(100.0 * caught / trials)])
	print("sim time: %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

## `player` is untyped on purpose: an arrest frees it mid-trial.
func _walk(player, goal: Vector3, done: Callable) -> void:
	if not is_instance_valid(player):
		return
	var map: RID = player.get_world_3d().navigation_map
	for i in 900:
		if not is_instance_valid(player) or player.get_tree() == null or root.get_node("GameState").in_custody:
			break
		if done.call():
			break
		var path := NavigationServer3D.map_get_path(map, player.global_position, goal, true)
		var next := goal
		for pt in path:
			if Vector2(pt.x - player.global_position.x, pt.z - player.global_position.z).length() > 0.35:
				next = pt
				break
		var dir := Vector2(next.x - player.global_position.x, next.z - player.global_position.z).normalized()
		for a in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(a)
		if dir.x > 0: Input.action_press("move_right", dir.x)
		elif dir.x < 0: Input.action_press("move_left", -dir.x)
		if dir.y > 0: Input.action_press("move_down", dir.y)
		elif dir.y < 0: Input.action_press("move_up", -dir.y)
		await physics_frame
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
