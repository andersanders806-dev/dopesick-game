shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// The street outside a room's doorway, at infinity: the day and night panoramas (assets/doors/glass_street_*_soft.png,
// out-of-focus copies made by dev-tools/gen_door_soft.py: a doorway shows a hand-wide slice of the panorama, and seen
// from a dim room the street is blurred and bright) looked up by the direction you look, mixed by the time of day.
// One texture fetch by day or by night, two only while the sky changes over; no taps, no loop.

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
	vec3 c;
	if (day_amount >= 0.999) {
		c = texture(street_day, puv).rgb;
	} else if (day_amount <= 0.001) {
		c = texture(street_night, puv).rgb;
	} else {
		c = mix(texture(street_night, puv).rgb, texture(street_day, puv).rgb, day_amount);
	}
	// By day the glare lifts it toward white.
	c = mix(c, vec3(0.92, 0.93, 0.9), 0.18 * day_amount);
	ALBEDO = c * (1.0 + 0.3 * day_amount);
}
