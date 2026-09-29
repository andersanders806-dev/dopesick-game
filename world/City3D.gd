extends "res://world/WorldRoot3D.gd"

const CAR_COLORS := [
	Color(0.55, 0.08, 0.07),
	Color(0.12, 0.2, 0.42),
	Color(0.18, 0.3, 0.16),
	Color(0.62, 0.5, 0.2),
	Color(0.75, 0.75, 0.72),
	Color(0.1, 0.1, 0.1),
]

## Night values are what build_rooms_3d.gd bakes into the scene; day values
## are an overcast afternoon, not a postcard -- the block should still look
## tired in daylight.
const DAY_SKY := Color(0.42, 0.47, 0.52)
const DAY_AMBIENT := Color(0.62, 0.66, 0.72)
const DAY_AMBIENT_ENERGY := 0.6
const SUN_COLOR := Color(1.0, 0.93, 0.8)
const SUN_ENERGY := 1.0
const DAY_FOG_LIGHT := Color(0.5, 0.53, 0.58)

const CollectorScene := preload("res://npc/Collector3D.tscn")
## He comes up the block from the dark east end, where the pusher works, a
## few seconds after you step out -- long enough to see him coming.
const COLLECTOR_ENTRY := Vector3(27.5, 0, 1.0)
const COLLECTOR_DELAY := 3.0
var _collector_timer: float = COLLECTOR_DELAY

const PedestrianScript := preload("res://npc/Pedestrian3D.gd")
const GuardScene := preload("res://npc/Guard3D.tscn")
const PatrolScript := preload("res://npc/PatrolCop3D.gd")
## Two sidewalk lanes, one each way. Busier by day.
const PEDESTRIAN_LANES := [-3.1, -2.2]
const PEDESTRIANS_NIGHT := 1
const PEDESTRIANS_DAY := 5
const PEDESTRIAN_SPAWN_GAP := Vector2(3.0, 8.0)
const STREET_END_X := 29.5
## The beat cop walks out of the station; after a chase he's back on the
## block a while later.
const PATROL_START := Vector3(-24.5, 0, -1.3)
const PATROL_RETURN_DELAY := 25.0
var _pedestrian_timer: float = 0.0
var _patrol_timer: float = 0.0

var _env: Environment
@onready var _sky_light: DirectionalLight3D = $Moon

var _night := {}
## [light, night energy] for everything that only matters after dark:
## streetlights and the glow under each shop sign.
var _night_lights: Array = []
var _street_lamp_heads: Array[MeshInstance3D] = []

func _ready() -> void:
	super._ready()
	# The Environment is a sub-resource of the cached PackedScene; blending a
	# shared copy would leak today's daylight into the next visit's "night"
	# baseline.
	var world_env := $WorldEnvironment as WorldEnvironment
	_env = world_env.environment.duplicate()
	world_env.environment = _env
	_night = {
		"sky": _env.background_color,
		"ambient": _env.ambient_light_color,
		"ambient_energy": _env.ambient_light_energy,
		"fog_light": _env.fog_light_color,
		"fog_density": _env.fog_density,
		"vol_density": _env.volumetric_fog_density,
		"moon_color": _sky_light.light_color,
		"moon_energy": _sky_light.light_energy,
	}
	for child in get_children():
		if child.name.begins_with("Streetlight"):
			var lamp := child.get_node_or_null("Light") as Light3D
			if lamp:
				_night_lights.append([lamp, lamp.light_energy])
			var head := child.get_node_or_null("Head") as MeshInstance3D
			if head:
				_street_lamp_heads.append(head)
		elif child.name.ends_with("SignGlow") and child is Light3D:
			_night_lights.append([child, child.light_energy])
	GameState.clock_changed.connect(_on_clock_changed)
	GameState.weather_changed.connect(_on_weather_changed)
	_apply_daylight()
	var life: Node3D = preload("res://world/StreetLife.gd").new()
	life.name = "StreetLife"
	for n in ["Manhole1", "Manhole2"]:
		var m := get_node_or_null(n) as Node3D
		if m:
			life.steam_points.append(m.position + Vector3(0, 0.1, 0))
	add_child(life)
	var dressing: Node3D = preload("res://world/StreetDressing.gd").new()
	dressing.name = "StreetDressing"
	add_child(dressing)
	var scenes: Node3D = preload("res://world/StreetScenes.gd").new()
	scenes.name = "StreetScenes"
	add_child(scenes)
	# Start with the street already populated rather than empty.
	for i in _pedestrian_target():
		_spawn_pedestrian(randf_range(-STREET_END_X + 3.0, STREET_END_X - 3.0))
	if not GameState.wanted:
		_spawn_patrol(Vector3(randf_range(-22.0, 22.0), 0, PATROL_START.z))
	for body in get_tree().get_nodes_in_group("car_bodies"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CAR_COLORS.pick_random()
		mat.metallic = 0.4
		mat.roughness = 0.35
		(body as MeshInstance3D).material_override = mat

func _process(delta: float) -> void:
	super._process(delta)
	_update_collector(delta)
	_update_pedestrians(delta)
	_update_patrol(delta)

func _pedestrian_target() -> int:
	return int(round(lerpf(PEDESTRIANS_NIGHT, PEDESTRIANS_DAY, GameState.daylight())))

func _update_pedestrians(delta: float) -> void:
	_pedestrian_timer -= delta
	if _pedestrian_timer > 0.0:
		return
	_pedestrian_timer = randf_range(PEDESTRIAN_SPAWN_GAP.x, PEDESTRIAN_SPAWN_GAP.y)
	if get_tree().get_nodes_in_group("pedestrians").size() < _pedestrian_target():
		_spawn_pedestrian()

## `at_x` NAN means walk in from whichever end the lane starts at.
func _spawn_pedestrian(at_x := NAN) -> void:
	var walker: Area3D = PedestrianScript.new()
	var lane := randi() % PEDESTRIAN_LANES.size()
	walker.direction = 1.0 if lane == 0 else -1.0
	walker.lane_z = PEDESTRIAN_LANES[lane]
	walker.end_x = STREET_END_X
	walker.speed = randf_range(1.1, 1.5)
	walker.look_index = randi()
	add_child(walker)
	var x: float = at_x if not is_nan(at_x) else -walker.direction * STREET_END_X
	walker.global_position = Vector3(x, 0, walker.lane_z)

func _spawn_patrol(pos: Vector3) -> void:
	var cop := GuardScene.instantiate()
	cop.set_script(PatrolScript)
	cop.name = "PatrolCop"
	cop.set("role", "police")
	cop.set("vision_range", 7.5)
	cop.set("vision_angle_deg", 70.0)
	cop.set("sweep_arc_deg", 80.0)
	cop.set("sweep_speed", 0.5)
	cop.set("talk_name", "Officer")
	cop.set("talk_lines", "Move along.\nYou live around here?\nDon't let me see you by that alley again.\nEvening.")
	add_child(cop)
	cop.global_position = pos
	cop.heading = 1.0 if randf() < 0.5 else -1.0
	cop.spotted_theft.connect(_on_patrol_spotted.bind(cop))

## The beat cop saw enough: he calls it in and comes after you himself.
func _on_patrol_spotted(cop: Node3D) -> void:
	if GameState.wanted or GameState.in_custody:
		return
	var at := cop.global_position
	cop.queue_free()
	var police := PoliceScene.instantiate()
	add_child(police)
	police.global_position = at
	_patrol_timer = PATROL_RETURN_DELAY

func _update_patrol(delta: float) -> void:
	if GameState.wanted or get_tree().get_first_node_in_group("patrol") != null:
		return
	_patrol_timer -= delta
	if _patrol_timer <= 0.0:
		_spawn_patrol(PATROL_START)

## Sends the collector once a front is overdue and he isn't already out.
func _update_collector(delta: float) -> void:
	if not GameState.debt_overdue() or GameState.in_custody or get_tree().get_first_node_in_group("collector"):
		_collector_timer = COLLECTOR_DELAY
		return
	_collector_timer -= delta
	if _collector_timer > 0.0:
		return
	var collector := CollectorScene.instantiate()
	add_child(collector)
	collector.global_position = COLLECTOR_ENTRY

func _on_weather_changed(_raining: bool) -> void:
	_apply_daylight()

func _on_clock_changed(_minute: int) -> void:
	_apply_daylight()

## Blends the scene between its baked night look and daylight as the clock
## moves through dawn and dusk.
func _apply_daylight() -> void:
	var d := GameState.daylight()
	# Rain: an overcast, darker day.
	if GameState.raining:
		d *= 0.55
	_env.background_color = (_night["sky"] as Color).lerp(DAY_SKY, d)
	_env.ambient_light_color = (_night["ambient"] as Color).lerp(DAY_AMBIENT, d)
	_env.ambient_light_energy = lerpf(_night["ambient_energy"], DAY_AMBIENT_ENERGY, d)
	_env.fog_light_color = (_night["fog_light"] as Color).lerp(DAY_FOG_LIGHT, d)
	_env.fog_density = lerpf(_night["fog_density"], 0.004, d)
	_env.volumetric_fog_density = lerpf(_night["vol_density"], 0.002, d)
	_sky_light.light_color = (_night["moon_color"] as Color).lerp(SUN_COLOR, d)
	_sky_light.light_energy = lerpf(_night["moon_energy"], SUN_ENERGY, d)
	# Streetlights are on a photocell: fully on until well into dawn, and
	# back on before dusk is over.
	var lamps_on := 1.0 - smoothstep(0.35, 0.75, d)
	for entry in _night_lights:
		(entry[0] as Light3D).light_energy = entry[1] * lamps_on
		(entry[0] as Light3D).visible = lamps_on > 0.01
	for head in _street_lamp_heads:
		var mat := head.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0 * lamps_on
