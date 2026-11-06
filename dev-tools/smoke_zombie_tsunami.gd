extends "res://dev-tools/smoke_test_3d.gd"
## The tsunami after the quake (zombie mode, task Z4c): the countdown, the two Drowned, the cancel, the wave.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_tsunami.gd
func _run() -> void:
	await _zombie_tsunami_checks(_gs())

func _wait_secs(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		await process_frame

func _wait_until(cond: Callable, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < seconds:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func _tsunami_block() -> Node:
	var zm := root.get_node("ZombieMode")
	zm.begin(true)
	var city := await _load("res://world/City3D.tscn")
	await _frames(8)
	var block := city.get_node("ZombieBlock")
	block.spawner.enabled = false
	block.spawner.adaptive = false
	block.surge.enabled = false
	for z in get_nodes_in_group("zombies"):
		z.free()
	return block

func _kill(z: Node) -> void:
	z.take_hit("torso", 1.0e9, Vector3.FORWARD)

# --- The physical walk to the high ground (the navmesh ignores barricades; the player cannot) ---

## The way to the stair that never passes an alley barricade: from where you start to the east end of Main
## Street, down the east avenue, through the camp fence's gap and the lot fence's gap (world/HighGround.gd), across
## the lot to the stair's foot and up. Hand anchors, joined by navmesh paths between them.
const WALK_ANCHORS := [Vector3(75.5, 0, -3.0), Vector3(75.5, 0, -40.5), Vector3(68.0, 0, -41.0)]
## Then by hand (the baked zombie navmesh has the lot's fence closed): through the gap in the camp's fence and the
## lot's, across the lot to the stair's foot, up the stair and onto the deck.
const GATE_RUN := [Vector3(57.5, 0, -42.5), Vector3(46.0, 0, -40.0), Vector3(38.5, 0, -36.0), Vector3(38.5, 0, -29.5),
	Vector3(46.0, 0, -29.5), Vector3(62.0, 0, -29.5)]

func _walk_route(map: RID, start: Vector3, anchors: Array) -> PackedVector3Array:
	var pts := PackedVector3Array([start])
	var from := start
	for a in anchors:
		var seg: PackedVector3Array = NavigationServer3D.map_get_path(map, from, a, true)
		for i in range(1, seg.size()):
			pts.append(Vector3(seg[i].x, 0.0, seg[i].z))
		from = a
	for q in GATE_RUN:
		pts.append(q)
	return pts

## Distance (on the ground plane) from `p` to a barricade's boards (a segment `width` wide through its centre).
func _barricade_gap(b: Node3D, p: Vector3) -> float:
	var half: float = float(b.get("width")) * 0.5
	var axis := b.global_transform.basis.x
	var c := b.global_position
	var a2 := Vector2(c.x - axis.x * half, c.z - axis.z * half)
	var b2 := Vector2(c.x + axis.x * half, c.z + axis.z * half)
	var q := Vector2(p.x, p.z)
	var ab := b2 - a2
	var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return q.distance_to(a2 + ab * t)

func _high_ground_walk_checks(block: Node, player: CharacterBody3D, hg: Node3D) -> void:
	var bars: Array = get_nodes_in_group("barricades")
	var boarded := bars.size() >= 2
	for b in bars:
		boarded = boarded and int(b.get("boards")) == int(b.get("BOARD_COUNT"))
	_check(boarded, "  walk to the high ground: all %d barricades fully boarded" % bars.size())
	var gs := root.get_node("GameState")
	var was_sick: bool = gs.no_sickness
	gs.no_sickness = true
	hg.up.clear()
	var map: RID = block.city.get_world_3d().navigation_map
	var starts := {
		"Main Street west end": Vector3(-60.0, 0.0, -3.0), "Main Street east end": Vector3(60.0, 0.0, -3.0),
		"west avenue": Vector3(-68.0, 0.0, -30.0), "east avenue": Vector3(74.0, 0.0, -30.0)}
	var worst := 0.0
	for label in starts:
		var start: Vector3 = starts[label]
		var anchors: Array = WALK_ANCHORS.duplicate()
		if label == "west avenue":
			anchors = [Vector3(-68.0, 0, -3.0)] + anchors
		elif label == "east avenue":
			anchors = anchors.slice(1)
		var route := _walk_route(map, start, anchors)
		var near := 1.0e9
		for pt in route:
			for b in bars:
				near = minf(near, _barricade_gap(b, pt))
		_check(near > 1.5, "  %s: the route (%d points) stays %.1f m from the boards" % [label, route.size(), near])
		player.global_position = start
		player.velocity = Vector3.ZERO
		await _frames(3)
		var r := await _walk_route_physically(player, route, hg, 90.0, bars)
		worst = maxf(worst, float(r["secs"]))
		_check(bool(r["ok"]), "  %s: the real player ends in the zone after %.0f s (stuck at %s, nearest board %.1f m)" % [label, r["secs"], r["where"], r["near"]])
		_check(float(r["near"]) > 1.0, "  %s: never closer than %.1f m to a board" % [label, r["near"]])
	print("WALK worst run time to the zone: %.1f s" % worst)
	_check(worst < 70.0, "  the farthest start is %.0f s from the zone at a sprint (well inside 2:00)" % worst)
	Input.action_release("move_up")
	Input.action_release("sprint")
	gs.no_sickness = was_sick
	hg.up.clear()
	player.global_position = Vector3(10.0, 0.0, 1.5)
	player.velocity = Vector3.ZERO
	await _frames(3)

## Drives the real CharacterBody3D along `route` with the move/sprint input (physics ticks, so the seconds are
## game seconds). Returns {ok, secs, where, near}.
func _walk_route_physically(player: CharacterBody3D, route: PackedVector3Array, hg: Node3D, limit: float, bars: Array) -> Dictionary:
	var ticks := 0
	var i := 1
	var near := 1.0e9
	var last := player.global_position
	var stuck := 0
	Input.action_press("move_up")
	Input.action_press("sprint")
	var max_ticks := int(limit * Engine.physics_ticks_per_second)
	while ticks < max_ticks and not hg.zone_contains(player.global_position):
		await physics_frame
		ticks += 1
		# (a pad lying on the desk can send a zero axis event that lets go of the held action: hold it)
		Input.action_press("move_up")
		Input.action_press("sprint")
		var pos := player.global_position
		for b in bars:
			near = minf(near, _barricade_gap(b, pos))
		var target: Vector3 = route[mini(i, route.size() - 1)]
		var to := target - pos
		to.y = 0.0
		if to.length() < 0.9 and i < route.size() - 1:
			i += 1
			continue
		# past the last point of the route: keep to the deck
		player.set_look(atan2(-to.x, -to.z), 0.0)
		if Vector2(pos.x - last.x, pos.z - last.z).length() < 0.01:
			stuck += 1
		else:
			stuck = 0
		last = pos
		if stuck > 120:
			break
	Input.action_release("move_up")
	Input.action_release("sprint")
	return {"ok": hg.zone_contains(player.global_position), "secs": float(ticks) / Engine.physics_ticks_per_second,
		"where": player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), "near": near}

func _zombie_tsunami_checks(_gs: Node) -> void:
	await _section("Dead Block: the tsunami -- countdown, two Drowned, cancel, wave")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	var gfx := root.get_node("Graphics")
	gfx.camera_motion = true
	var master := AudioServer.get_bus_index("Master")
	var base_fx := AudioServer.get_bus_effect_count(master)

	# --- Starts AT the quake: the first always, later ones by chance ---
	var block := await _tsunami_block()
	var ts: Node = block.tsunami
	var player := _player()
	_check(ts != null and ts.phase == ts.Phase.IDLE and not zm.tsunami_active, "  the block has a tsunami director, idle")
	ts.later_chance = 0.0
	zm.surge_ended.emit()
	await _frames(3)
	_check(ts.phase == ts.Phase.IDLE, "  the quake's end does not start it")
	zm.surge_started.emit()
	await _frames(3)
	_check(ts.phase == ts.Phase.COUNTDOWN and zm.tsunami_active, "  the first quake brings it, as it hits")
	_check(ts.duration == 120.0 and ts.remaining > 119.0 and ts.remaining <= 120.0, "  the countdown starts at 120 s (%.2f)" % ts.remaining)
	_check(ts.drowned.size() == 2, "  the Drowned come up as it hits")
	_check(ts.hud.time_text == "2:00" or ts.hud.time_text == "1:59", "  the HUD shows it (%s)" % ts.hud.time_text)
	_check(ts.hud.needed == 2 and ts.hud.tracker_label.text.begins_with("DROWNED  0 / 2"), "  DROWNED 0 / 2 (%s)" % ts.hud.tracker_label.text)
	_check(ts.hud.banner.position.y < -200.0, "  the broadcast card waits (the RICHTER readout is not covered)")
	_check(not ts.warned and ts.remaining == 120.0 and not ts.hud.shown, "  the clock waits, still 2:00, until the warning is given")
	_check(await _wait_until(func(): return ts.warned, 5.0), "  the warning comes a few seconds after the quake (%.1f s)" % ts.INTRO)
	_check(absf(ts.remaining - 120.0) < 0.2 and ts.hud.shown and ts.hud.time_text == "2:00", "  and it reads 2:00 when it appears (%.2f, %s)" % [ts.remaining, ts.hud.time_text])
	await _wait_secs(1.2)
	_check(ts.hud.banner.position.y > -60.0, "  and slides in a few seconds after the quake started (y %.0f)" % ts.hud.banner.position.y)
	var seismo_left: float = ts.hud.get_viewport().get_visible_rect().size.x - 358.0
	_check(ts.hud.banner.position.x + ts.hud.banner.size.x <= seismo_left + 0.5, "  and stays left of the seismograph (right edge %.0f of %.0f)" % [ts.hud.banner.position.x + ts.hud.banner.size.x, seismo_left])
	ts._finish()
	_check(ts.phase == ts.Phase.IDLE and not zm.tsunami_active, "  finished: idle again")
	zm.surge_started.emit()
	await _frames(3)
	_check(ts.phase == ts.Phase.IDLE, "  the second quake (chance 0) brings none")
	ts.later_chance = 1.0
	zm.surge_started.emit()
	await _frames(3)
	_check(ts.phase == ts.Phase.COUNTDOWN, "  the third (chance 1) does")
	ts._finish()

	# --- The two Drowned ---
	var points0: int = zm.points
	var health0: float = float(zm.zombie_health(maxi(zm.round, 1)))
	ts.start()
	await _frames(4)
	var d: Array = ts.drowned
	_check(d.size() == 2 and d[0].is_in_group("zombies") and d[1].is_in_group("zombies"), "  two Drowned spawned, in the zombie group")
	var pp: Vector3 = player.global_position
	var a: Vector3 = d[0].global_position - pp
	var b: Vector3 = d[1].global_position - pp
	a.y = 0.0
	b.y = 0.0
	var ang := rad_to_deg(a.angle_to(b))
	_check(a.length() >= 14.0 and b.length() >= 14.0, "  both far from the player (%.0f m, %.0f m)" % [a.length(), b.length()])
	_check(ang >= 60.0 and d[0].global_position.distance_to(d[1].global_position) > 25.0, "  on different sides: %.0f degrees apart, %.0f m between" % [ang, d[0].global_position.distance_to(d[1].global_position)])
	_check(d[0].side == "sea" and d[1].side == "inland", "  one on the sea side, one inland")
	_check(absf(d[0].max_health - health0 * 3.0) < 1.0, "  3 times the health of a normal zombie (%.0f vs %.0f)" % [d[0].max_health, health0])
	_check(d[0].is_inside_tree() and d[0].entrance == "rise", "  they rise out of the ground")
	await _wait_secs(3.6)
	var head_y: float = (d[0]._skeleton.global_transform * d[0]._skeleton.get_bone_global_pose(d[0]._skeleton.find_bone("Bip01 Head")).origin).y
	_check(head_y > 1.9 and head_y < 2.6, "  about 2.2 m tall (head bone at %.2f m)" % head_y)
	_check(not d[0].hitboxes.is_empty() and d[0].hitboxes["head"].get_child_count() > 0, "  hit zones, scaled with the body")
	_check(ts.remaining < 119.9 and ts.remaining > 110.0, "  the clock runs (%.1f)" % ts.remaining)
	_check(absf(ts.hud.targets.size() - 2.0) < 0.1 and ts.dread > 0.0 and ts.dread < 0.1, "  the HUD tracks both, the dread has begun (%.3f)" % ts.dread)

	# --- Easy to kill: helmet, stagger, a head shot stops a charge ---
	var z: Node = d[1]
	var mh: float = z.max_health
	var h0: float = z.health
	z.take_hit("head", 10.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 10.0) < 0.5 and z.helmet_on, "  a headshot does its full damage, the helmet holding for now (%.1f)" % (h0 - z.health))
	h0 = z.health
	z.take_hit("torso", 20.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 20.0) < 0.5, "  the body takes it all")
	var broke := [false]
	z.helmet_broke.connect(func(_x): broke[0] = true)
	var shots := 1
	while z.helmet_on and shots < 20:
		z.take_hit("head", 10.0, Vector3.FORWARD)
		shots += 1
	_check(broke[0] and not z.helmet_on and not z._helmet_node.visible and shots <= 3, "  the helmet breaks off after %d head hits" % shots)
	h0 = z.health
	z.take_hit("head", 10.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 10.0) < 0.5, "  and headshots stay at full damage")
	z.health = mh
	z.state = z.State.CHASE
	z.charge = z.Charge.NONE
	z._stagger = 0.0
	z.take_hit("torso", mh * 0.04, Vector3.FORWARD)
	var small_stagger: float = z._stagger
	z._stagger = 0.0
	z._burst = 0.0
	z.take_hit("torso", mh * 0.1, Vector3.FORWARD)
	var heavy_stagger: float = z._stagger
	_check(small_stagger == 0.0 and heavy_stagger > 0.0, "  one heavy hit staggers it (%.2f vs %.2f)" % [small_stagger, heavy_stagger])
	z._stagger = 0.0
	z._burst = 0.0
	z._burst_t = 0.0
	for i in 3:
		z.take_hit("torso", mh * 0.045, Vector3.FORWARD)
	_check(z._stagger > 0.0, "  so do three quick hits (%.2f)" % z._stagger)
	z.health = mh
	# a head hit in the middle of a charge stops it
	z._stagger = 0.0
	z.state = z.State.CHASE
	z._start_windup(Vector3.FORWARD)
	_check(z.charge == z.Charge.WINDUP, "  a charge starts with a roar and a stomp (windup %.1f s)" % z.WINDUP)
	z.take_hit("head", 5.0, Vector3.FORWARD)
	_check(z.charge == z.Charge.RECOVER and z.interrupted == 1, "  a bullet to the head stops it")
	z.charge = z.Charge.NONE
	z._stagger = 0.0
	z.health = mh
	_check(z.is_alive() and z.health > 0.0, "  and it is alive")
	z.health = z.max_health

	# --- The charge: a roar, a run in a line, a throw ---
	var street := Vector3(0.0, 0.0, 6.0)
	player.global_position = street
	player.velocity = Vector3.ZERO
	zm.health = zm.MAX_HEALTH
	for dd in d:
		dd.global_position = Vector3(500, -50, 500)
		dd.set_physics_process(false)
	var c: Node = d[0]
	c.set_physics_process(true)
	var placed := false
	for yaw in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, yaw * TAU / 16.0)
		var spot := street + dir * 12.0
		c.global_position = spot
		await _frames(1)
		if c._line_free(street - spot) and not c._blocked((street - spot).normalized() * 4.0):
			placed = true
			break
	_check(placed, "  found a clear run at the player to try the charge")
	c.target = player
	c.state = c.State.CHASE
	c._stagger = 0.0
	c._charge_cd = 0.0
	c._slot = -1
	var low_hp := [zm.MAX_HEALTH]
	zm.health_changed.connect(func(h): low_hp[0] = minf(low_hp[0], h))
	var got_windup := await _wait_until(func(): return c.charge == c.Charge.WINDUP, 2.0)
	_check(got_windup, "  it stops and roars first (windup)")
	var got_rush := await _wait_until(func(): return c.charge == c.Charge.RUSH or c.charges_made > 0, 3.0)
	_check(got_rush, "  then comes at a run")
	var spd := 0.0
	var t0 := Time.get_ticks_msec()
	var before_hit := player.global_position
	while float(Time.get_ticks_msec() - t0) < 3000.0 and c.charge_hits == 0:
		spd = maxf(spd, Vector2(c.velocity.x, c.velocity.z).length())
		await physics_frame
	_check(spd > 6.0, "  at %.1f m/s" % spd)
	_check(c.charge_hits == 1 and low_hp[0] < zm.MAX_HEALTH, "  the charge lands and hurts (health went down to %.0f)" % low_hp[0])
	before_hit = player.global_position
	await _wait_secs(0.5)
	var thrown := player.global_position.distance_to(before_hit)
	_check(thrown > 1.5, "  and throws the player back (%.1f m)" % thrown)
	c.global_position = Vector3(500, -50, 500)
	c.set_physics_process(false)
	zm.health = zm.MAX_HEALTH
	_check(ts.phase == ts.Phase.COUNTDOWN and ts.remaining > 100.0, "  the clock kept running through all that")

	# --- The pause menu stops the clock ---
	var r0: float = ts.remaining
	paused = true
	await _frames(30)
	var r1: float = ts.remaining
	paused = false
	await _frames(20)
	_check(absf(r1 - r0) < 0.05 and ts.remaining < r1, "  the timer pauses with the pause menu (%.2f -> %.2f -> %.2f)" % [r0, r1, ts.remaining])

	# --- Dread over the time ---
	var night: Dictionary = block.city._night
	var base_sky: Color = ts._base_env["sky"]
	ts.skip_to(80.0)
	await _frames(4)
	var sky80: Color = night["sky"]
	ts.skip_to(20.0)
	await _frames(4)
	var sky20: Color = night["sky"]
	_check(sky20.g > sky80.g and sky80.g > base_sky.g and sky20.r < base_sky.r, "  the sky goes darker and greener with the clock")
	_check(ts.wave_h > 0.0 and ts.wave.visible and ts.wave_h < ts.WAVE_HEIGHT.y, "  at 0:20 the wave stands on the horizon (%.0f m high, %.0f m off)" % [ts.wave_h, ts.wave_dist])
	var h20: float = ts.wave_h
	ts.skip_to(5.0)
	await _wait_secs(1.0)
	_check(ts.wave_h > h20 and ts.seep > 0.1, "  it rises, and the water seeps in (wave %.0f m, seep %.2f)" % [ts.wave_h, ts.seep])
	_check(ts._loop("heart2") != null and ts._loop("roar") != null and ts._loop("siren") != null and ts._loop("wind") != null, "  siren, wind, roar and the fast heartbeat all playing")
	_check(ts.hud.wave_marker, "  the wave has its marker on the HUD")
	ts.skip_to(60.0)
	ts.remaining = 100.0
	await _frames(2)

	# --- Cancel: kill both ---
	var kills_seen := [0]
	ts.drowned_killed.connect(func(n): kills_seen[0] = n)
	var points_before: int = zm.points
	ts.skip_to(40.0)
	_kill(d[0])
	await _frames(4)
	_check(ts.kills == 1 and ts.phase == ts.Phase.COUNTDOWN and ts.hud.tracker_label.text.begins_with("DROWNED  1 / 2"), "  one down: 1 / 2, the clock goes on")
	_kill(d[1])
	await _frames(6)
	_check(ts.phase == ts.Phase.CANCELLED and kills_seen[0] == 2, "  two down: cancelled")
	_check(zm.points - points_before >= 2000 and ts.bonus_paid == 2000 and ts.bonus_count == 1, "  +2000 once (%d)" % (zm.points - points_before))
	_check(ts.slowmo_active and Engine.time_scale < 0.5, "  slow motion on the second kill (x%.2f)" % Engine.time_scale)
	_check(not zm.tsunami_active, "  the tsunami flag is off")
	var done := await _wait_until(func(): return ts.phase == ts.Phase.IDLE, 12.0)
	_check(done, "  the relief plays out and it is over")
	_check(Engine.time_scale == 1.0 and not ts.slowmo_active and AudioServer.playback_speed_scale == 1.0, "  time is back to normal")
	_check(is_equal_approx((night["sky"] as Color).g, base_sky.g) and is_equal_approx(float(night["fog_density"]), block.city._env.fog_density), "  the sky and fog are put back")
	_check(not ts.wave.visible and not ts._water.visible and ts._audio.is_empty(), "  the wave sank, the water drained, the loops stopped")
	var players := 0
	for ch in ts.get_children():
		if ch is AudioStreamPlayer and ch.playing:
			players += 1
	_check(players <= 1, "  nothing still playing but the relief tail (%d)" % players)
	_check(ts.bonus_count == 1 and zm.points - points_before < 2100, "  and no second bonus")
	_check(AudioServer.get_bus_effect_count(master) == base_fx, "  no leftover audio filter")
	_check(ts.hud.cancel_banner.modulate.a >= 0.0 and not ts.hud.timer_label.visible, "  the HUD cleared")

	# --- The high ground: a stair up to the overpass deck, a safe zone, a beacon, a marker ---
	var hg: Node3D = block.high_ground
	_check(hg != null and hg.zone_center().y > 11.0 and not hg.lit, "  the block has a high ground (the overpass deck at %.1f m), its beacon dark" % hg.DECK_Y)
	var nav_map: RID = block.city.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(nav_map)
	var route: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(10.0, 0.3, 1.5), hg.zone_center() + Vector3(0, 0.3, 0), true)
	var route_len := 0.0
	for i in range(1, route.size()):
		route_len += route[i].distance_to(route[i - 1])
	_check(route.size() > 5 and route[route.size() - 1].y > 11.0 and route[route.size() - 1].distance_to(hg.zone_center() + Vector3(0, 0.3, 0)) < 3.0, "  the zone is reachable on the navmesh from Main Street (%d points, %.0f m)" % [route.size(), route_len])
	var far: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(-60.0, 0.3, -3.0), hg.zone_center() + Vector3(0, 0.3, 0), true)
	var far_len := 0.0
	for i in range(1, far.size()):
		far_len += far[i].distance_to(far[i - 1])
	_check(far.size() > 5 and far_len > 100.0 and far_len < 260.0, "  from the far west end it is %.0f m, about %.0f s at a run" % [far_len, far_len / (player.BASE_SPEED * player.SPRINT_MULT)])
	await _high_ground_walk_checks(block, player, hg)
	player.global_position = Vector3(46.0, 0.0, -29.5)
	await _frames(4)
	_check(absf(player.global_position.y - hg.height_at_x(46.0)) < 0.05 and not hg.is_up(player), "  on the stair the player is lifted along it (y %.2f of %.2f)" % [player.global_position.y, hg.height_at_x(46.0)])
	player.global_position = Vector3(55.8, player.global_position.y, -29.5)
	await _frames(3)
	player.global_position = Vector3(60.0, player.global_position.y, -29.5)
	await _frames(3)
	_check(hg.is_up(player) and absf(player.global_position.y - hg.DECK_Y) < 0.05 and hg.zone_contains(player.global_position), "  walking off the top puts it on the deck, in the zone (y %.2f)" % player.global_position.y)
	player.global_position = Vector3(60.0, player.global_position.y, -48.0)
	await _frames(3)
	_check(not hg.zone_contains(player.global_position), "  and past the barrier is not")
	hg.put_up(player, hg.zone_center())
	player.velocity = Vector3.ZERO
	# a runner at the foot of the stair follows up it; one under the deck cannot claw through it
	block.spawner.enabled = false
	var chaser: Node = block.spawner.spawn_one("runner", Vector3(38.5, 0.0, -26.0))
	var under: Node = block.spawner.spawn_one("walker", Vector3(61.0, 0.0, -29.0))
	var hp_before: float = zm.health
	var climbed := await _wait_until(func(): return is_instance_valid(chaser) and chaser.global_position.y > 8.0, 25.0)
	_check(climbed, "  the dead follow you up the stair (y %.1f)" % (chaser.global_position.y if is_instance_valid(chaser) else -1.0))
	_check(zm.health >= hp_before - 0.1 or (is_instance_valid(chaser) and chaser.global_position.y > 8.0), "  the one under the deck did not claw through it (health %.0f)" % zm.health)
	for zz in get_nodes_in_group("zombies"):
		zz.queue_free()
	await _frames(3)
	zm.health = zm.MAX_HEALTH

	# on the deck at 0:00: the wave passes below, the street's dead are swept, play goes on
	hg.put_up(player, hg.zone_center())
	var street_dead: Array = []
	for i in 3:
		street_dead.append(block.spawner.spawn_one("walker", Vector3(40.0 + i * 3.0, 0.0, -45.0)))
	var roof_dead: Node = block.spawner.spawn_one("walker", Vector3(0, 0, 0))
	hg.put_up(roof_dead, hg.zone_center() + Vector3(2.0, 0, 3.0))
	roof_dead.set_physics_process(false)
	var pts_before: int = zm.points
	ts.flood_hold = 1.0
	ts.flood_recede = 1.5
	ts.start(30.0)
	_check(not hg.lit and not ts.hud.safe_marker, "  no beacon or marker before the warning is given")
	await _wait_until(func(): return ts.warned, 6.0)
	await _frames(4)
	_check(hg.lit and ts.hud.safe_here and not ts.hud.safe_marker, "  the beacon is lit; standing in the zone shows a SAFE chip, not the marker")
	hg.up.clear()
	player.global_position = Vector3(-20.0, 0.0, -3.0)
	await _frames(3)
	_check(ts.hud.safe_marker and not ts.hud.safe_here and ts.hud.safe_at.y > 12.0, "  out in the street the HIGH GROUND marker points at the beacon (%.0f m up)" % ts.hud.safe_at.y)
	hg.put_up(player, hg.zone_center())
	await _frames(3)
	for dd in ts.drowned:
		dd.global_position = Vector3(500, -50, 500)
		dd.set_physics_process(false)
	ts.skip_to(0.3)
	await _wait_until(func(): return ts.phase == ts.Phase.WAVE, 3.0)
	_check(ts.survive and ts.phase == ts.Phase.WAVE, "  in the zone at 0:00: it is a wave to live through")
	await _wait_until(func(): return ts.fired.has("impact"), 5.0)
	await _frames(4)
	var all_swept := true
	for sd in street_dead:
		all_swept = all_swept and (not is_instance_valid(sd) or not sd.is_alive())
	_check(all_swept and ts.swept >= 3, "  the street's dead are swept away (%d)" % ts.swept)
	_check(is_instance_valid(roof_dead) and roof_dead.is_alive(), "  the one up on the deck is not")
	_check(not zm.over and zm.points - pts_before >= 500 and zm.points - pts_before < 700, "  alive, and a small bonus (+%d)" % (zm.points - pts_before))
	await _wait_secs(1.5)
	_check(ts.water_level > 3.0 and ts._water.visible, "  the water stands in the street (%.1f m)" % ts.water_level)
	_check(zm.surge_busy, "  the horde waits while it does")
	var ended := await _wait_until(func(): return ts.phase == ts.Phase.IDLE, 10.0)
	_check(ended and ts.water_level < 0.05 and not zm.surge_busy and not zm.over and zm.active, "  the water goes and play goes on")
	_check(ts._wet > 0.3 and ts._water.visible and ts.flood_mode == 0.0, "  and the ground stays wet (puddles %.2f)" % ts._wet)
	_check(is_equal_approx(ts.dread, 0.0) or ts.dread < 0.01, "  the sky is back to the night (dread %.2f)" % ts.dread)
	_check(not hg.lit and not zm.tsunami_active and ts.survived == 1, "  the beacon is out")
	if is_instance_valid(roof_dead):
		roof_dead.queue_free()
	hg.up.clear()
	player.global_position = Vector3(-17.5, 0.0, -3.0)
	await _frames(3)

	# 120 s (here: the duration given) pass between the warning being shown and the wave
	hg.up.clear()
	hg.put_up(player, hg.zone_center())
	ts.flood_hold = 0.5
	ts.flood_recede = 0.5
	ts.start(4.0)
	await _frames(2)
	for dd in ts.drowned:
		dd.global_position = Vector3(500, -50, 500)
		dd.set_physics_process(false)
	var t_warn := -1
	var t_wave := -1
	var t0w := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0w < 14000:
		if ts.warned and t_warn < 0:
			t_warn = Time.get_ticks_msec()
		if ts.phase == ts.Phase.WAVE:
			t_wave = Time.get_ticks_msec()
			break
		await process_frame
	var gap := float(t_wave - t_warn) / 1000.0
	_check(t_warn > 0 and t_wave > 0 and absf(gap - 4.0) < 0.6, "  the wave arrives exactly the countdown after the warning is shown (%.2f s for a 4 s clock)" % gap)
	_check(ts.DURATION == 120.0 and ts.INTRO > 2.0 and ts.INTRO < 5.0, "  the real clock is 120 s, the warning %.1f s after the quake" % ts.INTRO)
	await _wait_until(func(): return ts.phase == ts.Phase.IDLE, 12.0)
	hg.up.clear()
	player.global_position = Vector3(-17.5, 0.0, -3.0)
	await _frames(3)

	# --- The zombie round keeps going; the surge waits for the tsunami ---
	block.spawner.enabled = true
	block.surge.enabled = true
	block.surge.plan_in = 0.01
	ts.start()
	await _frames(40)
	_check(block.surge.phase == block.surge.Phase.IDLE and block.surge.surges == 0, "  no new surge while the countdown is on")
	var alive_during: int = block.spawner.alive()
	_check(alive_during >= 2, "  the Drowned count as the living: the round cannot end (%d alive)" % alive_during)
	ts.auto = false
	ts.skip_to(1.0)
	ts._finish()
	ts.start(30.0)

	# --- Timeout: the wave ---
	block.surge.enabled = false
	block.spawner.enabled = false
	for dd in ts.drowned:
		dd.global_position = Vector3(500, -50, 500)
		dd.set_physics_process(false)
	ts.skip_to(0.4)
	var yaw0: float = float(player.get("_look_yaw"))
	var points_fail: int = zm.points
	await _wait_until(func(): return ts.phase == ts.Phase.WAVE, 3.0)
	_check(ts.phase == ts.Phase.WAVE and ts.waves_hit == 3 and not ts.survive, "  at 0:00 outside the zone the wave hits")
	var d_early: float = ts.wave_dist
	await _wait_secs(1.0)
	_check(ts.wave_dist < d_early and ts.wave.visible, "  it rushes down the street (%.0f m -> %.0f m)" % [d_early, ts.wave_dist])
	var yaw1: float = float(player.get("_look_yaw"))
	_check(absf(angle_difference(yaw0, yaw1)) > 0.05 or absf(angle_difference(yaw0, atan2(-ts.SEA_DIR.x, -ts.SEA_DIR.z))) < 0.1, "  the view is turned to face it")
	await _wait_until(func(): return ts.fired.has("impact"), 3.0)
	await _wait_secs(1.0)
	_check(ts.hud.water.visible and ts._lp != null and ts._lp.cutoff_hz < 8000.0, "  the screen is the sea and the sound goes dull (%.0f Hz)" % (ts._lp.cutoff_hz if ts._lp else -1.0))
	var over := await _wait_until(func(): return zm.over, 6.0)
	_check(over and zm.death_cause == "Drowned by the tsunami" and zm.summary()["cause"] == "Drowned by the tsunami", "  game over: Drowned by the tsunami")
	_check(zm.points == points_fail and ts.bonus_count == 1, "  no bonus for it")
	var screen := root.get_node_or_null("ZombieGameOver")
	_check(screen != null and screen.title_button != null, "  the summary screen is up")
	var title_text := ""
	if screen != null:
		for ch in screen.find_children("*", "Label", true, false):
			title_text += (ch as Label).text + "|"
	_check(title_text.contains("DROWNED BY THE TSUNAMI"), "  and says so")
	if screen != null:
		screen._close()

	# --- Reduced camera motion ---
	block = await _tsunami_block()
	ts = block.tsunami
	player = _player()
	gfx.camera_motion = false
	ts.start(20.0)
	for dd in ts.drowned:
		dd.global_position = Vector3(500, -50, 500)
		dd.set_physics_process(false)
	ts.skip_to(8.0)
	await _frames(6)
	_check(ts.trauma_target > 0.1 and absf(ts.shake_applied - ts.trauma_target * ts.REDUCED) < 0.001, "  camera motion off: the tremor is a quarter (%.2f of %.2f)" % [ts.shake_applied, ts.trauma_target])
	var feel = player.get("feel")
	if feel != null:
		_check(feel.trauma <= ts.trauma_target * 0.6, "  and so is what the camera gets (%.2f)" % feel.trauma)
	var yaw_r: float = float(player.get("_look_yaw"))
	ts.skip_to(0.2)
	await _wait_secs(2.0)
	_check(is_equal_approx(float(player.get("_look_yaw")), yaw_r), "  the view is not turned to the wave")
	gfx.camera_motion = true
	ts._finish()
	await _wait_until(func(): return zm.over, 6.0)
	if root.get_node_or_null("ZombieGameOver") != null:
		root.get_node("ZombieGameOver")._close()
	paused = false
	zm.begin(true)
	var back := await _load("res://world/City3D.tscn")
	await _frames(4)
	_check(AudioServer.get_bus_effect_count(master) == base_fx and Engine.time_scale == 1.0, "  leaving the scene puts the audio and time back")
	_check(back != null and not zm.tsunami_active, "  and the flag")
	zm.leave()
