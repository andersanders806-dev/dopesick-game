extends Node3D
## A street rat (Poly Haven CC0 model) running along the base of a wall:
## a quick dash, a stop to sniff around, a dash back. Pure set dressing, but
## a moving thing at the edge of the frame does a lot for a dead street.

@export var span: float = 3.0
const SPEED := 2.6
const PAUSE := Vector2(0.6, 3.5)

var _origin: Vector3
var _target_x: float
var _pause: float = 0.0

func _ready() -> void:
	_origin = position
	_pause = randf_range(PAUSE.x, PAUSE.y)
	_pick()

func _pick() -> void:
	_target_x = _origin.x + randf_range(-span, span)

func _physics_process(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	var dx := _target_x - position.x
	if absf(dx) < 0.05:
		_pause = randf_range(PAUSE.x, PAUSE.y)
		_pick()
		return
	position.x += signf(dx) * minf(absf(dx), SPEED * delta)
	rotation.y = PI * 0.5 * signf(dx)
