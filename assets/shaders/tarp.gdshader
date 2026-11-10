shader_type spatial;
// A tarp over a parked car (world/ParkedRow.gd): sun-faded plastic with fold
// shading and seams, and a hem that stirs in the wind (vertex sway weighted
// by how close to the ground the cloth hangs, so the roof stays put). The
// glTF covered car passes its own texture; the draped tarps are procedural.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float use_tex : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.22, 0.31, 0.42, 1.0);
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// Below this height the cloth hangs free and moves.
uniform float hem_top = 0.75;
// x: phase, y: how much it moves (0 still), z: dirt
instance uniform vec4 flutter = vec4(0.0, 1.0, 0.5, 0.0);

varying vec3 lp;

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
	lp = VERTEX;
	float w = clamp(1.0 - VERTEX.y / hem_top, 0.0, 1.0);
	w *= w;
	float gust = 0.55 + 0.45 * sin(TIME * 0.37 + flutter.x * 6.28);
	float s1 = sin(TIME * 1.9 + VERTEX.x * 2.3 + VERTEX.z * 1.7 + flutter.x * 6.28);
	float s2 = sin(TIME * 3.3 + VERTEX.z * 3.7 - VERTEX.x * 1.3 + flutter.x * 12.0);
	VERTEX += NORMAL * (s1 * 0.02 + s2 * 0.008) * w * gust * flutter.y;
	VERTEX.y += s2 * 0.01 * w * gust * flutter.y;
}

void fragment() {
	float seed = flutter.x * 31.0;
	float folds = vnoise(lp * vec3(3.0, 7.0, 3.0) + seed) * 0.6 + vnoise(lp * vec3(9.0, 18.0, 9.0) + seed) * 0.4;
	float seam = smoothstep(0.02, 0.0, abs(fract(lp.z * 0.55 + 0.1) - 0.5) - 0.47) * 0.5;
	vec3 plastic = tint.rgb * (0.55 + 0.7 * folds) * (1.0 - seam * 0.5);
	vec3 tex = texture(albedo_tex, UV).rgb;
	vec3 col = mix(plastic, tex, use_tex);
	// Grit on the top, streaks where the water runs off.
	float top = clamp(normalize(NORMAL).y, 0.0, 1.0);
	col = mix(col, vec3(0.2, 0.18, 0.15), flutter.z * (0.25 + 0.35 * vnoise(lp * 5.0 + seed)) * (1.0 - 0.5 * top));
	ALBEDO = col * (1.0 - wet * 0.25);
	ROUGHNESS = mix(0.62, 0.3, wet) * (0.8 + 0.4 * folds);
	SPECULAR = mix(0.45, 0.7, wet);
	// The cloth's own crinkle, as a nudge to the normal.
	vec3 g = vec3(vnoise(lp * 14.0 + seed) - 0.5, vnoise(lp * 14.0 + seed + 9.0) - 0.5, vnoise(lp * 14.0 + seed + 21.0) - 0.5);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * MODEL_MATRIX * vec4(g, 0.0)).xyz * 0.35);
}
