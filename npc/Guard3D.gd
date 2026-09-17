extends Node3D

signal spotted_theft

@export var vision_range: float = 6.0
@export var vision_angle_deg: float = 50.0
@export var sweep_arc_deg: float = 70.0
@export var sweep_speed: float = 0.6
@export var base_facing_deg: float = 0.0
## Who this is when you talk to them (pushed onto the TalkZone child, so each
## store's clerk or guard can have their own name and lines).
@export var talk_name: String = ""
@export_multiline var talk_lines: String = ""
@export var talk_portrait_path: String = ""

const VISION_COLOR_CALM := Color(0.5, 0.95, 1.0, 0.35)
const VISION_COLOR_ALERT := Color(1.0, 0.15, 0.15, 0.55)

@onready var vision_cone: MeshInstance3D = $VisionCone
@onready var body: Node3D = $Body

const CharacterAnimator := preload("res://npc/CharacterAnimator.gd")

var anim: CharacterAnimator
@onready var cone_material := StandardMaterial3D.new()

var _sweep_t: float = 0.0
var can_see_player: bool = false

func _ready() -> void:
	add_to_group("guards")
	anim = CharacterAnimator.new(body)
	var talk := get_node_or_null("TalkZone")
	if talk:
		if talk_name != "":
			talk.npc_name = talk_name
			talk.portrait_path = talk_portrait_path
		if talk_lines != "":
			talk.flavor_lines = talk_lines
	cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_material.albedo_color = VISION_COLOR_CALM
	vision_cone.material_override = cone_material

func _physics_process(delta: float) -> void:
	_sweep_t += delta * sweep_speed
	var facing_deg := base_facing_deg + sin(_sweep_t) * (sweep_arc_deg * 0.5)
	var facing := Vector2.RIGHT.rotated(deg_to_rad(facing_deg))

	var player := get_tree().get_first_node_in_group("player")
	can_see_player = false

	if player and is_instance_valid(player):
		var to_player_3d: Vector3 = player.global_position - global_position
		var to_player := Vector2(to_player_3d.x, to_player_3d.z)
		var dist := to_player.length()
		if dist <= vision_range:
			var angle_diff := rad_to_deg(abs(facing.angle_to(to_player.normalized())))
			if angle_diff <= vision_angle_deg * 0.5:
				can_see_player = _has_line_of_sight(player)

	if can_see_player and player.is_stealing and not GameState.in_custody:
		spotted_theft.emit()

	_redraw_cone(facing_deg)

func _has_line_of_sight(player: Node) -> bool:
	var space_state := get_world_3d().direct_space_state
	# Eye height sits above the shop counter so the counter itself doesn't
	# blind the shopkeeper; the tall shelves still break line of sight.
	var from: Vector3 = global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	var result := space_state.intersect_ray(params)
	if result.is_empty():
		return true
	return result.collider == player

func _redraw_cone(facing_deg: float) -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	uvs.append(Vector2(0.5, 0.5))
	var steps := 10
	var half := vision_angle_deg * 0.5
	for i in range(steps + 1):
		var a := deg_to_rad(facing_deg - half + (vision_angle_deg * i / float(steps)))
		var dir := Vector2.RIGHT.rotated(a) * vision_range
		verts.append(Vector3(dir.x, 0.03, dir.y))
		uvs.append(Vector2(0.5, 0.5))
	for i in range(1, steps + 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	vision_cone.mesh = mesh
	cone_material.albedo_color = VISION_COLOR_ALERT if can_see_player else VISION_COLOR_CALM
