extends Node3D
## A real door: a leaf on a hinge, swung by a damped spring door-closer.
## No RigidBody, no HingeJoint -- the angle is a number this script owns, and
## the leaf (an AnimatableBody3D) is moved to it each physics tick.
##
## Frame of the door (this node's origin: the middle of the opening, on the
## floor, the leaf's plane at z = 0): +z is the side you approach it from
## outside, -z the inside of the place. The hinge node sits at one edge of the
## opening; in its own frame the closed leaf runs along +x and a positive angle
## swings it toward its -z.
##
## What it does:
##   - Walk into it and it gives way, away from you, at the pace you walked
##     (a body is felt in a sensor strip in front of the leaf: nothing is
##     simulated against the player). Sprint into it and it flies open, hits
##     its stop and slams: loud, and a noise event for the guards.
##   - Let go and the closer takes it back: fast while it is wide open,
##     slowing down over the last ten degrees, and the latch clicks home.
##     Someone standing where it would swing stops it, as a person would.
##   - NPCs (clerks, customers, police) open it the same way as they come
##     to it, so nobody gets stuck behind it. The navmesh is the doorway's:
##     the leaf is never in it.
##   - Locked: it does not give. The handle rattles, the leaf jerks about a
##     centimetre, a rattle sounds (and noise is made). `interact()` rattles
##     too; the caller says why it's locked.
##   - Its sound is layered: handle, bell, hinge creak (pitch and loudness
##     follow how fast it swings; a variant per door), latch, slam, rattle,
##     steel scrape. Street ambience reads `openness()` (world/StreetBleed.gd).
## Kinds (`kind`): "shop_glass" (aluminium and glass, push bar, a bell),
## "steel_back" (a service door: heavy, panic bar, scrape), "bar" (heavy wood).

const SoundSet := preload("res://interactables/DoorSounds.gd")
const TouchScript := preload("res://interactables/DoorTouch3D.gd")

signal opened
signal latched
signal slammed(speed: float)
signal rattled

## Per kind: closer (spring/damper rates), stops, leaf, noise. `r` is the slow
## rate of the overdamped closer: the angle decays like exp(-r t).
const KINDS := {
	"shop_glass": {"width": 1.28, "height": 2.15, "thick": 0.045, "ks": 30.0, "cd": 26.0,
		"out_deg": 88.0, "in_deg": 82.0, "bell": true, "creak_db": -14.0, "stop_db": -3.0},
	"steel_back": {"width": 1.0, "height": 2.1, "thick": 0.05, "ks": 11.0, "cd": 20.0,
		"out_deg": 82.0, "in_deg": 82.0, "bell": false, "creak_db": -12.0, "stop_db": 0.0},
	"bar": {"width": 1.12, "height": 2.1, "thick": 0.06, "ks": 20.0, "cd": 22.0,
		"out_deg": 92.0, "in_deg": 92.0, "bell": false, "creak_db": -10.0, "stop_db": -1.0},
}
## Closer: below this angle (rad) it creeps at LATCH_CREEP until the latch.
const LATCH_ZONE := 0.19
const LATCH_CREEP := 0.2
const LATCH_ANGLE := 0.024
## Walking pace pushes it open this much faster than you walk; sprinting at
## SLAM_SPEED or over slams it.
const PUSH_GAIN := 1.35
const SLAM_SPEED := 3.6
const PUSH_REACH := 0.78
const MIN_PUSH_SPEED := 0.4
const SLAM_OMEGA := 6.5
## How long after the last push or someone in the doorway before it closes.
const HOLD_AFTER := 0.45

@export_enum("shop_glass", "steel_back", "bar") var kind := "shop_glass"
## The hinge is on the +x side of the opening (looking at it from outside).
@export var hinge_east := true
## Width of the opening between the posts (the leaf is a bit narrower).
@export var opening := -1.0
## Draw the posts and header (the shop fronts have their own).
@export var frame := false
## Variant of the hinge's voice; -1: from the node's name.
@export var voice := -1
@export var start_open_deg := 0.0
## Leaf width override (m); -1: the kind's.
@export var door_width := -1.0
## Doors that hand over to each other across a room change share an id (Door3D).
@export var arrival_id := ""
## Only the handle sounds on opening: the caller plays the rest (it's about to change rooms).
var quiet_open := false

var locked := false
var angle := 0.0
var omega := 0.0
## The leaf and its hinge, for whoever wants to look.
var hinge: Node3D
var leaf: AnimatableBody3D
var touch: Area3D
var sensor: Area3D
## Something to shake with the leaf when it's rattled (a roller shutter in front of it).
var shutter: Node3D
## Set by whoever puts the door in a place that has "an inside": "" or its place id.
var place := ""

var _p: Dictionary
## Which way the closed leaf runs from its hinge, along the door's x: +1 east hinge no, -1 hinge on the east side.
var _sx := 1.0
var _width: float
var _height: float
var _latched := true
var _hold := 0.0
var _bodies := {}
var _seen := {}
var _slam_next := false
var _rattle_t := 0.0
var _rattle_cool := 0.0
var _shutter_rest := Vector3.ZERO
var _max_pos := 1.4
var _max_neg := 1.4
var _creak: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_i := 0
var _creak_stream: AudioStream
var _creak_gain := 1.0
var _creak_pitch := 1.0
var _voice := 0
var _cam_push := 0.0
var _cam_t := 99.0
var _cam_dir := Vector3.ZERO
var _arrival := false
## The state the door was last announced in: openness, for the street's sound.
var _last_open := 0.0

## What a transition from a scene hands to the one it arrives in: the door
## behind you finishing its close (set by Door3D).
static var arrival_pending := ""

func _ready() -> void:
	add_to_group("hinged_doors")
	_p = KINDS[kind]
	_width = door_width if door_width > 0.0 else float(_p["width"])
	_height = _p["height"]
	if opening <= 0.0:
		opening = _width + 0.08
	_voice = voice if voice >= 0 else absi(String(name).hash() + int(global_position.x * 7.0)) % 4
	_build()
	_max_pos = deg_to_rad(_p["out_deg"] if hinge_east else _p["in_deg"])
	_max_neg = deg_to_rad(_p["in_deg"] if hinge_east else _p["out_deg"])
	angle = deg_to_rad(start_open_deg)
	if absf(angle) > 0.01:
		_latched = false
	if arrival_id != "" and arrival_pending == arrival_id:
		arrival_pending = ""
		_start_arrival()
	_apply()

# --- Frame of reference ---------------------------------------------------------------

## +1 if a positive angle swings the leaf out (+z) of the opening, -1 in.
func out_sign() -> float:
	return 1.0 if hinge_east else -1.0

## The side of the leaf a world point is on, in the swing's own sign: the
## direction the leaf must go to open away from it.
func away_from(world_pos: Vector3) -> float:
	return 1.0 if _hl(world_pos).z >= 0.0 else -1.0

## The free edge of the leaf, in the world (for tests and the hand).
func tip() -> Vector3:
	return leaf.global_transform * Vector3(_sx * _width, 1.0, 0.0)

func openness() -> float:
	return smoothstep(0.0, 0.75, absf(angle))

func is_closed() -> bool:
	return _latched

## Angle in degrees, as seen from outside, positive swinging out.
func swing_deg() -> float:
	return rad_to_deg(angle) * out_sign()

# --- Build ----------------------------------------------------------------------------

func _build() -> void:
	var hx := opening / 2.0 - 0.03
	hinge = Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(hx if hinge_east else -hx, 0.0, 0.0)
	add_child(hinge)
	_sx = -1.0 if hinge_east else 1.0
	leaf = AnimatableBody3D.new()
	leaf.name = "Leaf"
	leaf.sync_to_physics = true
	leaf.collision_layer = 1
	leaf.collision_mask = 0
	hinge.add_child(leaf)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_width, _height, _p["thick"])
	cs.shape = box
	cs.position = Vector3(_sx * _width / 2.0, _height / 2.0, 0.0)
	leaf.add_child(cs)
	match kind:
		"shop_glass":
			_build_glass_leaf()
		"steel_back":
			_build_steel_leaf()
		"bar":
			_build_bar_leaf()
	if frame or kind != "shop_glass":
		_build_frame()
	# The strip in front of and behind the leaf, and what it sweeps.
	sensor = Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 2 | 8
	sensor.monitorable = false
	hinge.add_child(sensor)
	var ss := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(_width + 0.8, 2.2, (_width + 0.9) * 2.0)
	ss.shape = sb
	ss.position = Vector3(_sx * _width / 2.0, 1.1, 0.0)
	sensor.add_child(ss)
	sensor.body_entered.connect(_on_body_entered)
	sensor.body_exited.connect(_on_body_exited)
	# E on it (a door you don't just walk through): only the player's reach.
	touch = Area3D.new()
	touch.name = "Touch"
	touch.set_script(TouchScript)
	touch.collision_layer = 4
	touch.collision_mask = 0
	touch.monitoring = false
	touch.set("door", self)
	add_child(touch)
	var ts := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(opening + 0.3, 2.2, 1.6)
	ts.shape = tb
	ts.position = Vector3(0.0, 1.1, 0.0)
	touch.add_child(ts)
	touch.set_meta("prompt", "")
	_sound_nodes()

func _sound_nodes() -> void:
	for i in 3:
		var s := _player3d(14.0)
		_shots.append(s)
	_creak = _player3d(9.0)
	_creak.name = "Creak"
	_creak_stream = SoundSet.creak_for(kind, _voice)
	_creak.stream = _creak_stream
	_creak_gain = SoundSet.CREAK_GAIN[_voice % 4]
	_creak_pitch = SoundSet.CREAK_PITCH[_voice % 4] * (0.8 if kind == "bar" else (0.9 if kind == "steel_back" else 1.0))
	_scrape = _player3d(8.0)
	_scrape.name = "Scrape"

func _player3d(unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.unit_size = unit
	p.max_distance = 40.0
	p.attenuation_filter_cutoff_hz = 9000.0
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	leaf.add_child(p)
	p.position = Vector3(_sx * _width * 0.55, 1.1, 0.0)
	return p

## The leaf's picture is drawn running along +x from its hinge; a hinge on the
## east side mirrors it (the leaf runs west), and its sticker is placed by hand.
func _visual() -> Node3D:
	var vis := Node3D.new()
	vis.name = "Visual"
	vis.scale.x = _sx
	leaf.add_child(vis)
	return vis

## Materials are shared by every door (one resource each, one shader each).
static var _mats := {}
## Past this the door isn't drawn at all (m).
const DRAW_RANGE := 38.0

func _mat(color: Color, metallic := 0.0, rough := 0.6, pbr := "", uv := 1.0) -> StandardMaterial3D:
	var key := [color, metallic, rough, pbr, uv]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if pbr != "":
		var d := "res://assets/pbr/" + pbr
		m.albedo_texture = load(d + "_diff.jpg")
		m.normal_enabled = true
		m.normal_texture = load(d + "_nor.jpg")
		m.roughness_texture = load(d + "_rough.jpg")
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * uv
	return m

func _box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DRAW_RANGE
	parent.add_child(mi)
	mi.position = pos
	return mi

func _cyl(parent: Node3D, nm: String, radius: float, length: float, pos: Vector3, mat: Material, along := "x") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 10
	cm.rings = 1
	cm.material = mat
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DRAW_RANGE
	parent.add_child(mi)
	mi.position = pos
	if along == "x":
		mi.rotation_degrees.z = 90.0
	elif along == "z":
		mi.rotation_degrees.x = 90.0
	return mi

## Aluminium frame, glass, push bar inside, a pull on the street side, a
## door-closer box on the header, a brushed kick plate.
func _build_glass_leaf() -> void:
	var w := _width
	var h := _height
	var t: float = _p["thick"]
	var alu := _mat(Color(0.86, 0.87, 0.89), 0.25, 0.5, "metal_brushed", 0.6)
	var dark := _mat(Color(0.14, 0.14, 0.15), 0.2, 0.55)
	var glass: StandardMaterial3D = _mats.get("glass")
	if glass == null:
		glass = StandardMaterial3D.new()
		_mats["glass"] = glass
	glass.albedo_color = Color(0.72, 0.82, 0.86, 0.11)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.04
	glass.metallic = 0.0
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var stile := 0.075
	var vis := _visual()
	_box(vis, "StileHinge", Vector3(stile, h, t), Vector3(stile / 2.0, h / 2.0, 0), alu)
	_box(vis, "StileLatch", Vector3(stile, h, t), Vector3(w - stile / 2.0, h / 2.0, 0), alu)
	_box(vis, "RailTop", Vector3(w - 2.0 * stile, 0.09, t), Vector3(w / 2.0, h - 0.045, 0), alu)
	_box(vis, "RailBottom", Vector3(w - 2.0 * stile, 0.22, t), Vector3(w / 2.0, 0.11, 0),
		_mat(Color(0.62, 0.62, 0.62), 0.25, 0.55, "metal_worn", 0.8))
	_box(vis, "Glass", Vector3(w - 2.0 * stile, h - 0.31, 0.012), Vector3(w / 2.0, 0.22 + (h - 0.31) / 2.0, 0), glass)
	# A grubby band where hands go, and a worn edge: a darker thin box behind the glass reads as film.
	var film: StandardMaterial3D = _mats.get("film")
	if film == null:
		film = StandardMaterial3D.new()
		_mats["film"] = film
	film.albedo_color = Color(0.5, 0.52, 0.5, 0.07)
	film.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	film.roughness = 0.9
	_box(vis, "Grime", Vector3(w - 2.0 * stile, 0.5, 0.004), Vector3(w / 2.0, 0.95, 0.008), film)
	# Inside (-z): push bar on two standoffs.
	var bar_x := w - 0.1 - 0.22
	_cyl(vis, "PushBar", 0.016, 0.52, Vector3(bar_x, 1.0, -0.055), alu)
	for dx in [-0.2, 0.2]:
		_box(vis, "Standoff", Vector3(0.02, 0.02, 0.05), Vector3(bar_x + dx, 1.0, -0.03), alu)
	# Outside (+z): the pull, a vertical bar on the latch stile.
	_cyl(vis, "Pull", 0.014, 0.5, Vector3(w - stile / 2.0 - 0.0, 1.0, 0.07), alu, "y")
	for dy in [-0.19, 0.19]:
		_box(vis, "PullPost", Vector3(0.02, 0.02, 0.07), Vector3(w - stile / 2.0, 1.0 + dy, 0.035), alu)
	# The closer's body on the header, inside; the lock cylinder on the latch stile.
	_box(vis, "Closer", Vector3(0.24, 0.06, 0.05), Vector3(w * 0.5, h - 0.115, -0.045), dark)
	_box(vis, "Cylinder", Vector3(0.035, 0.07, 0.03), Vector3(w - stile / 2.0, 0.78, 0.035), _mat(Color(0.8, 0.66, 0.34), 0.3, 0.4))
	# Bell on a spring above the latch edge, inside.
	if _p["bell"]:
		_cyl(vis, "BellSpring", 0.004, 0.14, Vector3(w - 0.12, h - 0.19, -0.06), dark, "y")
		var bell := MeshInstance3D.new()
		bell.name = "Bell"
		var sm := SphereMesh.new()
		sm.radius = 0.028
		sm.height = 0.05
		sm.radial_segments = 10
		sm.rings = 5
		sm.material = _mat(Color(0.85, 0.66, 0.3), 0.3, 0.35)
		bell.mesh = sm
		bell.visibility_range_end = DRAW_RANGE
		bell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		vis.add_child(bell)
		bell.position = Vector3(w - 0.12, h - 0.27, -0.06)
	_stickers(vis)

## Hours, as on a real shop door; filled in by `set_hours()`.
var _sticker: Label3D

func _stickers(vis: Node3D) -> void:
	_sticker = Label3D.new()
	_sticker.name = "Hours"
	_sticker.text = ""
	_sticker.font_size = 28
	_sticker.pixel_size = 0.0016
	_sticker.outline_size = 0
	_sticker.modulate = Color(0.92, 0.9, 0.82, 0.92)
	_sticker.double_sided = false
	_sticker.shaded = false
	_sticker.visibility_range_end = 14.0
	_sticker.no_depth_test = false
	leaf.add_child(_sticker)
	_sticker.position = Vector3(_sx * _width * 0.5, 1.58, 0.012)

## "OPEN 07-22" style text for the street side of the glass.
func set_hours(text: String) -> void:
	if _sticker != null:
		_sticker.text = text

func _build_steel_leaf() -> void:
	var w := _width
	var h := _height
	var t: float = _p["thick"]
	var paint := _mat(Color(0.42, 0.47, 0.43), 0.15, 0.8, "metal_worn", 0.8)
	var steel := _mat(Color(0.75, 0.76, 0.78), 0.25, 0.5, "metal_brushed", 0.6)
	var vis := _visual()
	_box(vis, "Slab", Vector3(w, h, t), Vector3(w / 2.0, h / 2.0, 0), paint)
	_box(vis, "KickPlate", Vector3(w - 0.08, 0.28, 0.008), Vector3(w / 2.0, 0.16, 0.03), steel)
	_box(vis, "KickPlateIn", Vector3(w - 0.08, 0.28, 0.008), Vector3(w / 2.0, 0.16, -0.03), steel)
	# Panic bar, inside.
	_box(vis, "PanicBar", Vector3(w - 0.22, 0.07, 0.045), Vector3(w / 2.0 + 0.02, 1.0, -0.06), _mat(Color(0.7, 0.12, 0.09), 0.2, 0.5))
	for dx in [-0.4, 0.4]:
		_box(vis, "PanicMount", Vector3(0.09, 0.14, 0.03), Vector3(w / 2.0 + dx + 0.02, 1.0, -0.04), steel)
	# Outside: no handle but a lock cylinder and a pull plate.
	_box(vis, "PullPlate", Vector3(0.1, 0.34, 0.012), Vector3(w - 0.14, 1.0, 0.035), steel)
	_box(vis, "Cylinder", Vector3(0.04, 0.07, 0.03), Vector3(w - 0.14, 0.78, 0.045), _mat(Color(0.8, 0.66, 0.34), 0.3, 0.4))
	_box(vis, "Closer", Vector3(0.3, 0.08, 0.06), Vector3(w * 0.5, h - 0.12, -0.06), _mat(Color(0.12, 0.12, 0.13), 0.5, 0.5))
	for y in [0.3, 1.0, 1.85]:
		_cyl(vis, "HingeBarrel", 0.022, 0.12, Vector3(0.0, y, 0.0), steel, "y")

func _build_bar_leaf() -> void:
	var w := _width
	var h := _height
	var t: float = _p["thick"]
	var wood := _mat(Color(0.62, 0.27, 0.21), 0.0, 0.7, "wood_panels", 0.5)
	var raised := _mat(Color(0.74, 0.33, 0.26), 0.0, 0.65, "wood_panels", 0.5)
	var brass := _mat(Color(0.85, 0.66, 0.32), 0.3, 0.4)
	var vis := _visual()
	_box(vis, "Slab", Vector3(w, h, t), Vector3(w / 2.0, h / 2.0, 0), wood)
	# Raised panels, both faces.
	for side in [-1.0, 1.0]:
		var z: float = side * (t / 2.0 + 0.004)
		_box(vis, "PanelLow", Vector3(w - 0.3, 0.7, 0.024), Vector3(w / 2.0, 0.55, z), raised)
		_box(vis, "PanelHigh", Vector3(w - 0.3, 0.7, 0.024), Vector3(w / 2.0, 1.55, z), raised)
	# A small window with the room's glow in it, from outside.
	var glow: StandardMaterial3D = _mats.get("barglow")
	if glow == null:
		glow = StandardMaterial3D.new()
		_mats["barglow"] = glow
	glow.albedo_color = Color(0.5, 0.32, 0.15)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.3)
	glow.emission_energy_multiplier = 1.4
	_box(vis, "Window", Vector3(0.34, 0.34, 0.01), Vector3(w / 2.0, 1.55, t / 2.0 + 0.024), glow)
	_box(vis, "KickPlate", Vector3(w - 0.1, 0.22, 0.01), Vector3(w / 2.0, 0.13, t / 2.0 + 0.006), brass)
	_box(vis, "KickPlateIn", Vector3(w - 0.1, 0.22, 0.01), Vector3(w / 2.0, 0.13, -t / 2.0 - 0.006), brass)
	# Pull outside (+z), plate inside.
	_cyl(vis, "Pull", 0.018, 0.55, Vector3(w - 0.12, 1.05, 0.085), brass, "y")
	for dy in [-0.2, 0.2]:
		_box(vis, "PullPost", Vector3(0.025, 0.025, 0.06), Vector3(w - 0.12, 1.05 + dy, 0.05), brass)
	_box(vis, "PushPlate", Vector3(0.14, 0.32, 0.01), Vector3(w - 0.15, 1.05, -t / 2.0 - 0.006), brass)
	_box(vis, "Closer", Vector3(0.28, 0.07, 0.06), Vector3(w * 0.5, h - 0.12, -t / 2.0 - 0.03), _mat(Color(0.1, 0.1, 0.11), 0.5, 0.5))
	for y in [0.3, 1.05, 1.8]:
		_cyl(vis, "HingeBarrel", 0.02, 0.11, Vector3(0.0, y, 0.0), brass, "y")

func _build_frame() -> void:
	var trim: StandardMaterial3D
	match kind:
		"bar":
			trim = _mat(Color(0.34, 0.24, 0.19), 0.0, 0.8, "wood_dark", 0.55)
		"steel_back":
			trim = _mat(Color(0.28, 0.3, 0.3), 0.5, 0.7, "metal_worn", 0.8)
		_:
			trim = _mat(Color(0.8, 0.81, 0.83), 0.25, 0.5, "metal_brushed", 0.6)
	var fh := _height + 0.1
	var fw := opening
	var d := 0.14
	var vis := Node3D.new()
	vis.name = "Frame"
	add_child(vis)
	for s in [-1.0, 1.0]:
		_box(vis, "Post", Vector3(0.08, fh, d), Vector3(s * (fw / 2.0 + 0.04), fh / 2.0, 0), trim)
	_box(vis, "Header", Vector3(fw + 0.16, 0.1, d), Vector3(0, fh - 0.0, 0), trim)
	_box(vis, "Threshold", Vector3(fw, 0.02, d + 0.06), Vector3(0, 0.01, 0), _mat(Color(0.6, 0.6, 0.62), 0.25, 0.5, "metal_worn", 0.8))

# --- Bodies -----------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	_bodies[body.get_instance_id()] = body
	_seen.erase(body.get_instance_id())

func _on_body_exited(body: Node3D) -> void:
	_bodies.erase(body.get_instance_id())
	_seen.erase(body.get_instance_id())

## A world point in the hinge's frame, turned so the closed leaf runs along +x and
## a positive angle swings it toward -z, whichever side the hinge is on.
func _hl(world: Vector3) -> Vector3:
	var h := hinge.global_transform.affine_inverse() * world
	return Vector3(h.x * _sx, h.y, h.z * _sx)

## What each body in the sensor is doing to the door.
func _update_bodies(dt: float) -> void:
	var gone: Array = []
	for id in _bodies:
		var b := _bodies[id] as Node3D
		if not is_instance_valid(b):
			gone.append(id)
			continue
		var pos := b.global_position
		var prev: Vector3 = _seen.get(id, pos)
		_seen[id] = pos
		var vel := (pos - prev) / dt
		var h := _hl(pos)
		var hv := hinge.global_transform.basis.inverse() * vel
		hv = Vector3(hv.x * _sx, hv.y, hv.z * _sx)
		var player := b.is_in_group("player")
		# Where the leaf is across this body's x: it pushes if the leaf is ahead.
		var dir := 1.0 if h.z >= 0.0 else -1.0
		var leaf_z := -h.x * tan(clampf(angle, -1.45, 1.45)) if h.x > 0.0 else 0.0
		var ahead := absf(h.z - leaf_z) if (h.z - leaf_z) * dir > 0.0 else 0.0
		var toward := -hv.z * dir
		var in_x := h.x > -0.12 and h.x < _width + 0.1
		var reach := PUSH_REACH if player else PUSH_REACH + 0.45
		# In the doorway: hold the closer off until they're through.
		if in_x and absf(h.z) < 1.0 and absf(angle) > 0.05:
			_hold = maxf(_hold, HOLD_AFTER + (0.4 if not player else 0.0))
		if not in_x or ahead <= 0.0 or ahead > reach or toward < MIN_PUSH_SPEED:
			continue
		if locked and _latched:
			if player:
				_try_rattle()
			continue
		var speed := toward
		var w := speed * PUSH_GAIN / maxf(h.x, 0.4)
		var slam := player and speed >= SLAM_SPEED
		if slam:
			w = maxf(w, SLAM_OMEGA)
			_slam_next = true
		w = minf(w, 9.0)
		_push(dir, w, player, speed)
	for id in gone:
		_bodies.erase(id)
		_seen.erase(id)

## Sets the leaf moving in `dir` (+1/-1, in angle sign) at no less than w rad/s.
func _push(dir: float, w: float, by_player := false, speed := 0.0) -> void:
	if omega * dir < w:
		omega = dir * w
	_hold = maxf(_hold, HOLD_AFTER)
	if _latched:
		_latched = false
		_on_open(by_player, w)
	if by_player and _cam_t > 0.5:
		_cam_t = 0.0
		_cam_push = clampf(speed / 2.0, 0.3, 2.2)
		_cam_dir = Vector3(0, 0, -1.0)
		_reach_hand()

## E on the door, or a script opening it: gives way away from `from_pos`.
func push_open(from_pos: Vector3, speed := 1.9, toward := false) -> void:
	if locked and _latched:
		_try_rattle()
		return
	var dir := away_from(from_pos) * (-1.0 if toward else 1.0)
	_push(dir, speed * PUSH_GAIN / maxf(_width * 0.7, 0.4), false, speed)
	_hold = maxf(_hold, 1.1)

## Keeps the closer off for `secs` (a room change is about to happen).
func hold_open(secs: float) -> void:
	_hold = maxf(_hold, secs)

## The player's right hand goes to the leaf (StoryHands.reach, if there is such a thing).
func _reach_hand() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var hands: Object = player.get("story_hands")
	if hands != null and hands.has_method("reach"):
		var handle := leaf.global_transform * Vector3(_sx * _width * 0.8, 1.0, 0.0)
		hands.call("reach", handle, true)

# --- Locked ------------------------------------------------------------------------------

func set_locked(on: bool) -> void:
	locked = on
	touch.set_meta("prompt", "Locked door" if on else "")

func _try_rattle() -> bool:
	if _rattle_cool > 0.0:
		return false
	rattle()
	return true

## The handle's tried and it won't give: a jerk of about a centimetre, a rattle.
func rattle() -> void:
	_rattle_t = 0.5
	_rattle_cool = 1.3
	_shot("handle", -4.0, 1.0)
	_shot_rattle()
	if shutter != null and is_instance_valid(shutter):
		_shutter_rest = shutter.position
	_noise(8.0, "door_rattle")
	rattled.emit()

func _shot_rattle() -> void:
	var s := SoundSet.pick("rattle")
	_play_shot(s, -2.0 if kind != "steel_back" else 0.0, randf_range(0.94, 1.06))

# --- Events --------------------------------------------------------------------------------

func _on_open(by_player: bool, w: float) -> void:
	opened.emit()
	var loud := clampf(w / 2.0, 0.5, 1.4)
	_shot("handle", -9.0, randf_range(0.95, 1.05))
	if quiet_open:
		return
	match kind:
		"shop_glass":
			_shot("door_open", -3.0, 1.0)
			if _p["bell"]:
				_shot("bell", -6.0 + 3.0 * loud, randf_range(0.97, 1.04))
				_noise(7.0, "door_bell")
		"steel_back":
			_shot("steel_bar", -2.0, randf_range(0.95, 1.05))
			_noise(6.0, "door_steel")
		"bar":
			_shot("door_open", -1.0, randf_range(0.85, 0.95))
			_shot("wood_close", -9.0, 0.7)
	if kind == "steel_back":
		_scrape.stream = SoundSet.pick("scrape")
		_scrape.volume_db = -6.0
		_scrape.pitch_scale = randf_range(0.9, 1.05)
		_scrape.play()

func _on_latch(speed: float) -> void:
	latched.emit()
	_shot("latch", clampf(-12.0 + speed * 8.0, -12.0, -3.0), randf_range(0.97, 1.03))
	if kind == "shop_glass" and _p["bell"]:
		_shot("bell", -17.0, randf_range(1.02, 1.08))
	if kind != "shop_glass":
		_shot("wood_close" if kind == "bar" else "steel_slam_b", -14.0 + (4.0 if kind == "steel_back" else 0.0), randf_range(0.9, 1.0))
	_creak_stop()

func _on_stop_hit(speed: float, at_open: bool) -> void:
	slammed.emit(speed)
	var key := "slam_light"
	match kind:
		"shop_glass":
			key = "slam_light"
		"steel_back":
			key = "steel_slam"
		"bar":
			key = "slam_wood" if speed < 5.5 else "slam_heavy"
	_shot(key, clampf(-8.0 + speed * 1.5, -8.0, 0.0), randf_range(0.93, 1.05))
	if kind == "shop_glass":
		_shot("bell", 0.0, randf_range(0.95, 1.05))
		_shot("glass_rattle", -4.0, 1.0)
	_noise(16.0 if speed >= 4.5 else 11.0, "door_slam")
	var player := get_tree().get_first_node_in_group("player")
	if player != null and at_open and player.has_method("kick") and global_position.distance_to(player.global_position) < 3.5:
		player.call("kick", 0.18)

## The last noise made, for tests (and whoever wants to look).
var last_noise := {}

func _noise(loudness: float, what: String) -> void:
	last_noise = {"kind": what, "loudness": loudness, "pos": global_position}
	if GameState.has_method("emit_noise"):
		GameState.emit_noise(global_position, loudness, what)

func _shot(key: String, db: float, pitch: float) -> void:
	_play_shot(SoundSet.pick(key), db, pitch)

func _play_shot(stream: AudioStream, db: float, pitch: float) -> void:
	if stream == null or _shots.is_empty():
		return
	var p := _shots[_shot_i]
	_shot_i = (_shot_i + 1) % _shots.size()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()

# --- The hinge's voice --------------------------------------------------------------------

func _creak_stop() -> void:
	if _creak.playing:
		_creak.stop()

func _update_creak() -> void:
	var s := absf(omega)
	if s < 0.12 or _latched:
		if _creak.playing:
			_creak.volume_db = lerpf(_creak.volume_db, -60.0, 0.35)
			if _creak.volume_db < -50.0:
				_creak.stop()
		return
	var k := clampf(s / 2.4, 0.0, 1.0)
	var base: float = _p["creak_db"] + _creak_gain
	_creak.volume_db = lerpf(_creak.volume_db if _creak.playing else -40.0, base + lerpf(-16.0, 0.0, k), 0.4)
	_creak.pitch_scale = _creak_pitch * lerpf(0.72, 1.4, sqrt(k))
	if not _creak.playing:
		var slen := _creak_stream.get_length()
		_creak.play(randf() * maxf(slen - 1.0, 0.0))

# --- Camera -------------------------------------------------------------------------------

## A shove moves the view: a short push forward and a dip, after the player has
## placed the camera this frame (process priority).
func _process(dt: float) -> void:
	if _cam_t > 0.6:
		return
	_cam_t += dt
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not Graphics.first_person or Graphics.camera_motion == false:
		return
	var cam := player.get("camera") as Camera3D
	if cam == null:
		return
	var t := _cam_t / 0.45
	var pulse := sin(clampf(t, 0.0, 1.0) * PI)
	var push := 0.075 * _cam_push * pulse
	cam.transform = cam.transform.translated_local(Vector3(0.0, -0.4 * push, -push)).rotated_local(Vector3.RIGHT, -0.5 * push)

# --- Dynamics -----------------------------------------------------------------------------

func _start_arrival() -> void:
	# Just came through: the leaf is swung toward the room you're in and is
	# closing on the latch behind you.
	_arrival = true
	var dir := out_sign()
	angle = dir * deg_to_rad(52.0)
	omega = -dir * 0.9
	_latched = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	_rattle_cool = maxf(0.0, _rattle_cool - dt)
	_update_bodies(dt)
	var moving := absf(omega) > 0.001 or not _latched
	if not moving and _rattle_t <= 0.0:
		return
	_integrate(dt)
	_apply()
	var o := openness()
	if absf(o - _last_open) > 0.0005:
		_last_open = o

func _integrate(dt: float) -> void:
	# Two substeps: stiff closers stay stable.
	var n := 2
	var h := dt / n
	for _i in n:
		var old := angle
		var ks: float = _p["ks"]
		var cd: float = _p["cd"]
		if _hold > 0.0:
			# Held off: the damper only, so a push dies away instead of being fought.
			omega += -cd * 0.35 * omega * h
		else:
			var zone := absf(angle) < LATCH_ZONE
			var dd := cd * (2.6 if zone else 1.0)
			omega += (-ks * angle - dd * omega) * h
			if zone and absf(omega) < LATCH_CREEP and not _latched:
				omega = -signf(angle) * LATCH_CREEP * (0.4 + 0.6 * absf(angle) / LATCH_ZONE)
		var new := angle + omega * h
		new = _clamp_obstacles(old, new)
		if new != angle + omega * h:
			omega = 0.0 if absf(new - old) < 1e-5 else (new - old) / h
		if new > _max_pos:
			new = _max_pos
			_hit_stop(omega, true)
		elif new < -_max_neg:
			new = -_max_neg
			_hit_stop(-omega, true)
		angle = new
		if not _latched and absf(angle) < LATCH_ANGLE and absf(omega) < 1.2 and _hold <= 0.0:
			var speed := absf(omega)
			angle = 0.0
			omega = 0.0
			_latched = true
			_on_latch(speed)
			break
	_hold = maxf(0.0, _hold - dt)
	if _hold <= 0.0 and _arrival and _latched:
		_arrival = false
		process_mode = Node.PROCESS_MODE_INHERIT
	_update_creak()

func _hit_stop(speed: float, at_open: bool) -> void:
	if speed > 1.0:
		if _slam_next or speed > 3.0:
			_on_stop_hit(speed, at_open)
		else:
			_shot("stop", clampf(-14.0 + speed * 4.0, -14.0, -4.0), randf_range(0.95, 1.05))
		omega = -omega * 0.3
		_slam_next = false
		_hold = maxf(_hold, 0.9)
	else:
		omega = 0.0

## Whoever stands where the leaf would sweep stops it, as a person would.
func _clamp_obstacles(old: float, new: float) -> float:
	if new == old or _bodies.is_empty():
		return new
	var d := 1.0 if new > old else -1.0
	for id in _bodies:
		var b := _bodies[id] as Node3D
		if not is_instance_valid(b):
			continue
		var h := _hl(b.global_position)
		var r := Vector2(h.x, h.z).length()
		if r > _width + 0.3 or r < 0.05 or h.x < -0.25:
			continue
		var phi := atan2(-h.z, h.x)
		var m := minf(atan(0.34 / maxf(r, 0.35)), 0.6)
		if d > 0.0 and phi > old:
			new = minf(new, maxf(old, phi - m))
		elif d < 0.0 and phi < old:
			new = maxf(new, minf(old, phi + m))
	return new

func _apply() -> void:
	var jerk := 0.0
	if _rattle_t > 0.0:
		_rattle_t = maxf(0.0, _rattle_t - get_physics_process_delta_time())
		var k := _rattle_t / 0.5
		jerk = sin(_rattle_t * 52.0) * (0.01 / _width) * k * (1.0 if _latched else 0.0)
		if shutter != null and is_instance_valid(shutter):
			shutter.position = _shutter_rest + Vector3(sin(_rattle_t * 61.0) * 0.012 * k, 0.0, 0.0)
	leaf.rotation.y = angle + jerk

# --- Test hooks ------------------------------------------------------------------------------

## Leaf-plane normal side, for tests: +1 if `world_pos` is outside (+z).
func side_of(world_pos: Vector3) -> float:
	return 1.0 if (global_transform.affine_inverse() * world_pos).z >= 0.0 else -1.0
