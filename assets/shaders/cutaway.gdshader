shader_type spatial;
// Single-sided buildings (the masses, flat walls, glass): see cutaway.gdshaderinc.
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/cutaway.gdshaderinc"
