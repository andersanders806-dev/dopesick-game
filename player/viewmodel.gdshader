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
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_amount = 0.0;
uniform sampler2D emission_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;

void vertex() {
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
