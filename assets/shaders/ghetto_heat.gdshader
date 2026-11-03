shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Heat shimmer over a fire: a camera-facing quad that re-draws the screen behind it a little
// displaced by two drifting sines, strongest in the middle and fading at the edges. One screen
// copy a frame while a burning car is on screen; the set leaves it out on the Low preset.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 0.011;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float mask = smoothstep(0.0, 0.3, 0.5 - abs(uv.x - 0.5)) * smoothstep(0.0, 0.25, 1.0 - uv.y) * smoothstep(0.0, 0.2, uv.y);
	vec2 wob = vec2(sin(uv.y * 26.0 - TIME * 5.0 + uv.x * 7.0), cos(uv.y * 19.0 - TIME * 4.0 - uv.x * 5.0));
	ALBEDO = texture(screen_tex, SCREEN_UV + wob * strength * mask).rgb;
	ALPHA = clamp(mask * 6.0, 0.0, 1.0);
}
