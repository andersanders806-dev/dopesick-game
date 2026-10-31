extends Node3D
## The gore of Dead Block (zombie mode, option on by default): wounds painted into the skin
## shader where a bullet went in, limbs that come off at a damage threshold (the bone folds to
## nothing, a stump cap closes the cut, the limb flies as a gib), the head popped by a heavy
## headshot or a shotgun at point blank, a fountain out of the neck, blood on walls and ground,
## drips from stumps, a pool under every corpse, and blood on your screen. Fiction only: only
## zombies (npc/Zombie3D.gd) call this. One per scene, found by group "gore" (Gore.of(node)).
##
## Everything is pooled and capped: 80 blood decals, 24 gibs, 12 corpse pools, 4 neck fountains,
## 12 bleeding stumps. A shotgun blast that takes several limbs pays its kill points once
## (points are the weapon's business, not this node's).

const GoreRig := preload("res://fx/gore/GoreRig.gd")
const GibPool := preload("res://fx/gore/GibPool.gd")
const ScreenBlood := preload("res://fx/gore/ScreenBlood.gd")
const ImpactFX := preload("res://fx/ImpactFX.gd")

const DECALS := 80
const POOLS := 12
const FOUNTAINS := 4
const BLEEDERS := 12
## What a limb must take (as a fraction of the zombie's health, summed over its own hit zone) to come off.
const THRESHOLD := {"lower_arm": 0.30, "upper_arm": 0.42, "lower_leg": 0.34, "upper_leg": 0.48}
## The limb a hit zone takes off.
const LIMB_OF := {"lower_arm_l": "forearm_l", "lower_arm_r": "forearm_r", "upper_arm_l": "arm_l", "upper_arm_r": "arm_r",
	"lower_leg_l": "shin_l", "lower_leg_r": "shin_r", "upper_leg_l": "leg_l", "upper_leg_r": "leg_r"}
## What a limb carries off with it.
const CHILD := {"arm_l": "forearm_l", "arm_r": "forearm_r", "leg_l": "shin_l", "leg_r": "shin_r"}
## Hit zones that stop being hittable when the limb is gone.
const ZONES := {"forearm_l": ["lower_arm_l"], "forearm_r": ["lower_arm_r"], "arm_l": ["upper_arm_l", "lower_arm_l"], "arm_r": ["upper_arm_r", "lower_arm_r"],
	"shin_l": ["lower_leg_l"], "shin_r": ["lower_leg_r"], "leg_l": ["upper_leg_l", "lower_leg_l"], "leg_r": ["upper_leg_r", "lower_leg_r"], "head": ["head", "neck"]}
## Most of each per physics frame.
const BUDGET := {"decal": 3, "wound": 2, "raycast": 4}

static var _flesh: StandardMaterial3D
static var _bone: StandardMaterial3D

var rng := RandomNumberGenerator.new()
var gibs: Node3D
var screen: CanvasLayer
var severs := 0
var heads_popped := 0
var wounds := 0
var _decals: Array[Decal] = []
var _decal_next := 0
var _textures := {}
var _pools: Array = []
var _pool_next := 0
var _fountains: Array = []
var _bleeders: Array = []
var _used := {}
var _frame := -1

static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("gore")
	if found != null:
		return found as Node3D
	var g: Node3D = (load("res://fx/gore/Gore.gd") as GDScript).new()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(g)
	return g

static func enabled() -> bool:
	return ZombieMode.gore_enabled

func _ready() -> void:
	add_to_group("gore")
	name = "Gore"
	rng.randomize()
	for k in ["splatter_01", "splatter_02", "spray_01", "spray_02", "pool_01", "pool_02", "drips_01", "drips_02"]:
		_textures[k] = load("res://assets/decals/blood_%s.png" % k)
	for i in DECALS:
		var d := Decal.new()
		d.size = Vector3(0.8, 0.4, 0.8)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 28.0
		d.distance_fade_length = 10.0
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		add_child(d)
		_decals.append(d)
	for i in POOLS:
		var d := Decal.new()
		d.visible = false
		d.size = Vector3(1.0, 0.4, 1.0)
		d.texture_albedo = _textures["pool_%02d" % (1 + i % 2)]
		add_child(d)
		_pools.append({"decal": d, "z": null, "t": 99.0, "size": 1.3})
	for i in FOUNTAINS:
		var p := _fountain_node()
		add_child(p)
		_fountains.append({"p": p, "z": null, "t": 99.0})
	gibs = GibPool.new()
	add_child(gibs)
	gibs.gib_landed.connect(_on_gib_landed)
	screen = ScreenBlood.new()
	add_child(screen)

func _fountain_node() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 46
	p.lifetime = 0.8
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 16.0
	p.initial_velocity_min = 2.2
	p.initial_velocity_max = 4.4
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.07
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.03, 0.03, 1.0))
	g.set_color(1, Color(0.3, 0.0, 0.0, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ImpactFX._soft_texture()
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

static func flesh_material() -> StandardMaterial3D:
	if _flesh == null:
		_flesh = StandardMaterial3D.new()
		_flesh.albedo_color = Color(0.34, 0.02, 0.025)
		_flesh.roughness = 0.22
		_flesh.metallic_specular = 0.7
		_flesh.emission_enabled = true
		_flesh.emission = Color(0.12, 0.0, 0.0)
	return _flesh

static func bone_material() -> StandardMaterial3D:
	if _bone == null:
		_bone = StandardMaterial3D.new()
		_bone.albedo_color = Color(0.72, 0.68, 0.58)
		_bone.roughness = 0.55
	return _bone

func _allow(kind: String) -> bool:
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_used.clear()
	var n: int = _used.get(kind, 0)
	if n >= int(BUDGET.get(kind, 99)):
		return false
	_used[kind] = n + 1
	return true

# --- Hits ---------------------------------------------------------------------------------

## Called by Zombie3D.take_hit for every hit, after health has been taken.
func on_hit(z: Node, part: String, dmg: float, dir: Vector3, at: Vector3, killed: bool, weapon: Resource) -> void:
	if not ZombieMode.gore_enabled or z._skeleton == null:
		return
	var maxh: float = z.max_health
	var pos := at
	if pos == Vector3.INF:
		z.sync_hitboxes()
		var zone := z.hitboxes.get(part) as Node3D
		pos = zone.global_position if zone != null else z.global_position + Vector3(0, 1.1, 0)
	if dmg >= maxh * 0.04 and _allow("wound"):
		_wound(z, part, dmg, pos)
	if (dmg >= maxh * 0.05 or killed) and _allow("raycast"):
		_blood_on_world(z, pos, dir, dmg)
	# Limbs come off at their own threshold; a heavy headshot or a shotgun at point blank takes the head.
	var key: String = LIMB_OF.get(part, "")
	if key != "":
		var level := part.trim_suffix("_l").trim_suffix("_r")
		var th: float = THRESHOLD[level] * maxh
		var sum: float = float(z.limb_damage.get(part, 0.0)) + dmg
		z.limb_damage[part] = sum
		if sum >= th or (killed and dmg >= th * 0.5):
			sever(z, key, dir)
	elif part == "head" and killed and not z.head_gone:
		var close: bool = weapon != null and int(weapon.get("pellets")) > 1 and z.target != null and is_instance_valid(z.target) \
			and (z.target as Node3D).global_position.distance_to(z.global_position) < 6.0
		if dmg >= maxh * 0.7 or close:
			pop_head(z, dir)

## Paints a wound into the skin shader where the bullet went in (two per zombie, the oldest redone).
func _wound(z: Node, part: String, dmg: float, pos: Vector3) -> void:
	var uvs := GoreRig.wound_uv(z, part, pos)
	if uvs.x < 0.0:
		return
	var inst := GoreRig.body_mesh(z._skeleton)
	if inst == null:
		return
	var maxh: float = z.max_health
	var k := clampf(dmg / maxf(maxh, 1.0), 0.0, 1.0)
	var radius := 0.028 + 0.05 * k
	var depth := clampf(0.25 + k * 1.4, 0.0, 1.0)
	var slot: int = z.wounds_placed % 2
	z.wounds_placed += 1
	wounds += 1
	var w := Vector4(uvs.x, uvs.y, radius, depth)
	if slot == 0:
		inst.set_instance_shader_parameter("wound_a", w)
		inst.set_instance_shader_parameter("wound_sa", uvs.z)
	else:
		inst.set_instance_shader_parameter("wound_b", w)
		inst.set_instance_shader_parameter("wound_sb", uvs.z)

## Blood on the wall behind (it goes through) and on the ground under it.
func _blood_on_world(z: Node, pos: Vector3, dir: Vector3, dmg: float) -> void:
	var space: PhysicsDirectSpaceState3D = (z as Node3D).get_world_3d().direct_space_state
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var q := PhysicsRayQueryParameters3D.create(pos, pos + d * 2.4)
	q.collision_mask = 0x7FFFFF7F
	q.exclude = [(z as CollisionObject3D).get_rid()]
	var r: Dictionary = space.intersect_ray(q)
	if not r.is_empty() and absf((r.normal as Vector3).y) < 0.6:
		splat(r.position, r.normal, rng.randf_range(0.6, 1.1) * (0.8 + dmg / maxf(z.max_health, 1.0)), "spray")
	var q2 := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 3.0)
	q2.collision_mask = 0x7FFFFF7F
	q2.exclude = [(z as CollisionObject3D).get_rid()]
	var r2: Dictionary = space.intersect_ray(q2)
	if not r2.is_empty():
		splat(r2.position, r2.normal, rng.randf_range(0.4, 0.8), "splatter")

## One blood decal (spray, splatter, drips) on a surface; the oldest of the 80 is reused.
func splat(pos: Vector3, normal: Vector3, size: float, kind := "splatter") -> void:
	if not _allow("decal"):
		return
	var d := _decals[_decal_next]
	_decal_next = (_decal_next + 1) % _decals.size()
	var k := "%s_%02d" % [kind, 1 + rng.randi() % 2]
	d.texture_albedo = _textures[k]
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var xf := ImpactFX._up_basis(n, pos + n * 0.01)
	xf.basis = xf.basis.rotated(n, rng.randf() * TAU)
	d.global_transform = xf
	d.size = Vector3(size, 0.4, size)
	d.modulate = Color(1, 1, 1, rng.randf_range(0.75, 1.0))
	d.visible = true

func decals_shown() -> int:
	var n := 0
	for d in _decals:
		if d.visible:
			n += 1
	return n

# --- Severing -----------------------------------------------------------------------------------

## Takes a limb off (and whatever hangs on it). False if it was already gone.
func sever(z: Node, limb: String, dir: Vector3) -> bool:
	if not ZombieMode.gore_enabled or z._skeleton == null or z.severed.has(limb) or z.severed.has("sev_parent_" + limb):
		return false
	var sk: Skeleton3D = z._skeleton
	var spec: Array = GoreRig.LIMBS[limb]
	var bone := sk.find_bone(spec[0])
	var parent := sk.find_bone(spec[1])
	if bone < 0 or parent < 0:
		return false
	var segs := [limb]
	if CHILD.has(limb) and not z.severed.has(CHILD[limb]):
		segs.append(CHILD[limb])
	for sg in segs:
		z.severed[sg] = true
	if CHILD.has(limb):
		z.severed["sev_parent_" + CHILD[limb]] = true
	severs += 1
	# The gibs first (they copy what the body looks like now), then the limb is clipped from the skin.
	_stump(z, limb, bone, parent)
	for sg in segs:
		_throw(z, sg, dir)
	var body := GoreRig.body_mesh(sk)
	for sg in segs:
		z.sever_bits |= 1 << int(GoreRig.LIMB_ID[sg])
	if body != null:
		body.set_instance_shader_parameter("sever_bits", float(z.sever_bits))
		if limb == "head":
			# The hair is not the skin shader's: it goes by swapping its surface for nothing.
			for si in body.mesh.get_surface_count():
				var m := body.mesh.surface_get_material(si)
				if m != null and m.resource_name.ends_with("opacity"):
					var hide := ShaderMaterial.new()
					hide.shader = GoreRig.HIDDEN_SHADER
					body.set_surface_override_material(si, hide)
	for part in ZONES.get(limb, []):
		var area := z.hitboxes.get(part) as Area3D
		if area != null:
			area.collision_layer = 0
	var joint := sk.global_transform * sk.get_bone_global_pose(bone).origin
	var fx := ImpactFX.of(z)
	if fx != null:
		fx.blood_hit(joint, dir if dir.length() > 0.01 else Vector3.UP, "torso", true, 2.0)
		fx.play(joint, "sever_%d" % (1 + rng.randi() % 2), -1.0)
		fx.play(joint, "blood_squirt_%d" % (1 + rng.randi() % 2), -4.0)
	_add_bleeder(z, bone)
	if limb in ["leg_l", "shin_l", "leg_r", "shin_r"]:
		var left: bool = z.severed.has("leg_l") or z.severed.has("shin_l")
		var right: bool = z.severed.has("leg_r") or z.severed.has("shin_r")
		if left and right:
			z.set_legless(true)
			if z.state == z.State.CHASE or z.state == z.State.STANDUP or z.state == z.State.TEAR:
				z.state = z.State.CHASE
		elif z.is_alive() and z.state == z.State.CHASE:
			z._begin_kneel()
	return true

## A flat disc of flesh with a bone in it, closing the cut on the body (follows the parent bone).
func _stump(z: Node, limb: String, bone: int, parent: int) -> void:
	var sk: Skeleton3D = z._skeleton
	var unit := maxf(sk.global_transform.basis.get_scale().x, 0.0001)
	var measured: float = float(GoreRig.limb(z, limb).get("radius", 0.0))
	var radius: float = measured if measured > 0.0 else float(GoreRig.LIMBS[limb][2]) / unit
	var att := BoneAttachment3D.new()
	att.name = "Stump_" + limb
	att.bone_name = sk.get_bone_name(parent)
	sk.add_child(att)
	var pr := sk.get_bone_global_rest(parent)
	var joint := sk.get_bone_global_rest(bone).origin
	var axis := (joint - pr.origin).normalized()
	if axis.length() < 0.001:
		axis = Vector3.UP
	var xf := pr.affine_inverse() * ImpactFX._up_basis(axis, joint - axis * radius * 0.05)
	for k in 2:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = radius * (0.97 if k == 0 else 0.3)
		cyl.bottom_radius = cyl.top_radius
		cyl.height = radius * (0.3 if k == 0 else 0.34)
		cyl.radial_segments = 12
		cyl.rings = 1
		mi.mesh = cyl
		mi.material_override = flesh_material() if k == 0 else bone_material()
		mi.transform = xf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		att.add_child(mi)

## Launches the limb as a gib from where it was.
func _throw(z: Node, seg: String, dir: Vector3) -> void:
	var sk: Skeleton3D = z._skeleton
	var data := GoreRig.limb(z, seg)
	if data.is_empty() or (data["mesh"] as ArrayMesh).get_surface_count() == 0:
		return
	var inst := GoreRig.body_mesh(sk)
	var mats := []
	for s in inst.mesh.get_surface_count():
		mats.append(inst.get_surface_override_material(s))
	var b: int = data["bone"]
	var pose := sk.get_bone_global_pose(b) * sk.get_bone_global_rest(b).affine_inverse()
	var xf: Transform3D = sk.global_transform * pose * Transform3D(Basis.IDENTITY, data["centre"])
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	d.y = 0.0
	d = d.normalized() if d.length() > 0.01 else Vector3.BACK
	var power := 2.5 if seg != "head" else 3.2
	var vel := d * rng.randf_range(2.0, 5.0) + Vector3(rng.randf_range(-1, 1), rng.randf_range(2.0, 3.6) * (1.0 if seg != "head" else 1.3), rng.randf_range(-1, 1)) * (power * 0.4)
	var unit := maxf(sk.global_transform.basis.get_scale().x, 0.0001)
	var cap_r: float = float(data.get("radius", 0.0)) if float(data.get("radius", 0.0)) > 0.0 else float(GoreRig.LIMBS[seg][2]) / unit
	gibs.spawn(data, mats, float(z._rot_amount), float(z.get_meta("seed", 0.0)), xf, vel, z.global_position.y, flesh_material(), cap_r)

func _on_gib_landed(at: Vector3, impact: float) -> void:
	splat(at + Vector3(0, 0.02, 0), Vector3.UP, rng.randf_range(0.5, 0.9) * clampf(impact / 4.0, 0.6, 1.4), "splatter")
	var fx := ImpactFX.of(self)
	if fx != null:
		fx.play(at, "gib_splat_%d" % (1 + rng.randi() % 3), -3.0 + clampf(impact - 4.0, -4.0, 2.0))

## The head comes off: the skull flies, the neck spurts for a couple of seconds.
func pop_head(z: Node, dir: Vector3) -> bool:
	if z.head_gone or z._skeleton == null:
		return false
	z.head_gone = true
	var ok := sever(z, "head", dir)
	if not ok:
		return false
	heads_popped += 1
	var fx := ImpactFX.of(z)
	var sk: Skeleton3D = z._skeleton
	var neck := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Neck")).origin
	if fx != null:
		fx.play(neck, "head_pop_%d" % (1 + rng.randi() % 2), 0.0)
		fx.blood_hit(neck + Vector3(0, 0.1, 0), Vector3.UP, "head", true, 3.0)
	_start_fountain(z)
	return true

func _start_fountain(z: Node) -> void:
	var f: Dictionary = _fountains[0]
	for e in _fountains:
		if e["t"] > f["t"]:
			f = e
	f["z"] = z
	f["t"] = 0.0
	(f["p"] as CPUParticles3D).emitting = true

# --- Bleeding, pools, the passage of time ----------------------------------------------------------

func _add_bleeder(z: Node, bone: int) -> void:
	if _bleeders.size() >= BLEEDERS:
		_bleeders.pop_front()
	_bleeders.append({"z": z, "bone": bone, "t": 0.0, "next": 0.2})

## A pool spreads under a corpse (the newest of 12).
func pool_under(z: Node) -> void:
	if not ZombieMode.gore_enabled:
		return
	var e: Dictionary = _pools[_pool_next]
	_pool_next = (_pool_next + 1) % _pools.size()
	var d: Decal = e["decal"]
	var pos: Vector3 = (z as Node3D).global_position
	var xf := ImpactFX._up_basis(Vector3.UP, Vector3(pos.x, z.global_position.y + 0.02, pos.z))
	xf.basis = xf.basis.rotated(Vector3.UP, rng.randf() * TAU)
	d.global_transform = xf
	d.size = Vector3(0.2, 0.4, 0.2)
	d.visible = true
	e["z"] = z
	e["t"] = 0.0
	e["size"] = rng.randf_range(1.2, 1.7)

func pools_shown() -> int:
	var n := 0
	for e in _pools:
		if (e["decal"] as Decal).visible:
			n += 1
	return n

func fountains_active() -> int:
	var n := 0
	for e in _fountains:
		if (e["p"] as CPUParticles3D).emitting:
			n += 1
	return n

func bleeders() -> int:
	return _bleeders.size()

func _process(delta: float) -> void:
	for e in _pools:
		if e["t"] < 6.0:
			e["t"] += delta
			var s: float = float(e["size"]) * (1.0 - pow(1.0 - clampf(e["t"] / 6.0, 0.0, 1.0), 2.0))
			(e["decal"] as Decal).size = Vector3(maxf(s, 0.2), 0.4, maxf(s, 0.2))
	for f in _fountains:
		var p: CPUParticles3D = f["p"]
		if not p.emitting:
			continue
		f["t"] += delta
		var z = f["z"]
		if f["t"] > 2.6 or not is_instance_valid(z):
			p.emitting = false
			continue
		var sk: Skeleton3D = z._skeleton
		var neck := sk.find_bone("Bip01 Neck")
		var n := sk.global_transform * sk.get_bone_global_pose(neck).origin
		# The spurts weaken as it bleeds out; pulses with the heart.
		var pulse := 0.6 + 0.4 * sin(f["t"] * 9.0)
		p.initial_velocity_max = 4.4 * (1.0 - f["t"] / 3.2) * (0.7 + 0.3 * pulse)
		p.global_position = n
	for i in range(_bleeders.size() - 1, -1, -1):
		var b: Dictionary = _bleeders[i]
		var z = b["z"]
		b["t"] += delta
		if b["t"] > 5.0 or not is_instance_valid(z) or not z.is_inside_tree():
			_bleeders.remove_at(i)
			continue
		b["next"] -= delta
		if b["next"] <= 0.0:
			b["next"] = rng.randf_range(0.35, 0.6)
			var sk: Skeleton3D = z._skeleton
			var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(b["bone"]).origin
			var gy: float = (z as Node3D).global_position.y
			if _allow("decal"):
				splat(Vector3(p.x + rng.randf_range(-0.15, 0.15), gy + 0.01, p.z + rng.randf_range(-0.15, 0.15)), Vector3.UP, rng.randf_range(0.18, 0.32), "splatter")

## You get hit, or cut one down at point blank: blood on the screen.
func screen_blood(strength := 1.0) -> void:
	if ZombieMode.gore_enabled and screen != null:
		screen.splat(strength)
