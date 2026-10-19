extends RefCounted
## The see-through walls: a building mesh that can stand between the
## street camera and you gets its StandardMaterial3Ds swapped for the
## cutaway shader (assets/shaders/cutaway*.gdshader) with the same
## textures and values, so it looks the same until you walk behind it.
## Player3D drives the shader's two globals.
##
## Made once per source material and kept on it (meta "cutaway"), so it
## lives as long as the source does -- Facades makes some materials afresh
## each visit. The sources still change at runtime (lit windows follow the
## hour, normal maps follow the preset), so sync() copies them across.

const SHADER := preload("res://assets/shaders/cutaway.gdshader")
const SHADER_DOUBLE := preload("res://assets/shaders/cutaway_double.gdshader")
## Metres round the camera-to-you line that dither out.
const RADIUS := 2.2

## Every source with a twin, weakly: sync_all() walks them.
static var _sources: Array[WeakRef] = []

## The cutaway twin of `src`, or `src` itself if it's one the shader
## doesn't do (see-through glass: the blended pass can't be dithered, and
## it's small).
static func material_for(src: Material) -> Material:
	var sm := src as StandardMaterial3D
	if sm == null or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	if sm.has_meta("cutaway"):
		return sm.get_meta("cutaway")
	var m := ShaderMaterial.new()
	m.shader = SHADER if sm.cull_mode == BaseMaterial3D.CULL_BACK else SHADER_DOUBLE
	sm.set_meta("cutaway", m)
	_sources.append(weakref(sm))
	sync(sm)
	return m

## The source a twin was made from (the probes put them back), or null.
static func source_of(twin: Material) -> StandardMaterial3D:
	for w in _sources:
		var sm := w.get_ref() as StandardMaterial3D
		if sm and sm.get_meta("cutaway") == twin:
			return sm
	return null

static func is_cutaway(m: Material) -> bool:
	return m is ShaderMaterial and ((m as ShaderMaterial).shader == SHADER or (m as ShaderMaterial).shader == SHADER_DOUBLE)

## Puts every surface of `gi` (and the meshes under it) on the cutaway
## shader, and into group "cutaway".
static func apply(gi: Node) -> void:
	for n in [gi] + gi.find_children("*", "GeometryInstance3D", true, false):
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				var twin := material_for(src)
				if twin != src:
					mi.set_surface_override_material(i, twin)
			mi.add_to_group("cutaway")
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			# One material for a multimesh: only those of one surface.
			if mmi.multimesh and mmi.multimesh.mesh and mmi.multimesh.mesh.get_surface_count() == 1:
				var twin := material_for(mmi.multimesh.mesh.surface_get_material(0))
				if is_cutaway(twin):
					mmi.material_override = twin
					mmi.add_to_group("cutaway")

static func sync_all() -> void:
	_sources = _sources.filter(func(w): return w.get_ref() != null)
	for w in _sources:
		sync(w.get_ref())

const _CHANNELS := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1), Vector4(0.333333, 0.333333, 0.333333, 0)]

static func sync(sm: StandardMaterial3D) -> void:
	if sm == null or not sm.has_meta("cutaway"):
		return
	var m: ShaderMaterial = sm.get_meta("cutaway")
	m.set_shader_parameter("albedo", sm.albedo_color)
	m.set_shader_parameter("use_albedo_texture", sm.albedo_texture != null)
	m.set_shader_parameter("texture_albedo", sm.albedo_texture)
	m.set_shader_parameter("roughness", sm.roughness)
	m.set_shader_parameter("use_roughness_texture", sm.roughness_texture != null)
	m.set_shader_parameter("texture_roughness", sm.roughness_texture)
	m.set_shader_parameter("roughness_texture_channel", _CHANNELS[sm.roughness_texture_channel])
	m.set_shader_parameter("metallic", sm.metallic)
	m.set_shader_parameter("specular", sm.metallic_specular)
	m.set_shader_parameter("use_metallic_texture", sm.metallic_texture != null)
	m.set_shader_parameter("texture_metallic", sm.metallic_texture)
	m.set_shader_parameter("metallic_texture_channel", _CHANNELS[sm.metallic_texture_channel])
	m.set_shader_parameter("use_normal", sm.normal_enabled and sm.normal_texture != null)
	m.set_shader_parameter("texture_normal", sm.normal_texture)
	m.set_shader_parameter("normal_scale", sm.normal_scale)
	m.set_shader_parameter("use_emission", sm.emission_enabled)
	m.set_shader_parameter("emission", sm.emission)
	m.set_shader_parameter("emission_energy", sm.emission_energy_multiplier)
	m.set_shader_parameter("uv1_scale", sm.uv1_scale)
	m.set_shader_parameter("uv1_offset", sm.uv1_offset)
	m.set_shader_parameter("uv1_triplanar", sm.uv1_triplanar and sm.uv1_world_triplanar)
	m.set_shader_parameter("uv1_blend_sharpness", sm.uv1_triplanar_sharpness)
