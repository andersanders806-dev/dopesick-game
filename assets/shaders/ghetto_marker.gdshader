shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// An objective in the world: either a ring on the ground (ring = 1) with a sweep running outwards, or a
// shaft of light standing on it (ring = 0), brightest at its foot and gone at the top.
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.3);
uniform float intensity = 1.0;
uniform float ring = 0.0;
uniform float phase = 0.0;
uniform float height = 7.0;
varying float vy;

void vertex() {
	vy = VERTEX.y;
}

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * 3.2 + phase);
	float a;
	if (ring > 0.5) {
		float r = length(UV * 2.0 - 1.0);
		float band = smoothstep(1.0, 0.9, r) * smoothstep(0.66, 0.82, r);
		float sweep = 0.55 + 0.45 * sin(r * 14.0 - TIME * 4.5);
		float core = smoothstep(0.75, 0.0, r) * 0.14;
		a = band * (0.7 + 0.5 * sweep) + core;
	} else {
		float t = clamp((vy + height * 0.5) / height, 0.0, 1.0);
		float side = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.3);
		a = pow(1.0 - t, 1.6) * 0.5 * side + 0.02 * (1.0 - t);
	}
	ALBEDO = tint;
	ALPHA = clamp(a * pulse * intensity, 0.0, 1.0);
}
