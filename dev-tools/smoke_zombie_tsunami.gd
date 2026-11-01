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

func _zombie_tsunami_checks(_gs: Node) -> void:
	await _section("Dead Block: the tsunami -- countdown, two Drowned, cancel, wave")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	var gfx := root.get_node("Graphics")
	gfx.camera_motion = true
	var master := AudioServer.get_bus_index("Master")
	var base_fx := AudioServer.get_bus_effect_count(master)

	# --- Starts after the surge: the first quake always, later ones by chance ---
	var block := await _tsunami_block()
	var ts: Node = block.tsunami
	var player := _player()
	_check(ts != null and ts.phase == ts.Phase.IDLE and not zm.tsunami_active, "  the block has a tsunami director, idle")
	ts.start_delay = 0.2
	ts.later_chance = 0.0
	zm.surge_ended.emit()
	_check(ts.phase == ts.Phase.IDLE, "  not at once: the quake has to fade first")
	await _wait_secs(0.6)
	_check(ts.phase == ts.Phase.COUNTDOWN and zm.tsunami_active, "  the first quake always brings it")
	_check(ts.duration == 120.0 and ts.remaining > 118.5 and ts.remaining <= 120.0, "  the countdown starts at 120 s (%.2f)" % ts.remaining)
	_check(ts.hud.time_text == "2:00" or ts.hud.time_text == "1:59", "  the HUD shows it (%s)" % ts.hud.time_text)
	_check(ts.hud.needed == 2 and ts.hud.tracker_label.text.begins_with("DROWNED  0 / 2"), "  DROWNED 0 / 2 (%s)" % ts.hud.tracker_label.text)
	ts._finish()
	_check(ts.phase == ts.Phase.IDLE and not zm.tsunami_active, "  finished: idle again")
	zm.surge_ended.emit()
	await _wait_secs(0.6)
	_check(ts.phase == ts.Phase.IDLE, "  the second quake (chance 0) brings none")
	ts.later_chance = 1.0
	zm.surge_ended.emit()
	await _wait_secs(0.6)
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
	_check(absf(d[0].max_health - health0 * 25.0) < 1.0, "  25 times the health of a normal zombie (%.0f vs %.0f)" % [d[0].max_health, health0])
	_check(d[0].is_inside_tree() and d[0].entrance == "rise", "  they rise out of the ground")
	await _wait_secs(3.6)
	var head_y: float = (d[0]._skeleton.global_transform * d[0]._skeleton.get_bone_global_pose(d[0]._skeleton.find_bone("Bip01 Head")).origin).y
	_check(head_y > 1.9 and head_y < 2.6, "  about 2.2 m tall (head bone at %.2f m)" % head_y)
	_check(not d[0].hitboxes.is_empty() and d[0].hitboxes["head"].get_child_count() > 0, "  hit zones, scaled with the body")
	_check(ts.remaining < 117.0, "  the clock runs (%.1f)" % ts.remaining)
	_check(absf(ts.hud.targets.size() - 2.0) < 0.1 and ts.dread > 0.0 and ts.dread < 0.1, "  the HUD tracks both, the dread has begun (%.3f)" % ts.dread)

	# --- Head armour, stagger ---
	var z: Node = d[1]
	var h0: float = z.health
	z.take_hit("head", 100.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 50.0) < 0.5 and z.helmet_on, "  a headshot does half while the helmet holds (%.1f)" % (h0 - z.health))
	h0 = z.health
	z.take_hit("torso", 100.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 100.0) < 0.5, "  the body takes it all")
	var broke := [false]
	z.helmet_broke.connect(func(_x): broke[0] = true)
	var shots := 0
	while z.helmet_on and shots < 400:
		z.take_hit("head", 100.0, Vector3.FORWARD)
		shots += 1
	_check(broke[0] and not z.helmet_on and not z._helmet_node.visible, "  the helmet breaks off after %d headshots (%.0f hp of shell)" % [shots, z.helmet_max])
	h0 = z.health
	z.take_hit("head", 100.0, Vector3.FORWARD)
	_check(absf((h0 - z.health) - 100.0) < 0.5, "  then headshots count in full")
	z._stagger = 0.0
	z.take_hit("torso", 30.0, Vector3.FORWARD)
	var small_stagger: float = z._stagger
	z._stagger = 0.0
	z.state = z.State.CHASE
	z.charge = z.Charge.NONE
	z.take_hit("torso", 300.0, Vector3.FORWARD)
	_check(small_stagger == 0.0 and z._stagger > 0.0, "  only a heavy hit staggers it (%.2f vs %.2f)" % [small_stagger, z._stagger])
	_check(z.is_alive() and z.health > 0.0, "  and it is a long way from dead")
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
	_check(c.charge_hits == 1 and zm.health < zm.MAX_HEALTH, "  the charge lands and hurts (health %.0f)" % zm.health)
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
	_check(ts.phase == ts.Phase.WAVE and ts.waves_hit == 1, "  at 0:00 the wave hits")
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
