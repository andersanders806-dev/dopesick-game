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
	while root.get_node("SceneLoader").busy() or current_scene == null or current_scene.name != "City3D":
		await process_frame
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready or block.cover == null or block.cover.points.is_empty():
		await process_frame
	story = block.story
	player = get_first_node_in_group("player") as Node3D
	holder = get_first_node_in_group("weapon_holder")
	holder.give(load("res://weapons/ar.tres"))
	holder.refill_all()
	_hook_story()
	say("in the block, wave %d, chapter %s" % [zm.round, story.chapter])
	await snap("block_start")
	var limit := float(args.get("limit", "1500"))
	var frames := 0
	while not zm.over and (Time.get_ticks_msec() / 1000.0 - t0) < limit:
		await process_frame
		frames += 1
		if frames % 30 == 0:
			fps_samples.append(Engine.get_frames_per_second())
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
	var busting := String(args.get("ending", "clean")) == "bust" and story.raid_active
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
	# Combat.
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

func _shoot_best(allow_turn: bool) -> bool:
	var cam := root.get_viewport().get_camera_3d()
	var best: Node3D
	var bd := INF
	for g in _alive_crew():
		var head: Vector3 = g.global_position + Vector3(0, 1.45 if not g.crouched else 0.95, 0)
		if _visible(cam.global_position, head):
			var d := g.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = g
	if best == null:
		return false
	_last_target_seen = Time.get_ticks_msec() / 1000.0
	_release_moves()
	var head: Vector3 = best.global_position + Vector3(0, 1.45 if not best.crouched else 0.95, 0)
	_face(head)
	if holder.can_fire():
		holder.fire()
	return true

func _walk(goal: Vector3) -> void:
	var map: RID = player.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, player.global_position, goal, true)
	var next := goal
	for pt in path:
		if Vector2(pt.x - player.global_position.x, pt.z - player.global_position.z).length() > 0.6:
			next = pt
			break
	var cam := root.get_viewport().get_camera_3d()
	_face(Vector3(next.x, cam.global_position.y, next.z))
	_release_moves()
	Input.action_press("move_up", 1.0)
	if Vector2(goal.x - player.global_position.x, goal.z - player.global_position.z).length() > 6.0:
		Input.action_press("sprint")
