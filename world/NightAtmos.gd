extends Node3D
## The zombie block's wet night (world/ZombieBlock.gd adds one): everything that makes the street read as a
## cold rainy city after dark and nothing that costs a screen-space pass.
##
## Wet paving: the Road / Sidewalk / Curb boxes of every cell get assets/shaders/wet_street.gdshader, built
## from the textures they already had (puddles, damp, rain rings) plus a streak reflection of the nearest
## lamps and neon signs, fed from here every frame (so a stuttering lamp stutters in the water too).
## Light haze: a soft sodium halo round each streetlight head, the cheap stand-in for volumetric fog on Low.
## Rain: fx/Rain.gd, switched by Settings > Rain and splashes at night.

const WetShader := preload("res://assets/shaders/wet_street.gdshader")
const RainScript := preload("res://fx/Rain.gd")
const PAVING := ["Road", "Sidewalk", "Curb", "RowGround"]
## Reflections the shader can hold (the nearest ones are chosen).
const REFLECTIONS := 6
## Lamp halo: size (m), how much of the lamp's colour it carries, how close the camera may get before it fades.
const HALO_SIZE := 4.6
const HALO_ALPHA := 0.34
## What a sign's reflection is worth next to a streetlamp's.
const SIGN_GAIN := 0.55
## Streetlamps: their pool is wider and falls off faster than the story's, a warm sodium.
const LAMP_RANGE := 10.5
const LAMP_ENERGY := 3.4
const LAMP_ATTENUATION := 1.7
const LAMP_COLOR := Color(1.0, 0.62, 0.27)

static var _noise: Texture2D

var city: Node3D
var rain: Node3D
var _mats: Array[ShaderMaterial] = []
var _lights: Array = []
var _halos: Array = []
var _chosen: Array = []
var _frame := 0
var _halo_tex: Texture2D

func setup(block: Node3D) -> void:
	city = block
	name = "NightAtmos"
	_tune_lamps()
	_wet_paving()
	_gather_lights()
	_build_halos()
	rain = RainScript.new()
	rain.name = "Rain"
	add_child(rain)

## Number of paving materials swapped (the smoke test reads it).
func wet_count() -> int:
	return _mats.size()

func halo_count() -> int:
	return _halos.size()

## Sodium streetlamps with a real pool: a longer reach with a steeper falloff, same energy by the lamp post.
func _tune_lamps() -> void:
	for entry in city._night_lights:
		var light := entry[0] as OmniLight3D
		if light == null or not light.get_parent().name.begins_with("Streetlight"):
			continue
		light.light_color = LAMP_COLOR
		light.omni_attenuation = LAMP_ATTENUATION
		entry[1] = LAMP_ENERGY
		light.light_energy = LAMP_ENERGY
		light.omni_range = LAMP_RANGE
		# Graphics (F3) keeps the range the room was built with, to put it back on High and cut it on Low.
		light.set_meta("built_range", LAMP_RANGE)
		Graphics._apply_light(light)

static func noise_texture() -> Texture2D:
	if _noise != null:
		return _noise
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	fn.frequency = 0.02
	fn.seed = 811
	var img := fn.get_seamless_image(256, 256, false, false, 0.15, true)
	img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise

func _wet_paving() -> void:
	var made := {}
	for node in city.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var nm := String(mi.name)
		if not PAVING.any(func(p: String): return nm.ends_with(p) or nm.contains(p)):
			continue
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null or src.albedo_texture == null:
			# Already swapped (a second setup) or not the street's own paving.
			continue
		if not made.has(src):
			made[src] = _wet_material(src, nm)
		mi.material_override = made[src]

func _wet_material(src: StandardMaterial3D, nm: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WetShader
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	if src.roughness_texture != null:
		m.set_shader_parameter("rough_tex", src.roughness_texture)
	if src.normal_texture != null:
		m.set_shader_parameter("normal_tex", src.normal_texture)
	m.set_shader_parameter("noise_tex", noise_texture())
	m.set_shader_parameter("tint", src.albedo_color)
	m.set_shader_parameter("uv_scale", src.uv1_scale.x)
	var road := nm.contains("Road")
	m.set_shader_parameter("puddle_cover", 0.46 if road else 0.22)
	m.set_shader_parameter("damp", 0.7 if road else 0.55)
	m.set_shader_parameter("rain_amount", 1.0 if Graphics.rain_fx else 0.0)
	_mats.append(m)
	return m

func _gather_lights() -> void:
	_lights.clear()
	for entry in city._night_lights:
		var light := entry[0] as Light3D
		if light == null:
			continue
		var parent := String(light.get_parent().name)
		if parent.begins_with("Streetlight"):
			_lights.append([light, 1.0, LAMP_COLOR])
		elif String(light.name).ends_with("SignGlow"):
			_lights.append([light, SIGN_GAIN, light.light_color])

func _soft_texture() -> Texture2D:
	if _halo_tex != null:
		return _halo_tex
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.35, Color(1, 1, 1, 0.28))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 96
	g.height = 96
	_halo_tex = g
	return g

## A soft glow round each lamp head: the haze the lamp lights in the wet air. Billboard, additive, fades
## out when the camera is close (a glow you stand inside is not a card).
func _build_halos() -> void:
	for entry in _lights:
		var light := entry[0] as Light3D
		if not light.get_parent().name.begins_with("Streetlight"):
			continue
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = _soft_texture()
		m.albedo_color = Color(LAMP_COLOR.r, LAMP_COLOR.g, LAMP_COLOR.b, HALO_ALPHA)
		m.disable_receive_shadows = true
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 1.2
		m.distance_fade_max_distance = 4.5
		var q := QuadMesh.new()
		q.size = Vector2(HALO_SIZE, HALO_SIZE)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2.0
		add_child(mi)
		mi.global_position = light.global_position + Vector3(0.0, 0.05, 0.0)
		_halos.append([mi, light, m])

func _process(_delta: float) -> void:
	_frame += 1
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	if _frame % 12 == 1 or _chosen.is_empty():
		_choose(at)
	# (Low: no ripples in the puddles, three reflections: the wet paving was the night's dearest pixel work)
	var rain_on := 1.0 if Graphics.rain_fx and Graphics.preset != Graphics.Preset.LOW else 0.0
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for entry in _chosen:
		var light := entry[0] as Light3D
		var e := 0.0
		if is_instance_valid(light) and light.is_visible_in_tree():
			e = light.light_energy
		var p := light.global_position if is_instance_valid(light) else Vector3.ZERO
		var c: Color = entry[2]
		pos.append(Vector4(p.x, p.y, p.z, 1.0))
		col.append(Vector4(c.r, c.g, c.b, e * entry[1] * 0.4))
	while pos.size() < REFLECTIONS:
		pos.append(Vector4())
		col.append(Vector4())
	for m in _mats:
		m.set_shader_parameter("refl_count", _chosen.size())
		m.set_shader_parameter("refl_pos", pos)
		m.set_shader_parameter("refl_col", col)
		m.set_shader_parameter("rain_amount", rain_on)
	for h in _halos:
		var light := h[1] as Light3D
		var on := is_instance_valid(light) and light.is_visible_in_tree() and light.light_energy > 0.05
		var mi := h[0] as MeshInstance3D
		if mi.visible != on:
			mi.visible = on
		if on:
			var k := clampf(light.light_energy / LAMP_ENERGY, 0.0, 1.5)
			(h[2] as StandardMaterial3D).albedo_color.a = HALO_ALPHA * k

func _reflection_cap() -> int:
	return 3 if Graphics.preset == Graphics.Preset.LOW else REFLECTIONS

func _choose(at: Vector3) -> void:
	var live: Array = _lights.filter(func(e): return is_instance_valid(e[0]) and (e[0] as Light3D).is_visible_in_tree())
	live.sort_custom(func(a, b): return (a[0] as Light3D).global_position.distance_squared_to(at) < (b[0] as Light3D).global_position.distance_squared_to(at))
	_chosen = live.slice(0, _reflection_cap())
