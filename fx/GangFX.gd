extends Node3D
## The gunfight's effects in Ghetto Wars: tracers and muzzle flashes (pooled), the enemy's shots as sound in the
## world (darker the further they are), the crack and whizz of a round that goes past you with the shake and blur
## that come with it (suppression), impacts in the walls, and the bottles and grenades the crews throw.
## One per block (world/GangBlock.gd adds it), found with GangFX.of(node).

const GrenadeScript := preload("res://fx/GangGrenade.gd")
const ImpactFX := preload("res://fx/ImpactFX.gd")
const SFX_DIR := "res://assets/sfx/guns/"
const TRACERS := 28
const FLASHES := 12
const LIGHTS := 3
const VOICES := 12
## Tracer speed (m/s) and length (m).
const TRACER_SPEED := 240.0
const TRACER_LEN := 7.0
## A round closer than this to the head snaps (cracks); closer than WHIZZ, it whizzes too.
const SNAP_RANGE := 3.6
const WHIZZ_RANGE := 2.4

## 0..1: rounds going past make the view shake and blur; the HUD reads it.
var suppression := 0.0
## For the tests.
var tracers_spawned := 0
var snaps := 0
var flashes_shown := 0
var shot_sounds := 0
var world_hits := 0
var last_sound := ""
var throws := 0

var _tracers: Array = []
var _tr_next := 0
var _flashes: Array = []
var _fl_next := 0
var _lights: Array = []
var _lt_next := 0
var _voices: Array[AudioStreamPlayer3D] = []
var _vo_next := 0
var _streams := {}
var _impact_frame := -1
var _impact_budget := 0

static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("gang_fx") as Node3D

func _ready() -> void:
	add_to_group("gang_fx")
	name = "GangFX"
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.85, 0.45)
	tm.emission_enabled = true
	tm.emission = Color(1.0, 0.75, 0.3)
	tm.emission_energy_multiplier = 3.0
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var box := BoxMesh.new()
	box.size = Vector3(0.03, 0.03, 1.0)
	for i in TRACERS:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracers.append({"mi": mi, "from": Vector3.ZERO, "dir": Vector3.FORWARD, "len": 0.0, "t": 0.0, "dur": 0.0, "live": false, "w": 1.0})
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.4)
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.7, 0.25)
	fm.emission_energy_multiplier = 4.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	for i in FLASHES:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = fm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flashes.append({"mi": mi, "t": 0.0})
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.7, 0.35)
		l.light_energy = 0.0
		l.omni_range = 7.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append({"l": l, "t": 0.0})
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 200.0
		p.attenuation_filter_cutoff_hz = 2400.0
		p.attenuation_filter_db = -16.0
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(p)
		_voices.append(p)

func _process(delta: float) -> void:
	suppression = maxf(suppression - delta * 0.9, 0.0)
	for t in _tracers:
		if not t["live"]:
			continue
		t["t"] += delta
		var u: float = t["t"] / maxf(t["dur"], 0.001)
		if u >= 1.0 + float(t["len"]) / maxf(t["dur"] * TRACER_SPEED, 0.01):
			t["live"] = false
			(t["mi"] as Node3D).visible = false
			continue
		var travelled: float = minf(t["t"] * TRACER_SPEED, t["total"])
		var tail: float = maxf(t["t"] * TRACER_SPEED - float(t["len"]), 0.0)
		tail = minf(tail, t["total"])
		var l := travelled - tail
		if l < 0.05:
			(t["mi"] as Node3D).visible = false
			continue
		var mi: MeshInstance3D = t["mi"]
		mi.visible = true
		var dir: Vector3 = t["dir"]
		var mid: Vector3 = (t["from"] as Vector3) + dir * (tail + l * 0.5)
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		mi.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3(1, 1, l)), mid)
	for f in _flashes:
		if f["t"] > 0.0:
			f["t"] -= delta
			if f["t"] <= 0.0:
				(f["mi"] as Node3D).visible = false
	for l in _lights:
		if l["t"] > 0.0:
			l["t"] -= delta
			if l["t"] <= 0.0:
				(l["l"] as Light3D).visible = false

## A bullet's streak from `from` to `to`.
func tracer(from: Vector3, to: Vector3, weight := 1.0) -> void:
	var d := to - from
	var total := d.length()
	if total < 0.5:
		return
	var t: Dictionary = _tracers[_tr_next]
	_tr_next = (_tr_next + 1) % TRACERS
	t["from"] = from
	t["dir"] = d / total
	t["total"] = total
	t["len"] = TRACER_LEN * weight
	t["t"] = 0.0
	t["dur"] = total / TRACER_SPEED
	t["live"] = true
	tracers_spawned += 1

func muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	flashes_shown += 1
	var f: Dictionary = _flashes[_fl_next]
	_fl_next = (_fl_next + 1) % FLASHES
	var mi: MeshInstance3D = f["mi"]
	mi.global_position = pos + dir * 0.15
	var s := randf_range(0.7, 1.3)
	mi.scale = Vector3(s, s, s)
	mi.visible = true
	f["t"] = 0.05
	# A light for the flashes near the player only.
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_to(pos) < 35.0:
		var l: Dictionary = _lights[_lt_next]
		_lt_next = (_lt_next + 1) % LIGHTS
		var light: OmniLight3D = l["l"]
		light.global_position = pos + dir * 0.4
		light.light_energy = 2.5
		light.visible = true
		l["t"] = 0.06

func _stream(n: String) -> AudioStream:
	if not _streams.has(n):
		var path := SFX_DIR + n + ".wav"
		_streams[n] = load(path) if ResourceLoader.exists(path) else null
	return _streams[n]

func _play_at(pos: Vector3, n: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _stream(n)
	if s == null:
		return
	var p := _voices[_vo_next]
	_vo_next = (_vo_next + 1) % VOICES
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	last_sound = n

## The shot of `gun` where `pos` is: the gun's own sound, a little different each time, darker with distance.
func shot_sound(pos: Vector3, gun: String) -> void:
	shot_sounds += 1
	var fam := gun
	var n := "fire_%s_%s" % [fam, "ab"[randi() % 2]]
	if _stream(n) == null:
		n = "fire_%s_body_%s" % [fam, "ab"[randi() % 2]]
	_play_at(pos, n, -3.0, randf_range(0.93, 1.06))

## A round has gone by: `closest` is its nearest point to the head. Cracks, whizzes, shakes, blurs.
func snap(origin: Vector3, closest: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(closest)
	if d > SNAP_RANGE:
		return
	snaps += 1
	var k := 1.0 - d / SNAP_RANGE
	_play_at(closest, "bullet_crack_%d" % (1 + randi() % 3), -4.0 + 5.0 * k, randf_range(0.92, 1.08))
	if d < WHIZZ_RANGE:
		_play_at(closest, "bullet_whizz_%d" % (1 + randi() % 3), -6.0 + 5.0 * k, randf_range(0.9, 1.1))
	suppression = minf(suppression + 0.12 + 0.2 * k, 1.0)
	var holder := get_tree().get_first_node_in_group("weapon_holder")
	if holder != null and holder.get("feel") != null:
		holder.feel.add_trauma(0.03 + 0.07 * k)
	ZombieMode.bullet_snap.emit(origin, closest)

## A round into the world: a puff, a spark, a pock, the sound; no more than a few a frame.
func world_hit(pos: Vector3, normal: Vector3) -> void:
	var f := Engine.get_physics_frames()
	if f != _impact_frame:
		_impact_frame = f
		_impact_budget = 3
	if _impact_budget <= 0:
		return
	_impact_budget -= 1
	world_hits += 1
	var fx := ImpactFX.of(self)
	if fx != null:
		fx.bullet_hit(pos, normal)

## A bottle or grenade in the air from `from` to `to` (fx/GangGrenade.gd shows where it will land).
func throw_thing(kind: String, from: Vector3, to: Vector3, who: Node) -> Node3D:
	throws += 1
	var g: Node3D = GrenadeScript.new()
	g.kind = kind
	add_child(g)
	g.launch(from, to, who)
	return g
