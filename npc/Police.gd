extends CharacterBody2D

const SPEED := 165.0
const LOSE_SIGHT_TIME := 4.0
const RETARGET_INTERVAL := 0.25

@onready var catch_zone: Area2D = $CatchZone
@onready var nav_agent: NavigationAgent2D = $NavAgent

var _lose_timer: float = 0.0
var _retarget_timer: float = 0.0

func _ready() -> void:
	add_to_group("police")
	GameState.set_wanted(true)
	catch_zone.body_entered.connect(_on_catch_body_entered)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		nav_agent.target_position = player.global_position

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return

	# Only re-aim while we can actually see the player, so losing sight
	# means committing to their last known position instead of tracking
	# them straight through walls.
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
		velocity = Vector2.ZERO
	else:
		var next_point: Vector2 = nav_agent.get_next_path_position()
		velocity = (next_point - global_position).normalized() * SPEED
	move_and_slide()

func _has_line_of_sight(player: Node) -> bool:
	var space_state := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 3)
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
		func(): get_tree().change_scene_to_file("res://world/Apartment.tscn")
	)
	queue_free()
