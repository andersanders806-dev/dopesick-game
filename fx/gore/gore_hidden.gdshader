shader_type spatial;
render_mode unshaded, cull_disabled;
// Swapped onto a surface that must vanish (a severed head's hair): draws nothing.
void fragment() {
	discard;
}
