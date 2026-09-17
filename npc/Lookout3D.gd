extends "res://npc/NPC3D.gd"
## The pusher's lookout, posted down the block watching for police. Whistles
## a warning the moment you're wanted so the pusher can clear out.

const WHISTLE := preload("res://assets/sfx/lookout_whistle.wav")

var _whistle: AudioStreamPlayer3D

func _ready() -> void:
	fences_items = false
	super._ready()
	_whistle = AudioStreamPlayer3D.new()
	_whistle.stream = WHISTLE
	_whistle.volume_db = 4.0
	_whistle.unit_size = 8.0
	_whistle.max_distance = 40.0
	_whistle.position = Vector3(0, 1.4, 0)
	add_child(_whistle)
	GameState.wanted_changed.connect(_on_wanted_changed)

func _on_wanted_changed(is_wanted: bool) -> void:
	if is_wanted:
		_whistle.play()
