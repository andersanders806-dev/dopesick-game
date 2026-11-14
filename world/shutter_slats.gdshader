shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Dark slat lines over a roller shutter's face (world/Facades.gd): about 4.5 cm a slat, a shadowed seam under each,
// a little uneven so it isn't a barcode. Alpha only, so the lamp's light on the shutter shows through.

uniform float slats = 52.0;
uniform float seam = 0.16;
uniform float strength = 0.62;

void fragment() {
	float v = UV.y * slats;
	float f = fract(v);
	float id = floor(v);
	float uneven = 0.75 + 0.25 * fract(sin(id * 12.9898) * 43758.5453);
	float line = 1.0 - smoothstep(seam * 0.55, seam, f);
	float soft = smoothstep(seam, 0.55, f) * 0.18 * (1.0 - smoothstep(0.55, 1.0, f));
	ALBEDO = vec3(0.0);
	ALPHA = clamp((line + soft) * strength * uneven, 0.0, 0.8);
}
