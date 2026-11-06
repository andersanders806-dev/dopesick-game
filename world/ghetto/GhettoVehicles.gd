extends Node
## The set's cars: the drive-by car and THE BUST's dressing.
##
## drive_by(path_id): a car (assets/cars, repainted) drives a path at speed -- wheels turning, headlights,
## engine going by with doppler -- with a muzzle flash and a flash of light at each of its windows (slots:
## Marker3Ds the core can hang its shooters on; `slots_facing_corner()` are the ones that face the north
## sidewalk). It frees itself at the end and the set emits drive_by_finished(path_id). `auto_fire` makes the
## windows flash on their own (the core turns it off when it fires the shots itself and calls flash_slot()).
##
## build_bust(): police cars arriving (and braking) in a roadblock at each end of Main Street, their
## lightbars flashing red and blue and the street shining wet under them, a SWAT van, tape across the road
## on two poles, and the getaway car idling at the lot's exit with its lights on.

const CarPaint := preload("res://world/CarPaint.gd")
const Mat := preload("res://world/ghetto/GhettoMat.gd")
const TEX := "res://assets/ghetto/"

## id -> the car's route: points in the world, y 0. A car faces +X in its model.
const PATHS := {
	"main_east": [Vector3(-84, 0, 1.0), Vector3(-30, 0, 0.9), Vector3(30, 0, 1.0), Vector3(84, 0, 1.1)],
	"main_west": [Vector3(84, 0, 0.1), Vector3(30, 0, 0.0), Vector3(-30, 0, 0.2), Vector3(-84, 0, 0.1)],
	# Down West Avenue, round the corner onto Main in a squeal, and out east.
	"swerve": [Vector3(-71, 0, -70), Vector3(-71, 0, -30), Vector3(-70, 0, -8), Vector3(-62, 0, 0.9), Vector3(-45, 0, 1.0), Vector3(20, 0, 1.0), Vector3(84, 0, 1.0)],
	"back_street": [Vector3(-84, 0, -91.0), Vector3(0, 0, -91.0), Vector3(84, 0, -91.0)],
}
const ROADBLOCKS := [
	# [model, position, yaw degrees, arrives from the side (+1 east, -1 west)]
	# The two that stop at the laundromat's door.
	["police_crownvic", Vector3(36.6, 0, 0.3), 168.0, 1],
	["police_crownvic", Vector3(29.0, 0, -0.2), 12.0, -1],
	["police_crownvic", Vector3(52.5, 0, -0.6), 84.0, 1],
	["police_crownvic", Vector3(52.7, 0, 3.7), 96.0, 1],
	["van_shvan92", Vector3(59.5, 0, 0.9), 175.0, 1],
	["police_crownvic", Vector3(-46.5, 0, 0.0), 95.0, -1],
	["police_crownvic", Vector3(-46.2, 0, 4.0), 84.0, -1],
]
const TAPES := [47.0, -40.0]
## The getaway car waits in the lot behind the laundromat (the lot's way out is the gap at x 45..47 onto Back Street).
const GETAWAY := Vector3(47.0, 0.0, -22.0)
const GETAWAY_POINT := Vector3(47.0, 0.0, -22.0)
const GETAWAY_ROUTE := [Vector3(47.0, 0, -22.0), Vector3(46.8, 0, -34.0), Vector3(46.0, 0, -62.0), Vector3(46.0, 0, -84.0), Vector3(45.5, 0, -90.0), Vector3(30.0, 0, -91.0), Vector3(-30.0, 0, -91.0), Vector3(-90.0, 0, -91.0)]
const MAX_FLASH_LIGHTS := 6

var set_node: Node
var auto_fire := true
var bust_built := false
var police_cars: Array[Node3D] = []
var swat_van: Node3D
var getaway_car: Node3D
var getaway_leaving := false
var _leave_last := 0.0
var lights_on := true
var tape_strips: Array[MeshInstance3D] = []
var drive_car: Node3D
var drive_id := ""
var drive_slots: Array[Marker3D] = []
var drives_finished := 0

var _curve: Curve3D
var _offset := 0.0
var _speed := 19.0
var _slot_t: Array[float] = []
var _burst_left := 0
var _burst_gap := 0.0
var _arrivals: Array = []
var _lightbars: Array = []         # [mat_red, mat_blue, light, phase, glow decal]
var _flash_mat: StandardMaterial3D
var _t := 0.0
var _blink: Array = []

func _ready() -> void:
	name = "Vehicles"
	set_process(true)
	# The police models load in the background so THE BUST's arrival doesn't hitch.
	for m in ["police_crownvic", "van_shvan92", "sedan_generic"]:
		ResourceLoader.load_threaded_request("res://assets/cars/%s.glb" % m)

func _car_scene(model: String) -> PackedScene:
	return ResourceLoader.load("res://assets/cars/%s.glb" % model) as PackedScene

## A car with its wheels: Node3D "Car" -> the dressed model; `wheels` and `wheel_radius` in meta.
func make_car(model: String, pick := -1) -> Node3D:
	var car := Node3D.new()
	car.name = "Car_" + model
	var m := _car_scene(model).instantiate() as Node3D
	m.name = "Model"
	CarPaint.dress(m, pick, false)
	car.add_child(m)
	var wheels := CarPaint.wheels(m)
	car.set_meta("wheels", wheels)
	car.set_meta("wheel_radius", (wheels[0] as MeshInstance3D).get_aabb().size.y * 0.5 if not wheels.is_empty() else 0.32)
	car.set_meta("aabb", CarPaint.bounds(m))
	return car

func _spin(car: Node3D, dist: float) -> void:
	var r: float = car.get_meta("wheel_radius")
	for w in car.get_meta("wheels"):
		(w as Node3D).rotate_object_local(Vector3.BACK, -dist / r)

# --- The drive-by ---------------------------------------------------------------------

func is_driving() -> bool:
	return drive_car != null and is_instance_valid(drive_car)

func drive_by(path_id: String, speed := 19.0) -> Node3D:
	if is_driving():
		return drive_car
	if not PATHS.has(path_id):
		push_warning("GhettoSet.drive_by: no path '%s'" % path_id)
		return null
	var pts: Array = PATHS[path_id]
	_curve = Curve3D.new()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var next: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var h := (next - prev) * 0.25
		_curve.add_point(p, -h, h)
	var kind: String = ["sedan_generic", "hatch_generic", "wagon_generic", "suv_generic"][randi() % 4]
	drive_car = make_car(kind, 1)
	drive_car.name = "DriveByCar"
	add_child(drive_car)
	drive_id = path_id
	_speed = speed
	_offset = 0.0
	_place(drive_car, 0.0)
	# Slots: a muzzle flash and a light at each window (front and rear, both sides), at gun height.
	drive_slots.clear()
	_slot_t.clear()
	var aabb: AABB = drive_car.get_meta("aabb")
	for side in [-1.0, 1.0]:
		for xf in [0.18, -0.12]:
			var s := Marker3D.new()
			s.name = "Window%d" % drive_slots.size()
			s.position = Vector3(aabb.position.x + aabb.size.x * (0.5 + xf), aabb.size.y * 0.72, aabb.size.z * 0.5 * side + aabb.position.z + aabb.size.z * 0.5 * (side * 0.1))
			s.set_meta("side", side)
			drive_car.add_child(s)
			_build_flash(s)
			drive_slots.append(s)
			_slot_t.append(0.0)
	# Headlights and an engine going by.
	var head := SpotLight3D.new()
	head.name = "Headlights"
	head.light_energy = 4.0
	head.spot_range = 26.0
	head.spot_angle = 32.0
	head.shadow_enabled = false
	head.position = Vector3(aabb.end.x - 0.2, aabb.size.y * 0.35, aabb.position.z + aabb.size.z * 0.5)
	head.rotation_degrees.y = -90.0
	drive_car.add_child(head)
	var eng := AudioStreamPlayer3D.new()
	eng.name = "Engine"
	var path := "res://assets/sfx/guns/car_pass.wav"
	if ResourceLoader.exists(path):
		eng.stream = load(path)
	eng.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	eng.unit_size = 14.0
	eng.max_distance = 140.0
	eng.volume_db = 2.0
	eng.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	drive_car.add_child(eng)
	eng.play()
	if path_id == "swerve":
		set_node.call("_sound", "tyre_squeal", Vector3(-68, 0, -4), 2.0, 1.0, 120.0)
	_burst_left = 0
	_burst_gap = 0.6
	set_node.emit_signal("drive_by_started", path_id, drive_car)
	return drive_car

func _place(car: Node3D, off: float) -> void:
	var p := _curve.sample_baked(off, true)
	var q := _curve.sample_baked(minf(off + 1.5, _curve.get_baked_length()), true)
	var d := q - p
	car.global_position = Vector3(p.x, 0, p.z)
	if d.length() > 0.01:
		car.rotation.y = atan2(-d.z, d.x)

func slots_facing_corner() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for s in drive_slots:
		if is_instance_valid(s) and s.global_position.z < drive_car.global_position.z - 0.3:
			out.append(s)
	return out

func _build_flash(slot: Marker3D) -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var tex := GradientTexture2D.new()
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
		g.set_color(1, Color(1.0, 0.5, 0.1, 0.0))
		tex.gradient = g
		_flash_mat.albedo_texture = tex
	var q := MeshInstance3D.new()
	q.name = "Flash"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.7, 0.7)
	q.mesh = qm
	q.material_override = _flash_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.visible = false
	slot.add_child(q)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.light_color = Color(1.0, 0.7, 0.35)
	l.light_energy = 0.0
	l.omni_range = 7.0
	l.shadow_enabled = false
	slot.add_child(l)

## A muzzle flash at window `i` (the core calls this when its shooter there fires).
func flash_slot(i: int) -> void:
	if i < 0 or i >= drive_slots.size() or not is_instance_valid(drive_slots[i]):
		return
	_slot_t[i] = 0.07
	var s := drive_slots[i]
	(s.get_node("Flash") as Node3D).visible = true
	(s.get_node("Flash") as Node3D).rotation.z = randf() * TAU
	(s.get_node("Light") as OmniLight3D).light_energy = 3.5

func _drive(delta: float) -> void:
	var len := _curve.get_baked_length()
	# Eases up to speed and stays there; the swerve slows for its corner.
	var sp := _speed * (0.62 if drive_id == "swerve" and _offset > 40.0 and _offset < 75.0 else 1.0)
	_offset += sp * delta
	_place(drive_car, minf(_offset, len))
	_spin(drive_car, sp * delta)
	# Leans into the turn.
	var ahead := _curve.sample_baked(minf(_offset + 6.0, len), true) - _curve.sample_baked(minf(_offset, len), true)
	var back := _curve.sample_baked(minf(_offset, len), true) - _curve.sample_baked(maxf(_offset - 6.0, 0.0), true)
	var turn := ahead.angle_to(back) if ahead.length() > 0.1 and back.length() > 0.1 else 0.0
	(drive_car.get_node("Model") as Node3D).rotation.x = clampf(turn * 0.8, 0.0, 0.1) * (1.0 if ahead.cross(back).y > 0 else -1.0)
	for i in drive_slots.size():
		if _slot_t[i] > 0.0:
			_slot_t[i] -= delta
			if _slot_t[i] <= 0.0:
				(drive_slots[i].get_node("Flash") as Node3D).visible = false
				(drive_slots[i].get_node("Light") as OmniLight3D).light_energy = 0.0
	if auto_fire:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			if _burst_left <= 0:
				_burst_left = randi_range(5, 11)
			var faces := slots_facing_corner()
			if not faces.is_empty():
				var s := faces[randi() % faces.size()]
				flash_slot(drive_slots.find(s))
				if set_node:
					set_node.call("_sound", "res://assets/sfx/guns/fire_smg_a.wav", s.global_position, -10.0, randf_range(0.9, 1.15), 90.0)
			_burst_left -= 1
			_burst_gap = randf_range(0.06, 0.12) if _burst_left > 0 else randf_range(0.6, 1.4)
	if _offset >= len + 6.0:
		var id := drive_id
		drive_car.queue_free()
		drive_car = null
		drive_slots.clear()
		drives_finished += 1
		set_node.emit_signal("drive_by_finished", id)

# --- THE BUST -----------------------------------------------------------------------------

func build_bust() -> void:
	if bust_built:
		return
	bust_built = true
	for spec in ROADBLOCKS:
		var car := make_car(spec[0], 1 if spec[0] == "van_shvan92" else -1)
		var is_van: bool = spec[0] == "van_shvan92"
		car.name = "SwatVan" if is_van else "PoliceCar%d" % police_cars.size()
		add_child(car)
		var to: Vector3 = spec[1]
		var side: int = spec[3]
		var from := to + Vector3(55.0 * side, 0, 0)
		car.global_position = from
		car.rotation_degrees.y = 180.0 if side > 0 else 0.0
		car.set_meta("yaw_from", car.rotation.y)
		_arrivals.append({"car": car, "from": from, "to": to, "yaw_to": deg_to_rad(spec[2]), "t": -0.4 * _arrivals.size(), "dur": 3.2, "last": from})
		_wet_decals(car, to)
		_lightbar(car, is_van)
		if is_van:
			swat_van = car
			for sd in [-1.0, 1.0]:
				var l := Label3D.new()
				l.text = "SWAT"
				l.font_size = 120
				l.pixel_size = 0.005
				l.modulate = Color(0.92, 0.92, 0.94)
				l.outline_size = 0
				var a: AABB = car.get_meta("aabb")
				l.position = Vector3(a.position.x + a.size.x * 0.5, a.size.y * 0.5, a.position.z + a.size.z * 0.5 + sd * (a.size.z * 0.5 + 0.03))
				l.rotation_degrees.y = 0.0 if sd > 0 else 180.0
				car.add_child(l)
		else:
			police_cars.append(car)
	for x: float in TAPES:
		_tape(x)
	_getaway()
	# Once they are in place, the bullhorn: the warrant team telling the block what is about to happen.
	var horn := get_tree().create_timer(4.5)
	horn.timeout.connect(func():
		set_node.call("_sound", "res://assets/sfx/ghetto/bullhorn_whoop.wav", Vector3(36.6, 1.6, 0.3), 4.0, 1.0, 140.0)
		get_tree().create_timer(3.2).timeout.connect(func():
			set_node.call("_sound", "res://assets/sfx/ghetto/bullhorn_double.wav", Vector3(29.0, 1.6, -0.2), 4.0, 1.0, 140.0)))

func _wet_decals(car: Node3D, at: Vector3) -> void:
	# The street gone glossy under the car and a pulsing glow where the lights fall on it.
	var wet := Decal.new()
	wet.name = "WetSheen"
	wet.texture_albedo = load("res://assets/decals/puddle.png")
	wet.texture_orm = load("res://assets/decals/puddle_orm.png")
	wet.size = Vector3(10.0, 0.4, 8.0)
	wet.position = Vector3(at.x, 0.0, at.z)
	wet.albedo_mix = 0.7
	add_child(wet)
	var glow := Decal.new()
	glow.name = "LightPool"
	var rad := GradientTexture2D.new()
	rad.fill = GradientTexture2D.FILL_RADIAL
	rad.fill_from = Vector2(0.5, 0.5)
	rad.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	rad.gradient = g
	glow.texture_albedo = rad
	glow.texture_emission = rad
	glow.albedo_mix = 0.0
	glow.emission_energy = 0.16
	glow.size = Vector3(12.0, 0.5, 9.0)
	glow.position = Vector3(at.x, 0.0, at.z)
	glow.upper_fade = 0.2
	add_child(glow)
	car.set_meta("glow", glow)

func _lightbar(car: Node3D, van: bool) -> void:
	var a: AABB = car.get_meta("aabb")
	var bar := Node3D.new()
	bar.name = "Lightbar"
	bar.position = Vector3(a.position.x + a.size.x * (0.42 if not van else 0.6), a.end.y + 0.04, a.position.z + a.size.z * 0.5)
	car.add_child(bar)
	var red := Mat.mat(Color(1.0, 0.05, 0.05), 0.3, 0.0, 0.2)
	var blue := Mat.mat(Color(0.1, 0.25, 1.0), 0.3, 0.0, 0.2)
	var base := Mat.mat(Color(0.05, 0.05, 0.06), 0.5, 0.2)
	var mr := red.duplicate() as StandardMaterial3D
	var mb := blue.duplicate() as StandardMaterial3D
	for spec in [[-0.28, mr], [0.28, mb]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.12, 0.5)
		mi.mesh = bm
		mi.material_override = spec[1]
		mi.position = Vector3(0, 0.06, spec[0] if spec[0] < 0 else spec[0])
		mi.position.z = spec[0]
		mi.position.x = 0.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bar.add_child(mi)
	var b := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.28, 0.04, 1.3)
	b.mesh = bb
	b.material_override = base
	bar.add_child(b)
	var l := OmniLight3D.new()
	l.name = "FlashLight"
	l.omni_range = 15.0
	l.light_energy = 0.0
	l.shadow_enabled = false
	l.position = Vector3(0, 0.6, 0)
	bar.add_child(l)
	_lightbars.append([mr, mb, l, randf() * 0.5, car])
	# Every other car has its siren on (a wail and a yelp trade off; the rest are only lights).
	if _lightbars.size() % 2 == 1:
		var yelp := _lightbars.size() % 4 == 3
		var sp := Mat.loop_player(car, "res://assets/sfx/ghetto/%s.wav" % ("siren_yelp_loop" if yelp else "siren_wail_loop"), Vector3(0, 1.4, 0), -6.0, 150.0, 14.0)
		if sp:
			sp.name = "Siren"
			sp.seek(randf() * 5.0)

func _tape(x: float) -> void:
	var tex := load(TEX + "tape_police.png") as Texture2D
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(5.0, 1.0, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.7
	for sx in [-4.4, 4.4]:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = 1.5
		cm.radial_segments = 6
		cm.rings = 1
		pole.mesh = cm
		pole.material_override = Mat.mat(Color(0.9, 0.9, 0.9), 0.6)
		pole.position = Vector3(x, 0.75, sx - 0.2 if sx < 0 else sx)
		add_child(pole)
	for y in [0.98, 1.22]:
		var strip := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(8.8, 0.1)
		strip.mesh = qm
		strip.material_override = m
		strip.position = Vector3(x, y, 0.0)
		strip.rotation_degrees.y = 90.0
		strip.name = "Tape"
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
		tape_strips.append(strip)

func _getaway() -> void:
	getaway_car = make_car("sedan_generic", 3)
	getaway_car.name = "GetawayCar"
	add_child(getaway_car)
	getaway_car.global_position = GETAWAY
	getaway_car.rotation_degrees.y = 90.0
	var a: AABB = getaway_car.get_meta("aabb")
	var body := StaticBody3D.new()
	var s := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(a.size.x, a.size.y, a.size.z - 0.2)
	s.shape = bs
	s.position = Vector3(a.position.x + a.size.x * 0.5, a.size.y / 2.0, 0)
	body.add_child(s)
	getaway_car.add_child(body)
	# Headlights on the gate, brake lights, hazards blinking; the engine idling in a haze.
	var head := SpotLight3D.new()
	head.light_energy = 3.5
	head.spot_range = 22.0
	head.spot_angle = 34.0
	head.shadow_enabled = false
	head.position = Vector3(a.end.x - 0.2, a.size.y * 0.35, 0)
	head.rotation_degrees.y = -90.0
	head.name = "Headlights"
	getaway_car.add_child(head)
	var tail := OmniLight3D.new()
	tail.light_color = Color(1.0, 0.1, 0.08)
	tail.light_energy = 0.9
	tail.omni_range = 4.5
	tail.shadow_enabled = false
	tail.position = Vector3(a.position.x - 0.3, a.size.y * 0.4, 0)
	getaway_car.add_child(tail)
	for sx in [-1.0, 1.0]:
		var hz := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.05, 0.1, 0.18)
		hz.mesh = hb
		var hm := Mat.mat(Color(1.0, 0.55, 0.1), 0.3, 0.0, 3.0).duplicate() as StandardMaterial3D
		hz.material_override = hm
		hz.position = Vector3(a.position.x - 0.02, a.size.y * 0.45, 0.7 * sx)
		getaway_car.add_child(hz)
		_blink.append(hm)
	set_node.call("make_exhaust", getaway_car, Vector3(a.position.x - 0.15, 0.3, 0.55))
	var marker := Marker3D.new()
	marker.name = "GetawayPoint"
	add_child(marker)
	marker.global_position = GETAWAY_POINT

## ESCAPED: the getaway car pulls out of the lot, up through the gap onto Back Street and away west, the tyres
## squealing, its tail lights going.
func getaway_leave() -> void:
	if getaway_car == null or not is_instance_valid(getaway_car) or getaway_leaving:
		return
	getaway_leaving = true
	set_node.call("_sound", "tyre_squeal", getaway_car.global_position, 3.0, 1.0, 110.0)
	set_node.call("_sound", "res://assets/sfx/car_pass.wav", getaway_car.global_position, 2.0, 0.8, 120.0)
	var route := Curve3D.new()
	for i in GETAWAY_ROUTE.size():
		var p: Vector3 = GETAWAY_ROUTE[i]
		var prev: Vector3 = GETAWAY_ROUTE[maxi(i - 1, 0)]
		var next: Vector3 = GETAWAY_ROUTE[mini(i + 1, GETAWAY_ROUTE.size() - 1)]
		var h := (next - prev) * 0.2
		route.add_point(p, -h, h)
	var total := route.get_baked_length()
	_leave_last = 0.0
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(getaway_car):
			return
		var d := total * t * t
		var p := route.sample_baked(d, true)
		var q := route.sample_baked(minf(d + 1.5, total), true)
		_spin(getaway_car, d - _leave_last)
		_leave_last = d
		getaway_car.global_position = Vector3(p.x, 0, p.z)
		var dir := q - p
		if dir.length() > 0.01:
			getaway_car.rotation.y = atan2(-dir.z, dir.x), 0.0, 1.0, 9.0)
	tw.tween_callback(func():
		if is_instance_valid(getaway_car):
			getaway_car.visible = false)

## The police lightbars and their sirens on or off (the clean ending: the night goes quiet).
func set_lights(on: bool) -> void:
	lights_on = on
	var cars: Array = []
	cars.append_array(police_cars)
	cars.append(swat_van)
	for c in cars:
		if c and is_instance_valid(c):
			var sp := c.get_node_or_null("Siren") as AudioStreamPlayer3D
			if sp:
				if on and not sp.playing:
					sp.play()
				elif not on:
					sp.stop()

func getaway_point() -> Vector3:
	return GETAWAY_POINT

func _process(delta: float) -> void:
	_t += delta
	if is_driving():
		_drive(delta)
	# Police cars rolling in: fast, braking hard, swinging into place, the tyres squealing.
	for i in range(_arrivals.size() - 1, -1, -1):
		var ar: Dictionary = _arrivals[i]
		ar["t"] += delta
		var t: float = ar["t"]
		if t < 0.0:
			continue
		var k := clampf(t / float(ar["dur"]), 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 2.4)
		var car := ar["car"] as Node3D
		var p: Vector3 = (ar["from"] as Vector3).lerp(ar["to"], e)
		_spin(car, p.distance_to(ar["last"]))
		ar["last"] = p
		car.global_position = p
		car.rotation.y = lerp_angle(float(car.get_meta("yaw_from")), float(ar["yaw_to"]), smoothstep(0.35, 1.0, k))
		if t - delta < 0.0:
			set_node.call("_sound", "tyre_squeal", (ar["to"] as Vector3), -2.0, randf_range(0.9, 1.1), 110.0)
		if k >= 1.0:
			_arrivals.remove_at(i)
			_make_solid(car)
	# Lightbars: red, red, blue, blue; the street answers in the same colours.
	for lb in _lightbars:
		var ph := fposmod(_t * 2.4 + float(lb[3]), 1.0)
		var r := lights_on and (ph < 0.1 or (ph > 0.18 and ph < 0.28))
		var b := lights_on and ((ph > 0.5 and ph < 0.6) or (ph > 0.68 and ph < 0.78))
		(lb[0] as StandardMaterial3D).emission_energy_multiplier = 6.0 if r else 0.2
		(lb[1] as StandardMaterial3D).emission_energy_multiplier = 6.0 if b else 0.2
		var l := lb[2] as OmniLight3D
		l.light_color = Color(1.0, 0.08, 0.06) if r else Color(0.12, 0.25, 1.0)
		l.light_energy = 5.0 if (r or b) else 0.0
		var car := lb[4] as Node3D
		var glow := car.get_meta("glow") as Decal
		glow.modulate = Color(1.0, 0.1, 0.08) if r else (Color(0.15, 0.3, 1.0) if b else Color(0, 0, 0))
	var hz := 1.0 if int(_t * 2.8) % 2 == 0 else 0.1
	for m in _blink:
		(m as StandardMaterial3D).emission_energy_multiplier = hz * 3.0

func _make_solid(car: Node3D) -> void:
	var a: AABB = car.get_meta("aabb")
	var body := StaticBody3D.new()
	body.name = "Solid"
	var s := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(a.size.x, a.size.y, maxf(a.size.z - 0.2, 1.0))
	s.shape = bs
	s.position = Vector3(a.position.x + a.size.x * 0.5, a.size.y / 2.0, a.position.z + a.size.z * 0.5)
	body.add_child(s)
	car.add_child(body)
