extends RefCounted
## Dresses the flat for the eye-level camera. The room was lit for the top-down view (one bare bulb, one blue
## shaft, a black window), which from standing height is a lit brick patch in a void. This adds the lights a
## real junkie flat at night has, each with a source you can see: street light through the blinds, a floor lamp,
## the hallway under the door and the stove ring (emissive, no light of their own), the TV and the laptop
## (already there). Only two lights are added, unshadowed: on a UHD 620 a light costs about 0.5 ms however
## small it is, and the room had to look this way without costing more than it did.
## Also: skirting, a door frame, a rug, a stove and a bookcase (Poly Haven, CC0).

## What the room reads as in the dark before any lamp: a faint cold bounce off the street, not black.
const AMBIENT_COLOR := Color(0.46, 0.5, 0.64)
const AMBIENT_ENERGY := 0.85

const STREET := Color(0.55, 0.68, 1.0)
const LAMP := Color(1.0, 0.7, 0.38)
const HALL := Color(1.0, 0.62, 0.28)

static func apply(room: Node3D) -> void:
	# DOPESICK_NO_DRESS=1 leaves it out, for before/after perf comparisons.
	if room.get_node_or_null("Dressing") != null or OS.has_environment("DOPESICK_NO_DRESS"):
		return
	var d := Node3D.new()
	d.name = "Dressing"
	room.add_child(d)
	_ambient(room)
	_windows(room, d)
	_lamp(d, Vector3(-2.9, 0.0, -3.05))
	_door(room, d)
	_skirting(d)
	_rug(d, Vector3(0.2, 0.0, 0.1))
	_stove(d, Vector3(0.1, 0.0, -3.17))
	_bookcase(d, Vector3(-4.77, 0.0, -0.2))

## Fills the dark a little, from the room's own environment (shared by every preset).
static func _ambient(room: Node3D) -> void:
	var we := room.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY

static func _mat(color: Color, rough := 0.85, emit := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m

static func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## An unshadowed light with a reach that survives Graphics' Low preset trimming it to 70 percent.
static func _light(parent: Node, pos: Vector3, color: Color, energy: float, reach: float, nm: String) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = nm
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.light_specular = 0.0
	parent.add_child(l)
	return l

## A kit model scaled and centred on its footprint, so `pos` is where it stands and `yaw` is where its front looks.
static func _model(parent: Node, path: String, pos: Vector3, yaw: float, scale: float, tint := Color.WHITE) -> Node3D:
	var res: PackedScene = load(path)
	if res == null:
		return null
	var wrap := Node3D.new()
	wrap.position = pos
	wrap.rotation.y = yaw
	var inst := res.instantiate() as Node3D
	var bb := AABB()
	var first := true
	for mesh in inst.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mesh as MeshInstance3D).transform * (mesh as MeshInstance3D).get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	inst.scale = Vector3.ONE * scale
	inst.position = Vector3(-(bb.position.x + bb.size.x * 0.5), 0.0, -(bb.position.z + bb.size.z * 0.5)) * scale
	wrap.add_child(inst)
	parent.add_child(wrap)
	if tint != Color.WHITE:
		for mesh in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s)
				if src is StandardMaterial3D:
					var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					m.albedo_color *= tint
					mi.set_surface_override_material(s, m)
	return wrap

static func _solid(parent: Node, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

# --- Street light through the blinds ---------------------------------------------------------

## Slats of light: bright lines with dark gaps, so a window reads as a window with blinds and the
## city behind it rather than a black rectangle.
static func _blinds_texture() -> ImageTexture:
	var img := Image.create(4, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		var slat := y % 4
		var v := 0.05 if slat == 3 else (0.55 + 0.45 * (1.0 - float(y) / 32.0)) * (0.7 if slat == 0 else 1.0)
		for x in 4:
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

static func _windows(room: Node3D, d: Node3D) -> void:
	var tex := _blinds_texture()
	var opening := room.get_node_or_null("BoardedWindow/Opening") as MeshInstance3D
	if opening:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.11, 0.14)
		m.emission_enabled = true
		m.emission = STREET
		m.emission_texture = tex
		m.emission_energy_multiplier = 1.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		opening.material_override = m
	# The foil-covered one: dull crinkled foil with the street coming round its taped edges.
	var foil := room.get_node_or_null("FoilWindow") as MeshInstance3D
	if foil:
		var f := _mat(Color(0.13, 0.13, 0.14), 0.9, Color(0.4, 0.5, 0.7), 0.06)
		f.metallic = 0.0
		foil.material_override = f
	# One light stands for both windows (every light costs what it covers on screen, and this is a laptop's GPU).
	_light(d, Vector3(0.1, 1.6, -2.6), STREET, 1.3, 5.5, "StreetFill")

# --- The lamp ---------------------------------------------------------------------------------

## A cheap floor lamp by the bed: pole, base, a shade that glows. The one warm thing in the cold.
static func _lamp(d: Node3D, at: Vector3) -> void:
	var g := Node3D.new()
	g.name = "FloorLamp"
	g.position = at
	d.add_child(g)
	var dark := _mat(Color(0.08, 0.075, 0.07), 0.5)
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.16
	bc.bottom_radius = 0.18
	bc.height = 0.04
	bc.material = dark
	base.mesh = bc
	base.position.y = 0.02
	g.add_child(base)
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.014
	pc.bottom_radius = 0.014
	pc.height = 1.35
	pc.material = dark
	pole.mesh = pc
	pole.position.y = 0.7
	g.add_child(pole)
	var shade := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.15
	sc.bottom_radius = 0.23
	sc.height = 0.3
	sc.material = _mat(Color(0.75, 0.6, 0.42), 0.9, LAMP, 2.6)
	shade.mesh = sc
	shade.position.y = 1.52
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(shade)
	_light(g, Vector3(0, 1.45, 0.05), LAMP, 2.4, 5.8, "LampLight")
	_solid(d, Vector3(0.35, 1.7, 0.35), at + Vector3(0, 0.85, 0))

# --- The door ---------------------------------------------------------------------------------

## A frame round the door, and the hall light under it: the way out is the one thing you can find in the dark.
static func _door(room: Node3D, d: Node3D) -> void:
	var door := room.get_node_or_null("DoorToCity") as Node3D
	if door == null:
		return
	var p := door.global_position
	var wood := _mat(Color(0.1, 0.075, 0.055), 0.7)
	var x := p.x + 0.4
	_box(d, Vector3(0.12, 2.18, 0.1), Vector3(x, 1.09, p.z - 0.55), wood)
	_box(d, Vector3(0.12, 2.18, 0.1), Vector3(x, 1.09, p.z + 0.55), wood)
	_box(d, Vector3(0.12, 0.1, 1.2), Vector3(x, 2.18, p.z), wood)
	var gap := _mat(HALL, 0.5, HALL, 5.0)
	_box(d, Vector3(0.02, 0.012, 0.92), Vector3(x + 0.07, 0.008, p.z), gap)

# --- Walls, floor, ceiling --------------------------------------------------------------------

## Skirting boards give the walls a base line, so the room has edges in the dark.
static func _skirting(d: Node3D) -> void:
	var m := _mat(Color(0.12, 0.095, 0.075), 0.6)
	_box(d, Vector3(10.0, 0.12, 0.03), Vector3(0, 0.06, -3.48), m)
	_box(d, Vector3(10.0, 0.12, 0.03), Vector3(0, 0.06, 3.48), m)
	_box(d, Vector3(0.03, 0.12, 7.0), Vector3(-4.98, 0.06, 0), m)
	_box(d, Vector3(0.03, 0.12, 7.0), Vector3(4.98, 0.06, 0), m)

# --- Furniture --------------------------------------------------------------------------------

const PH := "res://assets/polyhaven/%s/%s.gltf"

## A stove between the windows, one ring still red: the other warm thing in the room, and not a happy one.
static func _stove(d: Node3D, at: Vector3) -> void:
	var s := _model(d, PH % ["electric_stove", "electric_stove"], at, 0.0, 1.15, Color(0.8, 0.78, 0.72))
	if s == null:
		return
	s.name = "Stove"
	_solid(d, Vector3(0.6, 1.0, 0.75), at + Vector3(0, 0.5, 0))
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.085
	cm.bottom_radius = 0.085
	cm.height = 0.006
	cm.material = _mat(Color(0.4, 0.08, 0.03), 0.6, Color(1.0, 0.3, 0.08), 3.0)
	ring.mesh = cm
	ring.position = Vector3(-0.1, 1.0, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.add_child(ring)

static func _bookcase(d: Node3D, at: Vector3) -> void:
	var b := _model(d, PH % ["wooden_bookshelf_worn", "wooden_bookshelf_worn"], at, PI * 0.5, 0.8)
	if b:
		b.name = "Shelf"
		_solid(d, Vector3(0.5, 1.65, 1.1), at + Vector3(0, 0.83, 0))

## A worn rug under the middle of the room, the one soft thing on the floor.
static func _rug(d: Node3D, at: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.13, 0.11)
	m.roughness = 1.0
	var rug := _box(d, Vector3(3.0, 0.012, 2.0), at + Vector3(0, 0.006, 0), m)
	rug.name = "Rug"
