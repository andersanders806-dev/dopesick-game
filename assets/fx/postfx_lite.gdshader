shader_type canvas_item;
// The PostFX when you're well (sickness 0): just the vignette and the
// grain, drawn over the frame instead of read from a copy of it. The full
// shader samples a screen copy four times a pixel; on a UHD 620 that was
// ~3.5 ms a frame for an effect that, at sickness 0, is only these two.

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.05;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);
	float dist = length(centered) / vignette_radius;
	float vig = max(1.0 - smoothstep(0.35, 1.0, dist) * vignette_strength, 0.0);
	float g = (rand(SCREEN_UV * vec2(960.0, 540.0) + TIME * 60.0) - 0.5) * grain_strength;
	// Blended over the frame: frame * vig darkens it like the full shader's
	// multiply; a light speck of grain adds, a dark one dims a touch.
	float a = 1.0 - vig * (1.0 - abs(g));
	vec3 c = g > 0.0 ? vec3(g / max(a, 0.001)) : vec3(0.0);
	COLOR = vec4(c, a);
}
