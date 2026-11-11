shader_type spatial;
render_mode unshaded, cull_disabled;
// A room that isn't there, seen through a doorway: interior mapping. The quad is the doorway; behind it is a box
// room (width x height of the quad, `depth` deep). Each pixel's view ray is followed into the box and picks up the
// wall, floor, ceiling or back wall it hits, so the room has depth and the sides slide as you move.

uniform sampler2D wall_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D floor_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ceil_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D back_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 size = vec2(1.5, 2.2);
uniform float depth = 7.0;
uniform vec3 tint : source_color = vec3(1.0);
// How much darker the room gets with depth (a store's far end is dimmer than its door).
uniform float fall_off = 0.45;

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 p = vec3(local_pos.xy, 0.0);
	vec3 d = p - cam_local;
	d = normalize(d);
	// Walking toward the doorway the camera is in front of it (cam_local.z > 0); from behind, nothing.
	float hw = size.x * 0.5;
	float hh = size.y * 0.5;
	// Distances to each plane the ray can leave through.
	float tx = 1e9;
	if (d.x > 1e-4) { tx = (hw - p.x) / d.x; }
	else if (d.x < -1e-4) { tx = (-hw - p.x) / d.x; }
	float ty = 1e9;
	if (d.y > 1e-4) { ty = (hh - p.y) / d.y; }
	else if (d.y < -1e-4) { ty = (-hh - p.y) / d.y; }
	float tz = (-depth - p.z) / min(d.z, -1e-4);
	float t = min(tx, min(ty, tz));
	vec3 h = p + d * t;
	vec3 col;
	if (t == tz) {
		col = texture(back_tex, vec2(h.x / size.x + 0.5, 0.5 - h.y / size.y)).rgb;
	} else if (t == ty) {
		vec2 uv = vec2(h.x / size.x + 0.5, -h.z / depth);
		if (d.y > 0.0) {
			col = texture(ceil_tex, uv).rgb;
		} else {
			col = texture(floor_tex, uv).rgb;
		}
	} else {
		// Side walls: u runs from the door to the far end, v up the wall (mirrored on the right).
		vec2 uv = vec2(-h.z / depth, 0.5 - h.y / size.y);
		col = texture(wall_tex, uv).rgb;
	}
	float dist = clamp(-h.z / depth, 0.0, 1.0);
	col *= mix(1.0, 1.0 - fall_off, dist);
	ALBEDO = col * tint;
}
