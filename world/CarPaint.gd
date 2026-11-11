extends RefCounted
## One look for every car on the block, traffic (StreetLife.gd) and parked
## (City3D.gd) alike: assets/cars/*.glb come out of the box clean and loud,
## and these are old, dirty and mostly grey. The body is repainted from a
## muted palette (assets/shaders/car_paint.gdshader keeps the model's own
## shading and panel lines), the glass goes dark and reflective, and rain
## makes the lot shine. The taxi and the cruiser keep their livery.

const SHADER := preload("res://assets/shaders/car_paint.gdshader")
const GLASS_SHADER := preload("res://assets/shaders/car_glass.gdshader")

## Greys, a faded navy, dark green, maroon, beige, off-white: what's left on
## a street nobody washes.
const PALETTE := [
	Color(0.34, 0.35, 0.37),
	Color(0.2, 0.21, 0.23),
	Color(0.14, 0.18, 0.3),
	Color(0.13, 0.21, 0.16),
	Color(0.32, 0.1, 0.11),
	Color(0.52, 0.47, 0.38),
	Color(0.66, 0.65, 0.6),
	Color(0.5, 0.52, 0.54),
]
## Beyond this many metres a parked car or wreck isn't drawn at all.
const PARKED_REACH := 60.0
const LIVERY := ["taxi_crownvic", "police_crownvic"]

static var _bodies := {}
## Texture -> its paint brightness, read back once.
static var _brightness := {}
static var _bounds := {}
static var _glass: StandardMaterial3D
static var _glass_parked: ShaderMaterial
static var _panels := {}
static var _wet := false

## Dresses an instance of one of the car models: `pick` is the palette index
## (a parked car's name hashes to one, so it keeps its colour), random when
## negative. Wrecks are left as they burnt. A moving car's shadow isn't worth
## the sun's pass over its triangles (`shadows` false), a parked one's grounds it.
## `reach` > 0 hides the car beyond that many metres (nothing is drawn of a far
## parked car; the roofs of the block's other end aren't worth their triangles).
static func dress(model: Node3D, pick := -1, shadows := true, reach := 0.0, wear_seed := -1) -> void:
	limit_range(model, reach)
	var kind := model.scene_file_path.get_file().get_basename()
	if kind.begins_with("wreck"):
		return
	var paint: Color = PALETTE[(pick if pick >= 0 else randi()) % PALETTE.size()]
	var parked := reach > 0.0
	var wear := wear_for(wear_seed if wear_seed >= 0 else randi(), kind in LIVERY)
	var arch := arch_for(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		# The shadow of the shell is the car's; the seats, underbody and
		# wheels inside it add nothing but triangles to the sun's pass.
		if mi.name != "body" or not shadows:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name == "glass":
			if parked:
				# Parked cars are looked at close up: glass you can see a little
				# through, dusty and beaded. Traffic's stays opaque (cheap on Low).
				(mi as MeshInstance3D).set_surface_override_material(0, glass_parked())
				(mi as MeshInstance3D).set_instance_shader_parameter("wear", wear)
			else:
				(mi as MeshInstance3D).set_surface_override_material(0, glass())
		elif mi.name == "body":
			var base := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			if base != null:
				(mi as MeshInstance3D).set_surface_override_material(0, _body_material(base, paint, kind in LIVERY))
				(mi as MeshInstance3D).set_instance_shader_parameter("wear", wear)
				(mi as MeshInstance3D).set_instance_shader_parameter("arch", arch)

## Hides the model's meshes beyond `reach` metres (0: never), no fade.
static func limit_range(model: Node3D, reach: float) -> void:
	if reach <= 0.0:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = reach
		(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

static func paint_index(car_name: String) -> int:
	return absi(car_name.hash()) % PALETTE.size()

## Dark, reflective, opaque: no sorting, and nobody sees the inside from the
## road anyway.
static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.03, 0.04, 0.045)
		_glass.metallic = 0.7
		_glass.roughness = 0.1
		_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass

## The glass of a parked car: see-through enough for a dashboard, dusty, beads
## in the rain (assets/shaders/car_glass.gdshader).
static func glass_parked() -> ShaderMaterial:
	if _glass_parked == null:
		_glass_parked = ShaderMaterial.new()
		_glass_parked.shader = GLASS_SHADER
		_glass_parked.set_shader_parameter("wet", 1.0 if _wet else 0.0)
	return _glass_parked

## How worn one car is, from a seed: x dirt (0.5 is the old fixed look), y
## rust, z dust on the roof and rear glass, w the noise seed. The taxi and
## the cruiser are kept up: clean-ish and never rusty.
static func wear_for(seed_: int, livery: bool) -> Vector4:
	var r := RandomNumberGenerator.new()
	r.seed = seed_ * 7919 + 13
	var rust := 0.0 if r.randf() < 0.4 else r.randf_range(0.25, 1.0)
	if livery:
		return Vector4(r.randf_range(0.18, 0.3), 0.0, r.randf_range(0.1, 0.3), r.randf())
	return Vector4(r.randf_range(0.28, 0.95), rust, r.randf_range(0.15, 0.95), r.randf())

## The axles for the shader's rust arches: front x, rear x, axle height and
## the arch radius, from the model's own wheel nodes.
static func arch_for(model: Node3D) -> Vector4:
	var ws := wheels(model)
	if ws.size() < 4:
		return Vector4(1.35, -1.35, 0.34, 0.5)
	var fx := 0.0
	var rx := 0.0
	var y := 0.0
	for w in ws:
		var n := String(w.name)
		if n.contains("_f"):
			fx += w.position.x * 0.5
		else:
			rx += w.position.x * 0.5
		y += w.position.y * 0.25
	return Vector4(fx, rx, y, y * 1.45)

static func _body_material(base: StandardMaterial3D, paint: Color, livery: bool) -> ShaderMaterial:
	var key := [base, paint, livery]
	if not _bodies.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = SHADER
		sm.set_shader_parameter("albedo_tex", base.albedo_texture)
		sm.set_shader_parameter("orm_tex", base.roughness_texture)
		sm.set_shader_parameter("paint", paint if base.albedo_texture != null else paint * Color(0.9, 0.9, 0.9))
		sm.set_shader_parameter("livery", 1.0 if livery else 0.0)
		sm.set_shader_parameter("ref_lum", _paint_brightness(base.albedo_texture))
		sm.set_shader_parameter("grime", randf_range(0.45, 0.85))
		sm.set_shader_parameter("wet", 1.0 if _wet else 0.0)
		_bodies[key] = sm
	return _bodies[key]

## How bright the texture's paint is (linear): a high percentile of a small
## copy, so the baked-dark panel gaps and trim don't drag it down. 1 for a
## model whose paint is a flat colour.
static func _paint_brightness(tex: Texture2D) -> float:
	if tex == null:
		return 1.0
	if not _brightness.has(tex):
		_brightness[tex] = _measure_brightness(tex)
	return _brightness[tex]

static func _measure_brightness(tex: Texture2D) -> float:
	var img := tex.get_image()
	if img == null:
		return 1.0
	if img.is_compressed():
		img.decompress()
	img.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var lums: Array[float] = []
	for y in 32:
		for x in 32:
			var c := img.get_pixel(x, y).srgb_to_linear()
			lums.append(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722)
	lums.sort()
	return maxf(lums[int(lums.size() * 0.8)], 0.05)

## The rain starts or stops: every dressed car shines, or doesn't.
static func set_wet(raining: bool) -> void:
	_wet = raining
	for sm in _bodies.values():
		(sm as ShaderMaterial).set_shader_parameter("wet", 1.0 if raining else 0.0)
	if _glass_parked != null:
		_glass_parked.set_shader_parameter("wet", 1.0 if raining else 0.0)

## The model's extent in its own space (no tree needed), cached per model:
## traffic lamps and parked-car collision boxes are sized from it.
static func bounds(model: Node3D) -> AABB:
	var key := model.scene_file_path
	if not _bounds.has(key):
		var acc: Array = [AABB(), false]
		_gather(model, Transform3D.IDENTITY, acc)
		_bounds[key] = acc[0]
	return _bounds[key]

static func _gather(node: Node3D, xf: Transform3D, acc: Array) -> void:
	for child in node.get_children():
		if not child is Node3D:
			continue
		var t := xf * (child as Node3D).transform
		if child is MeshInstance3D:
			var box := t * (child as MeshInstance3D).get_aabb()
			acc[0] = box if not acc[1] else (acc[0] as AABB).merge(box)
			acc[1] = true
		_gather(child as Node3D, t, acc)

## The model's wheel_* nodes (fl, fr, rl, rr), for spinning.
static func wheels(model: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for w in model.find_children("wheel_*", "Node3D", true, false):
		out.append(w as Node3D)
	return out

## Where a car's panes are, in the model's space, from its glass mesh's own
## triangles (cached per model): {"front", "rear", "left", "right"}, each
## {"c": centre, "n": outward normal, "ext": size}. Props taped to or laid
## against the glass (ParkedRow) are placed from these.
static func glass_panels(model: Node3D) -> Dictionary:
	var key := model.scene_file_path
	if _panels.has(key):
		return _panels[key]
	var out := {}
	var mi := model.find_child("glass", true, false) as MeshInstance3D
	if mi != null and mi.mesh != null:
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var groups := {"front": [], "rear": [], "left": [], "right": []}
		for i in verts.size():
			var n := norms[i]
			if n.x > 0.35 and n.y > 0.1:
				groups["front"].append(i)
			elif n.x < -0.35 and n.y > 0.1:
				groups["rear"].append(i)
			elif n.z > 0.8:
				groups["right"].append(i)
			elif n.z < -0.8:
				groups["left"].append(i)
		for g in groups:
			var idx: Array = groups[g]
			if idx.size() < 3:
				continue
			var box := AABB(verts[idx[0]], Vector3.ZERO)
			var nsum := Vector3.ZERO
			for i in idx:
				box = box.expand(verts[i])
				nsum += norms[i]
			out[g] = {"c": box.get_center(), "n": nsum.normalized(), "ext": box.size}
	_panels[key] = out
	return out
