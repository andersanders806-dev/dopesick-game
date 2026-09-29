extends SceneTree
## Dev helper: prints a model's node tree, animation clips, and mesh/material
## names, so an imported asset can be inspected without opening the editor.
##   godot --headless --path . -s res://dev-tools/inspect_model.gd -- <res://path>
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		print("== ", path)
		var ps := load(path) as PackedScene
		if ps == null:
			print("   (failed to load)")
			continue
		var n := ps.instantiate()
		_walk(n, 0)
		n.free()
	quit()

func _walk(n: Node, depth: int) -> void:
	var line := "  ".repeat(depth) + "- %s (%s)" % [n.name, n.get_class()]
	if n is AnimationPlayer:
		var clips: Array = (n as AnimationPlayer).get_animation_list()
		line += "  clips=%d %s" % [clips.size(), str(clips.slice(0, 40))]
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		var mats := []
		if m:
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				mats.append(mat.resource_name if mat else "<none>")
		line += "  surfaces=%s aabb=%s" % [str(mats), str(m.get_aabb().size) if m else "?"]
	if n is Skeleton3D:
		line += "  bones=%d" % (n as Skeleton3D).get_bone_count()
	print(line)
	for c in n.get_children():
		_walk(c, depth + 1)
