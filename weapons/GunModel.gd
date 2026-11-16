extends RefCounted
## Builds the Node3D of a gun from its WeaponData: the glTF in assets/guns/
## turned so the barrel points down -Z, scaled to the gun's length and
## pivoted near the grip, with the loose bits left out; the upgraded look as a
## glow laid over the lot. The wonder weapon has no model file and is
## kitbashed here from primitives.

const WD := preload("res://weapons/WeaponData.gd")

## Where the pivot sits along the gun, from the back (0) to the muzzle (1): the grip.
const GRIP_AT := 0.32

static var _scenes := {}

## A model's scene, kept for the session: a gun swapped away from and back to (or the red dot that the
## next gun also wears) would load again, 100 to 500 ms each time.
static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]

## Hands a scene loaded elsewhere (fx/Prewarm.gd loads them on worker threads) to the cache.
static func keep(path: String, ps: PackedScene) -> void:
	if ps != null and not _scenes.has(path):
		_scenes[path] = ps

static func build(d: WD) -> Node3D:
	var root := Node3D.new()
	root.name = "Gun_" + d.id
	var body: Node3D
	if d.model == "":
		body = _wonder(d)
	else:
		body = _load(d)
	root.add_child(body)
	if d.tint.a > 0.0:
		_glow(body, d.tint)
	return root

static func _load(d: WD) -> Node3D:
	var holder := Node3D.new()
	var ps := scene(d.model)
	if ps == null:
		return holder
	var model := ps.instantiate() as Node3D
	holder.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var low := part_path(mi, model)
		for h in d.model_hide:
			if low.contains(h):
				(mi as MeshInstance3D).visible = false
	# A model that lies on its side is stood up first, then turned to point down -Z.
	var turn := d.model_turn * (PI / 180.0)
	model.basis = Basis(Vector3.UP, deg_to_rad(d.model_yaw)) * Basis.from_euler(turn)
	var box := bounds(model, holder)
	if box.size.z > 0.0001:
		var s := d.model_length / box.size.z
		model.scale = Vector3.ONE * s
		var pivot := Vector3(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5,
			box.position.z + box.size.z * (1.0 - GRIP_AT))
		model.position = -pivot * s
	_pose_bones(model, d.model_bones)
	_move_parts(model, holder, d.model_moves)
	return holder

## A rigged model (the M249's bipod): bones turned from their rest (degrees, x y z), or shrunk (a number).
static func _pose_bones(model: Node, bones: Dictionary) -> void:
	if bones.is_empty():
		return
	for sk in model.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		for bn in bones:
			var i := s.find_bone(String(bn))
			if i < 0:
				continue
			var v = bones[bn]
			if v is Vector3:
				var e: Vector3 = (v as Vector3) * (PI / 180.0)
				s.set_bone_pose_rotation(i, (s.get_bone_rest(i).basis * Basis.from_euler(e)).get_rotation_quaternion())
			else:
				# A number: the bone (and what hangs on it) shrunk to that size; 0.001 takes it out of the picture.
				s.set_bone_pose_scale(i, Vector3.ONE * float(v))

## Parts of a model put somewhere else (metres in the gun's space): the RPG's spare rocket, which the model has lying
## along the tube, goes into the muzzle.
static func _move_parts(model: Node, holder: Node3D, moves: Dictionary) -> void:
	if moves.is_empty():
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var low := part_path(mi, model)
		for frag in moves:
			if not low.contains(String(frag)):
				continue
			var xf := Basis.IDENTITY
			var c: Node = mi.get_parent()
			while c != null and c != holder:
				xf = (c as Node3D).transform.basis * xf
				c = c.get_parent()
			(mi as Node3D).position += xf.inverse() * (moves[frag] as Vector3)
			break

## What a mesh is called for the hide and moving-part lists: its own name and those of the nodes over it inside the model,
## in lower case ("magazine_low/magazine_low_magazine_0"): a Sketchfab export names the part on the parent, not the mesh.
static func part_path(mi: Node, model: Node) -> String:
	var out := String(mi.name)
	var c := mi.get_parent()
	while c != null and c != model:
		out = String(c.name) + "/" + out
		c = c.get_parent()
	return out.to_lower()

## The box of the visible meshes under `node`, in `top`'s space (node is a child of top).
static func bounds(node: Node3D, top: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var xf := Transform3D()
		var c: Node = m
		while c != null and c != top:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var a := xf * m.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out

## A glow over every mesh: the upgrade machine's new look.
static func _glow(body: Node3D, tint: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat

## A ray gun from boxes and tubes: a fat body, a coil on the barrel and a core that glows.
static func _wonder(d: WD) -> Node3D:
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.26)
	metal.metallic = 0.8
	metal.roughness = 0.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.9, 1.0)
	glow.emission_energy_multiplier = 2.5
	var len := d.model_length
	_part(root, BoxMesh.new(), Vector3(0.07, 0.11, len * 0.5), Vector3(0, 0, len * 0.05), metal)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.025
	barrel.bottom_radius = 0.03
	barrel.height = len * 0.55
	_part(root, barrel, Vector3.ONE, Vector3(0, 0.02, -len * 0.4), metal, Vector3(90, 0, 0))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.03
	coil.outer_radius = 0.05
	for i in 3:
		_part(root, coil, Vector3.ONE, Vector3(0, 0.02, -len * (0.22 + 0.14 * i)), glow, Vector3(90, 0, 0))
	var core := SphereMesh.new()
	core.radius = 0.04
	core.height = 0.08
	_part(root, core, Vector3.ONE, Vector3(0, 0.07, len * 0.02), glow)
	_part(root, BoxMesh.new(), Vector3(0.045, 0.13, 0.06), Vector3(0, -0.11, len * 0.18), metal, Vector3(18, 0, 0))
	return root

static func _part(parent: Node3D, mesh: Mesh, size: Vector3, at: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
