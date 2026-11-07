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
const DOT_SHADER := preload("res://player/viewmodel_dot.gdshader")
const GLASS_SHADER := preload("res://player/viewmodel_glass.gdshader")
const ARMS_SCENE := "res://assets/viewmodel/arms.glb"
## Vertical field of view the gun and arms are drawn with (research: 55 to 65).
const VM_FOV := 60.0
const ARM_NEAR_CUT := 0.12

## Where the hands go on each gun, as fractions of the gun's box (x across from the left
## side, y up from the bottom, z from the BACK (0) to the muzzle (1)): the right hand on the
## grip, the left on the foregrip or, for a pistol, cupping the right. Then each hand's roll
## about its own length (degrees) and how far its fingers close (1 = the standard grip), then the
## finger shape each hand takes (SHAPES) and the size of the hands (a pistol's are slimmer so the
## slide and the sights read between them).
## [right, left, right_roll, left_roll, right_curl, left_curl, right_shape, left_shape, hand_scale]
const HANDS := {
	"pistol": [Vector3(0.5, 0.2, 0.14), Vector3(-0.9, 0.05, 0.18), 0.0, 0.0, 1.0, 1.0, "pistol_r", "pistol_l", 0.84],
	"magnum": [Vector3(0.5, 0.2, 0.15), Vector3(-1.1, 0.2, 0.2), 0.0, 0.0, 1.0, 1.0, "pistol_r", "pistol_l", 0.86],
	"smg": [Vector3(0.5, 0.2, 0.30), Vector3(-0.3, 0.55, 0.58), 0.0, 0.0, 1.0, 1.0, "rifle_r", "vert_l", 1.0],
	"ar": [Vector3(0.5, 0.18, 0.22), Vector3(-0.35, 0.7, 0.74), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cgrip_l", 1.0],
	"lmg": [Vector3(0.5, 0.60, 0.24), Vector3(0.40, 0.74, 0.50), 0.0, 0.0, 1.0, 1.0, "rifle_r", "wrap_l", 1.0],
	"shotgun": [Vector3(0.5, 0.35, 0.28), Vector3(0.5, 0.66, 0.56), 0.0, 0.0, 1.0, 1.0, "rifle_r", "pump_l", 1.0],
	"sniper": [Vector3(0.5, 0.30, 0.30), Vector3(0.5, 0.55, 0.54), 0.0, 0.0, 1.0, 1.0, "rifle_r", "cradle_l", 1.0],
	"wonder": [Vector3(0.5, 0.20, 0.28), Vector3(0.5, 0.30, 0.54), 0.0, 0.0, 1.0, 1.0, "rifle_r", "wrap_l", 1.0],
}

## How the fingers sit on each kind of grip, degrees of bend [base, middle, tip] per finger
## (t thumb, i index, m middle, r ring, p pinky). `i_on` is the index finger on the trigger
## (the firing hand's index lies straight along the frame until the shot).
const SHAPES := {
	# Two hands on a pistol, thumbs forward along the frame: the firing hand's thumb rides the slide
	# side, the support hand lies over the firing hand's fingers.
	"pistol_r": {"t": [4.0, 6.0, 2.0], "i": [4.0, 6.0, 2.0], "i_on": [34.0, 46.0, 24.0], "m": [58.0, 70.0, 42.0], "r": [60.0, 70.0, 44.0], "p": [58.0, 66.0, 42.0]},
	"pistol_l": {"t": [-4.0, 0.0, 0.0], "i": [52.0, 66.0, 40.0], "m": [58.0, 70.0, 44.0], "r": [60.0, 70.0, 44.0], "p": [58.0, 66.0, 42.0]},
	# A rifle's pistol grip: the thumb wraps over the back strap, the index lies along the receiver.
	"rifle_r": {"t": [30.0, 32.0, 20.0], "i": [8.0, 10.0, 4.0], "i_on": [36.0, 48.0, 28.0], "m": [58.0, 70.0, 42.0], "r": [60.0, 72.0, 44.0], "p": [60.0, 70.0, 44.0]},
	# The AR/SMG support hand: a C-grip under the handguard, thumb along its side, fingers curled up.
	"cgrip_l": {"t": [10.0, 14.0, 8.0], "i": [40.0, 50.0, 32.0], "m": [46.0, 58.0, 38.0], "r": [48.0, 60.0, 40.0], "p": [50.0, 62.0, 42.0]},
	"vert_l": {"t": [22.0, 26.0, 16.0], "i": [50.0, 62.0, 40.0], "m": [54.0, 66.0, 42.0], "r": [56.0, 68.0, 44.0], "p": [56.0, 68.0, 44.0]},
	"wrap_l": {"t": [14.0, 18.0, 10.0], "i": [50.0, 62.0, 40.0], "m": [52.0, 64.0, 42.0], "r": [54.0, 66.0, 44.0], "p": [54.0, 66.0, 44.0]},
	# Pump hand: all four fingers round the forend, thumb over the top.
	"pump_l": {"t": [34.0, 30.0, 20.0], "i": [60.0, 72.0, 48.0], "m": [62.0, 74.0, 50.0], "r": [62.0, 74.0, 50.0], "p": [60.0, 72.0, 48.0]},
	# A bolt rifle: the hand cups under the fore-end, fingers half closed.
	"cradle_l": {"t": [12.0, 14.0, 8.0], "i": [34.0, 44.0, 28.0], "m": [38.0, 48.0, 30.0], "r": [40.0, 50.0, 32.0], "p": [42.0, 52.0, 34.0]},
}
## The bare hands of the story's first person (player/StoryHands.gd): loose, holding a
## thing, closed round something small, and a fist.
const STORY_SHAPES := {
	"relaxed": {"t": [10.0, 10.0, 6.0], "i": [26.0, 30.0, 16.0], "m": [32.0, 38.0, 20.0], "r": [38.0, 42.0, 22.0], "p": [42.0, 44.0, 24.0]},
	"hold": {"t": [18.0, 22.0, 12.0], "i": [48.0, 58.0, 36.0], "m": [54.0, 64.0, 40.0], "r": [58.0, 66.0, 42.0], "p": [60.0, 68.0, 44.0]},
	"pinch": {"t": [20.0, 22.0, 14.0], "i": [38.0, 48.0, 30.0], "m": [58.0, 68.0, 40.0], "r": [62.0, 72.0, 44.0], "p": [64.0, 74.0, 46.0]},
	"fist": {"t": [26.0, 30.0, 18.0], "i": [70.0, 84.0, 50.0], "m": [74.0, 88.0, 52.0], "r": [76.0, 90.0, 54.0], "p": [76.0, 90.0, 54.0]},
}

## A hand held open (reaching for a magazine, letting go of one).
const OPEN_SHAPE := {"t": [4.0, 4.0, 2.0], "i": [14.0, 12.0, 6.0], "m": [16.0, 14.0, 6.0], "r": [18.0, 16.0, 8.0], "p": [20.0, 16.0, 8.0]}

## Landmarks the reloads and the first raise work on, as fractions of the gun's box
## (x across, y up from the bottom, z from the MUZZLE (0) to the back (1)):
## magwell: the centre of a seated magazine (the shell port for a shotgun, the receiver's top for a bolt rifle);
## charge: where the support hand takes the charging handle / slide; bolt: the bolt handle;
## [magwell, charge, bolt, mag_kind, mag_height, mag_tilt_deg]
const ANCHORS := {
	"pistol": [Vector3(0.5, 0.2, 0.8), Vector3(0.5, 0.95, 0.88), Vector3(0.5, 0.9, 0.9), "pistol", 0.085, 0.0],
	"magnum": [Vector3(0.5, 0.2, 0.8), Vector3(0.5, 0.95, 0.88), Vector3(0.5, 0.9, 0.9), "magnum", 0.07, 0.0],
	"smg": [Vector3(0.5, 0.33, 0.52), Vector3(0.5, 0.95, 0.72), Vector3(0.5, 0.9, 0.9), "smg", 0.1, 4.0],
	"ar": [Vector3(0.5, 0.23, 0.545), Vector3(0.5, 0.95, 0.76), Vector3(0.5, 0.9, 0.9), "stanag", 0.105, 6.0],
	"lmg": [Vector3(0.5, 0.855, 0.5), Vector3(0.9, 0.7, 0.72), Vector3(0.9, 0.7, 0.72), "pan", 0.0, 0.0],
	"shotgun": [Vector3(0.5, 0.5, 0.55), Vector3(0.5, 0.5, 0.56), Vector3(0.5, 0.5, 0.56), "shell", 0.07, 0.0],
	"sniper": [Vector3(0.5, 0.7, 0.62), Vector3(0.5, 0.7, 0.6), Vector3(1.0, 0.65, 0.66), "round", 0.07, 0.0],
	"wonder": [Vector3(0.5, 0.23, 0.545), Vector3(0.5, 0.95, 0.72), Vector3(0.5, 0.9, 0.9), "stanag", 0.105, 0.0],
}

## The parts of a gun's model that move on their own: [mesh name fragment, kind of part].
## The pistol's slide, the bolt rifle's bolt, the LMG's pan magazine.
const PARTS := {
	"pistol": {"slide": ["slide_a"]},
	"magnum": {},
	"sniper": {"bolt": ["bolt_a", "bolt_b"]},
	"lmg": {"pan": ["mag_dp28", "mag_cap_dp28", "mag_cap_pipka"]},
}

## Guns whose model is plain colours (the importer drops its specular-glossiness
## materials, which leaves flat grey): the shader paints them. Material name ->
## 1 blued steel, 2 walnut; "*" is everything else.
const PLAIN_KIT := {}

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
## Landmarks (this node's space), see ANCHORS: magwell, charge, bolt; the kind and size of the magazine.
var anchors := {}
var mag_kind := ""
var mag_height := 0.1
var mag_tilt := 0.0
## Moving parts of the model: name -> {nodes, rest (positions), to_local (vm offset -> parent offset), vis}.
var parts := {}
## Materials of the gun's own meshes with the mesh's transform into this node's space (the magazine cut).
var _cut_mats: Array = []
var _extra_rest := {}
var _skeleton: Skeleton3D
var _flash_mats: Array[ShaderMaterial] = []
var _fingers := {}
var _arm_cfg := {}

## A viewmodel built and freed within a frame or two (a gun swap, a view change) used to leave
## the renderer an instance still marked for update whose materials were already gone: four
## 'Parameter "material" is null' engine errors at the start of a run. Letting go of the
## materials first, while the nodes still exist, keeps the instances clean.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for mi in find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			m.material_override = null
			m.material_overlay = null
			if m.mesh != null:
				for s in m.mesh.get_surface_count():
					m.set_surface_override_material(s, null)

func setup(d: WD) -> Node3D:
	data = d
	name = "Viewmodel"
	gun = GunModel.build(d)
	add_child(gun)
	box = GunModel.bounds(gun.get_child(0) as Node3D, gun)
	_convert(gun)
	_collect_cut_mats()
	_find_parts()
	_measure()
	_build_flash()
	_build_props()
	_build_arms()
	return self

## Arms and hands without a gun (story first person, player/StoryHands.gd). This node's space
## is the camera's; the caller sets grip_r each frame (the right wrist) and calls aim_hands()
## with the left wrist.
func setup_hands_only() -> Node3D:
	name = "StoryViewmodel"
	data = null
	_hand_shape = {"R": "relaxed", "L": "relaxed"}
	_build_arms()
	return self

## A hand's finger shape: a name from SHAPES / STORY_SHAPES, or a dictionary of the same form
## (what blending two shapes gives), and roll about its length in degrees.
func set_hand(side: String, shape, roll := 0.0, hand_scale := 1.0) -> void:
	_hand_shape[side] = shape
	_hand_roll[side] = roll
	_hand_scale = hand_scale

## Halfway between two finger shapes.
static func blend_shape(a: String, b: String, t: float) -> Dictionary:
	var sa: Dictionary = STORY_SHAPES.get(a, SHAPES.get(a, OPEN_SHAPE))
	var sb: Dictionary = STORY_SHAPES.get(b, SHAPES.get(b, OPEN_SHAPE))
	var out := {}
	for k in sa:
		var x: Array = sa[k]
		var y: Array = sb[k]
		out[k] = [lerpf(x[0], y[0], t), lerpf(x[1], y[1], t), lerpf(x[2], y[2], t)]
	return out

var _arm_mats: Array = []

## Sets a shader parameter on every arm surface (bare skin, pallor, sweat for the story).
func set_arm_param(pname: String, value: Variant) -> void:
	if arms == null:
		return
	if _arm_mats.is_empty():
		for mi in arms.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for i in m.mesh.get_surface_count():
				var mat := m.get_surface_override_material(i) as ShaderMaterial
				if mat != null:
					_arm_mats.append(mat)
	for mat in _arm_mats:
		mat.set_shader_parameter(pname, value)

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
func _convert(node: Node, cut := 0.05, is_arms := false) -> void:
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
			if is_arms:
				mat.set_shader_parameter("arms", true)
			elif data != null and src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture == null:
				var kind: int = PLAIN_KIT.get(data.family(), {}).get(src.resource_name, 0)
				if kind == 0 and PLAIN_KIT.has(data.family()):
					kind = PLAIN_KIT[data.family()].get("*", 0)
				if kind != 0:
					mat.set_shader_parameter("procedural", kind)
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
	_hand_roll = {"R": hands[2], "L": hands[3]}
	_hand_curl = {"R": hands[4], "L": hands[5]}
	_hand_shape = {"R": hands[6], "L": hands[7]}
	_hand_scale = float(hands[8])
	var an: Array = ANCHORS.get(f, ANCHORS["ar"])
	magwell = _at(an[0])
	anchors = {"magwell": magwell, "charge": _at(an[1]), "bolt": _at(an[2]), "grip_l": grip_l, "grip_r": grip_r}
	mag_kind = an[3]
	mag_height = an[4]
	mag_tilt = an[5]
	belt = magwell + Vector3(-0.2, -0.28, 0.12)
	_measure_sights(f)

## Where the sight picture sits on each gun: the zones (fractions of the gun's length from
## the muzzle) of the front sight and the rear sight to measure the sight line from, the eye
## relief (metres from the eye to the rear sight), and whether a red dot is fitted.
## [front_lo, front_hi, rear_lo, rear_hi, relief, optic, lift]; with a red dot: [rail_lo, rail_hi, dot_z, -, relief, true, riser].
## `lift` raises the eye over the gun's top (a sight that is only a flat receiver); with a red dot it is the
## height of a riser the sight stands on (the LMG's, so the dot clears the pan magazine).
const SIGHTS := {
	"pistol": [0.0, 0.14, 0.78, 0.97, 0.30, false, 0.0],
	"magnum": [0.0, 0.14, 0.62, 0.78, 0.30, false, 0.0],
	"smg": [0.3, 0.7, 0.55, 0.0, 0.14, true, 0.0],
	"ar": [0.3, 0.7, 0.58, 0.0, 0.14, true, 0.0],
	"lmg": [0.3, 0.7, 0.5, 0.0, 0.19, true, 0.018],
	"shotgun": [0.0, 0.1, 0.55, 0.72, 0.42, false, 0.05],
	"sniper": [0.0, 0.1, 0.5, 0.65, 0.2, false, 0.01],
	"wonder": [0.0, 0.1, 0.5, 0.65, 0.3, false, 0.05],
}

## The point on the sight line the eye sits behind (rear sight, or the red dot), in this
## node's space, and the pitch that levels the line with the view.
var sight_point := Vector3.ZERO
var ads_pitch := 0.0
var optic: Node3D
var has_optic := false
static var _sight_cache := {}

func _measure_sights(f: String) -> void:
	var cfg: Array = SIGHTS.get(f, SIGHTS["ar"])
	var b := box
	var len := b.size.z
	var z0 := b.position.z
	var key := data.id if data != null else f
	var front := Vector3(0.0, b.end.y, z0)
	var rear := Vector3(0.0, b.end.y, b.end.z)
	var measured := false
	# The answer, found or fallen back to, is kept for the gun (the AR's rail has no vertex on its centreline
	# and was measured again, 300 to 400 ms, on every swap to it).
	if _sight_cache.has(key):
		var c: Array = _sight_cache[key]
		front = c[0]
		rear = c[1]
		measured = true
	else:
		var verts := _gun_verts()
		if verts.size() > 0:
			var cfg_f: Array = [z0 + len * cfg[0], z0 + len * cfg[1]]
			var cfg_r: Array = [z0 + len * cfg[2], z0 + len * cfg[3]]
			if cfg[5]:
				# A red dot goes on the rail: the top of the receiver there.
				var r := _top_in(verts, cfg_f[0], cfg_f[1])
				r.z = z0 + len * cfg[2]
				front = r
				rear = r
			else:
				front = _top_in(verts, cfg_f[0], cfg_f[1])
				rear = _top_in(verts, cfg_r[0], cfg_r[1])
			if front.y > -1e8 and rear.y > -1e8:
				_sight_cache[key] = [front, rear]
				measured = true
	if not measured or front.y < -1e8 or rear.y < -1e8:
		front = Vector3(0.0, b.end.y - 0.004, z0)
		rear = Vector3(0.0, b.end.y - 0.004, b.end.z - len * 0.25)
		_sight_cache[key] = [front, rear]
	has_optic = cfg[5]
	var relief: float = cfg[4]
	if has_optic:
		var riser: float = cfg[6]
		_build_optic(Vector3(0.0, rear.y + riser, rear.z))
		if riser > 0.0:
			_build_riser(rear.y, riser, rear.z)
		# The dot sits in the middle of the sight's frame.
		sight_point = optic.position + optic_dot
		ads_pitch = 0.0
	else:
		var d := front - rear
		ads_pitch = atan(d.y / d.z) if absf(d.z) > 0.01 else 0.0
		sight_point = Vector3(0.0, rear.y + float(cfg[6]), rear.z)
	var rot := Basis(Vector3.RIGHT, ads_pitch)
	ads_position = Vector3(0.0, 0.0, -relief) - rot * sight_point
	muzzle = Vector3(0.0, muzzle.y, muzzle.z)

## Every vertex of the gun's visible meshes in this node's space (empty when the renderer
## keeps no mesh data, as a headless run).
func _gun_verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var xf := Transform3D()
		var c: Node = m
		while c != null and c != gun:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		for sidx in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(sidx)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			out.append_array(xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	return out

## The highest vertex near the gun's centreline with z between the two, as (x, y, z).
func _top_in(verts: PackedVector3Array, zlo: float, zhi: float) -> Vector3:
	var best := Vector3(0.0, -1e9, 0.0)
	for v in verts:
		if v.z < zlo or v.z > zhi or absf(v.x) > 0.02:
			continue
		if v.y > best.y:
			best = v
	return best

# --- The red dot sight: a frame you look through with a dot floating in it -----------

const OPTIC_CENTRE_Y := 0.032
const OPTIC_W := 0.05
const OPTIC_H := 0.042
const OPTIC_L := 0.06

## The sight model (CC BY 4.0, assets/guns/optic): scale, and where its lens centre is once
## its base sits on the rail (metres, in the model's own scale).
const OPTIC_MODEL := "res://assets/guns/optic/red_dot_sight.glb"
const OPTIC_SCALE := 0.55
## Lens centre above the base and along the sight (z), after scaling.
var optic_dot := Vector3(0.0, OPTIC_CENTRE_Y, 0.0)

func _build_optic(at: Vector3) -> void:
	optic = Node3D.new()
	optic.name = "RedDot"
	optic.position = Vector3(0.0, at.y, at.z)
	add_child(optic)
	var ps := GunModel.scene(OPTIC_MODEL)
	if ps != null:
		var model := ps.instantiate() as Node3D
		model.name = "Model"
		model.scale = Vector3.ONE * OPTIC_SCALE
		model.rotation_degrees.y = OPTIC_YAW
		# Its base on the rail.
		
		model.position = Vector3(0.0, 0.0472 * OPTIC_SCALE, 0.0)
		optic.add_child(model)
		_convert(optic, 0.05)
		_blank_logo(model)
		# The lens is glass you see through: a faint tint, not the model's solid blue.
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			for sidx in inst.mesh.get_surface_count():
				var src := inst.mesh.surface_get_material(sidx)
				if src != null and src.resource_name.begins_with("08"):
					var gm := ShaderMaterial.new()
					gm.shader = GLASS_SHADER
					gm.set_shader_parameter("viewmodel_fov", VM_FOV)
					gm.set_shader_parameter("edge_amount", 0.0)
					inst.set_surface_override_material(sidx, gm)
		optic_dot = Vector3(0.0, OPTIC_LENS_Y * OPTIC_SCALE + 0.0472 * OPTIC_SCALE, OPTIC_LENS_Z * OPTIC_SCALE)
		_add_dot()
		return
	_build_optic_kit()

const OPTIC_YAW := 0.0
## Lens centre in the model's own units, from the model's centre.
const OPTIC_LENS_Y := 0.012
const OPTIC_LENS_Z := 0.0

## The "AimDot" logo printed on the sight's side (in its base colour texture) painted out dark.
const OPTIC_LOGO := Vector4(0.128, 0.622, 0.192, 0.748)

func _blank_logo(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for sidx in inst.mesh.get_surface_count():
			var sm := inst.get_surface_override_material(sidx) as ShaderMaterial
			if sm != null and sm.shader == SHADER:
				sm.set_shader_parameter("blank_rect", OPTIC_LOGO)

func _add_dot() -> void:
	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.034
	dot.mesh = q
	var dm := ShaderMaterial.new()
	dm.shader = DOT_SHADER
	dm.set_shader_parameter("viewmodel_fov", VM_FOV)
	dot.material_override = dm
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.position = optic_dot
	optic.add_child(dot)

func _build_optic_kit() -> void:
	var steel := ShaderMaterial.new()
	steel.shader = SHADER
	steel.set_shader_parameter("viewmodel_fov", VM_FOV)
	steel.set_shader_parameter("albedo", Color(0.012, 0.012, 0.014))
	steel.set_shader_parameter("metallic", 0.1)
	steel.set_shader_parameter("roughness", 0.6)
	steel.set_shader_parameter("near_cut", 0.05)
	var wall := 0.0035
	var half_w := OPTIC_W * 0.5
	# Mount plate, then the rectangular tube you look through (left, right, top, bottom).
	_optic_box(Vector3(0.026, 0.008, OPTIC_L * 1.2), Vector3(0.0, 0.004, 0.0), steel)
	_optic_box(Vector3(OPTIC_W, 0.006, OPTIC_L), Vector3(0.0, 0.011, 0.0), steel)
	_optic_box(Vector3(wall, OPTIC_H, OPTIC_L), Vector3(-half_w + wall * 0.5, 0.008 + OPTIC_H * 0.5, 0.0), steel)
	_optic_box(Vector3(wall, OPTIC_H, OPTIC_L), Vector3(half_w - wall * 0.5, 0.008 + OPTIC_H * 0.5, 0.0), steel)
	_optic_box(Vector3(OPTIC_W, wall * 1.4, OPTIC_L), Vector3(0.0, 0.008 + OPTIC_H - wall * 0.7, 0.0), steel)
	# A lens-hood lip at the front and a little glare line on the top.
	_optic_box(Vector3(OPTIC_W + 0.004, 0.004, 0.006), Vector3(0.0, 0.008 + OPTIC_H + 0.001, -OPTIC_L * 0.5), steel)
	# The dot: a small red disc and a faint ring, unshaded, drawn on the viewmodel's projection.
	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.034
	dot.mesh = q
	var dm := ShaderMaterial.new()
	dm.shader = DOT_SHADER
	dm.set_shader_parameter("viewmodel_fov", VM_FOV)
	dot.material_override = dm
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.position = Vector3(0.0, OPTIC_CENTRE_Y, 0.0)
	optic.add_child(dot)
	# The glass: a faint cool tint across the window.
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var gq := QuadMesh.new()
	gq.size = Vector2(OPTIC_W - wall * 2.0, OPTIC_H - wall * 1.5)
	glass.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = GLASS_SHADER
	gm.set_shader_parameter("viewmodel_fov", VM_FOV)
	glass.material_override = gm
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = Vector3(0.0, OPTIC_CENTRE_Y - 0.002, OPTIC_L * 0.2)
	optic.add_child(glass)

## The mount under a raised red dot: a low picatinny rail, not a post. A flat plate with cross slots
## lies on the pan magazine's top under the sight, clamped at the sides, and (where the sight needs
## to stand higher) rides on two short narrow legs.
func _build_riser(from_y: float, height: float, z: float) -> void:
	var steel := ShaderMaterial.new()
	steel.shader = SHADER
	steel.set_shader_parameter("viewmodel_fov", VM_FOV)
	steel.set_shader_parameter("albedo", Color(0.02, 0.02, 0.022))
	steel.set_shader_parameter("metallic", 0.3)
	steel.set_shader_parameter("roughness", 0.55)
	steel.set_shader_parameter("near_cut", 0.05)
	var root := Node3D.new()
	root.name = "Riser"
	root.position = Vector3(0.0, from_y, z)
	add_child(root)
	var plate_h := minf(0.008, height * 0.6)
	var len := 0.11
	_riser_box(root, steel, Vector3(0.034, plate_h, len), Vector3(0.0, height - plate_h * 0.5, 0.0))
	for i in 8:
		var zz := -len * 0.5 + len * (float(i) + 0.5) / 8.0
		_riser_box(root, steel, Vector3(0.037, plate_h * 0.45, 0.004), Vector3(0.0, height - plate_h * 0.7, zz))
	# Clamp blocks at the foot, sloped so the rail sits down on the pan.
	for zz in [-len * 0.38, len * 0.38]:
		_riser_box(root, steel, Vector3(0.03, maxf(height - plate_h, 0.003), 0.016), Vector3(0.0, (height - plate_h) * 0.5, zz))
		_riser_box(root, steel, Vector3(0.044, 0.004, 0.022), Vector3(0.0, 0.002, zz))

func _riser_box(root: Node3D, mat: Material, size: Vector3, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

func _optic_box(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	optic.add_child(mi)

## A point of the gun's box: x across, y up from the bottom, z from the muzzle (0) to the back (1).
func _at(frac: Vector3) -> Vector3:
	return Vector3(box.position.x + box.size.x * frac.x, box.position.y + box.size.y * frac.y, box.position.z + box.size.z * frac.z)

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
		mesh.size = Vector2.ONE * 0.26
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

## The prop and the thing that falls on the floor are the same model: made here with whatever
## material maker is handed (the viewmodel's shader, or a standard material for the world).
## `kind` as in ANCHORS. Origin: the middle of the magazine.
static func mag_model(kind: String, mat_for: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "Mag_" + kind
	var steel: Material = mat_for.call(Color(0.07, 0.07, 0.08), 0.75, 0.4)
	var poly: Material = mat_for.call(Color(0.035, 0.036, 0.04), 0.0, 0.6)
	var brass: Material = mat_for.call(Color(0.8, 0.62, 0.25), 0.9, 0.35)
	var red: Material = mat_for.call(Color(0.62, 0.1, 0.08), 0.0, 0.5)
	match kind:
		"shell":
			_part(root, _cyl(0.0105, 0.05), red, Vector3.ZERO, Vector3(90, 0, 0))
			_part(root, _cyl(0.0112, 0.02), brass, Vector3(0, 0, 0.034), Vector3(90, 0, 0))
		"round":
			_part(root, _cyl(0.0058, 0.05), brass, Vector3(0, 0, 0.012), Vector3(90, 0, 0))
			_part(root, _cyl(0.0042, 0.026), steel, Vector3(0, 0, -0.026), Vector3(90, 0, 0))
		"pan":
			_part(root, _cyl(0.07, 0.03), steel, Vector3.ZERO, Vector3.ZERO)
			_part(root, _cyl(0.03, 0.036), poly, Vector3.ZERO, Vector3.ZERO)
		"pistol", "magnum":
			var h := 0.085 if kind == "pistol" else 0.07
			_part(root, _box(0.025, h, 0.04), poly, Vector3.ZERO, Vector3.ZERO)
			_part(root, _box(0.027, 0.008, 0.044), steel, Vector3(0, -h * 0.5, 0), Vector3.ZERO)
			_part(root, _box(0.021, 0.006, 0.034), brass, Vector3(0, h * 0.5 + 0.002, 0), Vector3.ZERO)
		_:
			# A curved rifle/SMG magazine: three slabs bent forward, a floor plate, the rounds' brass on top.
			var segs := 3
			var h := 0.13 if kind != "smg" else 0.12
			var bend := 6.0 if kind == "stanag" else 2.5
			var w := 0.024
			var dpt := 0.05 if kind == "stanag" else 0.04
			for i in segs:
				var y := (float(i) - 1.0) * h / float(segs)
				var seg := _box(w, h / float(segs) + 0.004, dpt)
				_part(root, seg, poly, Vector3(0, y, -sin(deg_to_rad(bend)) * (float(i) - 1.0) * 0.012), Vector3((float(i) - 1.0) * bend, 0, 0))
			_part(root, _box(w + 0.003, 0.009, dpt + 0.004), steel, Vector3(0, -h * 0.5 - 0.002, 0.004), Vector3(-bend, 0, 0))
			_part(root, _box(w - 0.003, 0.006, dpt - 0.01), brass, Vector3(0, h * 0.5 + 0.003, -0.004), Vector3(bend, 0, 0))
	return root

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m

static func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 14
	m.rings = 1
	return m

static func _part(root: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

func _build_props() -> void:
	mag_prop = Node3D.new()
	mag_prop.name = "MagProp"
	mag_prop.visible = false
	add_child(mag_prop)
	if mag_kind == "pan" or mag_kind == "":
		return
	var mk := func(c: Color, metal: float, rough: float) -> Material:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("viewmodel_fov", VM_FOV)
		m.set_shader_parameter("albedo", c)
		m.set_shader_parameter("metallic", metal)
		m.set_shader_parameter("roughness", rough)
		return m
	mag_prop.add_child(mag_model(mag_kind, mk))

## Places the carried magazine (or shell, or round): `at` in this node's space, rotation in degrees.
## For a gun whose magazine is part of its model (the LMG's pan) it moves that instead.
func set_mag(show: bool, at: Vector3, rot_deg: Vector3) -> void:
	if parts.has("pan") or mag_prop == null:
		return
	mag_prop.visible = show
	mag_prop.position = at
	mag_prop.rotation_degrees = rot_deg + Vector3(mag_tilt, 0, 0)

# --- Moving parts and the magazine cut ------------------------------------------------

func _collect_cut_mats() -> void:
	_cut_mats.clear()
	for mi in gun.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var xf := Transform3D()
		var c: Node = m
		while c != null and c != gun:
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		for sidx in m.mesh.get_surface_count():
			var sm := m.get_surface_override_material(sidx) as ShaderMaterial
			if sm != null:
				_cut_mats.append([sm, xf])

## Hides (or shows) the part of the gun's own mesh where its magazine sits: the left hand has it.
func set_cut(on: bool) -> void:
	var half := Vector3(0.022, mag_height * 0.5 + 0.012, 0.034)
	var vm_box := AABB(magwell - half, half * 2.0)
	for e in _cut_mats:
		var sm: ShaderMaterial = e[0]
		if not on:
			sm.set_shader_parameter("cut_on", false)
			continue
		var local: AABB = (e[1] as Transform3D).affine_inverse() * vm_box
		sm.set_shader_parameter("cut_lo", local.position)
		sm.set_shader_parameter("cut_hi", local.end)
		sm.set_shader_parameter("cut_on", true)

func _find_parts() -> void:
	parts.clear()
	var f: String = data.family() if data != null else "pistol"
	var spec: Dictionary = PARTS.get(f, {})
	for pname in spec:
		var nodes: Array = []
		var rest: Array = []
		var basis_in := Basis.IDENTITY
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			var low := String(mi.name).to_lower()
			for frag in spec[pname]:
				if low.contains(frag) and (mi as MeshInstance3D).visible:
					nodes.append(mi)
					rest.append((mi as Node3D).position)
					# The part's parent turns and scales the model: a step in this space is a different step there.
					var xf := Basis.IDENTITY
					var c: Node = mi.get_parent()
					while c != null and c != gun:
						xf = (c as Node3D).transform.basis * xf
						c = c.get_parent()
					basis_in = xf
					break
		if not nodes.is_empty():
			parts[pname] = {"nodes": nodes, "rest": rest, "to_local": basis_in.inverse(), "amount": Vector3.ZERO}

## Moves a part of the model by `offset` (this node's space) from where it rests.
func set_part(pname: String, offset: Vector3, show := true) -> void:
	if not parts.has(pname):
		return
	var pt: Dictionary = parts[pname]
	var nodes: Array = pt["nodes"]
	var rest: Array = pt["rest"]
	var d: Vector3 = (pt["to_local"] as Basis) * offset
	for i in nodes.size():
		var n := nodes[i] as Node3D
		n.position = (rest[i] as Vector3) + d
		n.visible = show
	pt["amount"] = offset
	# The LMG's red dot is clamped to the pan: it goes where the pan goes.
	if pname == "pan":
		for extra in [optic, get_node_or_null("Riser")]:
			if extra != null:
				var rest_at: Vector3 = _extra_rest.get(extra, extra.position)
				_extra_rest[extra] = rest_at
				(extra as Node3D).position = rest_at + offset
				(extra as Node3D).visible = show

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
	_convert(arms, ARM_NEAR_CUT, true)
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
const ARM_SCALE := 1.12
## Thickness of the forearm and upper arm against the avatar's (the hands keep their size).
const ARM_SLIM := 0.78
## Shoulders, camera space.
const SHOULDER_R := Vector3(0.22, -0.54, 0.22)
const SHOULDER_L := Vector3(-0.22, -0.54, 0.22)
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
var _hand_roll := {"R": 0.0, "L": 0.0}
var _hand_curl := {"R": 1.0, "L": 1.0}
var _hand_shape := {"R": "rifle_r", "L": "cgrip_l"}
var _hand_scale := 1.0
var _trig := 0.0
var _open := {"R": 0.0, "L": 0.0}
var _roll_extra := 0.0

## The skeleton's pose with the hands where they go. `left` is the left hand's
## target on the gun (this node's space); the right is on the grip (plus opt.right, a
## shift in this node's space, for the hand that leaves it to work a bolt). Reads the
## node's own transform for where the camera-fixed shoulders are. `opt`: trig (0..1,
## the firing hand's index on the trigger), open_l / open_r (0..1, a hand opened to take
## or let go of something), left_roll (degrees, turns the support hand about its length).
func aim_hands(left: Vector3, opt := {}) -> void:
	if _skeleton == null or _arm.is_empty():
		return
	_trig = float(opt.get("trig", 0.0))
	_open["L"] = float(opt.get("open_l", 0.0))
	_open["R"] = float(opt.get("open_r", 0.0))
	_roll_extra = float(opt.get("left_roll", 0.0))
	var cam_to_vm := transform.affine_inverse()
	var right: Vector3 = grip_r + (opt.get("right", Vector3.ZERO) as Vector3)
	_solve("R", cam_to_vm * SHOULDER_R, right, Vector3(0.25, -1.0, 0.0))
	_solve("L", cam_to_vm * SHOULDER_L, left, Vector3(-0.25, -1.0, 0.0))

func _solve(side: String, shoulder_vm: Vector3, wrist_vm_target: Vector3, pole_vm: Vector3) -> void:
	var a: Dictionary = _arm[side]
	# vm space -> arms space -> skeleton space (centimetres).
	var to_sk := (arms.transform * _skeleton_in_arms()).affine_inverse()
	var sh: Vector3 = to_sk * shoulder_vm
	var hand_dir_vm := (wrist_vm_target - shoulder_vm).normalized()
	# The hand's long axis: along the forearm, tipped down onto the grip.
	var palm := 0.05 * _hand_scale
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
	var roll := float(_hand_roll[side]) + (_roll_extra if side == "L" else 0.0)
	ha_basis = Basis(ha_dir, deg_to_rad(roll)) * ha_basis
	# A slimmer forearm and upper arm (COD sleeves are fitted, not tubes): thinned about the bone's own axis.
	var slim := Basis.from_scale(Vector3(1.0, ARM_SLIM, ARM_SLIM))
	_skeleton.set_bone_global_pose(a["upper"], Transform3D(up_basis * slim, sh))
	_skeleton.set_bone_global_pose(a["fore"], Transform3D(fo_basis * slim, elbow))
	_skeleton.set_bone_global_pose(a["hand"], Transform3D(ha_basis * Basis.from_scale(Vector3.ONE * _hand_scale), t))
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

## Fingers closed round the gun: each segment bent about its own Z axis, as the grip's shape says
## (the firing hand's index on or off the trigger, a hand opened to take a magazine).
func _curl(a: Dictionary, side: String) -> void:
	var named = _hand_shape[side]
	var shape: Dictionary = named if named is Dictionary else SHAPES.get(named, STORY_SHAPES.get(named, SHAPES["rifle_r"]))
	var open := float(_open[side])
	var fingers: Array = a["fingers"]
	var keys := ["t", "i", "m", "r", "p"]
	for f in range(fingers.size()):
		var chain: Array = fingers[f]
		var src: Array = shape[keys[f]]
		if f == 1 and side == "R" and shape.has("i_on"):
			var on: Array = shape["i_on"]
			src = [lerpf(src[0], on[0], _trig), lerpf(src[1], on[1], _trig), lerpf(src[2], on[2], _trig)]
		var op: Array = OPEN_SHAPE[keys[f]]
		for k in range(chain.size()):
			var idx: int = chain[k]
			if idx < 0:
				continue
			var ang: float = lerpf(float(src[k]), float(op[k]), open) * CURL_SIGN * float(_hand_curl[side])
			var rest_local: Transform3D = _skeleton.get_bone_rest(idx)
			var rot := Basis(Vector3.BACK, deg_to_rad(ang))
			_skeleton.set_bone_pose_rotation(idx, (rest_local.basis * rot).get_rotation_quaternion())
