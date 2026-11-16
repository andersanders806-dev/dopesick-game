extends SceneTree
## Dev helper (SHIP 16 B2): a gun's top profile, as weapons/GunModel.gd builds it, in 2 cm slices from the muzzle back: the
## heights of its vertices above `ymin` and the slice's x range and middle. Where the sights stand (player/GunViews.gd
## sight_pts), where a built-in sight's glass is (hole), and whether the barrel drifts off the centreline (the yaw).
## Needs the renderer's mesh data: run windowed (tiny is fine) under the gpu lock.
##   flatpak run org.godotengine.Godot --path . --resolution 320x200 --windowed -s res://dev-tools/gun_profile.gd -- mp5 0.095
const GunModel := preload("res://weapons/GunModel.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var ymin := float(args[1]) if args.size() > 1 else 0.09
	var d: Resource = load("res://weapons/%s.tres" % id)
	var gun := GunModel.build(d)
	root.add_child(gun)
	var verts := PackedVector3Array()
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible:
			continue
		var xf := Transform3D()
		var c: Node = m
		while c != gun:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			verts.append_array(xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	var box := GunModel.bounds(gun, gun)
	print("box ", box)
	var z := box.position.z
	while z < box.end.z:
		var ys := {}
		var xmax := 0.0
		var xlo := 9.0
		var xhi := -9.0
		for v in verts:
			if v.z >= z and v.z < z + 0.02 and v.y > ymin:
				ys[snappedf(v.y, 0.004)] = true
				xmax = maxf(xmax, absf(v.x))
				xlo = minf(xlo, v.x)
				xhi = maxf(xhi, v.x)
		if not ys.is_empty():
			var k := ys.keys()
			k.sort()
			print("z %.2f..%.2f  y %s  x %.3f..%.3f mid %.4f" % [z, z + 0.02, str(k).substr(0, 90), xlo, xhi, (xlo + xhi) * 0.5])
		z += 0.02
	quit()
