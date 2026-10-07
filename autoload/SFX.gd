extends Node

## Centralized sound effects: a small pooled player for one-shots
## (SFX.play("cash")) plus dedicated looping players for ambience
## (wanted siren, low-craving heartbeat) driven by GameState signals.

const LOW_CRAVING_THRESHOLD := 20.0
const POOL_SIZE := 8

const SOUNDS := {
	"footstep_a": preload("res://assets/sfx/footstep_a.wav"),
	"footstep_b": preload("res://assets/sfx/footstep_b.wav"),
	"door": preload("res://assets/sfx/door.wav"),
	"steal": preload("res://assets/sfx/steal.wav"),
	"cash": preload("res://assets/sfx/cash.wav"),
	"busted": preload("res://assets/sfx/busted.wav"),
	"blip": preload("res://assets/sfx/blip.wav"),
	"fix": preload("res://assets/sfx/fix.wav"),
	"sleep": preload("res://assets/sfx/sleep.wav"),
	"phone": preload("res://assets/sfx/phone.wav"),
}

## Recorded one-shots from Kenney's CC0 Impact Sounds and RPG Audio packs
## (assets/sfx/kenney/). Each name has several takes and play() picks one at
## random, so repeated actions don't sound like the same sample every time.
## These override the synthesized SOUNDS entry of the same name.
const KENNEY := "res://assets/sfx/kenney/"
const VARIANTS := {
	"door": [preload(KENNEY + "door_open_1.ogg"), preload(KENNEY + "door_open_2.ogg")],
	"steal": [preload(KENNEY + "cloth_1.ogg"), preload(KENNEY + "cloth_2.ogg"),
		preload(KENNEY + "cloth_3.ogg"), preload(KENNEY + "cloth_4.ogg")],
	"cash": [preload(KENNEY + "coins_1.ogg"), preload(KENNEY + "coins_2.ogg")],
	"latch": [preload(KENNEY + "latch.ogg")],
	"punch": [preload(KENNEY + "punch_0.ogg"), preload(KENNEY + "punch_1.ogg"), preload(KENNEY + "punch_2.ogg")],
	# Withdrawal cramps: the same wet cough and sigh the bar regulars make.
	"groan": [preload("res://assets/sfx/patron_cough_wet.wav"), preload("res://assets/sfx/patron_sigh.wav")],
}
## The Kenney recordings are mastered 6-13 dB hotter than the synthesized
## set; this brings them level with it so callers' volume_db still means
## the same thing.
const VARIANT_GAIN_DB := {"door": -12.0, "steal": -5.0, "cash": -12.0, "latch": -10.0, "punch": -6.0}

const FOOTSTEPS := {
	"concrete": [preload(KENNEY + "step_concrete_0.ogg"), preload(KENNEY + "step_concrete_1.ogg"),
		preload(KENNEY + "step_concrete_2.ogg"), preload(KENNEY + "step_concrete_3.ogg"),
		preload(KENNEY + "step_concrete_4.ogg")],
	"wood": [preload(KENNEY + "step_wood_0.ogg"), preload(KENNEY + "step_wood_1.ogg"),
		preload(KENNEY + "step_wood_2.ogg"), preload(KENNEY + "step_wood_3.ogg"),
		preload(KENNEY + "step_wood_4.ogg")],
}
const FOOTSTEP_GAIN_DB := -6.0
## Which floor each room has. Anything not listed (City, stores, Jail) is
## concrete, asphalt, or tile, which all read as a hard "concrete" step.
const ROOM_SURFACE := {"Apartment3D": "wood", "DiveBar3D": "wood"}

## Withdrawal hallucinations: deep in the sickness you start hearing things
## -- a siren a few streets over, the lookout's whistle, footsteps behind
## you, a knock, someone muttering -- placed a few metres away in the room
## so they sound real. They're only ever sounds that could be real, which
## is the point: you can't tell which ones to ignore.
const PHANTOM_MIN_SICKNESS := 0.6
const PHANTOM_INTERVAL := Vector2(12.0, 28.0)
const PHANTOM_VOICES := [
	preload("res://assets/sfx/patron_mutter_a.wav"),
	preload("res://assets/sfx/patron_mutter_b.wav"),
	preload("res://assets/sfx/patron_mutter_c.wav"),
]
const PHANTOM_WHISTLE := preload("res://assets/sfx/lookout_whistle.wav")

const SIREN_STREAM := preload("res://assets/sfx/siren_loop.wav")
const HEARTBEAT_STREAM := preload("res://assets/sfx/heartbeat_loop.wav")

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _siren_player: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer
var _phantom_timer: float = PHANTOM_INTERVAL.x

## --- Mix -----------------------------------------------------------------
## Buses: Music, SFX, Voice, Ambience, all into a Master with a compressor
## and a limiter -- the compressor is most of what makes impacts and voices
## sit up front instead of getting lost under the room tone. SFX and Voice
## also go through a reverb whose size follows the room you're in.
const ROOM_ACOUSTICS := {
	# room_size, damping, wet
	"City3D": [0.35, 0.6, 0.10],
	"DiveBar3D": [0.45, 0.55, 0.16],
	"Apartment3D": [0.25, 0.7, 0.12],
	"Jail3D": [0.6, 0.2, 0.28],
	"Backyard3D": [0.4, 0.5, 0.14],
	"Shelter3D": [0.55, 0.4, 0.2],
}
const STORE_ACOUSTICS := [0.45, 0.35, 0.14]

## What plays where. The bar has its jukebox instead; stores, the jail, and
## the shelter keep to their room tone. A chase overrides everything.
const MUSIC := {
	"city_day": preload("res://assets/music/lofi_loop.ogg"),
	"city_night": preload("res://assets/music/friendly_trap.ogg"),
	"apartment": preload("res://assets/music/lofi_hiphop.ogg"),
	"chase": preload("res://assets/music/downtempo_chase.ogg"),
}
const MUSIC_VOLUME_DB := {"city_day": -14.0, "city_night": -12.0, "apartment": -22.0, "chase": -7.0}
const MUSIC_FADE := 1.5
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_track: String = ""

func _ready() -> void:
	_setup_buses()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		# A door's sound plays on through the room change's fade, which
		# pauses the tree.
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
	get_tree().node_added.connect(_on_node_added)

	_siren_player = AudioStreamPlayer.new()
	_siren_player.stream = SIREN_STREAM
	_siren_player.volume_db = -8.0
	add_child(_siren_player)
	_siren_player.finished.connect(func(): if GameState.wanted: _siren_player.play())

	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.stream = HEARTBEAT_STREAM
	_heartbeat_player.volume_db = -6.0
	add_child(_heartbeat_player)
	_heartbeat_player.finished.connect(func(): if GameState.craving <= LOW_CRAVING_THRESHOLD: _heartbeat_player.play())

	GameState.wanted_changed.connect(_on_wanted_changed)
	GameState.craving_changed.connect(_on_craving_changed)
	GameState.busted.connect(func(): play("busted"))
	GameState.clock_changed.connect(func(_m): if _music_track.begins_with("city"): _update_music())

func _process(delta: float) -> void:
	if GameState.sickness() < PHANTOM_MIN_SICKNESS:
		# The first one comes a little while after it gets bad, not at once.
		_phantom_timer = maxf(_phantom_timer, PHANTOM_INTERVAL.x * 0.5)
		return
	_phantom_timer -= delta
	if _phantom_timer > 0.0:
		return
	_phantom_timer = randf_range(PHANTOM_INTERVAL.x, PHANTOM_INTERVAL.y)
	play_phantom()

## One sound that isn't there, somewhere 4-8 m from you. Returns its kind.
func play_phantom(kind := "") -> String:
	var tree := get_tree()
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null or tree.current_scene == null:
		return ""
	if kind == "":
		kind = ["siren", "whistle", "steps", "knock", "voice"].pick_random()
	var p := AudioStreamPlayer3D.new()
	p.name = "Phantom"
	p.add_to_group("phantom_sounds")
	p.unit_size = 4.0
	p.max_distance = 30.0
	tree.current_scene.add_child(p)
	var angle := randf() * TAU
	p.global_position = player.global_position + Vector3(cos(angle), 0.4, sin(angle)) * randf_range(4.0, 8.0)
	match kind:
		"siren":
			# A few seconds of it, fading, as if a car went by a street over.
			p.stream = SIREN_STREAM
			p.volume_db = -14.0
			p.play()
			var tween := p.create_tween()
			tween.tween_interval(1.5)
			tween.tween_property(p, "volume_db", -40.0, 2.0)
			tween.tween_callback(p.queue_free)
			return kind
		"whistle":
			p.stream = PHANTOM_WHISTLE
			p.volume_db = -4.0
		"voice":
			p.stream = PHANTOM_VOICES.pick_random()
			p.volume_db = -2.0
			p.pitch_scale = randf_range(0.75, 0.85)
		"steps", "knock":
			# Several hits in a row: footsteps closing in, or three raps.
			var steps := kind == "steps"
			var tween := p.create_tween()
			for i in (5 if steps else 3):
				tween.tween_callback(func():
					p.stream = footstep_stream() if steps else FOOTSTEPS["wood"].pick_random()
					p.pitch_scale = randf_range(0.9, 1.0) if steps else 0.55
					p.volume_db = FOOTSTEP_GAIN_DB + (2.0 if steps else 6.0)
					p.play())
				tween.tween_interval(0.34 if steps else 0.22)
			tween.tween_interval(0.5)
			tween.tween_callback(p.queue_free)
			return kind
	p.finished.connect(p.queue_free)
	p.play()
	return kind

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream
	if VARIANTS.has(name):
		stream = VARIANTS[name].pick_random()
		volume_db += VARIANT_GAIN_DB.get(name, 0.0)
	elif SOUNDS.has(name):
		stream = SOUNDS[name]
	else:
		return
	_play_stream(stream, volume_db, pitch)

## A random footfall for the floor of the room you're in.
func footstep_stream() -> AudioStream:
	var scene := get_tree().current_scene
	var surface: String = ROOM_SURFACE.get(String(scene.name) if scene else "", "concrete")
	return FOOTSTEPS[surface].pick_random()

func play_footstep(volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_play_stream(footstep_stream(), volume_db + FOOTSTEP_GAIN_DB, pitch)

func _play_stream(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _setup_buses() -> void:
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -16.0
		comp.ratio = 3.0
		comp.attack_us = 8000.0
		comp.release_ms = 180.0
		comp.gain = 4.0
		AudioServer.add_bus_effect(master, comp)
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, limiter)
	for bus in ["Music", "SFX", "Voice", "Ambience", "Walkman"]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")
		if bus in ["SFX", "Voice"]:
			AudioServer.add_bus_effect(i, AudioEffectReverb.new())
		if bus == "Voice":
			# Presence: a little lift where speech is intelligible, and its
			# own compressor so quiet and loud lines come out even.
			var eq := AudioEffectEQ6.new()
			eq.set_band_gain_db(3, 3.0)
			eq.set_band_gain_db(0, -4.0)
			AudioServer.add_bus_effect(i, eq)
			var vcomp := AudioEffectCompressor.new()
			vcomp.threshold = -20.0
			vcomp.ratio = 4.0
			vcomp.gain = 5.0
			AudioServer.add_bus_effect(i, vcomp)
			AudioServer.set_bus_volume_db(i, 2.0)
		if bus == "Ambience":
			AudioServer.set_bus_volume_db(i, -2.0)
		if bus == "Walkman":
			# Cheap foam headphones and a worn tape: thin low end, soft top,
			# and a little wow from the chorus.
			var weq := AudioEffectEQ6.new()
			weq.set_band_gain_db(0, -6.0)
			weq.set_band_gain_db(5, -5.0)
			AudioServer.add_bus_effect(i, weq)
			var wow := AudioEffectChorus.new()
			wow.voice_count = 1
			wow.wet = 0.18
			wow.dry = 1.0
			AudioServer.add_bus_effect(i, wow)

## Every sound a room brings with it goes onto the right bus: looping
## room tone to Ambience, everything else to SFX.
func _on_node_added(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		if node.bus != "Master" or node.get_parent() == self:
			return
		var looping: bool = node.autoplay or node.name == "RoomTone"
		node.bus = "Ambience" if looping else "SFX"
	elif node.get_parent() == get_tree().root and node is Node3D:
		_enter_room.call_deferred(node)

func _enter_room(room: Node) -> void:
	if not is_instance_valid(room):
		return
	var a: Array = ROOM_ACOUSTICS.get(String(room.name), STORE_ACOUSTICS)
	for bus in ["SFX", "Voice"]:
		var reverb := AudioServer.get_bus_effect(AudioServer.get_bus_index(bus), 0) as AudioEffectReverb
		reverb.room_size = a[0]
		reverb.damping = a[1]
		reverb.wet = a[2] * (0.6 if bus == "Voice" else 1.0)
		reverb.dry = 1.0
	_update_music()

func _update_music() -> void:
	var scene := get_tree().current_scene
	var room := String(scene.name) if scene else ""
	var track := ""
	var walkman := get_node_or_null("/root/Walkman")
	if walkman and walkman.is_playing():
		track = ""
	elif GameState.wanted:
		track = "chase"
	elif room == "City3D" or room == "Backyard3D":
		track = "city_day" if GameState.daylight() > 0.5 else "city_night"
	elif room == "Apartment3D":
		track = "apartment"
	play_music(track)

## Crossfades to `track` ("" for silence). Picks up where the same track
## left off rather than restarting it.
func play_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old := _music_a if _music_a.playing and _music_a.volume_db > -60.0 else _music_b
	var new := _music_b if old == _music_a else _music_a
	var tween := create_tween().set_parallel(true)
	tween.tween_property(old, "volume_db", -80.0, MUSIC_FADE)
	tween.chain().tween_callback(old.stop)
	if track != "":
		new.stream = MUSIC[track]
		new.volume_db = -80.0
		new.play()
		var t2 := create_tween()
		t2.tween_property(new, "volume_db", MUSIC_VOLUME_DB[track], MUSIC_FADE)

func _on_wanted_changed(is_wanted: bool) -> void:
	_update_music.call_deferred()
	if is_wanted:
		if not _siren_player.playing:
			_siren_player.play()
	else:
		_siren_player.stop()

func _on_craving_changed(craving: float) -> void:
	var should_play := craving <= LOW_CRAVING_THRESHOLD
	if should_play and not _heartbeat_player.playing:
		_heartbeat_player.play()
	elif not should_play and _heartbeat_player.playing:
		_heartbeat_player.stop()
