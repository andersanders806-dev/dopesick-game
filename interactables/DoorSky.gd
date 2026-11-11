extends RefCounted
## What's outside a room's doorway (a store's, the bar's): the street panorama (assets/doors/glass_street_*) on a big
## sphere seen only through the doorway, matching the time of day, and the interior-mapped rooms seen through a
## facade's doorway from the street (interactables/interior_map.gdshader). Shared materials.

const SKY := preload("res://interactables/sky_dome.gdshader")
const ROOM := preload("res://interactables/interior_map.gdshader")
const DAY: Texture2D = preload("res://assets/doors/glass_street_day.png")
const NIGHT: Texture2D = preload("res://assets/doors/glass_street_night.png")

static var _sky: ShaderMaterial = null
static var _rooms := {}
static var _hooked := false

static func sky_material() -> ShaderMaterial:
	if _sky == null:
		_sky = ShaderMaterial.new()
		_sky.shader = SKY
		_sky.set_shader_parameter("street_day", DAY)
		_sky.set_shader_parameter("street_night", NIGHT)
		_hook()
		_refresh()
	return _sky

## The interior-mapped room of `kind` ("store" bright, "dim" bar and workshop) for a doorway `size` across.
static func room_material(kind: String, size: Vector2) -> ShaderMaterial:
	var key := [kind, size]
	if _rooms.has(key):
		return _rooms[key]
	var m := ShaderMaterial.new()
	m.shader = ROOM
	m.set_shader_parameter("wall_tex", load("res://assets/doors/room_wall_%s.png" % kind))
	m.set_shader_parameter("floor_tex", load("res://assets/doors/room_floor_%s.png" % kind))
	m.set_shader_parameter("ceil_tex", load("res://assets/doors/room_ceiling_%s.png" % kind))
	m.set_shader_parameter("back_tex", load("res://assets/doors/room_back_%s.png" % kind))
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("depth", 7.0)
	_rooms[key] = m
	return m

static func _hook() -> void:
	var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	if gs != null and not _hooked:
		_hooked = true
		gs.clock_changed.connect(func(_m): _refresh())

static func _refresh() -> void:
	var gs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameState")
	if _sky != null and gs != null:
		_sky.set_shader_parameter("day_amount", clampf(float(gs.daylight()), 0.0, 1.0))
