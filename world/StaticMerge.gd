extends RefCounted
## Merges the small, anonymous, static meshes a builder script made under one node (a front's wall slabs, trims,
## sills, sign backs) into one mesh per material, so a front is a dozen draws and not 100.
##
## Why: on a UHD 620 every draw call costs ~12 us of GPU whatever it draws (a night street's facades were 287 calls
## and 3.6 ms; 747 of the objects behind them were boxes of 12 triangles). Only what nobody can reach is merged:
## nodes whose engine-made name starts with "@" (nobody looks them up by name), with no children, no groups, no
## material override, opaque materials, few triangles (so no mesh LOD is lost), visible, and not world-space
## texture-mapped differently once moved. Everything named, toggled, animated or see-through stays as it was.

const MAX_TRIS := 600

## Merges `parent`'s anonymous small meshes. Returns how many nodes it replaced.
static func merge_anonymous(parent: Node3D, max_tris := MAX_TRIS) -> int:
	var groups := {}  # key -> {"mat": Material, "shadow": int, "st": SurfaceTool, "nodes": 0}
	var taken: Array[MeshInstance3D] = []
	for n in parent.get_children():
		var mi := n as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("@") or mi.mesh == null or not mi.visible:
			continue
		if mi.get_child_count() > 0 or mi.material_override != null or mi.material_overlay != null or mi.get_script() != null:
			continue
		if mi.visibility_range_end > 0.0 or mi.visibility_range_begin > 0.0 or mi.skin != null:
			continue
		if not _plain_groups(mi) or not mi.get_meta_list().is_empty():
			continue
		if not _mergeable(mi, max_tris):
			continue
		taken.append(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var key := "%d/%d" % [mat.get_instance_id() if mat != null else 0, mi.cast_shadow]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"mat": mat, "shadow": mi.cast_shadow, "st": st, "n": 0}
			groups[key]["st"].append_from(mi.mesh, s, mi.transform)
			groups[key]["n"] += 1
	if taken.size() < 2:
		return 0
	var made := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var mesh: ArrayMesh = (g["st"] as SurfaceTool).commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		if g["mat"] != null:
			mesh.surface_set_material(0, g["mat"])
		var out := MeshInstance3D.new()
		out.name = "Merged%d" % made
		out.mesh = mesh
		out.cast_shadow = g["shadow"]
		parent.add_child(out)
		made += 1
	for mi in taken:
		parent.remove_child(mi)
		mi.free()
	return taken.size()

static func _plain_groups(n: Node) -> bool:
	for g in n.get_groups():
		if not String(g).begins_with("_"):
			return false
	return true

## Opaque, no world-less triplanar mapping, few triangles, on every surface.
static func _mergeable(mi: MeshInstance3D, max_tris: int) -> bool:
	var tris := 0
	for s in mi.mesh.get_surface_count():
		if mi.get_surface_override_material(s) != null:
			return false
		var mat := mi.mesh.surface_get_material(s)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and bm.blend_mode != BaseMaterial3D.BLEND_MODE_MIX:
				return false
			if bm.uv1_triplanar and not bm.uv1_world_triplanar:
				return false
			if bm.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
				return false
		elif mat is ShaderMaterial:
			return false
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			var il := am.surface_get_array_index_len(s)
			tris += (il if il > 0 else am.surface_get_array_len(s)) / 3
		else:
			tris += 12
		if tris > max_tris:
			return false
	return true
