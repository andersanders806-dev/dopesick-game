shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// The zombie block's wet paving (world/NightAtmos.gd): the street's own asphalt / concrete textures
// (world-planar, as the old triplanar material had them) under a puddle mask, a damp darkening, rain
// ripples, and a screen-space-free reflection of the lamps and neon signs: for every light source the
// mirrored position under the ground is projected into the view and a streak is painted where the
// reflection of that light would be (stretched towards the viewer, as on rippled water).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.2;
uniform float puddle_cover : hint_range(0.0, 1.0) = 0.4;
uniform float damp : hint_range(0.0, 1.0) = 0.65;
uniform float rain_amount : hint_range(0.0, 1.0) = 1.0;
uniform float streak_gain = 1.0;
uniform int refl_count = 0;
uniform vec4 refl_pos[6];
uniform vec4 refl_col[6];

varying vec3 wpos;
varying vec3 wnrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The slope of the rain's rings on standing water (two scales of cells, each with one ring growing).
vec2 ripples(vec2 p) {
	vec2 acc = vec2(0.0);
	for (int k = 0; k < 1; k++) {
		vec2 q = p * (2.4 + float(k) * 1.7);
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash12(id + float(k) * 17.0);
		float t = fract(TIME * (0.5 + 0.35 * h) + h * 7.0);
		vec2 c = (vec2(hash12(id + 3.1), hash12(id + 5.7)) - 0.5) * 0.5;
		vec2 d = f - c;
		float r = length(d) + 1e-4;
		float w = r - t * 0.45;
		float amp = (1.0 - t) * (1.0 - t);
		acc += (d / r) * sin(w * 70.0) * exp(-w * w * 1400.0) * amp;
	}
	return acc;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	bool top = wnrm.y > 0.7;
	vec2 uv = wpos.xz * uv_scale;
	if (!top) {
		uv = (abs(wnrm.x) > abs(wnrm.z) ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y)) * uv_scale;
	}
	vec3 alb = texture(albedo_tex, uv).rgb * tint.rgb;
	float rgh = texture(rough_tex, uv).r;

	// Where the water stands: big soft blobs with ragged edges, and a patchy damp everywhere else.
	vec2 n2 = vec2(texture(noise_tex, wpos.xz * 0.05).r, texture(noise_tex, wpos.xz * 0.37 + 7.3).r);
	float n = n2.x * 0.85 + n2.y * 0.15;
	float edge = 1.0 - puddle_cover;
	float puddle = top ? smoothstep(edge, edge + 0.035, n) : 0.0;
	float rim = top ? smoothstep(edge - 0.07, edge, n) : 0.0;
	float patch = n2.y;
	float wet = top ? clamp(damp * (0.75 + 0.5 * patch) + rim * 0.35 + puddle, 0.0, 1.0) : damp * 0.5;

	alb *= mix(1.0, 0.62, wet);
	alb *= mix(1.0, 0.55, puddle);
	float r_wet = mix(rgh, 0.16 + rgh * 0.12, wet);
	ROUGHNESS = mix(r_wet, 0.035, puddle);
	SPECULAR = mix(0.5, 0.85, wet);
	METALLIC = 0.0;
	ALBEDO = alb;

	vec2 slope = vec2(0.0);
	if (top) {
		if (puddle < 0.98) {
			vec3 nm = texture(normal_tex, uv).xyz * 2.0 - 1.0;
			slope = nm.xy * (1.0 - puddle);
		}
		if (rain_amount > 0.01 && wet > 0.5) {
			slope += ripples(wpos.xz) * (0.12 + 0.2 * puddle) * rain_amount * clamp(wet * 1.4, 0.0, 1.0);
		}
		vec3 wn = normalize(vec3(slope.x, 1.0, slope.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}

	// Reflections of the lights in the wet.
	if (top && refl_count > 0 && (puddle > 0.02 || wet > 0.75)) {
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 vdir = normalize(wpos - cam);
		float hl = length(vdir.xz) + 1e-4;
		vec2 vh = vdir.xz / hl;
		float ev = vdir.y / hl;
		float fres = 0.04 + 0.96 * pow(1.0 - clamp(-vdir.y, 0.0, 1.0), 5.0);
		float shimmer = (n2.y - 0.5) * 0.05 + slope.x * 0.02;
		float spread = mix(0.05, 0.022, puddle);
		vec3 acc = vec3(0.0);
		for (int i = 0; i < refl_count; i++) {
			vec3 s = refl_pos[i].xyz;
			vec3 d3 = vec3(s.x, -s.y, s.z) - cam;
			float dl = length(d3.xz) + 1e-4;
			if (dl > 60.0) {
				continue;
			}
			vec2 dh = d3.xz / dl;
			if (dot(vh, dh) < 0.2) {
				continue;
			}
			float ed = d3.y / dl;
			float daz = vh.x * dh.y - vh.y * dh.x + shimmer;
			float dy = ev - ed;
			float along = dy < 0.0 ? exp(-(dy * dy) / 0.35) : exp(-(dy * dy) / 0.0016);
			float side = exp(-(daz * daz) / (spread * spread));
			float att = 1.0 / (1.0 + (dl * dl) / 120.0);
			acc += refl_col[i].rgb * (side * along * att * refl_col[i].a);
		}
		EMISSION = acc * fres * streak_gain * (0.25 * wet + 0.9 * puddle);
	}
}
