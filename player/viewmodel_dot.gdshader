shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;

#include "res://player/viewmodel.gdshaderinc"

// The red dot of a reflex sight: a bright dot in a thin ring, from the UVs.
// Drawn with the viewmodel's projection and on top of the sight's own frame.
uniform float viewmodel_fov = 60.0;
uniform vec3 tint : source_color = vec3(1.0, 0.08, 0.04);
uniform float dot_size = 0.07;
uniform float ring_size = 0.9;

void vertex() {
	POSITION = vm_clip(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, viewmodel_fov);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float d = 1.0 - smoothstep(dot_size * 0.6, dot_size, r);
	float glow = exp(-r * r / (dot_size * dot_size) * 0.5) * 0.35;
	float ring = (1.0 - smoothstep(0.0, 0.035, abs(r - ring_size * 0.8))) * 0.22 * (1.0 - smoothstep(0.85, 1.0, r));
	float v = clamp(d + glow + ring, 0.0, 1.0);
	ALBEDO = tint * v * 2.0;
	ALPHA = v;
}
