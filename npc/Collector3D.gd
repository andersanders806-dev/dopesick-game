extends CharacterBody3D
## The pusher's collector. Shows up on the street once a front is overdue
## and walks you down -- not a sprint like the police, a steady walk that a
## healthy person can stay ahead of and a sick one can't. He doesn't give up
## and he doesn't care about doors: step back out onto the block and he's
## still there. When he reaches you he takes what you've got
## (GameState.collect_debt()), and if that isn't enough, hurts you.

const SPEED := 3.3
const RETARGET_INTERVAL := 0.3
const TURN_SPEED := 8.0
const STEP_INTERVAL := 0.36

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")
const CharacterCast := preload("res://npc/CharacterCast.gd")

@onready var catch_zone: Area3D = $CatchZone
@onready var nav_agent: NavigationAgent3D = $NavAgent
@onready var model: Node3D = $Model
@onready var footsteps: AudioStreamPlayer3D = $Footsteps

var anim: CharacterAnimator
var _retarget_timer: float = 0.0
var _facing_angle: float = 0.0
var _step_timer: float = 0.0
var _done: bool = false

func _ready() -> void:
	add_to_group("collector")
	CharacterCast.dress(model, "collector")
	anim = CharacterAnimator.new(model)
	catch_zone.body_entered.connect(_on_catch_body_entered)

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or _done:
		return
	if not GameState.debt_overdue():
		# Paid up while he was on his way.
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
		velocity = to_next.normalized() * SPEED
	move_and_slide()
	var speed := Vector2(velocity.x, velocity.z).length()
	anim.update(speed)
	if speed > 0.1:
		_facing_angle = lerp_angle(_facing_angle, atan2(velocity.x, velocity.z), TURN_SPEED * delta)
		model.rotation.y = _facing_angle
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = STEP_INTERVAL
			footsteps.stream = SFX.footstep_stream()
			footsteps.pitch_scale = randf_range(0.8, 0.88)
			footsteps.volume_db = 2.0 + SFX.FOOTSTEP_GAIN_DB
			footsteps.play()

func _on_catch_body_entered(body: Node) -> void:
	if _done or not body.is_in_group("player") or GameState.in_custody or body.dialogue_active:
		return
	_done = true
	velocity = Vector3.ZERO
	var owed := GameState.debt
	var taken := GameState.collect_debt()
	var hud := get_tree().get_first_node_in_group("hud")
	body.dialogue_active = true
	var text: String
	if GameState.debt == 0:
		SFX.play("cash", -6.0, 0.75)
		text = "A heavy hand lands on your shoulder. \"He says you owe $%d.\" He goes through your pockets, counts it, and he's gone." % owed
	else:
		SFX.play("punch", -2.0)
		get_tree().create_timer(0.35).timeout.connect(func(): SFX.play("punch", -4.0, 0.9))
		var took := ("takes your $%d, " % taken) if taken > 0 else "finds your pockets empty, "
		text = "A heavy hand lands on your shoulder. He %sand then puts you on the pavement. \"$%d now. Tomorrow.\" Everything hurts." % [took, GameState.debt]
	if hud:
		hud.show_dialogue("Collector", text)
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_callback(queue_free)
