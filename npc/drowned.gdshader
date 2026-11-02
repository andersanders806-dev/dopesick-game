shader_type spatial;
render_mode cull_back;
// THE DROWNED (npc/Drowned.gd): the dead shader below, turned into a sea-bloated brute: swollen,
// bluish skin that is always wet (slick highlights, running sheen), barnacle crust and green
// algae on the lower body, cloth gone to rags of weed, and big pale glowing eyes.
// Same instance uniforms as the rot shader (wounds, severed limbs), so the gore works on it.
//
// (The dead: a Rocketbox body's own texture (skin and clothes are painted
// together) pushed towards pale grey-green flesh with dark veins, grimed and
// blood-stained cloth, torn cloth (holes by a damage mask) and a faint glow
// in the eyes. One material per source surface is shared by every zombie;
// what differs per zombie is set per instance (`rot`, `seed`).
//
// kind 0: the body (skin and clothes in one map), 1: the head. Hair and
// lashes keep the model's own alpha-cut material (npc/Zombie3D.gd).)

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform int kind = 0;
uniform float roughness_base = 0.8;
uniform float specular_base = 0.3;
// So they read in the dark street: a cold rim where the body turns away from you
// (the silhouette) and a small lift of the body's own colour, both stronger with
// distance, so a zombie is always seen without the night turning into day.
uniform vec3 rim_color : source_color = vec3(0.3, 0.38, 0.36);
uniform float rim_power = 2.4;
uniform float rim_strength = 0.3;
uniform float body_lift = 0.045;
uniform float bloat = 6.5;
uniform float head_scale = 1.2;
uniform float hunch = 11.0;

// How far gone this one is (0 fresh .. 1 rotten) and its own offset into the
// noise, so no two share a pattern.
instance uniform float rot : hint_range(0.0, 1.0) = 0.6;
instance uniform float seed = 0.0;
// Wounds (fx/gore/Gore.gd): where a bullet went in, in the body's UVs: (u, v, radius, depth),
// and which surface (0 body, 1 head) each is on. Radius 0 is no wound. Skin, then torn flesh, then bone.
instance uniform vec4 wound_a = vec4(0.0);
instance uniform vec4 wound_b = vec4(0.0);
instance uniform float wound_sa = -1.0;
instance uniform float wound_sb = -1.0;
// Limbs that are gone: a bit for every limb id (fx/gore/GoreRig.gd LIMB_ID) whose triangles are clipped away.
instance uniform float sever_bits = 0.0;

varying vec2 v_uv;
varying vec3 v_local;
varying vec3 v_wpos;
varying float v_dist;
varying flat float v_limb;

void vertex() {
	v_limb = COLOR.r * 16.0;
	v_uv = UV;
	// A bigger head, then bulk: thick legs, a swollen belly and chest, heavy arms; then the hunch.
	// (The model's mesh space: pelvis at the origin, head at +40..+52, forward is +X.)
	float hs = smoothstep(35.0, 38.0, VERTEX.y);
	vec3 hc = vec3(-2.0, 45.0, 0.0);
	VERTEX = mix(VERTEX, hc + (VERTEX - hc) * head_scale, hs);
	float legs = 2.6 * (1.0 - smoothstep(-6.0, 0.0, VERTEX.y));
	float belly = bloat * smoothstep(-24.0, -6.0, VERTEX.y) * (1.0 - smoothstep(8.0, 22.0, VERTEX.y));
	float chest = bloat * 0.8 * smoothstep(6.0, 16.0, VERTEX.y) * (1.0 - smoothstep(30.0, 36.0, VERTEX.y));
	float arm = 3.4 * smoothstep(8.0, 14.0, abs(VERTEX.z)) * smoothstep(-8.0, 6.0, VERTEX.y);
	VERTEX += NORMAL * (max(max(legs, belly), max(chest, arm)) + 0.8);
	float up = smoothstep(2.0, 46.0, VERTEX.y);
	VERTEX.x += hunch * up * up;
	VERTEX.y -= hunch * 0.25 * up * up;
	v_local = VERTEX;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	float mx = max(c.r, max(c.g, c.b));
	// Orange-ish, moderately saturated pixels are skin; the head is nearly
	// all skin.
	float skin = step(c.g, c.r + 0.02) * step(c.b, c.g + 0.04) * smoothstep(0.1, 0.26, sat) * (1.0 - smoothstep(0.62, 0.8, sat));
	if (kind == 1) {
		skin = max(skin, 0.65);
	}
	vec2 so = vec2(seed * 7.13, seed * 3.71);
	float n_lo = texture(noise_tex, v_uv * 2.0 + so).r;
	float n_mid = texture(noise_tex, v_uv * 7.0 + so.yx).g;
	float n_hi = texture(noise_tex, v_uv * 19.0 + so).b;

	// Cloth is soaked through and torn: ragged edges darkened, not cut away (nothing here is see-through).
	float tear = 0.0;
	if (kind == 0 && skin < 0.4) {
		tear = smoothstep(0.86, 0.95, texture(noise_tex, v_uv * 4.0 + so * 1.7).a);
	}

	// Flesh: opaque, pale grey-green and bloated, mottled with bruises and sickly yellow patches,
	// dark veins in a ridged network.
	vec3 flesh = vec3(0.52, 0.6, 0.47) * (0.66 + luma * 0.65);
	float bruise = smoothstep(0.5, 0.78, n_lo * 0.75 + n_mid * 0.45);
	float jaundice = smoothstep(0.55, 0.8, n_mid * 0.6 + (1.0 - n_lo) * 0.4);
	flesh = mix(flesh, vec3(0.2, 0.11, 0.18) * (0.8 + n_hi * 0.5), bruise * 0.75);
	flesh = mix(flesh, vec3(0.5, 0.55, 0.3) * (0.7 + n_hi * 0.5), jaundice * 0.35 * (1.0 - bruise));
	float vein_line = 1.0 - smoothstep(0.0, 0.07, abs(n_mid - 0.5));
	float vein_fine = 1.0 - smoothstep(0.0, 0.05, abs(n_hi - 0.5));
	float veins = clamp(vein_line + vein_fine * 0.7, 0.0, 1.0);
	flesh = mix(flesh, vec3(0.09, 0.07, 0.16), veins * 0.85);
	vec3 skin_out = mix(c * vec3(0.8, 0.9, 0.8), flesh, 0.96);

	// Clothes: dark, soaked, stained with sea slime, frayed at the tears.
	vec3 soaked = vec3(luma) * vec3(0.3, 0.36, 0.33) * 0.75 + vec3(0.008, 0.012, 0.01);
	float stain = smoothstep(0.55, 0.72, n_mid * 0.7 + n_lo * 0.5);
	soaked = mix(soaked, vec3(0.02, 0.05, 0.035), stain * 0.8);
	soaked *= 1.0 - 0.6 * tear;
	vec3 col = mix(soaked, skin_out, skin);

	// Slime and weed stains from the knees down; barnacle crust in patches.
	float low = 1.0 - smoothstep(-34.0, 2.0, v_local.y);
	float algae = smoothstep(0.42, 0.66, n_mid * 0.6 + n_lo * 0.6) * (0.2 + 0.8 * low);
	col = mix(col, vec3(0.04, 0.14, 0.07) * (0.6 + n_hi), algae * 0.7);
	float crust_n = texture(noise_tex, v_uv * 13.0 + so * 2.0).g;
	float crust = smoothstep(0.8, 0.84, crust_n + low * 0.08) * (0.3 + 0.7 * smoothstep(0.35, 0.65, n_lo)) * (kind == 1 ? 0.0 : 1.0);
	col = mix(col, vec3(0.6, 0.62, 0.55) * (0.6 + 0.5 * n_hi), crust);

	// Wet: slick, with a clear coat of water over the skin; dry and rough only where the crust is.
	float rough_out = mix(0.3 + 0.12 * n_hi, 0.85, crust);
	col = wound_layer(wound_a, wound_sa, col, v_uv, kind, rough_out);
	col = wound_layer(wound_b, wound_sb, col, v_uv, kind, rough_out);
	ALBEDO = col;
	ROUGHNESS = rough_out;
	SPECULAR = mix(0.55, 0.2, crust);
	CLEARCOAT = 0.55 * (1.0 - crust);
	CLEARCOAT_ROUGHNESS = 0.08;
	// Water running down: streaks that are glassier than the rest.
	float run = texture(noise_tex, vec2(v_uv.x * 6.0, v_uv.y * 2.0 - TIME * 0.12) + so).a;
	float sheen = smoothstep(0.62, 0.9, run) * (1.0 - crust);
	ROUGHNESS = mix(ROUGHNESS, 0.05, sheen);

	// A faint cold edge so the shape reads against the night: not a glow.
	float far_k = 1.0 + 1.2 * smoothstep(6.0, 26.0, v_dist);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	EMISSION = rim_color * rim * rim_strength * far_k + col * body_lift * far_k;
}
