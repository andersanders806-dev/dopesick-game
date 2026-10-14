extends StaticBody3D
## The mailbox by the apartment door on the block: where Silk Lane orders
## land (world/Darknet.gd), dropped off by the postman (npc/Postman3D.gd).
## The red flag is up when there's something in it.

const Darknet := preload("res://world/Darknet.gd")
const InteractableScript := preload("res://interactables/Interactable3D.gd")

var _flag: Node3D

func _ready() -> void:
	name = "Mailbox"
	var metal := _mat(Color(0.18, 0.24, 0.36), 0.45, 0.6)
	_box(Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0), _mat(Color(0.2, 0.2, 0.22), 0.6))
	_box(Vector3(0.36, 0.3, 0.5), Vector3(0, 1.15, 0), metal)
	var top := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.18
	cyl.height = 0.5
	top.mesh = cyl
	top.material_override = metal
	add_child(top)
	top.position = Vector3(0, 1.3, 0)
	top.rotation_degrees.x = 90.0
	var label := Label3D.new()
	label.text = "12B"
	label.font_size = 36
	label.pixel_size = 0.004
	label.modulate = Color(0.95, 0.92, 0.8)
	add_child(label)
	label.position = Vector3(0.185, 1.18, 0.0)
	label.rotation_degrees.y = 90.0
	# The flag on a pivot at its foot: down along the side, or straight up.
	_flag = Node3D.new()
	add_child(_flag)
	_flag.position = Vector3(0.2, 1.15, 0.1)
	var stick := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.03, 0.42, 0.04)
	stick.mesh = sm
	stick.material_override = _mat(Color(0.95, 0.1, 0.08), 0.5, 0.6)
	_flag.add_child(stick)
	stick.position = Vector3(0, 0.21, 0)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.03, 0.14, 0.18)
	plate.mesh = pm
	plate.material_override = stick.material_override
	_flag.add_child(plate)
	plate.position = Vector3(0, 0.38, 0.09)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 1.5, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)
	var zone := Area3D.new()
	zone.name = "MailboxZone"
	zone.set_meta("prompt", "Check the mailbox")
	zone.collision_layer = 4
	zone.collision_mask = 0
	zone.monitoring = false
	zone.set_script(InteractableScript)
	add_child(zone)
	zone.position = Vector3(0, 0, 0.7)
	var zshape := CollisionShape3D.new()
	var zbox := BoxShape3D.new()
	zbox.size = Vector3(1.0, 1.4, 0.9)
	zshape.shape = zbox
	zshape.position = Vector3(0, 0.7, 0)
	zone.add_child(zshape)
	zone.interacted.connect(_on_check)
	refresh()

## A package that's landed and the postman's been (or came while you
## weren't out here).
func has_mail() -> bool:
	var p: Dictionary = GameState.parcel
	return Darknet.arrived() and p.get("fate", "") == "ok" and p.get("posted", true)

func refresh() -> void:
	if _flag:
		_flag.rotation_degrees.x = 0.0 if has_mail() else 90.0

func _on_check(_zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if not has_mail():
		if hud:
			player.dialogue_active = true
			var waiting: bool = not GameState.parcel.is_empty() and not Darknet.arrived()
			hud.show_dialogue("", "Empty. Tracking says about %d hours yet." % maxi(1, roundi(Darknet.hours_left())) if waiting
				else ["A takeout menu and a final notice for someone who moved out.", "Nothing. Somebody's jimmied the lock again, but there's nothing to take."].pick_random())
		return
	Darknet._open_with_menus(null, player)
	refresh()

func _process(delta: float) -> void:
	# Cheap: a couple of reads; keeps the flag honest when the package is
	# opened, taken, or lands while you're standing here.
	var want := 0.0 if has_mail() else 90.0
	if _flag and not is_equal_approx(_flag.rotation_degrees.x, want):
		_flag.rotation_degrees.x = move_toward(_flag.rotation_degrees.x, want, 360.0 * delta)

func _mat(col: Color, rough: float, emit := 0.0, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	mi.position = pos
