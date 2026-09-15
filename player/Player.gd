extends CharacterBody2D

const BASE_SPEED := 145.0
const SICK_SPEED_MULT := 0.55
const SICK_THRESHOLD := 20.0

@onready var interact_zone: Area2D = $InteractZone
@onready var sprite: ColorRect = $Sprite

var nearby: Array = []
var dialogue_active: bool = false
var is_stealing: bool = false

func _ready() -> void:
	add_to_group("player")
	interact_zone.area_entered.connect(_on_area_entered)
	interact_zone.area_exited.connect(_on_area_exited)

func _physics_process(_delta: float) -> void:
	if dialogue_active:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	dir = dir.normalized()

	var speed := BASE_SPEED
	if GameState.craving <= SICK_THRESHOLD:
		speed *= SICK_SPEED_MULT

	velocity = dir * speed
	move_and_slide()

	if dir.length() > 0.1:
		sprite.rotation = 0.0

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

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("interactable"):
		nearby.append(area)

func _on_area_exited(area: Area2D) -> void:
	nearby.erase(area)

func begin_theft_window(duration: float) -> void:
	is_stealing = true
	get_tree().create_timer(duration).timeout.connect(func(): is_stealing = false)
