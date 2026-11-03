extends SceneTree
## Prints how to turn a gun into the aim pose's right hand and a band onto the head (headless).
func _initialize() -> void:
	await process_frame
	var model: Node3D = (load("res://assets/rocketbox/Male_Adult_04.glb") as PackedScene).instantiate()
	var holder := Node3D.new()
	root.add_child(holder)
	model.scale = Vector3.ONE * 1.5
	holder.add_child(model)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	ap.add_animation_library("gang", load("res://assets/gang_anims/gang_clips.res"))
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	ap.play("gang/ga_stand")
	ap.seek(0.0, true)
	ap.advance(0.0)
	sk.force_update_all_bone_transforms()
	var unit := sk.global_transform.basis.get_scale().x
	print("unit ", unit)
	var rh := sk.find_bone("Bip01 R Hand")
	var lh := sk.find_bone("Bip01 L Hand")
	var gp := sk.get_bone_global_pose(rh)
	var fwd := ((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 L Toe0"))).origin - (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 L Foot"))).origin)
	fwd.y = 0
	fwd = fwd.normalized()
	print("model forward (world) ", fwd)
	# Desired gun basis in WORLD: barrel (-Z) along the arm's pointing direction (hand -> forward), up = world up.
	var rh_w := sk.global_transform * gp
	var lh_w := sk.global_transform * sk.get_bone_global_pose(lh)
	var ua := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 R UpperArm"))).origin
	var ua_l := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 L UpperArm"))).origin
	var hand_w := (sk.global_transform * gp).origin
	var arm_dir := (hand_w - ua).normalized()
	print("right arm dir ", arm_dir, " upper arm ", ua, " left upper arm ", ua_l)
	var pel := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Spine2"))).basis
	print("spine2 basis z ", pel.z.normalized(), " x ", pel.x.normalized(), " y ", pel.y.normalized())
	var aim_dir := arm_dir
	var z := -aim_dir
	var y := Vector3.UP
	var x := y.cross(z).normalized()
	y = z.cross(x).normalized()
	var want_w := Basis(x, y, z)
	var hand_b := rh_w.basis.orthonormalized()
	var local := hand_b.inverse() * want_w
	print("right hand world ", rh_w.origin, " left hand ", lh_w.origin)
	print("hand->gun rotation (deg) ", local.get_euler() * 180.0 / PI, " as quat ", local.get_rotation_quaternion())
	print("hands apart (m) ", rh_w.origin.distance_to(lh_w.origin))
	# Where the hands are relative to each other in the body's frame.
	var rel := lh_w.origin - rh_w.origin
	print("left - right in (fwd, up, side): ", rel.dot(fwd), " ", rel.y, " ", rel.dot(fwd.cross(Vector3.UP)))
	var head := sk.find_bone("Bip01 Head")
	var hg := sk.global_transform * sk.get_bone_global_pose(head)
	print("head world ", hg.origin, " head basis y ", hg.basis.y.normalized(), " x ", hg.basis.x.normalized(), " z ", hg.basis.z.normalized())
	var inv := hg.basis.orthonormalized().inverse()
	print("world up in head-local ", inv * Vector3.UP, "  fwd in head-local ", inv * fwd)
	var l_eye := sk.get_bone_global_rest(sk.find_bone("Bip01 LEye")).origin
	var r_eye := sk.get_bone_global_rest(sk.find_bone("Bip01 REye")).origin
	var h_rest := sk.get_bone_global_rest(head)
	var eyes := (l_eye + r_eye) * 0.5
	print("eyes in head-local (m) ", (h_rest.affine_inverse() * eyes) * unit, " crown ", (h_rest.affine_inverse() * (eyes + Vector3.UP * (eyes.y - h_rest.origin.y) * 0.35)) * unit)
	quit(0)
