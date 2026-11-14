shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
// The red glow of a room's EXIT sign: a soft radial haze in front of the doorway, added to what is behind it. Stands in
// for a light (an omni over a small room is dear on an iGPU).

uniform vec3 glow_color : source_color = vec3(1.0, 0.25, 0.16);
uniform float strength = 0.26;

void fragment() {
	vec2 p = (UV - vec2(0.5, 0.4)) * vec2(2.0, 2.0);
	float g = clamp(1.0 - length(p), 0.0, 1.0);
	g = g * g * g;
	ALBEDO = glow_color * g * strength;
	ALPHA = 1.0;
}
