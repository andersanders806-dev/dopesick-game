extends Node3D
## The south side of Main Street. The block's own world stops at the road's south curb (z 4.6): turn round on the
## sidewalk and there is only fog and nothing. This row closes it: a sidewalk, a kerb, and a street of buildings
## facing north, made of the same kit fronts the north side is (Facades._build_front, turned round), with solid
## bodies behind them and gravel roofs, so the street is a street from either way you look. Lit, shuttered and
## dark shops and windows by the same rules as the north side.

const Facades := preload("res://world/Facades.gd")
const Mat := preload("res://world/ghetto/GhettoMat.gd")

const X_FROM := -77.0
const X_TO := 77.0
const WALK_Z := 4.6
const LINE_Z := 7.7                 # the building line (the sidewalk is 3.1 m deep, as the north one)
const DEPTH := 12.0
const FLAGS := ["aircon", "escape", "shop", "closed", "aircon,shop", "escape,closed", "aircon", "shop", "", "escape,shop"]

var set_node: Node
var facades: Node
var fronts: Array[Node3D] = []
var building_count := 0

func _ready() -> void:
	name = "SouthSide"
	var city := get_parent().get("city") as Node3D if get_parent() else null
	if city == null:
		return
	facades = city.get_node_or_null("Facades")
	_pavement(city)
	_row()

func _pavement(city: Node) -> void:
	var walk := city.find_child("Sidewalk", true, false) as MeshInstance3D
	var curb := city.find_child("Curb", true, false) as MeshInstance3D
	var mi := MeshInstance3D.new()
	mi.name = "SouthSidewalk"
	var bm := BoxMesh.new()
	bm.size = Vector3(X_TO - X_FROM, 0.1, LINE_Z - WALK_Z)
	mi.mesh = bm
	if walk and walk.get_active_material(0):
		mi.material_override = walk.get_active_material(0)
	else:
		mi.material_override = Mat.mat(Color(0.3, 0.3, 0.3), 0.9)
	add_child(mi)
	mi.position = Vector3(0.0, -0.04, (WALK_Z + LINE_Z) / 2.0)
	var kb := MeshInstance3D.new()
	kb.name = "SouthKerb"
	var km := BoxMesh.new()
	km.size = Vector3(X_TO - X_FROM, 0.14, 0.25)
	kb.mesh = km
	if curb and curb.get_active_material(0):
		kb.material_override = curb.get_active_material(0)
	else:
		kb.material_override = Mat.mat(Color(0.4, 0.4, 0.4), 0.9)
	add_child(kb)
	kb.position = Vector3(0.0, 0.03, WALK_Z - 0.12)
	# Something to stand on: the ground the road's floor does not reach.
	var body := StaticBody3D.new()
	body.name = "SouthGround"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(X_TO - X_FROM + 40.0, 1.0, LINE_Z - WALK_Z + 8.0)
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.position = Vector3(0.0, -0.5, (WALK_Z + LINE_Z) / 2.0 + 4.0 - 0.0)

func _row() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4412
	var x := X_FROM
	var i := 0
	while x < X_TO - 2.0:
		var w := minf(rng.randf_range(6.0, 11.0), X_TO - x)
		var floors := rng.randi_range(2, 5)
		var kit := "apt" if rng.randf() < 0.65 else "factory"
		var flags: String = FLAGS[rng.randi() % FLAGS.size()]
		_building("South%d" % i, x, x + w, kit, floors, flags)
		x += w
		i += 1

func _building(nm: String, x0: float, x1: float, kit: String, floors: int, flags: String) -> void:
	var h := floors * Facades.MODULE + Facades.ROOF_OVER
	# Its front: the kit's, built as if facing Main Street from the north, then turned round and set on the line.
	if facades:
		var f := [nm, -x1, -x0, kit, floors, "", "main", nm, flags]
		facades.call("_build_front", f)
		var front := facades.get_node_or_null("Front" + nm) as Node3D
		if front:
			front.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, LINE_Z + Facades.FACE_Z))
			front.set_meta("cell", "Cell_Main")
			fronts.append(front)
	# Its body: a brick box behind the front, a gravel roof on it.
	var body := Node3D.new()
	body.name = "Body" + nm
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, h, DEPTH)
	mi.mesh = bm
	mi.material_override = facades.call("_mass_mat", kit) if facades else Mat.mat(Color(0.4, 0.3, 0.26), 0.9)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	body.position = Vector3((x0 + x1) / 2.0, h / 2.0, LINE_Z + 0.45 + DEPTH / 2.0)
	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(x1 - x0 - 0.2, 0.08, DEPTH - 0.2)
	roof.mesh = rm
	var gravel = Facades._roof_mat
	roof.material_override = gravel if gravel is Material else Mat.mat(Color(0.3, 0.29, 0.28), 0.95)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(roof)
	roof.position = Vector3(0, h / 2.0 + 0.04, 0)
	# A parapet lip so the roofline reads.
	var lip := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(x1 - x0, 0.45, 0.3)
	lip.mesh = lm
	lip.material_override = mi.material_override
	body.add_child(lip)
	lip.position = Vector3(0, h / 2.0 + 0.22, -DEPTH / 2.0 + 0.15)
	var sb := StaticBody3D.new()
	sb.name = "Solid"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	sb.add_child(cs)
	body.add_child(sb)
	building_count += 1
