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
uniform vec3 rim_color : source_color = vec3(0.34, 0.5, 0.46);
uniform float rim_power = 2.4;
uniform float rim_strength = 0.55;
uniform float body_lift = 0.12;
uniform float bloat = 4.5;
uniform vec3 eye_color : source_color = vec3(0.62, 0.95, 1.0);

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
	// Swollen: the belly and chest bulge, the limbs a little.
	float belly = smoothstep(-24.0, -4.0, VERTEX.y) * (1.0 - smoothstep(12.0, 30.0, VERTEX.y));
	VERTEX += NORMAL * (belly * bloat + 1.4);
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

	// Cloth that is torn through: holes cut by the damage mask, more of them
	// the further gone.
	if (kind == 0 && skin < 0.4) {
		float tear = texture(noise_tex, v_uv * 4.0 + so * 1.7).a;
		if (tear > 1.0 - 0.1 * rot) {
			discard;
		}
	}

	// Skin: drained, greenish, with dark veins in a ridged network.
	vec3 dead_skin = vec3(luma * 1.0) * vec3(0.62, 0.82, 0.9) + vec3(0.02, 0.05, 0.07);
	dead_skin *= mix(1.0, 0.72 + n_lo * 0.5, rot);
	float vein_line = 1.0 - smoothstep(0.0, 0.06, abs(n_mid - 0.5));
	float vein_fine = 1.0 - smoothstep(0.0, 0.05, abs(n_hi - 0.5));
	float veins = clamp(vein_line + vein_fine * 0.6, 0.0, 1.0) * rot;
	dead_skin = mix(dead_skin, vec3(0.1, 0.15, 0.3), veins * 0.8);
	vec3 skin_out = mix(c, dead_skin, clamp(rot * 1.4, 0.0, 1.0));

	// Cloth: dirt in the folds, mould, and blood that has dried dark.
	// Cloth soaked and sea-stained: the colour it had mostly washed out to a green-grey.
	vec3 washed = vec3(luma) * vec3(0.5, 0.78, 0.74) + vec3(0.0, 0.025, 0.02);
	vec3 grime = mix(c * vec3(0.5, 0.75, 0.75), washed, 0.94) * mix(1.0, 0.45 + n_lo * 0.4, rot);
	float stain = smoothstep(0.62, 0.72, n_mid * 0.7 + n_lo * 0.5) * rot;
	grime = mix(grime, vec3(0.03, 0.09, 0.06), stain * 0.85);
	vec3 col = mix(grime, skin_out, skin);

	// Blood on the skin too, wetter than the cloth's.
	float blood = smoothstep(0.7, 0.8, n_mid * 0.6 + n_lo * 0.55 + (1.0 - n_hi) * 0.1) * rot;
	col = mix(col, vec3(0.18, 0.05, 0.12), blood * 0.5 * skin);
	// Algae and weed from the knees down, barnacle crust in patches on the cloth and skin.
	float low = 1.0 - smoothstep(-34.0, 2.0, v_local.y);
	float algae = smoothstep(0.38, 0.62, n_mid * 0.6 + n_lo * 0.6) * (0.35 + 0.65 * low);
	col = mix(col, vec3(0.05, 0.18, 0.08) * (0.6 + n_hi), algae * 0.75);
	float crust_n = texture(noise_tex, v_uv * 13.0 + so * 2.0).g;
	float crust = smoothstep(0.7, 0.74, crust_n + low * 0.1) * (0.4 + 0.6 * smoothstep(0.35, 0.65, n_lo));
	col = mix(col, vec3(0.62, 0.64, 0.58) * (0.7 + 0.5 * n_hi), crust);

	// Wet: slick everywhere, dry and rough only where the crust is.
	float rough_out = mix(0.14 + 0.16 * n_hi, 0.85, crust);
	col = wound_layer(wound_a, wound_sa, col, v_uv, kind, rough_out);
	col = wound_layer(wound_b, wound_sb, col, v_uv, kind, rough_out);
	ALBEDO = col;
	ROUGHNESS = rough_out;
	SPECULAR = mix(0.9, 0.2, crust);
	// A running sheen of water.
	float run = texture(noise_tex, vec2(v_uv.x * 6.0, v_uv.y * 2.0 - TIME * 0.12) + so).a;
	float sheen = smoothstep(0.62, 0.9, run) * (1.0 - crust);
	ROUGHNESS = mix(ROUGHNESS, 0.03, sheen);

	float far_k = 1.0 + 1.6 * smoothstep(6.0, 26.0, v_dist);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 glow = rim_color * rim * rim_strength * far_k + col * body_lift * far_k + vec3(0.02, 0.06, 0.07) * sheen;
	// Eyes: the whites of a head glow a sick yellow.
	if (kind == 1) {
		float eye = (1.0 - smoothstep(0.08, 0.2, sat)) * smoothstep(0.62, 0.82, mx);
		glow += eye * eye_color * 1.6;
	}
	EMISSION = glow;
}
