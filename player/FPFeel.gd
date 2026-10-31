extends Node
## How the first person feels in Dead Block (research §2): aiming down the
## sights, the gun's sway and bob, recoil in two layers, a trauma shake, the
## slide, the reload and inspect on the viewmodel, and the muzzle flash, shells
## and tracers that go with a shot -- with a sound for every one of them.
##
## A child of the WeaponHolder (it creates this in _ready). It drives the
## Viewmodel (player/Viewmodel.gd) the holder builds, and in Player3D's first
## person path overwrites the camera's field of view, adds the recoil and shake
## to its look, and lowers it for a slide. State is advanced by advance(delta)
## (what _process calls; the tests call it with a fixed delta and `auto = false`),
## and written to the nodes by apply().

const WD := preload("res://weapons/WeaponData.gd")
const Viewmodel := preload("res://player/Viewmodel.gd")
const ImpactFX := preload("res://fx/ImpactFX.gd")

# --- The numbers (research §2) -------------------------------------------------------
const HIP_FOV := 70.0
const SPRINT_FOV := 7.0
## The viewmodel kicks back 2 to 5 cm and up 2 to 6 degrees, on a spring.
const KICK_STIFFNESS := 200.0
const KICK_DAMPING := 20.0
## Camera recoil: degrees up per point of WeaponData.recoil, and how fast it comes back.
const CAM_KICK_DEG := 0.45
const CAM_ADS_KICK := 0.75
const CAM_RECOVER := 17.0
const CAM_HOLD_RATE := 3.0
const CAM_HOLD_TIME := 0.1
## Trauma shake: shake = trauma^2, and trauma decays at 1.5 per second.
const TRAUMA_DECAY := 1.5
const SHAKE_DEG := Vector3(1.6, 1.6, 2.0)
## Sprint and walk: figure-8 bob at the step rate.
const BOB_WALK_HZ := 1.8
const BOB_SPRINT_HZ := 2.6
const BOB_AMP := 0.012
## Slide: a sprint, then crouch.
const SLIDE_TIME := 0.8
const SLIDE_BOOST := 1.4
const SLIDE_END_SPEED := 0.3
const SLIDE_DROP := 0.6
const SLIDE_ROLL_DEG := 4.0
const SLIDE_FOV := 5.0
const SLIDE_COOLDOWN := 0.5
## Walking while aimed is slower.
const ADS_MOVE := 0.6
const INSPECT_TIME := 1.7
const MELEE_TIME := 0.34
const FLASH_TIME := 0.05
const TRACER_SPEED := 300.0
const TRACER_EVERY := 3
const SHELLS := 10
const TRACERS := 6
const SFX_DIR := "res://assets/sfx/guns/"

## Where the viewmodel sits on the hip, and the sprint pose (camera space).
const HIP_POS := Vector3(0.15, -0.17, -0.36)
const SPRINT_POS := Vector3(0.02, -0.055, 0.0)
const SPRINT_ROT := Vector3(-10.0, 24.0, -16.0)
const SLIDE_POS := Vector3(0.0, -0.03, 0.02)
const SLIDE_ROT := Vector3(-4.0, 8.0, -10.0)

# --- State (public so the tests read it) -----------------------------------------------
var holder: Node
var player: Node3D
var camera: Camera3D
## false: _process does nothing (the tests advance by hand).
var auto := true
var rng := RandomNumberGenerator.new()

var ads := 0.0
## What the camera's field of view should be right now, degrees.
var fov := HIP_FOV
## The camera's recoil offset: x pitch up, y yaw (left positive), radians.
var recoil := Vector2.ZERO
var trauma := 0.0
var sliding := false
var slide_time_left := 0.0
var sprint_blend := 0.0
var swap_blend := 0.0
## The viewmodel's springs: position offset (m) and rotation (rad), with velocities.
var kick_pos := Vector3.ZERO
var kick_pos_v := Vector3.ZERO
var kick_rot := Vector3.ZERO
var kick_rot_v := Vector3.ZERO
## Where the viewmodel is right now, camera space.
var vm_position := HIP_POS
var vm_rotation := Vector3.ZERO
var shake_angles := Vector3.ZERO
var eye_drop := 0.0
var shots := 0
var inspecting := false

var _hip_fov := HIP_FOV
var _slide_blend := 0.0
var _slide_dir := Vector3.ZERO
var _slide_v0 := 0.0
var _slide_cd := 0.0
var _sway := Vector2.ZERO
var _look_prev := Vector2.ZERO
var _look_known := false
var _bob_phase := 0.0
var _bob_weight := 0.0
var _burst := 0
var _burst_idle := 0.0
var _since_shot := 1.0
var _flash_left := 0.0
var _reload_total := 0.0
var _reload_prev := 0.0
var _reload_events: Array = []
var _inspect_t := 0.0
var _melee_t := -1.0
var _ads_was := false
var _t := 0.0
var _left_hand := Vector3.ZERO
var _mag_phase := 0.0
var _noise_seed := 0.0
var _shell_pool: Array = []
var _tracer_pool: Array = []
var _tracer_n := 0
var _light: OmniLight3D
var _audio: Array[AudioStreamPlayer] = []
var _audio_next := 0
static var _streams := {}

func _ready() -> void:
	name = "FPFeel"
	holder = get_parent()
	player = holder.get("player") as Node3D
	if player != null:
		camera = player.get("camera") as Camera3D
		if player.get("feel") == null:
			player.set("feel", self)
	rng.randomize()
	_noise_seed = rng.randf() * 100.0
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(p)
		_audio.append(p)
	holder.connect("fired", _on_fired)
	holder.connect("hit", _on_hit)
	holder.connect("reload_started", _on_reload_started)
	holder.connect("reload_finished", _on_reload_finished)
	holder.connect("weapon_changed", _on_weapon_changed)
	holder.connect("traced", _on_traced)
	if holder.has_signal("dry_fired"):
		holder.connect("dry_fired", _on_dry)
	if holder.has_signal("melee_swung"):
		holder.connect("melee_swung", _on_melee)
	Graphics.view_changed.connect(_on_view_changed)

func _exit_tree() -> void:
	if player != null and is_instance_valid(player) and player.get("feel") == self:
		player.set("feel", null)

# --- Reading the world ------------------------------------------------------------------

func _fp() -> bool:
	return player != null and is_instance_valid(player) and bool(player.get("_first_person"))

func _vm() -> Viewmodel:
	var v = holder.get("viewmodel")
	return v as Viewmodel if is_instance_valid(v) else null

func _data() -> WD:
	return holder.get("current")

## The speed the player walks at, as a multiple (aimed is slower).
func speed_mult() -> float:
	return lerpf(1.0, ADS_MOVE, smoothstep(0.0, 1.0, ads))

## Mouse and stick turn by the ratio of the zoomed field of view to the hip's,
## so the same hand movement sweeps the same part of the picture.
func sens_scale() -> float:
	return tan(deg_to_rad(fov) * 0.5) / tan(deg_to_rad(_hip_fov) * 0.5) if ads > 0.0 else 1.0

## The field of view aimed down these sights as a multiple of the hip's:
## about 0.8 for irons, 0.65 for the assault rifle's optic, a sniper scope's
## real zoom.
func ads_fov_mult() -> float:
	var d := _data()
	if d == null:
		return 1.0
	var z := maxf(d.ads_zoom, 1.0)
	if z >= 2.5:
		return 1.0 / z
	return 1.0 - (1.0 - 1.0 / z) * 0.8

## Seconds from hip to sights: 0.2 pistols and SMGs, 0.3 rifles, 0.4 LMG and sniper.
func ads_time() -> float:
	var d := _data()
	if d == null:
		return 0.2
	match d.family():
		"pistol", "smg", "magnum", "wonder":
			return 0.2
		"lmg", "sniper":
			return 0.4
		"shotgun":
			return 0.25
	return 0.3

# --- The slide -----------------------------------------------------------------------

## Starts a slide: only from a sprint, not while one is on or cooling.
func try_slide() -> bool:
	if sliding or _slide_cd > 0.0 or not _fp():
		return false
	if not (player.has_method("is_sprinting") and player.is_sprinting()):
		return false
	var v: Vector3 = player.get("velocity")
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length() < 1.5:
		return false
	sliding = true
	slide_time_left = SLIDE_TIME
	_slide_dir = flat.normalized()
	_slide_v0 = float(player.get("BASE_SPEED")) * float(player.get("SPRINT_MULT")) * SLIDE_BOOST
	holder.set("aiming", false)
	_sound("slide", -3.0, rng.randf_range(0.97, 1.03))
	add_trauma(0.12)
	return true

## The velocity of the slide this physics tick (Player3D asks while `sliding`).
func slide_velocity(delta: float) -> Vector3:
	slide_time_left = maxf(slide_time_left - delta, 0.0)
	var k := 1.0 - slide_time_left / SLIDE_TIME
	var speed := _slide_v0 * lerpf(1.0, SLIDE_END_SPEED, pow(k, 1.4))
	var out := _slide_dir * speed
	if slide_time_left <= 0.0:
		sliding = false
		_slide_cd = SLIDE_COOLDOWN
	return out

# --- Events from the holder ----------------------------------------------------------

func _on_fired() -> void:
	var d := _data()
	if d == null:
		return
	# The shot is heard in either view; the rest is the first person's.
	_sound(_fire_sound(d), -2.0, rng.randf_range(0.97, 1.04))
	if not _fp():
		return
	shots += 1
	_burst += 1
	_burst_idle = 0.0
	_since_shot = 0.0
	# Actual recoil: the view climbs, with a pattern to the side and a little jitter.
	var kick := deg_to_rad(d.recoil * CAM_KICK_DEG) * lerpf(1.0, CAM_ADS_KICK, ads)
	var side := sin(float(_burst) * 1.7) * 0.35 + rng.randf_range(-0.2, 0.2)
	recoil += Vector2(kick, kick * side)
	# Visual recoil: the gun jumps back 2 to 5 cm and up 2 to 6 degrees, and rolls a little.
	var heavy := clampf(d.recoil / 4.0, 0.0, 1.0)
	var back := lerpf(0.02, 0.05, heavy) * lerpf(1.0, 0.5, ads)
	var up := deg_to_rad(lerpf(2.0, 6.0, heavy)) * lerpf(1.0, 0.6, ads)
	# (A burst keeps the gun juddering, not walking back: the more it's back, the less a shot adds.)
	var room := clampf(1.0 - kick_pos.z / 0.05, 0.0, 1.0)
	var room_rot := clampf(1.0 - kick_rot.x / deg_to_rad(6.0), 0.0, 1.0)
	kick_pos_v += Vector3(rng.randf_range(-0.004, 0.004), 0.004, back * room) * 38.0
	kick_rot_v += Vector3(up * room_rot, rng.randf_range(-0.012, 0.012), rng.randf_range(-0.03, 0.03) * (1.0 + heavy)) * 38.0
	add_trauma(0.05 + d.recoil * 0.018)
	_muzzle_flash(d)
	if d.family() in ["pistol", "smg", "ar", "lmg"]:
		_eject_shell(d)
	elif d.family() == "shotgun":
		_later.append([maxf(d.interval() * 0.45, 0.2), "pump"])
	elif d.family() == "sniper":
		_later.append([maxf(d.interval() * 0.3, 0.3), "bolt"])

func _on_dry() -> void:
	_sound("dry_click", -6.0, rng.randf_range(0.95, 1.05))

## Sounds still to come after a shot (the shotgun's pump, the rifle's bolt):
## [seconds left, name].
var _later: Array = []
## The left hand working the pump after a shotgun shot: seconds left.
var _pump_t := 0.0
const PUMP_TIME := 0.5

func _fire_sound(d: WD) -> String:
	var fam := d.family()
	if not (fam in ["pistol", "smg", "ar", "shotgun", "sniper", "magnum", "lmg", "wonder"]):
		fam = "pistol"
	return "fire_%s_%s" % [fam, "ab"[rng.randi() % 2]]

func _on_hit(part: String, killed: bool) -> void:
	if killed:
		_sound("hit_kill", -3.0, rng.randf_range(0.95, 1.05))
		add_trauma(0.08)
	elif part == "head":
		_sound("hit_head", -4.0, rng.randf_range(0.97, 1.03))
	else:
		_sound("hit_body", -5.0, rng.randf_range(0.95, 1.05))

func _on_reload_started() -> void:
	_reload_total = maxf(float(holder.call("reload_left")), 0.01)
	_reload_prev = 0.0
	_reload_events = _events_for(_data())
	var v := _vm()
	if v != null and v.mag_prop != null:
		v.mag_prop.visible = false

func _on_reload_finished() -> void:
	_reload_prev = 0.0
	_reload_events = []
	var v := _vm()
	if v != null and v.mag_prop != null:
		v.mag_prop.visible = false

func _on_weapon_changed(_d: WD) -> void:
	swap_blend = 1.0
	_reload_events = []
	inspecting = false
	_inspect_t = 0.0
	_melee_t = -1.0
	recoil = Vector2.ZERO
	_sound("draw", -4.0, rng.randf_range(0.97, 1.03))

func _on_view_changed(_on: bool) -> void:
	# Leaving first person (or coming back) drops every first-person-only state.
	reset_state()

func _on_melee(_hit: bool) -> void:
	_melee_t = 0.0
	_sound("whoosh", -4.0, rng.randf_range(0.95, 1.05))

func _on_traced(from: Vector3, to: Vector3) -> void:
	var d := _data()
	if d == null or d.pellets > 1 or not _fp():
		return
	_tracer_n += 1
	if _tracer_n % TRACER_EVERY != 0 or from.distance_to(to) < 5.0:
		return
	_spawn_tracer(_muzzle_world(), to)

## Everything first-person is put back: the sights down, the recoil gone, the flash off.
func reset_state() -> void:
	ads = 0.0
	_pump_t = 0.0
	recoil = Vector2.ZERO
	trauma = 0.0
	sliding = false
	_slide_blend = 0.0
	_slide_cd = 0.0
	sprint_blend = 0.0
	kick_pos = Vector3.ZERO
	kick_pos_v = Vector3.ZERO
	kick_rot = Vector3.ZERO
	kick_rot_v = Vector3.ZERO
	inspecting = false
	_inspect_t = 0.0
	_melee_t = -1.0
	_flash_left = 0.0
	_reload_events = []
	_ads_was = false
	fov = _hip_fov
	eye_drop = 0.0
	var v := _vm()
	if v != null:
		v.hide_flash()
	if is_instance_valid(_light):
		_light.visible = false

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

## Inspect the gun (a turn of it in the hands); not while firing, aiming or reloading.
func inspect() -> bool:
	if inspecting or not _fp() or bool(holder.get("reloading")) or ads > 0.05 or sliding:
		return false
	inspecting = true
	_inspect_t = 0.0
	_sound("inspect", -5.0, 1.0)
	return true

# --- The clock -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not auto:
		return
	if InputMap.has_action("crouch") and Input.is_action_just_pressed("crouch"):
		try_slide()
	if InputMap.has_action("inspect") and Input.is_action_just_pressed("inspect"):
		inspect()
	advance(delta)
	apply()

## Steps every piece of feel by `delta` seconds (no node is touched).
func advance(delta: float) -> void:
	_t += delta
	_slide_cd = maxf(_slide_cd - delta, 0.0)
	if not _fp():
		return
	var d := _data()
	var aiming: bool = bool(holder.get("aiming")) and not sliding and d != null and not d.melee
	# --- aiming down the sights
	var dur := ads_time()
	ads = move_toward(ads, 1.0 if aiming else 0.0, delta / maxf(dur, 0.01))
	if aiming and not _ads_was:
		_sound("ads_in", -6.0, rng.randf_range(0.97, 1.03))
	elif not aiming and _ads_was:
		_sound("ads_out", -8.0, rng.randf_range(0.97, 1.03))
	_ads_was = aiming
	var ease := smoothstep(0.0, 1.0, ads)
	# --- sprint, slide
	var speed := 0.0
	if player != null:
		var v: Vector3 = player.get("velocity")
		speed = Vector2(v.x, v.z).length()
	var sprinting: bool = player.has_method("is_sprinting") and player.is_sprinting() and speed > 1.0
	sprint_blend = move_toward(sprint_blend, 1.0 if sprinting and not sliding and ads < 0.05 and not bool(holder.get("reloading")) else 0.0, delta / 0.18)
	_slide_blend = move_toward(_slide_blend, 1.0 if sliding else 0.0, delta / 0.12)
	eye_drop = SLIDE_DROP * smoothstep(0.0, 1.0, _slide_blend)
	# --- the field of view
	var sprint_fov: float = SPRINT_FOV if (sprinting and Graphics.camera_motion) else 0.0
	_hip_fov = lerpf(_hip_fov, HIP_FOV + sprint_fov, 1.0 - exp(-5.0 * delta))
	var ads_fov := HIP_FOV * ads_fov_mult()
	fov = lerpf(_hip_fov, ads_fov, ease) + SLIDE_FOV * smoothstep(0.0, 1.0, _slide_blend)
	# --- camera recoil: comes back to the aim, critically damped
	# While the trigger is down it creeps back slowly (so a burst climbs, but not
	# without end); a tenth of a second after the last shot it comes home fast.
	_since_shot += delta
	recoil *= exp(-(CAM_HOLD_RATE if _since_shot < CAM_HOLD_TIME else CAM_RECOVER) * delta)
	if recoil.length() < 0.00002:
		recoil = Vector2.ZERO
	# --- trauma shake
	trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	var shake := trauma * trauma
	var n := _t * 23.0 + _noise_seed
	shake_angles = Vector3(
		sin(n * 1.31) + 0.5 * sin(n * 2.7 + 1.0),
		sin(n * 1.57 + 2.0) + 0.5 * sin(n * 3.1),
		sin(n * 1.13 + 4.0) + 0.5 * sin(n * 2.3 + 3.0)) * deg_to_rad(1.0) * shake
	shake_angles = Vector3(shake_angles.x * SHAKE_DEG.x, shake_angles.y * SHAKE_DEG.y, shake_angles.z * SHAKE_DEG.z)
	# --- the burst counter
	_burst_idle += delta
	if _burst_idle > 0.35:
		_burst = 0
	# --- the viewmodel's springs
	_step_springs(delta)
	# --- swap, inspect, melee clocks
	swap_blend = maxf(swap_blend - delta / maxf(d.swap_time if d != null else 0.4, 0.1), 0.0)
	if inspecting:
		_inspect_t += delta
		if _inspect_t >= INSPECT_TIME or ads > 0.05 or bool(holder.get("reloading")) or sliding:
			inspecting = false
	if _melee_t >= 0.0:
		_melee_t += delta
		if _melee_t >= MELEE_TIME:
			_melee_t = -1.0
	# --- look sway and bob
	_update_sway(delta)
	var moving := clampf(speed / 3.0, 0.0, 1.3)
	_bob_weight = move_toward(_bob_weight, moving if not sliding else 0.0, delta * 5.0)
	_bob_phase = fmod(_bob_phase + TAU * (BOB_SPRINT_HZ if sprinting else BOB_WALK_HZ) * delta * clampf(speed / 1.6, 0.4, 1.6), TAU * 4.0)
	# --- the reload
	_update_reload(delta)
	# --- the flash
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			var vm := _vm()
			if vm != null:
				vm.hide_flash()
			if is_instance_valid(_light):
				_light.visible = false
	_pump_t = maxf(_pump_t - delta, 0.0)
	for i in range(_later.size() - 1, -1, -1):
		_later[i][0] -= delta
		if _later[i][0] <= 0.0:
			_sound(_later[i][1], -4.0, rng.randf_range(0.97, 1.03))
			if _later[i][1] == "pump":
				_pump_t = PUMP_TIME
			_later.remove_at(i)
	_update_shells(delta)
	_update_tracers(delta)
	_pose(delta)

func _step_springs(delta: float) -> void:
	# Fixed small steps keep a stiff spring stable at any frame rate.
	var steps := maxi(int(ceil(delta / 0.004)), 1)
	var h := delta / float(steps)
	for i in steps:
		kick_pos_v += (-KICK_STIFFNESS * kick_pos - KICK_DAMPING * kick_pos_v) * h
		kick_pos += kick_pos_v * h
		kick_rot_v += (-KICK_STIFFNESS * kick_rot - KICK_DAMPING * kick_rot_v) * h
		kick_rot += kick_rot_v * h

func _update_sway(delta: float) -> void:
	if player == null:
		return
	var look := Vector2(float(player.get("_look_yaw")), float(player.get("_look_pitch")))
	if not _look_known:
		_look_prev = look
		_look_known = true
	var dyaw := angle_difference(_look_prev.x, look.x)
	var dpitch := look.y - _look_prev.y
	_look_prev = look
	# The gun lags the mouse: 2 to 4 degrees at a hard flick.
	var gain := lerpf(0.9, 0.35, ads)
	_sway += Vector2(-dyaw, -dpitch) * gain
	_sway = _sway.limit_length(deg_to_rad(4.0))
	_sway *= exp(-9.0 * delta)

# --- Placing the viewmodel -------------------------------------------------------------

## Works out where the viewmodel and its hands are this frame.
func _pose(_delta: float) -> void:
	var vm := _vm()
	if vm == null:
		return
	var ease := smoothstep(0.0, 1.0, ads)
	var pos: Vector3 = HIP_POS.lerp(vm.ads_position, ease)
	var rot := Vector3(vm.ads_pitch * ease, 0.0, 0.0)
	# Breathing, and the Lissajous drift of the sights while aimed.
	var breath := Vector3(sin(_t * 1.1) * 0.0008, sin(_t * 1.6) * 0.0012, 0.0)
	pos += breath * (1.0 - ease)
	var drift := deg_to_rad(0.2) * ease
	rot.x += sin(_t * 1.3) * drift
	rot.y += sin(_t * 0.9 + 1.0) * drift
	# Walking: a figure-8, small when aimed.
	var amp := BOB_AMP * _bob_weight * lerpf(1.0, 0.2, ease)
	pos += Vector3(sin(_bob_phase) * amp, sin(_bob_phase * 2.0) * amp * 0.7, 0.0)
	rot.z += sin(_bob_phase) * deg_to_rad(0.6) * _bob_weight * (1.0 - ease)
	# Mouse look: the gun trails the aim.
	rot.y += _sway.x
	rot.x += _sway.y
	# Sprint and slide poses.
	var sb := smoothstep(0.0, 1.0, sprint_blend)
	pos += SPRINT_POS * sb
	rot += (Vector3(deg_to_rad(SPRINT_ROT.x), deg_to_rad(SPRINT_ROT.y), deg_to_rad(SPRINT_ROT.z))) * sb
	var lb := smoothstep(0.0, 1.0, _slide_blend)
	pos += SLIDE_POS * lb
	rot += Vector3(deg_to_rad(SLIDE_ROT.x), deg_to_rad(SLIDE_ROT.y), deg_to_rad(SLIDE_ROT.z)) * lb
	# Drawing a gun: it comes up from below.
	var sw := smoothstep(0.0, 1.0, swap_blend)
	pos += Vector3(0.03, -0.26, 0.04) * sw
	rot += Vector3(deg_to_rad(-38.0), deg_to_rad(10.0), deg_to_rad(-12.0)) * sw
	# Inspect, reload, knife.
	var extra := _inspect_pose()
	pos += extra[0]
	rot += extra[1]
	var rl := _reload_pose()
	pos += rl[0]
	rot += rl[1]
	var ml := _melee_pose()
	pos += ml[0]
	rot += ml[1]
	# The spring kicks.
	pos += kick_pos
	rot += kick_rot
	vm_position = pos
	vm_rotation = rot
	_left_hand = rl[2]
	if _pump_t > 0.0:
		# The forend is pulled back to the chest and pushed home.
		var u := 1.0 - _pump_t / PUMP_TIME
		_left_hand += Vector3(0.0, 0.0, 0.16 * sin(PI * u))
		pos += Vector3(0.0, 0.004 * sin(PI * u), 0.012 * sin(PI * u))

func _curve(keys: Array, t: float) -> float:
	# keys: [[t, v], ...] ascending; smooth between them.
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u: float = (t - a[0]) / maxf(b[0] - a[0], 0.0001)
			return lerpf(a[1], b[1], smoothstep(0.0, 1.0, u))
	return keys[keys.size() - 1][1]

func _inspect_pose() -> Array:
	if not inspecting:
		return [Vector3.ZERO, Vector3.ZERO]
	var u := clampf(_inspect_t / INSPECT_TIME, 0.0, 1.0)
	var turn := _curve([[0.0, 0.0], [0.25, 1.0], [0.7, 1.0], [1.0, 0.0]], u)
	var roll := _curve([[0.0, 0.0], [0.3, 1.0], [0.55, -0.4], [0.75, 0.8], [1.0, 0.0]], u)
	return [Vector3(-0.07, 0.02, 0.03) * turn, Vector3(deg_to_rad(10.0), deg_to_rad(-48.0) * turn, deg_to_rad(40.0) * roll)]

func _melee_pose() -> Array:
	if _melee_t < 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var u := _melee_t / MELEE_TIME
	var lunge := _curve([[0.0, 0.0], [0.28, 1.0], [0.5, 0.7], [1.0, 0.0]], u)
	return [Vector3(-0.1, 0.02, -0.12) * lunge, Vector3(deg_to_rad(-16.0), deg_to_rad(32.0), deg_to_rad(-26.0)) * lunge]

## Reload progress 0..1 -> pose of the gun, and where the left hand is (gun space).
func _reload_pose() -> Array:
	var vm := _vm()
	var reloading: bool = bool(holder.get("reloading"))
	if not reloading or vm == null:
		return [Vector3.ZERO, Vector3.ZERO, vm.grip_l if vm != null else Vector3.ZERO]
	var p := _reload_progress()
	var dip := _curve([[0.0, 0.0], [0.16, 1.0], [0.78, 1.0], [0.94, 0.15], [1.0, 0.0]], p)
	var pos := Vector3(-0.03, -0.045, 0.03) * dip
	var rot := Vector3(deg_to_rad(-6.0), deg_to_rad(-8.0), deg_to_rad(-24.0)) * dip
	# The old magazine drops out, the new one goes in, and the action is worked.
	pos += Vector3(0.0, -0.012, 0.0) * _curve([[0.27, 0.0], [0.30, 1.0], [0.36, 0.0], [0.6, 0.0], [0.63, 1.0], [0.69, 0.0]], p)
	rot.x += deg_to_rad(5.0) * _curve([[0.58, 0.0], [0.62, 1.0], [0.7, 0.0]], p)
	var rack := _curve([[0.80, 0.0], [0.84, 1.0], [0.9, 0.0]], p)
	pos.z += 0.03 * rack
	rot.z += deg_to_rad(6.0) * rack
	# The left hand: foregrip -> mag well -> (old mag out) -> belt -> new mag in -> foregrip.
	var hand: Vector3 = vm.grip_l
	var carrying := false
	var shotgun: bool = vm.data != null and vm.data.family() == "shotgun"
	if shotgun:
		var cyc := fposmod(p * 4.0, 1.0)
		var to_port := _curve([[0.0, 0.0], [0.5, 1.0], [1.0, 0.0]], cyc)
		hand = vm.grip_l.lerp(vm.magwell + Vector3(0.0, -0.02, 0.0), smoothstep(0.1, 0.25, p) * (1.0 - smoothstep(0.84, 0.94, p)))
		hand += Vector3(0.0, -0.1, 0.06) * to_port * smoothstep(0.1, 0.25, p) * (1.0 - smoothstep(0.78, 0.86, p))
		carrying = to_port > 0.2 and p > 0.12 and p < 0.8
	else:
		if p < 0.18:
			hand = vm.grip_l.lerp(vm.magwell, smoothstep(0.0, 0.18, p))
		elif p < 0.32:
			hand = vm.magwell.lerp(vm.belt, smoothstep(0.26, 0.32, p))
		elif p < 0.62:
			hand = vm.belt.lerp(vm.magwell, smoothstep(0.42, 0.62, p))
			carrying = p > 0.34
		elif p < 0.74:
			hand = vm.magwell
		else:
			hand = vm.magwell.lerp(vm.grip_l, smoothstep(0.74, 0.88, p))
		carrying = carrying or (p > 0.18 and p < 0.3)
	if vm.mag_prop != null:
		vm.mag_prop.visible = carrying
		vm.mag_prop.position = hand + Vector3(0.0, 0.02, 0.0)
	return [pos, rot, hand]

func _reload_progress() -> float:
	var left := float(holder.call("reload_left"))
	return clampf(1.0 - left / maxf(_reload_total, 0.01), 0.0, 1.0)

## The sounds of a reload, at their moments (progress 0..1).
func _events_for(d: WD) -> Array:
	if d == null:
		return []
	match d.family():
		"shotgun":
			return [[0.14, "shell_in"], [0.30, "shell_in"], [0.46, "shell_in"], [0.62, "shell_in"], [0.84, "pump"]]
		"sniper":
			return [[0.22, "mag_out"], [0.54, "mag_in"], [0.78, "bolt"]]
		"magnum":
			return [[0.18, "mag_out"], [0.52, "shell_in"], [0.62, "shell_in"], [0.84, "mag_in"]]
		"pistol":
			return [[0.28, "mag_out"], [0.62, "mag_in"], [0.84, "rack"]]
		"lmg":
			return [[0.22, "mag_out"], [0.64, "mag_in"], [0.86, "bolt"]]
	return [[0.28, "mag_out"], [0.62, "mag_in"], [0.84, "rack"]]

func _update_reload(_delta: float) -> void:
	if not bool(holder.get("reloading")):
		return
	var p := _reload_progress()
	for ev in _reload_events:
		if _reload_prev < ev[0] and p >= ev[0]:
			_sound(ev[1], -3.0, rng.randf_range(0.97, 1.03))
	_reload_prev = p

# --- Writing to the nodes ---------------------------------------------------------------

## Puts the state on the camera and the viewmodel. Runs after Player3D's own
## camera update (it is a child of the player), so it simply adds to it.
func apply() -> void:
	if not _fp() or camera == null:
		return
	var mount := player.get_node_or_null("CameraMount") as Node3D
	if mount != null:
		mount.rotation = Vector3(
			mount.rotation.x + recoil.x + shake_angles.x,
			mount.rotation.y + recoil.y + shake_angles.y, 0.0)
		mount.global_position.y -= eye_drop
	camera.fov = fov
	var roll := shake_angles.z - deg_to_rad(SLIDE_ROLL_DEG) * smoothstep(0.0, 1.0, _slide_blend)
	if absf(roll) > 0.00001:
		camera.rotate_object_local(Vector3.FORWARD, roll)
	var vm := _vm()
	if vm == null:
		return
	vm.position = vm_position
	vm.rotation = vm_rotation
	vm.visible = not (_scoped())
	if vm.has_method("aim_hands"):
		vm.aim_hands(_left_hand)

## A sniper rifle with the sights up shows the scope's circle instead of the gun.
func _scoped() -> bool:
	var d := _data()
	return d != null and d.family() == "sniper" and ads > 0.92

# --- Muzzle flash, light, shells, tracers -------------------------------------------------

## The muzzle in world space as the screen shows it (the viewmodel's own
## projection is narrower than the camera's, so its camera-space x and y are
## widened by the ratio to land on the same pixels).
func _muzzle_world() -> Vector3:
	var vm := _vm()
	if vm == null or camera == null:
		return camera.global_position if camera != null else Vector3.ZERO
	return _vm_to_world(vm.global_transform * vm.muzzle)

## A point on the viewmodel in world space -> where the real camera must put a
## point to show at the same pixel.
func _vm_to_world(p_world: Vector3) -> Vector3:
	var local := camera.global_transform.affine_inverse() * p_world
	var k := tan(deg_to_rad(camera.fov) * 0.5) / tan(deg_to_rad(Viewmodel.VM_FOV) * 0.5)
	local.x *= k
	local.y *= k
	return camera.global_transform * local

func _muzzle_flash(d: WD) -> void:
	var vm := _vm()
	if vm == null:
		return
	var size := lerpf(1.1, 2.3, clampf(d.recoil / 4.0, 0.0, 1.0))
	if d.family() == "wonder":
		size = 1.0
	vm.show_flash(rng, size)
	_flash_left = FLASH_TIME
	if camera != null and is_inside_tree():
		var fx := ImpactFX.of(self)
		if fx != null:
			fx.muzzle_smoke(_muzzle_world() + (-camera.global_transform.basis.z) * 0.12, -camera.global_transform.basis.z, size * 0.9)
	if not is_instance_valid(_light) and camera != null:
		_light = OmniLight3D.new()
		_light.name = "MuzzleLight"
		_light.omni_range = 4.0
		_light.light_energy = 2.4
		_light.light_color = Color(1.0, 0.68, 0.36)
		_light.shadow_enabled = false
		camera.add_child(_light)
	if is_instance_valid(_light):
		_light.visible = true
		_light.light_energy = rng.randf_range(2.8, 4.4)
		_light.global_position = _muzzle_world() + camera.global_transform.basis * Vector3(0.0, 0.0, -0.25)

func _eject_shell(_d: WD) -> void:
	var vm := _vm()
	if vm == null or camera == null:
		return
	var port := _vm_to_world(vm.global_transform * vm.eject_port)
	var node: MeshInstance3D = null
	for s in _shell_pool:
		if not s["on"]:
			node = s["node"]
			s["on"] = true
			s["bounced"] = false
			s["age"] = 0.0
			var b := camera.global_transform.basis
			var pv: Vector3 = player.get("velocity")
			s["v"] = b * Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(1.4, 2.4), rng.randf_range(0.2, 0.9)) + pv * 0.6
			s["spin"] = Vector3(rng.randf_range(-20, 20), rng.randf_range(-20, 20), rng.randf_range(-20, 20))
			node.global_position = port
			node.visible = true
			return
	if _shell_pool.size() >= SHELLS:
		return
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0045
	mesh.bottom_radius = 0.0045
	mesh.height = 0.02
	mesh.radial_segments = 8
	mesh.rings = 1
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.66, 0.26)
	mat.metallic = 0.9
	mat.roughness = 0.32
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	add_child(m)
	_shell_pool.append({"node": m, "on": false, "v": Vector3.ZERO, "spin": Vector3.ZERO, "age": 0.0, "bounced": false})
	_eject_shell(_d)

func _update_shells(delta: float) -> void:
	if player == null:
		return
	var floor_y: float = player.global_position.y + 0.012
	for s in _shell_pool:
		if not s["on"]:
			continue
		var n: MeshInstance3D = s["node"]
		s["age"] += delta
		if s["age"] > 3.5:
			s["on"] = false
			n.visible = false
			continue
		var v: Vector3 = s["v"]
		if v != Vector3.ZERO:
			v.y -= 9.8 * delta
			n.global_position += v * delta
			n.rotate_x(s["spin"].x * delta)
			n.rotate_z(s["spin"].z * delta)
			if n.global_position.y <= floor_y:
				n.global_position.y = floor_y
				if not s["bounced"]:
					s["bounced"] = true
					v = Vector3(v.x * 0.25, absf(v.y) * 0.3, v.z * 0.25)
					_tink(n.global_position)
				else:
					v = Vector3.ZERO
			s["v"] = v

func _tink(at: Vector3) -> void:
	if camera == null:
		return
	var dist := camera.global_position.distance_to(at)
	_sound("brass_" + "abc"[rng.randi() % 3], clampf(-9.0 - dist * 2.0, -30.0, -8.0), rng.randf_range(0.9, 1.15))

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var t: Dictionary = {}
	for e in _tracer_pool:
		if not e["on"]:
			t = e
			break
	if t.is_empty():
		if _tracer_pool.size() >= TRACERS:
			return
		var m := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.014, 0.014, 1.4)
		m.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.82, 0.45, 0.9)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.top_level = true
		add_child(m)
		t = {"node": m, "on": false, "from": from, "to": to, "u": 0.0}
		_tracer_pool.append(t)
	t["on"] = true
	t["from"] = from
	t["to"] = to
	t["u"] = 0.0
	var n: MeshInstance3D = t["node"]
	n.visible = true

func _update_tracers(delta: float) -> void:
	for t in _tracer_pool:
		if not t["on"]:
			continue
		var n: MeshInstance3D = t["node"]
		var from: Vector3 = t["from"]
		var to: Vector3 = t["to"]
		var len := from.distance_to(to)
		t["u"] += TRACER_SPEED * delta
		if t["u"] >= len:
			t["on"] = false
			n.visible = false
			continue
		var dir := (to - from) / maxf(len, 0.001)
		n.global_position = from + dir * t["u"]
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		n.look_at(n.global_position + dir, up)

# --- Sound ------------------------------------------------------------------------------

static func stream(name_: String) -> AudioStream:
	if not _streams.has(name_):
		var path := SFX_DIR + name_ + ".wav"
		_streams[name_] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name_]

func _sound(name_: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(name_)
	if s == null:
		return
	var p := _audio[_audio_next]
	_audio_next = (_audio_next + 1) % _audio.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	last_sound = name_
	recent.append(name_)
	if recent.size() > 12:
		recent.pop_front()

## The last sound played (the tests read it).
var last_sound := ""
## The last dozen (the tests read them: a later brass tink must not hide an earlier sound).
var recent: Array = []
