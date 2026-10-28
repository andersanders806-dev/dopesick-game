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
##     by the time that has gone by; no animation (the model isn't
##     processed).
##   in a sleeping cell: BlockCells freezes them (group cell_sleepers) and
##     City3D hides them. They are not simulated: when the cell wakes
##     resync() puts them where position_at() says they should be.

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const HeadTurn := preload("res://npc/HeadTurn.gd")

const WALK_SPEED := 1.2
const FULL_RANGE := 40.0
const AVOID_RANGE := 10.0
const FAR_EVERY := 15
## How often the schedule is looked at (seconds).
const PLAN_PERIOD := 0.5
## A clock that has gone this far (game minutes) since the last tick -- a
## sleeping cell, a load, a night's sleep -- isn't walked through: the
## person is put where the entry in force says.
const SNAP_GAP := 20.0
const ARRIVE := 0.35
const TURN_SPEED := 6.0
## They don't pop out of, or into, thin air in front of you: where there's
## no door (the court, the camp) a person only goes in or comes out
## unseen -- farther than this from the player.
const SEEN_RANGE := 22.0
const WANDER_RADIUS := 1.1
const WANDER_PAUSE := Vector2(2.5, 6.0)
## Places with a door, a bus or a building to step into.
const DOORS := ["Stoop1", "Stoop2", "Stoop3", "BusStop", "PoliceStation", "PusherCorner", "RayCrate"]

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
## made, after a long time away, and when their cell wakes.
func resync() -> void:
	_last_minute = _now()
	var e := Schedules.entry_at(person, _minute())
	_apply_goal(e)
	if goal_pos != Vector3.INF:
		global_position = goal_pos
		reset_physics_interpolation()
	_walking = false
	_wander_to = Vector3.INF
	_set_indoors(goal.get("activity", "") == "sleep")
	_face_goal()
	_seat()

func _apply_goal(e: Dictionary) -> void:
	goal = e
	if e.is_empty():
		goal_pos = Vector3.INF
		return
	goal_pos = Schedules.position_for(person, e["place"])
	_rest_clip = "sit" if e["activity"] == "sit" else "idle"
	_model_root.position.y = 0.0
	anim.set_rest_clip(_rest_clip)

func _set_indoors(on: bool) -> void:
	indoors = on
	refresh()

## City3D calls this when a cell wakes or sleeps: hidden if indoors or
## frozen, and put right if they have just been woken.
func refresh() -> void:
	var live := can_process()
	var show := live and not indoors
	if visible != show:
		visible = show
	_model_root.process_mode = Node.PROCESS_MODE_INHERIT if (show and _full) else Node.PROCESS_MODE_DISABLED
	if live and absf(_now() - _last_minute) > SNAP_GAP:
		resync()

## A sitter's body is raised to a taller seat than the clip's (Schedules `lift`).
func _seat() -> void:
	_model_root.position.y = float(Schedules.info(person).get("lift", 0.0)) if goal.get("activity", "") == "sit" else 0.0

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
		# Sitters and stoop-leaners face the street; the rest anywhere.
		if goal.get("place", "") in ["ParkBench", "Stoop1", "Stoop2", "Stoop3", "BusStop"]:
			yaw = 0.0
	_facing = yaw
	_model_root.rotation.y = yaw

func _physics_process(delta: float) -> void:
	var now := _now()
	if absf(now - _last_minute) > SNAP_GAP:
		resync()
	_last_minute = now
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var dist := 1.0e9
	if player != null:
		dist = Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length()
	var full := dist <= FULL_RANGE and not indoors
	if full != _full:
		_full = full
		_model_root.process_mode = Node.PROCESS_MODE_INHERIT if (full and visible) else Node.PROCESS_MODE_DISABLED
	if not full:
		_far_ticks += 1
		_far_dt += delta
		if _far_ticks % FAR_EVERY != 0:
			return
		delta = _far_dt
		_far_dt = 0.0
	_plan_t -= delta
	if _plan_t <= 0.0:
		_plan_t = PLAN_PERIOD
		_plan(player, dist)
	if indoors:
		return
	_move(delta, full, player, dist)

## Looks at the clock: has the next entry come up?
func _plan(_player: Node3D, dist: float) -> void:
	var e := Schedules.entry_at(person, _minute())
	if e.is_empty():
		return
	if goal.is_empty() or e["from"] != goal["from"] or e["place"] != goal["place"] or e["activity"] != goal["activity"]:
		_begin(e, dist)
	var close := dist <= AVOID_RANGE
	if nav_agent.avoidance_enabled != close:
		nav_agent.avoidance_enabled = close
	# Going in: where nobody can see it.
	if not _walking and not indoors and goal.get("activity", "") == "sleep" and _can_vanish(String(goal.get("place", "")), dist):
		_set_indoors(true)

func _begin(e: Dictionary, dist: float) -> void:
	var came_from: String = goal.get("place", "")
	_apply_goal(e)
	_wander_to = Vector3.INF
	if goal_pos == Vector3.INF:
		return
	if indoors:
		if e["activity"] == "sleep":
			# Still not out: only the door they will come out of has changed.
			return
		# Out of the door they went in at; the next place is a walk from there.
		if not _can_vanish(came_from, dist):
			# Seen: stay in until nobody is looking.
			goal = {"from": -1, "place": came_from, "activity": "sleep"}
			return
		var door := Schedules.position_for(person, came_from)
		if door != Vector3.INF:
			global_position = door
			reset_physics_interpolation()
		_set_indoors(false)
	_walking = global_position.distance_to(goal_pos) > ARRIVE
	if _walking:
		nav_agent.target_position = goal_pos

## Whether they can step in or out of `place` right now without being
## watched do it.
func _can_vanish(place: String, dist: float) -> bool:
	return place in DOORS or dist > SEEN_RANGE

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
	if full:
		anim.update(0.0)
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
		if full:
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
	if full:
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
		# Far away: along the path by the time that has gone, no collision,
		# no animation.
		global_position += want * delta
		global_position.y = 0.0

func _on_safe_velocity(safe: Vector3) -> void:
	# The agent reports every tick while avoidance is on, even for someone
	# sitting still; moving them then would shove a sitter off his bench.
	if not _walking and _wander_to == Vector3.INF:
		velocity = Vector3.ZERO
		return
	velocity = safe
	move_and_slide()
	global_position.y = 0.0
