shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	vec2 centered = SCREEN_UV - vec2(0.5);
	float dist = length(centered) / vignette_radius;
	float vig = 1.0 - smoothstep(0.35, 1.0, dist) * vignette_strength;
	col *= vig;

	float grain = (rand(SCREEN_UV * vec2(960.0, 540.0) + TIME * 60.0) - 0.5) * grain_strength;
	col += grain;

	COLOR = vec4(col, 1.0);
}
