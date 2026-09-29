shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;
// 0 = well, 1 = deep withdrawal (GameState.sickness()). Drives everything
// below: doubled, swimming vision, colour fringing at the edges, a vignette
// that tightens with the heartbeat, and the colour draining out.
uniform float sickness : hint_range(0.0, 1.0) = 0.0;
// Beats per second of the pulse; the heartbeat loop runs about this fast.
uniform float pulse_rate = 1.15;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float s = sickness;

	// A slow swim: the whole frame drifts a few pixels on two out-of-phase
	// sine waves, as if you can't quite hold your eyes still.
	uv += vec2(sin(TIME * 0.9 + uv.y * 3.0), cos(TIME * 0.7 + uv.x * 2.0)) * 0.0035 * s;

	vec3 col = texture(screen_tex, uv).rgb;

	// Double vision: a ghost of the frame drifting in and out beside it.
	vec2 ghost = vec2(sin(TIME * 0.55), cos(TIME * 0.4)) * 0.012 * s;
	col = mix(col, texture(screen_tex, uv + ghost).rgb, 0.35 * s);

	// Chromatic fringing, strongest toward the edges.
	float edge = dot(centered, centered) * 4.0;
	vec2 ca = centered * 0.012 * s * edge;
	col.r = mix(col.r, texture(screen_tex, uv + ca).r, s);
	col.b = mix(col.b, texture(screen_tex, uv - ca).b, s);

	// Drain the colour.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), 0.45 * s);

	// Vignette, closing in on each heartbeat.
	float beat = pow(max(0.0, sin(TIME * pulse_rate * 6.2832)), 8.0);
	float radius = vignette_radius - 0.28 * s - 0.08 * s * beat;
	float dist = length(centered) / max(radius, 0.2);
	float vig = 1.0 - smoothstep(0.35, 1.0, dist) * (vignette_strength + 0.4 * s);
	col *= max(vig, 0.0);

	float grain = (rand(SCREEN_UV * vec2(960.0, 540.0) + TIME * 60.0) - 0.5) * (grain_strength + 0.06 * s);
	col += grain;

	COLOR = vec4(col, 1.0);
}
