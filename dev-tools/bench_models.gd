extends SceneTree
## Dev helper (SHIP 16 B2): every gun as GunModel.build makes it (turned, scaled, pivoted at the grip), seen from
## its right side (muzzle to the right), from above (muzzle up) and from behind (the shooter's eye), with the
## parts listed: each mesh's path, whether it is shown, and its box in the gun's space (metres; -Z the muzzle).
## Reads the yaw / turn / hide of weapons/<id>.tres, so a change to dev-tools/gen_weapons.py shows up here.
## -> .pilot/ship16b2/raw/<id>.png and the parts on stdout.
##   flock ../../.gpu.lock flatpak run org.godotengine.Godot --path . --resolution 960x540 --windowed -s res://dev-tools/bench_models.gd -- [ids]
## (--headless: the parts only.)
const IDS := ["glock", "tec9", "uzi", "mp5", "vector", "ak", "m16", "sawnoff", "deagle", "aa12", "dmr", "amr", "saw", "rpg", "bat", "machete"]
const GunModel := preload("res://weapons/GunModel.gd")

func _initialize() -> void:
	var out := ProjectSettings.globalize_path("res://.pilot/ship16b2/raw")
	DirAccess.make_dir_recursive_absolute(out)
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			ids.append(a)
	if ids.is_empty():
		ids = IDS
	var headless := DisplayServer.get_name() == "headless"
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.37, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(cam)
	cam.make_current()
	for id in ids:
		var d: Resource = load("res://weapons/%s.tres" % id)
		if d == null:
			print("NO DATA ", id)
			continue
		var gun := GunModel.build(d)
		world.add_child(gun)
		var body := gun.get_child(0) as Node3D
		var box := GunModel.bounds(body, gun)
		print("== %s  box pos %s size %s" % [id, _v(box.position), _v(box.size)])
		var model := body.get_child(0) if body.get_child_count() > 0 else null
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D()
			var c: Node = m
			while c != null and c != gun:
				xf = (c as Node3D).transform * xf
				c = c.get_parent()
			var a := xf * m.mesh.get_aabb()
			var tris := 0
			for s in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(s)
				if not arr.is_empty() and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print("  %s %-60s c %s s %s tris %d" % ["+" if m.visible else "-", GunModel.part_path(m, model), _v(a.get_center()), _v(a.size), tris])
		if not headless:
			var big := maxf(box.size.z, maxf(box.size.y, box.size.x)) * 1.15
			var mid := box.get_center()
			cam.size = big
			for v in [["side", Vector3(3, 0, 0), Vector3.UP], ["top", Vector3(0, 3, 0), Vector3(0, 0, -1)], ["rear", Vector3(0, 0, 3), Vector3.UP]]:
				cam.look_at_from_position(mid + v[1], mid, v[2])
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, id, v[0]])
		gun.free()
	quit()

func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
