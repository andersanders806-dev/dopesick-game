extends "res://npc/Guard3D.gd"
## A beat cop walking the block. Same eyes as the shop staff (a vision cone
## that goes amber, then red), but out on the street he cares about
## different things: someone carrying goods, someone running with them,
## and above all a hand-to-hand at the pusher's corner. When his suspicion
## fills he calls it in and gives chase himself (City3D swaps him for a
## Police3D). The pusher watches for him too and melts away when he's near.
##
## Created in code by City3D.gd on a Guard3D.tscn instance.

const WALK_SPEED := 1.25
## He strolls from the station end to the far end of the block and back,
## stopping now and then to look around.
const ROUTE_X := Vector2(-26.0, 26.0)
const ROUTE_Z := -1.3
const PAUSE_CHANCE := 0.25
const PAUSE_TIME := Vector2(2.0, 4.5)

const RATE_CARRYING := 0.22
const RATE_RUNNING_WITH_GOODS := 1.1
## Watching you buy from the pusher is the one thing he's out here for.
const RATE_HAND_TO_HAND := 2.6
const HAND_TO_HAND_RANGE := 3.0

var heading: float = 1.0
var _pause_timer: float = 0.0
var _next_pause_x: float = 0.0

func _ready() -> void:
	super._ready()
	add_to_group("patrol")
	_pick_next_pause()

func _physics_process(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		anim.update(0.0)
	else:
		position.x += heading * WALK_SPEED * delta
		position.z = move_toward(position.z, ROUTE_Z, delta)
		anim.update(WALK_SPEED)
		if (heading > 0.0 and position.x >= ROUTE_X.y) or (heading < 0.0 and position.x <= ROUTE_X.x):
			heading = -heading
			_pause_timer = randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
			_pick_next_pause()
		elif (position.x - _next_pause_x) * heading >= 0.0:
			_pause_timer = randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
			_pick_next_pause()
	base_facing_deg = 0.0 if heading > 0.0 else 180.0
	super._physics_process(delta)

func _pick_next_pause() -> void:
	var ahead := randf_range(6.0, 16.0) if randf() < PAUSE_CHANCE else 999.0
	_next_pause_x = position.x + heading * ahead

func _update_suspicion(player: Node, delta: float) -> void:
	if GameState.in_custody or _alarm_raised or GameState.wanted:
		return
	var rate := 0.0
	if can_see_player and player != null and is_instance_valid(player):
		var carrying := not GameState.inventory.is_empty()
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
