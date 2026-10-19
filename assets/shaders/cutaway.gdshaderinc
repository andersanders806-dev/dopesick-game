// The block's buildings, drawn as StandardMaterial3D draws them (the
// features their materials use: albedo, normal, roughness and metallic
// maps with channels, UV or world-triplanar mapping, emission), plus the
// cutaway: what lies on the line from the camera to you, within
// cutaway_radius of it, is dithered out with `discard` -- no blending, so
// it stays in the opaque pass. Player3D sets the two globals; first person
// sets the radius to 0 (nothing in front of your face dithers).
// world/Cutaway.gd turns a building's StandardMaterial3D into this.

global uniform vec3 player_world_pos;
global uniform float cutaway_radius;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_texture_channel = vec4(0.0);
uniform bool use_roughness_texture = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel = vec4(0.0);
uniform bool use_metallic_texture = false;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool use_normal = false;
uniform bool use_emission = false;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform bool uv1_triplanar = false;
uniform float uv1_blend_sharpness = 1.0;

varying vec3 uv1_power_normal;
varying vec3 uv1_triplanar_pos;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (uv1_triplanar) {
		// World triplanar, as BaseMaterial3D's uv1_world_triplanar.
		vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		TANGENT = vec3(0.0, 0.0, -1.0) * abs(NORMAL.x);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.y);
		TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.z);
		TANGENT = normalize(TANGENT);
		BINORMAL = vec3(0.0, 1.0, 0.0) * abs(NORMAL.x);
		BINORMAL += vec3(0.0, 0.0, -1.0) * abs(NORMAL.y);
		BINORMAL += vec3(0.0, 1.0, 0.0) * abs(NORMAL.z);
		BINORMAL = normalize(BINORMAL);
		uv1_power_normal = pow(abs(n), vec3(uv1_blend_sharpness));
		uv1_power_normal /= dot(uv1_power_normal, vec3(1.0));
		uv1_triplanar_pos = world_pos * uv1_scale + uv1_offset;
		uv1_triplanar_pos *= vec3(1.0, -1.0, 1.0);
	} else {
		UV = UV * uv1_scale.xy + uv1_offset.xy;
	}
}

vec4 cut_sample(sampler2D s, vec2 uv) {
	if (uv1_triplanar) {
		vec4 o = texture(s, uv1_triplanar_pos.xy) * uv1_power_normal.z;
		o += texture(s, uv1_triplanar_pos.xz) * uv1_power_normal.y;
		o += texture(s, uv1_triplanar_pos.zy * vec2(-1.0, 1.0)) * uv1_power_normal.x;
		return o;
	}
	return texture(s, uv);
}

// 4x4 ordered dither, 0..1.
float cut_bayer(vec2 frag) {
	ivec2 p = ivec2(frag) % 4;
	int i = p.x + p.y * 4;
	const float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	if (cutaway_radius > 0.0) {
		vec3 cam = CAMERA_POSITION_WORLD;
		// Aimed at your chest; only between the camera and you, never
		// the wall behind you.
		vec3 seg = player_world_pos + vec3(0.0, 1.0, 0.0) - cam;
		float t = dot(world_pos - cam, seg) / max(dot(seg, seg), 0.0001);
		if (t > 0.0 && t < 1.0) {
			float d = distance(world_pos, cam + seg * t);
			float fade = 1.0 - smoothstep(cutaway_radius * 0.6, cutaway_radius, d);
			if (fade > cut_bayer(FRAGCOORD.xy)) {
				discard;
			}
		}
	}
	vec4 a = albedo;
	if (use_albedo_texture) {
		a *= cut_sample(texture_albedo, UV);
	}
	ALBEDO = a.rgb;
	float m = metallic;
	if (use_metallic_texture) {
		m = dot(cut_sample(texture_metallic, UV), metallic_texture_channel) * metallic;
	}
	METALLIC = m;
	SPECULAR = specular;
	float r = roughness;
	if (use_roughness_texture) {
		r = dot(cut_sample(texture_roughness, UV), roughness_texture_channel) * roughness;
	}
	ROUGHNESS = r;
	if (use_normal) {
		NORMAL_MAP = cut_sample(texture_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	if (use_emission) {
		EMISSION = emission.rgb * emission_energy;
	}
}
