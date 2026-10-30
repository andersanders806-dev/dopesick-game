extends Node3D
## The gun in your hands in first person, and the arms holding it.
##
## Every mesh under it wears player/viewmodel.gdshader (its own projection and a
## depth just under the near plane), so it never clips into a wall or a zombie
## and zooming the world for aiming never grows it. No shadows. WeaponHolder
## builds one per gun (setup(data)); player/FPFeel.gd moves it.
##
## Space: this node's origin is the gun's pivot (near the grip), -Z the way it
## shoots. The arms are skinned to a Rocketbox skeleton (assets/viewmodel/arms.glb,
## cut from Male_Adult_20 by dev-tools/make_fp_arms.py) and reach for the gun
## with two-bone IK: the right hand on the grip, the left on the foregrip, or
## wherever FPFeel sends it for a reload.

const WD := preload("res://weapons/WeaponData.gd")
const GunModel := preload("res://weapons/GunModel.gd")
const SHADER := preload("res://player/viewmodel.gdshader")
const FX_SHADER := preload("res://player/viewmodel_fx.gdshader")
const ARMS_SCENE := "res://assets/viewmodel/arms.glb"
## Vertical field of view the gun and arms are drawn with (research: 55 to 65).
const VM_FOV := 60.0
const ARM_NEAR_CUT := 0.12

## Where the hands go on each gun, as fractions of the gun's box
## (x across, y up, z from the muzzle (0) to the back (1)), right hand then left:
## the grip, and the foregrip / support.
const HANDS := {
	"pistol": [Vector3(0.5, 0.22, 0.60), Vector3(-0.9, 0.12, 0.62)],
	"magnum": [Vector3(0.5, 0.20, 0.72), Vector3(-0.9, 0.12, 0.72)],
	"smg": [Vector3(0.5, 0.20, 0.70), Vector3(0.5, 0.30, 0.42)],
	"ar": [Vector3(0.5, 0.18, 0.66), Vector3(0.5, 0.22, 0.42)],
	"lmg": [Vector3(0.5, 0.18, 0.62), Vector3(0.5, 0.22, 0.44)],
	"shotgun": [Vector3(0.5, 0.35, 0.68), Vector3(0.5, 0.30, 0.46)],
	"sniper": [Vector3(0.5, 0.30, 0.66), Vector3(0.5, 0.25, 0.46)],
	"wonder": [Vector3(0.5, 0.20, 0.72), Vector3(0.5, 0.30, 0.46)],
}

var data: WD
var gun: Node3D
## The gun's visible box, in this node's space.
var box := AABB()
var muzzle := Vector3.ZERO
var eject_port := Vector3.ZERO
var grip_r := Vector3.ZERO
var grip_l := Vector3.ZERO
var magwell := Vector3.ZERO
var belt := Vector3.ZERO
## Camera-space position of this node that puts the sights on the view's axis.
var ads_position := Vector3(0.0, -0.1, -0.3)
var flash: Node3D
var arms: Node3D
var mag_prop: Node3D
var _skeleton: Skeleton3D
var _flash_mats: Array[ShaderMaterial] = []
var _fingers := {}
var _arm_cfg := {}

func setup(d: WD) -> Node3D:
	data = d
	name = "Viewmodel"
	gun = GunModel.build(d)
	add_child(gun)
	box = GunModel.bounds(gun.get_child(0) as Node3D, gun)
	_convert(gun)
	_measure()
	_build_flash()
	_build_props()
	_build_arms()
	return self

# --- Materials: every surface on the depth shader ----------------------------------

static func material_for(src: Material) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("viewmodel_fov", VM_FOV)
	var b := src as BaseMaterial3D
	if b != null:
		m.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture != null:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("roughness", b.roughness if b.roughness_texture == null else 1.0)
		m.set_shader_parameter("metallic", b.metallic if b.metallic_texture == null else 1.0)
		var orm: Texture2D = b.roughness_texture if b.roughness_texture != null else b.metallic_texture
		if orm != null:
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("use_orm", true)
		if b.normal_enabled and b.normal_texture != null:
			m.set_shader_parameter("normal_tex", b.normal_texture)
			m.set_shader_parameter("use_normal", true)
		if b.emission_enabled:
			m.set_shader_parameter("emission_color", b.emission)
			m.set_shader_parameter("emission_amount", b.emission_energy_multiplier)
			if b.emission_texture != null:
				m.set_shader_parameter("emission_tex", b.emission_texture)
				m.set_shader_parameter("use_emission_tex", true)
	return m

## Puts every mesh under `node` on the viewmodel shader, shadows off. The
## upgraded guns' tint becomes the shader's glow instead of an overlay (which
## would be drawn with the world's projection).
func _convert(node: Node, cut := 0.05) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_overlay = null
		if m.material_override != null:
			# Kit-built parts (the wonder weapon) carry one material for the lot.
			var one := material_for(m.material_override)
			one.set_shader_parameter("near_cut", cut)
			if data != null and data.tint.a > 0.0:
				one.set_shader_parameter("glow_color", Color(data.tint.r, data.tint.g, data.tint.b))
				one.set_shader_parameter("glow_amount", 0.9)
			m.material_override = one
			continue
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			# Glass and the like are left out rather than drawn as solid.
			if src is BaseMaterial3D and (src as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and (src as BaseMaterial3D).albedo_color.a < 0.5:
				pass
			var mat := material_for(src)
			mat.set_shader_parameter("near_cut", cut)
			if data != null and data.tint.a > 0.0:
				mat.set_shader_parameter("glow_color", Color(data.tint.r, data.tint.g, data.tint.b))
				mat.set_shader_parameter("glow_amount", 0.9)
			m.set_surface_override_material(s, mat)

## Every material the viewmodel draws with (the tests check each is on the shader).
func materials() -> Array:
	var out := []
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			out.append(m.get_active_material(s))
	return out

# --- Where things are on the gun -----------------------------------------------------

func _measure() -> void:
	var f: String = data.family() if data != null else "pistol"
	var b := box
	if b.size.length() < 0.001:
		b = AABB(Vector3(-0.03, -0.05, -0.3), Vector3(0.06, 0.12, 0.45))
		box = b
	muzzle = Vector3(b.position.x + b.size.x * 0.5, b.position.y + b.size.y * 0.72, b.position.z - 0.005)
	eject_port = Vector3(b.position.x + b.size.x * 0.9, b.position.y + b.size.y * 0.7, b.position.z + b.size.z * 0.5)
	var hands: Array = HANDS.get(f, HANDS["ar"])
	grip_r = _in_box(hands[0])
	grip_l = _in_box(hands[1])
	magwell = Vector3(b.position.x + b.size.x * 0.5, b.position.y + b.size.y * 0.1, b.position.z + b.size.z * 0.55)
	belt = magwell + Vector3(-0.12, -0.15, 0.06)
	# The top of the gun on the view's axis, its back end a hand's width from the eye.
	var sight_y := b.end.y - 0.004
	var eye_gap: float = {"pistol": 0.34, "magnum": 0.34, "smg": 0.28, "ar": 0.30, "lmg": 0.30, "shotgun": 0.28, "sniper": 0.14, "wonder": 0.3}.get(f, 0.3)
	ads_position = Vector3(-(b.position.x + b.size.x * 0.5), -sight_y, -(eye_gap + b.end.z))

func _in_box(frac: Vector3) -> Vector3:
	return Vector3(box.position.x + box.size.x * frac.x, box.position.y + box.size.y * frac.y, box.position.z + box.size.z * (1.0 - frac.z))

# --- The muzzle flash: two crossed quads on the barrel ---------------------------

func _build_flash() -> void:
	flash = Node3D.new()
	flash.name = "MuzzleFlash"
	flash.position = muzzle
	flash.visible = false
	add_child(flash)
	for i in 2:
		var q := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * 0.2
		q.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = FX_SHADER
		mat.set_shader_parameter("viewmodel_fov", VM_FOV)
		mat.set_shader_parameter("spikes", 5.0 if i == 0 else 7.0)
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.rotation_degrees.y = 90.0 * i
		flash.add_child(q)
		_flash_mats.append(mat)

## Shows the flash for a frame or two: a random twist and size each shot, bigger
## for the heavy guns.
func show_flash(rng: RandomNumberGenerator, size: float) -> void:
	flash.visible = true
	flash.rotation.z = rng.randf() * TAU
	flash.scale = Vector3.ONE * size * rng.randf_range(0.8, 1.25)
	for m in _flash_mats:
		m.set_shader_parameter("spin", rng.randf() * TAU)
		m.set_shader_parameter("intensity", rng.randf_range(0.85, 1.2))

func hide_flash() -> void:
	flash.visible = false

# --- Reload props: the magazine (or shell) the left hand brings ---------------------

func _build_props() -> void:
	mag_prop = Node3D.new()
	mag_prop.name = "MagProp"
	mag_prop.visible = false
	add_child(mag_prop)
	var shell := data != null and data.family() == "shotgun"
	var metal := ShaderMaterial.new()
	metal.shader = SHADER
	metal.set_shader_parameter("viewmodel_fov", VM_FOV)
	if shell:
		metal.set_shader_parameter("albedo", Color(0.62, 0.1, 0.08))
		metal.set_shader_parameter("roughness", 0.5)
		var body := CylinderMesh.new()
		body.top_radius = 0.0105
		body.bottom_radius = 0.0105
		body.height = 0.07
		_prop_part(body, metal, Vector3.ZERO, Vector3(90, 0, 0))
		var brass := ShaderMaterial.new()
		brass.shader = SHADER
		brass.set_shader_parameter("viewmodel_fov", VM_FOV)
		brass.set_shader_parameter("albedo", Color(0.8, 0.62, 0.25))
		brass.set_shader_parameter("metallic", 0.9)
		brass.set_shader_parameter("roughness", 0.35)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0112
		cap.bottom_radius = 0.0112
		cap.height = 0.018
		_prop_part(cap, brass, Vector3(0, 0, 0.026), Vector3(90, 0, 0))
	else:
		metal.set_shader_parameter("albedo", Color(0.09, 0.09, 0.1))
		metal.set_shader_parameter("metallic", 0.7)
		metal.set_shader_parameter("roughness", 0.45)
		var long := 0.07 if data != null and data.family() in ["pistol", "magnum"] else 0.13
		var body := BoxMesh.new()
		body.size = Vector3(0.026, long, 0.05)
		_prop_part(body, metal, Vector3.ZERO, Vector3(8, 0, 0))
		var rim := BoxMesh.new()
		rim.size = Vector3(0.03, 0.012, 0.054)
		_prop_part(rim, metal, Vector3(0, long * 0.5, 0.0), Vector3(8, 0, 0))

func _prop_part(mesh: Mesh, mat: Material, at: Vector3, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mag_prop.add_child(mi)

# --- The arms ------------------------------------------------------------------------

func _build_arms() -> void:
	var ps := load(ARMS_SCENE) as PackedScene
	if ps == null:
		return
	arms = ps.instantiate() as Node3D
	arms.name = "Arms"
	add_child(arms)
	_skeleton = arms.find_child("Skeleton3D", true, false) as Skeleton3D
	# Nothing of an arm nearer than this to the eye is drawn: the upper arms stay out of the picture.
	_convert(arms, ARM_NEAR_CUT)
	if _skeleton == null:
		return
	_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	var ap := arms.find_child("AnimationPlayer", true, false)
	if ap != null:
		ap.queue_free()
	_fit_arms()

# --- Two-bone IK: the hands on the gun -------------------------------------------------
#
# The arms are skinned to Rocketbox's Bip01 skeleton (units: centimetres, the
# bone's own X axis runs down the bone, the fingers curl about their Z axis).
# Each arm is set, bone by bone, in the skeleton's space: the shoulder end is
# wherever it has to be for the hand to reach (the shoulder is out of the
# picture), the elbow comes from the law of cosines with a pole pointing down
# and out, the wrist sits on the gun's grip.

## Arm scale against the avatar's own (first-person arms are always big: the
## viewmodel's narrow field of view and the short reach to the gun need it).
const ARM_SCALE := 1.3
## Shoulders, camera space.
const SHOULDER_R := Vector3(0.20, -0.40, 0.0)
const SHOULDER_L := Vector3(-0.20, -0.40, 0.0)
## Roll of each hand about its own length, degrees (tuned on screen).
const HAND_ROLL := {"R": 0.0, "L": 0.0}
## Finger curl about the Z axis, degrees [base, middle, tip] and the thumb's.
const GRIP_CURL := {"R": [58.0, 70.0, 42.0], "L": [50.0, 62.0, 40.0]}
const THUMB_CURL := {"R": [12.0, 18.0], "L": [6.0, 10.0]}
const CURL_SIGN := 1.0

func _fit_arms() -> void:
	arms.rotation.y = PI * 0.5
	arms.scale = Vector3.ONE * ARM_SCALE
	for side in ["R", "L"]:
		var a := {}
		a["upper"] = _skeleton.find_bone("Bip01 %s UpperArm" % side)
		a["fore"] = _skeleton.find_bone("Bip01 %s Forearm" % side)
		a["hand"] = _skeleton.find_bone("Bip01 %s Hand" % side)
		var ou: Vector3 = _skeleton.get_bone_global_rest(a["upper"]).origin
		var of: Vector3 = _skeleton.get_bone_global_rest(a["fore"]).origin
		var oh: Vector3 = _skeleton.get_bone_global_rest(a["hand"]).origin
		a["l1"] = ou.distance_to(of)
		a["l2"] = of.distance_to(oh)
		var fingers := []
		for f in range(5):
			var base := "Bip01 %s Finger%d" % [side, f]
			fingers.append([_skeleton.find_bone(base), _skeleton.find_bone(base + "1"), _skeleton.find_bone(base + "2")])
		a["fingers"] = fingers
		_arm[side] = a

var _arm := {}

## The skeleton's pose with the hands where they go. `left` is the left hand's
## target on the gun (this node's space); the right is on the grip. Reads the
## node's own transform for where the camera-fixed shoulders are.
func aim_hands(left: Vector3) -> void:
	if _skeleton == null or _arm.is_empty():
		return
	var cam_to_vm := transform.affine_inverse()
	_solve("R", cam_to_vm * SHOULDER_R, grip_r, Vector3(0.25, -1.0, 0.0))
	_solve("L", cam_to_vm * SHOULDER_L, left, Vector3(-0.25, -1.0, 0.0))

func _solve(side: String, shoulder_vm: Vector3, wrist_vm_target: Vector3, pole_vm: Vector3) -> void:
	var a: Dictionary = _arm[side]
	# vm space -> arms space -> skeleton space (centimetres).
	var to_sk := (arms.transform * _skeleton_in_arms()).affine_inverse()
	var sh: Vector3 = to_sk * shoulder_vm
	var hand_dir_vm := (wrist_vm_target - shoulder_vm).normalized()
	# The hand's long axis: along the forearm, tipped down onto the grip.
	var palm := 0.05
	var target_vm := wrist_vm_target - (hand_dir_vm + Vector3(0, -0.3, 0)).normalized() * palm
	var t: Vector3 = to_sk * target_vm
	var l1: float = a["l1"]
	var l2: float = a["l2"]
	var reach := (l1 + l2) * 0.985
	var to_t := t - sh
	if to_t.length() > reach:
		sh = t - to_t.normalized() * reach
		to_t = t - sh
	var d := maxf(to_t.length(), absf(l1 - l2) + 0.5)
	var dir := to_t / maxf(to_t.length(), 0.0001)
	var pole: Vector3 = (to_sk.basis * pole_vm).normalized()
	var perp := (pole - dir * pole.dot(dir))
	perp = perp.normalized() if perp.length() > 0.001 else Vector3.UP
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var elbow := sh + dir * along + perp * h
	# Bones: each turned from its rest direction onto its new one.
	var up_rest: Transform3D = _skeleton.get_bone_global_rest(a["upper"])
	var fo_rest: Transform3D = _skeleton.get_bone_global_rest(a["fore"])
	var ha_rest: Transform3D = _skeleton.get_bone_global_rest(a["hand"])
	var up_basis := _aim_bone(up_rest.basis, (elbow - sh).normalized())
	var fo_basis := _aim_bone(fo_rest.basis, (t - elbow).normalized())
	var ha_dir := (to_sk.basis * (hand_dir_vm + Vector3(0, -0.3, 0))).normalized()
	var ha_basis := _aim_bone(ha_rest.basis, ha_dir)
	ha_basis = Basis(ha_dir, deg_to_rad(HAND_ROLL[side])) * ha_basis
	_skeleton.set_bone_global_pose(a["upper"], Transform3D(up_basis, sh))
	_skeleton.set_bone_global_pose(a["fore"], Transform3D(fo_basis, elbow))
	_skeleton.set_bone_global_pose(a["hand"], Transform3D(ha_basis, t))
	_curl(a, side)

## `rest` turned the shortest way so its X axis (down the bone) points along `dir`.
func _aim_bone(rest: Basis, dir: Vector3) -> Basis:
	var x := rest.x.normalized()
	var q := Quaternion(x, dir) if x.dot(dir) > -0.9999 else Quaternion(rest.y.normalized(), PI)
	return Basis(q) * rest

var _sk_in_arms := Transform3D.IDENTITY
var _sk_known := false

## Where the skeleton sits inside the arms node (fixed; read once, in the tree).
func _skeleton_in_arms() -> Transform3D:
	if not _sk_known and arms.is_inside_tree():
		_sk_in_arms = arms.global_transform.affine_inverse() * _skeleton.global_transform
		_sk_known = true
	return _sk_in_arms

## Fingers closed round the gun: each segment bent about its own Z axis.
func _curl(a: Dictionary, side: String) -> void:
	var curl: Array = GRIP_CURL[side]
	var thumb: Array = THUMB_CURL[side]
	var fingers: Array = a["fingers"]
	for f in range(fingers.size()):
		var chain: Array = fingers[f]
		for k in range(chain.size()):
			var idx: int = chain[k]
			if idx < 0:
				continue
			var ang: float = (thumb[mini(k, 1)] if f == 0 else curl[k]) * CURL_SIGN
			var rest_local: Transform3D = _skeleton.get_bone_rest(idx)
			var rot := Basis(Vector3.BACK, deg_to_rad(ang))
			_skeleton.set_bone_pose_rotation(idx, (rest_local.basis * rot).get_rotation_quaternion())
