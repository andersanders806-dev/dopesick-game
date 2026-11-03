shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// One falling raindrop streak (fx/Rain.gd): a thin quad that turns round its own up axis to face the
// camera, brightest in the middle and soft at both ends.

uniform vec4 col : source_color = vec4(0.62, 0.72, 0.9, 0.22);

void vertex() {
	mat4 m = MODEL_MATRIX;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], m[1], INV_VIEW_MATRIX[2], m[3]);
}

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	ALBEDO = col.rgb;
	float near = smoothstep(1.5, 5.0, -VERTEX.z);
	ALPHA = (1.0 - x) * (1.0 - x) * sin(UV.y * 3.14159) * col.a * COLOR.a * near;
}
