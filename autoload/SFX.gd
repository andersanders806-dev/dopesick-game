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

const SIREN_STREAM := preload("res://assets/sfx/siren_loop.wav")
const HEARTBEAT_STREAM := preload("res://assets/sfx/heartbeat_loop.wav")

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _siren_player: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer

func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

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

func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not SOUNDS.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = SOUNDS[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _on_wanted_changed(is_wanted: bool) -> void:
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
