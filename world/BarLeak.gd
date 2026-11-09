extends Node3D
## The jukebox through the bar's street door: a dull thump with the door shut,
## the room's music with it open. Only while the bar's open (11 to 02) and only
## near it. A positional sound whose low-pass is its own (the stream player's
## attenuation filter), which follows HingedDoor3D.openness().

const MUSIC := preload("res://assets/sfx/jukebox_loop.wav")
const RANGE := 16.0

var door: Node3D
var _p: AudioStreamPlayer3D
var _level := 0.0

func _ready() -> void:
	_p = AudioStreamPlayer3D.new()
	_p.name = "Leak"
	var s: AudioStream = MUSIC
	if s is AudioStreamWAV:
		s = (s as AudioStreamWAV).duplicate()
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_begin = 0
		(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).data.size() / 2
	_p.stream = s
	_p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	_p.unit_size = 4.0
	_p.max_distance = RANGE + 4.0
	_p.attenuation_filter_cutoff_hz = 500.0
	_p.volume_db = -24.0
	add_child(_p)
	set_process(true)

func _process(delta: float) -> void:
	var who := get_tree().get_first_node_in_group("player") as Node3D
	var want: bool = who != null and GameState.is_open("bar") and who.global_position.distance_to(global_position) < RANGE
	if want and not _p.playing:
		_p.play(randf() * 20.0)
	elif not want and _p.playing:
		_p.stop()
	if not _p.playing or door == null or not is_instance_valid(door):
		return
	_level = lerpf(_level, door.openness(), 1.0 - exp(-8.0 * delta))
	var k := _level * _level
	_p.attenuation_filter_cutoff_hz = 500.0 * pow(14000.0 / 500.0, k)
	_p.volume_db = lerpf(-22.0, -8.0, k)
