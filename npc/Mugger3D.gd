extends "res://npc/Collector3D.gd"
## Somebody who saw you alone on the block after dark (world/City3D.gd sends
## them, 21:00-04:00). Walks you down a little faster than the collector --
## a healthy sprint loses them, a sick shuffle doesn't -- and when they
## reach you it's your call: fight, hand it over, or run (ui/FightGame.gd).
## They give up after GIVE_UP seconds.

const MUGGER_SPEED := 3.9
const GIVE_UP := 40.0
const FightGame := preload("res://ui/FightGame.gd")

## Some of them have a knife: harder to put down, and a cut bleeds.
var knife := false
var _age := 0.0

func _ready() -> void:
	add_to_group("mugger")
	CharacterCast.dress(model, "mugger")
	anim = CharacterAnimator.new(model)
	catch_zone.body_entered.connect(_on_catch_body_entered)

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or _done:
		return
	_age += delta
	if _age > GIVE_UP or GameState.wanted or GameState.in_custody:
		queue_free()
		return
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		nav_agent.target_position = player.global_position
	if nav_agent.is_navigation_finished() or player.dialogue_active:
		velocity = Vector3.ZERO
	else:
		var to_next: Vector3 = nav_agent.get_next_path_position() - global_position
		to_next.y = 0.0
		velocity = to_next.normalized() * MUGGER_SPEED
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	anim.update(speed)
	if speed > 0.1:
		_facing_angle = lerp_angle(_facing_angle, atan2(velocity.x, velocity.z), TURN_SPEED * delta)
		model.rotation.y = _facing_angle

func _on_catch_body_entered(body: Node) -> void:
	if _done or not body.is_in_group("player") or GameState.in_custody or body.dialogue_active:
		return
	_done = true
	velocity = Vector3.ZERO
	confront(body)

## Opens the standoff; frees the mugger once it's over.
func confront(player: Node) -> CanvasLayer:
	player.dialogue_active = true
	var game: CanvasLayer = FightGame.new()
	get_tree().root.add_child(game)
	game.start(knife)
	game.tree_exited.connect(func():
		if is_instance_valid(player):
			player.dialogue_active = false
		if is_instance_valid(self):
			queue_free())
	return game
