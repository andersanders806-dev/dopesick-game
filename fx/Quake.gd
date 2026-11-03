extends Node3D
## RICHTER 8.0: the presentation of Dead Block's horde surge. world/ZombieBlock.gd adds one of these;
## it listens to ZombieMode.surge_warning / surge_started / surge_ended (the spawning is not here).
##
## Warning (2.5 s): a sub rumble swelling, the street lights stutter, car alarms start on parked cars
## (3D, looping, amber hazards), dust and grit fall from the buildings' edges, the camera trauma and
## the pad's rumble ramp, the seismograph (ui/Seismograph.gd on the HUD) starts its trace.
## Quake (about 4 s strong, then decaying): heavy shake, the readout climbs to RICHTER 8.0 with the
## stinger, cracks open in the ground with dust bursts and thrown rubble, the horde roar rises and
## DOUBLE POINTS shows on the HUD (ZombieMode.surge_active, which npc/ZombieSurge.gd sets). Ended: the
## roar, the alarms and the cracks fade and everything is put back.
##
## Settings > Camera motion off keeps the shake at a quarter and drops the third-person jolt.
## Nothing here is gore. Every pool is fixed: alarms 4, dust sites 6, cracks 8, bursts 6, rubble 12.
##
## F10 in a debug build runs a whole surge (debug_surge()); tests drive advance() by hand (auto off).

const SFX_DIR := "res://assets/sfx/quake/"
const WARNING_TIME := 2.5
## Full shake, then it dies away over DECAY_TIME.
const STRONG_TIME := 4.0
const DECAY_TIME := 3.5
## How long everything takes to fade once the surge is over.
const FADE_TIME := 2.5
## The readout: foreshocks to 3.6 during the warning, then up to 8.0 in this long.
const RICHTER_RISE := 2.2
const RICHTER_WARN_TOP := 3.6
const RICHTER_PEAK := 8.0
const ALARMS := 4
const DUST_SITES := 6
const CRACKS := 8
const BURSTS := 6
const CHUNKS := 12
const VOICES := 6
## With Camera motion off the shake is this much of itself.
const REDUCED := 0.25
const TP_KICK := 0.75
const ROAR_RISE := 10.0

enum Phase { IDLE, WARNING, QUAKE, ENDING }

var phase := Phase.IDLE
## false: _process does nothing (the tests advance by hand).
var auto := true
var city: Node
## Seconds in the current phase.
var t := 0.0
## 0..1 how hard the ground is moving (lights, dust and the trace follow it).
var level := 0.0
## What the camera trauma is held at right now (before the Camera motion scale).
var trauma_target := 0.0
var richter := 1.0
var roar_level := 0.0
var stinger_plays := 0
var rumble_pulses := 0
var cracks_made := 0
var shake_applied := 0.0
var rng := RandomNumberGenerator.new()

var _player: Node3D
var _lamps: Array = []
var _cars: Array = []
var _alarm_delay: Array[float] = []
var _alarm_fade := 1.0
var _level_end := 0.0
var _roar_end := 0.0
var _r0 := 1.0
var _stung := false
var _crack_t := 0.0
var _after_t := 0.0
var _rumble_t := 0.0
var _site_t: Array[float] = []
var _clock := 0.0
var _debris_lit := 0

var _alarms: Array[AudioStreamPlayer3D] = []
var _hazards: Array[OmniLight3D] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_next := 0
var _build_p: AudioStreamPlayer
var _main_p: AudioStreamPlayer
var _stinger_p: AudioStreamPlayer
var _roars: Array[AudioStreamPlayer] = []
var _dust: Array[CPUParticles3D] = []
var _grit: Array[CPUParticles3D] = []
var _decals: Array[Decal] = []
var _decal_a: Array[float] = []
var _decal_next := 0
var _bursts: Array[CPUParticles3D] = []
var _burst_next := 0
var _chunks: Array[RigidBody3D] = []
var _chunk_next := 0

static var _streams := {}
const DustShader := preload("res://assets/shaders/soft_dust.gdshader")
const NightAtmos := preload("res://world/NightAtmos.gd")

static var _soft: Texture2D
static var _crack_tex: Array[Texture2D] = []
static var _crack_em: Array[Texture2D] = []
static var _crack_nm: Array[Texture2D] = []

func _init() -> void:
	name = "Quake"
	process_priority = 100

func _ready() -> void:
	add_to_group("quake")
	rng.randomize()
	_build()
	ZombieMode.surge_warning.connect(_on_warning)
	ZombieMode.surge_started.connect(_on_started)
	ZombieMode.surge_ended.connect(_on_ended)

func _exit_tree() -> void:
	_restore_all()

func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F10 and phase == Phase.IDLE:
		debug_surge()

## Runs a whole surge by firing the mode's three signals: the warning, the quake `warn` seconds
## later, the end `strong` seconds after that (for tests, captures and F10).
func debug_surge(warn := WARNING_TIME, strong := 14.0) -> void:
	ZombieMode.surge_warning.emit()
	await get_tree().create_timer(warn).timeout
	if not is_inside_tree():
		return
	ZombieMode.surge_started.emit()
	await get_tree().create_timer(strong).timeout
	if not is_inside_tree():
		return
	ZombieMode.surge_ended.emit()

# --- Building the pools ---------------------------------------------------------------------------

func _build() -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_build_p = _flat(bus, "quake_buildup", false, -3.0)
	_main_p = _flat(bus, "quake_main", false, -1.0)
	_stinger_p = _flat(bus, "richter_stinger", false, -2.0)
	for n in ["horde_roar_1", "horde_roar_2"]:
		_roars.append(_flat(bus, n, true, -60.0))
	for i in ALARMS:
		var a := AudioStreamPlayer3D.new()
		a.bus = bus
		a.stream = _load("car_alarm_%d" % (1 + i % 2), true)
		a.unit_size = 14.0
		a.max_distance = 110.0
		a.volume_db = -5.0
		add_child(a)
		_alarms.append(a)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.12)
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_hazards.append(l)
		_alarm_delay.append(0.0)
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.bus = bus
		v.unit_size = 10.0
		v.max_distance = 90.0
		add_child(v)
		_voices.append(v)
	var dust_mat := _particle_material(Color(0.42, 0.38, 0.34))
	var grit_mat := StandardMaterial3D.new()
	grit_mat.albedo_color = Color(0.34, 0.31, 0.28)
	grit_mat.roughness = 1.0
	for i in DUST_SITES:
		_dust.append(_curtain(dust_mat))
		_grit.append(_grit_fall(grit_mat))
		_site_t.append(rng.randf_range(0.0, 2.5))
	for i in BURSTS:
		_bursts.append(_cloud(dust_mat))
	var sizes := [Vector3(0.34, 0.2, 0.28), Vector3(0.22, 0.22, 0.22), Vector3(0.46, 0.14, 0.3)]
	for i in CHUNKS:
		_chunks.append(_chunk(sizes[i % 3], grit_mat))
	for i in CRACKS:
		var d := Decal.new()
		d.texture_albedo = _crack_texture(i % 3)
		d.texture_emission = _crack_em[i % 3]
		d.texture_normal = _crack_nm[i % 3]
		d.normal_fade = 0.2
		d.emission_energy = 0.0
		d.size = Vector3(3.0, 0.3, 3.0)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 38.0
		d.distance_fade_length = 12.0
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)
		_decal_a.append(0.0)

func _flat(bus: String, sound: String, loop: bool, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = _load(sound, loop)
	p.volume_db = db
	add_child(p)
	return p

## A wav of the quake set; loops are made loop here (the import setting is not relied on).
static func _load(sound: String, loop: bool) -> AudioStream:
	var key := sound + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s := load(SFX_DIR + sound + ".wav") as AudioStreamWAV
	if s != null and loop:
		s = s.duplicate() as AudioStreamWAV
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		var bytes := 2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1
		s.loop_end = s.data.size() / (bytes * (2 if s.stereo else 1))
	_streams[key] = s
	return s

static func _particle_material(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = DustShader
	m.set_shader_parameter("noise_tex", NightAtmos.noise_texture())
	m.set_shader_parameter("albedo", c)
	return m

static func _soft_texture() -> Texture2D:
	if _soft != null:
		return _soft
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	_soft = g
	return g

## A curtain of dust coming off a building's edge: a wide box of slow soft puffs that sink.
func _curtain(mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 22
	p.lifetime = 2.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.2, 0.15, 0.25)
	p.direction = Vector3.DOWN
	p.spread = 22.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, -2.2, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.8
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(0.18, Color(1.0, 1.0, 1.0, 0.55))
	g.set_color(g.get_point_count() - 1, Color(0.8, 0.78, 0.75, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## Grit and plaster falling with it: small dark lumps.
func _grit_fall(mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 10
	p.lifetime = 1.9
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(2.0, 0.1, 0.2)
	p.direction = Vector3.DOWN
	p.spread = 30.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -13.0, 0)
	p.angular_velocity_min = -280.0
	p.angular_velocity_max = 280.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.5
	var b := BoxMesh.new()
	b.size = Vector3(0.07, 0.05, 0.06)
	b.material = mat
	p.mesh = b
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## The cloud that goes up where the ground splits.
func _cloud(mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 20
	p.lifetime = 2.2
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -0.35, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.8
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	g.set_color(1, Color(0.8, 0.78, 0.75, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

## A loose chunk of concrete: it collides with the world and with nothing else.
func _chunk(size: Vector3, mat: Material) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = 0
	b.collision_mask = 1
	b.mass = 2.0
	b.freeze = true
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.visible = false
	b.can_sleep = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_child(mi)
	add_child(b)
	return b

## A crack network drawn here: the black split with its branches, a spill of grey-brown dust and chips
## along the lips (speckled, not a clean halo), a normal map so the lamps catch the broken edges, and in
## the emission map only a few tiny embers deep in the split.
static func _crack_texture(variant: int) -> Texture2D:
	while _crack_tex.size() <= variant:
		_crack_tex.append(null)
		_crack_em.append(null)
		_crack_nm.append(null)
	if _crack_tex[variant] != null:
		return _crack_tex[variant]
	var n := 192
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var glow := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 4100 + variant * 31
	var segs: Array = []
	var arms := 5 + variant
	for i in arms:
		_crack_walk(r, segs, Vector2(n, n) * 0.5, TAU * (i + r.randf_range(-0.25, 0.25)) / arms, 4.2, 0.0, n * 0.46)
	var core := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var wide := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for pass_i in 3:
		var si := 0
		for s in segs:
			si += 1
			var a: Vector2 = s[0]
			var b: Vector2 = s[1]
			var w: float = s[2]
			var steps := int(a.distance_to(b)) + 1
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				if pass_i == 0:
					_stamp(img, p, w * 5.0 + 4.0, Color(0.46, 0.42, 0.36, 0.8), false)
					_stamp(wide, p, w * 3.0 + 2.5, Color(1, 1, 1, 1), false)
				elif pass_i == 1:
					_stamp(img, p, w, Color(0.008, 0.007, 0.007, 1.0), true)
					_stamp(core, p, w, Color(1, 1, 1, 1), true)
				elif si % 9 == 0 and w > 2.0:
					# A glint of heat far down in a few of the wider stretches.
					_stamp(glow, p, maxf(w * 0.28, 0.7), Color(0.75, 0.24, 0.05, 0.8), true)
	# Speckle the dust spill: grains and chips, not a smooth halo.
	for y in n:
		for x in n:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.r > 0.1:
				var g := r.randf()
				var k := 0.35 + 0.9 * g * g
				img.set_pixel(x, y, Color(c.r * (0.8 + 0.4 * r.randf()), c.g * (0.8 + 0.4 * r.randf()), c.b, minf(c.a * k, 0.9)))
	# Height: the split sunk, the lips raised a little; the normals are its slope.
	var h := PackedFloat32Array()
	h.resize(n * n)
	for y in n:
		for x in n:
			h[y * n + x] = wide.get_pixel(x, y).a * 0.55 - core.get_pixel(x, y).a * 1.4 + (r.randf() - 0.5) * 0.08 * wide.get_pixel(x, y).a
	var nm := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := h[y * n + mini(x + 1, n - 1)] - h[y * n + maxi(x - 1, 0)]
			var dy := h[mini(y + 1, n - 1) * n + x] - h[maxi(y - 1, 0) * n + x]
			var v := Vector3(-dx * 1.8, -dy * 1.8, 1.0).normalized()
			nm.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5, 1.0))
	_crack_tex[variant] = ImageTexture.create_from_image(img)
	_crack_em[variant] = ImageTexture.create_from_image(glow)
	_crack_nm[variant] = ImageTexture.create_from_image(nm)
	return _crack_tex[variant]

static func _crack_walk(r: RandomNumberGenerator, segs: Array, from: Vector2, ang: float, width: float, travelled: float, limit: float) -> void:
	var pos := from
	var w := width
	var dist := travelled
	while dist < limit and w > 0.45:
		var step := r.randf_range(6.0, 12.0)
		ang += r.randf_range(-0.55, 0.55)
		var nxt := pos + Vector2(cos(ang), sin(ang)) * step
		segs.append([pos, nxt, w])
		if r.randf() < 0.17 and w > 1.2:
			_crack_walk(r, segs, nxt, ang + r.randf_range(0.5, 1.1) * (1.0 if r.randf() < 0.5 else -1.0), w * 0.6, dist, limit)
		pos = nxt
		dist += step
		w -= 0.14
		# Cracks thin out towards the rim of the picture.
		if pos.distance_to(Vector2(96, 96)) > 90.0:
			break

static func _stamp(img: Image, p: Vector2, radius: float, c: Color, solid: bool) -> void:
	var rr := int(ceil(radius))
	for y in range(-rr, rr + 1):
		for x in range(-rr, rr + 1):
			var d := sqrt(float(x * x + y * y))
			if d > radius:
				continue
			var px := int(p.x) + x
			var py := int(p.y) + y
			if px < 0 or py < 0 or px >= img.get_width() or py >= img.get_height():
				continue
			var have := img.get_pixel(px, py)
			var a := c.a * (1.0 - smoothstep(radius * 0.55, radius, d)) if not solid else c.a * (1.0 - smoothstep(radius * 0.7, radius, d))
			if a > have.a:
				img.set_pixel(px, py, Color(c.r, c.g, c.b, a))

# --- The signals ----------------------------------------------------------------------------------

func _on_warning() -> void:
	if phase == Phase.WARNING or phase == Phase.QUAKE:
		return
	if phase == Phase.ENDING:
		_finish()
	_begin()
	phase = Phase.WARNING
	t = 0.0
	level = 0.15
	_build_p.play()
	var seismo := _seismo()
	if seismo != null:
		seismo.clear()
		seismo.shown = true

func _on_started() -> void:
	if phase == Phase.QUAKE:
		return
	if phase == Phase.IDLE or phase == Phase.ENDING:
		if phase == Phase.ENDING:
			_finish()
		_begin()
		var seismo := _seismo()
		if seismo != null:
			seismo.clear()
			seismo.shown = true
	phase = Phase.QUAKE
	t = 0.0
	_r0 = richter
	_stung = false
	_crack_t = 0.0
	_after_t = rng.randf_range(5.0, 8.0)
	_main_p.play()
	_build_p.stop()
	for r in _roars:
		r.play()
	# The first jolt: rubble up, a crack under your feet.
	for i in 3:
		_launch_chunk(_around(1.5, 6.0), Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(2.5, 5.0), rng.randf_range(-1.5, 1.5)))
	_open_crack(true)

func _on_ended() -> void:
	if phase == Phase.IDLE or phase == Phase.ENDING:
		return
	phase = Phase.ENDING
	t = 0.0
	_level_end = level
	_roar_end = roar_level
	_alarm_fade = 1.0
	_build_p.stop()
	var seismo := _seismo()
	if seismo != null:
		seismo.shown = false

func _begin() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if city == null:
		city = get_parent().get("city") if get_parent() != null else null
	if city == null:
		city = get_tree().current_scene
	_clock = 0.0
	richter = 1.0
	roar_level = 0.0
	trauma_target = 0.0
	_stung = false
	_alarm_fade = 1.0
	_grab_lights()
	_pick_cars()
	for i in DUST_SITES:
		_site_t[i] = rng.randf_range(0.0, 1.2)
	_rumble_t = 0.0

# --- The clock ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if auto:
		advance(delta)

func advance(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	# The run ended mid-surge (the surge logic aborts without a surge_ended): let go of everything.
	if (ZombieMode.over or not ZombieMode.active) and (phase == Phase.WARNING or phase == Phase.QUAKE):
		_on_ended()
	_clock += delta
	t += delta
	match phase:
		Phase.WARNING:
			var k := clampf(t / WARNING_TIME, 0.0, 1.0)
			level = 0.15 + 0.35 * k * k
			trauma_target = lerpf(0.08, 0.42, pow(k, 1.5))
			richter = 1.0 + (RICHTER_WARN_TOP - 1.0) * pow(k, 1.2)
		Phase.QUAKE:
			_advance_quake(delta)
		Phase.ENDING:
			var f := clampf(1.0 - t / FADE_TIME, 0.0, 1.0)
			level = _level_end * f
			trauma_target = 0.0
			roar_level = _roar_end * f
			_alarm_fade = f
	var seismo := _seismo()
	if seismo != null:
		seismo.amplitude = level
		seismo.value = richter
	_apply_shake()
	_pulse_pad(delta)
	_update_lamps()
	_update_alarms(delta)
	_update_dust(delta)
	_update_cracks(delta)
	_update_roar()
	if phase == Phase.ENDING and t >= FADE_TIME:
		_finish()

func _advance_quake(delta: float) -> void:
	var attack := smoothstep(0.0, 0.2, t)
	if t < STRONG_TIME:
		level = attack
		trauma_target = 0.95 * attack
	else:
		var d := clampf((t - STRONG_TIME) / DECAY_TIME, 0.0, 1.0)
		var e := 1.0 - (1.0 - d) * (1.0 - d)
		level = lerpf(1.0, 0.25, e)
		trauma_target = 0.95 * pow(1.0 - d, 2.0)
	roar_level = clampf(t / ROAR_RISE, 0.0, 1.0)
	var k := clampf(t / RICHTER_RISE, 0.0, 1.0)
	richter = lerpf(_r0, RICHTER_PEAK, k * k)
	if k >= 1.0 and not _stung:
		_stung = true
		richter = RICHTER_PEAK
		stinger_plays += 1
		_stinger_p.play()
	# Cracks open while it is strong, now and then after; aftershocks later still.
	_crack_t -= delta
	if _crack_t <= 0.0:
		_crack_t = rng.randf_range(0.35, 0.65) if t < STRONG_TIME else rng.randf_range(1.0, 1.9)
		if t < STRONG_TIME + DECAY_TIME:
			_open_crack(false)
	if t > STRONG_TIME + DECAY_TIME:
		_after_t -= delta
		if _after_t <= 0.0:
			_after_t = rng.randf_range(5.0, 8.0)
			_aftershock()

func _aftershock() -> void:
	level = maxf(level, 0.5)
	var feel = _feel()
	if feel != null:
		feel.add_trauma(0.3 * _motion_scale())
	_open_crack(false)

## Everything put back: lights, alarms, double points, cracks, rubble, sounds, the trace.
func _finish() -> void:
	phase = Phase.IDLE
	level = 0.0
	roar_level = 0.0
	trauma_target = 0.0
	_restore_all()

func _restore_all() -> void:
	_restore_lamps()
	for i in _alarms.size():
		_alarms[i].stop()
		_hazards[i].visible = false
		_hazards[i].light_energy = 0.0
	for r in _roars:
		r.stop()
	if _build_p != null:
		_build_p.stop()
	for p in _dust:
		p.emitting = false
	for p in _grit:
		p.emitting = false
	for i in _decals.size():
		_decals[i].visible = false
		_decal_a[i] = 0.0
	for c in _chunks:
		_park(c)
	var seismo := _seismo()
	if seismo != null and phase == Phase.IDLE:
		seismo.shown = false

func _seismo() -> Control:
	var hud := get_tree().get_first_node_in_group("zombie_hud") if is_inside_tree() else null
	return hud.get("seismo") as Control if hud != null else null

# --- Camera and pad -------------------------------------------------------------------------------

func _motion_scale() -> float:
	return 1.0 if Graphics.camera_motion else REDUCED

func _feel() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player.get("feel") as Node if _player != null else null

## Holds the camera's trauma at the target: FPFeel's own shake in first person, the player's kick
## in third.
func _apply_shake() -> void:
	var want := trauma_target * _motion_scale()
	shake_applied = want
	var feel = _feel()
	if feel != null and want > feel.trauma:
		feel.add_trauma(want - feel.trauma)
	if _player != null and not bool(_player.get("_first_person")) and Graphics.camera_motion and _player.has_method("kick"):
		_player.kick(want * TP_KICK)

func _pulse_pad(delta: float) -> void:
	_rumble_t -= delta
	if _rumble_t > 0.0 or level < 0.05:
		return
	_rumble_t = 0.1
	var pulse := [0.08 + 0.5 * level, 0.12 + 0.88 * level * level, 0.14]
	var holder := get_tree().get_first_node_in_group("weapon_holder")
	var pad = holder.get_node_or_null("PadRumble") if holder != null else null
	rumble_pulses += 1
	if pad != null:
		pad.ask(pulse, "quake")
	elif Graphics.rumble:
		load("res://player/PadRumble.gd").vibrate(pulse[0], pulse[1], pulse[2], "quake")

# --- Street lights --------------------------------------------------------------------------------

func _grab_lights() -> void:
	_lamps.clear()
	var entries = city.get("_night_lights") if city != null else null
	if not entries is Array:
		return
	var i := 0
	for e in entries:
		var light := e[0] as Light3D
		if light == null or not is_instance_valid(light) or light.get_parent() == null:
			continue
		if not String(light.get_parent().name).begins_with("Streetlight"):
			continue
		if not light.is_visible_in_tree():
			continue
		_lamps.append({"light": light, "entry": e, "seed": rng.randf_range(0.0, 100.0), "dies": i % 4 == 0})
		i += 1

## Stutter: each lamp drops to a dim or dark flash with a chance that grows with `level`; every
## fourth one gives out for good while the quake is on.
func _update_lamps() -> void:
	for lamp in _lamps:
		var light := lamp["light"] as Light3D
		if not is_instance_valid(light) or not light.visible:
			continue
		var base := float((lamp["entry"] as Array)[1])
		var f := 1.0
		if level > 0.02:
			var s: float = lamp["seed"]
			var step := floori(_clock * (9.0 + 12.0 * level) + s)
			var h := fposmod(sin(step * 12.9898 + s * 78.233) * 43758.5453, 1.0)
			var p := level * 0.85
			if h < p:
				f = h / p * 0.35
			if phase == Phase.QUAKE and lamp["dies"] and level > 0.6:
				f = 0.0 if h < 0.8 else f
		light.light_energy = base * f

func _restore_lamps() -> void:
	for lamp in _lamps:
		var light := lamp["light"] as Light3D
		if not is_instance_valid(light):
			continue
		var e: Array = lamp["entry"]
		if city != null and city.has_method("_set_light"):
			city._set_light(e)
		else:
			light.light_energy = float(e[1])
	_lamps.clear()

# --- Car alarms -----------------------------------------------------------------------------------

func _pick_cars() -> void:
	_cars.clear()
	if city == null or _player == null:
		return
	var found: Array = []
	for car in city.find_children("Car*", "StaticBody3D", true, false):
		if not (car as Node3D).is_visible_in_tree():
			continue
		var d := (car as Node3D).global_position.distance_to(_player.global_position)
		if d >= 5.0 and d <= 70.0:
			found.append([d, car])
	found.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(ALARMS, found.size()):
		_cars.append(found[i][1])
		_alarm_delay[i] = rng.randf_range(0.0, 1.4) if i > 0 else 0.0
		_alarms[i].global_position = (found[i][1] as Node3D).global_position + Vector3(0, 1.0, 0)
		_alarms[i].pitch_scale = rng.randf_range(0.94, 1.06)
		_alarms[i].volume_db = -5.0
		_hazards[i].global_position = _alarms[i].global_position + Vector3(0, 0.4, 0)

func _update_alarms(delta: float) -> void:
	for i in _cars.size():
		var a := _alarms[i]
		if phase == Phase.WARNING or phase == Phase.QUAKE:
			_alarm_delay[i] -= delta
			if _alarm_delay[i] <= 0.0 and not a.playing:
				a.play(rng.randf_range(0.0, 2.0))
		a.volume_db = -5.0 + (linear_to_db(maxf(_alarm_fade, 0.001)) if phase == Phase.ENDING else 0.0)
		var on := a.playing
		_hazards[i].visible = on
		_hazards[i].light_energy = (2.2 if fmod(_clock * 2.4 + i * 0.37, 1.0) < 0.5 else 0.0) * _alarm_fade if on else 0.0

## How many alarms are ringing (tests).
func alarms_playing() -> int:
	var n := 0
	for a in _alarms:
		if a.playing:
			n += 1
	return n

# --- Dust and grit from the buildings' edges ------------------------------------------------------

func _update_dust(delta: float) -> void:
	if _player == null:
		return
	var active := ceili(clampf(level, 0.0, 1.0) * DUST_SITES) if phase != Phase.IDLE else 0
	if phase == Phase.ENDING:
		active = ceili(level * DUST_SITES)
	for i in DUST_SITES:
		var on := i < active
		_dust[i].emitting = on
		_grit[i].emitting = on
		if not on:
			continue
		_site_t[i] -= delta
		if _site_t[i] <= 0.0:
			_site_t[i] = rng.randf_range(2.2, 3.6)
			_resite(i)

## Moves a dust site to a building wall near the player (a ray along a random bearing at roof
## height), or to a point 14 m out if there is none; and the sound of it coming down.
func _resite(i: int) -> void:
	var from := _player.global_position + Vector3(0, rng.randf_range(4.0, 8.0), 0)
	var best := Vector3.ZERO
	var normal := Vector3.UP
	var got := false
	var space := _player.get_world_3d().direct_space_state
	for attempt in 4:
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 28.0, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.5 and from.distance_to(hit["position"]) > 4.0:
			best = hit["position"]
			normal = hit["normal"]
			got = true
			break
	var xf := Transform3D.IDENTITY
	if got:
		var tangent := Vector3.UP.cross(normal).normalized()
		xf.basis = Basis(tangent, Vector3.UP, normal)
		xf.origin = best + normal * 0.35 + Vector3(0, rng.randf_range(1.0, 5.0), 0)
	else:
		var ang2 := rng.randf() * TAU
		xf.origin = _player.global_position + Vector3(cos(ang2), 0, sin(ang2)) * 14.0 + Vector3(0, 9.0, 0)
	_dust[i].global_transform = xf
	_grit[i].global_transform = xf
	_dust[i].restart()
	_grit[i].restart()
	_dust[i].emitting = true
	_grit[i].emitting = true
	_voice(xf.origin, "debris_fall_%d" % (1 + rng.randi() % 3), -6.0)

## Sites that are emitting (tests).
func dust_active() -> int:
	var n := 0
	for p in _dust:
		if p.emitting:
			n += 1
	return n

# --- Cracks, bursts and rubble --------------------------------------------------------------------

## A point on the ground `lo` to `hi` metres round the player, mostly where they are looking.
func _around(lo: float, hi: float) -> Vector3:
	if _player == null:
		return Vector3.ZERO
	var ang := rng.randf() * TAU
	if rng.randf() < 0.8 and _player.get("_look_yaw") != null:
		# The camera looks down -Z turned by the yaw: forward is (-sin y, 0, -cos y).
		var yaw := float(_player.get("_look_yaw"))
		ang = atan2(-sin(yaw), -cos(yaw)) + rng.randf_range(-0.9, 0.9)
	var dir := Vector3(sin(ang), 0, cos(ang))
	return _player.global_position + dir * rng.randf_range(lo, hi)

func _open_crack(under_player: bool) -> void:
	if _player == null:
		return
	var pos := _player.global_position + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)) if under_player else _around(3.0, 9.0)
	var i := _decal_next
	_decal_next = (_decal_next + 1) % CRACKS
	var d := _decals[i]
	var w := rng.randf_range(2.4, 4.6)
	d.size = Vector3(w, 0.3, w)
	d.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(pos.x, _player.global_position.y + 0.05, pos.z))
	d.modulate = Color(1, 1, 1, 0)
	d.visible = true
	_decal_a[i] = 0.0
	cracks_made += 1
	var b := _bursts[_burst_next]
	_burst_next = (_burst_next + 1) % BURSTS
	b.global_position = Vector3(pos.x, _player.global_position.y + 0.1, pos.z)
	b.restart()
	b.emitting = true
	_voice(pos, "quake_crack_%d" % (1 + rng.randi() % 3), -2.0)
	if rng.randf() < 0.7:
		_launch_chunk(pos + Vector3(0, 0.3, 0), Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(3.0, 6.0), rng.randf_range(-2.0, 2.0)))

func _update_cracks(delta: float) -> void:
	for i in CRACKS:
		if not _decals[i].visible:
			continue
		var rise := minf(_decal_a[i] + delta / 0.18, 1.0)
		_decal_a[i] = rise
		var fade := _alarm_fade if phase == Phase.ENDING else 1.0
		_decals[i].modulate = Color(1, 1, 1, rise * fade)
		_decals[i].emission_energy = 0.2 * rise * fade * (0.5 + 0.5 * sin(_clock * 3.0 + i * 1.7))

func cracks_visible() -> int:
	var n := 0
	for d in _decals:
		if d.visible:
			n += 1
	return n

func _launch_chunk(pos: Vector3, vel: Vector3) -> void:
	var c := _chunks[_chunk_next]
	_chunk_next = (_chunk_next + 1) % CHUNKS
	c.freeze = true
	c.global_position = pos
	c.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	c.visible = true
	c.freeze = false
	c.linear_velocity = vel
	c.angular_velocity = Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9))

func _park(c: RigidBody3D) -> void:
	c.freeze = true
	c.visible = false
	c.linear_velocity = Vector3.ZERO
	c.angular_velocity = Vector3.ZERO

func chunks_visible() -> int:
	var n := 0
	for c in _chunks:
		if c.visible:
			n += 1
	return n

func _voice(pos: Vector3, sound: String, db: float) -> void:
	var v := _voices[_voice_next]
	_voice_next = (_voice_next + 1) % VOICES
	var s := _load(sound, false)
	if s == null:
		return
	v.stream = s
	v.volume_db = db
	v.pitch_scale = rng.randf_range(0.92, 1.08)
	v.global_position = pos
	v.play()

# --- The horde's roar -----------------------------------------------------------------------------

func _update_roar() -> void:
	for i in _roars.size():
		var r := _roars[i]
		if roar_level <= 0.0:
			if r.playing and phase != Phase.QUAKE:
				r.stop()
			continue
		r.volume_db = lerpf(-42.0, -5.0, pow(roar_level, 0.7)) - 3.0 * i
		r.pitch_scale = (0.9 - 0.12 * i) + 0.2 * roar_level

func roars_playing() -> int:
	var n := 0
	for r in _roars:
		if r.playing:
			n += 1
	return n

## The roar's loudest player in dB (tests).
func roar_db() -> float:
	return _roars[0].volume_db
