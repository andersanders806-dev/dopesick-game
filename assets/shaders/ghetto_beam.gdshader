shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
// The visible cone of a searchlight through dusty air: an open cone (UV.y 0 at the lamp end, 1 at the
// ground), brightest at the lamp and along the middle as seen from the side, gone at the ground.
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.78);
uniform float intensity = 1.0;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float edge = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);
	float a = (1.0 - along) * 0.5 + 0.04;
	ALBEDO = tint;
	ALPHA = clamp(a * edge * 0.55 * intensity, 0.0, 1.0);
}
