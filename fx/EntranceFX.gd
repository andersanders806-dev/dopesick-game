extends Node3D
## What the dead's entrances (npc/Entrances.gd) and the quake leave on the block: a burst of dirt and
## a dust cloud and a crack in the street where one climbs out of the ground (a manhole's lid is
## thrown off), a puff and a thud where one lands off a roof, glass and splinters where one comes
## through a shop front, cracks opening in the pavement round the player. Everything is pooled;
## nothing is made while it plays once the pools are filled.
##
## One per scene, found by group "entrance_fx" (EntranceFX.of(node) makes it on first use).

const SFX_DIR := "res://assets/sfx/quake/"
const CRACKS := 28
const DIRT := 6
const DUST := 8
const GLASS := 6
const VOICES := 8
## Most of each per physics frame: a surge opens many at once.
const BUDGET := {"crack": 3, "dirt": 3, "dust": 4, "glass": 3, "sound": 4}

static var _streams := {}
static var _crack_tex: Texture2D
static var _soft: Texture2D

static func _particle_material(c: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_texture()
	m.albedo_color = c
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

## A soft round dot.
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

var rng := RandomNumberGenerator.new()
var _cracks: Array[Decal] = []
var _crack_next := 0
var _dirt: Array[CPUParticles3D] = []
var _dust: Array[CPUParticles3D] = []
var _glass: Array[CPUParticles3D] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _next := {"dirt": 0, "dust": 0, "glass": 0, "voice": 0}
var _used := {}
var _frame := -1
## Counts for the tests.
var bursts := 0
var landings := 0
var smashes := 0
var cracks_made := 0
var lids_thrown := 0

static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("entrance_fx")
	if found != null:
		return found as Node3D
	var fx: Node3D = (load("res://fx/EntranceFX.gd") as GDScript).new()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(fx)
	return fx

func _ready() -> void:
	add_to_group("entrance_fx")
	name = "EntranceFX"
	rng.randomize()
	_build()

func _build() -> void:
	var tex := crack_texture()
	for i in CRACKS:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(2.0, 1.2, 2.0)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 45.0
		d.distance_fade_length = 15.0
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		add_child(d)
		_cracks.append(d)
	var dirt_mat: StandardMaterial3D = _particle_material(Color(0.2, 0.14, 0.1), false)
	var dust_mat: StandardMaterial3D = _particle_material(Color(0.5, 0.45, 0.4), false)
	var glass_mat: StandardMaterial3D = _particle_material(Color(0.8, 0.9, 1.0), true)
	for i in DIRT:
		_dirt.append(_burst(dirt_mat, 46, 1.3, 0.06, 0.2, 3.0, 8.0, 32.0, Vector3(0, -13.0, 0), Color(0.22, 0.15, 0.1, 1.0), Color(0.15, 0.1, 0.07, 0.0), 0.0))
	for i in DUST:
		_dust.append(_burst(dust_mat, 14, 1.6, 0.35, 0.8, 0.6, 2.6, 80.0, Vector3(0, 0.3, 0), Color(0.5, 0.45, 0.4, 0.5), Color(0.42, 0.38, 0.34, 0.0), 2.0))
	for i in GLASS:
		_glass.append(_burst(glass_mat, 36, 1.1, 0.02, 0.07, 2.0, 7.0, 55.0, Vector3(0, -12.0, 0), Color(0.85, 0.95, 1.0, 0.95), Color(0.6, 0.8, 0.9, 0.0), 0.0))
	for i in VOICES:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 10.0
		a.max_distance = 90.0
		a.volume_db = 0.0
		add_child(a)
		_voices.append(a)

func _burst(mat: Material, amount: int, life: float, s0: float, s1: float, v0: float, v1: float, spread: float, gravity: Vector3, c0: Color, c1: Color, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
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
		curve.add_point(Vector2(0.0, 0.4))
		curve.add_point(Vector2(1.0, 0.4 + grow * 0.5))
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

# --- The street's cracks -----------------------------------------------------------------------

## Cracks radiating from a dark centre, drawn once: a handful of branching lines.
static func crack_texture() -> Texture2D:
	if _crack_tex != null:
		return _crack_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.02, 0.02, 0.0))
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var c := Vector2(n * 0.5, n * 0.5)
	# The broken centre.
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(c) / (n * 0.5)
			if d < 0.2:
				img.set_pixel(x, y, Color(0.015, 0.012, 0.01, clampf((0.2 - d) / 0.12, 0.0, 1.0) * 0.95))
	var arms := 9
	for a in arms:
		var ang := TAU * float(a) / arms + r.randf_range(-0.25, 0.25)
		_crack_line(img, c, ang, n * 0.5 * r.randf_range(0.7, 1.0), 2.6, r, 2)
	img.generate_mipmaps()
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex

static func _crack_line(img: Image, from: Vector2, ang: float, length: float, width: float, r: RandomNumberGenerator, depth: int) -> void:
	var p := from
	var steps := int(length / 2.0)
	for i in steps:
		var k := float(i) / maxf(steps, 1)
		ang += r.randf_range(-0.22, 0.22)
		var next := p + Vector2(cos(ang), sin(ang)) * 2.0
		var w := maxf(width * (1.0 - k * 0.8), 0.6)
		var alpha := lerpf(1.0, 0.25, k)
		_stamp(img, next, w, alpha)
		p = next
		if depth > 0 and i > 6 and r.randf() < 0.07:
			_crack_line(img, p, ang + r.randf_range(0.5, 1.1) * (1.0 if r.randf() < 0.5 else -1.0), length * (1.0 - k) * 0.55, width * 0.6, r, depth - 1)

static func _stamp(img: Image, at: Vector2, w: float, alpha: float) -> void:
	var n := img.get_width()
	var x0 := maxi(int(at.x - w), 0)
	var x1 := mini(int(at.x + w) + 1, n - 1)
	var y0 := maxi(int(at.y - w), 0)
	var y1 := mini(int(at.y + w) + 1, n - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y).distance_to(at)
			if d <= w:
				var a := alpha * (1.0 - d / (w + 0.01) * 0.6)
				var old := img.get_pixel(x, y)
				if a > old.a:
					img.set_pixel(x, y, Color(0.02, 0.018, 0.015, a))

## A crack in the ground at `pos`, `size` metres across. Counted against a per-frame budget.
func crack(pos: Vector3, size := 2.0) -> void:
	if not _allow("crack"):
		return
	var d := _cracks[_crack_next]
	_crack_next = (_crack_next + 1) % _cracks.size()
	d.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(pos.x, pos.y + 0.4, pos.z))
	d.size = Vector3(size, 1.2, size)
	d.visible = true
	cracks_made += 1

func visible_cracks() -> int:
	var n := 0
	for d in _cracks:
		if d.visible:
			n += 1
	return n

# --- Entrances -----------------------------------------------------------------------------------

## A zombie bursts up out of the ground at `pos`; a manhole lid there is thrown off.
func ground_burst(pos: Vector3, lid: Node3D = null) -> void:
	bursts += 1
	crack(pos, rng.randf_range(2.0, 3.2))
	if _allow("dirt"):
		_fire(_dirt, "dirt", Transform3D(Basis(), pos + Vector3(0, 0.05, 0)))
	if _allow("dust"):
		_fire(_dust, "dust", Transform3D(Basis(), pos + Vector3(0, 0.15, 0)))
	_play(pos, "ground_burst_%d" % (1 + rng.randi() % 3), 2.0)
	if lid != null and is_instance_valid(lid) and not bool(lid.get_meta("thrown", false)):
		_throw_lid(lid)

func _throw_lid(lid: Node3D) -> void:
	lid.set_meta("thrown", true)
	lids_thrown += 1
	var from := lid.position
	var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.7, 1.3)
	var tw := lid.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lid, "position:y", from.y + 1.6, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lid, "position:x", from.x + side.x, 0.6)
	tw.tween_property(lid, "position:z", from.z + side.z, 0.6)
	tw.tween_property(lid, "rotation:x", rng.randf_range(-0.5, 0.5), 0.5)
	tw.tween_property(lid, "rotation:z", rng.randf_range(-0.5, 0.5), 0.5)
	tw.chain().tween_property(lid, "position:y", from.y + 0.02, 0.26).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

## Lands off a fire escape or a roof: a ring of dust, a thud, and on a roof drop the ground cracks.
func landing(pos: Vector3, heavy: bool) -> void:
	landings += 1
	if _allow("dust"):
		_fire(_dust, "dust", Transform3D(Basis(), pos + Vector3(0, 0.1, 0)))
	if heavy:
		crack(pos, 1.6)
		if _allow("dirt"):
			_fire(_dirt, "dirt", Transform3D(Basis(), pos + Vector3(0, 0.05, 0)))
	_play(pos, "body_drop_%d" % (1 + rng.randi() % 2), 0.0 if heavy else -3.0)

## Through a shop front at `pos` (the facade point at the height of a window), spraying along `out`.
func smash(pos: Vector3, out: Vector3) -> void:
	smashes += 1
	var up := out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	var ref := Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var x := up.cross(ref).normalized()
	var z := x.cross(up).normalized()
	var at := Transform3D(Basis(x, up, z), pos + Vector3(0, 1.3, 0) + up * 0.2)
	if _allow("glass"):
		_fire(_glass, "glass", at)
	if _allow("dust"):
		_fire(_dust, "dust", Transform3D(Basis(), pos + Vector3(0, 1.0, 0) + up * 0.6))
	_play(pos + Vector3(0, 1.2, 0), "window_smash_%d" % (1 + rng.randi() % 3), 3.0)

# --- Pools -----------------------------------------------------------------------------------------

func _fire(pool: Array, key: String, at: Transform3D) -> void:
	var p: CPUParticles3D = pool[_next[key]]
	_next[key] = (_next[key] + 1) % pool.size()
	p.global_transform = at
	p.restart()
	p.emitting = true

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

static func stream(name_: String) -> AudioStream:
	if not _streams.has(name_):
		_streams[name_] = load(SFX_DIR + name_ + ".wav")
	return _streams[name_]

func _play(pos: Vector3, sound: String, db: float) -> void:
	if not _allow("sound"):
		return
	var a := _voices[_next["voice"]]
	_next["voice"] = (_next["voice"] + 1) % _voices.size()
	a.global_position = pos
	a.stream = stream(sound)
	a.volume_db = db
	a.pitch_scale = rng.randf_range(0.93, 1.07)
	a.play()
