extends RefCounted
## One look for every car on the block, traffic (StreetLife.gd) and parked
## (City3D.gd) alike: assets/cars/*.glb come out of the box clean and loud,
## and these are old, dirty and mostly grey. The body is repainted from a
## muted palette (assets/shaders/car_paint.gdshader keeps the model's own
## shading and panel lines), the glass goes dark and reflective, and rain
## makes the lot shine. The taxi and the cruiser keep their livery.

const SHADER := preload("res://assets/shaders/car_paint.gdshader")

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
const LIVERY := ["taxi_crownvic", "police_crownvic"]

static var _bodies := {}
static var _bounds := {}
static var _glass: StandardMaterial3D
static var _wet := false

## Dresses an instance of one of the car models: `pick` is the palette index
## (a parked car's name hashes to one, so it keeps its colour), random when
## negative. Wrecks are left as they burnt. A moving car's shadow isn't worth
## the sun's pass over its triangles (`shadows` false), a parked one's grounds it.
static func dress(model: Node3D, pick := -1, shadows := true) -> void:
	var kind := model.scene_file_path.get_file().get_basename()
	if kind.begins_with("wreck"):
		return
	var paint: Color = PALETTE[(pick if pick >= 0 else randi()) % PALETTE.size()]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		# The shadow of the shell is the car's; the seats, underbody and
		# wheels inside it add nothing but triangles to the sun's pass.
		if mi.name != "body" or not shadows:
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name == "glass":
			(mi as MeshInstance3D).set_surface_override_material(0, glass())
		elif mi.name == "body":
			var base := (mi as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			if base != null:
				(mi as MeshInstance3D).set_surface_override_material(0, _body_material(base, paint, kind in LIVERY))

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
