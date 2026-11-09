extends Node
## The street heard from inside. While you're in a shop on the street (or in the
## Dive Bar) the street's recording plays on its own bus ("Street", a low-pass,
## autoload/SFX.gd) behind the room's: dull and quiet through a shut door,
## flooding in as the nearest door opens and going dull again as it closes.
## The cutoff and level follow HingedDoor3D.openness() of the door nearest you.
##
## world/PlaceAmbience.gd makes and frees it (indoors(), apply()).

const CITY := preload("res://assets/sfx/places/city.ogg")
## Cutoff and level with the door shut, and open.
const SHUT := Vector2(480.0, -15.0)
const OPEN := Vector2(15000.0, -1.5)
## How fast it follows the door (per second).
const FOLLOW := 9.0
## dB lost per metre of the room between you and the door.
const DEPTH_DB := 0.55

var player: AudioStreamPlayer
var level := 0.0
var _bus := -1
var _lpf: AudioEffectLowPassFilter

static func start(room: Node, at := 0.0, street_db := -4.0) -> Node:
	var existing := room.get_node_or_null("StreetBleed")
	if existing != null:
		return existing
	var node: Node = (load("res://world/StreetBleed.gd") as GDScript).new()
	node.name = "StreetBleed"
	room.add_child(node)
	node.begin(at, street_db)
	return node

## Where the street's loop is, for whoever takes it up outside.
func position_seconds() -> float:
	return player.get_playback_position() if player != null and player.playing else 0.0

func begin(at: float, street_db: float) -> void:
	_street_trim = street_db
	_bus = AudioServer.get_bus_index("Street")
	if _bus >= 0:
		for k in AudioServer.get_bus_effect_count(_bus):
			if AudioServer.get_bus_effect(_bus, k) is AudioEffectLowPassFilter:
				_lpf = AudioServer.get_bus_effect(_bus, k)
	var stream: AudioStream = CITY.duplicate()
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	player = AudioStreamPlayer.new()
	player.name = "Street"
	player.stream = stream
	player.bus = "Street" if _bus >= 0 else "Ambience"
	player.volume_db = SHUT.y + street_db + 4.0
	add_child(player)
	level = 0.0
	_apply(0.0, 0.0)
	player.play(at)

func _process(delta: float) -> void:
	if player == null:
		return
	var who := get_tree().get_first_node_in_group("player") as Node3D
	var best := 0.0
	var dist := 0.0
	if who != null:
		var near := 1e9
		for d in get_tree().get_nodes_in_group("hinged_doors"):
			var door := d as Node3D
			if door == null or not door.is_inside_tree() or (door.get("place") == "" and door.get("arrival_id") == ""):
				continue
			var dd := door.global_position.distance_to(who.global_position)
			if dd < near:
				near = dd
				best = door.openness()
				dist = dd
	level = lerpf(level, best, 1.0 - exp(-FOLLOW * delta))
	_apply(level, dist)

func _apply(o: float, dist: float) -> void:
	var k := o * o
	if _lpf != null:
		# Exponential, so the sweep sounds even.
		_lpf.cutoff_hz = SHUT.x * pow(OPEN.x / SHUT.x, k)
	var depth := maxf(0.0, dist - 1.5) * DEPTH_DB * k
	player.volume_db = lerpf(SHUT.y, OPEN.y, k) - depth + 4.0 + _street_trim

var _street_trim := -4.0
