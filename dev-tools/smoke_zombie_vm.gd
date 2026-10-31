extends SceneTree
## Viewmodel arms and optic checks (headless, self-contained): the support hand reaches the
## handguard on every long gun, the forearms are slimmer than the avatar's, the red dot sight's
## logo is painted out and its reticle kept.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_vm.gd
const Viewmodel := preload("res://player/Viewmodel.gd")
var fails := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	await process_frame
	var host := Node3D.new()
	root.add_child(host)
	_check(Viewmodel.ARM_SLIM < 1.0 and Viewmodel.ARM_SLIM > 0.5, "forearms thinner than the avatar's (%.2f)" % Viewmodel.ARM_SLIM)
	for id in ["ar", "smg", "lmg", "shotgun", "pistol"]:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var vm := Viewmodel.new()
		host.add_child(vm)
		vm.setup(d)
		var b: AABB = vm.box
		if id != "pistol":
			var wraps: bool = id != "shotgun"
			# The support hand sits on the front half of the gun, beside or under it (not inside
			# the receiver where the gun hides it), within a hand's reach of the gun's box.
			var front: bool = vm.grip_l.z < b.position.z + b.size.z * 0.6
			_check(front, "%s: left hand on the front half of the gun" % id)
			var inflated := b.grow(0.12)
			_check(inflated.has_point(vm.grip_l), "%s: left hand within reach of the gun" % id)
			var beside: bool = absf(vm.grip_l.x) >= 0.02 or not wraps
			_check(beside, "%s: left hand beside the gun's axis, not inside the body (x %.3f)" % [id, vm.grip_l.x])
		else:
			_check(vm.grip_l.y < vm.grip_r.y, "pistol: support hand under the firing hand")
		_check(vm.arms != null, "%s: arms built" % id)
		if id == "ar" or id == "smg":
			_check(vm.has_optic and vm.optic != null, "%s: red dot fitted" % id)
			var painted := 0
			var dot := vm.optic.get_node_or_null("Dot") != null
			for mi in vm.optic.find_children("*", "MeshInstance3D", true, false):
				var inst := mi as MeshInstance3D
				if inst.mesh == null:
					continue
				for s in inst.mesh.get_surface_count():
					var sm := inst.get_surface_override_material(s) as ShaderMaterial
					if sm != null and sm.get_shader_parameter("blank_rect") != null:
						var r: Vector4 = sm.get_shader_parameter("blank_rect")
						if r.z > r.x and r.w > r.y:
							painted += 1
			_check(painted > 0, "%s: sight logo blanked on %d surfaces" % [id, painted])
			_check(dot, "%s: red reticle kept" % id)
		vm.queue_free()
		await process_frame
	print("smoke_zombie_vm: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
