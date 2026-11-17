extends Node3D
## The one explosion of the game (SHIP 16G): the player's Mk 2 frag, the launcher's rocket and the crews' grenades all go off
## through detonate(). It replaces the RPG's thirty screen-sized alpha quads (review I1: fill, not particle count, was the cost).
##
## The picture: ONE camera-facing flipbook card of fire into black smoke (Unity Labs sim, CC0) whose side is clamped to one screen
## height at its distance and which fades out between 4 m and 1.5 m from the lens (so a blast beside the eye never fills the
## screen with alpha); a thin smoke card that stays a moment; sparks and grit (CPUParticles3D, 10 and 14 particles); dust on the
## street; one flash light; and a scorch decal on the floor. Two big blasts at once at most (a third takes the oldest's place).
## Nothing is made while it plays: the pools are built with the node and drawn once behind the loading black (fx/Prewarm.gd).
##
## The sound is the user's pick (DESIGN.md section 9): real_A_taet close, real_C_fjern far, an equal-power crossfade by distance
## between them and no other boom layered; the debris rain, the street's slapback, the ear ring and the muffle of a very close
## one are their own events. Shake and pad rumble by distance. Damage is not here: the holder does it (WeaponHolder.explode()).
##
## One per scene, found by group "explosion_fx" (Explosion.of(node) makes it on first use).

const DIR := "res://assets/fx/explosion/"
const SFX_DIR := "res://assets/sfx/grenade/"
const SHADER := preload("res://assets/fx/explosion/explosion_flipbook.gdshader")
const ImpactFX := preload("res://fx/ImpactFX.gd")
const GunSounds := preload("res://weapons/GunSounds.gd")
const PadRumble := preload("res://player/PadRumble.gd")

const SLOTS := 2
const DECALS := 6
const FIRE_LIFE := 1.5
const FIRE_SIZE := 5.5
const SMOKE_LIFE := 2.2
const SMOKE_START := 0.5
const SMOKE_SIDE := 4.5
const DUST_LIFE := 0.9
const DUST_SIDE := 7.0
const FLASH_ENERGY := 9.0
const FLASH_RANGE := 12.0
const SCORCH_HOLD := 40.0
const SCORCH_FADE := 10.0
## The camera's distance (m) from the blast where the cards are faded out completely and where they are fully there.
const FADE_NEAR := 1.5
const FADE_FAR := 4.0
## Metres: the sound's close bracket ends and the far one begins; a blast nearer than SHAKE_REACH shakes the view.
const CLOSE_M := 10.0
const FAR_M := 35.0
const SHAKE_REACH := 26.0
const MUFFLE_M := 5.0
const DUCK_M := 25.0
const SOUND_REACH := 170.0

static var _tex := {}
static var _snd := {}
static var _buses_ready := false
## [bus index, effect index, effect]
static var _lows: Array = []
static var _amps: Array = []

class Blast:
	var active := false
	var age := 0.0
	var power := 1.0
	var at := Vector3.ZERO
	var normal := Vector3.UP
	var floor_y := -INF
	var fire: MeshInstance3D
	var smoke: MeshInstance3D
	var dust: MeshInstance3D
	var fire_mat: ShaderMaterial
	var smoke_mat: ShaderMaterial
	var dust_mat: ShaderMaterial
	var sparks: CPUParticles3D
	var grit: CPUParticles3D
	var boom_a: AudioStreamPlayer3D
	var boom_c: AudioStreamPlayer3D
	var slap: AudioStreamPlayer3D
	var debris: AudioStreamPlayer3D

var rng := RandomNumberGenerator.new()
var _blasts: Array[Blast] = []
var _decals: Array[Decal] = []
var _decal_age: Array[float] = []
var _decal_next := 0
var _flash: OmniLight3D
var _flash_rate := 60.0
var _flash_t := 99.0
var _ring: AudioStreamPlayer
## [seconds left, player, stream, volume_db, pitch]
var _pending: Array = []
var _last_boom := -1
var _last_debris := -1
var _flip_next := 0
## The very-close muffle: seconds since it began, how long it holds, and the low-pass cutoff it asks for (Hz).
var _ear_t := 99.0
var _ear_hold := 0.0
var _ear_on := false
## The ducking of music, room tone and voices.
var _duck_t := 99.0
var _duck_amt := 0.0
var _duck_on := false
## For the tests: blasts made, the last one's place, power, and what the sound did.
var blasts := 0
var last_at := Vector3.INF
var last_power := 0.0
var last_sound := {}
var last_shake := 0.0

## The scene's Explosion (made, parented to the current scene, on first use).
static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("explosion_fx")
	if found != null:
		return found as Node3D
	var fx: Node3D = (load("res://fx/Explosion.gd") as GDScript).new()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(fx)
	return fx

static func texture(name_: String) -> Texture2D:
	if not _tex.has(name_):
		_tex[name_] = load(DIR + name_ + ".png")
	return _tex[name_]

static func sound(name_: String) -> AudioStream:
	if not _snd.has(name_):
		var path := SFX_DIR + name_ + ".wav"
		_snd[name_] = load(path) if ResourceLoader.exists(path) else null
	return _snd[name_]

## Every file the blast plays, loaded now (the title's warm-up and Prewarm call it, so the first blast does not read the disk).
static func warm_files() -> void:
	for n in ["real_A_taet", "real_C_fjern", "slapback_street", "ear_ring", "debris_1", "debris_2", "debris_3"]:
		sound(n)
	for n in ["explosion_a_5x5", "explosion_b_5x5", "smoke_wispy_8x8", "dust_cloud_8x8", "sparks_4x1", "grit_4x2", "scorch_albedo_1", "scorch_albedo_2", "scorch_normal_1", "scorch_normal_2"]:
		texture(n)

func _ready() -> void:
	add_to_group("explosion_fx")
	name = "Explosion"
	rng.randomize()
	warm_files()
	_build()

# --- The pools --------------------------------------------------------------------------------

func _build() -> void:
	for i in SLOTS:
		var b := Blast.new()
		b.fire_mat = _card_material("explosion_a_5x5" if i % 2 == 0 else "explosion_b_5x5", 5, Color(1, 1, 1, 1))
		b.smoke_mat = _card_material("smoke_wispy_8x8", 8, Color(0.30, 0.29, 0.28, 0.35))
		b.dust_mat = _card_material("dust_cloud_8x8", 8, Color(0.5, 0.47, 0.43, 0.5))
		b.dust_mat.set_shader_parameter("billboard", false)
		b.dust_mat.set_shader_parameter("fade_near", 0.0)
		b.dust_mat.set_shader_parameter("fade_far", 0.5)
		b.fire = _card(b.fire_mat)
		b.smoke = _card(b.smoke_mat)
		b.dust = _card(b.dust_mat)
		b.dust.rotation.x = -PI * 0.5
		b.sparks = _sparks()
		b.grit = _grit()
		b.boom_a = _voice()
		b.boom_c = _voice()
		b.slap = _voice()
		b.debris = _voice()
		_blasts.append(b)
	for i in DECALS:
		var d := Decal.new()
		d.texture_albedo = texture("scorch_albedo_1" if i % 2 == 0 else "scorch_albedo_2")
		d.texture_normal = texture("scorch_normal_1" if i % 2 == 0 else "scorch_normal_2")
		d.size = Vector3(3.2, 1.5, 3.2)
		d.visible = false
		d.distance_fade_enabled = true
		d.distance_fade_begin = 40.0
		d.distance_fade_length = 10.0
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)
		_decal_age.append(99.0)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.72, 0.40)
	_flash.light_energy = 0.0
	_flash.omni_range = FLASH_RANGE
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	_ring = AudioStreamPlayer.new()
	_ring.bus = "Master"
	add_child(_ring)

func _card_material(tex: String, cells: int, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("flipbook", texture(tex))
	m.set_shader_parameter("cols", cells)
	m.set_shader_parameter("rows", cells)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("fade_near", FADE_NEAR)
	m.set_shader_parameter("fade_far", FADE_FAR)
	return m

func _card(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# (The card is billboarded in its shader: the culling box must not be the quad's flat one.)
	mi.extra_cull_margin = 8.0
	mi.visible = false
	add_child(mi)
	return mi

func _voice() -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	# The loudness by distance is this node's (the crossfade needs it), so the engine's own roll-off is off.
	a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	a.max_distance = 0.0
	a.unit_size = 14.0
	a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(a)
	return a

func _sparks() -> CPUParticles3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture("sparks_4x1")
	m.albedo_color = Color(1.8, 1.4, 0.8)
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	var p := _particles(m, 10, 0.55, Vector2(0.08, 0.5), 8.0, 16.0, 70.0, Vector3(0, -14.0, 0))
	p.particle_flag_align_y = true
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.5, 1.0))
	g.set_color(1, Color(1.0, 0.35, 0.08, 0.0))
	p.color_ramp = g
	return p

func _grit() -> CPUParticles3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture("grit_4x2")
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 2
	m.particles_anim_loop = false
	var p := _particles(m, 14, 0.9, Vector2.ONE, 5.0, 12.0, 80.0, Vector3(0, -12.0, 0))
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
	var g := Gradient.new()
	g.set_color(0, Color(0.46, 0.41, 0.36, 1.0))
	g.set_color(1, Color(0.3, 0.27, 0.24, 0.0))
	p.color_ramp = g
	return p

func _particles(mat: Material, amount: int, life: float, size: Vector2, v0: float, v1: float, spread: float, gravity: Vector3) -> CPUParticles3D:
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
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

# --- Going off ---------------------------------------------------------------------------------

## A blast at `at` on a surface facing `normal`: the picture, the sound, the shake. `power` 1.0 is the grenade, 1.4 the rocket
## (size x1.35, light x1.5, the sound +3 dB, longer debris).
func detonate(at: Vector3, normal := Vector3.UP, power := 1.0) -> void:
	blasts += 1
	last_at = at
	last_power = power
	var n := normal.normalized() if normal.length() > 0.001 else Vector3.UP
	var b := _slot()
	b.active = true
	b.age = 0.0
	b.power = power
	b.at = at
	b.normal = n
	b.floor_y = _floor_below(at)
	var big := 1.35 if power > 1.0 else 1.0
	# Which sheet (and which way round) it is this time.
	_flip_next += 1
	b.fire_mat.set_shader_parameter("flipbook", texture("explosion_a_5x5" if (_flip_next + rng.randi()) % 2 == 0 else "explosion_b_5x5"))
	b.fire_mat.set_shader_parameter("flip", float(rng.randi() % 2))
	b.smoke_mat.set_shader_parameter("flip", float(rng.randi() % 2))
	b.dust_mat.set_shader_parameter("flip", float(rng.randi() % 2))
	b.fire.visible = true
	b.smoke.visible = false
	b.dust.visible = false
	var xf := ImpactFX._up_basis(n, at + n * 0.03)
	b.sparks.global_transform = xf
	b.sparks.restart()
	b.sparks.emitting = true
	b.grit.global_transform = xf
	b.grit.restart()
	b.grit.emitting = true
	b.grit.lifetime = 0.9 * (1.3 if power > 1.0 else 1.0)
	_update(b, 0.0)
	# One light for the lot: a second blast within a moment of the first shares it.
	_flash.global_position = at + Vector3(0.0, 0.8, 0.0)
	_flash.light_energy = maxf(_flash.light_energy if _flash.visible else 0.0, FLASH_ENERGY * (1.5 if power > 1.0 else 1.0))
	_flash_rate = 40.0 if power > 1.0 else 60.0
	_flash.visible = true
	_flash_t = 0.0
	_scorch(b, big)
	var d := listener_distance(at)
	_sound(b, at, d, power)
	_shake(d, power)

## Metres from the ears (the active camera, else the player) to `at`.
func listener_distance(at: Vector3) -> float:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		return cam.global_position.distance_to(at)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	return pl.global_position.distance_to(at) if pl != null else 60.0

func _slot() -> Blast:
	var oldest: Blast = _blasts[0]
	for b in _blasts:
		if not b.active:
			return b
		if b.age > oldest.age:
			oldest = b
	_stop(oldest)
	return oldest

func _stop(b: Blast) -> void:
	b.active = false
	b.fire.visible = false
	b.smoke.visible = false
	b.dust.visible = false

## The floor under `at` (y), -INF if there is none within 1.5 m.
func _floor_below(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.25, 0), at + Vector3(0, -1.5, 0))
	q.collision_mask = 1 | 16
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or (r.normal as Vector3).y < 0.7:
		return -INF
	return (r.position as Vector3).y

func _scorch(b: Blast, big: float) -> void:
	if b.floor_y == -INF:
		return
	var i := _decal_next
	_decal_next = (_decal_next + 1) % _decals.size()
	var d := _decals[i]
	d.global_transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(b.at.x, b.floor_y + 0.02, b.at.z))
	var s := rng.randf_range(0.9, 1.15) * big
	d.size = Vector3(3.2 * s, 1.5, 3.2 * s)
	d.modulate = Color(1, 1, 1, 1)
	d.visible = true
	_decal_age[i] = 0.0

## How many scorch marks are on the ground now (the tests).
func scorches_shown() -> int:
	var n := 0
	for d in _decals:
		if d.visible:
			n += 1
	return n

func blasts_active() -> int:
	var n := 0
	for b in _blasts:
		if b.active:
			n += 1
	return n

## The quads' state for `b` at its age: sizes clamped to a screen height, the flipbook's progress, the fades.
func _update(b: Blast, _delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	var big := 1.35 if b.power > 1.0 else 1.0
	var u := b.age / FIRE_LIFE
	# The fireball: lifted off the surface by 0.55 of its half size, and never wider than the screen is tall where it is.
	var side := FIRE_SIZE * big
	if cam != null:
		var d := cam.global_position.distance_to(b.at + b.normal)
		side = minf(side, maxf(2.0 * d * tan(deg_to_rad(cam.fov) * 0.5), 0.8))
	b.fire.visible = u < 1.0
	b.fire.global_position = b.at + b.normal * (side * 0.5 * 0.55)
	b.fire.scale = Vector3(side, side, 1.0)
	b.fire_mat.set_shader_parameter("progress", clampf(u, 0.0, 1.0))
	# The smoke that stays: starts when the fire is dying, rises a little, fades in and out.
	var su := (b.age - SMOKE_START) / SMOKE_LIFE
	b.smoke.visible = su >= 0.0 and su < 1.0
	if b.smoke.visible:
		var sside := SMOKE_SIDE * big
		if cam != null:
			var ds := cam.global_position.distance_to(b.at + Vector3(0, 1.2, 0))
			sside = minf(sside, maxf(2.0 * ds * tan(deg_to_rad(cam.fov) * 0.5), 0.8))
		b.smoke.global_position = b.at + b.normal * (1.2 + su * 0.9)
		b.smoke.scale = Vector3(sside, sside, 1.0)
		var env := smoothstep(0.0, 0.18, su) * (1.0 - smoothstep(0.62, 1.0, su))
		b.smoke_mat.set_shader_parameter("progress", clampf(su, 0.0, 1.0))
		b.smoke_mat.set_shader_parameter("tint", Color(0.30, 0.29, 0.28, 0.35 * env))
	var du := b.age / DUST_LIFE
	b.dust.visible = b.floor_y != -INF and du < 1.0
	if b.dust.visible:
		var dside := DUST_SIDE * big * (0.55 + 0.45 * smoothstep(0.0, 0.5, du))
		b.dust.global_position = Vector3(b.at.x, b.floor_y + 0.06, b.at.z)
		b.dust.scale = Vector3(dside, dside, 1.0)
		b.dust_mat.set_shader_parameter("progress", clampf(du, 0.0, 1.0))
		b.dust_mat.set_shader_parameter("tint", Color(0.5, 0.47, 0.43, 0.5 * (1.0 - smoothstep(0.35, 1.0, du))))

func _process(delta: float) -> void:
	for b in _blasts:
		if not b.active:
			continue
		b.age += delta
		if b.age >= SMOKE_START + SMOKE_LIFE:
			_stop(b)
		else:
			_update(b, delta)
	if _flash.visible:
		_flash_t += delta
		_flash.light_energy = maxf(_flash.light_energy - delta * _flash_rate, 0.0)
		if _flash.light_energy <= 0.0:
			_flash.visible = false
	for i in _decals.size():
		if _decals[i].visible:
			_decal_age[i] += delta
			var over: float = _decal_age[i] - SCORCH_HOLD
			if over > 0.0:
				_decals[i].modulate.a = clampf(1.0 - over / SCORCH_FADE, 0.0, 1.0)
				if over >= SCORCH_FADE:
					_decals[i].visible = false
	_run_pending(delta)
	_run_ears(delta)

# --- Sound -------------------------------------------------------------------------------------

## The loudness (dB) of the close take, and of the far one, at distance `d` from the blast, and the delay of the crack's arrival.
## The two are an equal-power crossfade between CLOSE_M and FAR_M; both fall off a little with distance on top of their own level.
static func mix_at(d: float, power := 1.0) -> Dictionary:
	var t := clampf((d - CLOSE_M) / (FAR_M - CLOSE_M), 0.0, 1.0)
	var wa := cos(t * PI * 0.5)
	var wc := sin(t * PI * 0.5)
	var roll := -clampf((d - CLOSE_M) * 0.1, 0.0, 14.0)
	var pw := 3.0 if power > 1.0 else 0.0
	return {
		"a_db": (linear_to_db(wa) + roll + pw) if wa > 0.002 else -INF,
		"c_db": (linear_to_db(wc) + roll + pw + 3.0) if wc > 0.002 else -INF,
		"delay": minf(d / 343.0, 0.25) if d > 8.0 else 0.0,
	}

func _queue(player: Node, at_s: float, stream: AudioStream, db: float, pitch := 1.0) -> void:
	if stream == null or db < -60.0:
		return
	_pending.append([at_s, player, stream, db, pitch])

func _sound(b: Blast, at: Vector3, d: float, power: float) -> void:
	last_sound = {}
	if d > SOUND_REACH:
		return
	var m := mix_at(d, power)
	var delay: float = m["delay"]
	b.boom_a.global_position = at
	b.boom_c.global_position = at
	b.slap.global_position = at
	b.debris.global_position = at + Vector3(0, 2.5, 0)
	var pitch := rng.randf_range(0.97, 1.03)
	if m["a_db"] > -INF:
		_queue(b.boom_a, delay, sound("real_A_taet"), m["a_db"], pitch)
		last_sound["a_db"] = m["a_db"]
	if m["c_db"] > -INF:
		_queue(b.boom_c, delay, sound("real_C_fjern"), m["c_db"], pitch)
		last_sound["c_db"] = m["c_db"]
	last_sound["delay"] = delay
	var roll := -clampf((d - CLOSE_M) * 0.1, 0.0, 14.0)
	# The street's echo, outdoors only: 0.12 s behind the crack, softer the further you are.
	if not GunSounds.indoors(self):
		_queue(b.slap, delay + 0.12, sound("slapback_street"), (-9.0 if d < 20.0 else -16.0) + roll * 0.5, pitch)
		last_sound["slap"] = true
	# Rubble coming down, for anyone within earshot of it; dull and low when far.
	if d < FAR_M:
		var near := 1.0 - clampf(d / FAR_M, 0.0, 1.0)
		var db := lerpf(-14.0, -4.0, near) + (2.0 if power > 1.0 else 0.0)
		var k := 1 + (rng.randi() + _last_debris + 1) % 3
		_last_debris = k
		_queue(b.debris, 0.35 + delay, sound("debris_%d" % k), db, rng.randf_range(0.9, 1.05) * (0.85 if d > 20.0 else 1.0))
		last_sound["debris"] = true
	# Very close: the ears ring and the world goes dull for a while.
	if d < MUFFLE_M:
		var k2 := 1.0 - d / MUFFLE_M
		_queue(_ring, 0.08, sound("ear_ring"), -10.0 - 20.0 * (1.0 - k2))
		var carried := maxf(_ear_hold - _ear_t, 0.0) if _ear_on else 0.0
		_ear_hold = maxf(2.0 * k2, carried)
		_ear_t = 0.0
		_ear_on = true
		last_sound["ring"] = true
		last_sound["muffle_hold"] = _ear_hold
	if d < DUCK_M:
		_duck_amt = maxf(_duck_amt if _duck_on else 0.0, clampf(1.0 - d / DUCK_M, 0.0, 1.0))
		_duck_t = 0.0
		_duck_on = true
		last_sound["duck"] = _duck_amt

func _run_pending(delta: float) -> void:
	var i := 0
	while i < _pending.size():
		var e: Array = _pending[i]
		e[0] = float(e[0]) - delta
		if float(e[0]) <= 0.0:
			var p: Node = e[1]
			if is_instance_valid(p):
				(p as Node).set("stream", e[2])
				(p as Node).set("volume_db", e[3])
				(p as Node).set("pitch_scale", e[4])
				p.call("play")
			_pending.remove_at(i)
		else:
			i += 1

## Pending sounds (the tests).
func pending_sounds() -> int:
	return _pending.size()

static func _ensure_buses() -> void:
	if _buses_ready:
		return
	_buses_ready = true
	for bus in ["SFX", "Voice"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20500.0
		AudioServer.add_bus_effect(i, lp)
		var idx := AudioServer.get_bus_effect_count(i) - 1
		AudioServer.set_bus_effect_enabled(i, idx, false)
		_lows.append([i, idx, lp])
	for bus in ["Music", "Ambience", "Voice"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var amp := AudioEffectAmplify.new()
		amp.volume_db = 0.0
		AudioServer.add_bus_effect(i, amp)
		var idx := AudioServer.get_bus_effect_count(i) - 1
		AudioServer.set_bus_effect_enabled(i, idx, false)
		_amps.append([i, idx, amp])

## The cutoff (Hz) the ear muffle asks of the buses now: 20000 down to 900 in 0.08 s, held, back up over 2.5 s.
static func muffle_hz(t: float, hold: float) -> float:
	if t < 0.08:
		return lerpf(20000.0, 900.0, t / 0.08)
	if t < 0.08 + hold:
		return 900.0
	var r := (t - 0.08 - hold) / 2.5
	if r >= 1.0:
		return 20500.0
	return exp(lerpf(log(900.0), log(20000.0), r * r))

## The duck of music, room tone and voices in dB: 0 -> -10 x amount in 0.05 s, held 0.8 s, released over 3 s.
static func duck_db(t: float, amount: float) -> float:
	if t < 0.05:
		return -10.0 * amount * (t / 0.05)
	if t < 0.85:
		return -10.0 * amount
	var r := (t - 0.85) / 3.0
	if r >= 1.0:
		return 0.0
	return -10.0 * amount * (1.0 - r)

func _run_ears(delta: float) -> void:
	if _ear_on or _duck_on:
		_ensure_buses()
	if _ear_on:
		_ear_t += delta
		var hz := muffle_hz(_ear_t, _ear_hold)
		var done := hz >= 20400.0 and _ear_t > 0.1
		for e in _lows:
			AudioServer.set_bus_effect_enabled(e[0], e[1], not done)
			if not done:
				(e[2] as AudioEffectLowPassFilter).cutoff_hz = hz
		# The rest of the world (music, room tone) takes the lower of this and the sickness's own muffle (autoload/SFX.gd).
		if SFX.has_method("set_ear_muffle"):
			SFX.set_ear_muffle(20500.0 if done else hz)
		if done:
			_ear_on = false
			_ear_hold = 0.0
	if _duck_on:
		_duck_t += delta
		var db := duck_db(_duck_t, _duck_amt)
		var done2 := _duck_t > 0.85 + 3.0
		for e in _amps:
			AudioServer.set_bus_effect_enabled(e[0], e[1], not done2)
			if not done2:
				(e[2] as AudioEffectAmplify).volume_db = db
		if done2:
			_duck_on = false
			_duck_amt = 0.0

## The muffle in force now (Hz; 20500 when none) and the duck (dB), for the tests.
func ear_hz() -> float:
	return muffle_hz(_ear_t, _ear_hold) if _ear_on else 20500.0

func duck_now() -> float:
	return duck_db(_duck_t, _duck_amt) if _duck_on else 0.0

# --- Shake and rumble ----------------------------------------------------------------------------

func _shake(d: float, power: float) -> void:
	var k := clampf(1.0 - d / SHAKE_REACH, 0.0, 1.0)
	last_shake = 0.0
	if k <= 0.0:
		return
	var trauma := 0.95 * pow(k, 1.2) * (1.0 if power <= 1.0 else 1.1)
	last_shake = trauma
	var holder := get_tree().get_first_node_in_group("weapon_holder")
	if holder != null and holder.get("feel") != null:
		holder.feel.add_trauma(trauma)
	if Graphics.rumble:
		PadRumble.vibrate(0.6 * k, 0.9 * k, 0.25 + 0.45 * k, "explosion")

## Draws every part of the pool once, as a blast would (fx/Prewarm.gd): the light on, the cards and particles are
## shown by the pool walk (Prewarm._collect).
func warm_light(on: bool) -> void:
	_flash.visible = on
	_flash.light_energy = 1.0 if on else 0.0
