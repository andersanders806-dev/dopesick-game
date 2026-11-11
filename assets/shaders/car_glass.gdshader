shader_type spatial;
// A parked car's glass (world/CarPaint.gd): dark and reflective, just see-
// through enough for what's on the dashboard, dusty on the rear window and
// the upturned panes, beaded when it rains. Per-car dust in an instance
// uniform so every car shares the one material.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform float wet : hint_range(0.0, 1.0) = 0.0;
uniform float clarity : hint_range(0.0, 1.0) = 0.3;
instance uniform vec4 wear = vec4(0.5, 0.0, 0.3, 0.0);

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
	vec3 ln = normalize(local_n);
	float seed = wear.w * 17.0;
	// Facing up or back: more dust. Facing forward: the wipers' clean sweep.
	float rear = smoothstep(0.2, 0.7, -ln.x);
	float upward = smoothstep(0.35, 0.8, ln.y);
	float front = smoothstep(0.3, 0.7, ln.x);
	float film = (0.18 + rear * 0.55 + upward * 0.3 - front * 0.12) * wear.z * 1.6;
	film *= 0.65 + 0.7 * vnoise(local_pos * vec3(7.0, 14.0, 7.0) + seed);
	// A hand-wiped patch now and then.
	film *= 1.0 - 0.8 * smoothstep(0.55, 0.45, vnoise(local_pos * 2.2 + seed * 3.0)) * step(0.5, fract(wear.w * 7.0));
	film = clamp(film * (1.0 - wet * 0.65), 0.0, 0.85);
	vec3 dust = vec3(0.26, 0.24, 0.2);
	ALBEDO = mix(vec3(0.02, 0.03, 0.035), dust, film);
	ALPHA = clamp(mix(0.58 + clarity * 0.2, 0.97, film), 0.0, 1.0);
	METALLIC = 0.7 * (1.0 - film);
	ROUGHNESS = mix(0.08, 0.7, film) * mix(1.0, 0.5, wet);
	if (wet > 0.01) {
		vec2 bp = (abs(ln.y) > 0.6 ? local_pos.xz : local_pos.xy) * 52.0;
		vec2 cell = floor(bp);
		vec2 d2 = fract(bp) - (0.25 + 0.5 * vec2(hash13(vec3(cell, 1.0)), hash13(vec3(cell, 7.0))));
		float bead = (1.0 - smoothstep(0.08, 0.18, length(d2))) * step(0.4, hash13(vec3(cell, 11.0)));
		vec3 g_view = mat3(VIEW_MATRIX * MODEL_MATRIX) * (abs(ln.y) > 0.6 ? vec3(d2.x, 0.0, d2.y) : vec3(d2.x, d2.y, 0.0));
		NORMAL = normalize(NORMAL + g_view * bead * 2.5 * wet);
		ALPHA = clamp(ALPHA + bead * wet * 0.2, 0.0, 1.0);
	}
}
