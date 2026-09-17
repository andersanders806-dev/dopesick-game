extends RefCounted
## Builds each stealable item's 3D model out of simple primitives, so every
## item in GameState.REQUEST_POOL has a recognisable shape without needing an
## art asset per product. Also used by dev-tools/render_item_icons.gd to
## render the matching HUD icons, so icon and shelf model always agree.
##
## Each recipe is a list of parts: [shape, size, offset, colour] with optional
## trailing flags "glass" (translucent) or "metal". Shapes: "box" (size is
## the box extents) and "cyl" (size.x = radius, size.y = height). Sizes are
## roughly real-world metres; StealableItem3D scales the whole thing up so
## small products stay readable from the top-down camera.

const RED := Color(0.75, 0.12, 0.1)
const WHITE := Color(0.92, 0.92, 0.9)
const BLACK := Color(0.08, 0.08, 0.09)
const CARD := Color(0.72, 0.6, 0.42)

const RECIPES := {
	"cigs": [
		["box", Vector3(0.24, 0.06, 0.1), Vector3(0, 0.03, 0), WHITE],
		["box", Vector3(0.242, 0.03, 0.102), Vector3(0, 0.045, 0), RED],
	],
	"charger": [
		["box", Vector3(0.05, 0.05, 0.05), Vector3(-0.05, 0.025, 0), WHITE],
		["box", Vector3(0.012, 0.03, 0.004), Vector3(-0.05, 0.065, 0.01), Color(0.7, 0.7, 0.7), "metal"],
		["cyl", Vector3(0.05, 0.012, 0), Vector3(0.05, 0.006, 0), WHITE],
	],
	"batteries": [
		["box", Vector3(0.12, 0.16, 0.012), Vector3(0, 0.08, 0), Color(0.15, 0.25, 0.6)],
		["cyl", Vector3(0.012, 0.09, 0), Vector3(-0.03, 0.08, 0.014), Color(0.8, 0.55, 0.15), "metal"],
		["cyl", Vector3(0.012, 0.09, 0), Vector3(0.0, 0.08, 0.014), Color(0.8, 0.55, 0.15), "metal"],
		["cyl", Vector3(0.012, 0.09, 0), Vector3(0.03, 0.08, 0.014), Color(0.8, 0.55, 0.15), "metal"],
	],
	"energy": [
		["cyl", Vector3(0.03, 0.12, 0), Vector3(-0.035, 0.06, -0.035), Color(0.3, 0.85, 0.2), "metal"],
		["cyl", Vector3(0.03, 0.12, 0), Vector3(0.035, 0.06, -0.035), Color(0.3, 0.85, 0.2), "metal"],
		["cyl", Vector3(0.03, 0.12, 0), Vector3(-0.035, 0.06, 0.035), BLACK, "metal"],
		["cyl", Vector3(0.03, 0.12, 0), Vector3(0.035, 0.06, 0.035), BLACK, "metal"],
	],
	"sunglasses": [
		["box", Vector3(0.06, 0.035, 0.008), Vector3(-0.035, 0.03, 0), BLACK, "glass"],
		["box", Vector3(0.06, 0.035, 0.008), Vector3(0.035, 0.03, 0), BLACK, "glass"],
		["box", Vector3(0.14, 0.008, 0.008), Vector3(0, 0.045, 0), Color(0.75, 0.6, 0.2), "metal"],
		["box", Vector3(0.12, 0.2, 0.004), Vector3(0, 0.1, -0.01), WHITE],
	],
	"razors": [
		["box", Vector3(0.1, 0.16, 0.02), Vector3(0, 0.08, 0), Color(0.1, 0.35, 0.75)],
		["box", Vector3(0.05, 0.09, 0.02), Vector3(0, 0.09, 0.015), Color(0.85, 0.85, 0.85), "glass"],
		["box", Vector3(0.012, 0.07, 0.01), Vector3(0, 0.08, 0.02), Color(0.9, 0.45, 0.1)],
	],
	"whitening": [
		["box", Vector3(0.12, 0.17, 0.035), Vector3(0, 0.085, 0), WHITE],
		["box", Vector3(0.122, 0.05, 0.037), Vector3(0, 0.12, 0), Color(0.2, 0.55, 0.9)],
	],
	"coldmeds": [
		["box", Vector3(0.11, 0.07, 0.035), Vector3(0, 0.035, 0), Color(0.55, 0.25, 0.7)],
		["box", Vector3(0.112, 0.02, 0.037), Vector3(0, 0.05, 0), WHITE],
	],
	"formula": [
		["cyl", Vector3(0.06, 0.15, 0), Vector3(0, 0.075, 0), WHITE],
		["cyl", Vector3(0.062, 0.025, 0), Vector3(0, 0.16, 0), Color(0.3, 0.55, 0.9)],
		["cyl", Vector3(0.061, 0.05, 0), Vector3(0, 0.07, 0), Color(0.95, 0.8, 0.3)],
	],
	"makeup": [
		["box", Vector3(0.14, 0.02, 0.09), Vector3(0, 0.01, 0), BLACK],
		["box", Vector3(0.035, 0.005, 0.03), Vector3(-0.04, 0.022, 0), Color(0.85, 0.45, 0.5)],
		["box", Vector3(0.035, 0.005, 0.03), Vector3(0.0, 0.022, 0), Color(0.6, 0.4, 0.3)],
		["box", Vector3(0.035, 0.005, 0.03), Vector3(0.04, 0.022, 0), Color(0.75, 0.6, 0.45)],
		["cyl", Vector3(0.012, 0.08, 0), Vector3(0.09, 0.04, 0), Color(0.8, 0.1, 0.2)],
	],
	"steak": [
		["box", Vector3(0.2, 0.025, 0.14), Vector3(0, 0.0125, 0), BLACK],
		["box", Vector3(0.16, 0.03, 0.1), Vector3(0, 0.035, 0), Color(0.7, 0.12, 0.12)],
		["box", Vector3(0.05, 0.031, 0.02), Vector3(0.03, 0.036, 0.02), Color(0.95, 0.85, 0.8)],
		["box", Vector3(0.2, 0.05, 0.14), Vector3(0, 0.025, 0), Color(0.9, 0.9, 0.95, 0.25), "glass"],
	],
	"detergent": [
		["box", Vector3(0.14, 0.22, 0.09), Vector3(0, 0.11, 0), Color(0.95, 0.5, 0.05)],
		["box", Vector3(0.04, 0.07, 0.03), Vector3(-0.055, 0.25, 0), Color(0.95, 0.5, 0.05)],
		["cyl", Vector3(0.025, 0.04, 0), Vector3(0.03, 0.24, 0), Color(0.1, 0.3, 0.8)],
		["box", Vector3(0.1, 0.08, 0.092), Vector3(0.01, 0.1, 0), Color(0.95, 0.9, 0.2)],
	],
	"cheese": [
		["box", Vector3(0.14, 0.06, 0.09), Vector3(0, 0.03, 0), Color(0.95, 0.75, 0.25)],
		["box", Vector3(0.142, 0.03, 0.092), Vector3(0, 0.03, 0), Color(0.2, 0.25, 0.55)],
	],
	"whiskey": [
		["box", Vector3(0.08, 0.18, 0.05), Vector3(0, 0.09, 0), Color(0.55, 0.28, 0.08, 0.85), "glass"],
		["cyl", Vector3(0.014, 0.06, 0), Vector3(0, 0.21, 0), Color(0.55, 0.28, 0.08, 0.85), "glass"],
		["cyl", Vector3(0.017, 0.02, 0), Vector3(0, 0.25, 0), BLACK],
		["box", Vector3(0.07, 0.07, 0.052), Vector3(0, 0.09, 0), Color(0.1, 0.1, 0.1)],
	],
	"vodka": [
		["cyl", Vector3(0.04, 0.2, 0), Vector3(0, 0.1, 0), Color(0.85, 0.92, 0.95, 0.5), "glass"],
		["cyl", Vector3(0.014, 0.06, 0), Vector3(0, 0.23, 0), Color(0.85, 0.92, 0.95, 0.5), "glass"],
		["cyl", Vector3(0.016, 0.02, 0), Vector3(0, 0.27, 0), RED],
		["cyl", Vector3(0.041, 0.07, 0), Vector3(0, 0.1, 0), WHITE],
	],
	"cognac": [
		["cyl", Vector3(0.065, 0.13, 0), Vector3(0, 0.065, 0), Color(0.45, 0.2, 0.05, 0.85), "glass"],
		["cyl", Vector3(0.016, 0.07, 0), Vector3(0, 0.165, 0), Color(0.45, 0.2, 0.05, 0.85), "glass"],
		["cyl", Vector3(0.02, 0.03, 0), Vector3(0, 0.21, 0), Color(0.8, 0.65, 0.2), "metal"],
		["box", Vector3(0.06, 0.05, 0.132), Vector3(0, 0.07, 0), Color(0.85, 0.7, 0.3)],
	],
	"headphones": [
		["box", Vector3(0.17, 0.2, 0.07), Vector3(0, 0.1, 0), BLACK],
		["cyl", Vector3(0.045, 0.02, 0), Vector3(-0.04, 0.12, 0.036), Color(0.85, 0.85, 0.85)],
		["cyl", Vector3(0.045, 0.02, 0), Vector3(0.04, 0.12, 0.036), Color(0.85, 0.85, 0.85)],
	],
	"videogame": [
		["box", Vector3(0.12, 0.17, 0.016), Vector3(0, 0.085, 0), Color(0.1, 0.45, 0.2)],
		["box", Vector3(0.1, 0.12, 0.017), Vector3(0, 0.08, 0), Color(0.2, 0.15, 0.45)],
	],
	"watch": [
		["box", Vector3(0.1, 0.06, 0.1), Vector3(0, 0.03, 0), BLACK],
		["cyl", Vector3(0.025, 0.012, 0), Vector3(0, 0.066, 0), Color(0.8, 0.8, 0.82), "metal"],
		["box", Vector3(0.018, 0.004, 0.08), Vector3(0, 0.062, 0), Color(0.3, 0.2, 0.12)],
	],
	"smartphone": [
		["box", Vector3(0.1, 0.17, 0.035), Vector3(0, 0.085, 0), WHITE],
		["box", Vector3(0.065, 0.13, 0.036), Vector3(0, 0.085, 0), BLACK, "glass"],
	],
}

static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + id
	for part in RECIPES.get(id, []):
		var mesh: PrimitiveMesh
		var size: Vector3 = part[1]
		if part[0] == "cyl":
			var cyl := CylinderMesh.new()
			cyl.top_radius = size.x
			cyl.bottom_radius = size.x
			cyl.height = size.y
			cyl.radial_segments = 16
			mesh = cyl
		else:
			var box := BoxMesh.new()
			box.size = size
			mesh = box
		var mat := StandardMaterial3D.new()
		var color: Color = part[3]
		mat.albedo_color = color
		mat.roughness = 0.6
		var flags: Array = part.slice(4)
		if "glass" in flags:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.1
			mat.metallic_specular = 1.0
		if "metal" in flags:
			mat.metallic = 0.8
			mat.roughness = 0.3
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = part[2]
		root.add_child(mi)
	return root
