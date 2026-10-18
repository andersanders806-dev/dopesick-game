extends RefCounted
## Shared pieces for the block's area builders (main_street_ext.gd,
## avenues.gd, back_street.gd, inner.gd), called from build_rooms_3d.gd's
## _build_city(). `b` is the builder: its _solid, _ph, _model, _light,
## _box_mesh, _marker helpers do the node work and set owners so the nodes
## save into City3D.tscn.
##
## The block (1 unit = 1 m, x east, z south, camera looking north):
##   Main Street   z -4.5..4.6 (sidewalk -4.5..-1.5, road -1.5..4.5), x -77..77
##   West Ave      road x -74..-68, sidewalks -77..-74 and -68..-65
##   East Ave      road x 68..74, sidewalks 65..68 and 74..77
##   Back Street   road z -94..-88, sidewalks -99..-94 and -88..-85
##   the interior  x -65..65, z -85..-16 behind Main's buildings:
##                 park (west), back alley + service lane (middle), lot and
##                 the underpass under the overpass (east)
## The buildings themselves (fronts and masses) are world/Facades.gd's.

const Facades := preload("res://world/Facades.gd")

const CELLS := {
	# name: bounds. They overlap at the corners; world/BlockCells.gd (task 2)
	# wakes a cell when you're within its margin of these.
	"Cell_Main": AABB(Vector3(-90, -1, -16), Vector3(180, 25, 22)),
	"Cell_West": AABB(Vector3(-90, -1, -94), Vector3(26, 25, 98.6)),
	"Cell_East": AABB(Vector3(64, -1, -94), Vector3(26, 25, 98.6)),
	"Cell_Back": AABB(Vector3(-90, -1, -110), Vector3(180, 25, 25)),
	"Cell_Inner": AABB(Vector3(-65, -1, -85), Vector3(130, 25, 69)),
}
const CHAINLINK := "res://assets/polyhaven/modular_chainlink_fence/modular_chainlink_fence.gltf"
const MultiMeshFill := preload("res://world/MultiMeshFill.gd")
## Fences you can see through still stop you, and the bake.
const FENCE_H := 2.4

static var _mats := {}
static var _meshes := {}

# --- Cells and places ------------------------------------------------------------

static func make_cells(b: Node) -> void:
	for n in CELLS:
		var c := Node3D.new()
		c.name = n
		c.set_meta("bounds", CELLS[n])
		b._add(b._root, c)

static func cell(b: Node, n: String) -> Node3D:
	return b._root.get_node(n) as Node3D

## A named spot people will keep (Task 4's schedules), in group "places".
static func place(b: Node, n: String, pos: Vector3) -> Marker3D:
	var m: Marker3D = b._marker(n, pos)
	m.add_to_group("places", true)
	return m

## Never hidden when its cell sleeps: you navigate by it from anywhere.
static func landmark(node: Node) -> void:
	node.add_to_group("landmark", true)

# --- Materials -------------------------------------------------------------------

## Shared by every area, so the whole block's sidewalk is one material (and
## goes wet in the rain as one).
static func mat(b: Node, key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match key:
		"sidewalk":
			m = b._tex_mat("pbr:sidewalk_slabs", 1.0)
			m.albedo_color = Color(0.58, 0.56, 0.53)
		"road":
			m = b._tex_mat("pbr:road_worn", 1.0)
		"curb":
			m = b._tex_mat("pbr:curb", 1.0)
		"asphalt":
			m = b._tex_mat("pbr:asphalt", 1.0)
			m.albedo_color = Color(0.62, 0.6, 0.58)
		"park":
			m = b._tex_mat("pbr:dirt", 1.0)
			m.albedo_color = Color(0.58, 0.52, 0.4)
		"gravel":
			m = b._tex_mat("pbr:gravel", 1.0)
			m.albedo_color = Color(0.6, 0.57, 0.52)
		"court":
			m = b._tex_mat("pbr:asphalt", 1.0)
			m.albedo_color = Color(0.5, 0.52, 0.55)
		"concrete":
			m = b._tex_mat("pbr:concrete_wall", 1.0)
			m.albedo_color = Color(0.62, 0.61, 0.58)
		"concrete_dark":
			m = b._tex_mat("pbr:concrete_wall", 1.0)
			m.albedo_color = Color(0.38, 0.37, 0.36)
		"brownstone":
			m = b._tex_mat("pbr:concrete_wall", 1.0)
			m.albedo_color = Color(0.48, 0.34, 0.27)
		"corrugated":
			m = b._tex_mat("pbr:corrugated", 1.0)
		"metal":
			m = b._tex_mat("pbr:metal_worn", 1.0)
		"iron":
			m = b._color_mat(Color(0.06, 0.06, 0.07), 0.45)
			m.metallic = 0.7
		"steel":
			m = b._color_mat(Color(0.32, 0.33, 0.34), 0.5)
			m.metallic = 0.8
		"dumpster":
			m = b._tex_mat("pbr:metal_worn", 1.0)
			m.albedo_color = Color(0.25, 0.42, 0.28)
		"wood":
			m = b._tex_mat("pbr:planks", 1.0)
		"glass":
			m = b._color_mat(Color(0.55, 0.62, 0.66, 0.22), 0.08)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.4
		"door":
			m = b._tex_mat("res://assets/env/door.png", 1.0, 0.7)
		"line":
			m = b._color_mat(Color(0.62, 0.5, 0.14), 0.8)
		"tarp_blue", "tarp_green", "tarp_grey":
			m = b._tex_mat("pbr:tarp", 1.0)
			m.albedo_color = {"tarp_blue": Color(0.16, 0.3, 0.58), "tarp_green": Color(0.24, 0.32, 0.2), "tarp_grey": Color(0.4, 0.4, 0.38)}[key]
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"bark":
			m = StandardMaterial3D.new()
			m.albedo_texture = load("res://assets/pbr/bark_diff.jpg")
			m.normal_enabled = true
			m.normal_texture = load("res://assets/pbr/bark_nor.jpg")
			m.roughness_texture = load("res://assets/pbr/bark_rough.jpg")
			m.albedo_color = Color(0.42, 0.4, 0.36)
		_:
			push_error("kit.mat: no material " + key)
	_mats[key] = m
	return m

# --- Ground ----------------------------------------------------------------------

## A slab of ground with its top at `top` (visual only: the block's floor
## collider is one slab under everything).
static func ground(b: Node, parent: Node, n: String, x0: float, z0: float, x1: float, z1: float, key: String, top := 0.0) -> MeshInstance3D:
	return b._box_mesh(parent, n, Vector3(x1 - x0, 0.1, z1 - z0), Vector3((x0 + x1) / 2.0, top - 0.05, (z0 + z1) / 2.0), mat(b, key))

## A curb along x (from x0 to x1 at z) or along z (z0..z1 at x).
static func curb_x(b: Node, parent: Node, n: String, x0: float, x1: float, z: float) -> void:
	b._box_mesh(parent, n, Vector3(x1 - x0, 0.14, 0.25), Vector3((x0 + x1) / 2.0, 0.03, z), mat(b, "curb"))

static func curb_z(b: Node, parent: Node, n: String, z0: float, z1: float, x: float) -> void:
	b._box_mesh(parent, n, Vector3(0.25, 0.14, z1 - z0), Vector3(x, 0.03, (z0 + z1) / 2.0), mat(b, "curb"))

## Faded centre-line dashes down a road, every 3 m.
static func dashes(b: Node, parent: Node, n: String, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var count := int(d.length() / 3.0)
	var along_x := absf(d.x) > absf(d.z)
	for i in count:
		var p := from + d.normalized() * (1.5 + i * 3.0)
		b._box_mesh(parent, "%s%d" % [n, i], Vector3(1.4, 0.005, 0.1) if along_x else Vector3(0.1, 0.005, 1.4), Vector3(p.x, 0.002, p.z), mat(b, "line"))

# --- Buildings -------------------------------------------------------------------

## A collider for every building in Facades.masses(), in its cell: they're
## the walls of the block (and what the navmesh bakes round). Visuals are
## Facades.gd's, built at load.
static func building_colliders(b: Node) -> void:
	for m in Facades.masses():
		var r: Rect2 = m["rect"]
		var h: float = m["floors"] * Facades.MODULE + Facades.ROOF_OVER + Facades.COPING.y
		b._solid(cell(b, m["cell"]), "Building" + m["name"], Vector3(r.size.x, h, r.size.y),
			Vector3(r.get_center().x, h / 2.0, r.get_center().y), null)

# --- Navigation -------------------------------------------------------------------

## Bakes the block's navmesh into NavRegion here, ahead of time: at runtime
## it was 1-1.8 s behind every door into the City. The block's own static
## bodies on layer 1 or 16 -- not people's (the pusher's body is a static
## body, and carving his corner out kept you from walking up to him) --
## plus the vending machine and mailbox City3D adds at load.
static func bake_navigation(b: Node) -> void:
	var source := NavigationMeshSourceGeometryData3D.new()
	for body in b._root.find_children("*", "StaticBody3D", true, false):
		if (body.collision_layer & (1 | 16)) == 0 or body.owner != b._root:
			continue
		for cs in body.find_children("*", "CollisionShape3D", false, false):
			_add_shape(source, cs.shape, _rel(b._root, cs))
	var City = load("res://world/City3D.gd")
	_add_shape(source, _box(Vector3(0.9, 1.9, 0.75)), Transform3D(Basis(), City.VENDING_POS + Vector3(0, 0.95, 0)))
	_add_shape(source, _box(Vector3(0.4, 1.5, 0.5)), Transform3D(Basis(), City.MAILBOX_POS + Vector3(0, 0.75, 0)))
	var Room = load("res://world/WorldRoot3D.gd")
	var nav_mesh: NavigationMesh = Room.new_nav_mesh()
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	(b._root.get_node("NavRegion") as NavigationRegion3D).navigation_mesh = nav_mesh

static func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s

static func _add_shape(source: NavigationMeshSourceGeometryData3D, shape: Shape3D, xform: Transform3D) -> void:
	var mesh: PrimitiveMesh
	if shape is BoxShape3D:
		mesh = BoxMesh.new()
		(mesh as BoxMesh).size = (shape as BoxShape3D).size
	elif shape is CylinderShape3D:
		mesh = CylinderMesh.new()
		(mesh as CylinderMesh).top_radius = (shape as CylinderShape3D).radius
		(mesh as CylinderMesh).bottom_radius = (shape as CylinderShape3D).radius
		(mesh as CylinderMesh).height = (shape as CylinderShape3D).height
	elif shape is CapsuleShape3D:
		mesh = CapsuleMesh.new()
		(mesh as CapsuleMesh).radius = (shape as CapsuleShape3D).radius
		(mesh as CapsuleMesh).height = (shape as CapsuleShape3D).height
	elif shape is SphereShape3D:
		mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = (shape as SphereShape3D).radius
		(mesh as SphereMesh).height = (shape as SphereShape3D).radius * 2.0
	else:
		push_error("bake_navigation: no source for " + shape.get_class())
		return
	source.add_faces(mesh.get_faces(), xform)

# --- Chain-link -------------------------------------------------------------------

static func _kit_mesh(path: String, piece: String) -> Mesh:
	var key := path + ":" + piece
	if not _meshes.has(key):
		var scene: Node = load(path).instantiate()
		var mi := scene.find_child(piece, true, false) as MeshInstance3D
		_meshes[key] = mi.mesh
		scene.free()
	return _meshes[key]

## A run of Poly Haven chain-link from `a` to `b` (panels stretched to fit,
## a post at every joint) with one collider down its length. `height`
## scales it: the court's is 4 m.
static func fence(b: Node, parent: Node, n: String, a: Vector3, to: Vector3, height := FENCE_H) -> Node3D:
	var holder := Node3D.new()
	holder.name = n
	b._add(parent, holder)
	var d := to - a
	var length := d.length()
	holder.position = (a + to) / 2.0
	holder.rotation.y = atan2(-d.z, d.x)
	var panel := _kit_mesh(CHAINLINK, "modular_chainlink_fence_double")
	var post := _kit_mesh(CHAINLINK, "modular_chainlink_fence_post")
	var pb := panel.get_aabb()
	var count := maxi(1, roundi(length / pb.size.x))
	var sx := length / (count * pb.size.x)
	var sy := height / FENCE_H
	var panels: Array[Transform3D] = []
	for i in count:
		var cx := -length / 2.0 + (i + 0.5) * pb.size.x * sx
		var basis := Basis.from_scale(Vector3(sx, sy, 1.0))
		panels.append(Transform3D(basis, Vector3(cx, 0, 0) - basis * pb.get_center() + Vector3(0, pb.size.y * sy / 2.0, 0)))
	var posts: Array[Transform3D] = []
	var qb := post.get_aabb()
	for i in count + 1:
		var basis := Basis.from_scale(Vector3(1, sy, 1))
		posts.append(Transform3D(basis, Vector3(-length / 2.0 + i * pb.size.x * sx, 0, 0) - basis * qb.get_center() + Vector3(0, qb.size.y * sy / 2.0, 0)))
	for part in [["Panels", panel, panels], ["Posts", post, posts]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[1]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = part[0]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_script(MultiMeshFill)
		mmi.set("transforms", part[2])
		b._add(holder, mmi)
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_mask = 0
	b._add(holder, body)
	b._collision(body, b._box_shape(Vector3(length, height, 0.12)), Vector3(0, height / 2.0, 0))
	return holder

# --- Props -----------------------------------------------------------------------

## The meshes of the model at `path` (those whose names contain `only`),
## copied out as plain MeshInstance3Ds under a holder, so they can be picked
## from or repainted (`paint`) -- the builder's changes to nodes inside an
## instanced model aren't saved with the scene.
static func copy_model(b: Node, parent: Node, n: String, path: String, xform: Transform3D, paint: Material = null, only := "") -> Node3D:
	var holder := Node3D.new()
	holder.name = n
	b._add(parent, holder)
	holder.transform = xform
	var scene: Node3D = load(path).instantiate()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if only != "" and not String(mi.name).contains(only):
			continue
		var copy := MeshInstance3D.new()
		copy.name = mi.name
		copy.mesh = mi.mesh
		copy.material_override = paint
		b._add(holder, copy)
		copy.transform = _rel(scene, mi)
	scene.free()
	return holder

## `node`'s transform relative to the root of the (out of tree) scene.
static func _rel(root: Node3D, node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p != null and p != root:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t

## A dumpster: body, a lid left half open, and its collider.
static func dumpster(b: Node, parent: Node, n: String, pos: Vector3, yaw := 0.0) -> StaticBody3D:
	var body: StaticBody3D = b._solid(parent, n, Vector3(1.8, 1.2, 1.0), pos + Vector3(0, 0.6, 0), mat(b, "dumpster"))
	body.rotation_degrees.y = yaw
	var lid: MeshInstance3D = b._box_mesh(body, "Lid", Vector3(1.85, 0.05, 1.05), Vector3(0, 0.63, 0.1), mat(b, "iron"))
	lid.rotation_degrees.x = -12.0
	for wx in [-0.75, 0.75]:
		b._box_mesh(body, "Wheel", Vector3(0.12, 0.12, 0.12), Vector3(wx, -0.56, 0.35), mat(b, "iron"))
	return body

## Bags and a can or two heaped against a wall.
static func bags(b: Node, parent: Node, n: String, pos: Vector3, count: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		b._ph(parent, "%s%d" % [n, i], "trashbag", pos + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.3, 0.3)), rng.randf_range(0.8, 1.05), rng.randf_range(0, 360))

static func trash_can(b: Node, parent: Node, n: String, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = n
	b._add(parent, body)
	body.position = pos
	# The model is a showcase of two cans side by side: the rusted one (and
	# its lid, leaning on it), centred. Copied out as meshes -- changes to
	# nodes inside an instanced model don't save.
	copy_model(b, body, "Model", "res://assets/polyhaven/metal_trash_can/metal_trash_can.gltf",
		Transform3D(Basis(Vector3.UP, deg_to_rad(n.hash() % 360)), Vector3.ZERO) * Transform3D(Basis(), Vector3(0.5, 0, 0)), null, "rust")
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.9
	b._collision(body, cyl, Vector3(0, 0.45, 0))

static func hydrant(b: Node, parent: Node, n: String, pos: Vector3) -> void:
	var h := StaticBody3D.new()
	h.name = n
	b._add(parent, h)
	h.position = pos
	var red := b._color_mat(Color(0.75, 0.1, 0.08), 0.5) as Material
	b._cylinder(h, "Mesh", 0.16, 0.75, Vector3(0, 0.375, 0), red)
	b._cylinder(h, "Cap", 0.12, 0.14, Vector3(0, 0.82, 0), red)
	b._collision(h, b._box_shape(Vector3(0.4, 0.75, 0.4)), Vector3(0, 0.375, 0))

## A painted park bench (Poly Haven) with a collider; `yaw` 0 faces south.
static func bench(b: Node, parent: Node, n: String, pos: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = n
	b._add(parent, body)
	body.position = pos
	body.rotation_degrees.y = yaw
	b._ph(body, "Model", "painted_wooden_bench", Vector3.ZERO, 1.3)
	b._collision(body, b._box_shape(Vector3(1.5, 0.9, 0.6)), Vector3(0, 0.45, 0))

## Someone's whole life in a shopping cart.
static func cart(b: Node, parent: Node, n: String, pos: Vector3, yaw: float) -> void:
	var c := StaticBody3D.new()
	c.name = n
	b._add(parent, c)
	c.position = pos
	c.rotation_degrees.y = yaw
	b._box_mesh(c, "Basket", Vector3(0.9, 0.5, 0.55), Vector3(0, 0.65, 0), mat(b, "steel"))
	b._box_mesh(c, "Bags", Vector3(0.8, 0.4, 0.5), Vector3(0, 0.95, 0), b._color_mat(Color(0.08, 0.08, 0.09), 0.4))
	b._box_mesh(c, "Blanket", Vector3(0.45, 0.2, 0.52), Vector3(-0.2, 1.2, 0), b._color_mat(Color(0.3, 0.22, 0.32), 1.0))
	for wx in [-0.35, 0.35]:
		for wz in [-0.22, 0.22]:
			b._box_mesh(c, "Wheel", Vector3(0.1, 0.1, 0.04), Vector3(wx, 0.05, wz), mat(b, "iron"))
	b._collision(c, b._box_shape(Vector3(0.9, 1.3, 0.6)), Vector3(0, 0.65, 0))

## A shop sign over a door like Main Street's: lit letters and a glow that
## City3D switches with the streetlights (it ends in "SignGlow").
static func shop_sign(b: Node, parent: Node, n: String, text: String, pos: Vector3, color: Color, yaw := 0.0) -> void:
	var s := Label3D.new()
	s.name = n + "Sign"
	s.text = text
	s.font_size = 96 if text.length() <= 9 else 72
	s.pixel_size = 0.006
	s.modulate = color
	s.outline_modulate = Color(0, 0, 0, 0.8)
	b._add(parent, s)
	s.position = pos
	s.rotation_degrees.y = yaw
	var out := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, -0.3, 0.8)
	b._light(parent, n + "SignGlow", pos + out, color, 1.2, 4.0, false)

## A bare tree (the park's are dead or near it): trunk, limbs and twigs as
## tapered six-sided tubes in one mesh, a collider round the trunk.
static func tree(b: Node, parent: Node, n: String, pos: Vector3, variant: int) -> void:
	var body := StaticBody3D.new()
	body.name = n
	b._add(parent, body)
	body.position = pos
	body.rotation_degrees.y = variant * 47.0
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _tree_mesh(b, variant % 3)
	b._add(body, mi)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 3.0
	b._collision(body, cyl, Vector3(0, 1.5, 0))

static func _tree_mesh(b: Node, variant: int) -> ArrayMesh:
	var key := "tree%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + variant * 31
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_branch(st, rng, Vector3.ZERO, Vector3(rng.randf_range(-0.08, 0.08), 1, rng.randf_range(-0.08, 0.08)).normalized(), 3.2 + variant * 0.5, 0.2, 0)
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, mat(b, "bark"))
	_meshes[key] = mesh
	return mesh

static func _branch(st: SurfaceTool, rng: RandomNumberGenerator, from: Vector3, dir: Vector3, length: float, radius: float, depth: int) -> void:
	var to := from + dir * length
	var r_end := radius * (0.55 if depth < 3 else 0.25)
	_tube(st, from, to, radius, r_end)
	if depth >= 3:
		return
	var kids: int = 3 + rng.randi_range(0, 1)
	for k in kids:
		# Kids come off the top third, spreading out and up.
		var at := from.lerp(to, rng.randf_range(0.6, 1.0) if depth > 0 else rng.randf_range(0.75, 1.0))
		var spin := TAU * (float(k) / kids) + rng.randf_range(-0.5, 0.5)
		var tilt := rng.randf_range(0.45, 0.85)
		var side := Vector3(cos(spin), 0, sin(spin))
		var kid_dir := (dir * cos(tilt) + side * sin(tilt)).normalized()
		kid_dir.y = maxf(kid_dir.y, 0.2)
		_branch(st, rng, at, kid_dir.normalized(), length * rng.randf_range(0.5, 0.7), r_end * 0.85, depth + 1)

static func _tube(st: SurfaceTool, a: Vector3, to: Vector3, r0: float, r1: float) -> void:
	var axis := (to - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var v := axis.cross(u)
	var sides := 6
	var length := a.distance_to(to)
	for i in sides:
		var t0 := TAU * i / sides
		var t1 := TAU * (i + 1) / sides
		var n0 := u * cos(t0) + v * sin(t0)
		var n1 := u * cos(t1) + v * sin(t1)
		var quad := [[a + n0 * r0, n0, Vector2(float(i) / sides, 0)], [a + n1 * r0, n1, Vector2(float(i + 1) / sides, 0)],
			[to + n1 * r1, n1, Vector2(float(i + 1) / sides, length)], [to + n0 * r1, n0, Vector2(float(i) / sides, length)]]
		# Godot's front faces wind clockwise seen from outside.
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(quad[k][1])
			st.set_uv(quad[k][2])
			st.add_vertex(quad[k][0])
