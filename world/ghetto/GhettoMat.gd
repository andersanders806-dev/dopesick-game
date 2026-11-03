extends RefCounted
## Shared material cache for the Ghetto Wars set's scripts.

static var _mats := {}

static func mat(color: Color, rough := 0.85, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(true), rough, metal, glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats[key] = m
	return m
