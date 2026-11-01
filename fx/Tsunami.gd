extends Node3D
## THE TSUNAMI: after the Richter 8.0 surge (the first one always, later ones one time in two) the
## city's warning system goes off and a two minute countdown starts. Two Drowned (npc/Drowned.gd)
## come up out of the street, on different sides. Kill both before 0:00 and the wave is cancelled
## (+2000, relief, a slow-motion beat on the second kill). If the clock runs out the wave hits and
## the run ends: "Drowned by the tsunami".
##
## Over the two minutes it gets worse, on purpose:
##   2:00  the broadcast tone, the sirens across the city, dogs; the sky starts to go dark and green
##   1:40  dogs far off, the wind comes up (louder and higher all the way)
##   1:00  the sea draws back (the water noise sucks out of the street) and the gulls panic
##   0:30  a roar from far off that grows; a black wall of water stands on the horizon at the end
##         of the street and rises; a heartbeat; the vignette throbs; the camera trembles
##   0:15  water seeps over the ground in puddles that run together
##   0:10  the heartbeat doubles, every second is a pulse and a tick
##   0:00  the wave comes down the street (1.9 s, debris tumbling in front of it), the screen goes
##         white, then under; the sound goes dull; then the game over.
## The regular dead keep coming the whole time. Everything is put back when it ends. Camera motion off
## keeps the tremor at a quarter and stops the camera being turned to face the wave.
##
## Public: start(duration), remaining, phase, drowned, kills, the signals. ZombieBlock adds the node
## (as block.tsunami) and it listens to ZombieMode.surge_ended. F11 starts one in a debug build.

signal started
signal drowned_killed(count: int)
signal cancelled
signal wave_hit
signal finished

const DrownedScript := preload("res://npc/Drowned.gd")
const HudScript := preload("res://ui/TsunamiHud.gd")
const WaveScript := preload("res://fx/TsunamiWave.gd")
const SFX_DIR := "res://assets/sfx/tsunami/"

const DURATION := 120.0
const NEED := 2
const BONUS := 2000
## The sea is at this end of the street.
const SEA_DIR := Vector3(-1.0, 0.0, 0.0)
const CAUSE := "Drowned by the tsunami"
## Seconds after the quake's last zombie is out before the warning starts.
const START_DELAY := 2.5
## The wave's run down the street, and how long the water has the screen before the game over.
const RUSH := 1.9
const UNDER_TIME := 2.6
const SINK_TIME := 4.0
const WAVE_DIST := Vector2(560.0, 300.0)
const WAVE_HEIGHT := Vector2(22.0, 80.0)
const REDUCED := 0.25

enum Phase { IDLE, COUNTDOWN, CANCELLED, WAVE, DONE }

var city: Node3D
var spawner: Node
var phase: Phase = Phase.IDLE
var remaining := DURATION
var duration := DURATION
## false: the surge's end does not start it (tests start it by hand).
var auto := true
## The odds of a tsunami after the second and later quakes.
var later_chance := 0.5
var start_delay := START_DELAY
var quakes := 0
var rng := RandomNumberGenerator.new()
var drowned: Array = []
var kills := 0
var hud: CanvasLayer
var wave: Node3D
## What happened, for the tests and the captures.
var bonus_paid := 0
var bonus_count := 0
var waves_hit := 0
var dread := 0.0
var trauma_target := 0.0
var shake_applied := 0.0
var seep := 0.0
var water_level := 0.0
var wave_dist := 0.0
var wave_h := 0.0
var started_count := 0
var fired := {}
var slowmo_active := false

var _pending := -1.0
## true while a skip replays the events: the loops and the HUD states start, the one-shots do not.
var _quiet := false
var _w := 0.0
var _sink := 0.0
var _player: Node3D
var _base_env := {}
var _base_fog_sky := 1.0
var _audio := {}
var _water: MeshInstance3D
var _water_mat: ShaderMaterial
var _lp: AudioEffectLowPassFilter
var _lp_bus := -1
var _last_sec := -1
var _beat_t := 0.0
var _slow_start := -1
var _fade := 0.0
var _gull_t := 0.0
var _rumble_t := 0.0
var _cut := 20000.0

static var _streams := {}

func _init() -> void:
	name = "Tsunami"
	process_priority = 90

func _ready() -> void:
	add_to_group("tsunami")
	rng.randomize()
	hud = HudScript.new()
	add_child(hud)
	wave = WaveScript.new()
	add_child(wave)
	ZombieMode.surge_ended.connect(_on_surge_ended)

func _exit_tree() -> void:
	_restore_hard()

func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_F11 and phase == Phase.IDLE:
		start()

# --- When it starts ---------------------------------------------------------------------------

func _on_surge_ended() -> void:
	if not auto or phase != Phase.IDLE or not ZombieMode.active or ZombieMode.over:
		return
	quakes += 1
	if quakes > 1 and rng.randf() >= later_chance:
		return
	_pending = start_delay

## Starts the countdown now. False if one is on or the run is not.
func start(seconds := DURATION) -> bool:
	if phase != Phase.IDLE or not ZombieMode.active or ZombieMode.over:
		return false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	phase = Phase.COUNTDOWN
	duration = seconds
	remaining = seconds
	kills = 0
	fired = {}
	_pending = -1.0
	_w = 0.0
	_sink = 0.0
	_fade = 0.0
	_last_sec = -1
	ZombieMode.tsunami_active = true
	started_count += 1
	_capture_env()
	_build_audio()
	_build_water()
	_spawn_drowned()
	hud.start(seconds, NEED)
	hud.set_hint("KILL BOTH BEFORE THE WAVE")
	_play("broadcast_tone", -1.0)
	_play("broadcast_static", -12.0)
	_fire("start")
	started.emit()
	return true

## Jumps the clock to `r` seconds left without playing what lies between (captures and tests).
func skip_to(r: float) -> void:
	remaining = r
	_quiet = true
	for pair in _events():
		if r <= pair[0] and not fired.has(pair[1]):
			fired[pair[1]] = true
			_event(pair[1])
	_quiet = false

# --- The events, by time left -----------------------------------------------------------------

static func _events() -> Array:
	return [[100.0, "dogs"], [60.0, "retreat"], [58.0, "gulls"], [45.0, "dogs2"], [30.0, "roar"],
		[15.0, "seep"], [10.0, "last10"]]

func _fire(name_: String) -> void:
	fired[name_] = true

func _check_events() -> void:
	for pair in _events():
		if remaining <= pair[0] and not fired.has(pair[1]):
			fired[pair[1]] = true
			_event(pair[1])

func _event(e: String) -> void:
	match e:
		"dogs":
			_play("dogs_far", -10.0)
		"dogs2":
			_play("dogs_far", -8.0, 0.92)
		"retreat":
			_play("sea_retreat", -2.0)
			hud.set_hint("THE SEA IS DRAWING BACK")
		"gulls":
			_play("gulls_panic", -6.0)
		"roar":
			_start_loop("roar", "wave_roar_far", -50.0)
			_start_loop("heart", "heartbeat_loop", -22.0)
			hud.set_hint("THE WAVE IS ON THE HORIZON")
			hud.set_wave(SEA_DIR, true)
		"seep":
			_start_loop("rush", "water_rush_loop", -40.0)
			_gull_t = 0.0
		"last10":
			_stop_loop("heart")
			_start_loop("heart2", "heartbeat_fast_loop", -8.0)
			_play("countdown_last10", -6.0)
			hud.set_hint("")

# --- The frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _pending >= 0.0:
		_pending -= delta
		if _pending < 0.0:
			start()
	_slowmo_tick()
	match phase:
		Phase.COUNTDOWN:
			_countdown(delta)
		Phase.CANCELLED:
			_cancelled_tick(delta)
		Phase.WAVE:
			_wave_tick(delta)

func _countdown(delta: float) -> void:
	if ZombieMode.over or not ZombieMode.active:
		_abort()
		return
	remaining = maxf(remaining - delta, 0.0)
	_check_events()
	_check_drowned()
	if phase != Phase.COUNTDOWN:
		return
	dread = clampf(1.0 - remaining / 120.0, 0.0, 1.0)
	var k30 := clampf(1.0 - remaining / 30.0, 0.0, 1.0)
	_apply_env(dread)
	_apply_audio(delta, k30)
	_apply_wave(k30)
	_apply_seep(delta)
	_apply_tremor(k30)
	_tick_sounds()
	_hurry()
	hud.set_time(remaining)
	hud.set_targets(drowned)
	hud.set_dread(smoothstep(30.0, 0.0, remaining) * 0.85 + dread * 0.12)
	if remaining <= 0.0:
		_begin_wave()

## Who is dead; both dead cancels it.
func _check_drowned() -> void:
	var dead := 0
	for z in drowned:
		if not is_instance_valid(z) or not z.is_alive():
			dead += 1
	if dead != kills:
		var before := kills
		kills = dead
		hud.set_kills(kills, NEED)
		if kills > before:
			drowned_killed.emit(kills)
			_play("clock_tick", 0.0, 0.5)
	if kills >= NEED and phase == Phase.COUNTDOWN:
		_cancel()

## The Drowned quicken as the sea comes.
func _hurry() -> void:
	var u := 1.0 + 0.6 * clampf(1.0 - remaining / 120.0, 0.0, 1.0)
	for z in drowned:
		if is_instance_valid(z):
			z.urgency = u

func _tick_sounds() -> void:
	var sec := int(ceil(remaining))
	if sec == _last_sec:
		return
	_last_sec = sec
	if sec <= 30 and sec > 10:
		_play("clock_tick", -15.0)

# --- The Drowned --------------------------------------------------------------------------------------

func _spawn_drowned() -> void:
	drowned = []
	var sites := _pick_sites(NEED)
	var holder: Node = spawner.holder if spawner != null else city
	for s in sites:
		var z: CharacterBody3D = DrownedScript.new()
		z.setup_drowned(maxi(ZombieMode.round, 1), rng)
		z.position = s["pos"]
		z.side = s["side"]
		z.died.connect(_on_drowned_died)
		if spawner != null:
			z.died.connect(spawner._on_died)
		holder.add_child(z)
		z.reset_physics_interpolation()
		z.begin_entrance({"type": "rise", "pos": s["pos"], "start": s["pos"] + Vector3(0, -3.0, 0), "out": Vector3.FORWARD,
			"fall": 0.0, "node": null, "roof": false})
		drowned.append(z)

func _on_drowned_died(_z: Node, _part: String, _melee: bool) -> void:
	pass

## Two places on the ground far from the player on different sides: the first as much on the sea side
## as can be had, the second as far round the compass from it as possible.
func _pick_sites(n: int) -> Array:
	var from := Vector3.ZERO
	if _player != null:
		from = _player.global_position
	var ent = spawner.entrances if spawner != null else null
	var cands: Array[Vector3] = []
	for min_d in [38.0, 26.0, 14.0]:
		if ent != null:
			for i in 160:
				var p: Vector3 = ent._random_ground()
				if p == Vector3.INF or not ent.is_clear(p):
					continue
				var d := Vector2(p.x - from.x, p.z - from.z).length()
				if d >= min_d and d <= 95.0:
					cands.append(p)
		if cands.size() >= 6:
			break
	if cands.is_empty():
		for sp in (spawner.spawn_points if spawner != null else []):
			cands.append(sp)
	var out: Array = []
	if cands.is_empty():
		cands.append(from + Vector3(30, 0, 0))
		cands.append(from + Vector3(-30, 0, 0))
	# the first: most towards the sea
	var best := cands[0]
	var best_score := -INF
	for p in cands:
		var to := (p - from)
		to.y = 0.0
		var score := to.normalized().dot(SEA_DIR) * 40.0 + minf(to.length(), 70.0) * 0.2 + rng.randf() * 6.0
		if score > best_score:
			best_score = score
			best = p
	out.append({"pos": best, "side": "sea"})
	if n > 1:
		var a := Vector3(best.x - from.x, 0.0, best.z - from.z)
		var other := cands[0]
		var other_score := -INF
		for p in cands:
			var b := Vector3(p.x - from.x, 0.0, p.z - from.z)
			var ang := absf(a.angle_to(b)) if a.length() > 0.1 and b.length() > 0.1 else 0.0
			var apart := Vector2(p.x - best.x, p.z - best.z).length()
			var score := ang * 30.0 + minf(apart, 80.0) * 0.1 + rng.randf() * 4.0
			if apart < 25.0:
				score -= 100.0
			if score > other_score:
				other_score = score
				other = p
		out.append({"pos": other, "side": "inland"})
	return out

# --- Cancel -----------------------------------------------------------------------------------

func _cancel() -> void:
	phase = Phase.CANCELLED
	_sink = 0.0
	ZombieMode.tsunami_active = false
	bonus_count += 1
	bonus_paid += BONUS
	if ZombieMode.active and not ZombieMode.over:
		ZombieMode.points += BONUS
		ZombieMode.points_changed.emit(ZombieMode.points, BONUS, "tsunami")
	hud.show_cancelled(BONUS)
	_play("cancel_relief", 0.0)
	_start_slowmo()
	_stop_loop("heart")
	_stop_loop("heart2")
	_stop_loop("rush")
	_stop_loop("static")
	trauma_target = 0.0
	cancelled.emit()

func _cancelled_tick(delta: float) -> void:
	_sink += delta
	var k := clampf(_sink / SINK_TIME, 0.0, 1.0)
	# the roar recedes, the sirens wind down, the wave sinks back, the sky clears
	for n in ["siren", "siren2"]:
		var s := _loop(n)
		if s != null:
			s.pitch_scale = lerpf(1.0, 0.55, k)
			s.volume_db = lerpf(s.volume_db, -60.0, minf(delta * 0.9, 1.0))
	for n in ["roar", "wind", "heart", "heart2", "rush"]:
		var p := _loop(n)
		if p != null:
			p.volume_db = lerpf(p.volume_db, -70.0, minf(delta * 0.9, 1.0))
	var r := _loop("roar")
	if r != null:
		r.pitch_scale = lerpf(r.pitch_scale, 0.6, minf(delta, 1.0))
	wave_dist = lerpf(wave_dist, 900.0, minf(delta * 0.7, 1.0))
	wave_h = lerpf(wave_h, 0.0, minf(delta * 1.1, 1.0))
	_place_wave()
	seep = lerpf(seep, 0.0, minf(delta * 0.8, 1.0))
	_update_water()
	dread = lerpf(dread, 0.0, minf(delta * 0.9, 1.0))
	_apply_env(dread)
	trauma_target = 0.0
	hud.set_dread(dread * 0.2)
	if _sink >= SINK_TIME + 1.5:
		_finish()

# --- The wave ---------------------------------------------------------------------------------------

func _begin_wave() -> void:
	phase = Phase.WAVE
	_w = 0.0
	waves_hit += 1
	ZombieMode.tsunami_active = false
	_stop_loop("heart")
	_stop_loop("heart2")
	_stop_loop("roar")
	_stop_loop("static")
	_play("wave_roar_near", 2.0)
	_start_loop("rushloud", "water_rush_loop", -30.0)
	hud.set_hint("")
	hud.flash(1.0)
	wave.show_debris(true)
	hud.set_wave(SEA_DIR, false)
	hud.set_targets([])
	hud.set_time(0.0)
	wave_hit.emit()

## The 1.9 s run, then the screen is the sea, then the end.
func _wave_tick(delta: float) -> void:
	_w += delta
	var k := clampf(_w / RUSH, 0.0, 1.0)
	var eased := k * k
	var d0 := WAVE_DIST.y
	wave_dist = lerpf(d0, -70.0, eased)
	wave_h = WAVE_HEIGHT.y
	_place_wave()
	# the sky and the air go all the way
	dread = 1.0
	_apply_env(1.0)
	var vol := lerpf(-8.0, 0.0, k)
	var siren := _loop("siren")
	if siren != null:
		siren.volume_db = lerpf(siren.volume_db, -40.0, minf(delta * 1.2, 1.0))
	var far_siren := _loop("siren2")
	if far_siren != null:
		far_siren.volume_db = lerpf(far_siren.volume_db, -40.0, minf(delta * 1.2, 1.0))
	var wind := _loop("wind")
	if wind != null:
		wind.volume_db = lerpf(wind.volume_db, vol, minf(delta * 3.0, 1.0))
	var rush := _loop("rushloud")
	if rush != null:
		rush.volume_db = lerpf(-30.0, -2.0, eased)
	# the view turns to face it, and shakes
	_turn_to_wave(k)
	trauma_target = lerpf(0.3, 0.95, eased)
	_apply_shake()
	hud.set_dread(1.0)
	if _w < RUSH:
		hud.set_engulf(smoothstep(0.82, 1.0, k) * 0.6, 0.0)
		return
	var u := _w - RUSH
	if not fired.has("impact"):
		fired["impact"] = true
		_play("wave_impact", 3.0)
		_start_loop("under", "underwater", -80.0)
		_ensure_lowpass()
		hud.flash(1.0)
		wave.show_debris(false)
		ZombieMode.death_cause = CAUSE
	# the white wall hits, then the sea closes over
	var foam := 1.0 - smoothstep(0.0, 0.7, u)
	var under := smoothstep(0.1, 0.9, u)
	hud.set_engulf(foam, under)
	_cut = lerpf(20000.0, 450.0, smoothstep(0.0, 1.0, u))
	if _lp != null:
		_lp.cutoff_hz = _cut
	var und := _loop("under")
	if und != null:
		und.volume_db = lerpf(-40.0, -4.0, under)
	var ru := _loop("rushloud")
	if ru != null:
		ru.volume_db = lerpf(-2.0, -14.0, under)
	# the flood rises and carries the player
	water_level = lerpf(0.0, 3.2, smoothstep(0.0, 1.2, u))
	seep = 1.0
	_update_water()
	trauma_target = lerpf(0.9, 0.35, smoothstep(0.0, 1.4, u))
	_apply_shake()
	_sweep_player(delta, u)
	if u >= UNDER_TIME and phase == Phase.WAVE:
		phase = Phase.DONE
		if ZombieMode.active and not ZombieMode.over:
			ZombieMode.death_cause = CAUSE
			ZombieMode.game_over()
		finished.emit()

func _sweep_player(delta: float, u: float) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is CharacterBody3D):
		return
	var push := -SEA_DIR * 13.0 * clampf(1.0 - u / 1.6, 0.0, 1.0)
	if push.length() > 0.1:
		(_player as CharacterBody3D).move_and_collide(push * delta)

## First person: the head swings round to the sea (not with Camera motion off).
func _turn_to_wave(k: float) -> void:
	if _player == null or not Graphics.camera_motion or not _player.has_method("set_look"):
		return
	if not bool(_player.get("_first_person")):
		return
	var want := atan2(-SEA_DIR.x, -SEA_DIR.z)
	var yaw := float(_player.get("_look_yaw"))
	var step := clampf(3.5 * get_process_delta_time(), 0.0, 1.0) * smoothstep(0.0, 0.5, k)
	var pitch := float(_player.get("_look_pitch"))
	_player.call("set_look", lerp_angle(yaw, want, step), lerpf(pitch, 0.22, step))

func _place_wave() -> void:
	var from := _player.global_position if _player != null and is_instance_valid(_player) else Vector3.ZERO
	wave.place(from, SEA_DIR, wave_dist, wave_h)

func _apply_wave(k30: float) -> void:
	if remaining > 30.0:
		wave_h = 0.0
		wave.place(Vector3.ZERO, SEA_DIR, 900.0, 0.0)
		return
	var e := pow(k30, 1.3)
	wave_h = lerpf(WAVE_HEIGHT.x, WAVE_HEIGHT.y, e)
	wave_dist = lerpf(WAVE_DIST.x, WAVE_DIST.y, e)
	_place_wave()

# --- Water over the ground ----------------------------------------------------------------------------

func _build_water() -> void:
	if _water != null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(420.0, 420.0)
	_water = MeshInstance3D.new()
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float cover = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = texture(noise, wp.xz * 0.028).r * 0.55 + texture(noise, wp.xz * 0.09).g * 0.35 + texture(noise, wp.xz * 0.31).b * 0.1;
	float edge = cover * 1.25 - n * 0.9;
	float a = smoothstep(0.0, 0.07, edge);
	vec2 r1 = texture(noise, wp.xz * 0.45 + vec2(TIME * 0.04, 0.0)).rg;
	vec2 r2 = texture(noise, wp.xz * 0.33 - vec2(0.0, TIME * 0.05)).gb;
	NORMAL_MAP = vec3(0.5 + (r1.x + r2.x - 1.0) * 0.4, 0.5 + (r1.y + r2.y - 1.0) * 0.4, 1.0);
	float rim = smoothstep(0.0, 0.025, edge) * (1.0 - smoothstep(0.025, 0.08, edge));
	ALBEDO = mix(vec3(0.008, 0.04, 0.045), vec3(0.35, 0.45, 0.43), rim * 0.5);
	ROUGHNESS = 0.03;
	SPECULAR = 0.9;
	METALLIC = 0.0;
	EMISSION = vec3(0.004, 0.02, 0.018);
	ALPHA = a * 0.9;
}
"""
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = sh
	_water_mat.set_shader_parameter("noise", DrownedScript.noise_texture())
	_water.material_override = _water_mat
	_water.visible = false
	add_child(_water)

func _apply_seep(delta: float) -> void:
	var want := smoothstep(15.0, 0.0, remaining)
	seep = move_toward(seep, want, delta * 0.4)
	water_level = 0.0
	_update_water()
	if seep > 0.05 and remaining < 15.0 and ZombieMode.active:
		var rush := _loop("rush")
		if rush != null:
			rush.volume_db = lerpf(-40.0, -12.0, seep)

func _update_water() -> void:
	if _water == null:
		return
	_water.visible = seep > 0.01 or water_level > 0.01
	if not _water.visible:
		return
	var p := _player.global_position if _player != null and is_instance_valid(_player) else Vector3.ZERO
	# follows the player in whole steps (the puddles are tied to the world by the shader)
	_water.global_position = Vector3(snappedf(p.x, 8.0), 0.03 + water_level + seep * 0.05, snappedf(p.z, 8.0))
	_water_mat.set_shader_parameter("cover", 1.0 if water_level > 0.01 else seep)

# --- Sky and fog -------------------------------------------------------------------------------------

const ENV_TARGET := {
	"sky": Color(0.004, 0.03, 0.026), "ambient": Color(0.18, 0.5, 0.44), "fog_light": Color(0.03, 0.16, 0.13),
	"moon_color": Color(0.4, 0.88, 0.78),
}

func _capture_env() -> void:
	if city == null or city.get("_night") == null:
		return
	var n: Dictionary = city._night
	_base_env = n.duplicate()
	_base_fog_sky = city._env.fog_sky_affect

func _apply_env(k: float) -> void:
	if _base_env.is_empty() or city == null or not is_instance_valid(city):
		return
	var n: Dictionary = city._night
	var e: Environment = city._env
	for key in ["sky", "ambient", "fog_light", "moon_color"]:
		n[key] = (_base_env[key] as Color).lerp(ENV_TARGET[key], k)
	n["ambient_energy"] = lerpf(_base_env["ambient_energy"], 0.3, k)
	n["moon_energy"] = lerpf(_base_env["moon_energy"], 0.32, k)
	n["fog_density"] = lerpf(_base_env["fog_density"], 0.034, k)
	e.background_color = n["sky"]
	e.ambient_light_color = n["ambient"]
	e.ambient_light_energy = n["ambient_energy"]
	e.fog_light_color = n["fog_light"]
	e.fog_density = n["fog_density"]
	var moon := city.get("_sky_light") as DirectionalLight3D
	if moon != null:
		moon.light_color = n["moon_color"]
		moon.light_energy = n["moon_energy"]

func _restore_env() -> void:
	if _base_env.is_empty() or city == null or not is_instance_valid(city):
		return
	var n: Dictionary = city._night
	for key in _base_env:
		n[key] = _base_env[key]
	_apply_env(0.0)
	_base_env = {}

# --- Sound -----------------------------------------------------------------------------------------

static func _load(sound: String, loop: bool) -> AudioStream:
	var key := sound + ("#loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	var s := load(SFX_DIR + sound + ".wav") as AudioStream
	if s is AudioStreamWAV and loop:
		var wav := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		var bytes := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
		wav.loop_end = wav.data.size() / (bytes * (2 if wav.stereo else 1))
		s = wav
	_streams[key] = s
	return s

func _bus() -> String:
	return "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"

func _amb_bus() -> String:
	return "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"

## A one-shot sound, fire and forget.
func _play(sound: String, db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if _quiet:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = _load(sound, false)
	p.bus = _bus()
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p

func _loop(name_: String) -> AudioStreamPlayer:
	return _audio.get(name_) as AudioStreamPlayer

func _start_loop(key: String, sound: String, db: float) -> void:
	if _audio.has(key) and is_instance_valid(_audio[key]):
		(_audio[key] as AudioStreamPlayer).volume_db = db
		return
	var p := AudioStreamPlayer.new()
	p.name = "Loop_" + key
	p.stream = _load(sound, true)
	p.bus = _amb_bus() if key in ["wind", "siren", "siren2", "rush", "static", "under", "rushloud"] else _bus()
	p.volume_db = db
	add_child(p)
	p.play()
	_audio[key] = p

func _stop_loop(key: String) -> void:
	var p := _loop(key)
	if p != null:
		p.stop()
		p.queue_free()
	_audio.erase(key)

func _build_audio() -> void:
	_start_loop("siren2", "tsunami_siren_far", -14.0)
	_start_loop("siren", "tsunami_siren", -40.0)
	_start_loop("wind", "wind_rise_loop", -40.0)
	_start_loop("static", "broadcast_static", -80.0)
	_stop_loop("static")

## The mix follows the dread: sirens, wind and the roar all rise with the clock.
func _apply_audio(_delta: float, k30: float) -> void:
	var s2 := _loop("siren2")
	if s2 != null:
		s2.volume_db = lerpf(-14.0, -4.0, dread)
	var s := _loop("siren")
	if s != null:
		s.volume_db = lerpf(-40.0, -9.0, smoothstep(0.15, 1.0, dread))
	var w := _loop("wind")
	if w != null:
		w.volume_db = lerpf(-40.0, -7.0, pow(dread, 1.1))
		w.pitch_scale = lerpf(0.88, 1.18, dread)
	var r := _loop("roar")
	if r != null:
		r.volume_db = lerpf(-46.0, -2.0, pow(k30, 1.5))
		r.pitch_scale = lerpf(0.85, 1.05, k30)
	var h := _loop("heart")
	if h != null:
		h.volume_db = lerpf(-20.0, -7.0, k30)
	# gulls and dogs now and then in the last minute
	if remaining < 60.0 and remaining > 12.0:
		_gull_t -= _delta
		if _gull_t <= 0.0:
			_gull_t = rng.randf_range(9.0, 16.0)
			_play("gulls_panic", -9.0 - rng.randf() * 4.0, rng.randf_range(0.85, 1.1))

# --- The camera --------------------------------------------------------------------------------------

func _motion() -> float:
	return 1.0 if Graphics.camera_motion else REDUCED

func _apply_tremor(k30: float) -> void:
	var t := 0.0
	if remaining <= 30.0:
		t = lerpf(0.04, 0.17, k30)
	if remaining <= 10.0:
		t += 0.1 * (1.0 - remaining / 10.0)
	# a throb on every beat
	if remaining <= 30.0:
		_beat_t += get_process_delta_time() * (2.2 if remaining <= 10.0 else 1.15)
		t += 0.05 * exp(-fposmod(_beat_t, 1.0) * 8.0)
	trauma_target = t
	_apply_shake()
	_pulse_pad(get_process_delta_time(), k30)

func _player_feel() -> Node:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player.get("feel") as Node if _player != null else null

## Holds the camera's trauma at the target: FPFeel's shake in first person, the kick in third.
func _apply_shake() -> void:
	var want := trauma_target * _motion()
	shake_applied = want
	var feel = _player_feel()
	if feel != null and want > feel.trauma:
		feel.add_trauma(want - feel.trauma)
	if _player != null and not bool(_player.get("_first_person")) and Graphics.camera_motion and _player.has_method("kick"):
		_player.kick(want * 0.6)

func _pulse_pad(delta: float, k30: float) -> void:
	if remaining > 30.0:
		return
	_rumble_t -= delta
	if _rumble_t > 0.0:
		return
	_rumble_t = 0.45 if remaining > 10.0 else 0.22
	var strength := 0.08 + 0.3 * k30
	var holder := get_tree().get_first_node_in_group("weapon_holder")
	var pad = holder.get_node_or_null("PadRumble") if holder != null else null
	if pad != null:
		pad.ask([strength * 0.5, strength, 0.0], "tsunami")

# --- Slow motion on the second kill ------------------------------------------------------------------

func _start_slowmo() -> void:
	slowmo_active = true
	_slow_start = Time.get_ticks_msec()
	Engine.time_scale = 0.25
	AudioServer.playback_speed_scale = 0.5

func _slowmo_tick() -> void:
	if not slowmo_active:
		return
	var real := float(Time.get_ticks_msec() - _slow_start) / 1000.0
	var k := clampf((real - 0.7) / 0.7, 0.0, 1.0)
	Engine.time_scale = lerpf(0.25, 1.0, k)
	AudioServer.playback_speed_scale = lerpf(0.5, 1.0, k)
	if real >= 1.4:
		_end_slowmo()

func _end_slowmo() -> void:
	slowmo_active = false
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0

# --- Muffled audio underwater ------------------------------------------------------------------------

func _ensure_lowpass() -> void:
	if _lp != null:
		return
	_lp = AudioEffectLowPassFilter.new()
	_lp.cutoff_hz = 20000.0
	_lp.resonance = 0.6
	_lp_bus = AudioServer.get_bus_index("Master")
	AudioServer.add_bus_effect(_lp_bus, _lp)

func _remove_lowpass() -> void:
	if _lp == null:
		return
	for i in AudioServer.get_bus_effect_count(_lp_bus):
		if AudioServer.get_bus_effect(_lp_bus, i) == _lp:
			AudioServer.remove_bus_effect(_lp_bus, i)
			break
	_lp = null

# --- Ending ----------------------------------------------------------------------------------------

## Everything back as it was; the Drowned that are left are not left.
func _finish() -> void:
	_teardown()
	phase = Phase.IDLE
	finished.emit()

func _abort() -> void:
	# the run ended some other way (the dead got you): nothing to show
	_teardown()
	phase = Phase.DONE

func _teardown() -> void:
	ZombieMode.tsunami_active = false
	hud.clear()
	for k in _audio.keys():
		_stop_loop(k)
	wave.show_debris(false)
	wave.visible = false
	seep = 0.0
	water_level = 0.0
	_update_water()
	_restore_env()
	_remove_lowpass()
	_end_slowmo()
	for z in drowned:
		if is_instance_valid(z) and z.is_alive():
			z.queue_free()
	drowned = []
	trauma_target = 0.0
	dread = 0.0

## The node is leaving the tree (a scene change, a restart): what is global goes back.
func _restore_hard() -> void:
	_remove_lowpass()
	if Engine.time_scale != 1.0 and slowmo_active:
		_end_slowmo()
	AudioServer.playback_speed_scale = 1.0
	if ZombieMode != null:
		ZombieMode.tsunami_active = false
