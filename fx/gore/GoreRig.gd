extends RefCounted
## Cuts a zombie's body into limbs, at run time, from the Rocketbox mesh it already wears:
## which triangles belong to the head, an arm, a forearm, a thigh, a shin (the bone that
## has most weight on the triangle's vertices), as a static mesh centred on itself for a
## gib to carry. Also finds the vertex nearest a hit (in the body's rest pose) so a wound can be
## painted on the skin where the bullet went in. Per body, cached.

## limb -> [the bone cut at, its parent, radius (m), whether the limb's whole subtree goes with it]
const LIMBS := {
	"head": ["Bip01 Head", "Bip01 Neck", 0.085, true],
	"arm_l": ["Bip01 L UpperArm", "Bip01 L Clavicle", 0.05, false],
	"arm_r": ["Bip01 R UpperArm", "Bip01 R Clavicle", 0.05, false],
	"forearm_l": ["Bip01 L Forearm", "Bip01 L UpperArm", 0.04, true],
	"forearm_r": ["Bip01 R Forearm", "Bip01 R UpperArm", 0.04, true],
	"leg_l": ["Bip01 L Thigh", "Bip01 Pelvis", 0.085, false],
	"leg_r": ["Bip01 R Thigh", "Bip01 Pelvis", 0.085, false],
	"shin_l": ["Bip01 L Calf", "Bip01 L Thigh", 0.06, true],
	"shin_r": ["Bip01 R Calf", "Bip01 R Thigh", 0.06, true],
}

## A hit zone -> the bones whose skin it covers (for placing a wound).
const PART_BONES := {
	"head": ["Bip01 Head"],
	"neck": ["Bip01 Neck", "Bip01 Head"],
	"torso": ["Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Bip01 Pelvis", "Bip01 L Clavicle", "Bip01 R Clavicle"],
	"upper_arm_l": ["Bip01 L UpperArm"], "upper_arm_r": ["Bip01 R UpperArm"],
	"lower_arm_l": ["Bip01 L Forearm", "Bip01 L Hand"], "lower_arm_r": ["Bip01 R Forearm", "Bip01 R Hand"],
	"upper_leg_l": ["Bip01 L Thigh"], "upper_leg_r": ["Bip01 R Thigh"],
	"lower_leg_l": ["Bip01 L Calf", "Bip01 L Foot"], "lower_leg_r": ["Bip01 R Calf", "Bip01 R Foot"],
}

## The id a vertex carries (vertex colour red = id / 16) so the skin shader can clip a lost limb.
const LIMB_ID := {"head": 1, "arm_l": 2, "arm_r": 3, "forearm_l": 4, "forearm_r": 5, "leg_l": 6, "leg_r": 7, "shin_l": 8, "shin_r": 9}
const HIDDEN_SHADER := preload("res://fx/gore/gore_hidden.gdshader")

static var _tables := {}
static var _clipped := {}
static var _limb_cache := {}

## The skinned MeshInstance3D of the body (the one with the skin).
static func body_mesh(sk: Skeleton3D) -> MeshInstance3D:
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin != null and m.mesh != null and m.mesh.get_surface_count() > 0:
			return m
	return null

static func subtree(sk: Skeleton3D, root: int, whole := true) -> Dictionary:
	var out := {root: true}
	if not whole:
		return out
	var changed := true
	while changed:
		changed = false
		for i in sk.get_bone_count():
			if not out.has(i) and out.has(sk.get_bone_parent(i)):
				out[i] = true
				changed = true
	return out

## Gives the body mesh a limb id on every vertex (shared by every zombie of the body, built once),
## so a lost limb is clipped away in the skin shader instead of folded to a point.
static func prepare(z: Node) -> void:
	var sk: Skeleton3D = z._skeleton
	var inst := body_mesh(sk)
	if inst == null:
		return
	var body: String = z.get_meta("body", "")
	if _clipped.has(body):
		inst.mesh = _clipped[body]
		return
	var old := inst.mesh as ArrayMesh
	if old == null:
		return
	var map := bind_map(inst, sk)
	var sets := {}
	# Deepest first: a forearm vertex is a forearm's, not the arm's.
	for name_ in ["forearm_l", "forearm_r", "shin_l", "shin_r", "head", "arm_l", "arm_r", "leg_l", "leg_r"]:
		var spec: Array = LIMBS[name_]
		sets[name_] = subtree(sk, sk.find_bone(spec[0]), spec[3])
	var fresh := ArrayMesh.new()
	for s in old.get_surface_count():
		var a := old.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var n := verts.size()
		var stride := bones.size() / maxi(n, 1)
		var colors := PackedColorArray()
		colors.resize(n)
		for i in n:
			var best := -1
			var bw := -1.0
			for k in stride:
				var w := weights[i * stride + k] if weights.size() > i * stride + k else 0.0
				if w > bw:
					bw = w
					best = bones[i * stride + k]
			var bone: int = map[best] if best >= 0 and best < map.size() else -1
			var id := 0
			for name_ in sets:
				if (sets[name_] as Dictionary).has(bone):
					id = LIMB_ID[name_]
					break
			colors[i] = Color(float(id) / 16.0, 0.0, 0.0, 1.0)
		a[Mesh.ARRAY_COLOR] = colors
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			a[c] = null
		fresh.add_surface_from_arrays(old.surface_get_primitive_type(s), a, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if stride == 8 else 0)
		fresh.surface_set_material(s, old.surface_get_material(s))
		fresh.surface_set_name(s, old.surface_get_name(s))
	if fresh.get_surface_count() != old.get_surface_count():
		_clipped[body] = old
		return
	fresh.custom_aabb = old.get_aabb()
	_clipped[body] = fresh
	inst.mesh = fresh

## Mesh bone index (in the skin's list) -> skeleton bone.
static func bind_map(inst: MeshInstance3D, sk: Skeleton3D) -> PackedInt32Array:
	var skin := inst.skin
	var out := PackedInt32Array()
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = sk.find_bone(skin.get_bind_name(i))
		out.append(b)
	return out

## Per surface: rest positions, uvs and the dominant skeleton bone of every vertex.
static func table(z: Node) -> Array:
	var body: String = z.get_meta("body", "")
	if _tables.has(body):
		return _tables[body]
	var sk: Skeleton3D = z._skeleton
	var inst := body_mesh(sk)
	var out := []
	if inst == null:
		return out
	var map := bind_map(inst, sk)
	var binds := []
	for i in inst.skin.get_bind_count():
		var b := map[i]
		binds.append(sk.get_bone_global_rest(b) * inst.skin.get_bind_pose(i) if b >= 0 else Transform3D.IDENTITY)
	for s in inst.mesh.get_surface_count():
		var a := inst.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES] if a[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS] if a[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var n := verts.size()
		var stride := bones.size() / maxi(n, 1)
		var dom := PackedInt32Array()
		dom.resize(n)
		var rest := PackedVector3Array()
		rest.resize(n)
		var nrm := PackedVector3Array()
		nrm.resize(n)
		var src_n: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		for i in n:
			var best := -1
			var bw := -1.0
			for k in stride:
				var w := weights[i * stride + k] if weights.size() > i * stride + k else 0.0
				if w > bw:
					bw = w
					best = bones[i * stride + k]
			dom[i] = map[best] if best >= 0 and best < map.size() else -1
			var bx: Transform3D = binds[best] if best >= 0 and best < binds.size() else Transform3D.IDENTITY
			# Mesh space -> the skeleton's rest pose (the bind pose carries the model's unit scale).
			rest[i] = bx * verts[i]
			nrm[i] = (bx.basis.orthonormalized() * src_n[i]).normalized() if src_n.size() > i else Vector3.UP
		out.append({"rest": rest, "uv": uvs, "dom": dom, "nrm": nrm})
	_tables[body] = out
	return out

## The limb's gib: {mesh, surfaces (source surface of each), centre (rest space), size, cut (the cut point, relative to centre)}.
static func limb(z: Node, name_: String) -> Dictionary:
	var key: String = String(z.get_meta("body", "")) + "/" + name_
	if _limb_cache.has(key):
		return _limb_cache[key]
	var sk: Skeleton3D = z._skeleton
	var inst := body_mesh(sk)
	var spec: Array = LIMBS[name_]
	var cut_bone := sk.find_bone(spec[0])
	var set := subtree(sk, cut_bone, spec[3])
	var tab := table(z)
	var mesh := ArrayMesh.new()
	var surfaces: Array[int] = []
	var acc := Vector3.ZERO
	var count := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var picks := []
	for s in tab.size():
		var a := inst.mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var dom: PackedInt32Array = tab[s]["dom"]
		var tris := PackedInt32Array()
		var i := 0
		while i + 2 < idx.size():
			var c := 0
			for k in 3:
				if set.has(dom[idx[i + k]]):
					c += 1
			if c >= 2:
				tris.append(idx[i])
				tris.append(idx[i + 1])
				tris.append(idx[i + 2])
			i += 3
		picks.append(tris)
		for v in tris:
			var p: Vector3 = tab[s]["rest"][v]
			acc += p
			count += 1
			lo = lo.min(p)
			hi = hi.max(p)
	var centre := acc / float(maxi(count, 1))
	for s in tab.size():
		var tris: PackedInt32Array = picks[s]
		if tris.is_empty():
			continue
		var a := inst.mesh.surface_get_arrays(s)
		var src_v: PackedVector3Array = tab[s]["rest"]
		var src_n: PackedVector3Array = tab[s]["nrm"]
		var src_uv: PackedVector2Array = tab[s]["uv"]
		var remap := {}
		var v := PackedVector3Array()
		var nrm := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		for t in tris:
			if not remap.has(t):
				remap[t] = v.size()
				v.append(src_v[t] - centre)
				nrm.append(src_n[t])
				uv.append(src_uv[t] if src_uv.size() > t else Vector2.ZERO)
			idx.append(remap[t])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		surfaces.append(s)
	var cut_rest := sk.get_bone_global_rest(cut_bone).origin
	# The limb's cross-section at the cut: how far the skin lies from the limb's axis near the cut.
	var axis := (centre - cut_rest).normalized() if (centre - cut_rest).length() > 0.0001 else Vector3.UP
	var len_limb := maxf((centre - cut_rest).length() * 2.0, 0.0001)
	var rsum := 0.0
	var rn := 0
	for s in tab.size():
		for t in picks[s]:
			var rel: Vector3 = tab[s]["rest"][t] - cut_rest
			var along := rel.dot(axis)
			if along > -len_limb * 0.05 and along < len_limb * 0.18:
				rsum += (rel - axis * along).length()
				rn += 1
	var radius := rsum / float(rn) * 1.0 if rn > 0 else 0.0
	var out := {"mesh": mesh, "surfaces": surfaces, "centre": centre, "size": (hi - lo) if count > 0 else Vector3.ONE * 0.1,
		"cut": cut_rest - centre, "bone": cut_bone, "triangles": count / 3, "radius": radius}
	_limb_cache[key] = out
	return out

## Where on the skin a hit landed, as (u, v, surface): the vertex nearest the point
## (skeleton space, in the pose it has now) among those the part's bones carry.
static func wound_uv(z: Node, part: String, p_world: Vector3) -> Vector3:
	var sk: Skeleton3D = z._skeleton
	var tab := table(z)
	if tab.is_empty() or not PART_BONES.has(part):
		return Vector3(-1, -1, -1)
	var names: Array = PART_BONES[part]
	var want := {}
	var main := -1
	for n in names:
		var b := sk.find_bone(n)
		if b >= 0:
			want[b] = true
			if main < 0:
				main = b
	if main < 0:
		return Vector3(-1, -1, -1)
	var p := sk.global_transform.affine_inverse() * p_world
	var unposed := sk.get_bone_global_rest(main) * (sk.get_bone_global_pose(main).affine_inverse() * p)
	var best := INF
	var out := Vector3(-1, -1, -1)
	for s in tab.size():
		var rest: PackedVector3Array = tab[s]["rest"]
		var dom: PackedInt32Array = tab[s]["dom"]
		var uv: PackedVector2Array = tab[s]["uv"]
		for i in rest.size():
			if not want.has(dom[i]):
				continue
			var d := rest[i].distance_squared_to(unposed)
			if d < best:
				best = d
				out = Vector3(uv[i].x, uv[i].y, float(s))
	return out
