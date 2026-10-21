shader_type spatial;
// Old, dirty car paint (world/CarPaint.gd): the model's body texture is its
// shading, panel lines and baked dirt; its hue is thrown away for a muted
// paint, then road grime climbs the sills and the rain makes it shine.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
// glTF's occlusion-roughness-metallic: green is roughness, blue metal.
uniform sampler2D orm_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 paint : source_color = vec4(0.35, 0.36, 0.38, 1.0);
// 1: the texture's own colours stay (taxi, police).
uniform float livery : hint_range(0.0, 1.0) = 0.0;
// The texture's paint brightness, so a flat panel comes out as `paint`.
uniform float ref_lum = 1.0;
uniform float grime : hint_range(0.0, 1.0) = 0.6;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float metal : hint_range(0.0, 1.0) = 0.45;

varying vec3 local_pos;
varying vec3 local_n;

void vertex() {
	local_pos = VERTEX;
	local_n = NORMAL;
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 repaint = paint.rgb * clamp(lum / ref_lum, 0.15, 1.5);
	vec3 base = mix(repaint, tex * 0.85, livery);
	// Dirt from the road: thick at the sills, streaked down the flanks. Roofs
	// and bonnets get no streaks (they print a lattice), only an even film of dust.
	float low = 1.0 - smoothstep(0.2, 0.8, local_pos.y);
	float flank = 1.0 - smoothstep(0.35, 0.85, abs(normalize(local_n).y));
	float top = smoothstep(0.5, 0.9, normalize(local_n).y);
	float streak = 0.5 + 0.5 * sin(local_pos.x * 11.0 + sin(local_pos.z * 17.0) * 2.0);
	float dirt = clamp(grime * (low * 0.85 + streak * 0.3 * flank + top * 0.2), 0.0, 0.9);
	vec3 mud = mix(vec3(0.085, 0.07, 0.055), vec3(0.17, 0.15, 0.12), top);
	ALBEDO = mix(base, mud, dirt) * (1.0 - wet * 0.18);
	vec3 orm = texture(orm_tex, UV).rgb;
	// Old clearcoat: dull, and duller where it's dirty; rain puts the shine back.
	float rough = mix(clamp(orm.g + 0.3, 0.3, 1.0), 0.95, dirt);
	ROUGHNESS = rough * mix(1.0, 0.45, wet);
	METALLIC = orm.b * metal * (1.0 - dirt);
	SPECULAR = mix(0.5, 0.75, wet);
}
