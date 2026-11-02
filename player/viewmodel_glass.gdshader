shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://player/viewmodel.gdshaderinc"

// The glass of a reflex sight: a faint cool tint, a little denser at the edges.
uniform float viewmodel_fov = 60.0;
uniform float edge_amount = 1.0;
uniform vec3 tint : source_color = vec3(0.35, 0.55, 0.65);

void vertex() {
	POSITION = vm_clip(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, viewmodel_fov);
}

void fragment() {
	vec2 p = abs(UV * 2.0 - 1.0);
	float edge = smoothstep(0.6, 1.0, max(p.x, p.y));
	ALBEDO = tint;
	ALPHA = 0.1 + 0.25 * edge * edge_amount;
}
