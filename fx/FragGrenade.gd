extends Node3D
## A thrown Mk 2 frag (SHIP 16G): scripted ballistics, not a RigidBody. Each physics tick a sphere (r 6 cm) is swept along
## v*dt with cast_motion, so it never tunnels through a wall, a door or a car at any frame rate; the contact gives the
## normal and the surface, the bounce is a reflection with a restitution and a tangential loss by surface, and once it
## no longer leaves the floor it rolls (decelerating, spinning by its speed) and comes to rest. The fuse runs from the pin
## (the cook, in player/Lethal.gd, has already used some of it); at 0 the shared explosion (fx/Explosion.gd) goes off and
## WeaponHolder.explode() does the damage. Group "live_grenade" while live (the HUD's danger arrow reads fuse_left()).
## Pooled by the Lethal node: a throw makes no node.

const Explosion := preload("res://fx/Explosion.gd")
const Mk2 := preload("res://fx/Mk2.gd")
const GRAVITY := 11.0
const RADIUS := 0.06
## The sphere rolls this far above the floor (no contact with it, so a horizontal sweep never starts touching).
const LIFT := 0.02
const SETTLE_SPEED := 1.2
const ROLL_DECEL := 3.0
const STOP_SPEED := 0.15
const SPIN := 14.0
## Everything solid: the walls and props (layer 1), the floor (16), the dead's bodies (128)... but not the zombies' hit-zone areas (64).
const MASK := 0x7FFFFFFF & ~64
## What a ray along the street or to a body must not cross: the world (walls, props, the floor).
const WORLD := 1 | 16
const SURFACES := {
	# restitution, tangential loss
	"concrete": [0.38, 0.45], "metal": [0.45, 0.30], "wood": [0.30, 0.55], "flesh": [0.10, 0.60],
}
const FUSE := 3.5
## Names of the world's solids that are steel or timber (cars, vans, dumpsters, crates, doors, fences...), the rest being stone.
const METAL_WORDS := ["car", "van", "taxi", "truck", "bus", "dumpster", "vending", "mailbox", "lamp", "pole", "hydrant", "grate", "gate"]
const WOOD_WORDS := ["crate", "box", "pallet", "plank", "door", "fence", "table", "bench", "chair", "shelf", "board", "barricade"]

signal went_off(at: Vector3)

var holder: Node
var fuse := 0.0
var v := Vector3.ZERO
## "off" (in the pool), "air", "roll", "rest", "boom".
var state := "off"
var bounces := 0
var rolling_time := 0.0
var last_surface := ""
var last_normal := Vector3.UP
var last_impact := 0.0
var went_off_at := Vector3.INF
var swept_blocks := 0
var _model: Node3D
var _spoon: Node3D
var _spoon_v := Vector3.ZERO
var _spoon_t := -1.0
var _shape := SphereShape3D.new()
var _mats: Array = []
var _blinking := false
var _exclude: Array[RID] = []
var _spin_axis := Vector3.RIGHT
var _spin_rate := SPIN
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_next := 0
var _roll_voice: AudioStreamPlayer3D
var _boom_t := 0.0
var _rng := RandomNumberGenerator.new()
static var _bounce_streams := {}
static var _roll_stream: AudioStream

func _ready() -> void:
	top_level = true
	visible = false
	_rng.randomize()
	_shape.radius = RADIUS
	_model = Mk2.build()
	add_child(_model)
	# The spoon comes off at the throw and flies on its own for half a second: it is taken off the model here.
	var sw := Mk2.part(_model, "GrenadeSwitch")
	var pin := Mk2.part(_model, "GrenadePin")
	if pin != null:
		pin.visible = false
	if sw != null:
		_spoon = Node3D.new()
		_spoon.top_level = true
		_spoon.visible = false
		add_child(_spoon)
		var copy := sw.duplicate() as Node3D
		copy.transform = Transform3D.IDENTITY
		_spoon.add_child(copy)
		_spoon_xf_from = sw.transform
		sw.visible = false
	_make_glint()
	for i in 3:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 6.0
		a.max_distance = 60.0
		a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(a)
		_voices.append(a)
	_roll_voice = AudioStreamPlayer3D.new()
	_roll_voice.unit_size = 4.0
	_roll_voice.max_distance = 40.0
	_roll_voice.bus = _voices[0].bus
	add_child(_roll_voice)

var _spoon_xf_from := Transform3D.IDENTITY

## The warm self-lit rim of the thrown model (a faint emission from its own texture) so it can be seen in a night street,
## and its red blink in the last second of the fuse. The materials are this node's own copies.
const GLINT := 0.45
const GLINT_COLOR := Color(1.0, 0.72, 0.45)
const BLINK_COLOR := Color(1.0, 0.1, 0.05)

func _make_glint() -> void:
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as StandardMaterial3D
			if src == null:
				continue
			var d := src.duplicate() as StandardMaterial3D
			d.emission_enabled = true
			d.emission = GLINT_COLOR
			d.emission_energy_multiplier = GLINT
			if d.albedo_texture != null:
				d.emission_texture = d.albedo_texture
			m.set_surface_override_material(i, d)
			_mats.append(d)

## The rim and the blink for a fuse with `left` seconds to go: steady glint, then a red pulse (6 Hz, quicker to 14) in the last second.
func _glow(left: float) -> void:
	var blink := left < 1.0
	if not blink and not _blinking:
		return
	_blinking = blink
	var on := false
	if blink:
		var f := 1.0 - clampf(left, 0.0, 1.0)
		on = sin(left * lerpf(6.0, 14.0, f) * TAU) > 0.0
	for m in _mats:
		(m as StandardMaterial3D).emission = BLINK_COLOR if on else GLINT_COLOR
		(m as StandardMaterial3D).emission_energy_multiplier = 3.0 if on else GLINT

## Whether the blink is lit now (the tests).
func blink_lit() -> bool:
	return _mats.size() > 0 and (_mats[0] as StandardMaterial3D).emission_energy_multiplier > 1.0

## Loads the bounce and roll sounds now (the title's warm-up and the level's), so the first bounce reads no file.
static func warm_files() -> void:
	for s in ["concrete", "metal", "wood"]:
		for i in 3:
			_bounce("%s_%d" % [s, i + 1])
	_roll()

static func _bounce(key: String) -> AudioStream:
	if not _bounce_streams.has(key):
		var path := "res://assets/sfx/grenade/bounce_%s.wav" % key
		_bounce_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _bounce_streams[key]

## The rolling loop: a copy of the file with its loop switched on (the import's own loop flag is left alone).
static func _roll() -> AudioStream:
	if _roll_stream == null:
		var base := load("res://assets/sfx/grenade/roll_concrete.wav") as AudioStreamWAV
		if base != null:
			var st := base.duplicate() as AudioStreamWAV
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = st.data.size() / (2 if st.format == AudioStreamWAV.FORMAT_16_BITS else 1) / (2 if st.stereo else 1)
			_roll_stream = st
	return _roll_stream

## Off it goes from `from` with velocity `vel` and `fuse_s` seconds of fuse left. `ignore` is the thrower's body.
func launch(from: Vector3, vel: Vector3, fuse_s: float, who: Node = null, ignore: Node = null) -> void:
	holder = who
	global_position = from
	v = vel
	fuse = fuse_s
	state = "air"
	_blinking = true
	_glow(fuse)
	bounces = 0
	rolling_time = 0.0
	last_surface = ""
	last_normal = Vector3.UP
	went_off_at = Vector3.INF
	_boom_t = 0.0
	_exclude.clear()
	if ignore is CollisionObject3D:
		_exclude.append((ignore as CollisionObject3D).get_rid())
	visible = true
	_model.visible = true
	_model.position = Vector3.ZERO
	_model.basis = Basis.IDENTITY
	var side := vel.cross(Vector3.UP)
	_spin_axis = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	_spin_rate = SPIN
	# The spoon flies off the moment it leaves the hand.
	if _spoon != null:
		_spoon.visible = true
		_spoon.global_position = from + Vector3(0.0, 0.03, 0.0)
		_spoon.global_basis = Basis.looking_at(vel.normalized() if vel.length() > 0.1 else Vector3.FORWARD, Vector3.UP)
		_spoon_v = vel * 0.55 + Vector3(_rng.randf_range(-1.5, 1.5), 2.5, _rng.randf_range(-1.5, 1.5))
		_spoon_t = 0.0
	add_to_group("live_grenade")

## Seconds to the bang (the HUD's arrow pulses faster as it falls).
func fuse_left() -> float:
	return fuse if state in ["air", "roll", "rest"] else INF

func danger_radius() -> float:
	return 6.0

func danger_at() -> Vector3:
	return global_position

func is_live() -> bool:
	return state in ["air", "roll", "rest"]

func _physics_process(delta: float) -> void:
	step(delta)

## One tick of the grenade (the physics clock; the tests call it with a fixed step).
func step(delta: float) -> void:
	if state == "off":
		return
	if state == "boom":
		_boom_t += delta
		_spoon_fly(delta)
		if _boom_t > 0.6:
			_park()
		return
	fuse -= delta
	_spoon_fly(delta)
	_glow(fuse)
	if fuse <= 0.0:
		detonate()
		return
	delta = minf(delta, 1.0 / 30.0)
	match state:
		"air":
			_fly(delta)
		"roll":
			_roll_step(delta)
	_spin(delta)

func _spoon_fly(delta: float) -> void:
	if _spoon_t < 0.0:
		return
	_spoon_t += delta
	_spoon_v.y -= GRAVITY * delta
	_spoon.global_position += _spoon_v * delta
	_spoon.rotate_object_local(Vector3.RIGHT, 18.0 * delta)
	if _spoon_t > 0.5:
		_spoon.visible = false
		_spoon_t = -1.0

func _fly(delta: float) -> void:
	v.y -= GRAVITY * delta
	var motion := v * delta
	for i in 3:
		if motion.length() < 0.00005:
			return
		var hit := _sweep(global_position, motion)
		if hit.is_empty():
			global_position += motion
			return
		global_position += motion * float(hit.safe) + (hit.normal as Vector3) * 0.004
		_hit(hit)
		if state != "air":
			return
		motion = v * delta * (1.0 - float(hit.safe))

## The sphere swept along `motion`: {} if free, else {safe, normal, collider}.
func _sweep(from: Vector3, motion: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = motion
	q.collision_mask = MASK
	q.exclude = _exclude
	var r := space.cast_motion(q)
	if r.size() < 2 or float(r[0]) >= 1.0:
		return {}
	var at_contact := from + motion * float(r[1])
	q.transform = Transform3D(Basis.IDENTITY, at_contact)
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	var n := -motion.normalized()
	var collider: Object = null
	if not info.is_empty():
		n = info.normal
		collider = instance_from_id(int(info.collider_id))
	if float(r[0]) <= 0.0001 and not info.is_empty():
		# Started touching it: step out along the normal rather than into it.
		global_position += n * 0.01
	swept_blocks += 1
	return {"safe": float(r[0]), "normal": n, "collider": collider}

## What the thing it struck is made of: its "surface" meta, else its name (and its group), kept on it.
static func surface_of(c: Object) -> String:
	if c == null:
		return "concrete"
	if c.has_meta("surface"):
		return String(c.get_meta("surface"))
	var kind := "concrete"
	if c is Node:
		var n := c as Node
		if n.is_in_group("zombies"):
			kind = "flesh"
		else:
			var nm := String(n.name).to_lower() + " " + String(n.get_parent().name).to_lower() if n.get_parent() != null else String(n.name).to_lower()
			for w in METAL_WORDS:
				if nm.contains(w):
					kind = "metal"
					break
			if kind == "concrete":
				for w in WOOD_WORDS:
					if nm.contains(w):
						kind = "wood"
						break
	c.set_meta("surface", kind)
	return kind

func _hit(h: Dictionary) -> void:
	var n: Vector3 = h.normal
	var surf := surface_of(h.get("collider"))
	var spec: Array = SURFACES[surf]
	var vn := v.dot(n)
	if vn >= 0.0:
		return
	var impact := -vn
	var vt := v - n * vn
	v = vt * (1.0 - float(spec[1])) + n * (impact * float(spec[0]))
	bounces += 1
	last_surface = surf
	last_normal = n
	last_impact = impact
	_bounce_sound(surf, impact)
	# Spin follows the new direction.
	var side := v.cross(Vector3.UP)
	if side.length() > 0.01:
		_spin_axis = side.normalized()
	if n.y > 0.7 and impact * float(spec[0]) < SETTLE_SPEED:
		_begin_roll(n)

func _begin_roll(n: Vector3) -> void:
	state = "roll"
	v -= n * v.dot(n)
	v.y = 0.0
	_model.position = Vector3(0.0, -(LIFT + RADIUS - Mk2.RADIUS), 0.0)
	if _roll_voice != null and _roll() != null:
		_roll_voice.stream = _roll()
		_roll_voice.volume_db = -60.0
		_roll_voice.play()

func _roll_step(delta: float) -> void:
	rolling_time += delta
	var sp := Vector2(v.x, v.z).length()
	sp = maxf(sp - ROLL_DECEL * delta, 0.0)
	if sp < STOP_SPEED:
		_rest()
		return
	var dir := Vector3(v.x, 0.0, v.z).normalized()
	v = dir * sp
	var motion := v * delta
	var hit := _sweep(global_position, motion)
	if hit.is_empty():
		global_position += motion
	else:
		global_position += motion * float(hit.safe) + (hit.normal as Vector3) * 0.004
		var n: Vector3 = hit.normal
		if n.y < 0.7:
			# A wall or a kerb: bounces off it and goes on rolling.
			_hit(hit)
			v.y = 0.0
		else:
			# A rise in the floor: carried up it.
			pass
	# Follows the floor (a short ray down); no floor under it and it falls.
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.2, 0), global_position - Vector3(0, 0.35, 0))
	q.collision_mask = WORLD
	var fl := get_world_3d().direct_space_state.intersect_ray(q)
	if fl.is_empty():
		state = "air"
		_model.position = Vector3.ZERO
		if _roll_voice != null:
			_roll_voice.stop()
		return
	global_position.y = float((fl.position as Vector3).y) + RADIUS + LIFT
	_spin_axis = Vector3.UP.cross(dir).normalized()
	_spin_rate = sp / 0.04
	if _roll_voice != null and _roll_voice.playing:
		_roll_voice.volume_db = lerpf(-30.0, -8.0, clampf(sp / 5.0, 0.0, 1.0))
		_roll_voice.pitch_scale = lerpf(0.8, 1.3, clampf(sp / 5.0, 0.0, 1.0))

func _rest() -> void:
	state = "rest"
	v = Vector3.ZERO
	if _roll_voice != null:
		_roll_voice.stop()

func _spin(delta: float) -> void:
	match state:
		"air":
			_model.rotate(_spin_axis, _spin_rate * delta)
		"roll":
			_model.rotate(_spin_axis, _spin_rate * delta)
		"rest":
			pass

func _bounce_sound(surf: String, impact: float) -> void:
	# None under 1 m/s, 12 dB down under 2 m/s.
	if impact < 1.0:
		return
	var key := "wood" if surf == "flesh" else surf
	var st := _bounce("%s_%d" % [key, 1 + _rng.randi() % 3])
	if st == null:
		return
	var a := _voices[_voice_next]
	_voice_next = (_voice_next + 1) % _voices.size()
	a.stream = st
	var db := lerpf(-9.0, 0.0, clampf((impact - 2.0) / 8.0, 0.0, 1.0)) - (12.0 if impact < 2.0 else 0.0)
	a.volume_db = db
	a.pitch_scale = _rng.randf_range(0.94, 1.06) * (0.8 if surf == "flesh" else 1.0)
	a.global_position = global_position
	a.play()

## The bang: the shared explosion and the damage (the holder's); the model is gone, the node goes back to the pool a moment later.
func detonate() -> void:
	if state == "boom" or state == "off":
		return
	var at := global_position + Vector3(0.0, 0.08, 0.0)
	var was_air := state == "air"
	state = "boom"
	_boom_t = 0.0
	went_off_at = at
	remove_from_group("live_grenade")
	_model.visible = false
	if _roll_voice != null:
		_roll_voice.stop()
	var fx := Explosion.of(self)
	if fx != null:
		fx.detonate(at, Vector3.UP if was_air else last_normal, 1.0)
	if is_instance_valid(holder) and holder.has_method("explode") and holder.has_method("grenade_spec"):
		holder.explode(at, holder.grenade_spec())
	went_off.emit(at)

## Off in the hand (the cook ran out): goes off at `at` without ever flying.
func go_off_at(at: Vector3, who: Node) -> void:
	holder = who
	global_position = at
	state = "air"
	visible = true
	last_normal = Vector3.UP
	detonate()

func _park() -> void:
	state = "off"
	visible = false
	if _spoon != null:
		_spoon.visible = false
	_spoon_t = -1.0
	remove_from_group("live_grenade")

## The grenade put away at once (the level ends, a test resets).
func stop() -> void:
	_park()

## Drawn once for the loading black (every part on at `at`).
func show_for_warm(at: Vector3) -> void:
	global_position = at
	visible = true
	_model.visible = true
	_model.position = Vector3.ZERO
	if _spoon != null:
		_spoon.visible = true
		_spoon.global_position = at + Vector3(0.1, 0, 0)

func hide_after_warm() -> void:
	if state == "off":
		visible = false
		if _spoon != null:
			_spoon.visible = false
