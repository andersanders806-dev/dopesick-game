extends Node3D
## What a shot leaves behind (zombie mode): a bullet hole, sparks and a puff of grit where
## it hits a wall or the ground, a puff of blood and the sound of meat where it hits a
## zombie, the smoke that hangs off the muzzle, and (if the mode's option is on) floating
## damage numbers. Everything is pooled: no node is made while shooting once the pools are
## filled, and a shotgun's eight pellets share a small per-frame budget.
##
## One per scene, found by group "impact_fx" (ImpactFX.of(node) makes it on first use).

const SFX_DIR := "res://assets/sfx/guns/"
const DECALS := 48
const SPARKS := 10
const DUST := 10
const BLOOD := 16
const SMOKE := 6
const VOICES := 10
const NUMBERS := 10
## Most of each per physics frame (a shotgun blast is eight impacts).
const BUDGET := {"decal": 4, "spark": 4, "dust": 3, "blood": 5, "sound": 4}

static var _streams := {}
static var _hole: Texture2D
static var _soft: Texture2D

var rng := RandomNumberGenerator.new()
var _decals: Array[Decal] = []
var _decal_next := 0
var _sparks: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _blood: Array[CPUParticles3D] = []
var _mist: Array[CPUParticles3D] = []
var _smoke: Array[CPUParticles3D] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _next := {"spark": 0, "dust": 0, "blood": 0, "smoke": 0, "voice": 0, "number": 0}
var _numbers: Array = []
var _used := {}
var _frame := -1
## Counts for the tests.
var impacts := 0
var puffs := 0

## The scene's ImpactFX (made, parented to the current scene, on first use).
static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("impact_fx")
	if found != null:
		return found as Node3D
	var fx: Node3D = (load("res://fx/ImpactFX.gd") as GDScript).new()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(fx)
	return fx

func _ready() -> void:
	add_to_group("impact_fx")
	name = "ImpactFX"
	rng.randomize()
	_build()

# --- Pools ---------------------------------------------------------------------------

func _build() -> void:
	var hole := _hole_texture()
	for i in DECALS:
		var d := Decal.new()
		d.texture_albedo = hole
		d.size = Vector3(0.16, 0.3, 0.16)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 30.0
		d.distance_fade_length = 10.0
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)
	var spark_mat := _particle_material(Color(1.0, 0.75, 0.3), true, true)
	var dust_mat := _particle_material(Color(0.62, 0.58, 0.52), false, false)
	var blood_mat := _particle_material(Color(0.5, 0.02, 0.02), false, false)
	var mist_mat := _particle_material(Color(0.42, 0.02, 0.02), false, false)
	var smoke_mat := _particle_material(Color(0.72, 0.72, 0.74), false, false)
	for i in SPARKS:
		_sparks.append(_burst(spark_mat, 9, 0.28, 0.012, 0.03, 2.5, 6.0, 40.0, Vector3(0, -9.0, 0), Color(1.0, 0.8, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0), 0.0))
	for i in DUST:
		_dust.append(_burst(dust_mat, 6, 0.75, 0.09, 0.22, 0.4, 1.3, 55.0, Vector3(0, 0.25, 0), Color(0.62, 0.58, 0.52, 0.55), Color(0.5, 0.47, 0.42, 0.0), 2.2))
	for i in BLOOD:
		_blood.append(_burst(blood_mat, 14, 0.6, 0.025, 0.06, 1.2, 4.2, 38.0, Vector3(0, -10.0, 0), Color(0.55, 0.03, 0.03, 1.0), Color(0.3, 0.0, 0.0, 0.0), 0.0))
		_mist.append(_burst(mist_mat, 5, 0.45, 0.14, 0.3, 0.3, 1.2, 50.0, Vector3(0, -0.5, 0), Color(0.5, 0.02, 0.02, 0.5), Color(0.3, 0.0, 0.0, 0.0), 1.5))
	for i in SMOKE:
		_smoke.append(_burst(smoke_mat, 7, 1.3, 0.07, 0.14, 0.2, 0.7, 28.0, Vector3(0, 0.35, 0), Color(0.75, 0.75, 0.78, 0.4), Color(0.6, 0.6, 0.62, 0.0), 2.6))
	for i in VOICES:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 8.0
		a.max_distance = 70.0
		a.volume_db = -3.0
		add_child(a)
		_voices.append(a)

## One pooled one-shot burst: a CPUParticles3D whose quads fade from `c0` to `c1` and grow by
## `grow` over their life; `up` points the way it sprays (the node's +Y).
func _burst(mat: Material, amount: int, life: float, s0: float, s1: float, v0: float, v1: float, spread: float, gravity: Vector3, c0: Color, c1: Color, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.gravity = gravity
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	if grow > 0.0:
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.5))
		curve.add_point(Vector2(1.0, 0.5 + grow * 0.5))
		p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

static func _particle_material(c: Color, additive: bool, bright: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_texture()
	m.albedo_color = c if not bright else Color(1.6, 1.3, 0.8)
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	return m

## A soft round dot.
static func _soft_texture() -> Texture2D:
	if _soft != null:
		return _soft
	var g := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.set_offset(0, 0.0)
	grad.set_offset(1, 1.0)
	g.gradient = grad
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	_soft = g
	return g

## A bullet hole: dark crater with a chipped, paler rim, from a small image drawn here.
static func _hole_texture() -> Texture2D:
	if _hole != null:
		return _hole
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	for y in n:
		for x in n:
			var p := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5)
			var r := p.length() / (n * 0.5)
			var ang := atan2(p.y, p.x)
			var wob := noise.get_noise_2d(x, y) * 0.22 + sin(ang * 7.0) * 0.05
			var rr := r + wob
			var a := 0.0
			var col := Color(0.03, 0.03, 0.03)
			if rr < 0.2:
				a = 1.0
			elif rr < 0.5:
				a = lerpf(0.95, 0.55, (rr - 0.2) / 0.3)
				col = Color(0.08, 0.07, 0.065)
			elif rr < 0.95:
				var k := (rr - 0.5) / 0.45
				a = lerpf(0.5, 0.0, k * k)
				col = Color(0.12, 0.11, 0.1).lerp(Color(0.5, 0.48, 0.44), 0.5 * (1.0 - k))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	img.generate_mipmaps()
	_hole = ImageTexture.create_from_image(img)
	return _hole

static func stream(name_: String) -> AudioStream:
	if not _streams.has(name_):
		_streams[name_] = load(SFX_DIR + name_ + ".wav")
	return _streams[name_]

# --- Budget --------------------------------------------------------------------------

func _allow(kind: String) -> bool:
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_used.clear()
	var n: int = _used.get(kind, 0)
	if n >= int(BUDGET.get(kind, 99)):
		return false
	_used[kind] = n + 1
	return true

static func _up_basis(n: Vector3, at: Vector3) -> Transform3D:
	var up := n.normalized() if n.length() > 0.001 else Vector3.UP
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(ref).normalized()
	var z := x.cross(up).normalized()
	return Transform3D(Basis(x, up, z), at)

func _fire(p: CPUParticles3D, at: Transform3D) -> void:
	p.global_transform = at
	p.restart()
	p.emitting = true
	puffs += 1

# --- A bullet into the world --------------------------------------------------------------

func bullet_hit(pos: Vector3, normal: Vector3, _collider: Object = null) -> void:
	impacts += 1
	var n := normal if normal.length() > 0.001 else Vector3.UP
	if _allow("decal"):
		var d := _decals[_decal_next]
		_decal_next = (_decal_next + 1) % _decals.size()
		var xf := _up_basis(n, pos + n * 0.01)
		xf.basis = xf.basis.rotated(n, rng.randf() * TAU)
		d.global_transform = xf
		var s := rng.randf_range(0.8, 1.35)
		d.size = Vector3(0.16 * s, 0.3, 0.16 * s)
		d.visible = true
	var at := _up_basis(n, pos + n * 0.02)
	if _allow("spark"):
		_fire(_sparks[_next["spark"]], at)
		_next["spark"] = (_next["spark"] + 1) % _sparks.size()
	if _allow("dust"):
		_fire(_dust[_next["dust"]], at)
		_next["dust"] = (_next["dust"] + 1) % _dust.size()
	if _allow("sound"):
		_play(pos, "bullet_impact_concrete_%d" % (1 + rng.randi() % 3), -4.0)
		if rng.randf() < 0.25:
			_play(pos, "ricochet_%d" % (1 + rng.randi() % 2), -7.0)

## A bullet into a zombie: blood out of the way it went, and the sound of it.
func blood_hit(pos: Vector3, dir: Vector3, part: String, killed := false, power := 1.0) -> void:
	impacts += 1
	if _allow("blood"):
		# The spray goes on through, a little back too.
		var spray := (dir.normalized() + Vector3(0, 0.25, 0)).normalized()
		var at := _up_basis(spray, pos)
		_fire(_blood[_next["blood"]], at)
		_fire(_mist[_next["blood"]], at)
		_next["blood"] = (_next["blood"] + 1) % _blood.size()
		if part == "head" or killed or power > 1.4:
			var back := _up_basis(-dir.normalized() + Vector3(0, 0.3, 0), pos)
			_fire(_blood[_next["blood"]], back)
			_next["blood"] = (_next["blood"] + 1) % _blood.size()
	if _allow("sound"):
		var s := "flesh_hit_%d" % (1 + rng.randi() % 3)
		if part == "head":
			s = "headshot_crunch_%d" % (1 + rng.randi() % 2)
		_play(pos, s, -2.0 if part == "head" else -5.0)

func muzzle_smoke(pos: Vector3, dir: Vector3, size := 1.0) -> void:
	var p := _smoke[_next["smoke"]]
	_next["smoke"] = (_next["smoke"] + 1) % _smoke.size()
	var up := (dir.normalized() * 0.6 + Vector3(0, 0.8, 0)).normalized()
	p.scale_amount_min = 0.07 * size
	p.scale_amount_max = 0.14 * size
	_fire(p, _up_basis(up, pos))

func _play(pos: Vector3, sound: String, db: float) -> void:
	var a := _voices[_next["voice"]]
	_next["voice"] = (_next["voice"] + 1) % _voices.size()
	var st := stream(sound)
	if st == null:
		return
	a.stream = st
	a.volume_db = db
	a.pitch_scale = rng.randf_range(0.92, 1.08)
	a.global_position = pos
	a.play()

## The pooled sound players in use (tests).
func voices_busy() -> int:
	var n := 0
	for a in _voices:
		if a.playing:
			n += 1
	return n

func decals_shown() -> int:
	var n := 0
	for d in _decals:
		if d.visible:
			n += 1
	return n

# --- Damage numbers --------------------------------------------------------------------

func damage_number(pos: Vector3, amount: float, part: String, killed: bool) -> void:
	if not ZombieMode.damage_numbers:
		return
	var l: Label3D
	if _numbers.size() < NUMBERS:
		l = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.pixel_size = 0.004
		l.font_size = 64
		l.outline_size = 14
		l.outline_modulate = Color(0, 0, 0, 0.9)
		add_child(l)
		_numbers.append([l, 99.0])
	else:
		var oldest := 0
		for i in _numbers.size():
			if _numbers[i][1] > _numbers[oldest][1]:
				oldest = i
		l = _numbers[oldest][0]
		_numbers[oldest][1] = 0.0
	for e in _numbers:
		if e[0] == l:
			e[1] = 0.0
	l.text = str(int(round(amount)))
	l.modulate = Color(1, 0.5, 0.15) if part == "head" else (Color(1, 0.2, 0.15) if killed else Color(1, 1, 1))
	l.scale = Vector3.ONE * (1.4 if part == "head" or killed else 1.0)
	l.global_position = pos + Vector3(rng.randf_range(-0.15, 0.15), 0.3, rng.randf_range(-0.15, 0.15))
	l.visible = true

func _process(delta: float) -> void:
	for e in _numbers:
		var l: Label3D = e[0]
		if e[1] > 1.0:
			l.visible = false
			continue
		e[1] += delta
		l.global_position.y += delta * 0.7
		l.modulate.a = 1.0 - smoothstep(0.5, 1.0, e[1])

func numbers_shown() -> int:
	var n := 0
	for e in _numbers:
		if (e[0] as Label3D).visible and e[1] <= 1.0:
			n += 1
	return n
