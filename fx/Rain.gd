extends Node3D
## Light rain for the zombie block's night (world/NightAtmos.gd adds one): GPU streaks falling through a box
## round the camera and small rings where drops hit the ground, nothing that reads at a distance and nothing
## on the CPU but the follow. Settings > "Rain and splashes at night" (Graphics.rain_fx) switches it; the wet
## paving's own rings (assets/shaders/wet_street.gdshader) follow the same switch.

const StreakShader := preload("res://assets/shaders/rain_streak.gdshader")
## The box the rain falls in, centred on the camera (m).
const BOX := Vector3(16.0, 10.0, 16.0)
const STREAKS := 420
const SPLASHES := 90

var streaks: GPUParticles3D
var splashes: GPUParticles3D
var _ring: Texture2D

func _ready() -> void:
	top_level = true
	_build_streaks()
	_build_splashes()
	_apply()

func _build_streaks() -> void:
	streaks = GPUParticles3D.new()
	streaks.name = "Streaks"
	streaks.amount = STREAKS
	streaks.lifetime = 0.8
	streaks.preprocess = 0.8
	streaks.local_coords = false
	streaks.visibility_aabb = AABB(-BOX, BOX * 2.0)
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(BOX.x * 0.5, 0.1, BOX.z * 0.5)
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3.ZERO
	streaks.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.013, 0.6)
	var m := ShaderMaterial.new()
	m.shader = StreakShader
	q.material = m
	streaks.draw_pass_1 = q
	add_child(streaks)

func _ring_texture() -> Texture2D:
	if _ring != null:
		return _ring
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := exp(-pow((d - 0.78) / 0.11, 2.0)) * (1.0 - smoothstep(0.85, 1.0, d))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_ring = ImageTexture.create_from_image(img)
	return _ring

func _build_splashes() -> void:
	splashes = GPUParticles3D.new()
	splashes.name = "Splashes"
	splashes.amount = SPLASHES
	splashes.lifetime = 0.45
	splashes.preprocess = 0.45
	splashes.local_coords = false
	splashes.visibility_aabb = AABB(Vector3(-9, -1, -9), Vector3(18, 2, 18))
	splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8.0, 0.0, 8.0)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.6))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	splashes.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.36, 0.36)
	q.orientation = PlaneMesh.FACE_Y
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _ring_texture()
	m.albedo_color = Color(0.6, 0.7, 0.9, 0.5)
	m.disable_receive_shadows = true
	q.material = m
	splashes.draw_pass_1 = q
	add_child(splashes)

func _apply() -> void:
	var on: bool = Graphics.rain_fx
	streaks.emitting = on
	splashes.emitting = on
	visible = on

func _process(_delta: float) -> void:
	var on: bool = Graphics.rain_fx
	if on != visible:
		_apply()
	if not on:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	streaks.global_position = Vector3(at.x, at.y + 4.5, at.z)
	var ground := 0.03
	splashes.global_position = Vector3(at.x, ground, at.z)
