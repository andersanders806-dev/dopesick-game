shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

#include "res://player/viewmodel.gdshaderinc"

// The muzzle flash: a star of spikes round a hot core, computed from the UVs
// (no texture), drawn with the viewmodel's projection so it sits on the gun.
uniform float viewmodel_fov = 60.0;
uniform vec3 tint : source_color = vec3(1.0, 0.72, 0.35);
uniform float intensity = 1.0;
uniform float spikes = 5.0;
uniform float spin = 0.0;

void vertex() {
	POSITION = vm_clip(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, viewmodel_fov);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + spin;
	float star = pow(abs(cos(a * spikes * 0.5)), 6.0);
	float core = exp(-r * r * 9.0);
	float rays = star * exp(-r * 3.2) * (1.0 - smoothstep(0.7, 1.0, r));
	float v = (core * 1.4 + rays * 1.1) * intensity;
	ALBEDO = mix(tint, vec3(1.0, 0.95, 0.8), clamp(core, 0.0, 1.0)) * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
