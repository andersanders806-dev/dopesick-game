extends RefCounted
## The hit zones of a Rocketbox body: one Area3D with a capsule per body part,
## laid on the bones. They are NOT glued to the bones frame by frame (twenty
## zombies is 220 moving areas, which cost the physics server 1 to 4 ms every
## tick): sync() puts them where the animation has the bones, and the weapons
## call it for the zombies near a shot's line just before they cast (see
## WeaponHolder._cast), so a ray always meets the pose on screen. Eleven parts
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
	"torso": ["Bip01 Spine1", "Bip01 Pelvis", "Bip01 Neck", 0.17, "cylinder"],
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
static func build(skeleton: Skeleton3D, zombie: Node, grow := 1.0) -> Dictionary:
	var out := {}
	var unit := skeleton.global_transform.basis.get_scale().x
	if unit <= 0.0:
		return out
	var zones := Node3D.new()
	zones.name = "HitZones"
	zombie.add_child(zones)
	for part in PARTS:
		var spec: Array = LAYOUT[part]
		var bone := skeleton.find_bone(spec[0])
		if bone < 0:
			continue
		var a := _point(skeleton, spec[1])
		var b := _point(skeleton, spec[2])
		var area := Area3D.new()
		area.name = "Hit_" + part
		area.set_meta("bone", bone)
		area.collision_layer = HITBOX_LAYER
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("part", part)
		area.set_meta("zombie", zombie)
		zones.add_child(area)
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var radius: float = spec[3] * grow / unit
		if part == "head":
			# The skull starts at the head bone, so its round bottom doesn't swallow the neck.
			a += Vector3.UP * radius
		var length := a.distance_to(b)
		if spec.size() > 4 and spec[4] == "cylinder":
			# Flat ends: the torso stops where the neck starts instead of
			# rounding up over it.
			var cyl := CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = maxf(length, 0.01)
			shape.shape = cyl
		else:
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
	sync(skeleton, out)
	return out

## Puts every zone on its bone as the skeleton stands right now.
static func sync(skeleton: Skeleton3D, zones: Dictionary) -> void:
	var sk := skeleton.global_transform
	for part in zones:
		var area := zones[part] as Area3D
		if area == null or not area.is_inside_tree():
			continue
		area.global_transform = sk * skeleton.get_bone_global_pose(int(area.get_meta("bone")))
		# Transform changes reach the physics server at the next frame; a ray cast now needs it now.
		area.force_update_transform()

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
	if spec.contains("+"):
		var two := spec.split("+")
		return (_point(sk, two[0]) + _point(sk, two[1])) * 0.5
	return sk.get_bone_global_rest(sk.find_bone(spec)).origin
