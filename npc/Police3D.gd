extends CharacterBody3D

const SPEED := 4.6
const LOSE_SIGHT_TIME := 4.0
const RETARGET_INTERVAL := 0.25
const TURN_SPEED := 10.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

# The Kenney sprint clip is 0.5 s per cycle, two footfalls.
const STEP_INTERVAL := 0.25

const BEACON_FLIP_TIME := 0.3
const BEACON_RED := Color(1, 0.15, 0.1, 1)
const BEACON_BLUE := Color(0.15, 0.35, 1, 1)

@onready var catch_zone: Area3D = $CatchZone
@onready var nav_agent: NavigationAgent3D = $NavAgent
@onready var model: Node3D = $Model
@onready var beacon: OmniLight3D = $Beacon
@onready var footsteps: AudioStreamPlayer3D = $Footsteps

## Out of sight, an officer who actually saw you doesn't just stand there:
## he walks to where he last saw you and checks the hiding spots
## (group "hide_spots") right around it -- duck into one in front of him
## and he'll look there. One who never got eyes on you (called in by a
## clerk) gives up after LOSE_SIGHT_TIME as before.
const SEARCH_RADIUS := 4.5
const SEARCH_PAUSE := 1.3
const SEARCH_MAX_SPOTS := 2
const SEARCH_TIMEOUT := 16.0
const FOUND_RANGE := 1.4
## In a crowd and further than this, he loses you among the passersby.
const CROWD_SIGHT := 5.0

var _saw_player: bool = false
var _last_seen: Vector3
var _search: Array = []
var _search_pause: float = 0.0
var _search_time: float = 0.0
var _lose_timer: float = 0.0
var _retarget_timer: float = 0.0
var _facing_angle: float = 0.0
var _beacon_timer: float = 0.0
var _beacon_red: bool = true
var anim: CharacterAnimator
var _step_timer: float = 0.0
var _left_foot: bool = true

func _ready() -> void:
	add_to_group("police")
	CharacterCast.dress(model, "police")
	anim = CharacterAnimator.new(model, "sprint")
	GameState.set_wanted(true)
	catch_zone.body_entered.connect(_on_catch_body_entered)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		nav_agent.target_position = player.global_position

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return

	if _has_line_of_sight(player):
		_lose_timer = 0.0
		_search.clear()
		_search_time = 0.0
		_saw_player = true
		_last_seen = player.global_position
		_retarget_timer -= delta
		if _retarget_timer <= 0.0:
			_retarget_timer = RETARGET_INTERVAL
			nav_agent.target_position = player.global_position
	else:
		_lose_timer += delta
		if not _search_step(player, delta):
			return

	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
	else:
		var next_point: Vector3 = nav_agent.get_next_path_position()
		var to_next: Vector3 = next_point - global_position
		to_next.y = 0.0
		velocity = to_next.normalized() * SPEED
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	anim.update(speed)
	_update_footsteps(delta, speed > 0.1)

	if Vector2(velocity.x, velocity.z).length() > 0.1:
		var target_angle := atan2(velocity.x, velocity.z)
		_facing_angle = lerp_angle(_facing_angle, target_angle, TURN_SPEED * delta)
		model.rotation.y = _facing_angle

	_update_beacon(delta)

## Positional, so you can hear an officer coming round a shelf before you
## see them.
func _update_footsteps(delta: float, moving: bool) -> void:
	if not moving:
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer += STEP_INTERVAL
	_left_foot = not _left_foot
	footsteps.stream = SFX.footstep_stream()
	footsteps.pitch_scale = randf_range(0.85, 0.95)
	footsteps.volume_db = 2.0 + SFX.FOOTSTEP_GAIN_DB
	footsteps.play()

func _update_beacon(delta: float) -> void:
	_beacon_timer += delta
	if _beacon_timer >= BEACON_FLIP_TIME:
		_beacon_timer = 0.0
		_beacon_red = not _beacon_red
		beacon.light_color = BEACON_RED if _beacon_red else BEACON_BLUE

func _has_line_of_sight(player: Node) -> bool:
	if player.get("hiding"):
		return false
	# Walking (not running) among passersby, past arm's length, he loses you.
	if player.has_method("in_crowd") and player.in_crowd() and global_position.distance_to((player as Node3D).global_position) > CROWD_SIGHT:
		return false
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 0.8, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

## One tick of looking for you. Returns false once he's given up (or found
## you), when the caller should stop.
func _search_step(player: Node, delta: float) -> bool:
	if not _saw_player:
		if _lose_timer >= LOSE_SIGHT_TIME:
			_give_up()
			return false
		return true
	_search_time += delta
	if _search_time > SEARCH_TIMEOUT:
		_give_up()
		return false
	if _search.is_empty() and _lose_timer < 0.1:
		# Just lost you: plan the search -- the spot he last saw you, then
		# the nearest hiding places to it.
		_search.append(_last_seen)
		var spots := get_tree().get_nodes_in_group("hide_spots").filter(func(n): return (n as Node3D).global_position.distance_to(_last_seen) <= SEARCH_RADIUS)
		spots.sort_custom(func(a, b): return a.global_position.distance_to(_last_seen) < b.global_position.distance_to(_last_seen))
		for spot in spots.slice(0, SEARCH_MAX_SPOTS):
			_search.append(spot)
		nav_agent.target_position = _last_seen
	if _search.is_empty():
		# Nothing left to check.
		if _lose_timer >= LOSE_SIGHT_TIME:
			_give_up()
			return false
		return true
	var target = _search[0]
	var at: Vector3 = target if target is Vector3 else (target as Node3D).global_position
	nav_agent.target_position = at
	var flat := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if flat > FOUND_RANGE and not nav_agent.is_navigation_finished():
		return true
	# He's there. Anyone crouched in this spot is found.
	if target is Node3D and player.get("hiding") and (player as Node3D).global_position.distance_to(at) <= 1.6:
		_bust(player)
		return false
	_search_pause += delta
	if _search_pause >= SEARCH_PAUSE:
		_search_pause = 0.0
		_search.pop_front()
		# Nothing left to check: the empty-search branch above gives up
		# once he's been without you for LOSE_SIGHT_TIME.
	return true

func _give_up() -> void:
	GameState.set_wanted(false)
	queue_free()

func _on_catch_body_entered(body: Node) -> void:
	if not body.is_in_group("player") or GameState.in_custody:
		return
	# Crouched out of sight behind the dumpster: he walks right past --
	# unless he's come to search that very spot (_search_step).
	if body.get("hiding"):
		return
	_bust(body)

func _bust(body: Node) -> void:
	if body.get("hiding") and body.has_method("set_hiding"):
		body.set_hiding(false)
		var hud0 := get_tree().get_first_node_in_group("hud")
		if hud0:
			hud0.show_dialogue("Officer", "A flashlight in your face. \"Saw you duck in there. Up. Hands where I can see them.\"")
	GameState.get_busted()
	body.dialogue_active = true  # hold still while being cuffed
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash_busted()
	set_physics_process(false)
	GameState.pending_spawn = "SpawnCell"
	# Hold the tree ourselves: this officer is freed below, and a timer
	# callback that calls *its* get_tree() would never fire.
	var tree := get_tree()
	# A bust that ends the run gets the "sent away" scene from the run-end
	# screen instead; an ordinary one plays the arrest before the cell.
	var run_over := GameState.strikes >= GameState.max_strikes()
	tree.create_timer(0.9).timeout.connect(
		func():
			if not run_over:
				await Cutscene.play("busted")
			SceneLoader.go("res://world/Jail3D.tscn")
	)
	queue_free()
