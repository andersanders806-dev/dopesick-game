extends SceneTree
## Dev helper: a played run of the tsunami escape, for the movie writer. The quake hits, the warning comes, the
## player runs the passable route to the high ground (the real controls: sprint + forward + look, no teleport; it
## fails loudly if the zone is not reached), holds the head of the stair shooting the dead that follow, then
## watches the wave break over the block from the deck, the flood and what comes after. The clock is shortened
## (CLOCK, set after the intro) so the clip stays short; the player can't die (the point is to see the event).
##   flatpak run org.godotengine.Godot --path . --write-movie .pilot/high_ground.avi --fixed-fps 30 \
##     -s res://dev-tools/video_high_ground.gd
const CLOCK := 62.0
const DT := 1.0 / 30.0
const START := Vector3(34.0, 0.0, -3.0)
## The way that never passes an alley barricade (the same anchors as smoke_zombie_tsunami).
const ANCHORS := [Vector3(75.5, 0, -3.0), Vector3(75.5, 0, -40.5), Vector3(68.0, 0, -41.0)]
## Then by hand: the gaps in the camp's and the lot's fences, across the lot, up the stair.
const STAIR_RUN := [Vector3(57.5, 0, -42.5), Vector3(46.0, 0, -40.0), Vector3(38.5, 0, -36.0), Vector3(38.5, 0, -29.5),
	Vector3(46.0, 0, -29.5), Vector3(62.0, 0, -29.5)]

var p: CharacterBody3D
var block: Node
var ts: Node
var hg: Node3D
var zm: Node
var frames := 0

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	zm = root.get_node("ZombieMode")
	root.get_node("GameState").no_sickness = true
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	p = get_first_node_in_group("player") as CharacterBody3D
	ts = block.tsunami
	hg = block.high_ground
	zm.health = 1e9
	var h: Node = p.get_node("WeaponHolder")
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	p.global_position = START
	p.set_look(PI / 2.0, 0.0)
	await _secs(5.0, func(): _shoot_nearest(h, 25.0))
	# The quake (the surge) -- the tsunami starts with it.
	block.surge.trigger()
	await _secs(1.0)
	# Wait out the intro, then shorten the clock (the tsunami resets it after the intro).
	while not ts.warned:
		await process_frame
		frames += 1
	if ts.remaining > CLOCK:
		ts.remaining = CLOCK
	print("VIDEO warned t=%.1f clock %.1f" % [_now(), ts.remaining])
	var t0 := _now()
	var ok := await _run_route(h)
	print("VIDEO run %.1f s, in zone=%s, clock left %.1f" % [_now() - t0, ok, ts.remaining])
	if not ok:
		push_error("VIDEO FAILED: the player did not reach the high ground on foot")
		quit(1)
		return
	# Hold the head of the stair, facing down it, and shoot whatever follows.
	Input.action_release("sprint")
	Input.action_release("move_up")
	while ts.phase == ts.Phase.COUNTDOWN and ts.remaining > 7.0:
		_hold_drowned()
		_hold_stair(h)
		await process_frame
		frames += 1
	Input.action_release("fire")
	# Last seconds: step to the middle of the deck, look down the street to the west.
	print("VIDEO last seconds t=%.1f clock %.1f" % [_now(), ts.remaining])
	await _face_west(7.0, h)
	print("VIDEO in zone at 0:00 = %s" % hg.zone_contains(p.global_position))
	var impact_t := -1.0
	var t := 0.0
	while t < 60.0 and not (ts.phase == ts.Phase.IDLE and t > 6.0):
		await process_frame
		frames += 1
		t += DT
		if impact_t < 0.0 and ts.fired.has("impact"):
			impact_t = _now()
			print("VIDEO impact at video t=%.2f s (frame %d)" % [impact_t, int(impact_t * 30.0)])
		_hold_drowned()
		if _shoot_nearest(h, 7.0):
			continue
		Input.action_release("fire")
		var yaw: float = p.get("_look_yaw")
		p.set_look(lerp_angle(yaw, PI / 2.0 - 0.45 + clampf(t * 0.04, 0.0, 0.6), 0.04), lerpf(float(p.get("_look_pitch")), -0.12 if t < 3.0 else -0.5, 0.04))
	print("VIDEO after flood survived=%s swept=%d alive=%d round=%d wet=%.2f" % [ts.survived, ts.swept, get_nodes_in_group("zombies").size(), zm.round, ts._wet])
	# After: the run goes on.
	await _secs(8.0, func(): _shoot_nearest(h, 35.0))
	Input.action_release("fire")
	print("VIDEO end t=%.1f" % _now())
	zm.leave()
	quit()

func _now() -> float:
	return float(frames) * DT

func _secs(s: float, each := Callable()) -> void:
	var t := 0.0
	while t < s:
		await process_frame
		frames += 1
		t += DT
		if each.is_valid():
			each.call()

## Walks to the middle of the deck, then turns to look west down the street; the dead that get close are shot
## first (the Drowned are held at the foot of the stair so they do not fill the lens: this is a camera tool).
func _face_west(secs: float, h: Node) -> void:
	var t := 0.0
	# to the deck's west barrier (a low wall: you only see the street below from right up against it)
	var to_mid := Vector3(57.0, 0.0, -22.5)
	while t < secs:
		await process_frame
		frames += 1
		t += DT
		_hold_drowned()
		var d := to_mid - p.global_position
		d.y = 0.0
		if d.length() > 0.7 and t < 2.0:
			Input.action_press("move_up")
			p.set_look(lerp_angle(float(p.get("_look_yaw")), atan2(-d.x, -d.z), 0.3), 0.0)
			continue
		Input.action_release("move_up")
		if _shoot_nearest(h, 7.0):
			continue
		p.set_look(lerp_angle(float(p.get("_look_yaw")), PI / 2.0 - 0.3, 0.06), lerpf(float(p.get("_look_pitch")), -0.1, 0.06))
	Input.action_release("move_up")
	Input.action_release("fire")

func _hold_drowned() -> void:
	for d in ts.drowned:
		if is_instance_valid(d) and d.global_position.distance_to(p.global_position) < 26.0:
			d.set_physics_process(false)

## The navmesh path between the anchors, then straight up the stair.
func _route(start: Vector3) -> PackedVector3Array:
	var map := p.get_world_3d().navigation_map
	var pts := PackedVector3Array([start])
	var from := start
	for a in ANCHORS:
		var seg := NavigationServer3D.map_get_path(map, from, a, true)
		for i in range(1, seg.size()):
			pts.append(Vector3(seg[i].x, 0.0, seg[i].z))
		from = a
	for q in STAIR_RUN:
		pts.append(q)
	return pts

## Follows the route with the real controls. True once the player stands in the zone.
func _run_route(h: Node) -> bool:
	var route := _route(p.global_position)
	for b in get_nodes_in_group("barricades"):
		for pt in route:
			var d := Vector2(pt.x - b.global_position.x, pt.z - b.global_position.z).length()
			if d < 1.5:
				push_error("VIDEO FAILED: the route passes a barricade at %s" % pt)
				return false
	var i := 1
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	Input.action_press("move_up")
	Input.action_press("sprint")
	while t < 90.0 and not hg.zone_contains(p.global_position):
		await process_frame
		frames += 1
		t += DT
		# the dead in the way are shot down (the run is not a ghost run), then on
		if _shoot_nearest(h, 3.2):
			Input.action_release("move_up")
			stuck = 0.0
			continue
		Input.action_press("move_up")
		Input.action_release("fire")
		var target := route[mini(i, route.size() - 1)]
		var to := target - p.global_position
		to.y = 0.0
		if to.length() < 0.9 and i < route.size() - 1:
			i += 1
			continue
		p.set_look(lerp_angle(float(p.get("_look_yaw")), atan2(-to.x, -to.z), 0.3), 0.0)
		if p.global_position.distance_to(last) < 0.01:
			stuck += DT
		else:
			stuck = 0.0
		last = p.global_position
		if stuck > 3.0:
			push_error("VIDEO FAILED: stuck at %s (point %d of %d)" % [p.global_position, i, route.size()])
			break
	Input.action_release("move_up")
	return hg.zone_contains(p.global_position)

## At the head of the stair: face down it and shoot the nearest of the dead that climb.
func _hold_stair(h: Node) -> void:
	var post := Vector3(57.6, 0.0, -29.5)
	var d := post - p.global_position
	d.y = 0.0
	if d.length() > 0.6:
		Input.action_press("move_up")
		p.set_look(lerp_angle(float(p.get("_look_yaw")), atan2(-d.x, -d.z), 0.3), 0.0)
		return
	Input.action_release("move_up")
	var found := _shoot_nearest(h, 40.0)
	if not found:
		p.set_look(lerp_angle(float(p.get("_look_yaw")), PI / 2.0, 0.1), lerpf(float(p.get("_look_pitch")), -0.3, 0.1))

## Aims at the nearest living zombie and holds the trigger. False if there is none in reach.
func _shoot_nearest(h: Node, reach: float) -> bool:
	var best: Node3D = null
	var best_d := reach
	for z in get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or int(z.get("state")) >= 5 or float(z.get("body_scale")) > 1.6:
			continue
		var d: float = z.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = z
	if best == null:
		Input.action_release("fire")
		return false
	var eye := p.global_position + Vector3(0, 1.6, 0)
	var to := best.global_position + Vector3(0, 1.3, 0) - eye
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	p.set_look(lerp_angle(float(p.get("_look_yaw")), yaw, 0.25), lerpf(float(p.get("_look_pitch")), pitch, 0.25))
	if h.mag <= 0:
		h.refill_all()
	Input.action_press("fire")
	return true
