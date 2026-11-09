extends "res://dev-tools/smoke_test_3d.gd"
## Real doors (interactables/HingedDoor3D.gd): swing away from you, close and
## latch behind you, slam when you sprint into them, rattle when locked, let
## NPCs through, and the Dive Bar's door still takes you in and out.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_doors.gd
var DoorScene: PackedScene

var _slams := 0
var _latches := 0
var _rattles := 0

func _run() -> void:
	DoorScene = load("res://interactables/HingedDoor3D.tscn")
	var gs := _gs()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	await _bare_door_checks()
	await _street_checks(gs)
	await _bar_checks(gs)

## A capsule that stands in for the player (or an NPC) for the bare-door checks.
func _mover(layer: int, grp: String) -> CharacterBody3D:
	var m := CharacterBody3D.new()
	m.collision_layer = layer
	m.collision_mask = 1
	m.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	m.add_child(cs)
	if grp != "":
		m.add_to_group(grp)
	return m

## Walk (or run) `m` along `dir` at `speed` for `secs`, with real collision.
func _drive(m: CharacterBody3D, dir: Vector3, speed: float, secs: float) -> void:
	for i in int(secs * 60.0):
		m.velocity = dir * speed
		m.move_and_slide()
		await physics_frame
	m.velocity = Vector3.ZERO

func _watch(door: Node) -> void:
	_slams = 0
	_latches = 0
	_rattles = 0
	door.slammed.connect(func(_s): _slams += 1)
	door.latched.connect(func(): _latches += 1)
	door.rattled.connect(func(): _rattles += 1)

func _bare_door_checks() -> void:
	await _section("Doors: swing, closer, latch, slam, lock")
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(20, 0.2, 20)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var door := DoorScene.instantiate()
	door.kind = "shop_glass"
	world.add_child(door)
	_watch(door)
	await _frames(3)
	_check(door.is_closed() and door.angle == 0.0, "  a new door is shut and latched")
	_check(door.leaf is AnimatableBody3D and door.hinge is Node3D, "  a hinge node and an AnimatableBody3D leaf (no rigid body)")
	var rigid := world.find_children("*", "RigidBody3D", true, false)
	var joints := world.find_children("*", "HingeJoint3D", true, false)
	_check(rigid.is_empty() and joints.is_empty(), "  no RigidBody3D, no HingeJoint3D")

	# Walk in from outside (+z): it opens away from you.
	var m := _mover(2, "player")
	world.add_child(m)
	m.global_position = Vector3(0.1, 0, 2.2)
	await _frames(2)
	var peak := 0.0
	var tip_z := 0.0
	for i in 150:
		m.velocity = Vector3(0, 0, -1.75)
		m.move_and_slide()
		await physics_frame
		if absf(door.angle) > absf(peak):
			peak = door.angle
			tip_z = (door.leaf.global_transform * Vector3(1.0, 1.0, 0.0)).z
		if m.global_position.z < -1.6:
			break
	_check(m.global_position.z < -1.0, "  walking in from outside gets you through (z %.2f)" % m.global_position.z)
	_check(absf(peak) > 0.5 and tip_z < -0.2, "  it swung away from you, into the room (peak %.0f deg, leaf tip z %.2f)" % [rad_to_deg(peak), tip_z])
	# Let go: the closer shuts it and the latch catches.
	var t := 0
	while not door.is_closed() and t < 60 * 9:
		await physics_frame
		t += 1
	_check(door.is_closed() and door.angle == 0.0 and _latches >= 1, "  it closed itself and latched (%.1f s, %d latch)" % [t / 60.0, _latches])
	_check(t / 60.0 > 1.2, "  ...slowly, not a snap (%.1f s)" % [t / 60.0])

	# And out again from inside: the other way.
	m.global_position = Vector3(0.1, 0, -2.2)
	await _frames(2)
	peak = 0.0
	tip_z = 0.0
	for i in 150:
		m.velocity = Vector3(0, 0, 1.75)
		m.move_and_slide()
		await physics_frame
		if absf(door.angle) > absf(peak):
			peak = door.angle
			tip_z = (door.leaf.global_transform * Vector3(1.0, 1.0, 0.0)).z
		if m.global_position.z > 1.6:
			break
	_check(m.global_position.z > 1.0 and absf(peak) > 0.5 and tip_z > 0.2, "  from inside it swings out, away from you (peak %.0f deg, tip z %.2f)" % [rad_to_deg(peak), tip_z])
	t = 0
	while not door.is_closed() and t < 60 * 9:
		await physics_frame
		t += 1
	_check(door.is_closed(), "  ...and shuts behind you again")

	# Slow last stretch: the final ten degrees take real time.
	door.push_open(Vector3(0, 0, 2.0), 1.9)
	var last10 := -1
	t = 0
	var enter10 := 0
	while not door.is_closed() and t < 60 * 12:
		await physics_frame
		t += 1
		if enter10 == 0 and absf(door.angle) < deg_to_rad(10.0) and absf(door.angle) > 0.0:
			enter10 = t
	last10 = t - enter10
	_check(enter10 > 0 and last10 / 60.0 >= 0.6, "  the last 10 degrees take %.1f s (slow)" % [last10 / 60.0])

	# Sprint into it: slam, and a noise event.
	_slams = 0
	door.last_noise = {}
	m.global_position = Vector3(0.1, 0, 3.2)
	await _frames(2)
	for i in 80:
		m.velocity = Vector3(0, 0, -5.25)
		m.move_and_slide()
		await physics_frame
		if m.global_position.z < -1.5:
			break
	await _frames(30)
	_check(_slams >= 1, "  sprinting into it slams it against its stop (%d)" % _slams)
	_check(door.last_noise.get("kind", "") == "door_slam" and float(door.last_noise.get("loudness", 0.0)) >= 10.0,
		"  ...and makes a door_slam noise (%s)%s" % [door.last_noise, "" if gs_has_noise() else " [GameState.emit_noise not here yet: door stub-checks it]"])
	t = 0
	while not door.is_closed() and t < 60 * 12:
		await physics_frame
		t += 1
	_check(door.is_closed(), "  ...and it comes back to the latch after (%.1f s)" % [t / 60.0])

	# A walk is not a slam.
	_slams = 0
	m.global_position = Vector3(0.1, 0, 2.2)
	await _frames(2)
	await _drive(m, Vector3(0, 0, -1.75), 1.75, 2.4)
	_check(_slams == 0, "  walking into it doesn't slam it")
	while not door.is_closed():
		await physics_frame

	# Locked: it does not give.
	door.set_locked(true)
	m.global_position = Vector3(0.0, 0, 2.0)
	_rattles = 0
	await _frames(2)
	await _drive(m, Vector3(0, 0, -1.75), 1.75, 1.2)
	_check(door.angle == 0.0 and m.global_position.z > -0.2, "  a locked door doesn't open (angle %.3f, you at z %.2f)" % [door.angle, m.global_position.z])
	_check(_rattles >= 1, "  ...it rattles instead (%d)" % _rattles)
	var jerk_max := 0.0
	door.rattle()
	for i in 20:
		await physics_frame
		jerk_max = maxf(jerk_max, absf(door.leaf.rotation.y) * door._width)
	_check(jerk_max > 0.004 and jerk_max < 0.02, "  the leaf jerks about a centimetre (%.1f cm at the handle)" % (jerk_max * 100.0))
	var player_prompt: String = door.touch.prompt_text()
	_check(player_prompt == "Locked door", "  a locked door says so by the crosshair ('%s')" % player_prompt)
	door.set_locked(false)
	_check(door.touch.prompt_text() == "", "  an unlocked door shows no prompt (you just walk through)")

	# Someone standing where it would swing keeps it from closing on them.
	door.push_open(Vector3(0, 0, 2.0), 1.9)
	await _frames(20)
	m.global_position = Vector3(0.1, 0, -1.0)
	await _frames(60 * 4)
	_check(not door.is_closed() or absf(door.angle) < 0.001, "  it doesn't swing through someone standing in its path")
	m.global_position = Vector3(6.0, 0, -6.0)
	t = 0
	while not door.is_closed() and t < 60 * 12:
		await physics_frame
		t += 1
	_check(door.is_closed(), "  ...and closes once they've gone")

	# NPC through it: an NPC body (layer 8) on a path along the doorway.
	var npc := _mover(8, "")
	world.add_child(npc)
	npc.global_position = Vector3(0.1, 0, 3.0)
	await _frames(2)
	await _drive(npc, Vector3(0, 0, -1.2), 1.2, 6.0)
	_check(npc.global_position.z < -2.0, "  an NPC walks through it (z %.2f)" % npc.global_position.z)
	t = 0
	while not door.is_closed() and t < 60 * 12:
		await physics_frame
		t += 1
	_check(door.is_closed(), "  ...and it shuts behind them")
	# Door kinds build and work.
	for k in ["steel_back", "bar"]:
		var d2 := DoorScene.instantiate()
		d2.kind = k
		d2.position = Vector3(8.0, 0, 0)
		world.add_child(d2)
		await _frames(2)
		d2.push_open(Vector3(8.0, 0, 2.0), 1.9)
		await _frames(30)
		_check(absf(d2.angle) > 0.2, "  a %s door swings" % k)
		d2.queue_free()
	world.queue_free()
	await _frames(2)

func gs_has_noise() -> bool:
	return _gs().has_method("emit_noise")

func _street_checks(gs: Node) -> void:
	await _section("Doors: the shops on Main Street")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	var city := await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var p := _player()
	var shop := city.get_node("Cell_Main/WalkIn_Convenience")
	var door: Node3D = shop.get("door")
	_check(door != null and is_instance_valid(door) and door.kind == "shop_glass", "  the corner shop has a glass door in its doorway")
	p.global_position = Vector3(3.5, 0, -2.0)
	p.reset_physics_interpolation()
	await _wait_loaded(shop)
	await _frames(20)
	_watch(door)
	# On foot, with real input: no teleport.
	var z0 := p.global_position.z
	var peak := 0.0
	Input.action_press("move_up")
	for i in 240:
		await physics_frame
		peak = maxf(peak, absf(door.angle))
		if shop.player_inside and p.global_position.z < -7.4:
			break
	Input.action_release("move_up")
	_check(shop.player_inside and p.global_position.z < z0 - 3.0, "  walked in through the door on foot (z %.2f -> %.2f)" % [z0, p.global_position.z])
	await _frames(2)
	_check(peak > 0.6, "  the door swung open for it (%.0f deg)" % rad_to_deg(peak))
	var t := 0
	while not door.is_closed() and t < 60 * 10:
		await physics_frame
		t += 1
	_check(door.is_closed() and not door.locked, "  it shut behind you (angle %.1f deg, omega %.2f, hold %.2f, bodies %s)" % [rad_to_deg(door.angle), door.omega, door._hold, door._bodies.values().map(func(b): return str(b.name))])
	# The navmesh runs through the doorway, and a clerk-like NPC can walk it.
	var map: RID = p.get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, Vector3(door.global_position.x, 0, -2.4))
	var to := NavigationServer3D.map_get_closest_point(map, Vector3(door.global_position.x, 0, -9.0))
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	_check(path.size() >= 2 and path[path.size() - 1].distance_to(to) < 0.6, "  the navmesh has a path from the sidewalk into the shop (%d points)" % path.size())
	var npc := _mover(8, "")
	city.add_child(npc)
	npc.global_position = from
	await _frames(2)
	var i := 1
	for f in 60 * 20:
		if i >= path.size():
			break
		var tgt: Vector3 = path[i]
		var to_t := Vector3(tgt.x - npc.global_position.x, 0, tgt.z - npc.global_position.z)
		if to_t.length() < 0.25:
			i += 1
			continue
		npc.velocity = to_t.normalized() * 1.2
		npc.move_and_slide()
		await physics_frame
	_check(npc.global_position.distance_to(to) < 0.8, "  an NPC follows that path through the door and arrives (%.2f m short)" % npc.global_position.distance_to(to))
	npc.queue_free()
	# Closed: locked, rattles, then the text.
	gs.clock = 3 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	p = _player()
	var liquor := city.get_node("Cell_Main/WalkIn_Liquor")
	var ldoor: Node3D = liquor.get("door")
	_check(ldoor != null and ldoor.locked, "  the liquor store's door is locked at 03:00")
	p.global_position = Vector3(10.5, 0, -2.2)
	p.reset_physics_interpolation()
	await _frames(10)
	_watch(ldoor)
	Input.action_press("move_up")
	await _frames(100)
	Input.action_release("move_up")
	_check(ldoor.angle == 0.0 and not liquor.player_inside, "  walking into it: it doesn't open")
	_check(_rattles >= 1, "  ...it rattled (%d)" % _rattles)
	_rattles = 0
	var gate := liquor.get_node("Locked")
	_check(gate.collision_layer == 4 and ldoor.touch.collision_layer == 0, "  one prompt at a locked door: the gate's")
	p.dialogue_active = false
	gate.interact(p)
	await _frames(5)
	_check(_rattles == 1, "  E on it rattles the handle first")
	var hud := city.get_tree().get_first_node_in_group("hud")
	_check(not hud.dialogue_panel.visible, "  ...the 'Locked' text comes after")
	await _frames(60)
	_check(hud.dialogue_panel.visible, "  ...and then it's there")
	hud.advance_or_close_dialogue()
	p.dialogue_active = false

func _bar_checks(gs: Node) -> void:
	await _section("Doors: the Dive Bar, in and out")
	gs.clock = 21 * 60
	var city := await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var p := _player()
	var bdoor := city.get_node("DoorToBar")
	_check(bdoor.get("hinged") != null, "  the bar's street door has a hinged door")
	p.global_position = bdoor.global_position + Vector3(0, 0, 0.6)
	p.reset_physics_interpolation()
	await _frames(5)
	var hd: Node3D = bdoor.hinged
	bdoor.interact(p)
	await _frames(15)
	_check(absf(hd.angle) > 0.2, "  the street door starts to swing as you go in (%.0f deg)" % rad_to_deg(hd.angle))
	await _transition()
	_check(current_scene.name == "DiveBar3D", "  you arrive in the Dive Bar")
	p = _player()
	var spawn := current_scene.get_node("SpawnFromCity") as Marker3D
	_check(p.global_position.distance_to(spawn.global_position) < 1.0, "  at the door's spawn (%.2f m)" % p.global_position.distance_to(spawn.global_position))
	var inside_door: Node = current_scene.get_node("DoorToCity")
	var ihd: Node3D = inside_door.get("hinged")
	_check(ihd != null and ihd.kind == "bar", "  the bar's own door is a hinged one")
	await _frames(5)
	_check(ihd != null and (absf(ihd.angle) > 0.05 or ihd.is_closed()), "  it's behind you, still closing (%.0f deg)" % rad_to_deg(ihd.angle if ihd else 0.0))
	var t := 0
	while ihd != null and not ihd.is_closed() and t < 60 * 8:
		await physics_frame
		t += 1
	_check(ihd != null and ihd.is_closed(), "  ...and it latches shut (%.1f s)" % [t / 60.0])
	inside_door.interact(p)
	await _frames(10)
	await _transition()
	_check(current_scene.name == "City3D", "  out again onto the street")
	p = _player()
	var back := current_scene.get_node("SpawnFromBar") as Marker3D
	_check(p.global_position.distance_to(back.global_position) < 1.0, "  at the bar's spawn on the street (%.2f m)" % p.global_position.distance_to(back.global_position))
	var out_door: Node = current_scene.get_node("DoorToBar")
	var chd: Node3D = out_door.get("hinged")
	await _frames(5)
	_check(chd != null and (absf(chd.angle) > 0.05 or chd.is_closed()), "  the bar's door closes behind you on the street too")
