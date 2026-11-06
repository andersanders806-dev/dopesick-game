extends SceneTree
## Demo bot: plays Ghetto Wars from the title screen through the story in a real window, with real input (the move
## actions, the interact key, the 1/2 keys at the choice, the weapon's fire()), and takes screenshots at every story
## beat into .pilot/gwrun_*.png. It cheats where a player would have to learn: it starts with the rifle and has its
## health topped up, except in the raid when told to bust (ending=bust).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/play_ghetto.gd -- [ending=clean|bust|bag] [batch=dump|sell] [limit=SECONDS]
## Without "no_sick" withdrawal is not simulated in this mode anyway (the mode keeps the story's clock still).

var out := ""
var args: Dictionary = {}
var zm: Node
var block: Node
var story: Node
var player: Node3D
var holder: Node
var t0 := 0.0
var shots := 0
var pending: Array = []
var fps_samples: Array[float] = []
var walk_goal := Vector3.INF
var t_block := 0.0
var _last_pos := Vector3.ZERO
var _last_kill := 0.0
var kills := 0
var _last_target_seen := 0.0
var _choice_open_t := -1.0
var _flush_hold := false
var log_lines: Array[String] = []

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	out = ProjectSettings.globalize_path("res://.pilot")
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_main()

func say(m: String) -> void:
	var line := "[%6.1fs] %s" % [(Time.get_ticks_msec() / 1000.0) - t0, m]
	print(line)
	log_lines.append(line)

func snap(label: String) -> void:
	if args.has("noshots"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	shots += 1
	root.get_texture().get_image().save_png("%s/gwrun_%02d_%s.png" % [out, shots, label])
	say("snap %02d %s (fps %d)" % [shots, label, Engine.get_frames_per_second()])

func snap_later(label: String, secs: float) -> void:
	pending.append([Time.get_ticks_msec() / 1000.0 + secs, label])

func _main() -> void:
	t0 = Time.get_ticks_msec() / 1000.0
	await process_frame
	zm = root.get_node("ZombieMode")
	if args.has("preset"):
		var gfx := root.get_node("Graphics")
		gfx.set_preset(gfx.Preset[String(args["preset"]).to_upper()])
		say("graphics preset " + String(args["preset"]))
	# --- The title
	change_scene_to_file("res://ui/TitleScreen.tscn")
	for i in 90:
		await process_frame
	await snap("title")
	var btn: Button
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text == "Ghetto Wars":
			btn = b
	btn.pressed.emit()
	say("pressed Ghetto Wars on the title")
	var lw := 0
	while root.get_node("SceneLoader").busy() or current_scene == null or current_scene.name != "City3D":
		await process_frame
		lw += 1
		if lw % 120 == 0:
			say("loading: scene %s busy %s" % [current_scene.name if current_scene else "-", root.get_node("SceneLoader").busy()])
	say("City3D is up")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	var waited := 0
	while not block.purchases_ready or block.cover == null or block.cover.points.is_empty():
		await process_frame
		waited += 1
		if waited % 120 == 0:
			say("waiting for the block: purchases %s cover %s" % [block.purchases_ready, block.cover != null and not block.cover.points.is_empty()])
	story = block.story
	player = get_first_node_in_group("player") as Node3D
	holder = get_first_node_in_group("weapon_holder")
	holder.give(load("res://weapons/ar.tres"))
	holder.refill_all()
	_hook_story()
	if args.has("startwave"):
		# Jump ahead (for iterating on a later chapter): the story's trigger for that wave runs as it would.
		var w := int(args["startwave"])
		for g in _alive_crew():
			g.queue_free()
		zm.round = w - 1
		block.spawner.enabled = true
		zm.start_round()
		say("jumped to wave %d" % w)
	t_block = Time.get_ticks_msec() / 1000.0
	say("in the block, wave %d, chapter %s" % [zm.round, story.chapter])
	await snap("block_start")
	var limit := float(args.get("limit", "1500"))
	var frames := 0
	while not zm.over and (Time.get_ticks_msec() / 1000.0 - t0) < limit:
		await process_frame
		frames += 1
		var tn := Time.get_ticks_usec()
		_dt = clampf((tn - _t_prev) / 1000000.0, 0.001, 0.2)
		_t_prev = tn
		if frames % 20 == 0 and (Time.get_ticks_msec() / 1000.0 - t_block) > 15.0:
			fps_samples.append(Engine.get_frames_per_second())
		if frames % 300 == 0:
			if player.global_position.distance_to(_last_pos) < 0.3 and walk_goal != Vector3.INF:
				var cols: Array = []
				for ci in (player as CharacterBody3D).get_slide_collision_count():
					var c := (player as CharacterBody3D).get_slide_collision(ci)
					cols.append("%s/%s n=%s" % [(c.get_collider() as Node).name, (c.get_collider() as Node).get_parent().name, c.get_normal().snapped(Vector3.ONE * 0.01)])
				say("STUCK: velocity %s collisions %s" % [player.velocity, cols])
				snap_later("stuck", 0.1)
			_last_pos = player.global_position
			say("pos %s goal %s crew %d wave %d bags %d hp %.0f fps %d" % [player.global_position.snapped(Vector3.ONE * 0.1), walk_goal, _alive_crew().size(), zm.round, story.bags, zm.health, Engine.get_frames_per_second()])
		_tick()
		var now := Time.get_ticks_msec() / 1000.0
		for p in pending.duplicate():
			if now >= p[0]:
				pending.erase(p)
				await snap(p[1])
		if story.finished and not _end_handled:
			_end_handled = true
			_after_end()
	var fps_min := 999.0
	var fps_sum := 0.0
	for f in fps_samples:
		fps_min = minf(fps_min, f)
		fps_sum += f
	say("run over: wave %d kills %d over=%s ending=%s story_finished=%s; fps avg %.0f min %.0f over %d samples" % [zm.round, zm.kills, zm.over, story.ending, story.finished, fps_sum / maxf(fps_samples.size(), 1), fps_min, fps_samples.size()])
	await snap("game_over" if zm.over else "timeout")
	var f := FileAccess.open(out + "/gwrun_log.txt", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	quit(0)

var _end_handled := false

func _after_end() -> void:
	say("ending card: %s" % story.ending)
	await get_process_frame_n(120)
	await snap("ending_" + story.ending)
	await get_process_frame_n(240)
	await snap("ending_" + story.ending + "_tally")
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_process_frame_n(30)

func get_process_frame_n(n: int) -> void:
	for i in n:
		await process_frame

func _hook_story() -> void:
	story.chapter_started.connect(func(id: String):
		say("chapter " + id + " (wave %d)" % zm.round)
		snap_later("chapter_" + id, 1.0))
	story.text_received.connect(func(from: String, body: String, _s: String):
		say("TEXT %s: %s" % [from, body])
		snap_later("text_" + from.to_lower(), 1.2))
	story.radio_line.connect(func(who: String, line: String):
		say("RADIO %s: %s" % [who, line]))
	story.scanner_line.connect(func(line: String):
		say("SCANNER: " + line)
		snap_later("scanner", 0.8))
	story.choice_offered.connect(func(_id: String, _o: Array):
		say("CHOICE offered")
		_choice_open_t = Time.get_ticks_msec() / 1000.0
		snap_later("choice", 1.0))
	story.beat.connect(func(id: String):
		say("beat " + id)
		if id in ["raid_start", "heli", "flushed", "drive_by", "ods_street", "cops_circling"]:
			snap_later("beat_" + id, 2.0))
	story.bags_changed.connect(func(have: int, total: int): say("bags %d/%d" % [have, total]))
	story.raid_started.connect(func():
		say("RAID started")
		snap_later("raid_a", 4.0)
		snap_later("raid_b", 9.0))
	root.get_node("GhettoMode").enemy_killed.connect(func(_e: Node, _h: String): _last_kill = Time.get_ticks_msec() / 1000.0)
	zm.round_started.connect(func(r: int): say("wave %d starts" % r))
	zm.round_ended.connect(func(r: int): say("wave %d cleared (kills %d)" % [r, zm.kills]))

func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "sprint"]:
		Input.action_release(a)

func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)

func _alive_crew() -> Array:
	return get_nodes_in_group("gangsters").filter(func(g): return is_instance_valid(g) and g.is_alive())

func _visible(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _face(p: Vector3) -> void:
	var cam := root.get_viewport().get_camera_3d()
	var from := cam.global_position
	var d := p - from
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.set_look(yaw, pitch)

## One frame of the bot: stay alive (unless busting), pick what to do, do it.
func _tick() -> void:
	if zm.over or story.finished:
		_release_moves()
		return
	var busting: bool = String(args.get("ending", "clean")) == "bust" and story.raid_active
	if not busting:
		zm.health = zm.MAX_HEALTH
		zm._since_hit = 0.0
	if holder.mag <= 5 and holder.reserve > 0 and not holder.reloading:
		holder.reload()
	if holder.reserve < 40:
		holder.refill_all()
	# The choice: look at the cards a moment, then take one.
	if story._choice != "":
		_release_moves()
		if Time.get_ticks_msec() / 1000.0 - _choice_open_t > 3.0:
			_key(KEY_1 if String(args.get("batch", "dump")) == "dump" else KEY_2)
			say("picked %s" % args.get("batch", "dump"))
		return
	# The stash bags, the sink, the car: walk (and while walking, no shooting).
	var goal := Vector3.INF
	var hold_interact := false
	if story.stash_started and story.bags < story.bag_total and not story.raid_active:
		for nm in story.Plot.BAG_NAMES:
			if not story._collected.has(nm):
				goal = story._point(nm)
				break
	if story.raid_active and not busting:
		var want_flush := String(args.get("ending", "clean")) != "bag"
		if want_flush and not story.is_flushed:
			goal = story._point("sink")
			if Vector2(goal.x - player.global_position.x, goal.z - player.global_position.z).length() < 1.4:
				hold_interact = true
		else:
			goal = story._point("car")
	if busting:
		_release_moves()
		_shoot_best(false)
		return
	if hold_interact:
		_release_moves()
		Input.action_press("interact")
		_flush_hold = true
		return
	elif _flush_hold:
		Input.action_release("interact")
		_flush_hold = false
	if goal != Vector3.INF:
		_walk(goal)
		return
	# Combat. A crew that has held its cover for a while is pushed: walk up on the nearest, firing when he shows.
	walk_goal = Vector3.INF
	var crew_all := _alive_crew()
	var since := Time.get_ticks_msec() / 1000.0 - maxf(_last_kill, t0)
	if since > 14.0 and not crew_all.is_empty():
		crew_all.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
		var near: Node3D = crew_all[0]
		if near.global_position.distance_to(player.global_position) > 7.0:
			if not _shoot_best(true, true):
				_walk(near.global_position)
			return
	if not _shoot_best(true):
		var crew := _alive_crew()
		if crew.is_empty():
			_release_moves()
		elif Time.get_ticks_msec() / 1000.0 - _last_target_seen > 10.0:
			# Nobody in sight for a while: close in on the nearest.
			crew.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
			if crew[0].global_position.distance_to(player.global_position) > 9.0:
				_walk(crew[0].global_position)
			else:
				_release_moves()
		else:
			_release_moves()

func _shoot_best(allow_turn: bool, advance := false) -> bool:
	var cam := root.get_viewport().get_camera_3d()
	var best: Node3D
	var bd := INF
	for g in _alive_crew():
		var head: Vector3 = g.global_position + Vector3(0, 1.45 if not g.crouched else 0.95, 0)
		if _visible(cam.global_position, head):
			var d: float = g.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = g
	if best == null:
		return false
	_last_target_seen = Time.get_ticks_msec() / 1000.0
	_release_moves()
	if advance and bd > 7.0:
		Input.action_press("move_up", 1.0)
	var head: Vector3 = best.global_position + Vector3(0, 1.45 if not best.crouched else 0.95, 0)
	_face(head)
	if holder.can_fire():
		holder.fire()
	return true

## The laundromat the way a player walks it: in by the front door, through the divider's door to the back room,
## out by the back door into the lane. (The navmesh is the street's: the building is not on it.)
func _in_laundromat(p: Vector3) -> bool:
	return p.x > 29.6 and p.x < 37.0 and p.z < -3.1 and p.z > -16.2

func _next_step(goal: Vector3) -> Vector3:
	var pp := player.global_position
	var in_now := _in_laundromat(pp)
	var in_goal := _in_laundromat(goal)
	if in_goal and not in_now:
		if Vector2(pp.x - 33.3, pp.z + 1.8).length() > 1.7:
			return Vector3.INF # the street: by the navmesh to the door first
		return Vector3(33.3, 0, -4.4)
	if in_now and in_goal:
		if goal.z < -10.2 and pp.z > -10.9:
			return Vector3(32.0, 0, -8.5) if (pp.z > -9.0 and absf(pp.x - 32.0) > 0.4) else Vector3(32.0, 0, -11.6)
		return goal
	if in_now and not in_goal:
		if pp.z > -10.2:
			return Vector3(33.3, 0, -1.8)
		return Vector3(35.2, 0, -17.6)
	return Vector3.INF

var _stuck_t := 0.0
var _dt := 0.016
var _t_prev := 0
var _unstick_left := 0.0
var _unstick_dir := 1.0

func _walk(goal: Vector3) -> void:
	walk_goal = goal
	# Snagged on a car or a corner for a few seconds: sidestep a moment like a player would.
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.4:
		_stuck_t += _dt
	else:
		_stuck_t = 0.0
	if _stuck_t > 2.0 and _unstick_left <= 0.0:
		_unstick_left = 1.6
		_unstick_dir = -_unstick_dir
		_stuck_t = 0.0
	if _unstick_left > 0.0:
		_unstick_left -= _dt
		_release_moves()
		Input.action_press("move_right" if _unstick_dir > 0 else "move_left", 1.0)
		Input.action_press("move_down", 0.5)
		return
	var cam := root.get_viewport().get_camera_3d()
	var step := _next_step(goal)
	var sprint := false
	if step != Vector3.INF:
		_face(Vector3(step.x, cam.global_position.y, step.z))
		_release_moves()
		Input.action_press("move_up", 1.0)
		return
	var target := goal
	if _in_laundromat(goal):
		target = Vector3(33.3, 0, -1.8)
	var map: RID = player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, player.global_position, target, true)
	var next := target
	for pt in path:
		if Vector2(pt.x - player.global_position.x, pt.z - player.global_position.z).length() > 0.6:
			next = pt
			break
	_face(Vector3(next.x, cam.global_position.y, next.z))
	_release_moves()
	Input.action_press("move_up", 1.0)
	if Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length() > 6.0:
		Input.action_press("sprint")
