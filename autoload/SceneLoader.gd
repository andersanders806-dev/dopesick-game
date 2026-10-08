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

## Loaded rooms (and the street's facade kits), by path, kept for the session.
var _scenes := {}
## Paths whose background load failed: not asked for again.
var _failed := {}
## Paths waiting their turn to load in the background.
var _queue: Array = []
## The path with a background load in flight (one at most).
var _loading := {}
var _busy := false
var _warmed := false
## [path, spawn] asked for while a change was running.
var _next: Array = []
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
## One at a time, through a queue: the street has a door every few metres,
## and nine rooms loading at once on arrival fought the game for the CPU
## (12 ms of physics a frame for the first seconds, instead of 2). `soon`
## (the door you're walking up to) goes to the front.
func prefetch(path: String, soon := false) -> void:
	if path == "" or _scenes.has(path) or _loading.has(path) or _failed.has(path) or not ResourceLoader.exists(path):
		return
	if soon:
		_queue.erase(path)
		_queue.push_front(path)
	elif not _queue.has(path):
		_queue.append(path)
	_start_next()

func _start_next() -> void:
	while _loading.is_empty() and not _queue.is_empty():
		var path: String = _queue.pop_front()
		if _scenes.has(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading[path] = true
		else:
			_failed[path] = true

func _process(delta: float) -> void:
	for path in _loading.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_scenes[path] = ResourceLoader.load_threaded_get(path)
			_loading.erase(path)
		elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.erase(path)
			_failed[path] = true
	_start_next()
	_scan -= delta
	if _scan <= 0.0 and not _busy:
		_scan = 0.25
		_prefetch_near_doors()

func _prefetch_near_doors() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# The street is where every door leads: start on it, and on the facade
	# kits it builds itself from, from the first room you're in.
	if not _warmed:
		_warmed = true
		prefetch("res://world/City3D.tscn")
		for path in preload("res://world/Facades.gd").WARM:
			prefetch(path)
	for door in get_tree().get_nodes_in_group("doors"):
		if door.global_position.distance_to(player.global_position) < PREFETCH_RANGE:
			prefetch(door.target_scene, true)

## The scene at `path`, waiting for (or doing) the load if it isn't in yet;
## null if it won't load.
func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var packed: PackedScene = null
		_queue.erase(path)
		if _loading.has(path):
			_loading.erase(path)
			packed = ResourceLoader.load_threaded_get(path) as PackedScene
		if packed == null and ResourceLoader.exists(path):
			packed = load(path) as PackedScene
		if packed == null:
			return null
		_scenes[path] = packed
	return _scenes[path]

## Fades out, changes to the room at `path` (arriving at the marker named
## `spawn`), fades in and says where you are. Asked again mid-change (a
## bust as you go through a door), the later one goes next: the cell wins.
## Under a cutscene the room changes unseen, with no fade or card on top.
func go(path: String, spawn := "") -> void:
	if _busy:
		_next = [path, spawn]
		return
	_busy = true
	var tree := get_tree()
	var paused := tree.paused
	var hidden := Cutscene.is_playing()
	tree.paused = true
	_card.modulate.a = 0.0
	if not hidden:
		await _fade(1.0, FADE_OUT)
	var packed := _scene(path)
	if packed == null:
		push_error("SceneLoader: can't load %s" % path)
		_black.color.a = 0.0
		tree.paused = paused
		_busy = false
		_go_next()
		return
	if spawn != "":
		GameState.pending_spawn = spawn
	tree.change_scene_to_packed(packed)
	await tree.scene_changed
	# The first frame of a room compiles its shaders; let it pass in black.
	await tree.process_frame
	_card.text = "%s  ·  %s" % [NAMES.get(path.get_file().get_basename(), "").to_upper(), GameState.clock_text()]
	# The room holds still until you can see it: a cop who followed you
	# through the door doesn't get a head start in the dark.
	if not hidden:
		await _fade(0.0, FADE_IN)
	tree.paused = paused
	_busy = false
	if _next.is_empty() and not hidden:
		_show_card()
	_go_next()

func _go_next() -> void:
	if _next.is_empty():
		return
	var next: Array = _next
	_next = []
	go(next[0], next[1])

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
