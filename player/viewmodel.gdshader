shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://player/viewmodel.gdshaderinc"

uniform float viewmodel_fov = 60.0;
// Nothing nearer than this to the eye is drawn: an arm crossing the camera's plane would fill the screen.
uniform float near_cut = 0.11;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_orm = false;
// The upgraded look: a glow in the gun's tint, strongest at the edges.
// A little light of its own, so the night never turns the gun and arms into a silhouette.
uniform float ambient_lift = 0.16;
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow_amount = 0.0;
// The arms: the second UV map says what each bit wears (x glove, y sleeve, both 0 a bare fingertip).
uniform bool arms = false;
uniform float sleeve_push = 0.3;
// A procedural look for the plain-coloured kit models (the shotgun): 1 blued steel, 2 walnut.
uniform int procedural = 0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_amount = 0.0;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;

varying vec3 v_obj;
varying vec3 v_cloth;

void vertex() {
	v_obj = VERTEX;
	v_cloth = vec3(UV2, 0.0);
	if (arms) {
		// A jacket arm is fuller than a bare one, with a thick rolled cuff above the glove.
		float s = clamp(UV2.y - UV2.x * 0.5, 0.0, 1.0);
		float cuff = smoothstep(0.0, 0.5, UV2.x) * (1.0 - smoothstep(0.5, 0.95, UV2.x)) * UV2.y;
		VERTEX += NORMAL * (s * sleeve_push + cuff * sleeve_push * 1.4);
	}
	POSITION = vm_clip(MODELVIEW_MATRIX, PROJECTION_MATRIX, VERTEX, viewmodel_fov);
}

void fragment() {
	if (-VERTEX.z < near_cut) {
		discard;
	}
	vec4 tex = use_tex ? texture(albedo_tex, UV) : vec4(1.0);
	ALBEDO = albedo.rgb * tex.rgb;
	float r = roughness;
	float m = metallic;
	if (arms) {
		float glove = clamp(v_cloth.r, 0.0, 1.0);
		float sleeve = clamp(v_cloth.g, 0.0, 1.0);
		float tip = 1.0 - smoothstep(0.0, 0.4, glove + sleeve);
		vec2 w = UV * vec2(520.0, 520.0);
		float weave = 0.5 + 0.5 * sin(w.x + sin(w.y * 0.5) * 1.3) * sin(w.y);
		vec3 cloth = vec3(0.0065, 0.0075, 0.007) * (0.8 + 0.4 * weave);
		vec3 leather = vec3(0.005, 0.0045, 0.0045) * (0.85 + 0.3 * weave);
		// The wrist strap: where sleeve and glove overlap.
		float strap = smoothstep(0.15, 0.4, glove) * (1.0 - smoothstep(0.55, 0.85, glove)) * smoothstep(0.1, 0.4, sleeve);
		vec3 worn = mix(cloth, leather, smoothstep(0.35, 0.65, glove));
		worn = mix(worn, vec3(0.03, 0.028, 0.025), strap * 0.8);
		ALBEDO = mix(worn, albedo.rgb * tex.rgb * 0.9, tip);
		r = mix(mix(0.9, 0.5, smoothstep(0.35, 0.65, glove)), 0.65, tip);
		m = 0.0;
	}
	if (procedural == 1) {
		// Blued steel: dark with a soft sheen along the barrel.
		float brush = 0.5 + 0.5 * sin(v_obj.z * 90.0 + sin(v_obj.x * 25.0) * 1.2);
		ALBEDO = vec3(0.011, 0.012, 0.015) * (0.9 + 0.2 * brush);
		m = 0.0;
		r = 0.62 + 0.1 * brush;
		SPECULAR = 0.04;
	} else if (procedural == 2) {
		// Walnut: long grain along the stock with darker rings.
		float g = v_obj.y * 70.0 + sin(v_obj.z * 9.0 + v_obj.x * 40.0) * 1.7 + sin(v_obj.z * 31.0) * 0.4;
		float ring = 0.5 + 0.5 * sin(g * 3.0);
		float fine = 0.5 + 0.5 * sin(v_obj.z * 380.0 + sin(v_obj.y * 120.0) * 3.0);
		ALBEDO = mix(vec3(0.11, 0.05, 0.02), vec3(0.045, 0.02, 0.008), ring * 0.7 + fine * 0.2);
		m = 0.0;
		r = 0.55;
		SPECULAR = 0.25;
	}
	if (use_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		r *= orm.g;
		m *= orm.b;
	}
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec3 e = glow_color * glow_amount * (0.3 + rim) + ALBEDO * ambient_lift;
	if (use_emission_tex) {
		e += texture(emission_tex, UV).rgb * emission_amount;
	} else {
		e += emission_color * emission_amount;
	}
	EMISSION = e;
}
