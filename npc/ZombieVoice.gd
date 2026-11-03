extends Node3D
## The zombies' throats. One shared pool of positional voices (a horde of 40 does not get 40 audio
## nodes): a zombie asks for a sound when its body does something -- a groan on a heavy step, a
## rasp as it breathes in and out with the stride, a snarl at the windup of a bite, a roar as it
## lunges, a grunt when it is hit -- and gets it if it is close enough to matter, the pool has a
## free (or less important) voice and the same zombie has not just spoken. Sounds are synthesised
## by dev-tools/gen_zombie_voice.py (assets/sfx/zombie/).

const DIR := "res://assets/sfx/zombie/"
const VOICES := 10
const SOUNDS := {
	"groan": 5, "rasp_in": 2, "rasp_out": 2, "snarl": 3, "lunge": 2, "pain": 4,
}
## Higher wins the last free voice.
const PRIORITY := {"rasp": 0, "groan": 1, "snarl": 2, "pain": 3, "lunge": 3}
## Hearing range per kind (m): a rasp is only for the ones close by.
const RANGE := {"rasp": 9.0, "groan": 38.0, "snarl": 26.0, "pain": 30.0, "lunge": 34.0}
## Loudness (dB) at the source, by kind.
const LEVEL := {"rasp": -9.0, "groan": -4.0, "snarl": -1.0, "pain": -2.0, "lunge": 1.0}

static var _streams := {}

var _players: Array[AudioStreamPlayer3D] = []
var _kind: Array[String] = []
var _next := 0
var _listener: Node3D
## Per-physics-frame cap on new sounds, and a count for the tests.
var _frame := -1
var _started_this_frame := 0
var spoken := 0
var refused := 0
var last_kind := ""
var rng := RandomNumberGenerator.new()

static func of(node: Node) -> Node3D:
	var tree := node.get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("zombie_voice")
	if found != null:
		return found as Node3D
	var v: Node3D = (load("res://npc/ZombieVoice.gd") as GDScript).new()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(v)
	return v

static func stream(name_: String) -> AudioStream:
	if not _streams.has(name_):
		_streams[name_] = load(DIR + name_ + ".wav")
	return _streams[name_]

func _ready() -> void:
	add_to_group("zombie_voice")
	name = "ZombieVoice"
	rng.randomize()
	for i in VOICES:
		var a := AudioStreamPlayer3D.new()
		a.unit_size = 7.0
		a.max_distance = 60.0
		add_child(a)
		_players.append(a)
		_kind.append("")

## `kind` is a key of SOUNDS ("rasp" picks in or out by `variant`: 0 in, 1 out). `pitch` is the
## zombie's own voice, `gain_db` how it is muffled or pressed (a crawler, a buried one).
## True if it was spoken.
func say(at: Vector3, kind: String, pitch := 1.0, gain_db := 0.0, variant := -1) -> bool:
	var listener := _get_listener()
	if listener != null:
		var d := listener.global_position.distance_to(at)
		if d > float(RANGE.get(kind, 30.0)):
			return false
	var f := Engine.get_physics_frames()
	if f != _frame:
		_frame = f
		_started_this_frame = 0
	if _started_this_frame >= 2:
		refused += 1
		return false
	var slot := _free_voice(kind)
	if slot < 0:
		refused += 1
		return false
	var file := kind
	if kind == "rasp":
		file = "rasp_out" if variant == 1 else "rasp_in"
	var count: int = int(SOUNDS.get(file, 1))
	var a := _players[slot]
	a.stream = stream("%s_%d" % [file, 1 + rng.randi() % count])
	a.global_position = at
	a.volume_db = float(LEVEL.get(kind, 0.0)) + gain_db
	a.pitch_scale = pitch * rng.randf_range(0.95, 1.05)
	a.play()
	_kind[slot] = kind
	_started_this_frame += 1
	spoken += 1
	last_kind = kind
	return true

## A voice that is not speaking, or the one speaking the least important thing (if this is more important).
func _free_voice(kind: String) -> int:
	var want: int = PRIORITY.get(kind, 1)
	var worst := -1
	var worst_p := 99
	for i in _players.size():
		var j := (_next + i) % _players.size()
		if not _players[j].playing:
			_next = (j + 1) % _players.size()
			return j
		var p: int = PRIORITY.get(_kind[j], 1)
		if p < worst_p:
			worst_p = p
			worst = j
	if worst >= 0 and worst_p < want:
		_next = (worst + 1) % _players.size()
		return worst
	return -1

func _get_listener() -> Node3D:
	if _listener == null or not is_instance_valid(_listener):
		_listener = get_tree().get_first_node_in_group("player") as Node3D
	return _listener

## Anything speaking now (tests).
func speaking() -> int:
	var n := 0
	for a in _players:
		if a.playing:
			n += 1
	return n
