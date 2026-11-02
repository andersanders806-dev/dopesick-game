extends SkeletonModifier3D
## Drives the zombie's main bones from the bodies of its ragdoll (fx/gore/Ragdolls.gd), after the
## animation: each entry puts one bone where a rigid body says (the bone's frame in the body's
## frame, kept from the moment the ragdoll began). Everything below those bones (hands, fingers,
## face) follows through its own local pose. Once the bodies are gone it holds the last place.

## Each: {bone, body (RigidBody3D or null), rel (bone in body space), held (world transform when frozen)}
var entries: Array = []
var calls := 0

func _process_modification() -> void:
	calls += 1
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	for e in entries:
		var body = e["body"]
		var world: Transform3D
		if body != null and is_instance_valid(body):
			world = (body as Node3D).global_transform * (e["rel"] as Transform3D)
			e["held"] = world
		else:
			world = e["held"]
		sk.set_bone_global_pose(int(e["bone"]), inv * world)
