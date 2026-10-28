extends CharacterBody3D
## Someone with somewhere to be (autoload/Schedules.gd has the list): they
## keep their entries on the block -- walk to the next place when its time
## comes, sit, lean, shuffle about, or go indoors and come out again.
## Built in code by City3D.gd on a Rocketbox body; there's no scene.
##
## Three tiers, so a dozen of them cost almost nothing:
##   near (FULL_RANGE of the player): physics every tick, walking along the
##     navmesh, animated; the NavigationAgent3D steers round the player and
##     the others only within AVOID_RANGE.
##   far, in an awake cell: every FAR_EVERY-th tick, stepping along the path
##     by the time that has gone by; the model isn't processed, so one the
##     camera can see is stepped by hand (a lower frame rate, not a frozen
##     pose gliding along).
##   in a sleeping cell: BlockCells freezes them (group cell_sleepers). They
##     are not simulated; they stand as they were (hiding a frozen person
##     would pop). When the cell wakes and the clock has gone on, _catch_up()
##     puts them where position_at() says -- if neither place is in sight.
##
## The rule for all of it: nobody appears, vanishes, teleports or changes
## pose while the player could see it (Schedules.is_seen). A change that is
## due waits until it is unseen; a person who has to go in at a door walks to
## it first, and one who comes out of a door waits until nobody is looking.

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const HeadTurn := preload("res://npc/HeadTurn.gd")

const WALK_SPEED := 1.2
const FULL_RANGE := 40.0
const AVOID_RANGE := 10.0
const FAR_EVERY := 15
## Far but in the camera's view: logic and animation this often (about 15 Hz).
const FAR_EVERY_VIEWED := 4
## How often the schedule is looked at (seconds).
const PLAN_PERIOD := 0.5
## A clock that has gone this far (game minutes) since the last tick -- a
## sleeping cell, a load, a night's sleep -- isn't walked through: the
## person is put where the entry in force says.
const SNAP_GAP := 20.0
const ARRIVE := 0.35
const TURN_SPEED := 6.0
const WANDER_RADIUS := 1.1
const WANDER_PAUSE := Vector2(2.5, 6.0)
## Places with a door to walk into: the last metre is walked, then they go in
## (in sight or not). Everywhere else (the bench, the court, the camp, the bus
## stop) they only go in, or come out, where nobody is looking.
const DOORS := ["Stoop1", "Stoop2", "Stoop3"]
## How fast a seat is raised or lowered (m/s): standing up isn't a snap.
const LIFT_SPEED := 0.6

var person := ""
var look_index := 0
var nav_agent: NavigationAgent3D
var anim: CharacterAnimator
## The entry being played: {"from","place","activity"} and where it is.
var goal: Dictionary = {}
var goal_pos := Vector3.INF
var indoors := false

var _model_root: Node3D
var _full := true
var _walking := false
var _plan_t := 0.0
var _last_minute := -1.0e9
var _far_ticks := 0
var _far_dt := 0.0
var _wander_t := 0.0
var _wander_to := Vector3.INF
var _facing := 0.0
var _speed := WALK_SPEED
var _rest_clip := "idle"
var _phase := 0.0
var _lift_target := 0.0
## Far from the player but in the camera's view: still animated.
var _viewed := false

func _ready() -> void:
	add_to_group("scheduled_people")
	add_to_group("cell_sleepers")
	collision_layer = 8
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.1
	shape.shape = cap
	shape.position = Vector3(0, 0.55, 0)
	add_child(shape)
	nav_agent = NavigationAgent3D.new()
	nav_agent.radius = 0.35
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.4
	nav_agent.avoidance_enabled = false
	nav_agent.max_speed = WALK_SPEED * 1.2
	add_child(nav_agent)
	nav_agent.velocity_computed.connect(_on_safe_velocity)
	_model_root = Node3D.new()
	_model_root.scale = Vector3.ONE * 1.5
	add_child(_model_root)
	var role := Schedules.role_of(person)
	var model: Node = CharacterCast.scene_for(CharacterCast.model_for(role)).instantiate()
	_model_root.add_child(model)
	CharacterLook.apply(model, CharacterCast.look_for(role))
	anim = CharacterAnimator.new(model)
	HeadTurn.attach(model)
	_speed = WALK_SPEED * (0.9 + 0.2 * fposmod(float(person.hash() % 100) / 100.0, 1.0))
	_phase = float(person.hash() % 628) / 100.0
	nav_agent.max_speed = _speed * 1.2

func _now() -> float:
	return GameState.now_minutes()

func _minute() -> int:
	return int(fposmod(_now(), float(Schedules.DAY)))

## Puts them where the entry in force says they are: used when they are
## made (the room's fade covers it) and by _catch_up() once it is certain
## nobody could see the move.
func resync() -> void:
	_last_minute = _now()
	var e := Schedules.entry_at(person, _minute())
	_apply_goal(e, true)
	if goal_pos != Vector3.INF:
		global_position = goal_pos
		reset_physics_interpolation()
	_walking = false
	_wander_to = Vector3.INF
	_set_indoors(goal.get("activity", "") == "sleep")
	_face_goal()
	_seat(true)

func _apply_goal(e: Dictionary, instant := false) -> void:
	goal = e
	if e.is_empty():
		goal_pos = Vector3.INF
		return
	var place: String = e["place"]
	if e["activity"] == "sleep" and place in DOORS:
		# Going in: to the door itself.
		goal_pos = Schedules.place_position(place)
	else:
		goal_pos = Schedules.position_for(person, place)
	# On their way in they keep the pose they have until they're gone:
	# standing up through a bench is a pop.
	if e["activity"] == "sleep" and not indoors and not instant:
		return
	_rest_clip = "sit" if e["activity"] == "sit" else "idle"
	anim.set_rest_clip(_rest_clip)
	_seat(instant)

func _set_indoors(on: bool) -> void:
	indoors = on
	refresh()

## City3D calls this when a cell wakes or sleeps (and every so often): hidden
## when indoors; and, now that they are running again, brought up to date with
## a clock that went on while they were frozen. A frozen person is not hidden:
## they stand as they were.
func refresh() -> void:
	if visible == indoors:
		visible = not indoors
	_model_root.process_mode = Node.PROCESS_MODE_INHERIT if (not indoors and _full) else Node.PROCESS_MODE_DISABLED
	if can_process() and absf(_now() - _last_minute) > SNAP_GAP:
		_catch_up()

## The clock has gone on a long way (a sleeping cell, a load, a night's
## sleep). If neither where they are nor where they should be can be seen,
## they are put there; otherwise they carry on from where they stand and
## walk (or go in, or wait to come out) like anybody else.
func _catch_up() -> void:
	_last_minute = _now()
	var e := Schedules.entry_at(person, _minute())
	if e.is_empty():
		return
	var there := Schedules.position_for(person, e["place"])
	var out_there: bool = e["activity"] != "sleep"
	if there == Vector3.INF:
		return
	if (not indoors and Schedules.is_seen(global_position)) or (out_there and Schedules.is_seen(there)):
		return
	resync()

## A sitter's body is raised to a taller seat than the clip's (Schedules `lift`).
func _seat(instant := false) -> void:
	_lift_target = float(Schedules.info(person).get("lift", 0.0)) if goal.get("activity", "") == "sit" else 0.0
	if instant:
		_model_root.position.y = _lift_target

func _face_goal() -> void:
	var partner := Schedules.partner_of(person)
	var partner_node: Node3D = null
	if partner != "" and get_parent() != null:
		partner_node = get_parent().get_node_or_null(partner) as Node3D
	var yaw := _facing
	if partner_node != null and partner_node.global_position != global_position:
		var d := partner_node.global_position - global_position
		yaw = atan2(d.x, d.z)
	elif goal.get("activity", "") in ["sit", "idle", "smoke", "work"]:
		yaw = _phase
		# Sitters and stoop-leaners face the street (south on Main and the
		# bench, the stoops' road is south too); the bus stop's open side is
		# the road, to the north of it.
		var place: String = goal.get("place", "")
		if place in ["ParkBench", "Stoop1", "Stoop2", "Stoop3"]:
			yaw = 0.0
		elif place == "BusStop":
			yaw = PI
	_facing = yaw
	_model_root.rotation.y = yaw

func _physics_process(delta: float) -> void:
	var now := _now()
	if absf(now - _last_minute) > SNAP_GAP:
		_catch_up()
	_last_minute = now
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var dist := 1.0e9
	if player != null:
		dist = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	var full := dist <= FULL_RANGE and not indoors
	if full != _full:
		_full = full
		_model_root.process_mode = Node.PROCESS_MODE_INHERIT if (full and visible) else Node.PROCESS_MODE_DISABLED
	if absf(_model_root.position.y - _lift_target) > 0.0005:
		_model_root.position.y = move_toward(_model_root.position.y, _lift_target, LIFT_SPEED * delta)
	if not full:
		_far_ticks += 1
		_far_dt += delta
		if _far_ticks % (FAR_EVERY_VIEWED if _viewed else FAR_EVERY) != 0:
			return
		delta = _far_dt
		_far_dt = 0.0
	_plan_t -= delta
	if _plan_t <= 0.0:
		_plan_t = PLAN_PERIOD
		_plan(dist, full)
	if indoors:
		return
	_move(delta, full, player, dist)
	if _viewed and not full:
		anim.advance(delta)

## Looks at the clock: has the next entry come up? Goes in, if they are due to
## and nobody would see it.
func _plan(dist: float, full: bool) -> void:
	var e := Schedules.entry_at(person, _minute())
	if e.is_empty():
		return
	if goal.is_empty() or e["from"] != goal["from"] or e["place"] != goal["place"] or e["activity"] != goal["activity"]:
		_begin(e)
	var close := dist <= AVOID_RANGE
	if nav_agent.avoidance_enabled != close:
		nav_agent.avoidance_enabled = close
	_viewed = not full and not indoors and visible and Schedules.in_view(global_position)
	# Going in: at a door once they have walked to it, anywhere else only
	# where nobody can see it.
	if not _walking and not indoors and goal.get("activity", "") == "sleep":
		var place := String(goal.get("place", ""))
		if place in DOORS or not Schedules.is_seen(global_position):
			_set_indoors(true)

func _begin(e: Dictionary) -> void:
	var came_from: String = goal.get("place", "")
	_apply_goal(e)
	_wander_to = Vector3.INF
	if goal_pos == Vector3.INF:
		return
	if indoors:
		if e["activity"] == "sleep":
			# Still not out: only the door they will come out of has changed.
			return
		# Out of the door they went in at -- when nobody is looking. The next
		# place is a walk from there.
		var door := _door_of(came_from)
		if door == Vector3.INF or Schedules.is_seen(door):
			goal = {"from": -1, "place": came_from, "activity": "sleep"}
			return
		global_position = door
		reset_physics_interpolation()
		_set_indoors(false)
		_seat(true)
	_walking = global_position.distance_to(goal_pos) > ARRIVE
	if _walking:
		nav_agent.target_position = goal_pos
	else:
		_face_goal()

## Where they step out of: the stoop's door; anywhere else the spot itself.
func _door_of(place: String) -> Vector3:
	return Schedules.place_position(place) if place in DOORS else Schedules.position_for(person, place)

func _move(delta: float, full: bool, player: Node3D, dist: float) -> void:
	if _walking:
		_walk(delta, full)
		return
	# At the place: do the activity.
	var activity: String = goal.get("activity", "idle")
	if activity == "walk_loop" and goal_pos != Vector3.INF:
		_wander_t -= delta
		if _wander_to == Vector3.INF and _wander_t <= 0.0:
			var a := randf() * TAU
			_wander_to = goal_pos + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.4, WANDER_RADIUS)
			nav_agent.target_position = _wander_to
		if _wander_to != Vector3.INF:
			if global_position.distance_to(_wander_to) < ARRIVE or nav_agent.is_navigation_finished():
				_wander_to = Vector3.INF
				_wander_t = randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
			else:
				_step_along(delta, _speed * 0.8, full)
				return
	if full or _viewed:
		anim.update(0.0)
	if full:
		# Somebody coming up to you: a look, not a conversation.
		if player != null and dist < 3.0 and activity != "sit":
			var d := player.global_position - global_position
			_facing = lerp_angle(_facing, atan2(d.x, d.z), TURN_SPEED * delta)
			_model_root.rotation.y = _facing

func _walk(delta: float, full: bool) -> void:
	var to := goal_pos - global_position
	to.y = 0.0
	if to.length() <= ARRIVE:
		_arrive(full)
		return
	# The path ends at the nearest walkable spot, which can be a step short
	# of a seat or a counter: the last stretch is straight (a stride or two).
	if nav_agent.is_navigation_finished():
		if to.length() > 2.5:
			_arrive(full)
			return
		var step := minf(to.length(), _speed * delta)
		global_position += to.normalized() * step
		global_position.y = 0.0
		if full or _viewed:
			anim.update(_speed)
			_facing = lerp_angle(_facing, atan2(to.x, to.z), TURN_SPEED * delta)
			_model_root.rotation.y = _facing
		return
	_step_along(delta, _speed, full)

func _arrive(full: bool) -> void:
	_walking = false
	velocity = Vector3.ZERO
	_face_goal()
	_seat()
	if full or _viewed:
		anim.update(0.0)

## One step toward the next point of the agent's path.
func _step_along(delta: float, speed: float, full: bool) -> void:
	var next := nav_agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.05 else Vector3.ZERO
	var want := dir * speed
	if full:
		if nav_agent.avoidance_enabled:
			nav_agent.velocity = want
		else:
			_on_safe_velocity(want)
		var h := Vector2(velocity.x, velocity.z).length()
		anim.update(h)
		if h > 0.1:
			_facing = lerp_angle(_facing, atan2(velocity.x, velocity.z), TURN_SPEED * delta)
			_model_root.rotation.y = _facing
	else:
		# Far away: along the path by the time that has gone, no collision;
		# animated by hand when the camera can see them (see _physics_process).
		global_position += want * delta
		global_position.y = 0.0
		if dir != Vector3.ZERO:
			_facing = atan2(dir.x, dir.z)
			_model_root.rotation.y = _facing
		if _viewed:
			anim.update(speed)

func _on_safe_velocity(safe: Vector3) -> void:
	# The agent reports every tick while avoidance is on, even for someone
	# sitting still; moving them then would shove a sitter off his bench.
	if not _walking and _wander_to == Vector3.INF:
		velocity = Vector3.ZERO
		return
	velocity = safe
	move_and_slide()
	global_position.y = 0.0
