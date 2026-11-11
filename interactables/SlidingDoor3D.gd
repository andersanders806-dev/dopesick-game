extends Node3D
## An automatic sliding glass door, as on a supermarket or a pharmacy: two glass panels in a track under a
## header with the sensor in it. Same frame as HingedDoor3D (this node's origin is the middle of the opening
## on the floor, +z toward whoever comes in from outside), and the same calls Door3D and the shops make of a
## door, so either can stand in a doorway:
##   - Anyone (the player, an NPC) coming within SENSE of it on either side makes it open, and it holds open
##     while someone stands in it; it closes a moment after the doorway is clear. Locked (a shop that's shut,
##     `place` + GameState.is_open) it stays shut: the panels shiver in the track and the sensor stays quiet.
##   - A chime when it sees the player (a shop's sensor), a motor and the panels' glide going open, and the same
##     closing (assets/sfx/doors/slide_*.ogg, chime.ogg).
##   - `push_open()` (Door3D: E at the door) opens it and holds it a few seconds, `hold_open()` keeps it so, and a
##     door that you've just come through (`arrival_id`) is standing open and closes behind you.
## The panels are AnimatableBody3Ds moved by script: no joints, no rigid bodies.

const SoundSet := preload("res://interactables/DoorSounds.gd")
const DoorGlass := preload("res://interactables/DoorGlass.gd")

signal opened
signal latched
signal slammed(speed: float)
signal rattled

## How near (m) someone must be, in front of or behind it, for the sensor to see them.
const SENSE := 1.5
const OPEN_TIME := 1.15
const CLOSE_TIME := 1.7
const STAY := 1.4

@export var kind := "sliding_glass"
@export var hinge_east := true
@export var opening := 1.5
@export var door_width := -1.0
@export var frame := true
@export var arrival_id := ""
@export var voice := -1
var quiet_open := false
var locked := false
var place := ""
var shutter: Node3D = null
var touch: Area3D
var leaf: AnimatableBody3D
var sensor: Area3D
## 0 shut, 1 wide open (the smoothed panel position is what's drawn).
var angle := 0.0
var omega := 0.0
var last_noise := {}

var _right: AnimatableBody3D
var _pos := 0.0
var _hold := 0.0
var _bodies := {}
var _chime_cool := 0.0
var _rattle_t := 0.0
var _rattle_cool := 0.0
var _lock_poll := 0.0
var _panel_w := 0.0
var _travel := 0.0
var _height := 2.15
var _seen := {}
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_i := 0
var _was_open := false
var _arrival := false

static var arrival_pending := ""
static var _mats := {}
static var _mesh_cache := {}

func _ready() -> void:
	add_to_group("hinged_doors")
	if opening <= 0.0:
		opening = 1.5
	_panel_w = opening / 2.0 + 0.03
	_travel = _panel_w - 0.05
	_build()
	if arrival_id != "" and arrival_pending == arrival_id:
		arrival_pending = ""
		_arrival = true
		_pos = 1.0
		_hold = 0.9
		_was_open = true
		process_mode = Node.PROCESS_MODE_ALWAYS
	_apply()
	_update_lock()

# --- Calls shared with HingedDoor3D --------------------------------------------------------------

func openness() -> float:
	return smoothstep(0.0, 1.0, _pos)

func is_closed() -> bool:
	return _pos <= 0.0

func swing_deg() -> float:
	return angle * 90.0

func tip() -> Vector3:
	return global_transform * Vector3(opening / 2.0, 1.0, 0.0)

var _hours_text := ""
var _sticker: Label3D

func set_hours(text: String) -> void:
	_hours_text = text
	_update_sticker()

func _update_sticker() -> void:
	if _sticker == null:
		return
	if locked:
		_sticker.text = "CLOSED\n" + _hours_text.replace("OPEN", "OPENS")
		_sticker.modulate = Color(1.0, 0.42, 0.36, 0.95)
	else:
		_sticker.text = _hours_text
		_sticker.modulate = Color(0.92, 0.9, 0.82, 0.92)

func set_locked(on: bool) -> void:
	locked = on
	_update_sticker()

func hold_open(secs: float) -> void:
	_hold = maxf(_hold, secs)

## E at the door (or a script): it opens and stays a few seconds.
func push_open(from_pos: Vector3, _speed := 1.9, _toward := false) -> void:
	if locked and _pos <= 0.0:
		rattle()
		return
	_hold = maxf(_hold, 3.2)
	_sense_chime(from_pos)

func rattle() -> void:
	if _rattle_cool > 0.0:
		return
	_rattle_t = 0.45
	_rattle_cool = 1.4
	_shot("rattle", -6.0, randf_range(1.15, 1.3))
	_noise(6.0, "door_rattle")
	rattled.emit()

# --- Build -----------------------------------------------------------------------------------------

func _mat(color: Color, metallic := 0.0, rough := 0.6) -> StandardMaterial3D:
	var key := [color, metallic, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m

var _batch := {}

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_collect(bm, Transform3D(Basis(), pos), mat)

func _collect(mesh: Mesh, xf: Transform3D, mat: Material) -> void:
	if not _batch.has(mat):
		_batch[mat] = []
	_batch[mat].append([mesh, xf])

func _commit(parent: Node3D, key: String) -> void:
	var full := "%s|%.3f" % [key, opening]
	if not _mesh_cache.has(full):
		var am := ArrayMesh.new()
		for mat in _batch:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for part in _batch[mat]:
				st.append_from(part[0], 0, part[1])
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		_mesh_cache[full] = am
	_batch = {}
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _mesh_cache[full]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 20.0
	mi.visibility_range_end_margin = 5.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)

func _panel(nm: String, sign: float) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = nm
	body.sync_to_physics = true
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(_panel_w, _height, 0.04)
	cs.shape = bs
	cs.position = Vector3(0.0, _height / 2.0, 0.0)
	body.add_child(cs)
	# The picture, drawn for the right-hand panel (centred on its own origin) and mirrored for the left.
	var vis := Node3D.new()
	vis.name = "Visual"
	vis.scale.x = sign
	body.add_child(vis)
	var w := _panel_w
	var h := _height
	var alu := _mat(Color(0.74, 0.75, 0.77), 0.3, 0.45)
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.2, 0.6)
	var stile := 0.06
	_box(Vector3(stile, h, 0.045), Vector3(-w / 2.0 + stile / 2.0, h / 2.0, 0), alu)
	_box(Vector3(stile, h, 0.045), Vector3(w / 2.0 - stile / 2.0, h / 2.0, 0), alu)
	_box(Vector3(w - 2.0 * stile, 0.07, 0.045), Vector3(0, h - 0.035, 0), alu)
	_box(Vector3(w - 2.0 * stile, 0.16, 0.045), Vector3(0, 0.08, 0), alu)
	_box(Vector3(0.02, 0.05, 0.05), Vector3(-w / 2.0 + 0.012, 1.0, 0.0), dark)
	var pane := QuadMesh.new()
	pane.size = Vector2(w - 2.0 * stile, h - 0.23)
	_collect(pane, Transform3D(Basis(), Vector3(0, 0.16 + (h - 0.23) / 2.0, 0)), DoorGlass.material())
	# A band of frosting at eye height: the safety strip every glass door has.
	var film := _mat(Color(0.92, 0.94, 0.95, 0.55), 0.0, 0.8)
	film.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var band := QuadMesh.new()
	band.size = Vector2(w - 2.0 * stile, 0.07)
	_collect(band, Transform3D(Basis(), Vector3(0, 1.45, 0.004)), film)
	_commit(vis, "panel")
	add_child(body)
	return body

func _build() -> void:
	leaf = _panel("PanelLeft", -1.0)
	_right = _panel("PanelRight", 1.0)
	if frame:
		var trim := _mat(Color(0.7, 0.71, 0.73), 0.3, 0.45)
		var dark := _mat(Color(0.1, 0.1, 0.11), 0.2, 0.6)
		var led := StandardMaterial3D.new()
		led.albedo_color = Color(0.1, 0.4, 0.15)
		led.emission_enabled = true
		led.emission = Color(0.2, 1.0, 0.35)
		led.emission_energy_multiplier = 1.2
		var fh := _height + 0.2
		for s in [-1.0, 1.0]:
			_box(Vector3(0.07, fh, 0.14), Vector3(s * (opening / 2.0 + 0.035), fh / 2.0, -0.01), trim)
		_box(Vector3(opening + 0.14, 0.2, 0.16), Vector3(0, _height + 0.1, -0.01), trim)
		_box(Vector3(opening, 0.02, 0.14), Vector3(0, 0.01, 0), dark)
		# The sensor, a black bar under the header with a little green light.
		_box(Vector3(0.3, 0.07, 0.07), Vector3(0, _height - 0.035 - 0.02, 0.07), dark)
		_box(Vector3(0.03, 0.012, 0.012), Vector3(0.09, _height - 0.03, 0.108), led)
		var fm := Node3D.new()
		fm.name = "Frame"
		add_child(fm)
		_commit(fm, "frame")
	sensor = Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 2 | 8
	sensor.monitorable = false
	add_child(sensor)
	var ss := CollisionShape3D.new()
	var sb := BoxShape3D.new()
	sb.size = Vector3(opening + 0.5, 2.2, SENSE * 2.0)
	ss.shape = sb
	ss.position = Vector3(0, 1.1, 0)
	sensor.add_child(ss)
	sensor.body_entered.connect(_on_enter)
	sensor.body_exited.connect(func(b: Node3D): _bodies.erase(b.get_instance_id()); _seen.erase(b.get_instance_id()))
	_sticker = Label3D.new()
	_sticker.name = "Hours"
	_sticker.font_size = 28
	_sticker.pixel_size = 0.0016
	_sticker.outline_size = 0
	_sticker.shaded = false
	_sticker.double_sided = false
	_sticker.visibility_range_end = 14.0
	add_child(_sticker)
	_sticker.position = Vector3(opening / 2.0 - 0.34, 1.68, 0.03)
	_update_sticker()
	# (Kept for callers that look for it: a door you don't use with E has no reach area.)
	touch = Area3D.new()
	touch.name = "Touch"
	touch.collision_layer = 0
	touch.collision_mask = 0
	touch.monitoring = false
	touch.set_meta("prompt", "")
	add_child(touch)
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = 40.0
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(p)
		p.position = Vector3(0, 1.4, 0.2)
		_shots.append(p)

# --- Behaviour ---------------------------------------------------------------------------------------

func _on_enter(b: Node3D) -> void:
	_bodies[b.get_instance_id()] = b
	if b.is_in_group("player"):
		_sense_chime(b.global_position)

func _sense_chime(from_pos: Vector3) -> void:
	if locked or _chime_cool > 0.0 or _pos > 0.05:
		return
	_chime_cool = 5.0
	_shot("chime", -9.0, 1.0)
	_noise(5.0, "door_bell")

func _update_lock() -> void:
	if place != "":
		var now := not GameState.is_open(place)
		if now != locked:
			locked = now
			_update_sticker()

func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	_chime_cool = maxf(0.0, _chime_cool - dt)
	_rattle_cool = maxf(0.0, _rattle_cool - dt)
	_lock_poll -= dt
	if _lock_poll <= 0.0:
		_lock_poll = 0.5
		_update_lock()
	var want := _hold > 0.0
	var in_door := false
	for id in _bodies.keys():
		var b := _bodies[id] as Node3D
		if not is_instance_valid(b):
			_bodies.erase(id)
			continue
		var h := global_transform.affine_inverse() * b.global_position
		var prev: Vector3 = _seen.get(id, b.global_position)
		_seen[id] = b.global_position
		var vel := global_transform.basis.inverse() * ((b.global_position - prev) / dt)
		var toward := -vel.z * signf(h.z)
		var player := b.is_in_group("player")
		if locked and _pos <= 0.0:
			# Walking at a shut door: the panels shiver, the sensor doesn't see you.
			if player and absf(h.z) < 0.9 and absf(h.x) < opening / 2.0 + 0.2 and toward > 0.4:
				rattle()
			continue
		# The player is seen anywhere in the sensor's reach; a passer-by only coming at it
		# (the pavement's walkers shouldn't make a supermarket's door open all day).
		# (Just arrived: the door that closes behind you doesn't wait for you to walk off.)
		if _arrival:
			if absf(h.z) < 0.55 and absf(h.x) < opening / 2.0 + 0.25:
				in_door = true
			continue
		if player or (toward > 0.3 and absf(h.z) < 1.3 and absf(h.x) < opening / 2.0 + 0.3) or (absf(h.z) < 0.9 and absf(h.x) < opening / 2.0 + 0.2):
			want = true
		if absf(h.z) < 0.55 and absf(h.x) < opening / 2.0 + 0.25:
			in_door = true
	if in_door:
		_hold = maxf(_hold, 0.5)
		want = true
	else:
		_hold = maxf(0.0, _hold - dt)
	if locked and _pos <= 0.0:
		want = false
	# It stays open a moment after the doorway empties.
	if want:
		_stay_t = 0.0
	else:
		_stay_t += dt
	var target := 1.0 if (want or (_pos > 0.0 and _stay_t < STAY)) else 0.0
	var rate := (1.0 / OPEN_TIME) if target > _pos else (1.0 / CLOSE_TIME)
	var old := _pos
	_pos = move_toward(_pos, target, rate * dt)
	omega = (_pos - old) / dt
	angle = openness()
	if old <= 0.0 and _pos > 0.0:
		_started_opening()
	elif old >= 1.0 and _pos < 1.0:
		_started_closing()
	elif target == 0.0 and old > 0.0 and _pos < old and not _closing_sound:
		_started_closing()
	if _pos > 0.0:
		_was_open = true
	elif _was_open:
		_was_open = false
		_closing_sound = false
		latched.emit()
		if _arrival:
			_arrival = false
			process_mode = Node.PROCESS_MODE_INHERIT
	_apply()

var _stay_t := 0.0
var _closing_sound := false

func _started_opening() -> void:
	_closing_sound = false
	opened.emit()
	if not quiet_open:
		_shot("slide_open", -5.0, randf_range(0.97, 1.03))

func _started_closing() -> void:
	_closing_sound = true
	_shot("slide_close", -6.0, randf_range(0.97, 1.03))

func _apply() -> void:
	var o := openness()
	var jerk := 0.0
	if _rattle_t > 0.0:
		_rattle_t = maxf(0.0, _rattle_t - get_physics_process_delta_time())
		jerk = sin(_rattle_t * 55.0) * 0.008 * (_rattle_t / 0.45)
	var half := _panel_w / 2.0 - 0.015
	# Closed, each panel's inner edge meets the other's (the right one reaches 15 mm past the middle).
	leaf.position = Vector3(-half - _travel * o + jerk, 0.0, 0.0)
	_right.position = Vector3(half + _travel * o - jerk, 0.0, 0.0)

func _noise(loudness: float, what: String) -> void:
	last_noise = {"kind": what, "loudness": loudness, "pos": global_position}
	if GameState.has_method("emit_noise"):
		GameState.emit_noise(global_position, loudness, what)

func _shot(key: String, db: float, pitch: float) -> void:
	var s := SoundSet.pick(key)
	if s == null:
		return
	var p := _shots[_shot_i]
	_shot_i = (_shot_i + 1) % _shots.size()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
