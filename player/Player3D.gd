extends CharacterBody3D

const BASE_SPEED := 4.2
const SICK_SPEED_MULT := 0.55
const SICK_THRESHOLD := 20.0
const TURN_SPEED := 10.0

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")

@onready var interact_zone: Area3D = $InteractZone
@onready var model: Node3D = $Model

var nearby: Array = []
var dialogue_active: bool = false
var is_stealing: bool = false
var _facing_angle: float = 0.0
var anim: CharacterAnimator

func _ready() -> void:
	add_to_group("player")
	anim = CharacterAnimator.new(model)
	interact_zone.area_entered.connect(_on_area_entered)
	interact_zone.area_exited.connect(_on_area_exited)

func _physics_process(delta: float) -> void:
	if dialogue_active:
		velocity = Vector3.ZERO
		move_and_slide()
		anim.update(0.0)
		return

	var dir := Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	dir = dir.normalized()

	var speed := BASE_SPEED
	var sick := GameState.craving <= SICK_THRESHOLD
	if sick:
		speed *= SICK_SPEED_MULT

	velocity = dir * speed
	move_and_slide()
	# Withdrawal slows the stride along with the movement, so it reads as a
	# shuffle rather than the feet sliding.
	anim.update(Vector2(velocity.x, velocity.z).length(), SICK_SPEED_MULT if sick else 1.0)

	if dir.length() > 0.1:
		var target_angle := atan2(dir.x, dir.z)
		_facing_angle = lerp_angle(_facing_angle, target_angle, TURN_SPEED * delta)
		model.rotation.y = _facing_angle

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()

func _try_interact() -> void:
	if dialogue_active:
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.advance_or_close_dialogue()
		return
	if nearby.is_empty():
		return
	var target = nearby[0]
	if is_instance_valid(target) and target.has_method("interact"):
		target.interact(self)

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("interactable"):
		nearby.append(area)

func _on_area_exited(area: Area3D) -> void:
	nearby.erase(area)

func begin_theft_window(duration: float) -> void:
	is_stealing = true
	get_tree().create_timer(duration).timeout.connect(func(): is_stealing = false)
