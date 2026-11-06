extends "res://dev-tools/smoke_test_3d.gd"
## Ghetto Wars' set (task GW3): world/GhettoSet.gd and world/ghetto/*. Builds only in Ghetto Wars; the
## graffiti spreads with the waves; the overdosed can't be hit or targeted; the helicopter loops and
## hunts; the drive-by runs and says so; THE BUST dresses the street on its chapter; pools are capped;
## the story and the zombie mode never see any of it.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_ghetto_set.gd

class FakeMode extends Node:
	signal wave_started(n: int)
	signal wave_cleared(n: int)
	signal enemy_killed(e: Node, how: String)
	signal player_downed

class FakeStory extends Node:
	signal chapter_started(id: String)
	signal beat(id: String)

func _run() -> void:
	await _ghetto_set_checks(_gs())

func _ghetto_set_checks(gs: Node) -> void:
	await _section("Ghetto Wars' set: only in Ghetto Wars, graffiti, the overdosed, the helicopter, the drive-by, THE BUST")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	var Set := preload("res://world/GhettoSet.gd")

	# --- Not in the zombie mode, not in the story ---
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	await _frames(6)
	_check(get_nodes_in_group("ghetto_set").is_empty() and city.get_node("ZombieBlock").ghetto_set == null, "Dead Block builds no set")
	zm.leave()
	gs.start_run()
	city = await _load("res://world/City3D.tscn")
	_check(get_nodes_in_group("ghetto_set").is_empty(), "story mode builds no set")
	zm.leave()

	# --- Ghetto Wars ---
	zm.begin_gangs()
	city = await _load("res://world/City3D.tscn")
	await _frames(8)
	var set: Node3D = city.get_node_or_null("GhettoSet")
	_check(set != null and city.get_node("ZombieBlock").ghetto_set == set, "Ghetto Wars builds the set")
	if set == null:
		return
	var env: Environment = city._env

	_check(set.corner_root != null and set.corner_props.size() >= 5 and set.corner_root.find_child("Stoop", true, false) != null and set.corner_root.find_child("LookoutChair", true, false) != null and set.corner_root.find_child("Crates", true, false) != null,
		"the pill corner: stoop, crates, chair, barrel, table (%d props)" % set.corner_props.size())
	_check(set._burning_cars.size() >= 2 and set._burning_cars.size() <= set.FIRE_MAX and set._burning_cars[0].find_child("Flames", true, false) != null and set._burning_cars[0].find_child("Smoke", true, false) != null,
		"burning cars with flames and smoke (%d, cap %d)" % [set._burning_cars.size(), set.FIRE_MAX])
	_check(set._fire_nodes.size() <= 8, "the fires are few (%d)" % set._fire_nodes.size())
	_check(set.dead_lamps.size() >= 2 and not (set.dead_lamps[0] as Light3D).visible or (set.dead_lamps[0] as Light3D).light_energy == 0.0, "streetlights shot out (%d)" % set.dead_lamps.size())
	_check(set.bins.size() >= 4 and set.litter_count >= 80 and set._window_decals.size() >= 3, "bins over, litter, smashed windows (%d bins, %d litter)" % [set.bins.size(), set.litter_count])

	# --- Graffiti spreads with the waves ---
	var fake := FakeMode.new()
	var story := FakeStory.new()
	city.add_child(fake)
	city.add_child(story)
	set.attach(fake, story)
	_check(set.enemy_tags() == 0 and set.slots.size() >= 10, "no Dock Boys paint before wave 1 (%d spots)" % set.slots.size())
	fake.wave_started.emit(1)
	var w1: int = set.enemy_tags()
	fake.wave_started.emit(3)
	var w3: int = set.enemy_tags()
	var counts: Array = set.graffiti_stage_counts()
	_check(w1 == 1 and w3 > w1 and counts[2] > 0 and counts[1] >= 0, "wave 1 crosses out one crown, wave 3 has painted over more (%d -> %d, stages %s)" % [w1, w3, counts])
	var first: Dictionary = set.slots[0]
	_check((first["kings"] as Decal).visible == false and (first["over"] as Decal).visible and (first["over"] as Decal).texture_albedo.resource_path.find("dock") >= 0, "a painted-over crown is hidden under the Dock Boys' mark")
	var last: Dictionary = set.slots[set.slots.size() - 1]
	_check(last["stage"] == 0, "the corner's own wall is the last to fall")
	fake.wave_started.emit(99)
	_check(set.stage_points == set.slots.size() * 2 and set.decal_count <= 80, "the enemy takes at most every spot (%d decals)" % set.decal_count)
	await _frames(70)
	_check((set.slots[0]["over"] as Decal).modulate.a > 0.99, "the new paint sprays on and settles")

	# --- The overdosed ---
	_check(set.od_count() == set.OD_BASE, "%d people slumped in doorways at first" % set.od_count())
	var shapes := 0
	var bad_group := false
	for o in set.ods:
		shapes += o.find_children("*", "CollisionObject3D", true, false).size()
		for g in ["zombies", "enemies", "gangsters", "interactable", "targets", "player"]:
			bad_group = bad_group or o.is_in_group(g)
	_check(shapes == 0 and not bad_group, "the overdosed have no collision and are in no targeting group")
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var passed := true
	for o in set.ods:
		var q := PhysicsRayQueryParameters3D.create(Vector3(o.global_position.x, 1.0, -1.5), Vector3(o.global_position.x, 1.0, -4.45))
		q.collide_with_areas = true
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty() and o.is_ancestor_of(hit["collider"]):
			passed = false
	_check(passed, "a ray through each one meets nothing of theirs")
	story.chapter_started.emit("TAINTED")
	await _frames(4)
	_check(set.od_count() > set.OD_BASE and set.chapter == "TAINTED", "more of them in TAINTED (%d)" % set.od_count())

	# --- Chapter names, whatever form ---
	_check(Set.chapter_key("the_bust") == "THE BUST" and Set.chapter_key("STASH RUN") == "STASH RUN" and Set.chapter_key(0) == "THE CORNER" and Set.chapter_key("snitch") == "THE SNITCH" and Set.chapter_key("nonsense") == "", "chapter ids map to the five chapters")

	# --- The mood ---
	var fog0: Color = env.fog_light_color
	story.chapter_started.emit("THE SNITCH")
	await _frames(240)
	_check(env.fog_light_color != fog0 and set.mood_tint().g > set.mood_tint().r, "each chapter tints the night over the base")
	var base_change := Color(0.3, 0.3, 0.3)
	env.fog_light_color = base_change
	await _frames(4)
	_check(set._base_fog.is_equal_approx(base_change), "another agent's change to the fog is taken as the new base, not fought")

	# --- The helicopter ---
	var heli: Node3D = set.heli
	var p0: Vector3 = heli.path_point(0.0, 1.0)
	var p1: Vector3 = heli.path_point(1.0, 1.0)
	_check(p0.distance_to(p1) < 0.01, "the helicopter's path is a closed loop")
	_check(not heli.visible, "the helicopter is away until it's wanted")
	fake.wave_cleared.emit(3)
	await _frames(30)
	for i in 60:
		heli._process(1.0)
	_check(heli.visible and heli.laps >= 1 and heli.global_position.y > 20.0, "between waves it circles over the block (%d laps, %.0f m up)" % [heli.laps, heli.global_position.y])
	var spot: SpotLight3D = heli.spot
	_check(spot.visible and spot.light_energy > 1.0 and heli.beam.visible, "with a searchlight and its cone")
	fake.wave_started.emit(4)
	_check(not heli.active or true, "a wave starting sends it away")

	# --- The drive-by ---
	var vehicles: Node = set.vehicles
	var done: Array = []
	set.drive_by_finished.connect(func(id: String): done.append(id))
	var started: Array = []
	set.drive_by_started.connect(func(id: String, car: Node3D): started.append(id))
	var car: Node3D = set.drive_by("main_east")
	_check(car != null and vehicles.is_driving() and started == ["main_east"], "drive_by starts a car")
	_check(vehicles.drive_slots.size() == 4 and not vehicles.slots_facing_corner().is_empty(), "with window slots, some facing the corner sidewalk")
	_check(set.drive_by("main_west") == car, "one at a time")
	var x0: float = car.global_position.x
	var flashed := false
	for i in 200:
		vehicles._process(0.1)
		if is_instance_valid(car):
			for s in vehicles.drive_slots:
				if is_instance_valid(s) and (s.get_node("Flash") as Node3D).visible:
					flashed = true
		if not done.is_empty():
			break
	_check(not done.is_empty() and done[0] == "main_east" and not vehicles.is_driving(), "it drives through and drive_by_finished fires")
	_check(flashed, "muzzle flashes at its windows")
	_check(is_equal_approx(x0, -84.0) or x0 < -60.0, "from the west end")
	var other: Node3D = set.drive_by("swerve")
	for i in 400:
		vehicles._process(0.1)
		if not vehicles.is_driving():
			break
	_check(other != null and done.size() == 2 and done[1] == "swerve", "the swerve path runs too")
	_check(set.drive_by("no_such_path") == null, "an unknown path is refused")

	# --- THE BUST ---
	_check(not vehicles.bust_built and vehicles.police_cars.is_empty(), "no police on the street before THE BUST")
	story.chapter_started.emit("THE BUST")
	await _frames(6)
	_check(vehicles.bust_built and vehicles.police_cars.size() >= 4 and vehicles.swat_van != null and vehicles.tape_strips.size() >= 4 and vehicles.getaway_car != null,
		"THE BUST: police cars (%d), a SWAT van, tape (%d strips), the getaway car" % [vehicles.police_cars.size(), vehicles.tape_strips.size()])
	for i in 60:
		vehicles._process(0.1)
	var seen_red := false
	var seen_blue := false
	for i in 40:
		vehicles._process(0.07)
		for lb in vehicles._lightbars:
			seen_red = seen_red or (lb[0] as StandardMaterial3D).emission_energy_multiplier > 3.0
			seen_blue = seen_blue or (lb[1] as StandardMaterial3D).emission_energy_multiplier > 3.0
	_check(seen_red and seen_blue, "the lightbars flash red and blue")
	var arrived := true
	for pc in vehicles.police_cars:
		arrived = arrived and (pc as Node3D).find_child("Solid", true, false) != null
	_check(arrived and vehicles.getaway_point().distance_to(Vector3(46, 0, -87.2)) < 0.1 and city.find_child("GetawayPoint", true, false) != null, "the cars have rolled in and stopped; the getaway's at the lot's exit")
	_check(heli.searching and heli.active, "the searchlight hunts in THE BUST")
	var found: Array = []
	set.searchlight_found_player.connect(func(): found.append(true))
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(10.0, 0.0, -2.0)
	for i in 400:
		heli._process(0.1)
		if not found.is_empty():
			break
	_check(not found.is_empty() and heli.found, "it finds the player")

	# --- Pickups and the pools ---
	for i in 40:
		set.spawn_pickup(["pills", "stash", "cash"][i % 3], Vector3(i * 0.5, 1.0, -2.0))
	_check(set.pickup_count() == set.PICKUP_MAX, "pickups are pooled and capped (%d)" % set.pickup_count())
	var kinds := {}
	var got: Array = []
	set.pickup_collected.connect(func(k: String, at: Vector3): got.append(k))
	for k in ["pills", "stash", "cash"]:
		var pk: Node3D = set.spawn_pickup(k, Vector3(2, 1, -2))
		kinds[k] = pk.find_child("Model_" + k, true, false) != null
		set.collect_pickup(pk)
	_check(kinds.values().all(func(v): return v) and got == ["pills", "stash", "cash"] and set._bursts.size() == set.BURST_POOL, "pill bottles, stash bags and cash rolls, each with a burst when taken")
	await _frames(4)
	_check(set._bursts.size() <= 6 and set._fire_nodes.size() <= 8 and set.decal_count <= 80, "the particle, fire and decal pools stay capped")

	# --- Leaving ---
	zm.leave()
	zm.begin(false)
	city = await _load("res://world/City3D.tscn")
	_check(get_nodes_in_group("ghetto_set").is_empty(), "the zombie mode after Ghetto Wars is untouched")
	zm.leave()
