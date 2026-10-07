extends Node
## Room changes: fade to black, swap the room, fade back in with a card
## saying where you are and when. Rooms you've been in stay loaded, and the
## room behind a door starts loading in the background as you walk up to
## it, so going through is a fade rather than a multi-second freeze.

const FADE_OUT := 0.25
const FADE_IN := 0.35
const CARD_TIME := 2.5
## How close (m) the player gets to a door before its room starts loading.
const PREFETCH_RANGE := 4.0
const NAMES := {
	"Apartment3D": "Your apartment", "City3D": "The street", "DiveBar3D": "The Dive Bar",
	"Jail3D": "Holding cell", "KartCenter3D": "The kart track", "MusicStore3D": "Tape Deck",
	"Pawn3D": "The pawnshop", "Shelter3D": "St. Jude's shelter", "Backyard3D": "The backyard",
	"StoreConvenience3D": "The corner shop", "StoreElectronics3D": "The electronics store",
	"StoreLiquor3D": "The liquor store", "StorePharmacy3D": "The pharmacy",
	"StoreSupermarket3D": "The supermarket",
}

## Loaded rooms, by path, kept for the session.
var _scenes := {}
## Paths with a background load in flight.
var _loading := {}
var _busy := false
var _scan := 0.0
var _layer: CanvasLayer
var _black: ColorRect
var _card: Label

func _ready() -> void:
	# The fade runs while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_black = ColorRect.new()
	_black.name = "Fade"
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_black)
	_card = Label.new()
	_card.name = "ArrivalCard"
	_card.position = Vector2(24, 132)
	_card.add_theme_font_size_override("font_size", 22)
	_card.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
	_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_card.add_theme_constant_override("outline_size", 6)
	_card.modulate.a = 0.0
	_layer.add_child(_card)

func busy() -> bool:
	return _busy

func cached(path: String) -> bool:
	return _scenes.has(path)

## Starts loading `path` in the background, unless it's loaded already.
func prefetch(path: String) -> void:
	if path == "" or _scenes.has(path) or _loading.has(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_loading[path] = true

func _process(delta: float) -> void:
	for path in _loading.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_scenes[path] = ResourceLoader.load_threaded_get(path)
			_loading.erase(path)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.erase(path)
	_scan -= delta
	if _scan <= 0.0 and not _busy:
		_scan = 0.25
		_prefetch_near_doors()

func _prefetch_near_doors() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for door in get_tree().get_nodes_in_group("doors"):
		if door.global_position.distance_to(player.global_position) < PREFETCH_RANGE:
			prefetch(door.target_scene)

## The scene at `path`, waiting for (or doing) the load if it isn't in yet.
func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var packed: PackedScene = null
		if _loading.has(path):
			_loading.erase(path)
			packed = ResourceLoader.load_threaded_get(path)
		if packed == null:
			packed = load(path)
		_scenes[path] = packed
	return _scenes[path]

## Fades out, changes to the room at `path`, fades in and says where you are.
func go(path: String) -> void:
	if _busy:
		return
	_busy = true
	var tree := get_tree()
	var paused := tree.paused
	tree.paused = true
	_card.modulate.a = 0.0
	await _fade(1.0, FADE_OUT)
	tree.change_scene_to_packed(_scene(path))
	await tree.scene_changed
	# The first frame of a room compiles its shaders; let it pass in black.
	await tree.process_frame
	_card.text = "%s  ·  %s" % [NAMES.get(path.get_file().get_basename(), "").to_upper(), GameState.clock_text()]
	# The room holds still until you can see it: a cop who followed you
	# through the door doesn't get a head start in the dark.
	await _fade(0.0, FADE_IN)
	tree.paused = paused
	_busy = false
	_show_card()

func _fade(to: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", to, time)
	await tw.finished

func _show_card() -> void:
	if _card.text.begins_with(" "):
		return
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.3)
	tw.tween_interval(CARD_TIME)
	tw.tween_property(_card, "modulate:a", 0.0, 0.8)
