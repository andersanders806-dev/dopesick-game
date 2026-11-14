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

// Seen from a dim room the street is out of focus and bright: a doorway shows a hand-wide slice of the panorama,
// so it is blurred (a ring of taps, enough to melt the pixel blocks) and by day lifted toward daylight glare.
vec3 pano(vec2 uv) {
	return mix(texture(street_night, uv).rgb, texture(street_day, uv).rgb, day_amount);
}

void fragment() {
	vec3 r = normalize(dir_world);
	vec2 puv = vec2(atan(r.x, r.z) / TAU + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
	vec3 c = pano(puv) * 0.2;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * (TAU / 8.0);
		c += pano(puv + vec2(cos(a) * 0.006, sin(a) * 0.012)) * 0.1;
	}
	c = mix(c, vec3(0.92, 0.93, 0.9), 0.18 * day_amount);
	ALBEDO = c * (1.0 + 0.3 * day_amount);
}
