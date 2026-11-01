extends Node3D
## The wave itself: a wall of dark water with a foam crest that curls over towards the viewer, drawn
## by one grid mesh whose vertex shader bends it into the wave's profile (a quarter circle of
## swell rolling forward into an overhang), lit by itself (no fog: the street's red fog would
## swallow it at 300 m). Tsunami.gd places it on the horizon at the end of the street, raises it
## and, when the countdown runs out, sends it down the street (debris and all).
##
## Local space: X across the wall, Y up, +Z the front face (towards the viewer).

const NX := 140
const NY := 44
const WIDTH := 1500.0

var mesh_node: MeshInstance3D
var material: ShaderMaterial
var height := 0.0
var _debris: Array[MeshInstance3D] = []
var _debris_spin: Array[Vector3] = []
var _debris_root: Node3D
var _t := 0.0

const SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
uniform float H = 40.0;
uniform float W = 1500.0;
uniform float curl = 0.55;
uniform float flow = 0.0;
uniform float glow = 1.0;
uniform float flash = 0.0;
varying float v_v;
varying vec3 v_n;
varying vec2 v_xy;
varying float v_h;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1 + 3.7) * 0.28 + vnoise(p * 4.3 + 9.1) * 0.14;
}

vec3 prof(float u, float v) {
	float x = (u - 0.5) * W;
	// The crest line wanders: a few big swells and finer ones.
	float h = H * (0.84 + 0.16 * sin(x * 0.0075 + 1.3) + 0.1 * sin(x * 0.021 + 4.0) + 0.05 * sin(x * 0.07));
	h = max(h, 0.001);
	float a = v * 2.35;
	float y = h * sin(a);
	float lean = curl * (0.75 + 0.5 * vnoise(vec2(x * 0.01, 3.0)));
	float z = h * lean * (1.0 - cos(a));
	// the face is a rolling surface, not a sheet
	z += (fbm(vec2(x * 0.03, y * 0.05 + flow * 0.1)) - 0.4) * h * 0.12 * smoothstep(0.0, 0.4, v);
	return vec3(x, y, z);
}

void vertex() {
	float u = UV.x;
	float v = UV.y;
	vec3 p = prof(u, v);
	vec3 pu = prof(u + 0.0008, v);
	vec3 pv = prof(u, v + 0.01);
	vec3 n = normalize(cross(pu - p, pv - p));
	VERTEX = p;
	NORMAL = n;
	v_v = v;
	v_n = n;
	v_xy = vec2(p.x, p.y);
	v_h = H;
}

void fragment() {
	float v = v_v;
	vec3 n = normalize(NORMAL);
	float fres = pow(1.0 - abs(dot(n, VIEW)), 2.2);
	float swell = fbm(vec2(v_xy.x * 0.02, v_xy.y * 0.06 - flow * 0.35));
	vec3 deep = vec3(0.003, 0.016, 0.02);
	vec3 mid = vec3(0.05, 0.2, 0.2);
	vec3 col = mix(deep, mid, smoothstep(0.02, 0.7, v) * (0.35 + 1.1 * swell));
	// broad ridges climbing the face, lit pale from the moon side
	float ridge = pow(vnoise(vec2(v_xy.x * 0.035, v_xy.y * 0.03 - flow * 0.25)), 3.0);
	col += vec3(0.08, 0.26, 0.24) * ridge * smoothstep(0.1, 0.5, v);
	// light coming through the thin water of the curl
	float thin = smoothstep(0.5, 0.88, v);
	col += vec3(0.07, 0.34, 0.27) * thin * (0.35 + 0.9 * fbm(vec2(v_xy.x * 0.05, v * 6.0 - flow * 0.2))) * glow;
	col += vec3(0.05, 0.16, 0.16) * fres * 0.9;
	// streaks of foam sliding down the face, a rope of foam along the crest
	float streak = vnoise(vec2(v_xy.x * 0.16, v * 38.0 + flow * 1.4));
	float streak2 = vnoise(vec2(v_xy.x * 0.5, v * 70.0 + flow * 2.0));
	float foam_face = smoothstep(0.74, 0.9, streak * 0.7 + streak2 * 0.4) * smoothstep(0.3, 0.8, v) * 0.55;
	float crest = smoothstep(0.58, 0.69, v + (fbm(vec2(v_xy.x * 0.06, 2.0)) - 0.5) * 0.12);
	float lip = smoothstep(0.69, 0.98, v) * (0.7 + 0.3 * streak);
	float foam = clamp(foam_face + crest * 0.8 + lip * 0.9, 0.0, 1.0);
	vec3 foam_col = vec3(0.62, 0.74, 0.7) * (0.8 + 0.4 * streak2);
	col = mix(col, foam_col, foam);
	// a mist of spray at the foot
	float mist = smoothstep(0.1, 0.0, v);
	col = mix(col, vec3(0.28, 0.36, 0.35), mist * 0.9);
	col += vec3(flash);
	ALBEDO = col;
}
"""

func _init() -> void:
	name = "TsunamiWave"

func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in NY:
		for i in NX:
			var u0 := float(i) / NX
			var u1 := float(i + 1) / NX
			var v0 := float(j) / NY
			var v1 := float(j + 1) / NY
			# The UVs are the profile coordinates; the vertex shader puts the point where it goes.
			for q in [[u0, v0], [u1, v0], [u0, v1], [u1, v0], [u1, v1], [u0, v1]]:
				st.set_uv(Vector2(q[0], q[1]))
				st.add_vertex(Vector3(0, 0, 0))
	var mesh := st.commit()
	mesh_node = MeshInstance3D.new()
	mesh_node.mesh = mesh
	mesh_node.custom_aabb = AABB(Vector3(-WIDTH, -20.0, -80.0), Vector3(WIDTH * 2.0, 400.0, 400.0))
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	material.shader = sh
	mesh_node.material_override = material
	add_child(mesh_node)
	_build_debris()
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	material.set_shader_parameter("flow", _t * (0.6 + height * 0.01))
	if _debris_root != null and _debris_root.visible:
		for i in _debris.size():
			_debris[i].rotation += _debris_spin[i] * delta

## Puts it `dist` metres from `from`, on the side `dir` (a unit vector on the ground), `h` metres high.
func place(from: Vector3, dir: Vector3, dist: float, h: float) -> void:
	height = h
	visible = h > 0.5
	global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(from.x, 0.0, from.z) + dir * dist)
	if material != null:
		material.set_shader_parameter("H", maxf(h, 0.01))

func set_flash(f: float) -> void:
	if material != null:
		material.set_shader_parameter("flash", f)

## Debris carried on the face of the rushing wave: planks, barrels, wrecks, tumbling.
func _build_debris() -> void:
	_debris_root = Node3D.new()
	_debris_root.name = "Debris"
	_debris_root.visible = false
	add_child(_debris_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.1, 0.075, 0.05)
	wood.roughness = 0.8
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.13, 0.14)
	metal.metallic = 0.4
	metal.roughness = 0.5
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.2, 0.1, 0.06)
	rust.roughness = 0.7
	for i in 46:
		var m := MeshInstance3D.new()
		var kind := rng.randi() % 10
		if kind < 5:
			var b := BoxMesh.new()
			b.size = Vector3(rng.randf_range(2.5, 6.0), 0.25, rng.randf_range(0.3, 0.7))
			m.mesh = b
			m.material_override = wood
		elif kind < 8:
			var c := CylinderMesh.new()
			c.top_radius = 0.45
			c.bottom_radius = 0.45
			c.height = 1.0
			m.mesh = c
			m.material_override = metal
		else:
			# A car, tumbling.
			var b := BoxMesh.new()
			b.size = Vector3(4.4, 1.5, 1.9)
			m.mesh = b
			m.material_override = rust
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(1.5, 22.0), rng.randf_range(2.0, 44.0))
		m.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_debris_root.add_child(m)
		_debris.append(m)
		_debris_spin.append(Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0)))

func show_debris(on: bool) -> void:
	if _debris_root != null:
		_debris_root.visible = on
