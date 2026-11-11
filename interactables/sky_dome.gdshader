shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// The street outside a room's doorway, at infinity: the day and night panoramas (the glass's, assets/doors/glass_street_*)
// looked up by the direction you look, mixed by the time of day. A sphere round the room, seen only through its doorways.

uniform sampler2D street_day : source_color, filter_linear, repeat_enable;
uniform sampler2D street_night : source_color, filter_linear, repeat_enable;
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 dir_world;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	dir_world = wp.xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	vec3 r = normalize(dir_world);
	vec2 puv = vec2(atan(r.x, r.z) / TAU + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
	vec3 c = mix(texture(street_night, puv).rgb, texture(street_day, puv).rgb, day_amount);
	ALBEDO = c;
}
