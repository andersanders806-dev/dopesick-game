extends Node
## The lethal slot (SHIP 16G): the Mk 2 frag on G (keyboard) and R1 (pad). Child of the WeaponHolder.
##
##   tap    pin out at 0.25 s and away at 0.35 s in all (the draw, the pull, the throw)
##   hold   cook: the pin is out at 0.25 s, the spoon stays under the thumb, a soft tick counts the 3.5 s fuse in the hand;
##          letting go throws what is left of it; at 0 it goes off in the hand (full blast at arm's length: lethal)
##   crouch held at the throw: an underhand roll (6 m/s) instead of the 16 m/s overhand
##
## The throw is a pooled fx/FragGrenade.gd (scripted ballistics, bounces, rolls, the fuse, the shared explosion). The hands
## are player/GrenadeHands.gd (the off hand takes the pin out and throws, the gun dips). The count and its rules live on the
## holder (grenades, refill, restock); this node is the state machine, the input and the foley.
##
## advance(delta) is the clock (_process); the tests call press(), release() and advance() directly.

const FragGrenade := preload("res://fx/FragGrenade.gd")
const GrenadeHands := preload("res://player/GrenadeHands.gd")
const Explosion := preload("res://fx/Explosion.gd")

enum S { IDLE, DRAW, HELD, WIND, FOLLOW }
const DRAW_TIME := 0.25
const TAP_TOTAL := 0.35
const WIND_TIME := 0.12
const FOLLOW_TIME := 0.38
const FUSE := 3.5
const SPEED_OVER := 16.0
const SPEED_UNDER := 6.0
const LOFT_DEG := 6.0
const SOUNDS := "res://assets/sfx/grenade/"

signal state_changed(s: int)
signal pin_pulled
signal thrown(cooked: float, underhand: bool)
signal went_off_in_hand

var holder: Node
var hands: Node
var state: int = S.IDLE
## Seconds into the state, and seconds the pin has been out.
var t := 0.0
var cook := 0.0
var released := false
var underhand := false
## For the tests and the HUD.
var throws := 0
var in_hand_blasts := 0
var last_cook := 0.0
var last_velocity := Vector3.ZERO
var last_origin := Vector3.ZERO
var _pool: Array = []
var _voices: Array[AudioStreamPlayer] = []
var _voice_next := 0
var _tick_t := 0.0
var _tick_stream: AudioStreamWAV
var _cut_reload := false
static var _snd := {}

func _ready() -> void:
	name = "Lethal"
	holder = get_parent()
	for i in 4:
		var a := AudioStreamPlayer.new()
		a.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(a)
		_voices.append(a)
	hands = GrenadeHands.new()
	add_child(hands)
	hands.setup(self)

static func sound(n: String) -> AudioStream:
	if not _snd.has(n):
		var path := SOUNDS + n + ".wav"
		_snd[n] = load(path) if ResourceLoader.exists(path) else null
	return _snd[n]

## Every file the slot plays, loaded now.
static func warm_files() -> void:
	for n in ["pin_pull", "spoon_ping_1", "spoon_ping_2", "spoon_ping_3", "throw_whoosh_1", "throw_whoosh_2", "throw_whoosh_3"]:
		sound(n)
	FragGrenade.warm_files()
	Explosion.warm_files()

func _process(delta: float) -> void:
	if holder == null or not holder.call("_can_act"):
		if state != S.IDLE:
			reset()
		return
	if InputMap.has_action("lethal"):
		if Input.is_action_just_pressed("lethal"):
			press()
		if state in [S.DRAW, S.HELD] and not Input.is_action_pressed("lethal"):
			release()
	advance(delta)

# --- The input ------------------------------------------------------------------------------

func can_start() -> bool:
	return state == S.IDLE and int(holder.get("grenades")) > 0 and holder.call("_can_act") \
		and float(holder.get("_swing_t")) < 0.0

## The button went down: draws the grenade. False if it can't (none left, mid-throw, mid-swing).
func press() -> bool:
	if not can_start():
		return false
	# A reload under way is cut (and begins again when the throw is done), as a swap does.
	_cut_reload = false
	if bool(holder.get("reloading")):
		_cut_reload = not bool(holder.call("_cut_reload"))
	released = false
	underhand = false
	cook = 0.0
	_enter(S.DRAW)
	return true

## The button came up: throws what the fuse has left.
func release() -> void:
	if state == S.DRAW or state == S.HELD:
		released = true

func _enter(s: int) -> void:
	state = s
	t = 0.0
	state_changed.emit(s)

func active() -> bool:
	return state != S.IDLE

## Puts everything away (death, the level, a test).
func reset() -> void:
	state = S.IDLE
	t = 0.0
	cook = 0.0
	released = false
	if hands != null:
		hands.reset()
	state_changed.emit(S.IDLE)

# --- The clock --------------------------------------------------------------------------------

func advance(delta: float) -> void:
	if holder == null:
		return
	if state != S.IDLE:
		# The gun is out of the way while the grenade is out: no shot, no sights.
		holder.set("_swap_left", maxf(float(holder.get("_swap_left")), 0.05))
		holder.set("aiming", false)
	match state:
		S.DRAW:
			t += delta
			if t >= DRAW_TIME:
				_pull_pin()
		S.HELD:
			t += delta
			cook += delta
			_tick(delta)
			if cook >= FUSE:
				_blow_in_hand()
			elif released and (DRAW_TIME + cook) >= TAP_TOTAL - WIND_TIME:
				_enter(S.WIND)
		S.WIND:
			t += delta
			if t >= WIND_TIME:
				_throw()
		S.FOLLOW:
			t += delta
			if t >= FOLLOW_TIME:
				_enter(S.IDLE)
				_finish()
	if hands != null:
		hands.advance(delta)

func _pull_pin() -> void:
	holder.call("take_grenade")
	_play("pin_pull", -2.0, rng_pitch(0.04))
	cook = 0.0
	_tick_t = 0.0
	pin_pulled.emit()
	_enter(S.HELD)

func _tick(delta: float) -> void:
	# A soft tick counting the fuse down: every half second, quicker in the last second.
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 0.5 if cook < FUSE - 1.0 else 0.22
		if _tick_stream == null:
			_tick_stream = _make_tick()
		_play_stream(_tick_stream, -22.0 + 6.0 * smoothstep(FUSE - 1.2, FUSE, cook), 1.0 + 0.25 * smoothstep(1.0, FUSE, cook))

## A short dry click (a spring catching), made once: a decaying 1.7 kHz tone over a burst of noise.
func _make_tick() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.035)
	var data := PackedByteArray()
	data.resize(n * 2)
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in n:
		var u := float(i) / float(n)
		var env := pow(1.0 - u, 3.0)
		var s := (sin(TAU * 1700.0 * float(i) / rate) * 0.6 + r.randf_range(-1.0, 1.0) * 0.4) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 20000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

func rng_pitch(spread: float) -> float:
	return 1.0 + randf_range(-spread, spread)

func _play(n: String, db: float, pitch := 1.0) -> void:
	var st := sound(n)
	if st != null:
		_play_stream(st, db, pitch)

func _play_stream(st: AudioStream, db: float, pitch: float) -> void:
	var a := _voices[_voice_next]
	_voice_next = (_voice_next + 1) % _voices.size()
	a.stream = st
	a.volume_db = db
	a.pitch_scale = pitch
	a.play()

## Where the hand is (world), and which way the throw goes: [origin, direction, right, up].
func _hand() -> Array:
	var a: Array = holder.call("_aim")
	var o: Vector3 = a[0]
	var d: Vector3 = a[1]
	var right := d.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
	var up := right.cross(d).normalized()
	var fp: bool = Graphics.first_person
	var hand := o + d * (0.42 if fp else 0.5) + right * (0.12 if fp else 0.0) - up * (0.14 if fp else 0.0)
	# Never through a wall: a hand that would be inside one is held at the surface.
	var space: PhysicsDirectSpaceState3D = holder.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, hand)
	q.collision_mask = 1 | 16
	var pl := holder.get("player") as CollisionObject3D
	if pl != null:
		q.exclude = [pl.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		hand = (hit.position as Vector3) - d * 0.12
	return [hand, d, right, up]

func _next_grenade() -> Node:
	for g in _pool:
		if is_instance_valid(g) and not g.is_live() and g.state != "boom":
			return g
	var g: Node = FragGrenade.new()
	g.name = "FragGrenade%d" % _pool.size()
	var world := holder.get_tree().current_scene if holder.get_tree().current_scene != null else holder.get_tree().root
	world.add_child(g)
	_pool.append(g)
	return g

## How many pool grenades exist (tests).
func pool_size() -> int:
	return _pool.size()

func live_grenades() -> Array:
	var out := []
	for g in _pool:
		if is_instance_valid(g) and g.is_live():
			out.append(g)
	return out

## The grenade pool made now (fx/Prewarm.gd): the throw makes no node.
func warm(at: Vector3) -> void:
	warm_files()
	var want := int(holder.get("GRENADE_MAX")) if holder.get("GRENADE_MAX") != null else 4
	while _pool.size() < want:
		_next_grenade_forced()
	for g in _pool:
		g.show_for_warm(at)
	if hands != null:
		hands.warm()

func _next_grenade_forced() -> void:
	var g: Node = FragGrenade.new()
	g.name = "FragGrenade%d" % _pool.size()
	var world := holder.get_tree().current_scene if holder.get_tree().current_scene != null else holder.get_tree().root
	world.add_child(g)
	_pool.append(g)

func unwarm() -> void:
	for g in _pool:
		if is_instance_valid(g):
			g.hide_after_warm()
	if hands != null:
		hands.unwarm()

func _throw() -> void:
	var h := _hand()
	var d: Vector3 = h[1]
	underhand = Input.is_action_pressed("crouch") if InputMap.has_action("crouch") else false
	var pl := holder.get("player") as Node3D
	if pl != null and pl.get("sliding") == true:
		underhand = false
	var speed := SPEED_UNDER if underhand else SPEED_OVER
	var loft := deg_to_rad(LOFT_DEG if not underhand else -4.0)
	var dir: Vector3 = (d * cos(loft) + (h[3] as Vector3) * sin(loft)).normalized()
	var inherit := Vector3.ZERO
	if pl != null and pl.get("velocity") is Vector3:
		inherit = pl.get("velocity")
	var vel := dir * speed + inherit
	var g := _next_grenade()
	g.launch(h[0], vel, maxf(FUSE - cook, 0.05), holder, pl)
	last_cook = cook
	last_velocity = vel
	last_origin = h[0]
	throws += 1
	_play("spoon_ping_%d" % (1 + randi() % 3), -6.0, rng_pitch(0.05))
	_play("throw_whoosh_%d" % (1 + randi() % 3), -3.0 if not underhand else -9.0, rng_pitch(0.06))
	thrown.emit(cook, underhand)
	_enter(S.FOLLOW)

func _blow_in_hand() -> void:
	var h := _hand()
	in_hand_blasts += 1
	last_cook = cook
	var g := _next_grenade()
	g.go_off_at((h[0] as Vector3) - (h[3] as Vector3) * 0.05, holder)
	went_off_in_hand.emit()
	_enter(S.FOLLOW)

func _finish() -> void:
	if _cut_reload:
		holder.set("_reload_resume", true)
		_cut_reload = false
	holder.set("_swap_left", 0.0)
	if holder.has_signal("ammo_changed"):
		holder.emit_signal("ammo_changed")
