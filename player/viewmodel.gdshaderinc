// The viewmodel's own projection (Godot 4.3+ reverse-Z).
//
// The gun and arms are projected with their own vertical field of view, so
// zooming the world for aiming never grows or shrinks them, and their depth is
// pushed to just under the near plane, so they draw on top of every wall and
// zombie without a second viewport (too dear on an Intel UHD 620).
//
// Reverse-Z: NDC depth 1.0 is the near plane, 0.0 the far plane. A depth of
// 1.0 - 0.01 * distance keeps the viewmodel's parts in order among themselves
// and above any world surface a camera can see (nothing is nearer than near).
vec4 vm_clip(mat4 modelview, mat4 projection, vec3 vertex, float vm_fov_deg) {
	vec4 view = modelview * vec4(vertex, 1.0);
	vec4 clip = projection * view;
	// (The renderer's projection can carry a Y flip: only its size matters here.)
	float world_k = abs(projection[1][1]);
	float vm_k = 1.0 / tan(radians(vm_fov_deg) * 0.5);
	clip.xy *= vm_k / world_k;
	float d = max(-view.z, 0.001);
	clip.z = (1.0 - d * 0.01) * clip.w;
	return clip;
}
