extends CharacterBody3D

const SPEED := 4.6
const LOSE_SIGHT_TIME := 4.0
const RETARGET_INTERVAL := 0.25
const TURN_SPEED := 10.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")

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
		_retarget_timer -= delta
		if _retarget_timer <= 0.0:
			_retarget_timer = RETARGET_INTERVAL
			nav_agent.target_position = player.global_position
	else:
		_lose_timer += delta
		if _lose_timer >= LOSE_SIGHT_TIME:
			_give_up()
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
	footsteps.stream = SFX.SOUNDS["footstep_a" if _left_foot else "footstep_b"]
	footsteps.pitch_scale = randf_range(0.85, 0.95)
	footsteps.play()

func _update_beacon(delta: float) -> void:
	_beacon_timer += delta
	if _beacon_timer >= BEACON_FLIP_TIME:
		_beacon_timer = 0.0
		_beacon_red = not _beacon_red
		beacon.light_color = BEACON_RED if _beacon_red else BEACON_BLUE

func _has_line_of_sight(player: Node) -> bool:
	var space_state := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 0.8, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.8, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

func _give_up() -> void:
	GameState.set_wanted(false)
	queue_free()

func _on_catch_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	GameState.get_busted()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash_busted()
	set_physics_process(false)
	GameState.pending_spawn = "SpawnDefault"
	get_tree().create_timer(0.9).timeout.connect(
		func(): get_tree().change_scene_to_file("res://world/Apartment3D.tscn")
	)
	queue_free()
