shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
// Shop-door glass for a weak GPU: nearly clear straight on, more of a mirror toward the edge (fresnel), the
// street (a panorama, dawn to night) in the mirror, a film of smudges and fingerprints, no probes, no screen read.

uniform sampler2D street_day : source_color, filter_linear, repeat_enable;
uniform sampler2D street_night : source_color, filter_linear, repeat_enable;
uniform sampler2D smudge : filter_linear, repeat_disable;
uniform float day_amount : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.55, 0.68, 0.72);
uniform float base_alpha = 0.10;
uniform float reflect_base = 0.07;
uniform float smudge_amount = 0.32;

void fragment() {
	vec3 n = normalize(NORMAL);
	if (!FRONT_FACING) {
		n = -n;
	}
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-normalize(VIEW), n), 0.0)).xyz;
	vec2 puv = vec2(atan(r.x, r.z) / TAU + 0.5, acos(clamp(r.y, -1.0, 1.0)) / PI);
	vec3 street = mix(texture(street_night, puv).rgb, texture(street_day, puv).rgb, day_amount);
	float film = texture(smudge, UV).r;
	float refl = reflect_base + (1.0 - reflect_base) * fres;
	ALBEDO = tint * 0.25;
	ROUGHNESS = 0.06 + film * 0.5;
	SPECULAR = 0.7;
	EMISSION = street * (refl * 0.55 + film * 0.12 * (0.3 + day_amount));
	ALPHA = clamp(base_alpha + refl * 0.45 + film * smudge_amount, 0.0, 0.92);
}
