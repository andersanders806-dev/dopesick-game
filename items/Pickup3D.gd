extends Area3D
## Ammo and cash dropped by a downed officer. Walk over it to take it -- no
## key press, so you can grab it mid-firefight.

var ammo: int = 30
var cash: int = 0

var _mesh: Node3D
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	shape.shape = sphere
	shape.position = Vector3(0, 0.4, 0)
	add_child(shape)
	body_entered.connect(_on_body_entered)

	_mesh = Node3D.new()
	add_child(_mesh)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.26, 0.14, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.18)
	mat.roughness = 0.6
	bm.material = mat
	box.mesh = bm
	_mesh.add_child(box)
	# A faint glow so it can be found on a dark street.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.8, 0.4)
	glow.light_energy = 0.6
	glow.omni_range = 1.4
	glow.position = Vector3(0, 0.3, 0)
	add_child(glow)

func _process(delta: float) -> void:
	_t += delta
	_mesh.position.y = 0.25 + sin(_t * 3.0) * 0.05
	_mesh.rotation.y = _t * 1.5

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if ammo > 0:
		GameState.add_ammo(ammo)
	if cash > 0:
		GameState.add_cash(cash)
	SFX.play("pickup_ammo", -2.0)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		var bits := []
		if ammo > 0:
			bits.append("+%d rounds" % ammo)
		if cash > 0:
			bits.append("+$%d" % cash)
		hud.toast(", ".join(bits))
	queue_free()
