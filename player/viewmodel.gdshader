shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "res://player/viewmodel.gdshaderinc"

uniform float viewmodel_fov = 60.0;
// Nothing nearer than this to the eye is drawn: an arm crossing the camera's plane would fill the screen.
uniform float near_cut = 0.11;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
// A rectangle of the albedo texture (u0, v0, u1, v1) painted out dark: a maker's logo on the red dot sight.
uniform vec4 blank_rect = vec4(0.0);
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
// Story first person: bare hands instead of gloves; skin goes grey-green and wet as the sickness climbs.
uniform float bare = 0.0;
uniform vec3 skin_tone : source_color = vec3(0.62, 0.43, 0.34);
uniform float sick = 0.0;
uniform float sweat = 0.0;
uniform int procedural = 0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_amount = 0.0;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
// A box of the mesh (its own space) that is not drawn: the magazine the left hand has just pulled out of the gun.
uniform bool cut_on = false;
uniform vec3 cut_lo = vec3(0.0);
uniform vec3 cut_hi = vec3(0.0);

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
	if (cut_on && all(greaterThan(v_obj, cut_lo)) && all(lessThan(v_obj, cut_hi))) {
		discard;
	}
	vec4 tex = use_tex ? texture(albedo_tex, UV) : vec4(1.0);
	if (UV.x > blank_rect.x && UV.y > blank_rect.y && UV.x < blank_rect.z && UV.y < blank_rect.w) {
		tex.rgb = vec3(0.022);
	}
	ALBEDO = albedo.rgb * tex.rgb;
	float r = roughness;
	float m = metallic;
	if (arms) {
		float glove = clamp(v_cloth.r, 0.0, 1.0);
		float sleeve = clamp(v_cloth.g, 0.0, 1.0);
		float tip = 1.0 - smoothstep(0.0, 0.4, glove + sleeve);
		vec2 w = UV * vec2(520.0, 520.0);
		float weave = 0.5 + 0.5 * sin(w.x + sin(w.y * 0.5) * 1.3) * sin(w.y);
		// A worn field-jacket sleeve: charcoal olive, a coarse weave, and soft folds that run round the arm.
		float fold = 0.5 + 0.5 * sin(v_obj.x * 0.55 + sin(v_obj.y * 0.31 + v_obj.z * 0.2) * 2.4 + v_obj.z * 0.35);
		float fold2 = 0.5 + 0.5 * sin(v_obj.x * 1.7 + v_obj.y * 0.9 - v_obj.z * 0.8);
		float wear = 0.5 + 0.5 * sin(w.x * 0.07 + sin(w.y * 0.05) * 2.0);
		vec3 cloth = vec3(0.026, 0.029, 0.023) * (0.7 + 0.45 * weave) * (0.55 + 0.6 * fold) * (0.9 + 0.2 * fold2);
		cloth = mix(cloth, vec3(0.05, 0.052, 0.042), wear * 0.25);
		vec3 leather = vec3(0.012, 0.011, 0.011) * (0.85 + 0.3 * weave);
		float strap = smoothstep(0.15, 0.4, glove) * (1.0 - smoothstep(0.55, 0.85, glove)) * smoothstep(0.1, 0.4, sleeve);
		vec3 worn = mix(cloth, leather, smoothstep(0.35, 0.65, glove));
		worn = mix(worn, vec3(0.06, 0.056, 0.048), strap * 0.8);
		ALBEDO = mix(worn, albedo.rgb * tex.rgb * 0.9, tip);
		r = mix(mix(0.9, 0.5, smoothstep(0.35, 0.65, glove)), 0.65, tip);
		m = 0.0;
		if (bare > 0.0) {
			float skin_m = max(smoothstep(0.3, 0.6, glove), tip) * bare;
			float pores = 0.5 + 0.5 * sin(w.x * 0.9) * sin(w.y * 1.1);
			float knuckle = 0.5 + 0.5 * sin(v_obj.x * 1.3 + sin(v_obj.z * 0.7) * 1.5);
			vec3 skin = skin_tone * (0.88 + 0.16 * pores) * (0.92 + 0.12 * knuckle);
			skin = mix(skin, vec3(0.17, 0.19, 0.14) * (0.9 + 0.2 * pores), sick * 0.7);
			// Sweat: beads of shine that wander over the skin.
			float bead = smoothstep(0.55, 0.95, 0.5 + 0.5 * sin(w.x * 0.33 + sin(w.y * 0.27) * 2.0) * sin(w.y * 0.31 + TIME * 0.5));
			float wet = clamp(sweat * (0.45 + 0.55 * bead), 0.0, 1.0);
			skin = mix(skin, skin * 1.08, wet * 0.3);
			ALBEDO = mix(ALBEDO, skin, skin_m);
			r = mix(r, mix(0.62, 0.3, wet), skin_m);
		}
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
	ROUGHNESS = clamp(r, bare > 0.0 ? 0.25 : 0.4, 1.0);
	METALLIC = min(m, 0.6);
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
