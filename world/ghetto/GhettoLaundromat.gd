extends Node3D
## THE LAUNDROMAT: the story's stash room and the place the warrant team hits. It is the EastJut building on
## Main Street (the one with the blue LAUNDROMAT sign, x 29.6..37.0, z -3.1..-16.0), made hollow and lived in:
##
##   front room   washers along the west wall, stacked dryers along the east, a folding table, benches, a
##                coin change machine, a notice board; flickering fluorescent tubes, a wet floor
##   back room    the stash room: steel shelves, boxes, a utility sink (the flush point), the back door onto
##                the service lane, the lot beyond it where the getaway car waits
##   outside      its ground floor is the walk-in front (doorway + two windows) so the room shows from the
##                street; a caged lamp over the back door; the crew's mark on the back wall
##
## It publishes the story's points as Node3Ds in group "ghetto_pt" (meta "pt": stash_a..d, sink, car) -- the
## story (fx/GhettoStory.gd) puts the bags, the SINK and GETAWAY markers there.
##
## raid(true) is the bust: a flash and smoke at the door, the tubes dying, red emergency lights, tape on both
## doors, evidence cones, flood lamps on the street and torch beams sweeping the rooms. raid(false) clears it.
## stash_pulse(on) lights the sign up while the story sends you in for the bags.

const Mat := preload("res://world/ghetto/GhettoMat.gd")
const Facades := preload("res://world/Facades.gd")
const TEX := "res://assets/ghetto/"
const POLY := "res://assets/polyhaven/%s/%s.gltf"
const SFX := "res://assets/sfx/"
const FONT := "res://assets/fonts/Bungee-Regular.ttf"

# The building's rect and its rooms.
const X0 := 29.6
const X1 := 37.0
const Z_FRONT := -3.1
const Z_BACK := -16.0
const T := 0.2
const CEIL := 3.0
const ROOF_Y := 9.6
const DOOR_X := 33.3
const DIV_Z := -10.2
const DIV_DOOR_X := 32.0
const BACK_DOOR_X := 35.2
## What the story is told: where each piece of the run is.
const POINTS := {
	"stash_a": Vector3(30.9, 0.0, -11.5), "stash_b": Vector3(30.7, 0.0, -14.1),
	"stash_c": Vector3(33.6, 0.0, -15.0), "stash_d": Vector3(33.3, 0.0, -12.0),
	"sink": Vector3(35.9, 0.0, -12.9),
	"car": Vector3(41.5, 0.0, -24.0),
}

var set_node: Node
var facades: Node
var interior: Node3D
var dressing: Node3D
var points: Dictionary = {}
var raid_on := false
var stash_on := false
var door_light: OmniLight3D
var sign_node: Node
var _lights: Array = []        # {l: Light3D, base: float, mode: int (0 steady 1 buzzing 2 dying), t: float, f: float}
var _emergency: Array = []
var _bust_nodes: Array[Node3D] = []
var _torches: Array[SpotLight3D] = []
var _smoke: GPUParticles3D
var _flash: OmniLight3D
var _flash_t := 0.0
var _back_leaf: Node3D
var _t := 0.0
var _mats := {}

func _ready() -> void:
	name = "Laundromat"
	interior = Node3D.new()
	interior.name = "Interior"
	add_child(interior)
	_open_building()
	_shell()
	_front_room()
	_back_room()
	_lane_side()
	_points()
	_ambience()

# --- materials ----------------------------------------------------------------------------

## A world-triplanar PBR from assets/pbr (`diff`/`nor`/`rough`), tinted; cached.
func _pbr(tex: String, tint: Color, per_m := 0.5, rough_k := 1.0, nor_k := 0.35) -> StandardMaterial3D:
	var key := "%s%s%s%s" % [tex, tint.to_html(), per_m, nor_k]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/pbr/%s_diff.jpg" % tex)
	if ResourceLoader.exists("res://assets/pbr/%s_nor.jpg" % tex):
		m.normal_enabled = true
		m.normal_texture = load("res://assets/pbr/%s_nor.jpg" % tex)
		m.normal_scale = nor_k
	if ResourceLoader.exists("res://assets/pbr/%s_rough.jpg" % tex):
		m.roughness_texture = load("res://assets/pbr/%s_rough.jpg" % tex)
	m.roughness = rough_k
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_m
	_mats[key] = m
	return m

func _box(parent: Node, size: Vector3, pos: Vector3, m: Material, yaw_deg := 0.0, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees.y = yaw_deg
	return mi

## A box from the min corner and the max corner (world), the common way these rooms are laid out.
func _slab(parent: Node, a: Vector3, b: Vector3, m: Material) -> MeshInstance3D:
	return _box(parent, (b - a).abs(), (a + b) * 0.5, m, 0.0, false)

func _cyl(parent: Node, r: float, h: float, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	return mi

func _solid(size: Vector3, pos: Vector3, parent: Node = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	var s := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	s.shape = bs
	b.add_child(s)
	(parent if parent else self).add_child(b)
	b.position = pos
	return b

func _model(path_name: String, parent: Node, pos: Vector3, yaw_deg := 0.0, sc := 1.0) -> Node3D:
	var path := POLY % [path_name, path_name]
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	n.scale = Vector3.ONE * sc
	return n

func _label(parent: Node, text: String, pos: Vector3, px: float, col: Color, yaw_deg := 0.0, shaded := false, size := 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	if ResourceLoader.exists(FONT):
		l.font = load(FONT)
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.shaded = shaded
	l.outline_size = 0
	parent.add_child(l)
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	return l

func _light(parent: Node, pos: Vector3, col: Color, energy: float, rng: float, mode := 0, fade := 45.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = fade
	l.distance_fade_length = 15.0
	parent.add_child(l)
	l.position = pos
	_lights.append({"l": l, "base": energy, "mode": mode, "t": randf() * 3.0, "f": 1.0})
	return l

## A decal on a vertical face: `normal` points out of the wall, `at` is on its face.
func _decal(tex_path: String, at: Vector3, size: Vector2, normal: Vector3, roll_deg := 0.0, mix := 1.0, tint := Color.WHITE, depth := 0.14) -> Decal:
	var d := Decal.new()
	if ResourceLoader.exists(tex_path):
		d.texture_albedo = load(tex_path)
	d.albedo_mix = mix
	d.modulate = tint
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	d.distance_fade_enabled = true
	d.distance_fade_begin = 40.0
	d.distance_fade_length = 15.0
	d.size = Vector3(size.x, depth, size.y)
	var down := Vector3.DOWN.rotated(normal, deg_to_rad(roll_deg))
	d.basis = Basis(normal.cross(down), normal, down)
	d.position = at - normal * (depth / 2.0 - 0.03)
	add_child(d)
	return d

func _floor_decal(tex_path: String, at: Vector3, size: Vector2, yaw_deg := 0.0, mix := 1.0, tint := Color.WHITE) -> Decal:
	var d := Decal.new()
	if ResourceLoader.exists(tex_path):
		d.texture_albedo = load(tex_path)
	d.albedo_mix = mix
	d.modulate = tint
	d.size = Vector3(size.x, 0.4, size.y)
	d.position = at + Vector3(0, 0.1, 0)
	d.rotation_degrees.y = yaw_deg
	d.distance_fade_enabled = true
	d.distance_fade_begin = 35.0
	d.distance_fade_length = 12.0
	add_child(d)
	return d

# --- the building: hollow it, rebuild the walls ----------------------------------------------

func _open_building() -> void:
	var city := get_parent().get("city") as Node3D if get_parent() else null
	if city == null:
		return
	facades = city.get_node_or_null("Facades")
	# The solid mass the street built here goes inert; the walls below are this room's own.
	var body := city.find_child("BuildingEastJut", true, false) as StaticBody3D
	if body:
		for c in body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
			elif c is OccluderInstance3D:
				c.free()
		body.collision_layer = 0
	# Its sign's painted-on door stands open now (a real doorway is cut in the front below).
	var door := city.find_child("EastJutDoor", true, false) as Node3D
	if door:
		door.visible = false
	if facades == null:
		return
	var front := facades.get_node_or_null("FrontEastJut")
	if front:
		for c in front.get_children().duplicate():
			var ground: bool = (c is MeshInstance3D and (c as Node3D).position.y < 2.5) or c.name in ["Glass", "Glow", "Shutter"]
			if ground:
				c.free()
		facades.call("_open_wall", front, X0, X1 - X0, "apt")
		facades.call("_storefront", front, X0, X1 - X0, true)
		# The painted glow and the roller shutter are not wanted: the room is really there.
		for nm in ["Shutter", "Glow"]:
			var old := front.get_node_or_null(nm)
			if old:
				old.free()
			var stub := Node3D.new()
			stub.name = nm
			front.add_child(stub)
	var mass := facades.get_node_or_null("MassEastJut") as MeshInstance3D
	if mass and mass.mesh and mass.mesh.get_surface_count() > 0:
		# Keep the gravel roof, drop the walls: they are rebuilt with a doorway to the lane in the back wall.
		var src := mass.mesh as ArrayMesh
		var last := src.get_surface_count() - 1
		var roof := ArrayMesh.new()
		roof.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(last))
		roof.surface_set_material(0, src.surface_get_material(last))
		mass.mesh = roof

func _shell() -> void:
	var brick: Material = facades.call("_mass_mat", "apt") if facades else _pbr("bricks_old", Color(0.62, 0.5, 0.44), 0.5)
	var plaster := _pbr("concrete_wall", Color(0.78, 0.74, 0.62), 0.45, 1.0, 0.12)
	var h := ROOF_Y - 0.0
	var skin := Node3D.new()
	skin.name = "Shell"
	add_child(skin)
	var gap0 := BACK_DOOR_X - 0.6
	var gap1 := BACK_DOOR_X + 0.6
	# Outer brick: west, east, the back wall with its doorway.
	_slab(skin, Vector3(X0, 0, Z_BACK), Vector3(X0 + T, h, Z_FRONT), brick)
	_slab(skin, Vector3(X1 - T, 0, Z_BACK), Vector3(X1, h, Z_FRONT), brick)
	_slab(skin, Vector3(X0 + T, 0, Z_BACK), Vector3(gap0, h, Z_BACK + T), brick)
	_slab(skin, Vector3(gap1, 0, Z_BACK), Vector3(X1 - T, h, Z_BACK + T), brick)
	_slab(skin, Vector3(gap0, 2.3, Z_BACK), Vector3(gap1, h, Z_BACK + T), brick)
	# The roofline's lip, as on the buildings either side (the front is the facade's own crown).
	var lip := _pbr("concrete_wall", Color(0.4, 0.38, 0.34), 0.5)
	_slab(skin, Vector3(X0, h, Z_BACK), Vector3(X1, h + 0.45, Z_BACK + 0.3), lip)
	_slab(skin, Vector3(X0, h, Z_BACK), Vector3(X0 + 0.3, h + 0.45, Z_FRONT), lip)
	_slab(skin, Vector3(X1 - 0.3, h, Z_BACK), Vector3(X1, h + 0.45, Z_FRONT), lip)
	# Inside: plaster, a darker teal wainscot, dirty skirting; the ceiling; the floor.
	var teal := _pbr("concrete_wall", Color(0.22, 0.4, 0.38), 0.45, 1.0, 0.12)
	var iz0 := Z_FRONT - 0.3
	var iz1 := Z_BACK + T
	var ix0 := X0 + T
	var ix1 := X1 - T
	var e := 0.012
	# plaster above the wainscot, the wainscot below (1.15 m); back wall pieces leave the doorway out.
	for band in [[0.0, 1.15, teal], [1.15, CEIL, plaster]]:
		var ya: float = band[0]
		var yb: float = band[1]
		var m: Material = band[2]
		_slab(interior, Vector3(ix0, ya, iz1), Vector3(ix0 + e, yb, iz0), m)
		_slab(interior, Vector3(ix1 - e, ya, iz1), Vector3(ix1, yb, iz0), m)
		_slab(interior, Vector3(ix0, ya, iz1), Vector3(gap0, yb, iz1 + e), m)
		_slab(interior, Vector3(gap1, ya, iz1), Vector3(ix1, yb, iz1 + e), m)
		# the divider, both faces, doorway left out
		for sd in [-1.0, 1.0]:
			var zz: float = DIV_Z + sd * (T / 2.0 + e)
			_slab(interior, Vector3(ix0, ya, zz), Vector3(DIV_DOOR_X - 0.6, yb, zz + e * sd), m)
			_slab(interior, Vector3(DIV_DOOR_X + 0.6, ya, zz), Vector3(ix1, yb, zz + e * sd), m)
	_slab(interior, Vector3(gap0, 2.3, iz1), Vector3(gap1, CEIL, iz1 + e), plaster)
	_slab(interior, Vector3(ix0, 0, DIV_Z - T / 2.0), Vector3(DIV_DOOR_X - 0.6, CEIL, DIV_Z + T / 2.0), plaster)
	_slab(interior, Vector3(DIV_DOOR_X + 0.6, 0, DIV_Z - T / 2.0), Vector3(ix1, CEIL, DIV_Z + T / 2.0), plaster)
	_slab(interior, Vector3(DIV_DOOR_X - 0.6, 2.25, DIV_Z - T / 2.0), Vector3(DIV_DOOR_X + 0.6, CEIL, DIV_Z + T / 2.0), plaster)
	# Ceiling slab (underside shows) and the floor: old checker tile, a wet patch by the machines.
	var ceil_m := _pbr("concrete_wall", Color(0.6, 0.57, 0.5), 0.4, 1.0, 0.1)
	_slab(interior, Vector3(ix0, CEIL, iz1), Vector3(ix1, CEIL + 0.1, iz0), ceil_m)
	var tile := _pbr("checker_tiles", Color(0.85, 0.85, 0.78), 0.7)
	_slab(interior, Vector3(ix0, 0.0, iz1), Vector3(ix1, 0.025, iz0), tile)
	# Grime on the floor and the wall: stains, scuffs, water.
	for p in [Vector3(31.2, 0, -6.0), Vector3(34.3, 0, -8.4), Vector3(32.4, 0, -4.4)]:
		_floor_decal("res://assets/decals/puddle.png", p, Vector2(2.4, 2.0), randf() * 360.0, 0.55, Color(0.7, 0.75, 0.8))
	for p in [Vector3(35.0, 0, -5.4), Vector3(30.8, 0, -9.4), Vector3(33.2, 0, -13.5)]:
		_floor_decal("res://assets/decals/crack.png", p, Vector2(1.8, 1.8), randf() * 360.0, 0.7, Color(0.1, 0.1, 0.1))
	# Colliders: the walls, the divider with its door, the ceiling's solid above, the front with its doorway.
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var cols := [
		[Vector3(X0, 0, Z_BACK), Vector3(X0 + T, ROOF_Y, Z_FRONT)],
		[Vector3(X1 - T, 0, Z_BACK), Vector3(X1, ROOF_Y, Z_FRONT)],
		[Vector3(X0 + T, 0, Z_BACK), Vector3(gap0, ROOF_Y, Z_BACK + T)],
		[Vector3(gap1, 0, Z_BACK), Vector3(X1 - T, ROOF_Y, Z_BACK + T)],
		[Vector3(gap0, 2.3, Z_BACK), Vector3(gap1, ROOF_Y, Z_BACK + T)],
		[Vector3(ix0, 0, DIV_Z - T / 2.0), Vector3(DIV_DOOR_X - 0.6, CEIL, DIV_Z + T / 2.0)],
		[Vector3(DIV_DOOR_X + 0.6, 0, DIV_Z - T / 2.0), Vector3(ix1, CEIL, DIV_Z + T / 2.0)],
		[Vector3(ix0, CEIL, iz1), Vector3(ix1, ROOF_Y, iz0)],
		# the front: either side of the doorway, the lintel above it
		[Vector3(X0, 0, Z_FRONT - 0.3), Vector3(DOOR_X - 0.7, ROOF_Y, Z_FRONT)],
		[Vector3(DOOR_X + 0.7, 0, Z_FRONT - 0.3), Vector3(X1, ROOF_Y, Z_FRONT)],
		[Vector3(DOOR_X - 0.7, 2.25, Z_FRONT - 0.3), Vector3(DOOR_X + 0.7, ROOF_Y, Z_FRONT)],
	]
	for c in cols:
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = (b - a).abs()
		cs.shape = bs
		body.add_child(cs)
		cs.position = (a + b) * 0.5
	# The street's occlusion over the solid above the ceiling (the hollow below is left open).
	var occ := OccluderInstance3D.new()
	var ob := BoxOccluder3D.new()
	ob.size = Vector3(X1 - X0 - 0.4, ROOF_Y - CEIL - 0.6, Z_FRONT - Z_BACK - 0.4)
	occ.occluder = ob
	add_child(occ)
	occ.position = Vector3((X0 + X1) / 2.0, CEIL + 0.4 + ob.size.y / 2.0, (Z_FRONT + Z_BACK) / 2.0)

# --- the machines ------------------------------------------------------------------------------

## A front-loading washer: faces +Z in its own frame. `n` varies the grime and which one is dead.
func _washer(parent: Node3D, pos: Vector3, yaw_deg: float, n: int) -> Node3D:
	var w := Node3D.new()
	w.name = "Washer%d" % n
	parent.add_child(w)
	w.position = pos
	w.rotation_degrees.y = yaw_deg
	var tone := 0.62 + 0.1 * float((n * 7) % 4) / 3.0
	var body := Mat.mat(Color(tone, tone + 0.01, tone - 0.02), 0.45, 0.2)
	var dark := Mat.mat(Color(0.12, 0.12, 0.13), 0.55, 0.2)
	var steel := Mat.mat(Color(0.74, 0.76, 0.78), 0.35, 0.45)
	_box(w, Vector3(0.68, 0.92, 0.66), Vector3(0, 0.46, 0), body)
	_box(w, Vector3(0.68, 0.14, 0.04), Vector3(0, 0.85, 0.32), dark)         # control strip
	_box(w, Vector3(0.7, 0.05, 0.68), Vector3(0, 0.945, 0), steel)            # top
	_box(w, Vector3(0.66, 0.06, 0.04), Vector3(0, 0.03, 0.31), dark)          # kick plate
	_cyl(w, 0.27, 0.07, Vector3(0, 0.46, 0.34), steel, Vector3(90, 0, 0))     # door ring
	var running := n % 3 == 0
	var glass := Mat.mat(Color(0.25, 0.4, 0.5, 0.55), 0.05, 0.1, 0.6 if running else 0.0)
	_cyl(w, 0.215, 0.05, Vector3(0, 0.46, 0.365), glass, Vector3(90, 0, 0))
	_cyl(w, 0.2, 0.03, Vector3(0, 0.46, 0.33), dark, Vector3(90, 0, 0))       # the drum's dark
	# coin slot, a status lamp: green when someone left it running, red on the dead ones
	_box(w, Vector3(0.05, 0.015, 0.01), Vector3(0.22, 0.86, 0.345), steel)
	var led := Mat.mat(Color(0.2, 1.0, 0.3) if running else Color(1.0, 0.15, 0.1), 0.4, 0.0, 2.2 if (running or n % 4 == 1) else 0.0)
	_box(w, Vector3(0.03, 0.03, 0.01), Vector3(-0.2, 0.86, 0.345), led)
	if n % 5 == 2:
		w.rotation_degrees.x = 0.0
		_box(w, Vector3(0.3, 0.02, 0.3), Vector3(0.0, 0.96, 0.0), Mat.mat(Color(0.6, 0.15, 0.1), 0.9))   # a towel left on top
	return w

func _dryer(parent: Node3D, pos: Vector3, yaw_deg: float, n: int, stacked: bool) -> Node3D:
	var d := Node3D.new()
	d.name = "Dryer%d" % n
	parent.add_child(d)
	d.position = pos
	d.rotation_degrees.y = yaw_deg
	var body := Mat.mat(Color(0.7, 0.71, 0.7), 0.4, 0.3)
	var dark := Mat.mat(Color(0.06, 0.06, 0.07), 0.5, 0.4)
	var steel := Mat.mat(Color(0.76, 0.78, 0.8), 0.35, 0.45)
	for k in (2 if stacked else 1):
		var y := 0.0 + k * 0.98
		_box(d, Vector3(0.74, 0.96, 0.72), Vector3(0, y + 0.48, 0), body)
		_box(d, Vector3(0.74, 0.12, 0.04), Vector3(0, y + 0.88, 0.35), dark)
		_cyl(d, 0.26, 0.07, Vector3(0, y + 0.46, 0.37), steel, Vector3(90, 0, 0))
		var lit := Mat.mat(Color(0.9, 0.55, 0.2, 0.55), 0.05, 0.1, 0.5 if (n + k) % 3 == 0 else 0.0)
		_cyl(d, 0.2, 0.05, Vector3(0, y + 0.46, 0.4), lit, Vector3(90, 0, 0))
		_box(d, Vector3(0.05, 0.02, 0.01), Vector3(0.25, y + 0.88, 0.375), steel)
		_box(d, Vector3(0.04, 0.03, 0.01), Vector3(-0.25, y + 0.88, 0.375), Mat.mat(Color(1.0, 0.4, 0.1), 0.4, 0.0, 2.0 if (n + k) % 2 == 0 else 0.0))
	return d

func _front_room() -> void:
	var m := Node3D.new()
	m.name = "Machines"
	interior.add_child(m)
	# Washers on the west wall, facing east; back to back with nothing: the wall is theirs.
	var zs := [-4.6, -5.4, -6.2, -7.0, -7.8, -8.6, -9.4]
	for i in zs.size():
		_washer(m, Vector3(X0 + T + 0.34, 0.0, zs[i]), 90.0, i)
	_solid(Vector3(0.7, 1.0, 5.6), Vector3(X0 + T + 0.35, 0.5, -7.0), m)
	# A second row of washers back to back down the middle: the island.
	for i in 4:
		_washer(m, Vector3(32.0, 0.0, -4.5 - i * 0.7 - 0.0), 0.0, 10 + i)
	# Dryers (stacked pairs) on the east wall, facing west.
	for i in 4:
		_dryer(m, Vector3(X1 - T - 0.38, 0.0, -4.9 - i * 0.82), -90.0, i, true)
	_solid(Vector3(0.8, 1.95, 3.4), Vector3(X1 - T - 0.4, 0.97, -6.5), m)
	_solid(Vector3(0.8, 0.9, 3.0), Vector3(32.0, 0.45, -5.9), m)
	# The folding table and two benches.
	var table := _model("painted_wooden_table", m, Vector3(34.0, 0, -8.6), 90.0, 0.7)
	if table == null:
		_box(m, Vector3(1.4, 0.06, 0.7), Vector3(34.0, 0.78, -8.6), Mat.mat(Color(0.45, 0.36, 0.28)), 90.0)
	_solid(Vector3(0.9, 0.8, 1.8), Vector3(34.0, 0.4, -8.6), m)
	for z in [-9.4, -7.8]:
		var bench := _model("painted_wooden_bench", m, Vector3(35.3, 0, z), 90.0, 0.9)
		if bench == null:
			_box(m, Vector3(0.4, 0.45, 1.2), Vector3(35.3, 0.22, z), Mat.mat(Color(0.3, 0.25, 0.2)))
	# Plastic chairs in a row by the window, one tipped.
	for i in 3:
		var c := _model("plastic_monobloc_chair_01", m, Vector3(30.7, 0, -3.9 + 0.0 * i), 0.0, 1.0)
		if c:
			c.position = Vector3(30.55 + i * 0.55, 0, -3.8)
			c.rotation_degrees = Vector3(0, 180.0 + i * 6.0, 0 if i != 2 else 78.0)
			if i == 2:
				c.position.y = 0.2
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = Mat.mat(Color(0.18, 0.3, 0.42), 0.6)
	# The change machine and the soap vending box by the door.
	var chg := Node3D.new()
	chg.name = "ChangeMachine"
	m.add_child(chg)
	chg.position = Vector3(35.9, 0, -4.2)
	chg.rotation_degrees.y = -90.0
	_box(chg, Vector3(0.7, 1.7, 0.5), Vector3(0, 0.85, 0), Mat.mat(Color(0.6, 0.12, 0.1), 0.45, 0.3))
	_box(chg, Vector3(0.4, 0.5, 0.02), Vector3(0, 1.3, 0.26), Mat.mat(Color(0.05, 0.05, 0.06), 0.3, 0.3))
	_box(chg, Vector3(0.14, 0.03, 0.02), Vector3(0.18, 0.95, 0.26), Mat.mat(Color(0.8, 0.8, 0.8), 0.3, 0.9))
	_label(chg, "CHANGE", Vector3(0, 1.55, 0.26), 0.003, Color(1.0, 0.85, 0.3), 0.0, false, 56)
	_solid(Vector3(0.8, 1.7, 0.8), Vector3(35.9, 0.85, -4.2), m)
	# The notice board and the clock, a fire alarm.
	var board := _box(m, Vector3(1.0, 0.7, 0.03), Vector3(X0 + T + 0.02, 1.7, -6.2), Mat.mat(Color(0.45, 0.32, 0.2), 0.9), 90.0)
	for i in 5:
		var note := _box(m, Vector3(0.14, 0.18, 0.005), Vector3(X0 + T + 0.045, 1.7 + randf_range(-0.2, 0.2), -6.2 + randf_range(-0.38, 0.38)), Mat.mat(Color(0.85, 0.82, 0.7), 0.95), 90.0)
		note.rotation_degrees.x = randf_range(-8, 8)
	_model("wall_clock", m, Vector3(35.0, 2.35, iz_front_inner() - 0.0), 0.0, 1.0)
	_model("WetFloorSign_01", m, Vector3(33.4, 0, -4.4), 18.0, 1.0)
	# Light: fluorescents in the ceiling (the model, and the glow it sheds), two of them going bad.
	var tubes := [[31.2, -5.0, 0], [34.0, -5.0, 1], [32.6, -8.4, 2], [35.0, -8.6, 0]]
	for t in tubes:
		var fx := _model("mounted_fluorescent_lights", interior, Vector3(t[0], CEIL - 0.02, t[1]), 0.0, 1.0)
		if fx == null:
			_box(interior, Vector3(1.2, 0.05, 0.2), Vector3(t[0], CEIL - 0.05, t[1]), Mat.mat(Color(0.9, 0.95, 1.0), 0.3, 0.0, 1.8), 0.0, false)
		_light(interior, Vector3(t[0], CEIL - 0.3, t[1]), Color(0.82, 0.93, 1.0), 1.35, 6.2, int(t[2]))
	# A hanging dead one, its tube swinging on a wire.
	_box(interior, Vector3(1.2, 0.04, 0.16), Vector3(33.2, CEIL - 0.22, -6.7), Mat.mat(Color(0.2, 0.2, 0.18), 0.6), 14.0).rotation_degrees.z = 9.0
	# Laundry: a basket spilled by the dryers, a bag on a machine, a cloth on the floor.
	for i in 6:
		_box(interior, Vector3(0.28, 0.07, 0.2), Vector3(35.2 + randf_range(-0.3, 0.3), 0.04 + 0.05 * (i % 3), -5.6 + randf_range(-0.3, 0.3)),
			Mat.mat(Color.from_hsv(randf(), 0.2, 0.45), 0.95), randf_range(0, 360))
	_model("cardboard_box_01", interior, Vector3(35.4, 0, -10.0), 20.0, 1.0)

func iz_front_inner() -> float:
	return Z_FRONT - 0.28

# --- the back room: the stash --------------------------------------------------------------------

func _back_room() -> void:
	var r := Node3D.new()
	r.name = "BackRoom"
	interior.add_child(r)
	# Shelves with product boxes along the west wall, a rack and crates.
	for z in [-11.5, -12.55, -13.6]:
		var sh := _model("steel_frame_shelves_01", r, Vector3(X0 + T + 0.3, 0, z), 90.0, 0.09)
		if sh == null:
			_box(r, Vector3(0.5, 1.8, 1.2), Vector3(X0 + T + 0.3, 0.9, z), Mat.mat(Color(0.3, 0.3, 0.32), 0.5, 0.6))
	_solid(Vector3(0.5, 2.0, 3.2), Vector3(X0 + T + 0.3, 1.0, -12.55), r)
	for i in 12:
		_model("cardboard_box_01", r, Vector3(X0 + T + 0.3, 0.12 + (i % 4) * 0.5, -11.15 - (i / 4) * 1.05 - (i % 2) * 0.4), 90.0 + randf_range(-8, 8), 1.0)
	# Detergent drums and boxes in the corner, the stash's table with the scale.
	for i in 3:
		_cyl(r, 0.22, 0.55, Vector3(X0 + T + 0.5 + i * 0.5, 0.275, -15.4), Mat.mat([Color(0.1, 0.25, 0.6), Color(0.7, 0.15, 0.1), Color(0.15, 0.4, 0.2)][i], 0.55))
	_model("cardboard_box_01", r, Vector3(33.0, 0, -15.3), -10.0, 1.0)
	_model("cardboard_box_01", r, Vector3(33.0, 0.5, -15.3), 18.0, 0.8)
	_solid(Vector3(1.4, 1.2, 0.8), Vector3(33.2, 0.6, -15.3), r)
	var tbl := _model("metal_office_desk", r, Vector3(33.3, 0, -12.0), 0.0, 1.0)
	if tbl == null:
		_box(r, Vector3(1.4, 0.05, 0.7), Vector3(33.3, 0.76, -12.0), Mat.mat(Color(0.3, 0.3, 0.32), 0.5, 0.6))
	_solid(Vector3(1.5, 0.8, 0.8), Vector3(33.3, 0.4, -12.0), r)
	# The utility sink on the east wall: a deep steel basin, a tap, a drain pipe, a bucket under.
	var sink := Node3D.new()
	sink.name = "UtilitySink"
	r.add_child(sink)
	sink.position = Vector3(X1 - T - 0.3, 0, -12.9)
	sink.rotation_degrees.y = -90.0
	var steel := Mat.mat(Color(0.74, 0.76, 0.78), 0.35, 0.45)
	var dirty := Mat.mat(Color(0.25, 0.27, 0.26), 0.7, 0.4)
	_box(sink, Vector3(1.0, 0.1, 0.6), Vector3(0, 0.86, 0), steel)
	_box(sink, Vector3(0.9, 0.3, 0.04), Vector3(0, 1.0, -0.28), steel)
	_box(sink, Vector3(0.9, 0.2, 0.04), Vector3(0, 0.74, 0.28), steel)
	_box(sink, Vector3(0.04, 0.2, 0.5), Vector3(0.45, 0.74, 0), steel)
	_box(sink, Vector3(0.04, 0.2, 0.5), Vector3(-0.45, 0.74, 0), steel)
	_box(sink, Vector3(0.9, 0.04, 0.5), Vector3(0, 0.64, 0), dirty)
	_cyl(sink, 0.02, 0.35, Vector3(0.0, 1.15, -0.24), steel, Vector3(0, 0, 0))
	_cyl(sink, 0.015, 0.2, Vector3(0.0, 1.3, -0.14), steel, Vector3(90, 0, 0))
	_cyl(sink, 0.03, 0.75, Vector3(-0.4, 0.32, -0.25), dirty)
	_box(sink, Vector3(0.9, 0.7, 0.55), Vector3(0, 0.32, 0.0), Mat.mat(Color(0.2, 0.2, 0.21), 0.8, 0.3))
	_solid(Vector3(0.8, 1.3, 1.1), Vector3(X1 - T - 0.3, 0.65, -12.9), r)
	_cyl(r, 0.18, 0.3, Vector3(X1 - T - 0.5, 0.15, -11.7), Mat.mat(Color(0.8, 0.7, 0.1), 0.5))   # a mop bucket
	# The back room's own light: a caged bulb on a cord, dim and swinging; the exit sign over the door.
	_cyl(r, 0.006, 0.45, Vector3(33.0, CEIL - 0.22, -12.8), Mat.mat(Color(0.05, 0.05, 0.05), 0.8))
	_cyl(r, 0.06, 0.12, Vector3(33.0, CEIL - 0.48, -12.8), Mat.mat(Color(1.0, 0.82, 0.5), 0.3, 0.0, 3.0))
	_light(r, Vector3(33.0, CEIL - 0.55, -12.8), Color(1.0, 0.82, 0.55), 1.55, 6.0, 1)
	_light(r, Vector3(35.4, CEIL - 0.4, -14.6), Color(0.8, 0.9, 1.0), 0.85, 4.5, 2)
	var exit_sign := _box(r, Vector3(0.5, 0.18, 0.05), Vector3(BACK_DOOR_X, 2.52, Z_BACK + T + 0.04), Mat.mat(Color(0.9, 0.08, 0.06), 0.4, 0.0, 3.0), 0.0, false)
	exit_sign.name = "ExitSign"
	_label(r, "EXIT", Vector3(BACK_DOOR_X, 2.52, Z_BACK + T + 0.07), 0.0028, Color(1, 0.9, 0.9), 0.0, false, 64)
	# A mark on the plaster: the crew's crown, sprayed over a notice.
	_decal(TEX + "tag_kings_crown.png", Vector3(31.0, 1.9, DIV_Z + T / 2.0 + 0.02), Vector2(1.1, 1.1), Vector3.BACK, 4.0, 1.0, Color(1, 1, 1, 0.85))
	# The back door itself: a steel leaf standing open.
	_back_leaf = Node3D.new()
	_back_leaf.name = "BackDoor"
	add_child(_back_leaf)
	_back_leaf.position = Vector3(BACK_DOOR_X - 0.6, 0.0, Z_BACK + 0.1)
	_back_leaf.rotation_degrees.y = -100.0
	var leaf := _box(_back_leaf, Vector3(1.2, 2.3, 0.06), Vector3(0.6, 1.15, 0), Mat.mat(Color(0.18, 0.2, 0.22), 0.5, 0.6))
	_box(_back_leaf, Vector3(0.14, 0.05, 0.08), Vector3(1.0, 1.05, 0.05), Mat.mat(Color(0.7, 0.7, 0.72), 0.3, 0.9))
	leaf.name = "Leaf"

# --- the lane side ---------------------------------------------------------------------------------

func _lane_side() -> void:
	var lane := Node3D.new()
	lane.name = "LaneSide"
	add_child(lane)
	# A caged wall lamp over the back door: the lane's one light, a warm sodium pool on the brick.
	var lamp_pos := Vector3(BACK_DOOR_X, 2.75, Z_BACK - 0.25)
	if _model("industrial_wall_lamp", lane, lamp_pos, 180.0, 1.0) == null:
		_box(lane, Vector3(0.2, 0.2, 0.3), lamp_pos, Mat.mat(Color(0.1, 0.1, 0.1), 0.6, 0.4))
	_cyl(lane, 0.07, 0.1, lamp_pos + Vector3(0, -0.12, -0.05), Mat.mat(Color(1.0, 0.75, 0.4), 0.3, 0.0, 3.5))
	_light(lane, lamp_pos + Vector3(0, -0.4, -0.7), Color(1.0, 0.7, 0.38), 2.2, 8.5, 1)
	# Bins, boxes and a stack of crates against the wall, a drain pipe, grime.
	_model("metal_trash_can", lane, Vector3(32.0, 0, Z_BACK - 0.45), 20.0, 1.1)
	_model("metal_trash_can", lane, Vector3(32.7, 0, Z_BACK - 0.5), -35.0, 1.1)
	_model("trashbag", lane, Vector3(31.4, 0, Z_BACK - 0.6), 70.0, 1.0)
	_model("trashbag", lane, Vector3(31.0, 0, Z_BACK - 0.9), 10.0, 1.0)
	_model("cardboard_box_01", lane, Vector3(36.4, 0, Z_BACK - 0.5), 24.0, 1.0)
	_cyl(lane, 0.05, 6.0, Vector3(30.0, 3.0, Z_BACK - 0.06), Mat.mat(Color(0.22, 0.2, 0.18), 0.6, 0.5))
	_decal(TEX + "tag_kings_word.png", Vector3(31.6, 1.7, Z_BACK), Vector2(2.1, 0.8), Vector3.FORWARD, -3.0, 1.0)
	# The lane's pavement under the back door's glow gets a wet sheen.
	_floor_decal("res://assets/decals/puddle.png", Vector3(34.5, 0, Z_BACK - 1.6), Vector2(4.5, 2.6), 20.0, 0.55, Color(0.6, 0.65, 0.7))
	# The front: a hand-painted window sign and the neon OPEN, the crew's mark by the door.
	var win := Node3D.new()
	win.name = "WindowSigns"
	add_child(win)
	_label(win, "WASH  DRY  FOLD", Vector3(31.2, 1.75, Z_FRONT - 0.045), 0.0042, Color(0.95, 0.9, 0.8), 0.0, false, 56)
	_label(win, "24 HRS", Vector3(35.4, 1.75, Z_FRONT - 0.045), 0.0042, Color(0.95, 0.9, 0.8), 0.0, false, 56)
	sign_node = _label(win, "OPEN", Vector3(35.4, 1.28, Z_FRONT - 0.05), 0.0055, Color(1.0, 0.25, 0.2) * 2.2, 0.0, false, 72)
	# Window glass facing the street gets a light from the room: the sill and the sidewalk glow.
	door_light = _light(self, Vector3(DOOR_X, 2.1, Z_FRONT + 0.7), Color(0.78, 0.9, 1.0), 1.0, 5.5, 0)
	# Smashed pane, the shards on the sill; the crew's mark by the door.
	_decal(TEX + "window_smash.png", Vector3(31.4, 1.45, Z_FRONT + 0.0), Vector2(1.5, 1.5), Vector3.BACK, 4.0)
	_decal(TEX + "tag_kings_crown.png", Vector3(36.1, 2.0, Z_FRONT + 0.0), Vector2(0.9, 0.9), Vector3.BACK, -5.0)
	_floor_decal(TEX + "glass_shards.png", Vector3(31.4, 0, Z_FRONT + 0.6), Vector2(2.4, 1.4), 0.0)

# --- the story's points --------------------------------------------------------------------------

func _points() -> void:
	for k in POINTS:
		var n := Node3D.new()
		n.name = "Pt_" + k
		n.add_to_group("ghetto_pt")
		n.set_meta("pt", k)
		add_child(n)
		n.global_position = POINTS[k]
		points[k] = n

func point(name_: String) -> Vector3:
	return POINTS[name_] if POINTS.has(name_) else Vector3.ZERO

func front_door() -> Vector3:
	return Vector3(DOOR_X, 0.0, Z_FRONT + 0.4)

func back_door() -> Vector3:
	return Vector3(BACK_DOOR_X, 0.0, Z_BACK - 0.4)

# --- sound ---------------------------------------------------------------------------------------

func _ambience() -> void:
	Mat.loop_player(interior, SFX + "fluorescent_hum_loop.wav", Vector3(33.0, 2.6, -6.0), -9.0, 16.0, 4.0)
	Mat.loop_player(interior, SFX + "cooler_hum_loop.wav", Vector3(31.0, 0.6, -7.0), -12.0, 10.0, 3.0)
	Mat.loop_player(interior, SFX + "bulb_buzz_loop.wav", Vector3(33.0, 2.5, -12.8), -12.0, 10.0, 3.0)

# --- the raid --------------------------------------------------------------------------------------

## The bust: flash and smoke at the door, the room's tubes dying, red emergency lights, tape, cones, flood lamps.
func raid(on: bool) -> void:
	if on == raid_on:
		return
	raid_on = on
	if on:
		_build_dressing()
	if dressing:
		dressing.visible = on
	for e in _emergency:
		(e as Node3D).visible = on
	for t in _torches:
		t.visible = on
	if _smoke:
		_smoke.emitting = on
	if _back_leaf:
		var tw := create_tween()
		tw.tween_property(_back_leaf, "rotation_degrees:y", -160.0 if on else -100.0, 0.25).set_trans(Tween.TRANS_BACK)
	if on:
		_flash_t = 0.45
		if set_node and set_node.has_method("_sound"):
			set_node.call("_sound", "res://assets/sfx/door.wav", Vector3(DOOR_X, 1.0, Z_FRONT), 6.0, 0.7, 70.0)

func _build_dressing() -> void:
	if dressing:
		return
	dressing = Node3D.new()
	dressing.name = "BustDressing"
	add_child(dressing)
	var tape := load(TEX + "tape_police.png") as Texture2D
	var tm := StandardMaterial3D.new()
	tm.albedo_texture = tape
	tm.uv1_scale = Vector3(3.0, 1.0, 1.0)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.roughness = 0.7
	# Tape across the front doorway and the back door, a strip over the broken pane.
	for spec in [[Vector3(DOOR_X, 1.0, Z_FRONT + 0.15), 1.5, 0.0, 12.0], [Vector3(DOOR_X, 1.45, Z_FRONT + 0.15), 1.5, 0.0, -9.0],
			[Vector3(BACK_DOOR_X, 1.0, Z_BACK - 0.15), 1.4, 180.0, 8.0], [Vector3(BACK_DOOR_X, 1.5, Z_BACK - 0.15), 1.4, 180.0, -10.0],
			[Vector3(31.4, 1.2, Z_FRONT + 0.1), 1.8, 0.0, 28.0]]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(float(spec[1]), 0.1)
		q.mesh = qm
		q.material_override = tm
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dressing.add_child(q)
		q.position = spec[0]
		q.rotation_degrees = Vector3(0, float(spec[2]), float(spec[3]))
	# Evidence cones with numbers, on the floor of both rooms.
	var cone_m := Mat.mat(Color(1.0, 0.82, 0.08), 0.5, 0.0, 0.4)
	for i in 6:
		var p := [Vector3(31.0, 0, -5.6), Vector3(34.6, 0, -6.4), Vector3(33.3, 0, -9.4), Vector3(30.9, 0, -11.9), Vector3(33.6, 0, -13.4), Vector3(35.4, 0, -11.2)][i] as Vector3
		var c := MeshInstance3D.new()
		var cm := PrismMesh.new()
		cm.size = Vector3(0.14, 0.1, 0.14)
		c.mesh = cm
		c.material_override = cone_m
		dressing.add_child(c)
		c.position = p + Vector3(0, 0.06, 0)
		_label(dressing, str(i + 1), p + Vector3(0, 0.07, 0.075), 0.0028, Color(0.05, 0.05, 0.05), 0.0, false, 40)
	# Things the team left: a machine pulled out and open, towels everywhere, a dropped torch glow.
	var ws := _washer(dressing, Vector3(31.45, 0.0, -7.2), 40.0, 21)
	ws.position.x = 31.2
	for i in 10:
		_box(dressing, Vector3(0.34, 0.05, 0.24), Vector3(32.4 + randf_range(-1.6, 1.6), 0.04 + 0.04 * (i % 2), -7.8 + randf_range(-2.0, 2.0)),
			Mat.mat(Color.from_hsv(randf(), 0.25, 0.5), 0.95), randf_range(0, 360), false)
	# Flood lamps on tripods in the street, throwing white onto the front and the doorway.
	for fx in [31.6, 35.2]:
		var tri := Node3D.new()
		tri.name = "FloodLamp"
		dressing.add_child(tri)
		tri.position = Vector3(fx, 0, 0.2 + (0.5 if fx > 33 else -0.1))
		var leg := Mat.mat(Color(0.12, 0.12, 0.13), 0.5, 0.6)
		for a in [0.0, 120.0, 240.0]:
			var lg := _cyl(tri, 0.012, 1.6, Vector3(0.28 * sin(deg_to_rad(a)), 0.78, 0.28 * cos(deg_to_rad(a))), leg)
			lg.rotation_degrees = Vector3(-12.0 * cos(deg_to_rad(a)), 0, 12.0 * sin(deg_to_rad(a)))
		_cyl(tri, 0.02, 0.5, Vector3(0, 1.7, 0), leg)
		var head := _box(tri, Vector3(0.5, 0.35, 0.18), Vector3(0, 2.0, 0.0), Mat.mat(Color(0.2, 0.2, 0.22), 0.5, 0.5))
		head.rotation_degrees = Vector3(0, 180.0, 0)
		_box(tri, Vector3(0.44, 0.28, 0.02), Vector3(0, 2.0, -0.095), Mat.mat(Color(1.0, 0.97, 0.9), 0.2, 0.0, 6.0))
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.97, 0.9)
		sp.light_energy = 7.0
		sp.spot_range = 14.0
		sp.spot_angle = 38.0
		sp.shadow_enabled = false
		tri.add_child(sp)
		sp.position = Vector3(0, 2.0, -0.12)
		sp.look_at_from_position(sp.global_position, Vector3(DOOR_X, 1.2, Z_FRONT), Vector3.UP)
		_emergency.append(sp)
	# The interior goes red: emergency strobes on the ceiling.
	for p in [Vector3(32.0, CEIL - 0.3, -5.2), Vector3(34.5, CEIL - 0.3, -8.5), Vector3(32.8, CEIL - 0.3, -13.0)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.1, 0.06)
		l.light_energy = 1.8
		l.omni_range = 6.0
		l.shadow_enabled = false
		dressing.add_child(l)
		l.position = p
		_emergency.append(l)
	# Torch beams: two of the team inside, sweeping.
	for i in 2:
		var s := SpotLight3D.new()
		s.light_color = Color(0.95, 0.97, 1.0)
		s.light_energy = 4.0
		s.spot_range = 9.0
		s.spot_angle = 22.0
		s.shadow_enabled = false
		dressing.add_child(s)
		s.position = Vector3(32.0 + i * 2.6, 1.5, -6.0 - i * 5.5)
		_torches.append(s)
	# Smoke rolling out of the doorway after the flash: grey, thick, low.
	_smoke = GPUParticles3D.new()
	_smoke.name = "DoorSmoke"
	_smoke.amount = 20
	_smoke.lifetime = 4.5
	_smoke.local_coords = false
	_smoke.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.2, 1.0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0.0, 0.25, 0.0)
	pm.scale_min = 1.4
	pm.scale_max = 2.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.9, 0.2)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.18, Color(1, 1, 1, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	_smoke.process_material = pm
	var sq := QuadMesh.new()
	sq.size = Vector2(1.5, 1.5)
	sq.material = set_node.call("smoke_material") if set_node else null
	_smoke.draw_pass_1 = sq
	add_child(_smoke)
	_smoke.global_position = Vector3(DOOR_X, 1.1, Z_FRONT + 0.3)
	# The flash itself.
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.98, 0.92)
	_flash.light_energy = 0.0
	_flash.omni_range = 18.0
	_flash.shadow_enabled = false
	add_child(_flash)
	_flash.global_position = Vector3(DOOR_X, 1.6, Z_FRONT + 1.0)
	_bust_nodes.append(dressing)

## The story sends you in for the bags: the sign pulses and the doorway is lit.
func stash_pulse(on: bool) -> void:
	stash_on = on

# --- frame -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	for d in _lights:
		var l := d["l"] as Light3D
		if not is_instance_valid(l):
			continue
		d["t"] -= delta
		if d["t"] <= 0.0:
			match int(d["mode"]):
				0:
					d["t"] = randf_range(0.5, 2.0)
					d["f"] = randf_range(0.95, 1.0)
				1:
					d["t"] = randf_range(0.03, 0.12)
					d["f"] = randf_range(0.55, 1.05)
				_:
					d["t"] = randf_range(0.03, 0.4)
					d["f"] = 0.0 if randf() < 0.55 else randf_range(0.2, 1.0)
		var k: float = d["f"]
		if raid_on and (l.get_parent() == interior or l == door_light):
			k *= 0.35
		l.light_energy = float(d["base"]) * k
	if raid_on:
		var ph := fposmod(_t * 1.6, 1.0)
		for e in _emergency:
			if e is OmniLight3D:
				(e as OmniLight3D).light_energy = 2.6 * (0.2 + 0.8 * absf(sin((_t * 3.0) + float(e.get_instance_id() % 7))))
		for i in _torches.size():
			var s := _torches[i]
			s.rotation_degrees = Vector3(-8.0 + 6.0 * sin(_t * 1.1 + i), 180.0 * float(i) + 60.0 * sin(_t * 0.7 + i * 2.0), 0.0)
	if _flash and _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		_flash.light_energy = 40.0 * (_flash_t / 0.45) * (_flash_t / 0.45)
	if sign_node and sign_node is Label3D:
		var pulse := 1.0
		if stash_on:
			pulse = 0.6 + 0.4 * sin(_t * 5.0)
		(sign_node as Label3D).modulate = Color(1.0, 0.25, 0.2) * (2.2 * pulse)
