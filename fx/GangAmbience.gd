extends Node
## Ghetto Wars' soundscape under the story: the night street and the crowd's bed, a fire that grows with the
## chapters, far-off gunfire from other corners, and the raid's sounds (the ram on the door, the bullhorn, the
## flashbang, sirens, the helicopter's pass). It listens to the story (fx/GhettoStory.gd: chapter_started, beat,
## story_finished); with no story it just plays the night.
## Sounds are in assets/sfx/ghetto/amb (loops) and assets/sfx/ghetto/gw (the raid's one-shots).

const AMB := "res://assets/sfx/ghetto/amb/"
const GW := "res://assets/sfx/ghetto/gw/"
## Far-off shots: the zombie mode's reviewed gun sounds, played a long way off (the 3D player dulls them with distance).
const GUNS := "res://assets/sfx/guns/"
const DISTANT := ["fire_pistol_a", "fire_pistol_b", "fire_ar_tail", "fire_smg_tail", "fire_ar_b", "fire_lmg_tail"]
## Loudness of each bed (dB) by chapter id: [night street, burning block].
const BEDS := {
	"corner": [-15.0, -80.0], "stash": [-15.0, -80.0], "snitch": [-16.0, -24.0],
	"tainted": [-17.0, -19.0], "bust": [-20.0, -15.0],
}
const BED_NAMES := ["night_street_loop", "burning_block_loop"]

var audio := true
var story: Node
var _beds: Array[AudioStreamPlayer] = []
var _siren: AudioStreamPlayer
var _one: Array[AudioStreamPlayer] = []
var _one_next := 0
var _far_t := 6.0
var _chapter := "corner"
var _cache := {}
## For tests: what was played.
var played: Array[String] = []

func _ready() -> void:
	name = "GangAmbience"
	if not audio:
		return
	for i in BED_NAMES.size():
		var p := AudioStreamPlayer.new()
		p.bus = _bus("Ambience")
		p.volume_db = -80.0
		p.stream = _looped(AMB + BED_NAMES[i])
		add_child(p)
		_beds.append(p)
		if p.stream != null:
			p.play(randf() * 10.0)
	for i in 5:
		var q := AudioStreamPlayer.new()
		q.bus = _bus("SFX")
		add_child(q)
		_one.append(q)
	_siren = AudioStreamPlayer.new()
	_siren.bus = _bus("SFX")
	_siren.stream = _looped(GW + "siren_wail_loop")
	_siren.volume_db = -80.0
	add_child(_siren)
	_set_beds("corner", 3.0)

func attach(st: Node) -> void:
	story = st
	st.chapter_started.connect(_on_chapter)
	st.beat.connect(_on_beat)
	st.story_finished.connect(func(_e: String): _stop_siren())

func _bus(n: String) -> String:
	return n if AudioServer.get_bus_index(n) >= 0 else "Master"

func _load(base: String) -> AudioStream:
	if _cache.has(base):
		return _cache[base]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(base + ext):
			s = load(base + ext) as AudioStream
			break
	_cache[base] = s
	return s

## The stream, looping seamlessly (a copy, the resource itself stays as it was).
func _looped(base: String) -> AudioStream:
	var s := _load(base)
	if s == null:
		return null
	s = s.duplicate()
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / (4 if w.stereo else 2)
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s

func _set_beds(chapter: String, secs: float) -> void:
	_chapter = chapter
	var levels: Array = BEDS.get(chapter, BEDS["corner"])
	for i in _beds.size():
		var tw := create_tween()
		tw.tween_property(_beds[i], "volume_db", float(levels[i]), secs)

func _on_chapter(id: String) -> void:
	_set_beds(id, 4.0)

func _on_beat(id: String) -> void:
	match id:
		"raid_start":
			_raid_opening()
		"heli":
			one("heli_pass", -4.0)
		"busted":
			one("flashbang_b", -2.0)
			_stop_siren()

## One-shot from the gw folder; `name` without extension. Returns the played name ("" if missing).
func one(name_: String, db := 0.0, pitch := 1.0) -> String:
	played.append(name_)
	if not audio:
		return name_
	var s := _load(GW + name_)
	if s == null:
		return ""
	var p := _one[_one_next % _one.size()]
	_one_next += 1
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return name_

## The warrant team: the ram, the bullhorn, a flashbang through the window, the sirens.
func _raid_opening() -> void:
	one("door_ram_a", -1.0)
	await get_tree().create_timer(0.9, true, false, true).timeout
	one("bullhorn_whoop", -3.0)
	if _siren != null and _siren.stream != null:
		_siren.play()
		create_tween().tween_property(_siren, "volume_db", -11.0, 2.0)
	played.append("siren_wail_loop")
	await get_tree().create_timer(1.8, true, false, true).timeout
	one("flashbang_a", 0.0)
	var hud := get_tree().get_first_node_in_group("zombie_hud")
	if hud != null and hud.has_method("flash"):
		hud.flash()

func _stop_siren() -> void:
	if _siren != null and _siren.playing:
		var tw := create_tween()
		tw.tween_property(_siren, "volume_db", -80.0, 2.5)
		tw.tween_callback(_siren.stop)

func _process(delta: float) -> void:
	_far_t -= delta
	if _far_t <= 0.0:
		var busy: float = {"corner": 1.0, "stash": 1.2, "snitch": 1.5, "tainted": 1.6, "bust": 2.2}.get(_chapter, 1.0)
		_far_t = randf_range(6.0, 16.0) / busy
		_distant_shot()

## A shot from another corner, a long way off, somewhere around the block.
func _distant_shot() -> void:
	var name_: String = DISTANT[randi() % DISTANT.size()]
	played.append(name_)
	if not audio:
		return
	var s := _load(GUNS + name_)
	var cam := get_viewport().get_camera_3d()
	if s == null or cam == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = _bus("SFX")
	p.volume_db = -4.0
	p.unit_size = 30.0
	p.max_distance = 400.0
	p.attenuation_filter_cutoff_hz = 2200.0
	add_child(p)
	var a := randf() * TAU
	p.global_position = cam.global_position + Vector3(sin(a), 0.0, cos(a)) * randf_range(70.0, 140.0)
	p.finished.connect(p.queue_free)
	p.play()
