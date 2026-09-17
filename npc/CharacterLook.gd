extends RefCounted
## Small helpers for varying how a Kenney Mini Character looks without new
## art. The models keep the clothes/arms ("body-mesh") and head ("head-mesh")
## as separate meshes over one shared colour atlas, so tinting just the body
## reads as different clothing.

static func tint_clothes(model: Node, tint: Color) -> void:
	if tint == Color.WHITE:
		return
	for mi in model.find_children("body-mesh", "MeshInstance3D", true, false):
		var base := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if base == null:
			continue
		var mat := base.duplicate() as BaseMaterial3D
		mat.albedo_color = tint
		(mi as MeshInstance3D).material_override = mat
