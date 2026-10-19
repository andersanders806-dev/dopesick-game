shader_type spatial;
// Double-sided (the facade kits' pieces): see cutaway.gdshaderinc.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/cutaway.gdshaderinc"
