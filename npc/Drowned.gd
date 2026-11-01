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
const SCALE := 1.9
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
var _helmet_node: MeshInstance3D
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
			if src == null or src.resource_name.ends_with("opacity"):
				continue
			inst.set_surface_override_material(i, _skin_material(src))
		inst.set_instance_shader_parameter("rot", 0.95)

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
	m.set_shader_parameter("rim_color", Vector3(0.3, 0.55, 0.6))
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
	# The helmet: a crust of barnacles over the top of the skull.
	if _helmet_material == null:
		_helmet_material = _make_helmet_material()
	var sph := SphereMesh.new()
	sph.radius = 0.105
	sph.height = 0.105
	sph.is_hemisphere = true
	sph.radial_segments = 28
	sph.rings = 14
	_helmet_node = MeshInstance3D.new()
	_helmet_node.name = "BarnacleHelmet"
	_helmet_node.mesh = sph
	_helmet_node.material_override = _helmet_material
	_helmet_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hat := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), eyes + Vector3(0, 0.022, -0.004))
	_attach("Bip01 Head", hat, _helmet_node)
	# Eyes: two pale lamps and a light that shows the wet skin round them.
	if _eye_material == null:
		_eye_material = StandardMaterial3D.new()
		_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_material.albedo_color = Color(0.72, 1.0, 1.0)
		_eye_material.emission_enabled = true
		_eye_material.emission = Color(0.55, 0.95, 1.0)
		_eye_material.emission_energy_multiplier = 3.0
	for e in [eye_l, eye_r]:
		if e == eyes:
			continue
		var ball := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.0155
		bm.height = 0.031
		bm.radial_segments = 10
		bm.rings = 6
		ball.mesh = bm
		ball.material_override = _eye_material
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_attach("Bip01 Head", Transform3D(Basis(), e + Vector3(0, 0, 0.012)), ball)
		_eye_nodes.append(ball)
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(0.55, 0.92, 1.0)
	_eye_light.light_energy = 0.9
	_eye_light.omni_range = 5.5
	_eye_light.shadow_enabled = false
	_attach("Bip01 Head", Transform3D(Basis(), eyes + Vector3(0, 0.0, 0.12)), _eye_light)
	# Seaweed: strands off the helmet, the shoulders and the back, hanging and swaying.
	if _weed_mesh == null:
		_make_weed()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(get_meta("seed", 0.5) * 100000.0)
	var spots := [
		["Bip01 Head", eyes + Vector3(0.05, 0.05, -0.03), 0.9], ["Bip01 Head", eyes + Vector3(-0.05, 0.05, -0.02), 1.0],
		["Bip01 Head", eyes + Vector3(0.0, 0.07, -0.06), 1.2],
		["Bip01 L Clavicle", _bone_in_model("Bip01 L Clavicle") + Vector3(0.03, 0.0, 0.0), 1.4],
		["Bip01 R Clavicle", _bone_in_model("Bip01 R Clavicle") + Vector3(-0.03, 0.0, 0.0), 1.3],
		["Bip01 Spine1", _bone_in_model("Bip01 Spine1") + Vector3(0.05, 0.1, -0.05), 1.7],
		["Bip01 Spine1", _bone_in_model("Bip01 Spine1") + Vector3(-0.04, 0.12, -0.06), 1.5],
		["Bip01 L UpperArm", _bone_in_model("Bip01 L UpperArm") + Vector3(0.03, 0.0, 0.0), 1.1],
		["Bip01 R UpperArm", _bone_in_model("Bip01 R UpperArm") + Vector3(-0.03, 0.0, 0.0), 1.1],
		["Bip01 Pelvis", _bone_in_model("Bip01 Pelvis") + Vector3(0.06, 0.0, 0.02), 1.3],
		["Bip01 Pelvis", _bone_in_model("Bip01 Pelvis") + Vector3(-0.06, 0.0, -0.02), 1.0],
	]
	for s in spots:
		var strand := MeshInstance3D.new()
		strand.mesh = _weed_mesh
		strand.material_override = _weed_material
		strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var k: float = s[2]
		var tilt := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		tilt = tilt.scaled(Vector3(k, k, k) * rng.randf_range(0.85, 1.25))
		_attach(s[0], Transform3D(tilt, s[1]), strand)

static func _make_helmet_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_back;
varying vec3 v_p;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void vertex() {
	v_p = VERTEX;
	// Barnacles: a field of cones and bumps (cells of the sphere's surface).
	vec3 q = VERTEX * 70.0;
	vec3 cell = floor(q);
	vec3 f = fract(q) - 0.5;
	float r = h3(cell);
	float cone = max(0.0, 0.55 - length(f)) * step(0.35, r) * (0.5 + r);
	VERTEX += NORMAL * cone * 0.05;
}
void fragment() {
	vec3 q = v_p * 70.0;
	vec3 cell = floor(q);
	float r = h3(cell);
	vec3 f = fract(q) - 0.5;
	float top = max(0.0, 0.5 - length(f));
	vec3 shell = mix(vec3(0.55, 0.57, 0.5), vec3(0.78, 0.8, 0.72), r);
	vec3 gap = vec3(0.03, 0.07, 0.06);
	float mussel = step(0.8, h3(cell + 7.0));
	vec3 col = mix(gap, shell, smoothstep(0.05, 0.28, top));
	col = mix(col, vec3(0.04, 0.05, 0.08), mussel * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = vec3(0.26, 0.4, 0.4) * rim * 0.6 + col * 0.1;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

## One ribbon of weed (a strip of quads hanging down; the shader sways and tapers it).
static func _make_weed() -> void:
	var segs := 7
	var length := 0.36
	var width := 0.05
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var y0 := -length * float(i) / segs
		var y1 := -length * float(i + 1) / segs
		var v0 := float(i) / segs
		var v1 := float(i + 1) / segs
		var a := Vector3(-width, y0, 0)
		var b := Vector3(width, y0, 0)
		var c := Vector3(-width, y1, 0)
		var d := Vector3(width, y1, 0)
		st.set_uv(Vector2(0, v0)); st.add_vertex(a)
		st.set_uv(Vector2(1, v0)); st.add_vertex(b)
		st.set_uv(Vector2(0, v1)); st.add_vertex(c)
		st.set_uv(Vector2(1, v0)); st.add_vertex(b)
		st.set_uv(Vector2(1, v1)); st.add_vertex(d)
		st.set_uv(Vector2(0, v1)); st.add_vertex(c)
	st.generate_normals()
	_weed_mesh = st.commit()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled;
varying float v_t;
void vertex() {
	v_t = UV.y;
	float w = UV.y * UV.y;
	float ph = MODEL_MATRIX[3].x * 3.0 + MODEL_MATRIX[3].z * 5.0;
	VERTEX.x += sin(TIME * 2.2 + UV.y * 3.0 + ph) * 0.35 * w;
	VERTEX.z += cos(TIME * 1.7 + UV.y * 2.5 + ph) * 0.3 * w;
	// narrows to a point
	VERTEX.x *= 1.0 - UV.y * 0.7;
}
void fragment() {
	ALBEDO = mix(vec3(0.05, 0.17, 0.07), vec3(0.02, 0.07, 0.04), v_t) * (0.8 + 0.4 * fract(sin(UV.x * 12.0) * 99.0));
	ROUGHNESS = 0.25;
	SPECULAR = 0.7;
	EMISSION = vec3(0.01, 0.04, 0.02);
}
"""
	_weed_material = ShaderMaterial.new()
	_weed_material.shader = sh

func _build_drips() -> void:
	_drips = CPUParticles3D.new()
	_drips.name = "Drips"
	_drips.amount = 22
	_drips.lifetime = 1.1
	_drips.local_coords = false
	_drips.position = Vector3(0, 1.3, 0)
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drips.emission_box_extents = Vector3(0.45, 0.9, 0.3)
	_drips.direction = Vector3.DOWN
	_drips.spread = 12.0
	_drips.gravity = Vector3(0, -9.0, 0)
	_drips.initial_velocity_min = 0.1
	_drips.initial_velocity_max = 0.6
	_drips.scale_amount_min = 0.5
	_drips.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.07)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.billboard_keep_scale = true
	dm.albedo_color = Color(0.62, 0.8, 0.86, 0.75)
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
	quad.size = Vector2(0.09, 0.09)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
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
