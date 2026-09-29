extends RefCounted
## Varies how a character model looks without authoring new art.
##
## The Quaternius human models split the body into *named* surfaces on one
## mesh -- "Skin", "Hair", "Shirt", "Pants", "Shoes", "Socks", "Eyes", and a
## couple of outfit-specific extras -- so recolouring a single surface gives
## a genuinely different-looking person off the same body. That's what lets
## a cast of ~14 characters come out of 8 downloaded models without anybody
## looking like anybody else.
##
## The older Kenney Mini Characters instead keep clothes and head as separate
## *meshes* ("body-mesh"/"head-mesh") over one shared colour atlas. Both are
## still supported, because the 2D scenes and any not-yet-converted prop
## still use them.

## Surface names treated as clothing, in the order a "clothes tint" applies.
const CLOTHING_SURFACES := ["Shirt", "Pants", "Details", "TieTexture"]

## How each surface should respond to light. The models ship every surface at
## roughness 1.0 with no texture, which is completely matte -- under this
## game's small point lights that leaves characters as flat silhouettes with
## no highlight anywhere, which is most of what made them read as cardboard.
## Skin and hair especially need a sheen to look like a person.
const SURFACE_FINISH := {
	"Skin": {"roughness": 0.62, "specular": 0.45},
	"Hair": {"roughness": 0.58, "specular": 0.55},
	"Eyes": {"roughness": 0.25, "specular": 0.85},
	"Shirt": {"roughness": 0.88, "specular": 0.25},
	"Pants": {"roughness": 0.85, "specular": 0.30},
	"Shoes": {"roughness": 0.55, "specular": 0.55},
	"Socks": {"roughness": 0.95, "specular": 0.15},
}

## Recolours whichever surfaces the model actually has, and gives every
## surface a sane finish. `parts` maps a surface name (or the special key
## "clothes", meaning every clothing surface) to a Color. Unknown names are
## ignored, so one look dictionary can be reused across outfits that don't
## share every surface.
##
## Colours are *set*, not multiplied. The Quaternius surfaces are flat
## untextured colours that already sit fairly dark (a shirt is about 0.40
## grey), so multiplying a dark tint over them drove characters to near-black
## and they disappeared into these dim rooms entirely. There's no texture
## detail to preserve, so there's nothing to lose by replacing outright.
static func apply(model: Node, parts: Dictionary) -> void:
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var mat := inst.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var surface := mat.resource_name
			var tint: Variant = parts.get(surface)
			if tint == null and surface in CLOTHING_SURFACES:
				tint = parts.get("clothes")
			var finish: Dictionary = SURFACE_FINISH.get(surface, {})
			if tint == null and finish.is_empty():
				continue
			var dup := mat.duplicate() as BaseMaterial3D
			if tint != null:
				dup.albedo_color = tint as Color
			if not finish.is_empty():
				dup.roughness = finish["roughness"]
				dup.metallic_specular = finish["specular"]
			inst.set_surface_override_material(i, dup)

## Back-compatible helper: tints just the clothing. Works on the Quaternius
## models (by surface name) and on the Kenney ones (by mesh name).
static func tint_clothes(model: Node, tint: Color) -> void:
	if model == null or tint == Color.WHITE:
		return
	apply(model, {"clothes": tint})
	for mi in model.find_children("body-mesh", "MeshInstance3D", true, false):
		var base := (mi as MeshInstance3D).mesh.surface_get_material(0)
		if base == null:
			continue
		var mat := base.duplicate() as BaseMaterial3D
		mat.albedo_color = tint
		(mi as MeshInstance3D).material_override = mat
