extends "res://npc/Guard3D.gd"
## A beat cop walking the block. His beat is a loop round all four streets
## (Schedules.PATROL_ROUTE, the sidewalk beside the road, from the police
## station and back), walked on the navmesh from waypoint to waypoint with
## now and then a stop to look around. Same eyes as the shop staff (a vision
## cone that goes amber, then red), but out on the street he cares about
## different things: someone carrying goods, someone running with them,
## and above all a hand-to-hand at the pusher's corner. When his suspicion
## fills he calls it in and gives chase himself (City3D swaps him for a
## Police3D). The pusher watches for him too and melts away when he's near.
##
## Created in code by City3D.gd on a Guard3D.tscn instance.

const WALK_SPEED := 1.25
## Stops at a waypoint to look around, now and then.
const PAUSE_CHANCE := 0.4
const PAUSE_TIME := Vector2(2.0, 4.5)
## The clock has gone this far (game minutes) while he was frozen in a
## sleeping cell: he is put where the loop says he'd be by now.
const SNAP_GAP := 20.0

const RATE_CARRYING := 0.22
const RATE_RUNNING_WITH_GOODS := 1.1
## Watching you buy from the pusher is the one thing he's out here for.
const RATE_HAND_TO_HAND := 2.6
const HAND_TO_HAND_RANGE := 3.0
## With a warrant out, he's seen your face on the board at roll call.
const RATE_WARRANT := 0.9

## +1 walks the loop clockwise from the station, -1 the other way.
var heading: float = 1.0
var route_index: int = -1
var _pause_timer: float = 0.0
var _path := PackedVector3Array()
var _path_i: int = 0
var _last_minute: float = -1.0e9
## In a sleeping cell and out of sight: he stands as he was, not simulated
## (in sight, down a long street, he just walks on).
var _frozen := false
var _frozen_t := 0.0
var _cells: Node = null

func _ready() -> void:
	# He has his own business on the street: the stealth layer's hearing is the shops'.
	hears_noise = false
	super._ready()
	add_to_group("patrol")
	_last_minute = GameState.now_minutes()

## Frozen in a sleeping cell out of sight (he stands as he was -- hiding
## him would pop). Woken after the clock has gone on, he is put back on the
## beat by the loop's clock -- but not in front of the player: if that spot
## (or where he stands) is in sight he is carried on along the loop until he
## would be out of it, or left where he is and walks from there.
func refresh() -> void:
	if not visible:
		visible = true
	if absf(GameState.now_minutes() - _last_minute) > SNAP_GAP:
		_last_minute = GameState.now_minutes()
		if Schedules.is_seen(global_position):
			return
		var extra := 0.0
		while extra < 440.0:
			var at: Dictionary = Schedules.patrol_point(GameState.now_minutes(), int(heading), extra)
			if not Schedules.is_seen(at["pos"]):
				global_position = at["pos"]
				reset_physics_interpolation()
				route_index = at["index"]
				_path = PackedVector3Array()
				return
			extra += 6.0

func _physics_process(delta: float) -> void:
	_frozen_t -= delta
	if _frozen_t <= 0.0:
		_frozen_t = 0.25
		if _cells == null and is_inside_tree():
			_cells = get_tree().current_scene.get_node_or_null("BlockCells")
		_frozen = _cells != null and _cells.asleep_at(global_position) and not Schedules.is_seen(global_position)
	if _frozen:
		return
	if absf(GameState.now_minutes() - _last_minute) > SNAP_GAP:
		refresh()
	_last_minute = GameState.now_minutes()
	if _pause_timer > 0.0:
		_pause_timer -= delta
		anim.update(0.0)
	else:
		_follow(delta)
	super._physics_process(delta)

## Along the path to the next waypoint; at it, on to the one after.
func _follow(delta: float) -> void:
	var route: Array[Vector3] = Schedules.patrol_route()
	if route_index < 0:
		route_index = _first_waypoint(route)
	if _path_i >= _path.size():
		var map: RID = get_world_3d().navigation_map
		_path = NavigationServer3D.map_get_path(map, global_position, route[route_index], true)
		_path_i = 0
		if _path.size() == 0:
			anim.update(0.0)
			return
	var to := _path[_path_i] - global_position
	to.y = 0.0
	var step := WALK_SPEED * delta
	if to.length() <= maxf(step, 0.05):
		global_position = Vector3(_path[_path_i].x, 0.0, _path[_path_i].z)
		_path_i += 1
		if _path_i >= _path.size():
			route_index = posmod(route_index + int(heading), route.size())
			_path = PackedVector3Array()
			if randf() < PAUSE_CHANCE:
				_pause_timer = randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
		return
	var dir := to.normalized()
	global_position += dir * step
	global_position.y = 0.0
	base_facing_deg = rad_to_deg(atan2(dir.z, dir.x))
	anim.update(WALK_SPEED)

## The nearest waypoint, or the next one if the nearest is behind him.
func _first_waypoint(route: Array[Vector3]) -> int:
	var best := 0
	for i in route.size():
		if route[i].distance_squared_to(global_position) < route[best].distance_squared_to(global_position):
			best = i
	var ahead := route[posmod(best + int(heading), route.size())] - route[best]
	if (route[best] - global_position).dot(ahead) < 0.0 and route[best].distance_to(global_position) > 1.0:
		best = posmod(best + int(heading), route.size())
	return best

func _update_suspicion(player: Node, delta: float) -> void:
	if GameState.in_custody or _alarm_raised or GameState.wanted:
		return
	var rate := 0.0
	if can_see_player and player != null and is_instance_valid(player):
		if GameState.warrant:
			rate += RATE_WARRANT
		var carrying := GameState.carrying_stolen()
		if carrying:
			rate += RATE_CARRYING
			if player.has_method("is_sprinting") and player.is_sprinting():
				rate += RATE_RUNNING_WITH_GOODS
		var pusher := get_tree().get_first_node_in_group("pusher") as Node3D
		if pusher and pusher.get("state") in [pusher.State.AWAIT_BUYER, pusher.State.HANDOFF] \
				and pusher.global_position.distance_to(player.global_position) <= HAND_TO_HAND_RANGE:
			rate += RATE_HAND_TO_HAND
	if rate > 0.0:
		suspicion = minf(1.0, suspicion + rate * MetaProgress.suspicion_scale() * delta)
	else:
		suspicion = maxf(0.0, suspicion - SUSPICION_DECAY * delta)
	if suspicion >= SUSPICION_NOTICED and not _was_noticed:
		_was_noticed = true
		suspicion_raised.emit()
	elif suspicion < SUSPICION_NOTICED:
		_was_noticed = false
	if suspicion >= 1.0:
		_alarm_raised = true
		spotted_theft.emit()
