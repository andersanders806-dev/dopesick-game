extends "res://npc/Zombie3D.gd"
## A Drowned: a sea-bloated brute out of the harbour, the two that the tsunami (fx/Tsunami.gd) sends
## and that must both be killed before the countdown ends. A zombie in every respect that matters to
## the rest of the game (the same body pipeline, hit zones, gore, group "zombies", `died`), but
##   - about 2.2 m tall and wide, slow at first, with 25 times a normal zombie's health;
##   - a "helmet" of barnacles on the head: headshots do half until it has taken HELMET_SHARE of its
##     health in damage and breaks off;
##   - staggered only by heavy hits (a sniper round, a point-blank shotgun, the wonder weapon);
##   - a charge: it roars, plants itself and then comes at you at a run in a straight line; if it
##     gets you it hurts and throws you back, if you step aside it runs on and has to turn round;
##   - wet skin (npc/drowned.gdshader), seaweed, pale glowing eyes, dripping, gurgling roars.
## Sounds: assets/sfx/tsunami/drowned_roar_1..2.

const DrownedShader := preload("res://npc/drowned.gdshader")
const SFX_DIR := "res://assets/sfx/tsunami/"
const BIG_BODIES := ["Construction_Male_08", "Male_Adult_11", "Male_Adult_06", "Male_Adult_09"]

## Health compared with a normal zombie of the round.
const HEALTH_MULT := 25.0
const SCALE := 2.1
## Walking pace (m/s); it quickens as the sea gets nearer (`urgency`).
const WALK_SPEED_DROWNED := 1.5
const CLAW_DAMAGE := 50.0
const CHARGE_DAMAGE := 40.0
## The part of its health the helmet takes before it breaks; headshots count this much while it holds.
const HELMET_SHARE := 0.05
const HELMET_HEAD_MULT := 0.5
## A single hit this strong staggers it.
const HEAVY_HIT := 160.0
## Charge: from this far to this far, a roar of WINDUP seconds, then up to RUSH_TIME at up to RUSH_SPEED.
const CHARGE_RANGE := Vector2(5.5, 24.0)
const WINDUP := 1.0
const RUSH_TIME := 1.7
const RUSH_SPEED := 8.5
const RECOVER := 1.4
const CHARGE_PERIOD := Vector2(5.0, 9.0)
## The throw: metres per second at the start, dying away over KNOCK_TIME.
const KNOCK_SPEED := 15.0
const KNOCK_TIME := 0.32
const ROAR_PERIOD := Vector2(6.0, 12.0)
## The hunch pushes the head this far forward and down (in the model's metres; drowned.gdshader).
const HEAD_SHIFT := Vector3(0.0, -0.026, 0.105)
const HELMET_RADIUS := 0.112

enum Charge { NONE, WINDUP, RUSH, RECOVER }

signal helmet_broke(drowned: Node)
signal charged(drowned: Node, hit_player: bool)

var charge: Charge = Charge.NONE
## 1.0 .. 1.6: the sea is coming, it hurries (the Tsunami sets it from the clock).
var urgency := 1.0
var helmet := 0.0
var helmet_max := 0.0
var helmet_on := true
var roars := 0
var charges_made := 0
var charge_hits := 0
## Where it stands in the world on the sea side/etc: free text for the tests and the HUD.
var side := ""

var _charge_t := 0.0
var _charge_cd := 3.0
var _charge_dir := Vector3.FORWARD
var _charge_landed := false
var _base_speed := WALK_SPEED_DROWNED
var _pknock := Vector3.ZERO
var _pknock_t := 0.0
var _roar_t := 6.0
var _step_t := 0.5
var _voice: AudioStreamPlayer3D
var _helmet_node: Node3D
var _puddle: MeshInstance3D
var _eye_light: OmniLight3D
var _eye_nodes: Array[MeshInstance3D] = []
var _drips: CPUParticles3D
var _rise_voice_done := false

static var _skins := {}
static var _roar_streams: Array[AudioStream] = []
static var _weed_mesh: ArrayMesh
static var _weed_material: ShaderMaterial
static var _helmet_material: ShaderMaterial
static var _eye_material: StandardMaterial3D
static var _mouth_material: StandardMaterial3D
static var _plate_material: StandardMaterial3D

## Sets it up before it is added to the tree (the Tsunami does this).
func setup_drowned(round_no: int, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	configure("walker", round_no, rng)
	kind = "drowned"
	body_scale = SCALE
	set_meta("body", BIG_BODIES[rng.randi() % BIG_BODIES.size()])
	max_health = float(ZombieMode.zombie_health(round_no)) * HEALTH_MULT
	health = max_health
	helmet_max = max_health * HELMET_SHARE
	helmet = helmet_max
	_base_speed = WALK_SPEED_DROWNED * rng.randf_range(0.95, 1.1)
	speed = _base_speed
	damage = CLAW_DAMAGE
	_move_clip = "z_walk2"
	_rot_amount = 0.95
	_charge_cd = rng.randf_range(3.0, 6.0)
	_roar_t = rng.randf_range(ROAR_PERIOD.x, ROAR_PERIOD.y)

func _ready() -> void:
	super._ready()
	if get_meta("prewarm", false):
		return
	_wet_skin()
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_voice.unit_size = 16.0
	_voice.max_distance = 160.0
	_voice.volume_db = 2.0
	add_child(_voice)
	_build_gear()
	_build_drips()

# --- The look ---------------------------------------------------------------------------

func _wet_skin() -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var src := inst.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			if src.resource_name.ends_with("opacity"):
				# Hair and lashes would not follow the swollen, hunched head: it is bald, waterlogged.
				inst.set_surface_override_material(i, _hidden_material())
				continue
			inst.set_surface_override_material(i, _skin_material(src))
		inst.set_instance_shader_parameter("rot", 0.95)

static var _hidden: ShaderMaterial

static func _hidden_material() -> Material:
	if _hidden == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nvoid fragment() { discard; }\n"
		_hidden = ShaderMaterial.new()
		_hidden.shader = sh
	return _hidden

static func _skin_material(src: BaseMaterial3D) -> Material:
	if _skins.has(src):
		return _skins[src]
	var m := ShaderMaterial.new()
	m.shader = DrownedShader
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("albedo_color", src.albedo_color)
	m.set_shader_parameter("noise_tex", noise_texture())
	m.set_shader_parameter("kind", 1 if src.resource_name.ends_with("head") else 0)
	m.set_shader_parameter("roughness_base", 0.2)
	m.set_shader_parameter("rim_color", Vector3(0.3, 0.38, 0.36))
	_skins[src] = m
	return m

## Where a bone is, in the model's own (unscaled) space.
func _bone_in_model(bone: String) -> Vector3:
	var i := _skeleton.find_bone(bone)
	if i < 0:
		return Vector3(0, 1.0, 0)
	var world := _skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin
	return _model_root.global_transform.affine_inverse() * world

## Hangs `node` on `bone` so that it sits at `at` (a transform in the model's own space) now and
## follows the bone from then on.
func _attach(bone: String, at: Transform3D, node: Node3D) -> BoneAttachment3D:
	var i := _skeleton.find_bone(bone)
	if i < 0:
		return null
	var att := BoneAttachment3D.new()
	att.name = "On_" + bone.replace(" ", "_")
	att.bone_name = bone
	_skeleton.add_child(att)
	att.add_child(node)
	var to_skeleton := _skeleton.global_transform.affine_inverse() * _model_root.global_transform
	node.transform = _skeleton.get_bone_global_pose(i).affine_inverse() * (to_skeleton * at)
	return att

func _build_gear() -> void:
	if _skeleton == null:
		return
	var head := _bone_in_model("Bip01 Head")
	var eye_l := _bone_in_model("Bip01 LEye")
	var eye_r := _bone_in_model("Bip01 REye")
	var eyes := (eye_l + eye_r) * 0.5 if eye_l != eye_r else head + Vector3(0, 0.06, 0.04)
	# The shader hunches the body and the head goes forward and down with it; what hangs on the head goes too.
	eyes += HEAD_SHIFT
	eye_l += HEAD_SHIFT
	eye_r += HEAD_SHIFT
	_build_helmet(eyes)
	# Eyes: two small pale points, and a faint light that shows the wet skin round them.
	if _eye_material == null:
		_eye_material = StandardMaterial3D.new()
		_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_material.albedo_color = Color(0.85, 1.0, 1.0)
		_eye_material.emission_enabled = true
		_eye_material.emission = Color(0.7, 1.0, 1.0)
		_eye_material.emission_energy_multiplier = 4.0
	for e in [eye_l, eye_r]:
		if e == eyes:
			continue
		var ball := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.0085
		bm.height = 0.017
		bm.radial_segments = 8
		bm.rings = 4
		ball.mesh = bm
		ball.material_override = _eye_material
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_attach("Bip01 Head", Transform3D(Basis(), e + Vector3(0, 0, 0.022)), ball)
		_eye_nodes.append(ball)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(0.6, 0.95, 1.0)
	_eye_light.light_energy = 0.45
	_eye_light.omni_range = 3.5
	_eye_light.shadow_enabled = false
	_attach("Bip01 Head", Transform3D(Basis(), eyes + Vector3(0.0, 0.0, 0.14)), _eye_light)
	# A dark open mouth, hanging.
	if _mouth_material == null:
		_mouth_material = StandardMaterial3D.new()
		_mouth_material.albedo_color = Color(0.015, 0.005, 0.008)
		_mouth_material.roughness = 0.35
	var mouth := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.5
	mm.height = 1.0
	mm.radial_segments = 12
	mm.rings = 6
	mouth.mesh = mm
	mouth.material_override = _mouth_material
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mb := Basis().scaled(Vector3(0.05, 0.062, 0.03))
	_attach("Bip01 Head", Transform3D(mb, eyes + Vector3(0, -0.062, 0.048)), mouth)
	# Seaweed: clumps hanging from the helmet, the shoulders, the back and the hips.
	if _weed_mesh == null:
		_make_weed()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_meta("seed", 0.5) * 100000.0)
	var spots := [
		["Bip01 Head", eyes + Vector3(0.07, 0.07, -0.05), 1.0], ["Bip01 Head", eyes + Vector3(-0.07, 0.07, -0.04), 1.1],
		["Bip01 Head", eyes + Vector3(0.0, 0.09, -0.09), 1.3],
		["Bip01 L Clavicle", _bone_in_model("Bip01 L Clavicle") + Vector3(0.05, 0.0, 0.0), 1.5],
		["Bip01 R Clavicle", _bone_in_model("Bip01 R Clavicle") + Vector3(-0.05, 0.0, 0.0), 1.4],
		["Bip01 Spine1", _bone_in_model("Bip01 Spine1") + Vector3(0.08, 0.1, -0.1), 1.8],
		["Bip01 Spine1", _bone_in_model("Bip01 Spine1") + Vector3(-0.07, 0.12, -0.11), 1.6],
		["Bip01 L UpperArm", _bone_in_model("Bip01 L UpperArm") + Vector3(0.05, 0.0, 0.0), 1.2],
		["Bip01 R UpperArm", _bone_in_model("Bip01 R UpperArm") + Vector3(-0.05, 0.0, 0.0), 1.2],
		["Bip01 L Forearm", _bone_in_model("Bip01 L Forearm") + Vector3(0.04, 0.0, 0.0), 1.0],
		["Bip01 R Forearm", _bone_in_model("Bip01 R Forearm") + Vector3(-0.04, 0.0, 0.0), 1.0],
		["Bip01 Pelvis", _bone_in_model("Bip01 Pelvis") + Vector3(0.1, 0.02, 0.03), 1.4],
		["Bip01 Pelvis", _bone_in_model("Bip01 Pelvis") + Vector3(-0.1, 0.02, -0.03), 1.1],
	]
	for s in spots:
		var strand := MeshInstance3D.new()
		strand.mesh = _weed_mesh
		strand.material_override = _weed_material
		strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var k: float = s[2]
		var tilt := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		tilt = tilt.scaled(Vector3(k, k, k) * rng.randf_range(0.85, 1.25))
		_attach(s[0], Transform3D(tilt, s[1]), strand)
	_build_puddle()

## The barnacle helmet: a dark crust over the top of the skull, studded with plates of shell.
func _build_helmet(eyes: Vector3) -> void:
	if _helmet_material == null:
		_helmet_material = _make_helmet_material()
		_plate_material = StandardMaterial3D.new()
		_plate_material.vertex_color_use_as_albedo = true
		_plate_material.albedo_color = Color.WHITE
		_plate_material.roughness = 0.9
		_plate_material.emission_enabled = true
		_plate_material.emission = Color(0.16, 0.18, 0.16)
		_plate_material.emission_energy_multiplier = 0.5
	_helmet_node = Node3D.new()
	_helmet_node.name = "BarnacleHelmet"
	var sph := SphereMesh.new()
	sph.radius = HELMET_RADIUS
	sph.height = HELMET_RADIUS
	sph.is_hemisphere = true
	sph.radial_segments = 24
	sph.rings = 12
	var cap := MeshInstance3D.new()
	cap.mesh = sph
	cap.material_override = _helmet_material
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_helmet_node.add_child(cap)
	# plates: cones of shell on the dome, outwards, big ones overlapping small
	var cone := CylinderMesh.new()
	cone.top_radius = 0.18
	cone.bottom_radius = 0.5
	cone.height = 0.55
	cone.radial_segments = 7
	cone.rings = 1
	cone.material = _plate_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cone
	var n := 120
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_meta("seed", 0.5) * 100000.0) + 5
	for i in n:
		var big := i < 28
		# a point on the dome (not below the rim)
		var ang := rng.randf() * TAU
		var elev := acos(rng.randf_range(0.0, 1.0))
		var dir := Vector3(sin(elev) * cos(ang), cos(elev), sin(elev) * sin(ang))
		if big:
			dir = Vector3(sin(elev * 0.9) * cos(ang), cos(elev * 0.9), sin(elev * 0.9) * sin(ang))
		var size := rng.randf_range(0.026, 0.04) if big else rng.randf_range(0.011, 0.02)
		var basis := Basis(Quaternion(Vector3.UP, dir))
		basis = basis.scaled(Vector3(size, size * rng.randf_range(0.8, 1.6), size))
		mm.set_instance_transform(i, Transform3D(basis, dir * (HELMET_RADIUS - 0.002)))
		var shade := rng.randf_range(0.5, 0.85)
		var tint := Color(shade, shade * 1.02, shade * 0.92)
		if rng.randf() < 0.14:
			tint = Color(0.05, 0.06, 0.09)
		mm.set_instance_color(i, tint)
	var plates := MultiMeshInstance3D.new()
	plates.multimesh = mm
	plates.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_helmet_node.add_child(plates)
	var hat := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10.0)), eyes + Vector3(0, 0.004, -0.014))
	_attach("Bip01 Head", hat, _helmet_node)

static func _make_helmet_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
varying vec3 v_p;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void vertex() { v_p = VERTEX; }
void fragment() {
	vec3 q = v_p * 38.0;
	vec3 cell = floor(q);
	float r = h3(cell);
	// a dark, wet crust of mussel and rust under the plates
	vec3 col = mix(vec3(0.03, 0.045, 0.05), vec3(0.11, 0.12, 0.11), r * 0.8);
	col = mix(col, vec3(0.04, 0.09, 0.06), step(0.82, h3(cell + 3.0)) * 0.9);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.5;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = vec3(0.12, 0.16, 0.15) * rim + col * 0.2;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## A clump of weed: thick strands (tapered tubes that curve) and a couple of ragged fronds, hanging
## from the origin; the shader sways them.
static func _make_weed() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sides := 5
	var segs := 7
	for t in 6:
		var length := rng.randf_range(0.26, 0.5)
		var r0 := rng.randf_range(0.006, 0.011)
		var base := Vector3(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.01, 0.01), rng.randf_range(-0.03, 0.03))
		var bend := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * 0.09
		var rings: Array = []
		for j in segs + 1:
			var u := float(j) / segs
			var c := base + Vector3(0, -length * u, 0) + bend * u * u + Vector3(sin(u * 5.0 + t) * 0.012 * u, 0, 0)
			var rad := r0 * (1.0 - 0.85 * u)
			var ring: Array = []
			for k in sides:
				var a := TAU * float(k) / sides
				ring.append(c + Vector3(cos(a) * rad, 0, sin(a) * rad))
			rings.append(ring)
		for j in segs:
			for k in sides:
				var k2 := (k + 1) % sides
				var a: Vector3 = rings[j][k]
				var b: Vector3 = rings[j][k2]
				var c2: Vector3 = rings[j + 1][k]
				var d: Vector3 = rings[j + 1][k2]
				var col := Color(0, 0, 0, 0)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(a)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(b)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(c2)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(b)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(d)
				st.set_color(col); st.set_uv(Vector2(0, 0)); st.add_vertex(c2)
	# fronds: wide ragged ribbons, cut out by the shader (alpha in the colour's w)
	for f in 3:
		var length := rng.randf_range(0.3, 0.45)
		var width := rng.randf_range(0.035, 0.05)
		var yaw := rng.randf() * PI
		var side := Vector3(cos(yaw), 0, sin(yaw)) * width
		var sway := Vector3(-sin(yaw), 0, cos(yaw)) * rng.randf_range(-0.05, 0.05)
		var segs2 := 6
		for j in segs2:
			var u0 := float(j) / segs2
			var u1 := float(j + 1) / segs2
			var p0 := Vector3(0, -length * u0, 0) + sway * u0 * u0
			var p1 := Vector3(0, -length * u1, 0) + sway * u1 * u1
			var col := Color(1, 0, 0, 1)
			st.set_color(col); st.set_uv(Vector2(0, u0)); st.add_vertex(p0 - side)
			st.set_color(col); st.set_uv(Vector2(1, u0)); st.add_vertex(p0 + side)
			st.set_color(col); st.set_uv(Vector2(0, u1)); st.add_vertex(p1 - side)
			st.set_color(col); st.set_uv(Vector2(1, u0)); st.add_vertex(p0 + side)
			st.set_color(col); st.set_uv(Vector2(1, u1)); st.add_vertex(p1 + side)
			st.set_color(col); st.set_uv(Vector2(0, u1)); st.add_vertex(p1 - side)
	st.generate_normals()
	_weed_mesh = st.commit()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
varying float v_frond;
varying float v_len;
float h1(float x) { return fract(sin(x * 91.3) * 43758.5453); }
void vertex() {
	v_frond = COLOR.r;
	v_len = clamp(-VERTEX.y / 0.4, 0.0, 1.0);
	float ph = MODEL_MATRIX[3].x * 3.0 + MODEL_MATRIX[3].z * 5.0;
	float w = v_len * v_len;
	VERTEX.x += sin(TIME * 2.0 + v_len * 3.0 + ph) * 0.03 * w;
	VERTEX.z += cos(TIME * 1.6 + v_len * 2.5 + ph) * 0.025 * w;
}
void fragment() {
	if (v_frond > 0.5) {
		// a ragged leaf: narrows, with torn edges
		float e = abs(UV.x - 0.5) * 2.0;
		float env = smoothstep(0.0, 0.1, UV.y) * (1.0 - UV.y * 0.75);
		float tear = 0.78 + 0.22 * sin(UV.y * 38.0 + UV.x * 3.0) * sin(UV.y * 17.0);
		if (e > env * tear) {
			discard;
		}
	}
	vec3 dark = mix(vec3(0.045, 0.1, 0.05), vec3(0.015, 0.035, 0.02), v_len);
	ALBEDO = dark * (0.8 + 0.5 * h1(floor(v_len * 9.0) + MODEL_MATRIX[3].x));
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	CLEARCOAT = 0.4;
	CLEARCOAT_ROUGHNESS = 0.2;
	EMISSION = vec3(0.01, 0.025, 0.012);
}
"""
	_weed_material = ShaderMaterial.new()
	_weed_material.shader = sh

## A dark pool of water under it.
func _build_puddle() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.orientation = PlaneMesh.FACE_Y
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.85))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.55, Color(1, 1, 1, 0.7))
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	var m := StandardMaterial3D.new()
	m.albedo_texture = g
	m.albedo_color = Color(0.012, 0.03, 0.034)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	_puddle = MeshInstance3D.new()
	_puddle.name = "Puddle"
	_puddle.mesh = quad
	_puddle.position = Vector3(0, 0.035, 0)
	_puddle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puddle)

## Water off the body: a steady fall of drops and streaks.
func _build_drips() -> void:
	_drips = CPUParticles3D.new()
	_drips.name = "Drips"
	_drips.amount = 64
	_drips.lifetime = 1.0
	_drips.local_coords = false
	_drips.position = Vector3(0, 1.4, 0)
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drips.emission_box_extents = Vector3(0.5, 0.95, 0.32)
	_drips.direction = Vector3.DOWN
	_drips.spread = 10.0
	_drips.gravity = Vector3(0, -10.0, 0)
	_drips.initial_velocity_min = 0.1
	_drips.initial_velocity_max = 0.7
	_drips.scale_amount_min = 0.6
	_drips.scale_amount_max = 1.3
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.11)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.albedo_texture = _dot_texture()
	dm.albedo_color = Color(0.7, 0.85, 0.88, 0.8)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = dm
	_drips.mesh = quad
	add_child(_drips)

# --- Sound ----------------------------------------------------------------------------------

func roar(loud := 0.0, pitch := 1.0) -> void:
	if _voice == null or not is_inside_tree():
		return
	if _roar_streams.is_empty():
		for n in ["drowned_roar_1", "drowned_roar_2"]:
			_roar_streams.append(load(SFX_DIR + n + ".wav") as AudioStream)
	_voice.stream = _roar_streams[roars % _roar_streams.size()]
	_voice.pitch_scale = pitch * randf_range(0.88, 1.05)
	_voice.volume_db = 2.0 + loud
	_voice.play()
	roars += 1

# --- The brain ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state < State.DYING:
		_charge_cd -= delta
		_roar_t -= delta
		if _roar_t <= 0.0 and charge == Charge.NONE and state != State.ENTER:
			_roar_t = randf_range(ROAR_PERIOD.x, ROAR_PERIOD.y)
			roar(-3.0, 0.9)
		_step_thud(delta)
	if _pknock_t > 0.0:
		_apply_player_knock(delta)
	if _puddle != null:
		_puddle.visible = state != State.ENTER
	super._physics_process(delta)

## A footfall you feel: a thud and a little shake when it is near.
func _step_thud(delta: float) -> void:
	if state != State.CHASE or charge == Charge.WINDUP:
		return
	var v := Vector2(velocity.x, velocity.z).length()
	if v < 0.4:
		return
	_step_t -= delta * v / 1.5
	if _step_t > 0.0:
		return
	_step_t = 0.8
	var player := target as Node3D
	if player == null:
		return
	var d := player.global_position.distance_to(global_position)
	if d < 14.0:
		var feel = player.get("feel")
		if feel != null and Graphics.camera_motion:
			feel.add_trauma(0.045 * (1.0 - d / 14.0) * (2.0 if charge == Charge.RUSH else 1.0))

func _chase(delta: float) -> Vector3:
	if target == null or not is_instance_valid(target):
		return super._chase(delta)
	match charge:
		Charge.WINDUP:
			return _windup(delta)
		Charge.RUSH:
			return _rush(delta)
		Charge.RECOVER:
			_charge_t -= delta
			if _charge_t <= 0.0:
				charge = Charge.NONE
				_charge_cd = randf_range(CHARGE_PERIOD.x, CHARGE_PERIOD.y)
			return Vector3.ZERO
	if _stagger <= 0.0:
		speed = _base_speed * urgency
		if _charge_cd <= 0.0 and legless == false:
			var to := target.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d > CHARGE_RANGE.x and d < CHARGE_RANGE.y and not _blocked(to.normalized() * 4.0) and _line_free(to):
				_start_windup(to)
				return Vector3.ZERO
	return super._chase(delta)

## A clear run at the target (nothing solid between).
func _line_free(to: Vector3) -> bool:
	var from := global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, target.global_position + Vector3(0, 1.0, 0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _start_windup(to: Vector3) -> void:
	charge = Charge.WINDUP
	_charge_t = WINDUP
	_charge_dir = to.normalized()
	_charge_landed = false
	_stagger = WINDUP + 0.05
	var dur := anim.play_once("z_scream", 2.4)
	_charge_t = maxf(WINDUP, minf(dur, 1.3))
	_stagger = _charge_t + 0.05
	roar(6.0, 0.8)
	if _eye_light != null:
		_eye_light.light_energy = 3.2
	var player := target as Node3D
	if player != null and player.get("feel") != null and Graphics.camera_motion:
		player.get("feel").add_trauma(0.18)

func _windup(delta: float) -> Vector3:
	_charge_t -= delta
	var to := target.global_position - global_position
	to.y = 0.0
	_face(to, delta * 3.0)
	_stagger = maxf(_stagger, 0.05)
	if _charge_t <= 0.0:
		charge = Charge.RUSH
		_charge_t = RUSH_TIME
		_stagger = 0.0
		charges_made += 1
		_move_clip = "z_run"
		anim.play("z_run", 0.9)
	return Vector3.ZERO

func _rush(delta: float) -> Vector3:
	_charge_t -= delta
	var to := target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	# It can turn a little while it runs, not enough to follow a sidestep.
	if to.length() > 0.1:
		var want := to.normalized()
		var step := clampf(1.3 * delta, 0.0, 1.0)
		_charge_dir = _charge_dir.slerp(want, step).normalized() if _charge_dir.dot(want) > -0.99 else _charge_dir
	var elapsed := RUSH_TIME - _charge_t
	speed = lerpf(4.0, RUSH_SPEED, clampf(elapsed / 0.5, 0.0, 1.0))
	if d < 2.2 and not _charge_landed:
		_charge_landed = true
		_hit_with_charge(to)
		_end_rush(true)
		return Vector3.ZERO
	var passed := _charge_dir.dot(to) < -1.0
	if _charge_t <= 0.0 or passed:
		_end_rush(false)
		return Vector3.ZERO
	# Ran into something: it hurts.
	if elapsed > 0.45 and Vector2(velocity.x, velocity.z).length() < 1.5:
		_end_rush(false, true)
		return Vector3.ZERO
	return _charge_dir

func _end_rush(landed: bool, crashed := false) -> void:
	charge = Charge.RECOVER
	_charge_t = RECOVER + (0.8 if crashed else 0.0)
	_move_clip = "z_walk2"
	speed = _base_speed * urgency
	_stagger = _charge_t
	velocity = Vector3.ZERO
	if _eye_light != null:
		_eye_light.light_energy = 0.9
	if crashed:
		anim.play_once("z_hit_head", 0.8)
		roar(-2.0, 1.2)
		var player := target as Node3D
		if player != null and player.get("feel") != null and Graphics.camera_motion:
			player.get("feel").add_trauma(0.3)
	else:
		anim.play("z_idle", 0.8)
	charged.emit(self, landed)

func _hit_with_charge(to: Vector3) -> void:
	charge_hits += 1
	attacked.emit(self, CHARGE_DAMAGE)
	var dir := to.normalized() if to.length() > 0.01 else _charge_dir
	if target.is_in_group("player") and ZombieMode.gore_enabled:
		var gore := Gore.of(self)
		if gore != null:
			gore.screen_blood(1.6)
	if target.has_method("take_zombie_hit"):
		target.take_zombie_hit(CHARGE_DAMAGE, self)
	_pknock = dir * KNOCK_SPEED
	_pknock_t = KNOCK_TIME
	var feel = target.get("feel")
	if feel != null:
		feel.add_trauma(0.75 if Graphics.camera_motion else 0.2)
	elif target.has_method("kick") and Graphics.camera_motion:
		target.kick(2.0)
	roar(2.0, 0.7)

## The throw: the player carried back, stopping at walls (move_and_collide).
func _apply_player_knock(delta: float) -> void:
	_pknock_t = maxf(_pknock_t - delta, 0.0)
	if target == null or not is_instance_valid(target) or not (target is CharacterBody3D):
		_pknock_t = 0.0
		return
	var k := _pknock_t / KNOCK_TIME
	(target as CharacterBody3D).move_and_collide(_pknock * k * delta)

# --- Hits -------------------------------------------------------------------------------------

func take_hit(part: String, dmg: float, dir: Vector3, weapon: Resource = null, melee := false, at := Vector3.INF) -> void:
	if state >= State.DYING:
		return
	if part == "head" and helmet_on and not ZombieMode.insta_kill:
		dmg *= HELMET_HEAD_MULT
		helmet -= dmg
		if helmet <= 0.0:
			_break_helmet(dir)
	super.take_hit(part, dmg, dir, weapon, melee, at)

func _break_helmet(dir: Vector3) -> void:
	helmet_on = false
	helmet = 0.0
	if _helmet_node != null:
		_helmet_node.visible = false
		_shower(_helmet_node.global_position, dir)
	roar(4.0, 1.1)
	_stagger = maxf(_stagger, 0.5)
	if state == State.CHASE and charge == Charge.NONE:
		anim.play_once("z_hit_head", 1.0)
	helmet_broke.emit(self)

## The helmet's pieces fly: pale shell chips and dark specks.
func _shower(at: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 40
	p.lifetime = 1.2
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (-dir.normalized() if dir.length() > 0.01 else Vector3.UP) + Vector3.UP * 0.6
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.02, 0.03)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.72, 0.64)
	m.roughness = 0.9
	box.material = m
	p.mesh = box
	get_parent().add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

## Only a heavy hit makes it stagger; a bullet is a bee sting.
func _react(part: String, dmg: float) -> void:
	if dmg < HEAVY_HIT or state != State.CHASE or charge != Charge.NONE:
		return
	_stagger = 0.55
	anim.play_once("z_hit_knockback", 1.3)

func _begin_kneel() -> void:
	pass

## It stays on its feet (a crawling brute would be a different creature).
func set_legless(_on := true) -> void:
	pass

func _die(part: String, melee: bool, dir: Vector3) -> void:
	charge = Charge.NONE
	_pknock_t = 0.0
	super._die(part, melee, dir)
	roar(6.0, 0.6)
	if _drips != null:
		_drips.emitting = false
	if _eye_light != null:
		_eye_light.light_energy = 0.0
	for e in _eye_nodes:
		e.visible = false
	_death_splash()
	var player := target as Node3D
	if player != null and player.get("feel") != null and Graphics.camera_motion:
		var d := player.global_position.distance_to(global_position)
		if d < 25.0:
			player.get("feel").add_trauma(0.4 * (1.0 - d / 25.0))

static var _dot: Texture2D

## A soft round dot for the splash (a plain quad would be a square).
static func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := GradientTexture2D.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.width = 32
		g.height = 32
		_dot = g
	return _dot

## Collapsing, it lets go of the sea in it: a heavy splash and a pool.
func _death_splash() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 90
	p.lifetime = 1.0
	p.explosiveness = 0.9
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -10.0, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.albedo_texture = _dot_texture()
	dm.albedo_color = Color(0.6, 0.8, 0.85, 0.8)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = dm
	p.mesh = quad
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 0.9, 0)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)

# --- Climbing out of the ground: deeper and slower than the dead's ------------------------------

const BIG_RISE_TIME := 3.0
const BIG_RISE_DEPTH := 3.0

func begin_entrance(e: Dictionary) -> void:
	super.begin_entrance(e)
	if entrance == "rise":
		_model_root.position.y = -BIG_RISE_DEPTH
		if not _rise_voice_done:
			_rise_voice_done = true
			roar(4.0, 0.75)

func _enter_tick(delta: float) -> void:
	if entrance != "rise":
		super._enter_tick(delta)
		return
	_enter_t += delta
	var k := clampf(_enter_t / BIG_RISE_TIME, 0.0, 1.0)
	var u := smoothstep(0.15, 1.0, k)
	_model_root.position.y = -BIG_RISE_DEPTH * (1.0 - u)
	if k >= 1.0:
		_finish_entrance(0.5)
