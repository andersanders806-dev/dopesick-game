extends SceneTree
## Dev helper: bones (rest origin, parent), materials and their textures of a Rocketbox body.
func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var n: Node = (load(path) as PackedScene).instantiate()
	root.add_child(n)
	var sk := n.find_child("Skeleton3D", true, false) as Skeleton3D
	print("root scale ", n.scale, " skeleton global scale ", sk.global_transform.basis.get_scale())
	for i in sk.get_bone_count():
		var rest := sk.get_bone_global_rest(i)
		print("%3d %-28s parent=%3d  y=%.3f  pos=%s" % [i, sk.get_bone_name(i), sk.get_bone_parent(i), rest.origin.y, rest.origin])
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		var tri := 0
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s) as BaseMaterial3D
			var arr := m.surface_get_arrays(s)
			print("mesh %s surf %d mat=%s tex=%s verts=%d tris=%d transp=%d" % [mi.name, s, mat.resource_name if mat else "-", mat.albedo_texture.resource_path if mat and mat.albedo_texture else "-", arr[Mesh.ARRAY_VERTEX].size(), (arr[Mesh.ARRAY_INDEX].size() / 3) if arr[Mesh.ARRAY_INDEX] else 0, mat.transparency if mat else -1])
	var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("clips ", ap.get_animation_list())
	quit()
