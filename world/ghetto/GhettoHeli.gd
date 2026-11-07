extends Node3D
## The police helicopter. Kit-built (no model to license): a fuselage, a tail boom and fin, skids, a main
## rotor and a tail rotor that turn, nav lights, a strobe. It circles over the block on a closed loop
## between waves with a searchlight (a SpotLight3D and a soft additive cone of light down to the ground)
## sweeping Main Street; its rotor sound is a looped chop with doppler. In THE BUST (search_player(true))
## it comes down closer and the light hunts the player: when the beam holds on them for a moment,
## `found_player` goes off (the set re-emits it as searchlight_found_player).

signal found_player
signal lap_done(laps: int)

const Mat := preload("res://world/ghetto/GhettoMat.gd")
const BEAM_SHADER := preload("res://assets/shaders/ghetto_beam.gdshader")
const ROTOR_LOOP := "res://assets/sfx/guns/heli_loop.wav"
## The circuit: an ellipse over the block, centre, radii, height (m), seconds a lap.
const CENTER := Vector3(6.0, 0.0, -22.0)
const RADII := Vector2(62.0, 34.0)
const HEIGHT := 40.0
const LAP := 34.0
const FAR := 260.0

var set_node: Node
var active := false          # circling over the block
var searching := false       # the light hunts the player
var laps := 0
var phase := 0.0             # 0..1 round the loop
var found := false
var locked_time := 0.0
var beam_target := Vector3.ZERO
var spot: SpotLight3D
var beam: MeshInstance3D
var model: Node3D
var _rotor: Node3D
var _tail_rotor: Node3D
var _strobe: MeshInstance3D
var _nav: Array[MeshInstance3D] = []
var _engine: AudioStreamPlayer3D
var _blend := 0.0            # 0 gone .. 1 on station
var _sweep_t := 0.0
var _prev_pos := Vector3.ZERO
var _cam_t := 0.0

func _ready() -> void:
	name = "Helicopter"
	_build_model()
	_build_light()
	_build_sound()
	phase = 0.0
	global_position = path_point(0.0, 0.0)
	_prev_pos = global_position
	visible = false
	set_process(true)

## A point on the loop (t in 0..1) at `blend` (0 = out past the edge of the map, 1 = on station).
func path_point(t: float, blend: float) -> Vector3:
	var a := t * TAU
	var r := lerpf(FAR, 1.0, blend)
	var p := CENTER + Vector3(cos(a) * RADII.x * r, 0, sin(a) * RADII.y * r)
	p.y = HEIGHT + 6.0 * sin(a * 2.0) + (1.0 - blend) * 30.0 - (8.0 if searching else 0.0)
	return p

func set_between_waves(on: bool) -> void:
	var was := active
	active = on or searching
	# It comes in over the block: a fly-by first, then the circling rotor takes over.
	if active and not was and set_node and set_node.has_method("_sound"):
		set_node.call("_sound", "res://assets/sfx/ghetto/heli_pass.wav", Vector3(CENTER.x, HEIGHT, CENTER.z), -2.0, 1.0, 300.0)

func search_player(on: bool) -> void:
	searching = on
	found = false
	locked_time = 0.0
	if on:
		active = true
	elif set_node and set_node.get("wave_clear") != true:
		active = false

func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var body_m := Mat.mat(Color(0.06, 0.07, 0.1), 0.35, 0.4)
	var white := Mat.mat(Color(0.88, 0.9, 0.92), 0.5, 0.1)
	var glass := Mat.mat(Color(0.03, 0.05, 0.08, 0.9), 0.05, 0.8)
	var dark := Mat.mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var fus := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.95
	cap.height = 4.6
	cap.radial_segments = 14
	cap.rings = 4
	fus.mesh = cap
	fus.material_override = body_m
	fus.position = Vector3(0.4, 0, 0)
	fus.rotation_degrees = Vector3(0, 0, 90)
	model.add_child(fus)
	# A white belly stripe and POLICE along the side, the cockpit glass on the nose.
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(3.2, 0.2, 1.97)
	stripe.mesh = sm
	stripe.material_override = white
	stripe.position = Vector3(0.1, -0.05, 0)
	model.add_child(stripe)
	var wind := MeshInstance3D.new()
	var ws := SphereMesh.new()
	ws.radius = 0.9
	ws.height = 1.8
	wind.mesh = ws
	wind.material_override = glass
	wind.position = Vector3(1.75, 0.2, 0)
	wind.scale = Vector3(0.9, 0.8, 0.95)
	model.add_child(wind)
	for side in [-1.0, 1.0]:
		var t := Label3D.new()
		t.text = "POLICE"
		t.font_size = 90
		t.pixel_size = 0.006
		t.modulate = Color(0.9, 0.92, 0.95)
		t.outline_size = 0
		t.position = Vector3(0.1, 0.05, 0.97 * side)
		t.rotation_degrees.y = 0.0 if side > 0 else 180.0
		model.add_child(t)
	# Tail boom and fin.
	var boom := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.14
	bm.bottom_radius = 0.42
	bm.height = 4.6
	bm.radial_segments = 8
	bm.rings = 1
	boom.mesh = bm
	boom.material_override = body_m
	boom.rotation_degrees.z = 90.0
	boom.position = Vector3(-3.9, 0.25, 0)
	model.add_child(boom)
	var fin := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.7, 1.3, 0.08)
	fin.mesh = fb
	fin.material_override = body_m
	fin.position = Vector3(-6.0, 0.8, 0)
	fin.rotation_degrees.z = -18.0
	model.add_child(fin)
	# Skids.
	for side in [-1.0, 1.0]:
		var skid := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.045
		cm.height = 3.6
		cm.radial_segments = 6
		cm.rings = 1
		skid.mesh = cm
		skid.material_override = dark
		skid.rotation_degrees.z = 90.0
		skid.position = Vector3(0.3, -1.45, 0.85 * side)
		model.add_child(skid)
		for x in [-0.7, 1.2]:
			var strut := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.07, 0.6, 0.07)
			strut.mesh = sb
			strut.material_override = dark
			strut.position = Vector3(x, -1.18, 0.82 * side)
			strut.rotation_degrees.x = 14.0 * side
			model.add_child(strut)
	# Mast and main rotor: four thin blades and a soft disc for the blur.
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.12
	mm.bottom_radius = 0.18
	mm.height = 0.7
	mm.radial_segments = 6
	mm.rings = 1
	mast.mesh = mm
	mast.material_override = dark
	mast.position = Vector3(0.2, 1.3, 0)
	model.add_child(mast)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0.2, 1.7, 0)
	model.add_child(_rotor)
	for i in 4:
		var bl := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(5.4, 0.04, 0.26)
		bl.mesh = bb
		bl.material_override = dark
		bl.position = Vector3(2.7, 0, 0)
		var pivot := Node3D.new()
		pivot.rotation_degrees.y = i * 90.0
		pivot.add_child(bl)
		_rotor.add_child(pivot)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 5.4
	dm.bottom_radius = 5.4
	dm.height = 0.02
	dm.radial_segments = 20
	dm.rings = 1
	disc.mesh = dm
	var blur := StandardMaterial3D.new()
	blur.albedo_color = Color(0.1, 0.11, 0.13, 0.16)
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blur.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blur.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = blur
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0.2, 1.72, 0)
	model.add_child(disc)
	_tail_rotor = Node3D.new()
	_tail_rotor.position = Vector3(-6.0, 0.95, 0.12)
	model.add_child(_tail_rotor)
	for i in 2:
		var tb := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = Vector3(0.06, 1.1, 0.1)
		tb.mesh = tbm
		tb.material_override = dark
		tb.rotation_degrees.z = i * 90.0
		_tail_rotor.add_child(tb)
	# Lights: red and green navigation lights, a white strobe on the belly.
	for spec in [[Vector3(0.3, 0.1, 1.0), Color(0.1, 1.0, 0.2)], [Vector3(0.3, 0.1, -1.0), Color(1.0, 0.1, 0.1)]]:
		var nav := MeshInstance3D.new()
		var ns := SphereMesh.new()
		ns.radius = 0.07
		ns.height = 0.14
		ns.radial_segments = 6
		ns.rings = 3
		nav.mesh = ns
		nav.material_override = Mat.mat(spec[1], 0.3, 0.0, 4.0)
		nav.position = spec[0]
		model.add_child(nav)
		_nav.append(nav)
	_strobe = MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.1
	ss.height = 0.2
	ss.radial_segments = 6
	ss.rings = 3
	_strobe.mesh = ss
	_strobe.material_override = Mat.mat(Color(1, 1, 1), 0.3, 0.0, 8.0)
	_strobe.position = Vector3(-0.5, -1.0, 0)
	model.add_child(_strobe)
	model.scale = Vector3.ONE * 1.1
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_light() -> void:
	spot = SpotLight3D.new()
	spot.name = "Searchlight"
	spot.light_color = Color(1.0, 0.96, 0.82)
	spot.light_energy = 9.0
	spot.spot_range = 90.0
	spot.spot_angle = 9.0
	spot.spot_angle_attenuation = 0.7
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = false
	top_level = false
	add_child(spot)
	spot.position = Vector3(1.2, -1.0, 0)
	# The cone of light you see from the side: an open cone, brightest at the lamp, gone at the ground.
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 14
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	beam.mesh = cone
	var sm := ShaderMaterial.new()
	sm.shader = BEAM_SHADER
	beam.material_override = sm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.top_level = true
	add_child(beam)

func _build_sound() -> void:
	_engine = AudioStreamPlayer3D.new()
	_engine.name = "Rotor"
	if ResourceLoader.exists(ROTOR_LOOP):
		var s := (load(ROTOR_LOOP) as AudioStreamWAV).duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1)
		_engine.stream = s
	_engine.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_engine.unit_size = 22.0
	_engine.max_distance = 330.0
	_engine.volume_db = 2.0
	_engine.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_engine)

func _process(delta: float) -> void:
	var want := 1.0 if active else 0.0
	_blend = move_toward(_blend, want, delta / (7.0 if want > _blend else 5.0))
	var on := _blend > 0.02
	if visible != on:
		visible = on
		beam.visible = on
		spot.visible = on
		if on and not _engine.playing:
			_engine.play()
		elif not on:
			_engine.stop()
	if not on:
		return
	var prev_phase := phase
	phase = fposmod(phase + delta / LAP, 1.0)
	if phase < prev_phase:
		laps += 1
		lap_done.emit(laps)
	var ease_b := smoothstep(0.0, 1.0, _blend)
	var pos := path_point(phase, ease_b)
	var ahead := path_point(phase + 0.01, ease_b)
	global_position = pos
	# Nose along the path, banked into the turn; the rotors spin whatever the camera does.
	var fwd := (ahead - pos)
	fwd.y = 0.0
	if fwd.length() > 0.01:
		var yaw := atan2(-fwd.z, fwd.x)
		rotation = Vector3(0.0, yaw, 0.0)
		model.rotation = Vector3(0.05, 0, -0.14)
	_rotor.rotate_y(delta * 38.0)
	_tail_rotor.rotate_z(delta * 55.0)
	var tm := Time.get_ticks_msec()
	_strobe.visible = (tm % 1100) < 90
	for n in _nav:
		n.visible = (tm % 1500) < 900
	_engine.volume_db = lerpf(-30.0, 2.0, ease_b)
	_steer_light(delta, ease_b)
	_cam_t -= delta
	if _cam_t <= 0.0:
		_cam_t = 1.5
		_doppler_camera()

func _steer_light(delta: float, ease_b: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var goal := beam_target
	if searching and player:
		# Hunting: sweeps wide about the player, closing in as it homes; holds when it has them.
		_sweep_t += delta
		var d := goal.distance_to(player.global_position)
		var wobble := 0.0 if found else clampf(d * 0.4, 0.4, 7.0)
		var aim := player.global_position + Vector3(sin(_sweep_t * 1.7), 0, cos(_sweep_t * 1.3)) * wobble
		goal = goal.lerp(aim, clampf(delta * (2.4 if found else 0.9), 0, 1))
		if goal.distance_to(player.global_position) < 2.6:
			locked_time += delta
			if locked_time > 0.8 and not found:
				found = true
				found_player.emit()
				_flare()
		else:
			locked_time = maxf(0.0, locked_time - delta * 2.0)
			if found and goal.distance_to(player.global_position) > 6.0:
				found = false
	else:
		_sweep_t += delta
		# Sweeps Main Street end to end and along the alleys' mouths.
		goal = Vector3(CENTER.x + sin(_sweep_t * 0.35) * 46.0, 0.0, -2.0 + sin(_sweep_t * 0.9 + 1.0) * 4.0 - 14.0 * (0.5 + 0.5 * sin(_sweep_t * 0.12)))
		goal = beam_target.lerp(goal, clampf(delta * 3.0, 0, 1)) if beam_target != Vector3.ZERO else goal
	beam_target = goal
	var to_goal := Vector3(goal.x, 0.0, goal.z) - spot.global_position
	if to_goal.length() > 0.5 and absf(to_goal.normalized().dot(Vector3.UP)) < 0.9999:
		spot.look_at(Vector3(goal.x, 0.0, goal.z), Vector3.UP)
	spot.spot_angle = 8.0 + (2.0 if found else 0.0)
	spot.light_energy = (9.0 + (6.0 if found else 0.0)) * ease_b
	# The cone: from the lamp to the ground point.
	var lamp := spot.global_position
	var aim_pt := Vector3(goal.x, 0.0, goal.z)
	var dir := aim_pt - lamp
	var len := dir.length()
	if len > 1.0:
		var basis := Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)
		var rad := tan(deg_to_rad(spot.spot_angle)) * len
		basis = basis.scaled_local(Vector3(rad, len, rad))
		beam.global_transform = Transform3D(basis, lamp + dir * 0.5)
		(beam.material_override as ShaderMaterial).set_shader_parameter("intensity", (1.0 + (0.6 if found else 0.0)) * ease_b)

func _flare() -> void:
	if set_node and set_node.has_signal("searchlight_found_player"):
		set_node.emit_signal("searchlight_found_player")
	if set_node and set_node.has_method("_sound"):
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			set_node.call("_sound", "search_lock", player.global_position, 0.0, 1.0, 80.0)

## The listener's camera has to track its own motion too for the rotor's doppler to work.
func _doppler_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.doppler_tracking == Camera3D.DOPPLER_TRACKING_DISABLED:
		cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
