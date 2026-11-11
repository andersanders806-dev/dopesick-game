shader_type spatial;
// Old, dirty car paint (world/CarPaint.gd): the model's body texture is its
// shading, panel lines and baked dirt; its hue is thrown away for a muted
// paint, then road grime climbs the sills, rust eats the wheel arches, dust
// settles on the roof and the rain makes it shine and bead.
//
// Every car shares one material per colour. How worn each one is lives in
// instance uniforms, so they stay batchable and no two look alike:
//   wear.x dirt (0.5 = the old fixed look), wear.y rust, wear.z dust, wear.w seed
//   arch.xy the front and rear axle x, arch.z the axle height, arch.w the arch radius
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

instance uniform vec4 wear = vec4(0.5, 0.0, 0.3, 0.0);
instance uniform vec4 arch = vec4(1.35, -1.35, 0.34, 0.5);

varying vec3 local_pos;
varying vec3 local_n;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	local_pos = VERTEX;
	local_n = NORMAL;
}

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 repaint = paint.rgb * clamp(lum / ref_lum, 0.15, 1.5);
	vec3 base = mix(repaint, tex * 0.85, livery);
	vec3 ln = normalize(local_n);
	float seed = wear.w * 17.0;
	// Dirt from the road: thick at the sills, streaked down the flanks. Roofs
	// and bonnets get no streaks (they print a lattice), only an even film of dust.
	float low = 1.0 - smoothstep(0.2, 0.8, local_pos.y);
	float flank = 1.0 - smoothstep(0.35, 0.85, abs(ln.y));
	float top = smoothstep(0.5, 0.9, ln.y);
	float streak = 0.5 + 0.5 * sin(local_pos.x * 11.0 + sin(local_pos.z * 17.0) * 2.0 + seed);
	float patch_n = vnoise(local_pos * 3.1 + seed);
	float dirt = clamp(grime * wear.x * 2.0 * (low * (0.7 + 0.3 * patch_n) * 0.85 + streak * 0.3 * flank + top * 0.2), 0.0, 0.92);
	vec3 mud = mix(vec3(0.085, 0.07, 0.055), vec3(0.17, 0.15, 0.12), top);
	vec3 col = mix(base, mud, dirt);
	// Rust: bubbling out of the wheel arches and along the sills, in blotches.
	// Only on the flanks, and not on the livery cars.
	float ax = abs(local_pos.x - arch.x) < abs(local_pos.x - arch.y) ? arch.x : arch.y;
	float r = length(vec2(local_pos.x - ax, local_pos.y - arch.z));
	float zone = 1.0 - smoothstep(arch.w * 0.95, arch.w * 1.7, r);
	float sill = (1.0 - smoothstep(0.12, 0.4, local_pos.y)) * 0.45;
	float n1 = vnoise(local_pos * 9.0 + seed) * 0.6 + vnoise(local_pos * 23.0 + seed) * 0.4;
	float rust = clamp((zone + sill) * smoothstep(0.38, 0.62, n1 + (zone + sill) * 0.25) * wear.y * (1.0 - livery) * smoothstep(0.3, 0.7, 1.0 - abs(ln.y)), 0.0, 1.0);
	vec3 rcol = mix(vec3(0.2, 0.075, 0.03), vec3(0.4, 0.19, 0.07), vnoise(local_pos * 41.0 + seed));
	col = mix(col, rcol, rust);
	// Dust on the roof, bonnet and boot, thinning where the rain's run it.
	float dust = top * wear.z * (0.55 + 0.45 * vnoise(local_pos * 6.0 + seed)) * (1.0 - wet * 0.7);
	col = mix(col, vec3(0.34, 0.31, 0.26), clamp(dust, 0.0, 0.8));
	ALBEDO = col * (1.0 - wet * 0.18);
	vec3 orm = texture(orm_tex, UV).rgb;
	// Old clearcoat: dull, and duller where it's dirty; rain puts the shine back.
	float rough = mix(clamp(orm.g + 0.3, 0.3, 1.0), 0.95, max(dirt, dust * 0.9));
	rough = mix(rough, 0.95, rust);
	ROUGHNESS = rough * mix(1.0, 0.45, wet);
	METALLIC = orm.b * metal * (1.0 - max(dirt, rust));
	SPECULAR = mix(0.5, 0.75, wet);
	// Rain beads on the upward and sideways skin: a field of small domes.
	if (wet > 0.01) {
		vec2 bp = (abs(ln.y) > 0.6 ? local_pos.xz : local_pos.xy) * 46.0;
		vec2 cell = floor(bp);
		vec2 jit = vec2(hash13(vec3(cell, 1.0)), hash13(vec3(cell, 7.0)));
		vec2 d2 = fract(bp) - (0.25 + 0.5 * jit);
		float rr = 0.14 + 0.12 * hash13(vec3(cell, 3.0));
		float bead = (1.0 - smoothstep(rr * 0.6, rr, length(d2))) * step(0.35, hash13(vec3(cell, 11.0)));
		vec3 g_obj = abs(ln.y) > 0.6 ? vec3(d2.x, 0.0, d2.y) : vec3(d2.x, d2.y, 0.0);
		vec3 g_view = mat3(VIEW_MATRIX * MODEL_MATRIX) * g_obj;
		NORMAL = normalize(NORMAL + g_view * bead * 2.2 * wet);
		ROUGHNESS = mix(ROUGHNESS, 0.12, bead * wet);
	}
}
