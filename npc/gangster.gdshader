shader_type spatial;
render_mode cull_back;
// The armed humans of Ghetto Wars: a Rocketbox body's own texture (skin and clothes painted together),
// its clothes pulled towards the crew's colour so the two crews read apart at a glance, a faint cool rim
// so a figure holds against the night. Wounds and lost limbs are the zombies' (fx/gore/Gore.gd drives the
// same instance uniforms); nothing here is rotten.
// kind 0: the body, 1: the head. Hair and lashes keep the model's own alpha-cut material.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int kind = 0;
uniform float roughness_base = 0.8;
uniform float specular_base = 0.3;
uniform vec3 crew : source_color = vec3(0.3, 0.5, 0.2);
uniform float crew_tint = 0.6;
uniform vec3 rim_color : source_color = vec3(0.45, 0.5, 0.58);
uniform float rim_power = 2.4;
uniform float rim_strength = 0.3;
uniform float body_lift = 0.05;

instance uniform float rot : hint_range(0.0, 1.0) = 0.0;
instance uniform float seed = 0.0;
instance uniform float far_lod = 0.0;
instance uniform vec4 wound_a = vec4(0.0);
instance uniform vec4 wound_b = vec4(0.0);
instance uniform float wound_sa = -1.0;
instance uniform float wound_sb = -1.0;
instance uniform float sever_bits = 0.0;

varying vec2 v_uv;
varying float v_dist;
varying flat float v_limb;

void vertex() {
	v_limb = COLOR.r * 16.0;
	v_uv = UV;
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

float sat_of(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return (mx - mn) / (mx + 0.0001);
}

// Lays one wound over `col`: a bruised, torn edge, wet red flesh, and for a deep one a bone in the middle.
vec3 wound_layer(vec4 w, float surf, vec3 col, vec2 uv, int surface_kind, inout float rough) {
	if (w.z <= 0.0 || int(surf + 0.5) != surface_kind) {
		return col;
	}
	float n = texture(noise_tex, uv * 22.0).r + texture(noise_tex, uv * 61.0).g * 0.4;
	float r = length(uv - w.xy) / w.z + (n - 0.7) * 0.3;
	if (r >= 1.0) {
		return col;
	}
	float edge = smoothstep(1.0, 0.72, r);
	vec3 bruise = col * vec3(0.55, 0.3, 0.32) + vec3(0.06, 0.0, 0.01);
	vec3 flesh = mix(vec3(0.46, 0.04, 0.04), vec3(0.2, 0.008, 0.012), smoothstep(0.65, 0.2, r));
	flesh *= 0.8 + 0.4 * texture(noise_tex, uv * 40.0).b;
	vec3 outc = mix(bruise, flesh, smoothstep(0.85, 0.6, r));
	float bone = smoothstep(0.32, 0.18, r) * smoothstep(0.5, 0.8, w.w);
	outc = mix(outc, vec3(0.74, 0.7, 0.58), bone);
	rough = mix(rough, 0.18, smoothstep(0.9, 0.5, r) * (1.0 - bone));
	return mix(col, outc, edge);
}

void fragment() {
	int limb_id = int(v_limb + 0.5);
	if (limb_id > 0 && ((int(sever_bits + 0.5) >> limb_id) & 1) == 1) {
		discard;
	}
	vec4 tex = texture(albedo_tex, v_uv) * albedo_color;
	vec3 c = tex.rgb;
	float luma = dot(c, vec3(0.3, 0.59, 0.11));
	float sat = sat_of(c);
	float skin = step(c.g, c.r + 0.02) * step(c.b, c.g + 0.04) * smoothstep(0.1, 0.26, sat) * (1.0 - smoothstep(0.62, 0.8, sat));
	if (kind == 1) {
		skin = max(skin, 0.65);
	}
	// Clothes in the crew's colour with their own light and dark kept.
	vec3 cloth = crew * (0.35 + luma * 1.5);
	vec3 col = mix(c, mix(c, cloth, crew_tint), (1.0 - skin) * float(kind == 0));
	float rough_out = roughness_base;
	col = wound_layer(wound_a, wound_sa, col, v_uv, kind, rough_out);
	col = wound_layer(wound_b, wound_sb, col, v_uv, kind, rough_out);
	ALBEDO = col;
	ROUGHNESS = rough_out;
	SPECULAR = specular_base;
	float far_k = 1.0 + 1.2 * smoothstep(6.0, 26.0, v_dist);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim * rim_strength * far_k + col * body_lift * far_k;
}
