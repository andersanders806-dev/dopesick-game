extends LookAtModifier3D
## People notice you: within RANGE, a head turns to follow you (eased in
## and out, held inside a natural neck's range), and lets you go when you
## walk off. Rocketbox heads face +Y on "Bip01 Head" (measured).

const RANGE := 3.5
## Where a head is on the cast's 1.5-scaled bodies.
const EYE_HEIGHT := 2.4
const EASE := 2.5

var _target: Node3D

static func attach(model: Node) -> void:
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Bip01 Head") < 0:
		return
	var turn := LookAtModifier3D.new()
	turn.set_script(load("res://npc/HeadTurn.gd"))
	sk.add_child(turn)

func _ready() -> void:
	bone_name = "Bip01 Head"
	forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y
	use_angle_limitation = true
	symmetry_limitation = true
	primary_limit_angle = deg_to_rad(140.0)
	secondary_limit_angle = deg_to_rad(60.0)
	influence = 0.0
	_target = Node3D.new()
	_target.top_level = true
	add_child(_target)
	target_node = get_path_to(_target)

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var want := 0.0
	var sk := get_parent() as Node3D
	if player and sk and sk.is_visible_in_tree():
		_target.global_position = player.global_position + Vector3(0, EYE_HEIGHT, 0)
		if sk.global_position.distance_to(player.global_position) < RANGE:
			want = 1.0
	influence = move_toward(influence, want, EASE * delta)
