// One quad plays a flipbook (explosion_a/b_5x5.png = 5x5, smoke_wispy_8x8.png and dust_cloud_8x8.png = 8x8) and cross-fades the
// two neighbouring frames, so 25 frames over 1.5 s still look smooth. fx/Explosion.gd sets `progress` (age / life) every frame.
// The quad fades out near the lens (fade_near .. fade_far metres) so a blast beside the camera never fills the screen with alpha.
// billboard = false lays the quad on its own plane (the dust cloud on the street).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D flipbook : source_color, filter_linear, repeat_disable;
uniform int cols = 5;
uniform int rows = 5;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float brightness = 1.0;
uniform float fade_near = 1.5;   // metres from the camera: fully faded at this distance and closer
uniform float fade_far = 4.0;    // fully visible from here out
uniform float flip = 0.0;        // 1.0 mirrors the picture
uniform bool billboard = true;
// The card fades out over `floor_fade` metres above `floor_y` (0 = off), so a fireball that reaches below the street dissolves
// there instead of being cut off in a hard line by the floor.
uniform float floor_y = -1000.0;
uniform float floor_fade = 0.0;
varying float v_fade;
varying float v_world_y;

void vertex() {
	if (billboard) {
		// Faces the camera and keeps the node's scale (the standard Godot 4 recipe).
		mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
	v_world_y = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float d = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	v_fade = smoothstep(fade_near, fade_far, d);
}

void fragment() {
	float n = float(cols * rows);
	float f = clamp(progress, 0.0, 0.9999) * (n - 1.0);
	float i0 = floor(f);
	float k = f - i0;
	float i1 = min(i0 + 1.0, n - 1.0);
	vec2 cell = vec2(1.0 / float(cols), 1.0 / float(rows));
	vec2 u = clamp(vec2(mix(UV.x, 1.0 - UV.x, flip), UV.y), vec2(0.004), vec2(0.996));
	vec4 a = texture(flipbook, (vec2(mod(i0, float(cols)), floor(i0 / float(cols))) + u) * cell);
	vec4 b = texture(flipbook, (vec2(mod(i1, float(cols)), floor(i1 / float(cols))) + u) * cell);
	vec4 c = mix(a, b, k);
	ALBEDO = c.rgb * tint.rgb * brightness;
	float lift = floor_fade > 0.0 ? smoothstep(floor_y, floor_y + floor_fade, v_world_y) : 1.0;
	ALPHA = c.a * tint.a * v_fade * lift;
}
