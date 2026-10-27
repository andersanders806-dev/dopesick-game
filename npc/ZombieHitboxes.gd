extends RefCounted
## The hit zones of a Rocketbox body: one Area3D with a capsule per body part,
## each on a BoneAttachment3D so it follows the animation. Eleven parts
## (head, neck, torso, upper/lower arms and legs, left and right); the Area3D
## carries meta `part` and `zombie`, which is what a hitscan ray reads off
## its hit (collide_with_areas, mask HITBOX_LAYER).
##
## Shapes are laid out from the skeleton's rest pose, so they fit whichever
## Rocketbox avatar the zombie wears: two skeleton-space points and a radius
## in metres per part.

const HITBOX_LAYER := 64

const PARTS := ["head", "neck", "torso", "upper_arm_l", "upper_arm_r", "lower_arm_l", "lower_arm_r",
	"upper_leg_l", "upper_leg_r", "lower_leg_l", "lower_leg_r"]

## part -> [bone it rides, from point, to point, radius in metres]. A point
## is a bone name, or "a+b" for the middle of two bones.
const LAYOUT := {
	"head": ["Bip01 Head", "Bip01 Head", "eyes_up", 0.11],
	"neck": ["Bip01 Neck", "Bip01 Neck", "Bip01 Head", 0.06],
	"torso": ["Bip01 Spine1", "Bip01 Pelvis", "Bip01 Neck", 0.18],
	"upper_arm_l": ["Bip01 L UpperArm", "Bip01 L UpperArm", "Bip01 L Forearm", 0.055],
	"upper_arm_r": ["Bip01 R UpperArm", "Bip01 R UpperArm", "Bip01 R Forearm", 0.055],
	"lower_arm_l": ["Bip01 L Forearm", "Bip01 L Forearm", "Bip01 L Hand", 0.05],
	"lower_arm_r": ["Bip01 R Forearm", "Bip01 R Forearm", "Bip01 R Hand", 0.05],
	"upper_leg_l": ["Bip01 L Thigh", "Bip01 L Thigh", "Bip01 L Calf", 0.09],
	"upper_leg_r": ["Bip01 R Thigh", "Bip01 R Thigh", "Bip01 R Calf", 0.09],
	"lower_leg_l": ["Bip01 L Calf", "Bip01 L Calf", "Bip01 L Foot", 0.07],
	"lower_leg_r": ["Bip01 R Calf", "Bip01 R Calf", "Bip01 R Foot", 0.07],
}

## Builds the zombie's hitboxes under `skeleton`, which must already be in the
## tree (its scale is how metres turn into skeleton units). Returns part ->
## Area3D.
static func build(skeleton: Skeleton3D, zombie: Node) -> Dictionary:
	var out := {}
	var unit := skeleton.global_transform.basis.get_scale().x
	if unit <= 0.0:
		return out
	for part in PARTS:
		var spec: Array = LAYOUT[part]
		var bone := skeleton.find_bone(spec[0])
		if bone < 0:
			continue
		var a := _point(skeleton, spec[1])
		var b := _point(skeleton, spec[2])
		var attach := BoneAttachment3D.new()
		attach.name = "Hit_" + part
		attach.bone_name = spec[0]
		skeleton.add_child(attach)
		var area := Area3D.new()
		area.name = "Box"
		area.collision_layer = HITBOX_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("part", part)
		area.set_meta("zombie", zombie)
		attach.add_child(area)
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var radius: float = spec[3] / unit
		var length := a.distance_to(b)
		cap.radius = radius
		cap.height = maxf(length + radius * 2.0, radius * 2.0 + 0.01)
		shape.shape = cap
		# Capsule axis is +Y: turn it onto a -> b, in the bone's own frame.
		var rest := skeleton.get_bone_global_rest(bone)
		var axis := (b - a).normalized() if length > 0.0001 else Vector3.UP
		var basis := Basis(Quaternion(Vector3.UP, axis)) if absf(axis.dot(Vector3.UP)) < 0.9999 else (Basis() if axis.y > 0.0 else Basis(Vector3.RIGHT, PI))
		var world_xf := Transform3D(basis, (a + b) * 0.5)
		shape.transform = rest.affine_inverse() * world_xf
		area.add_child(shape)
		out[part] = area
	return out

## A skeleton-space rest position: a bone, or the head's eye line lifted to the
## crown ("eyes_up").
static func _point(sk: Skeleton3D, spec: String) -> Vector3:
	if spec == "eyes_up":
		var l := sk.find_bone("Bip01 LEye")
		var r := sk.find_bone("Bip01 REye")
		var h := sk.get_bone_global_rest(sk.find_bone("Bip01 Head")).origin
		var eyes := (sk.get_bone_global_rest(l).origin + sk.get_bone_global_rest(r).origin) * 0.5 if l >= 0 and r >= 0 else h + Vector3.UP * 6.0
		# From the eyes up to the crown: about half again the way from
		# the head bone to the eyes.
		return eyes + Vector3.UP * (eyes.y - h.y) * 0.35
	return sk.get_bone_global_rest(sk.find_bone(spec)).origin
