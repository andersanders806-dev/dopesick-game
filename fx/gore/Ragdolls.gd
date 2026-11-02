extends Node
## Ragdolls for the dead (zombie mode): ten rigid bodies on the zombie's hit-zone capsules
## (torso, head, upper and lower arms and legs) joined at the bone joints, thrown with the shot's
## impulse (a shotgun at point blank throws them hard), driving the skeleton through
## RagdollModifier. No more than 6 run at once (the oldest is frozen on the spot), each
## freezes after 3 s: the bodies are freed and the pose is held, so a heap costs nothing.
##
## Built from the zones, not from PhysicalBone3D: the zombie's skeleton sits under a 0.015 scale that
## physical bones do not cope with, and the bodies here are in metres.

const MAX_ACTIVE := 6
const FREEZE_AFTER := 3.0
## Collision: bodies sit on layer 512 and meet the street's floor (16) and walls (1), not each other or the living.
const LAYER := 512
const MASK := 1 | 16
const RagdollModifier := preload("res://fx/gore/RagdollModifier.gd")

## part -> [bone of the zone, mass, parent part (the joint is at this part's bone), extra bones it carries]
const PARTS := {
	"torso": ["Bip01 Spine1", 28.0, "", ["Bip01 Pelvis", "Bip01 Spine"]],
	"head": ["Bip01 Head", 5.0, "torso", []],
	"upper_arm_l": ["Bip01 L UpperArm", 2.5, "torso", []],
	"lower_arm_l": ["Bip01 L Forearm", 2.0, "upper_arm_l", []],
	"upper_arm_r": ["Bip01 R UpperArm", 2.5, "torso", []],
	"lower_arm_r": ["Bip01 R Forearm", 2.0, "upper_arm_r", []],
	"upper_leg_l": ["Bip01 L Thigh", 7.0, "torso", []],
	"lower_leg_l": ["Bip01 L Calf", 4.0, "upper_leg_l", []],
	"upper_leg_r": ["Bip01 R Thigh", 7.0, "torso", []],
	"lower_leg_r": ["Bip01 R Calf", 4.0, "upper_leg_r", []],
}

class Rig:
	var zombie: Node
	var root: Node3D
	var bodies := {}
	var joints: Array = []
	var modifier: SkeletonModifier3D
	var age := 0.0
	var frozen := false
	## > 0 while something (the tsunami's flood) is carrying it: it does not freeze.
	var carried := 0.0

var _rigs: Array = []
var started := 0

func active() -> int:
	var n := 0
	for r: Rig in _rigs:
		if not r.frozen and is_instance_valid(r.zombie):
			n += 1
	return n

## Forgets every rig (the prewarm's dummy was freed with its bodies).
func reset() -> void:
	_rigs.clear()
	started = 0

func total() -> int:
	return _rigs.size()

## Lets `z` fall: `dir` is the way the shot went, `power` the launch speed in m/s, `at` where it hit (or INF).
func start(z: Node, dir: Vector3, power: float, at := Vector3.INF) -> bool:
	var sk: Skeleton3D = z._skeleton
	if sk == null or z.hitboxes.is_empty():
		return false
	for r: Rig in _rigs:
		if r.zombie == z:
			return false
	# At most six at a time: the oldest running one stops where it lies.
	var running: Array = _rigs.filter(func(r): return not r.frozen and is_instance_valid(r.zombie))
	while running.size() >= MAX_ACTIVE:
		_freeze(running.pop_front())
	z.sync_hitboxes()
	var rig := Rig.new()
	rig.zombie = z
	rig.root = Node3D.new()
	rig.root.name = "Ragdoll"
	rig.root.top_level = true
	z.add_child(rig.root)
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.BACK
	var mod := RagdollModifier.new()
	sk.add_child(mod)
	rig.modifier = mod
	var sk_world := sk.global_transform
	var unit := sk_world.basis.get_scale().x
	# The bodies, on the zones' capsules as the animation has them now.
	for part in PARTS:
		var spec: Array = PARTS[part]
		var area := z.hitboxes.get(part) as Area3D
		if area == null:
			continue
		var cs: CollisionShape3D = area.get_child(0) as CollisionShape3D
		var xf: Transform3D = area.global_transform * cs.transform
		xf.basis = xf.basis.orthonormalized()
		var body := RigidBody3D.new()
		body.name = "Rag_" + part
		body.collision_layer = LAYER
		body.collision_mask = MASK
		body.mass = spec[1]
		body.linear_damp = 0.5
		body.angular_damp = 2.5
		body.can_sleep = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.05
		body.physics_material_override = pm
		var shape := CollisionShape3D.new()
		var src := cs.shape
		if src is CapsuleShape3D:
			var c := CapsuleShape3D.new()
			c.radius = (src as CapsuleShape3D).radius * unit
			c.height = (src as CapsuleShape3D).height * unit
			shape.shape = c
		elif src is CylinderShape3D:
			var c := CylinderShape3D.new()
			c.radius = (src as CylinderShape3D).radius * unit
			c.height = (src as CylinderShape3D).height * unit
			shape.shape = c
		else:
			var b := BoxShape3D.new()
			b.size = Vector3.ONE * 0.15
			shape.shape = b
		body.add_child(shape)
		rig.root.add_child(body)
		body.global_transform = xf
		rig.bodies[part] = body
		var bone := sk.find_bone(spec[0])
		var bones := [bone]
		for extra in spec[3]:
			bones.append(sk.find_bone(extra))
		for b in bones:
			if b < 0:
				continue
			var world := sk_world * sk.get_bone_global_pose(b)
			mod.entries.append({"bone": b, "body": body, "rel": xf.affine_inverse() * world, "held": world})
	# Parent-first, as the skeleton lists its bones.
	mod.entries.sort_custom(func(a, b): return int(a["bone"]) < int(b["bone"]))
	# Joints at the bone origins.
	for part in rig.bodies:
		var parent: String = PARTS[part][2]
		if parent == "" or not rig.bodies.has(parent):
			continue
		var j := PinJoint3D.new()
		rig.root.add_child(j)
		var bone := sk.find_bone(PARTS[part][0])
		j.global_position = (sk_world * sk.get_bone_global_pose(bone)).origin
		j.node_a = j.get_path_to(rig.bodies[parent])
		j.node_b = j.get_path_to(rig.bodies[part])
		rig.joints.append(j)
	# The shot's push: everything gets the launch speed, the part that was hit a kick on top.
	var launch := d * power + Vector3(0.0, power * 0.25, 0.0)
	for part in rig.bodies:
		var body: RigidBody3D = rig.bodies[part]
		body.linear_velocity = launch * (0.8 if part != "torso" else 1.0)
	var hit_part: String = z.last_part
	if rig.bodies.has(hit_part):
		(rig.bodies[hit_part] as RigidBody3D).apply_central_impulse(d * power * 0.6)
	if z._anim_player != null:
		z._anim_player.pause()
	_rigs.append(rig)
	started += 1
	_trim()
	return true

## Carries a running ragdoll along: `vel` is the push on the ground plane (m/s), `surface_y` the height it floats at
## (the flood). Call it every physics tick while it is carried; it does not freeze meanwhile. False if `z` has none.
func carry(z: Node, vel: Vector3, surface_y: float, tumble := 1.0) -> bool:
	for r: Rig in _rigs:
		if r.zombie != z or r.frozen:
			continue
		r.carried = 0.3
		for b in r.bodies.values():
			var rb := b as RigidBody3D
			if rb == null or not is_instance_valid(rb):
				continue
			rb.sleeping = false
			var v := rb.linear_velocity
			v.x = lerpf(v.x, vel.x, 0.1)
			v.z = lerpf(v.z, vel.z, 0.1)
			v.y = clampf((surface_y - rb.global_position.y) * 3.0, -9.0, 9.0)
			rb.linear_velocity = v
			rb.angular_velocity = rb.angular_velocity.lerp(Vector3(sin(float(rb.get_instance_id() % 97)), 0.4, cos(float(rb.get_instance_id() % 89))) * 2.5 * tumble, 0.05)
		return true
	return false

func _trim() -> void:
	# Forget rigs of freed zombies.
	_rigs = _rigs.filter(func(r): return is_instance_valid(r.zombie))

func _freeze(r: Rig) -> void:
	if r.frozen:
		return
	r.frozen = true
	if is_instance_valid(r.zombie):
		# The modifier keeps the last pose; the bodies and joints go.
		for e in r.modifier.entries:
			e["body"] = null
		for j in r.joints:
			if is_instance_valid(j):
				j.queue_free()
		for b in r.bodies.values():
			if is_instance_valid(b):
				b.queue_free()
		r.bodies.clear()
		r.joints.clear()

func _physics_process(delta: float) -> void:
	var dirty := false
	for r: Rig in _rigs:
		if r.frozen:
			continue
		if not is_instance_valid(r.zombie):
			dirty = true
			r.frozen = true
			continue
		if r.carried > 0.0:
			r.carried -= delta
			r.age = 0.0
			continue
		r.age += delta
		if r.age >= FREEZE_AFTER:
			_freeze(r)
	if dirty:
		_trim()
