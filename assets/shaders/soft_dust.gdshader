shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled;

// Dust and smoke puffs for CPUParticles3D quads (fx/Quake.gd): a billboard with a cloudy noise edge in
// place of a flat disc, a random turn per particle, soft against whatever it is in front of (depth
// fade), and lit (by the street lamps, the moon and the ambient) instead of unshaded.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec4 albedo : source_color = vec4(0.5, 0.46, 0.41, 1.0);
uniform float softness = 0.9;
uniform float density = 1.5;

varying float seed;

void vertex() {
	mat4 m = MODEL_MATRIX;
	float sx = length(m[0].xyz);
	float sy = length(m[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], m[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	seed = fract(sin(dot(m[3].xyz, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float ang = seed * 6.2831 + TIME * 0.12 * (seed - 0.5);
	vec2 q = vec2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
	float n = texture(noise_tex, q * 0.9 + 0.5 + seed * 5.0).r;
	float n2 = texture(noise_tex, q * 2.1 + 0.5 + seed * 11.0).r;
	float body = 1.0 - smoothstep(0.15, 1.0, r);
	float cloud = clamp((n * 0.7 + n2 * 0.3) * 1.7 - 0.3, 0.0, 1.0);
	float a = cloud * body * body;

	float depth = texture(depth_tex, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	float fade = clamp((-view.z + VERTEX.z) / softness, 0.0, 1.0);

	ALBEDO = albedo.rgb * COLOR.rgb * (0.8 + 0.4 * n2);
	ALPHA = clamp(a * COLOR.a * fade * density, 0.0, 1.0);
	ROUGHNESS = 1.0;
	NORMAL = vec3(0.0, 0.0, 1.0);
}
