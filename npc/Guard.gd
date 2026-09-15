extends Node2D

signal spotted_theft

@export var vision_range: float = 220.0
@export var vision_angle_deg: float = 50.0
@export var sweep_arc_deg: float = 70.0
@export var sweep_speed: float = 0.6
@export var base_facing_deg: float = 90.0

const VISION_COLOR_CALM := Color(0.85, 0.8, 0.3, 0.15)
const VISION_COLOR_ALERT := Color(0.9, 0.2, 0.2, 0.28)

@onready var vision_cone: Polygon2D = $VisionCone

var _sweep_t: float = 0.0
var can_see_player: bool = false

func _physics_process(delta: float) -> void:
	_sweep_t += delta * sweep_speed
	var facing_deg := base_facing_deg + sin(_sweep_t) * (sweep_arc_deg * 0.5)
	var facing := Vector2.RIGHT.rotated(deg_to_rad(facing_deg))

	var player := get_tree().get_first_node_in_group("player")
	can_see_player = false

	if player and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - global_position
		var dist := to_player.length()
		if dist <= vision_range:
			var angle_diff := rad_to_deg(abs(facing.angle_to(to_player.normalized())))
			if angle_diff <= vision_angle_deg * 0.5:
				can_see_player = _has_line_of_sight(player)

	if can_see_player and player.is_stealing:
		spotted_theft.emit()

	_redraw_cone(facing_deg)

func _has_line_of_sight(player: Node) -> bool:
	var space_state := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 3)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

func _redraw_cone(facing_deg: float) -> void:
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	var steps := 10
	var half := vision_angle_deg * 0.5
	for i in range(steps + 1):
		var a := deg_to_rad(facing_deg - half + (vision_angle_deg * i / float(steps)))
		points.append(Vector2.RIGHT.rotated(a) * vision_range)
	vision_cone.polygon = points
	vision_cone.color = VISION_COLOR_ALERT if can_see_player else VISION_COLOR_CALM
