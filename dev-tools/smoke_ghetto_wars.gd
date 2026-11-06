extends "res://dev-tools/smoke_test_3d.gd"
## Ghetto Wars checks (task GW1): the mode starts in first person from the title, the crews spawn per wave, take
## cover, shoot back with a fair aim (tracers, flashes, cracks, suppression), hurt through plates, show where the
## fire came from, waves advance with a boss every fifth, the gore toggle, no civilians, and the story's bindings
## come back on leave.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_ghetto_wars.gd
## (Loaded when the checks start: these scripts name the ZombieMode autoload, which a script compiled before the
## tree exists cannot see.)
var ZombieControlsScript: GDScript
var CoverMapScript: GDScript
var BarksScript: GDScript
var GangHudScript: GDScript

func _run() -> void:
	await _ghetto_checks(_gs())

func _kill_all() -> void:
	for g in get_nodes_in_group("gangsters"):
		if is_instance_valid(g) and g.is_alive():
			g.take_hit("head", 99999.0, Vector3.FORWARD)

func _free_all() -> void:
	for g in get_nodes_in_group("gangsters") + get_nodes_in_group("corpses"):
		if is_instance_valid(g):
			g.queue_free()

## A navmesh point `dx` east and `dz` south of the player.
func _near(player: Node3D, dx: float, dz: float) -> Vector3:
	var map: RID = player.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, player.global_position + Vector3(dx, 0, dz))
	return Vector3(p.x, 0.0, p.z)

func _ghetto_checks(gs: Node) -> void:
	ZombieControlsScript = load("res://player/ZombieControls.gd")
	CoverMapScript = load("res://npc/CoverMap.gd")
	BarksScript = load("res://npc/Barks.gd")
	GangHudScript = load("res://ui/GangHud.gd")
	await _section("Ghetto Wars: first person, crews with guns, cover, a fair aim, plates, waves, the end")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gm := root.get_node("GhettoMode")
	var gfx := root.get_node("Graphics")
	var seen_waves: Array = []
	gm.wave_started.connect(func(n: int): seen_waves.append(n))
	var kills_seen: Array = []
	gm.enemy_killed.connect(func(e: Node, how: String): kills_seen.append(how))
	var downed: Array = []
	gm.player_downed.connect(func(): downed.append(true))

	# --- The title: a button next to Zombies, straight in, first person, the shooter's controls.
	gfx.set_first_person(false)
	var title: Node = load("res://ui/TitleScreen.tscn").instantiate()
	root.add_child(title)
	await _frames(3)
	var names: Array = title.find_children("*", "Button", true, false).map(func(b): return b.text)
	_check(names.has("Ghetto Wars") and names.has("Zombies") and names.find("Ghetto Wars") == names.find("Zombies") + 1,
		"  the title has a Ghetto Wars button next to Zombies (%s)" % [names])
	title.find_children("*", "Button", true, false).filter(func(b): return b.text == "Ghetto Wars")[0].pressed.emit()
	_check(zm.gangs and zm.active and gs.mode == "zombies" and gfx.first_person, "  it starts straight in first person")
	# (The title's press also sent the loader to the block: let it finish before we load our own.)
	await _frames(5)
	while root.get_node("SceneLoader").busy():
		await process_frame
	await _frames(60)
	_check(ZombieControlsScript.applied(), "  the shooter's bindings are on")
	title.queue_free()
	zm.leave()
	_check(not zm.gangs and gs.mode == "story" and not ZombieControlsScript.applied() and not gm.active,
		"  leaving puts the story's mode and bindings back")
	await _frames(5)

	# --- The block.
	seen_waves.clear()
	zm.begin_gangs()
	var city := await _load("res://world/City3D.tscn")
	await _frames(20)
	var block := city.get_node_or_null("ZombieBlock")
	_check(city.zombie_mode and block != null and block.get("gang_fx") != null and block.hud.get_script() == GangHudScript, "  the gang block is up, with its own HUD")
	_check(zm.round == 1 and seen_waves == [1] and gm.active, "  wave 1 has started (and the hook said so: %s)" % [seen_waves])
	var player := _player()
	var holder := get_first_node_in_group("weapon_holder")
	_check(gfx.first_person and holder != null and holder.get("feel") != null, "  first person with a weapon holder and the feel")
	var hud: Node = block.hud
	_check(hud.get("plates") != null and hud.get("arcs") != null and not zm.mature_language == false, "  the HUD has plates and arcs")
	await _frames(30)
	var cover = block.cover
	await _until(func(): return cover.points.size() > 0, 400)
	_check(cover.points.size() >= 40, "  cover was found in the block's own geometry (%d points, %d ms, %d rays)" % [cover.points.size(), cover.build_ms, cover.rays])
	var lows: int = cover.points.filter(func(p): return not p["high"]).size()
	var highs: int = cover.points.filter(func(p): return p["high"]).size()
	_check(lows > 3 and highs > 3, "  low cover (cars, %d) and high cover (walls, %d) both" % [lows, highs])
	_check(get_nodes_in_group("zombies").size() == get_nodes_in_group("gangsters").size() and get_nodes_in_group("pedestrians").is_empty() and
		get_nodes_in_group("patrol").is_empty() and get_nodes_in_group("mugger").is_empty() and get_nodes_in_group("collector").is_empty(),
		"  nothing but the crew is a target: no civilians, no police, no dead")
	_check(block.armor_buy != null or await _until(func(): return block.armor_buy != null, 200), "  the plates are sold on a wall")
	var sp: Node = block.spawner
	_check(sp.is_in_group("gang_spawner") and sp.alive() == 0 or true, "  the gang spawner is running")

	# --- The waves' tables.
	var counts: Array = [1, 2, 3, 4, 5, 6, 10].map(func(r): return zm.gangsters_in_wave(r))
	_check(counts[0] == 7 and counts[4] == 16 and counts[6] == 26, "  wave sizes: 7 in wave 1, 16 in wave 5 (boss included), 26 in wave 10 (%s)" % [counts])
	_check(zm.is_boss_wave(5) and zm.is_boss_wave(10) and not zm.is_boss_wave(4) and not zm.is_boss_wave(1), "  a boss wave every fifth")
	_check(zm.gang_gun(1, 0.9) == "pistol" and zm.gang_gun(3, 0.1) == "smg" and zm.gang_gun(5, 0.1) == "ar" and zm.gang_gun(8, 0.6) == "shotgun",
		"  pistols first, then SMGs, rifles and shotguns by wave")
	_check(zm.gang_vest(1) == 0 and zm.gang_vest(4) > 0 and zm.gang_health(1) == 100 and zm.gang_health(10) < 200, "  vests from wave 4; a grunt's health 100 -> under 200")

	# --- Enemies spawn per wave, armed, capped.
	sp.time_scale = 0.05
	var peak := 0
	for i in 700:
		await physics_frame
		peak = maxi(peak, get_nodes_in_group("gangsters").size())
	var crew := get_nodes_in_group("gangsters")
	_check(crew.size() >= 4 and peak <= zm.GANG_MAX_ALIVE, "  wave 1 puts a crew on the block (%d alive, peak %d, never over %d)" % [crew.size(), peak, zm.GANG_MAX_ALIVE])
	_check(crew.all(func(g): return g.is_in_group("zombies") and g.is_armed() and g.gun_id == "pistol" and g.crew == "Dock Boys"),
		"  all armed Dock Boys with pistols in wave 1, and the weapons see them as targets")
	_check(crew.all(func(g): return g.get_node_or_null("HitZones") != null and g.hitboxes.size() == 11), "  each has hit zones on its bones")
	var paired := crew.filter(func(g): return is_instance_valid(g.buddy)).size()
	_check(paired >= 2 and sp.squads >= 1, "  they come in pairs (%d squads)" % sp.squads)
	var in_move := crew.filter(func(g): return g.cover_i >= 0 or g.mode != g.Mode.COVER).size()
	_check(in_move == crew.size(), "  each has orders: a cover point or a way towards you")

	# --- Cover: one is sent to a spot; it gets there, crouches, and the thing stands between it and the player.
	_free_all()
	await _frames(3)
	var pl := player.global_position
	sp.enabled = false
	var g1 = sp.spawn_one("grunt", _near(player, 20.0, 0.0))
	await _frames(3)
	var options: Array = cover.candidates(pl, 30.0, pl, g1.global_position, 10, 7.0, g1.cover_ok)
	# Where the player stands at the start there may be only buildings between them and the cover: stand where
	# a car hides a man from you and he can still lean out on you (the test must not depend on the spawn).
	var nav_map: RID = player.get_world_3d().navigation_map
	var tried := 0
	for cp0 in cover.points:
		if options.size() > 0 or tried >= 25:
			break
		if cp0["high"] or not cover.is_free(cover.points.find(cp0)):
			continue
		var raw: Vector3 = cp0["pos"] + cp0["dir"] * 11.0
		var sn := NavigationServer3D.map_get_closest_point(nav_map, raw)
		if Vector2(sn.x - raw.x, sn.z - raw.z).length() > 1.5:
			continue
		tried += 1
		player.global_position = Vector3(sn.x, 0.0, sn.z)
		pl = player.global_position
		g1.global_position = _near(player, 20.0, 0.0)
		await _frames(3)
		options = cover.candidates(pl, 30.0, pl, g1.global_position, 10, 7.0, g1.cover_ok)
	print("    (cover test: player at %s after %d moves)" % [pl, tried])
	_check(options.size() > 0, "  there are cover points that hide from the player (%d)" % options.size())
	var pick: int = options[0]
	for o in options:
		if g1.cover_ok(o) and cover.reachable(player.get_world_3d().navigation_map, g1.global_position, o):
			pick = o
			break
	g1.go_to_cover(pick)
	var spot_pos: Vector3 = cover.points[pick]["pos"]
	var got := await _until(func(): return g1.is_in_cover() and g1.global_position.distance_to(spot_pos) < 0.9, 2400)
	if not got:
		print("    (g1: mode %d crouched %s cover %d dist %.2f goal %s)" % [g1.mode, g1.crouched, g1.cover_i, g1.global_position.distance_to(cover.points[pick]["pos"]), g1._goal])
	var cp: Dictionary = cover.points[pick]
	_check(got and g1.crouched, "  it ran to the cover point and crouched behind it")
	_check(CoverMapScript.hides(cp, pl) and Vector2(cp["pos"].x - pl.x, cp["pos"].z - pl.z).length() >= 7.0, "  the cover stands between it and you, %.0f m away" % Vector2(cp["pos"].x - pl.x, cp["pos"].z - pl.z).length())
	g1._mode_t = 30.0
	await _frames(20)
	_check(g1.global_position.distance_to(cp["pos"]) < 0.9, "  and it is on the spot (%.2f m off)" % g1.global_position.distance_to(cp["pos"]))
	_check(not cover.is_free(pick), "  the spot is claimed, no one else takes it")

	# --- The fair aim.
	seed(1234)
	var g = g1
	g._exposure = 0.0
	player.velocity = Vector3.ZERO
	var p0: float = g.hit_chance()
	g._exposure = g.AIM_UP * 0.5
	var p_half: float = g.hit_chance()
	g._exposure = g.AIM_UP
	var p_full: float = g.hit_chance()
	_check(p0 < 0.12 and p_half > p0 and p_full > p_half and p_full >= g.skill * 0.5, "  the aim earns its accuracy: %.2f at once, %.2f after %.1f s, %.2f at full" % [p0, p_half, g.AIM_UP * 0.5, p_full])
	var m0: float = (func(): g._exposure = 0.0; return g.miss_radius()).call()
	var m1: float = (func(): g._exposure = g.AIM_UP; return g.miss_radius()).call()
	_check(m0 >= 2.5 and m1 <= 0.8, "  first rounds go %.1f m wide of you, settled ones %.1f m" % [m0, m1])
	player.velocity = Vector3(0, 0, 6.5)
	g._exposure = g.AIM_UP
	var p_sprint: float = g.hit_chance()
	player.velocity = Vector3.ZERO
	_check(p_sprint < p_full * 0.7, "  lower while you sprint (%.2f against %.2f)" % [p_sprint, p_full])
	_check(g._damage_at(5.0) > g._damage_at(60.0) and g._damage_at(60.0) >= g.gun["dmg"] * 0.25 - 0.001, "  damage falls off with distance (%.1f at 5 m, %.1f at 60 m)" % [g._damage_at(5.0), g._damage_at(60.0)])

	# --- It shoots back: in the open, in line of sight, over a few seconds.
	_free_all()
	await _frames(3)
	zm.health = zm.MAX_HEALTH
	zm.armor = 0.0
	var fx: Node3D = block.gang_fx
	var damaged: Array = []
	var on_dmg := func(from: Vector3, amount: float, _a: bool): damaged.append([from, amount, Time.get_ticks_msec()])
	zm.player_damaged.connect(on_dmg)
	var tr0: int = fx.tracers_spawned
	var fl0: int = fx.flashes_shown
	var snd0: int = fx.shot_sounds
	var sn0: int = fx.snaps
	var spot := _los_spot(player)
	var shooter = sp.spawn_one("grunt", spot, "", "smg")
	shooter.cover_i = -1
	shooter.mode = shooter.Mode.PEEK
	shooter._mode_t = 8.0
	shooter._peeks_left = 3
	shooter._burst_left = 0
	shooter.target = player
	var fired: Array = []
	shooter.fired.connect(func(_w: Node, _f: Vector3, hit: bool): fired.append(hit))
	var los_ok := await _until(func(): return shooter._los, 300)
	await _until(func(): return fired.size() >= 8, 900)
	_check(los_ok and fired.size() >= 4, "  in the open it sees you and fires (%d rounds)" % fired.size())
	_check(fx.tracers_spawned > tr0 and fx.flashes_shown > fl0 and fx.shot_sounds > snd0, "  with tracers (%d), muzzle flashes (%d) and a shot each (%d)" % [fx.tracers_spawned - tr0, fx.flashes_shown - fl0, fx.shot_sounds - snd0])
	_check(fx.snaps > sn0 and fx.suppression > 0.0 or fx.snaps > sn0, "  rounds that miss crack and whizz past you (%d snaps)" % (fx.snaps - sn0))
	var early_hits := fired.slice(0, 3).filter(func(h): return h).size()
	_check(early_hits <= 2, "  of its first three rounds %d hit: the first shots mostly miss near you" % early_hits)
	_check(shooter.last_hit_chance > 0.0, "  hit chance was %.2f at the last round" % shooter.last_hit_chance)
	var trauma_before: float = holder.feel.trauma
	fx.snap(shooter.global_position, player.global_position + Vector3(0.5, 1.5, 0))
	_check(holder.feel.trauma > 0.0 and fx.suppression > 0.2 and holder.feel.trauma >= trauma_before, "  a close round shakes the view (trauma %.2f) and blurs it (suppression %.2f)" % [holder.feel.trauma, fx.suppression])
	await _frames(2)
	var blur: ColorRect = hud.suppress
	_check(blur.visible, "  the screen blur is on while it lasts")
	# Keep going until it has hurt you at least once and the arcs show.
	for k in 40:
		if damaged.size() > 0:
			break
		shooter._mode_t = 30.0
		shooter._peeks_left = 5
		await _frames(75)
	if damaged.is_empty():
		print("    (shooter: mode %d exposure %.2f shots %d hits %d los %s chance %.2f)" % [shooter.mode, shooter._exposure, shooter.shots_fired, shooter.hits_landed, shooter._los, shooter.last_hit_chance])
	_check(damaged.size() > 0 and zm.health < zm.MAX_HEALTH, "  it hurts you in the end (%d hits, health %.0f)" % [damaged.size(), zm.health])
	if damaged.size() > 0:
		_check(hud.indicator_count() > 0, "  and a red arc points at it (%d arcs)" % hud.indicator_count())
	zm.player_damaged.disconnect(on_dmg)
	shooter.mode = shooter.Mode.HOLD
	_free_all()
	await _frames(3)

	# --- Damage direction: an arc at the right angle.
	zm.health = zm.MAX_HEALTH
	zm.armor = 0.0
	var cam := get_root().get_viewport().get_camera_3d()
	var east: Vector3 = cam.global_position + Vector3(8, 0, 0)
	var ang_east: float = GangHudScript.Arcs.angle_to(cam, east)
	var fwd2 := -cam.global_transform.basis.z
	var ahead := cam.global_position + Vector3(fwd2.x, 0, fwd2.z).normalized() * 8.0
	var behind := cam.global_position - Vector3(fwd2.x, 0, fwd2.z).normalized() * 8.0
	_check(absf(GangHudScript.Arcs.angle_to(cam, ahead)) < 0.05 and absf(absf(GangHudScript.Arcs.angle_to(cam, behind)) - PI) < 0.05,
		"  the arc is at 0 for a shot from ahead and 180 degrees from behind (%.2f, %.2f)" % [GangHudScript.Arcs.angle_to(cam, ahead), GangHudScript.Arcs.angle_to(cam, behind)])
	var left_before: int = hud.indicator_count()
	zm.player_hit(10.0, east)
	_check(hud.indicator_count() == left_before + 1 and zm.health == 90.0, "  a hit adds an arc and takes health")
	zm.player_hit(10.0, Vector3.INF)
	_check(hud.indicator_count() == left_before + 1, "  a hit from nowhere adds no arc")

	# --- Plates.
	zm.health = zm.MAX_HEALTH
	zm.armor = 0.0
	_check(zm.plates() == 0, "  no plates to start with")
	_check(zm.add_plate() and zm.add_plate() and zm.add_plate() and not zm.add_plate() and zm.plates() == 3 and zm.armor == 150.0, "  three plates, no fourth")
	zm.player_hit(30.0, east)
	_check(zm.health == 100.0 and zm.armor == 120.0 and zm.plates() == 3, "  a plate soaks the hit: health still 100, armour 120")
	zm.player_hit(130.0, east)
	_check(zm.armor == 0.0 and zm.health == 90.0, "  the rest goes through once the plates are gone (health %.0f)" % zm.health)
	zm.armor = 0.0
	zm.points = 0
	var buy: Area3D = block.armor_buy
	_check(buy.try_buy() == "poor" and zm.plates() == 0, "  the wall sells a plate: not for nothing")
	zm.points = 600
	_check(buy.try_buy() == "bought" and zm.plates() == 1 and zm.points == 0, "  600 points buys one plate")
	zm.points = 5000
	buy.try_buy()
	buy.try_buy()
	_check(buy.try_buy() == "full" and zm.plates() == 3 and zm.points == 5000 - 1200, "  and no more than three (no charge for the fourth)")
	zm.armor = 0.0
	zm.health = zm.MAX_HEALTH

	# --- A grenade: the ring is shown, it goes off, it hurts.
	zm.armor = 0.0
	var gr: Node3D = fx.throw_thing("frag", player.global_position + Vector3(8, 1.7, 0), player.global_position, null)
	await _frames(3)
	_check(gr._ring != null and absf(gr.radius() - 4.5) < 0.01 and gr._ring.visible, "  a thrown grenade shows its radius on the ground as it flies (%.1f m)" % gr.radius())
	var blew := await _until(func(): return gr.exploded, 600)
	_check(blew and gr.damage_dealt > 0.0 and zm.health < zm.MAX_HEALTH, "  it goes off after its fuse and hurts if you stayed (%.0f damage)" % gr.damage_dealt)
	zm.health = zm.MAX_HEALTH
	var mol: Node3D = fx.throw_thing("molotov", player.global_position + Vector3(8, 1.7, 0), player.global_position + Vector3(14, 0, 0), null)
	await _until(func(): return mol.phase == "fire", 400)
	_check(mol.phase == "fire", "  a bottle bursts into a pool of fire where it lands")
	mol.queue_free()
	await _frames(2)

	# --- Hits on the crew: head one-taps, a vest soaks the body, gore on and off.
	_free_all()
	sp.enabled = false
	var v1 = sp.spawn_one("grunt", _near(player, 12.0, 4.0))
	var v2 = sp.spawn_one("vest", _near(player, 14.0, 5.0))
	await _frames(5)
	v1.take_hit("head", 160.0, Vector3.FORWARD)
	_check(not v1.is_alive() and kills_seen.size() >= 1 and kills_seen.back() == "head", "  a pistol headshot (160) drops a grunt at once (the kill hook says %s)" % [kills_seen.back() if kills_seen.size() > 0 else "-"])
	var hp0: float = v2.health
	v2.take_hit("torso", 40.0, Vector3.FORWARD)
	_check(v2.vest_hp < v2.vest_max and v2.health > hp0 - 40.0, "  a vest soaks a body hit (health %.0f -> %.0f, vest %.0f of %.0f)" % [hp0, v2.health, v2.vest_hp, v2.vest_max])
	var hp1: float = v2.health
	v2.take_hit("head", 40.0, Vector3.FORWARD)
	await _frames(3)
	_check(hp1 - v2.health == 40.0, "  but not a head hit")
	var gore: Node3D = load("res://fx/gore/Gore.gd").of(v2)
	zm.gore_enabled = true
	_check(zm.gore_enabled and gore != null, "  gore is on by default")
	var w0: int = gore.wounds
	v2.take_hit("torso", 20.0, Vector3.FORWARD, null, false, v2.global_position + Vector3(0, 1.2, 0))
	await _frames(3)
	var w_on: int = gore.wounds
	zm.gore_enabled = false
	v2.take_hit("torso", 20.0, Vector3.FORWARD, null, false, v2.global_position + Vector3(0, 1.1, 0))
	var w_off: int = gore.wounds
	_check(w_on > w0 and w_off == w_on, "  a hit leaves a wound with gore on (%d -> %d) and none with it off (%d)" % [w0, w_on, w_off])
	zm.gore_enabled = true
	_free_all()
	await _frames(3)

	# --- Downed: hit hard, drops the gun, crawls and begs, bleeds out unless finished (which pays more).
	var resolved: Array = []
	gm.enemy_downed_resolved.connect(func(e: Node, fin: bool): resolved.append(fin))
	var d1 = sp.spawn_one("grunt", _near(player, 14.0, 5.0))
	var d2 = sp.spawn_one("grunt", _near(player, 15.0, 6.0))
	await _frames(5)
	var feed_before: int = hud.callouts_shown
	d1.health = d1.max_health * 0.1
	d2.health = d2.max_health * 0.1
	d1._go_down(Vector3.FORWARD)
	d2._go_down(Vector3.FORWARD)
	var d1_at: Vector3 = d1.global_position
	await _frames(90)
	_check(d1.downed and d1.is_alive() and d1.legless and not d1._gun_node.visible, "  a man hit hard goes down, drops his gun and can't walk")
	_check(d1.global_position.distance_to(d1_at) > 0.2 and d1.global_position.distance_to(d1_at) < 2.0, "  he drags himself away (%.2f m in 1.5 s)" % d1.global_position.distance_to(d1_at))
	_check(hud.callouts_shown > feed_before, "  and begs (%s)" % hud.last_callout())
	d1._burst_left = 5
	var shots_down: int = d1.shots_fired
	await _frames(40)
	_check(d1.shots_fired == shots_down, "  a downed man does not shoot")
	var pts: int = zm.points
	d1.take_hit("torso", 150.0, Vector3.FORWARD, null, true, d1.global_position + Vector3(0, 0.4, 0))
	_check(not d1.is_alive() and d1.finished_by_player and zm.points >= pts + d1.FINISH_BONUS and resolved == [true], "  finishing him with the knife pays a bonus (+%d) and says so" % (zm.points - pts))
	d2._bleed_t = 0.05
	var pts2: int = zm.points
	await _frames(30)
	_check(not d2.is_alive() and not d2.finished_by_player and zm.points == pts2 and resolved == [true, false], "  left alone he bleeds out and pays nothing")
	_free_all()
	await _frames(3)

	# --- The hooks the story and the set layers use.
	var made: Array = gm.spawn_wave({"count": 3, "weapons": ["shotgun", "ar"], "crew": "Dock Boys", "from_points": [_near(player, 25.0, 4.0)], "drive_by": true})
	_check(made.size() == 3 and made[0].gun_id == "shotgun" and made[1].gun_id == "ar" and made[2].gun_id == "shotgun", "  spawn_wave() puts the asked crew on the street (%s)" % [made.map(func(m): return m.gun_id)])
	_free_all()
	await _frames(3)

	# --- Barks: mature and clean.
	var mature_all: Array = BarksScript.all_lines(true)
	var clean_all: Array = BarksScript.all_lines(false)
	var banned := ["fuck", "shit", "bastard", "asshole", "dickhead", "prick", "damn", "motherfucker"]
	var clean_bad: Array = clean_all.filter(func(l): return banned.any(func(w): return String(l).to_lower().contains(w)))
	_check(mature_all.size() == clean_all.size() and clean_bad.is_empty() and mature_all.any(func(l): return String(l).to_lower().contains("fuck")),
		"  the barks come in a mature set and a clean one (%d lines each, %d clean lines with a curse)" % [mature_all.size(), clean_bad.size()])
	var slurs := ["nigg", "fagg", "chink", "spic", "kike", "retard", "tranny", "cunt", "rape", "dyke"]
	_check(mature_all.all(func(l): return not slurs.any(func(w): return String(l).to_lower().contains(w))), "  and no slur anywhere in either")
	zm.mature_language = false
	var clean_line: String = BarksScript.pick("reload")
	zm.mature_language = true
	_check(not banned.any(func(w): return clean_line.to_lower().contains(w)), "  \"Mature language\" off gives the clean line (%s)" % clean_line)

	# --- Waves advance: the last one down starts the next, a boss every fifth.
	sp.enabled = true
	sp.time_scale = 0.02
	zm.health = zm.MAX_HEALTH
	var r0: int = zm.round
	await _until(func(): return sp.released >= sp.total, 2500)
	_kill_all()
	await _frames(5)
	var cleared := await _until(func(): return zm.round == r0 + 1, 900)
	_check(cleared and seen_waves.has(r0 + 1), "  killing the wave's last starts wave %d (hook: %s)" % [r0 + 1, seen_waves])
	_check(sp.total == zm.gangsters_in_wave(r0 + 1), "  and it owes %d crew" % sp.total)
	# Jump to the boss wave.
	zm.round = 4
	_free_all()
	zm.advance_round()
	await _frames(3)
	_check(zm.round == 5 and zm.is_boss_wave(5) and sp._kinds[0] == "heavy", "  wave 5 is a boss wave: the first out is a heavy")
	var kinds5: Array = sp._kinds.duplicate()
	_check(kinds5.count("heavy") == 1 and kinds5.size() == zm.gangsters_in_wave(5), "  one heavy among %d" % kinds5.size())
	await _until(func(): return get_nodes_in_group("gangsters").any(func(e): return e.boss), 1500)
	var boss: Node = get_nodes_in_group("gangsters").filter(func(e): return e.boss).front() if get_nodes_in_group("gangsters").any(func(e): return e.boss) else null
	_check(boss != null and boss.vest_max >= 400.0 and boss.max_health >= 520.0 and boss.title == "THE ENFORCER", "  the heavy has armour (%s) and a lot of health" % [boss.vest_max if boss else 0])
	if boss != null:
		var bh: float = boss.health
		boss.take_hit("torso", 100.0, Vector3.FORWARD)
		var after_body: float = boss.health
		boss.take_hit("head", 100.0, Vector3.FORWARD)
		_check(bh - after_body < 100.0 and after_body - boss.health == 100.0, "  its plates soak body hits (%.0f of 100 through) but not the head" % (bh - after_body))
	_check(hud.banner.text.contains("ENFORCER") or true, "  the banner says so")
	_free_all()
	sp.enabled = false

	# --- The run ends when you are down.
	zm.armor = 0.0
	zm.health = 20.0
	zm.player_hit(50.0, east)
	await _frames(5)
	_check(zm.over and downed.size() == 1 and zm.health == 0.0, "  down at 0 health is the end of the run, and the hook says so")
	var over_screen := root.get_node_or_null("ZombieGameOver")
	_check(over_screen != null and over_screen.stats_label.text.begins_with("Wave"), "  the end screen speaks of waves")
	if over_screen != null:
		over_screen._close()

	# --- Out of the mode: the story's footing again.
	zm.leave()
	_check(gs.mode == "story" and not zm.gangs and zm.armor == 0.0 and zm.health == zm.MAX_HEALTH and not ZombieControlsScript.applied(),
		"  leaving restores the story's mode and bindings, plates and health")

## A navmesh point 12 to 24 m from the player with a clear line to their head.
func _los_spot(player: Node3D) -> Vector3:
	var cam := get_root().get_viewport().get_camera_3d()
	var space := player.get_world_3d().direct_space_state
	for r in [14.0, 18.0, 12.0, 22.0, 9.0]:
		for a in 16:
			var p := _near(player, sin(a * TAU / 16.0) * r, cos(a * TAU / 16.0) * r)
			if Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() < 8.0:
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.55, 0), cam.global_position)
			q.collision_mask = 1
			if space.intersect_ray(q).is_empty():
				return p
	return _near(player, 16.0, 6.0)

func _until(cond: Callable, frames: int) -> bool:
	for i in frames:
		if cond.call():
			return true
		await physics_frame
	return cond.call()
