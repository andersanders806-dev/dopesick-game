extends "res://world/WorldRoot3D.gd"

const CarPaint := preload("res://world/CarPaint.gd")
const PlaceAmbience := preload("res://world/PlaceAmbience.gd")

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
## The passers-by's walks: two loops round the block's sidewalks, one each
## way, chained so nobody pops out of thin air -- they come out of a door
## (`doors`: the points where a stretch starts at one) and go in at another.
## The first loop walks Main's shops eastbound at z -3.1 and the second
## westbound at -2.2, where the two lanes always were; both step round the
## newsstands on the building side. Task 4's schedules give people real
## places to go; these are the passers-by.
const WALKS := [
	{"points": [
		Vector3(-66.6, 0, -2.6), Vector3(-53.0, 0, -2.6), Vector3(-29.6, 0, -2.6), Vector3(-29.0, 0, -3.9),
		Vector3(-27.2, 0, -3.9), Vector3(-26.5, 0, -3.1), Vector3(3.5, 0, -3.1), Vector3(25.9, 0, -3.1),
		Vector3(26.6, 0, -3.9), Vector3(28.6, 0, -3.9), Vector3(29.3, 0, -2.6), Vector3(47.0, 0, -2.6),
		Vector3(66.6, 0, -2.6), Vector3(66.6, 0, -47.8), Vector3(67.5, 0, -48.4), Vector3(67.5, 0, -51.6),
		Vector3(66.6, 0, -52.2), Vector3(66.6, 0, -85.6), Vector3(53.6, 0, -85.6), Vector3(53.0, 0, -87.0),
		Vector3(51.0, 0, -87.0), Vector3(50.4, 0, -85.6), Vector3(5.6, 0, -85.6), Vector3(5.0, 0, -87.0),
		Vector3(3.0, 0, -87.0), Vector3(2.4, 0, -85.6), Vector3(-7.5, 0, -85.6), Vector3(-42.4, 0, -85.6),
		Vector3(-43.0, 0, -87.0), Vector3(-45.0, 0, -87.0), Vector3(-45.6, 0, -85.6), Vector3(-66.6, 0, -85.6),
		Vector3(-66.6, 0, -52.2), Vector3(-67.5, 0, -51.6), Vector3(-67.5, 0, -48.4), Vector3(-66.6, 0, -47.8),
		Vector3(-66.6, 0, -24.0)],
		"doors": [1, 6, 11, 26, 36]},
	{"points": [
		Vector3(76.2, 0, -2.35), Vector3(29.2, 0, -2.35), Vector3(28.6, 0, -3.9), Vector3(26.8, 0, -3.9),
		Vector3(26.2, 0, -2.2), Vector3(17.5, 0, -2.2), Vector3(-26.2, 0, -2.2), Vector3(-27.2, 0, -3.9),
		Vector3(-29.0, 0, -3.9), Vector3(-29.6, 0, -2.35), Vector3(-61.0, 0, -2.35), Vector3(-76.2, 0, -2.35),
		Vector3(-76.2, 0, -45.6), Vector3(-74.9, 0, -46.2), Vector3(-74.9, 0, -49.8), Vector3(-76.2, 0, -50.4),
		Vector3(-76.2, 0, -57.0), Vector3(-76.2, 0, -95.0), Vector3(-23.4, 0, -95.0), Vector3(-22.8, 0, -96.2),
		Vector3(-21.2, 0, -96.2), Vector3(-20.6, 0, -95.0), Vector3(-10.0, 0, -95.0), Vector3(10.2, 0, -95.0),
		Vector3(10.6, 0, -96.2), Vector3(12.4, 0, -96.2), Vector3(12.8, 0, -95.0), Vector3(45.6, 0, -95.0),
		Vector3(46.2, 0, -96.2), Vector3(47.8, 0, -96.2), Vector3(48.4, 0, -95.0), Vector3(76.2, 0, -95.0),
		Vector3(76.2, 0, -50.4), Vector3(74.9, 0, -49.8), Vector3(74.9, 0, -46.2), Vector3(76.2, 0, -45.6),
		Vector3(76.2, 0, -33.0)],
		"doors": [5, 10, 16, 22, 36]},
]
## The Main Street stretch of each walk where the first people are put,
## out where you come out of a door.
const MAIN_SEGMENT := [5, 5]
## Now and then someone goes in at a door even when the street isn't busy.
const LEAVE_CHANCE := 0.2
## Task 4 replaces the Task 1 values (5 by day, 1 at night, a new one every
## 3-8 s): they come out of a pool made on arrival, so more of them cost
## nothing while you walk.
const PEDESTRIANS_NIGHT := 2
const PEDESTRIANS_DAY := 7
const PEDESTRIAN_SPAWN_GAP := Vector2(2.5, 6.0)
## The beat cop walks out of the station; after a chase he's back on the
## block a while later.
const PATROL_START := Vector3(-24.5, 0, -1.3)
const PATROL_RETURN_DELAY := 25.0
var _pedestrian_timer: float = 0.0
var _patrol_timer: float = 0.0
## Passers-by: one body per look, made on arrival (behind the fade) and
## parked out of the way between walks. Nothing is instantiated while you
## walk the block.
var _pedestrian_pool: Array[Area3D] = []
## The scheduled people (npc/ScheduledPerson.gd), by name.
var _people: Node3D

var _env: Environment
@onready var _sky_light: DirectionalLight3D = $Moon

var _night := {}
## [light, night energy] for everything that only matters after dark:
## streetlights and the glow under each shop sign.
var _night_lights: Array = []
## world/BlockCells.gd: [light, energy] above also carries the light's cell
## and how far on its cell's waking has brought it (0..1, a quick fade:
## lamp pools don't pop on or off at the cell's edge).
var _cells: Node
const LIGHT_WAKE_SECONDS := 0.5
var _lights_fading := false
var _street_lamp_heads: Array[MeshInstance3D] = []

const VendingScript := preload("res://world/VendingMachine3D.gd")
const MailboxScript := preload("res://world/Mailbox3D.gd")
const PostmanScript := preload("res://npc/Postman3D.gd")
## Your mailbox, just east of the apartment door.
const MAILBOX_POS := Vector3(-16.1, 0.0, -3.7)
## He sets off this long before the package is due.
const POSTMAN_LEAD := 20.0

## A Silk Lane order coming today: the postman walks it to your mailbox
## while you're out here; whenever it's due, it's posted, seen or not.
func _check_post() -> void:
	if zombie_mode:
		return
	var p: Dictionary = GameState.parcel
	if p.is_empty() or not p.has("arrive_at") or p.get("posted", false) or p.get("fate", "") != "ok":
		return
	var now := GameState.now_minutes()
	var due := float(p["arrive_at"])
	if now >= due:
		p["posted"] = true
		return
	if now >= due - POSTMAN_LEAD and get_tree().get_first_node_in_group("postman") == null:
		var man := CollectorScene.instantiate()
		man.set_script(PostmanScript)
		man.name = "Postman"
		man.target = MAILBOX_POS + Vector3(0, 0, 0.7)
		man.exit = Vector3(26.0, 0.0, -2.6)
		add_child(man)
		man.global_position = Vector3(-26.0, 0.0, -2.6)
		man.reset_physics_interpolation()

## The block's navmesh comes baked with the scene (build_rooms_3d.gd: a
## runtime bake of the whole block was ~1-1.8 s behind every door); only
## bake here if it somehow didn't.
func _bake_navigation() -> void:
	var nav_region := get_node_or_null("NavRegion") as NavigationRegion3D
	if nav_region and nav_region.navigation_mesh and nav_region.navigation_mesh.get_polygon_count() > 0:
		nav_bake_ms = 0
		return
	super._bake_navigation()

## The block's trash bags and parked cars can be searched once a day each
## (autoload/Crafting.gd): rags, scrap, tape, a little food or change.
func _add_scavenge_spots() -> void:
	for n in ["Trash0", "Trash1", "Trash2", "Trash3", "BarTrash0", "BarTrash1", "CarA", "CarB", "CarC"]:
		var target := find_child(n, true, false) as Node3D
		if target == null:
			continue
		var car: bool = n.begins_with("Car")
		var zone := Area3D.new()
		zone.name = "Scavenge" + n
		zone.set_meta("spot", n)
		zone.set_meta("car", car)
		zone.set_meta("prompt", "Try the car door" if car else "Search the trash")
		zone.add_to_group("scavenge")
		zone.collision_layer = 4
		zone.collision_mask = 0
		zone.monitoring = false
		zone.set_script(InteractableScript)
		add_child(zone)
		zone.global_position = Vector3(target.global_position.x, 0.0, target.global_position.z + (-1.4 if car else 0.6))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.4 if car else 1.0, 1.4, 1.0)
		shape.shape = box
		shape.position = Vector3(0, 0.7, 0)
		zone.add_child(shape)
		zone.interacted.connect(_on_scavenge)

func _on_scavenge(zone: Area3D, player: Node) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	var line: String = Crafting.search(zone.get_meta("spot"), zone.get_meta("car"))
	SFX.play("steal", -6.0, 0.8)
	if hud:
		player.dialogue_active = true
		hud.show_dialogue("", line)
## Against the wall between the police station and the apartment door.
const VENDING_POS := Vector3(-19.25, 0.0, -3.95)

## How long _ready took (load behind the door's fade; the smoke test reads it).
var ready_ms := 0
## Of which the pool of passers-by and the scheduled people (the smoke test prints it).
var people_ms := 0

## Dead Block (autoload/ZombieMode.gd): the same block with the story taken
## out -- no shops' doors, no people, no traffic, no clock -- and
## world/ZombieBlock.gd laid over it. Read once, on arrival.
var zombie_mode := false
const ZombieBlockScript := preload("res://world/ZombieBlock.gd")

## You walked into / out of one of the walk-in shops on Main Street
## (world/WalkInShop.gd), by GameState place id.
signal entered_shop(place: String)
signal left_shop(place: String)

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	GameState.indoors = ""
	entered_shop.connect(_on_shop_changed.bind(true))
	left_shop.connect(_on_shop_changed.bind(false))
	zombie_mode = GameState.mode == "zombies"
	# The navmesh was baked round these two too (CityKit.bake_navigation);
	# they're the story's, so the zombie block goes without.
	if not zombie_mode:
		var vending := StaticBody3D.new()
		vending.set_script(VendingScript)
		add_child(vending)
		vending.position = VENDING_POS
		var mailbox := StaticBody3D.new()
		mailbox.set_script(MailboxScript)
		add_child(mailbox)
		mailbox.position = MAILBOX_POS
	super._ready()
	if not zombie_mode:
		_add_scavenge_spots()
		_check_post()
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
	# Every street's lamps and sign glows, whichever cell they're in.
	for lamp_post in find_children("Streetlight*", "StaticBody3D", true, false):
		var lamp := lamp_post.get_node_or_null("Light") as Light3D
		if lamp:
			_night_lights.append([lamp, lamp.light_energy])
		var head := lamp_post.get_node_or_null("Head") as MeshInstance3D
		if head:
			_street_lamp_heads.append(head)
	for glow in find_children("*SignGlow", "Light3D", true, false):
		_night_lights.append([glow, glow.light_energy])
	# The block's other after-dark lights: back doors, under the overpass,
	# the billboard, the projects' entrance, the bus shelter's ad.
	for light in get_tree().get_nodes_in_group("night_lights"):
		if is_ancestor_of(light) and not light.name.ends_with("SignGlow"):
			_night_lights.append([light, light.light_energy])
	# Which cell each light's in: a sleeping cell's stay off whatever the
	# hour (BlockCells hid them), and come back to the hour when it wakes.
	_cells = get_node_or_null("BlockCells")
	for entry in _night_lights:
		entry.append(_cells.cell_of(entry[0]) if _cells else null)
		entry.append(1.0)
	if _cells:
		_cells.cell_changed.connect(_on_cell_changed)
	GameState.clock_changed.connect(_on_clock_changed)
	GameState.weather_changed.connect(_on_weather_changed)
	_apply_daylight()
	var life: Node3D = preload("res://world/StreetLife.gd").new()
	life.name = "StreetLife"
	life.traffic = not zombie_mode
	for n in ["Manhole1", "Manhole2"]:
		var m := find_child(n, true, false) as Node3D
		if m:
			life.steam_points.append(m.global_position + Vector3(0, 0.1, 0))
	add_child(life)
	if not zombie_mode:
		var atmosphere: Node3D = preload("res://world/Atmosphere.gd").new()
		atmosphere.name = "Atmosphere"
		add_child(atmosphere)
	# The buildings' faces and the street's wear are the arena, in either mode.
	var facades: Node3D = preload("res://world/Facades.gd").new()
	facades.name = "Facades"
	add_child(facades)
	var dressing: Node3D = preload("res://world/StreetDressing.gd").new()
	dressing.name = "StreetDressing"
	add_child(dressing)
	if zombie_mode:
		_paint_parked_cars()
		var block := ZombieBlockScript.new()
		block.name = "ZombieBlock"
		add_child(block)
		block.setup(self)
		ready_ms = Time.get_ticks_msec() - t0
		return
	var scenes: Node3D = preload("res://world/StreetScenes.gd").new()
	scenes.name = "StreetScenes"
	add_child(scenes)
	_add_hide_spots()
	var temptation: Node3D = preload("res://world/Temptation.gd").new()
	temptation.name = "Temptation"
	add_child(temptation)
	var alley: Node3D = preload("res://world/AlleyOverdose.gd").new()
	alley.name = "AlleyOverdose"
	add_child(alley)
	var booster: Node3D = preload("res://world/Booster.gd").new()
	booster.name = "Booster"
	add_child(booster)
	var t_people := Time.get_ticks_msec()
	_make_pedestrian_pool()
	_spawn_scheduled_people()
	people_ms = Time.get_ticks_msec() - t_people
	# Start with the street already populated rather than empty: the first
	# two on Main Street's shops, where you come out, the rest anywhere.
	for i in _pedestrian_target():
		var walk := i % WALKS.size()
		var seg: int = MAIN_SEGMENT[walk] if i < 2 else randi() % WALKS[walk]["points"].size()
		_spawn_pedestrian(walk, seg, randf_range(0.05, 0.95))
	if not GameState.wanted:
		_spawn_patrol(_patrol_start_point())
	_paint_parked_cars()
	ready_ms = Time.get_ticks_msec() - t0

## A walk-in shop is indoors: no cold, muffled rain, its own floor and
## its own recording under the street's.
func _on_shop_changed(place: String, entered: bool) -> void:
	GameState.indoors = place if entered else ""
	SFX.indoors_changed()
	PlaceAmbience.indoors(self, place if entered else "")

func _exit_tree() -> void:
	GameState.indoors = ""

## Every parked car in an old, dull paint of its own (world/CarPaint.gd, the
## traffic's too). The builder can't do it: changes to nodes inside an
## instanced model don't save with the scene, so it's done here.
func _paint_parked_cars() -> void:
	for car in find_children("Car*", "StaticBody3D", true, false) + find_children("PoliceCruiser", "StaticBody3D", true, false):
		var model := car.get_node_or_null("Model") as Node3D
		if model != null and String(model.scene_file_path).begins_with("res://assets/cars/"):
			CarPaint.dress(model, CarPaint.paint_index(car.name), true, CarPaint.PARKED_REACH)

## Places on the block to crouch out of sight when the police are after
## you: in the mouth of the alley by the pusher's corner, behind a stack of
## pallets, and at the far end of the dumpster. E to crouch, move to get
## up. A cop who saw you go in will look there (npc/Police3D.gd), so break
## line of sight first.
const HIDE_SPOTS := [
	{"name": "AlleyHide", "pos": Vector3(14.0, 0, -4.05), "cover": "pallets"},
	{"name": "DumpsterHide", "pos": Vector3(22.6, 0, -3.95), "cover": "bags"},
]
const InteractableScript := preload("res://interactables/Interactable3D.gd")

func _add_hide_spots() -> void:
	for spec in HIDE_SPOTS:
		var zone := Area3D.new()
		zone.name = spec["name"]
		zone.collision_layer = 4
		zone.collision_mask = 0
		zone.monitoring = false
		zone.set_script(InteractableScript)
		add_child(zone)
		zone.global_position = spec["pos"]
		zone.add_to_group("hide_spots")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 1.2, 1.0)
		shape.shape = box
		shape.position = Vector3(0, 0.6, 0)
		zone.add_child(shape)
		# Cover between the spot and the street, visual only.
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.42, 0.32, 0.2)
		wood.roughness = 0.9
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.05, 0.05, 0.06)
		black.roughness = 0.4
		for i in 3:
			var piece := MeshInstance3D.new()
			var bm := BoxMesh.new()
			if spec["cover"] == "pallets":
				bm.size = Vector3(1.1, 0.14, 0.9)
				piece.material_override = wood
				zone.add_child(piece)
				piece.position = Vector3(0.0, 0.08 + i * 0.16, 0.55)
				piece.rotation.y = i * 0.12
			else:
				bm.size = Vector3(0.5, 0.45, 0.4)
				piece.material_override = black
				zone.add_child(piece)
				piece.position = Vector3(-0.35 + i * 0.35, 0.22 + (0.25 if i == 1 else 0.0), 0.5)
				piece.rotation.y = i * 0.7
			piece.mesh = bm
		zone.interacted.connect(_on_hide_spot)

func _on_hide_spot(_zone: Area3D, player: Node) -> void:
	player.set_hiding(not player.hiding)
	if player.hiding:
		SFX.play("steal", -8.0, 0.8)

func _process(delta: float) -> void:
	super._process(delta)
	if _lights_fading:
		_fade_lights(delta)
	if zombie_mode:
		return
	if not people_pending.is_empty():
		_build_next_person()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.3
		_refresh_sleepers()
	_update_collector(delta)
	_update_pedestrians(delta)
	_update_patrol(delta)

func _pedestrian_target() -> int:
	return int(round(lerpf(PEDESTRIANS_NIGHT, PEDESTRIANS_DAY, GameState.daylight()) * Headlines.pedestrian_mult()))

func _update_pedestrians(delta: float) -> void:
	_pedestrian_timer -= delta
	if _pedestrian_timer > 0.0:
		return
	_pedestrian_timer = randf_range(PEDESTRIAN_SPAWN_GAP.x, PEDESTRIAN_SPAWN_GAP.y)
	if get_tree().get_nodes_in_group("pedestrians").size() < _pedestrian_target():
		_spawn_pedestrian()

## Every passerby look, made once on arrival and kept: a pool of
## PASSERSBY.size() walkers parked under the street. A walker made mid-walk
## cost 42 ms the first time (materials and skins set up) and a few ms every
## time after; taking one from the pool costs nothing. Behind SceneLoader's
## fade anyway.
var looks_warmed := 0
const CharacterCast := preload("res://npc/CharacterCast.gd")
const CharacterLook := preload("res://npc/CharacterLook.gd")
const PARKED_AT := Vector3(0.0, -40.0, 0.0)
const ScheduledPersonScript := preload("res://npc/ScheduledPerson.gd")

func _make_pedestrian_pool() -> void:
	for i in CharacterCast.PASSERSBY.size():
		var walker: Area3D = PedestrianScript.new()
		walker.points = WALKS[0]["points"]
		walker.look_index = i
		walker.parkable = true
		walker.left_street.connect(_on_walker_left.bind(walker))
		add_child(walker)
		walker.park()
		_pedestrian_pool.append(walker)
		looks_warmed += 1

## Someone on walk `walk`, `at` (0..1) of the way along segment `seg`; by
## default coming out of one of its doors.
func _spawn_pedestrian(walk := -1, seg := -1, at := 0.0) -> void:
	if walk < 0:
		walk = randi() % WALKS.size()
	if seg < 0:
		seg = WALKS[walk]["doors"].pick_random()
	if _pedestrian_pool.is_empty():
		return
	var walker: Area3D = _pedestrian_pool.pop_at(randi() % _pedestrian_pool.size())
	walker.points = WALKS[walk]["points"]
	walker.doors = WALKS[walk]["doors"]
	walker.leave_here = _walker_leaves
	walker.speed = randf_range(1.1, 1.5)
	walker.unpark()
	walker.place_at(seg, at)

func _on_walker_left(walker: Area3D) -> void:
	walker.park()
	_pedestrian_pool.append(walker)

func _walker_leaves() -> bool:
	return get_tree().get_nodes_in_group("pedestrians").size() > _pedestrian_target() or randf() < LEAVE_CHANCE

## Where the beat cop is on his loop at this hour.
func _patrol_start_point() -> Vector3:
	return Schedules.patrol_point(GameState.now_minutes(), 1)["pos"]

## Everyone in autoload/Schedules.gd who is out on the block. They are
## made one a frame in the first frames on the street (_build_next_person),
## from character scenes the background loader already has: all twelve in
## _ready was ~2 s of the first visit, and a model that isn't in yet is
## waited for, never loaded on the spot. Each is put where its schedule has
## it as it's made, so nobody walks in from the spawn.
var people_pending: Array = []
var _refresh_t := 0.0
var _people_i := 0

func _spawn_scheduled_people() -> void:
	_people = Node3D.new()
	_people.name = "People"
	add_child(_people)
	for id in Schedules.walkers():
		if Schedules.position_at(id, 0) != Vector3.INF:
			people_pending.append(id)
			# Their bodies (the boot prefetch leaves the regulars out) are
			# asked for now, on arrival behind the fade, and built from as
			# they come in; nothing is requested once the player walks.
			var model := CharacterCast.model_for(Schedules.role_of(id))
			if not ResourceLoader.has_cached(model) and ResourceLoader.load_threaded_get_status(model) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(model)

## Called by SceneLoader behind the black before it fades in: makes the people
## whose bodies are in (a few a frame); true once everybody is made. A cap on
## the wait leaves the stragglers to _process.
func finish_arrival() -> bool:
	if zombie_mode:
		return true
	for i in 3:
		if not people_pending.is_empty():
			_build_next_person()
	return people_pending.is_empty()

## Makes the next one whose body is in; one a frame.
func _build_next_person() -> void:
	for k in people_pending.size():
		var id: String = people_pending[k]
		var model := CharacterCast.model_for(Schedules.role_of(id))
		if not ResourceLoader.has_cached(model):
			var status := ResourceLoader.load_threaded_get_status(model)
			if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				# Nothing is requested once the player walks: a body that
				# _spawn_scheduled_people never asked for is left out.
				push_warning("Schedules: %s's body %s was never requested; skipped" % [id, model])
				people_pending.remove_at(k)
				return
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(model)
			else:
				continue
		people_pending.remove_at(k)
		var p: CharacterBody3D = ScheduledPersonScript.new()
		p.name = id
		p.set("person", id)
		_people.add_child(p)
		p.call("resync")
		return

func _spawn_patrol(pos: Vector3) -> void:
	var cop := GuardScene.instantiate()
	cop.set_script(PatrolScript)
	cop.name = "PatrolCop"
	cop.set("role", "police")
	cop.set("vision_range", 7.5 * Headlines.patrol_vision_mult())
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
	_patrol_timer = PATROL_RETURN_DELAY * Headlines.patrol_return_mult()

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

func _on_cell_changed(_cell: Node3D, _awake: bool) -> void:
	_lights_fading = true
	_refresh_sleepers()

## BlockCells freezes the people and the beat cop whose cell sleeps (a poll
## of its own, so not every change comes with a cell_changed): show or hide
## them to match, and put the woken ones where their schedule has them.
func _refresh_sleepers() -> void:
	if _people != null:
		for p in _people.get_children():
			p.refresh()
	for cop in get_tree().get_nodes_in_group("patrol"):
		if cop.has_method("refresh"):
			cop.refresh()

func _on_weather_changed(_raining: bool) -> void:
	_apply_daylight()

func _on_clock_changed(minute: int) -> void:
	_apply_daylight()
	_check_post()
	if minute / 60 != _last_hour:
		_last_hour = minute / 60
		_maybe_mugger()

# --- Muggers (npc/Mugger3D.gd, ui/FightGame.gd) ------------------------------
## After dark, alone on the block: each hour there's a chance somebody
## decides you're worth following. Part of the survival layer, so off when
## it is (the smoke tests).
const MUGGER_HOURS := [21, 4]
const MUGGER_CHANCE := 0.3
const MUGGER_KNIFE_CHANCE := 0.35
const MuggerScript := preload("res://npc/Mugger3D.gd")
var _last_hour := -1

func _maybe_mugger() -> void:
	if zombie_mode or not Survival.enabled or GameState.wanted or GameState.in_custody:
		return
	if not GameState.hours_contain(MUGGER_HOURS, GameState.hour()):
		return
	if get_tree().get_first_node_in_group("mugger") != null or randf() >= MUGGER_CHANCE:
		return
	spawn_mugger(randf() < MUGGER_KNIFE_CHANCE)

func spawn_mugger(knife := false) -> Node3D:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var mugger := CollectorScene.instantiate()
	mugger.set_script(MuggerScript)
	mugger.knife = knife
	mugger.name = "Mugger"
	add_child(mugger)
	var px: float = player.global_position.x if player else 0.0
	var x := px + (16.0 if px < 0.0 else -16.0)
	mugger.global_position = Vector3(clampf(x, -26.0, 26.0), 0.0, -2.6)
	mugger.reset_physics_interpolation()
	return mugger

## Daylight as the sky and the lamps see it: rain makes an overcast, darker
## day. The one place the rain's dimming is decided.
func _effective_daylight() -> float:
	return GameState.daylight() * (RAIN_DAYLIGHT if GameState.raining else 1.0)

const RAIN_DAYLIGHT := 0.55
## How far the after-dark lights are on, 0..1; set with the daylight.
var _lamps_on := 0.0

## Blends the scene between its baked night look and daylight as the clock
## moves through dawn and dusk.
func _apply_daylight() -> void:
	var d := _effective_daylight()
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
	_lamps_on = 1.0 - smoothstep(0.35, 0.75, d)
	_apply_lights()

## The after-dark lights by the hour; a sleeping cell's fade out and stay
## dark, a waking cell's fade back in.
func _apply_lights() -> void:
	for entry in _night_lights:
		# Lamps that are off anyway (it's day) go straight to where their
		# cell says; the fade is for lamps you'd see.
		if _lamps_on <= 0.01:
			entry[3] = _wake_goal(entry)
		_set_light(entry)
	for head in _street_lamp_heads:
		var mat := head.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.emission_energy_multiplier = 5.0 * _lamps_on

func _set_light(entry: Array) -> void:
	var on: float = _lamps_on * float(entry[3])
	(entry[0] as Light3D).light_energy = entry[1] * on
	(entry[0] as Light3D).visible = on > 0.01

func _wake_goal(entry: Array) -> float:
	var cell: Node3D = entry[2]
	return 1.0 if (cell == null or _cells.is_awake(cell)) else 0.0

## Per frame while a cell's lights are coming on or going off.
func _fade_lights(delta: float) -> void:
	_lights_fading = false
	for entry in _night_lights:
		var goal := _wake_goal(entry)
		if entry[3] == goal:
			continue
		entry[3] = move_toward(entry[3], goal, delta / LIGHT_WAKE_SECONDS)
		_lights_fading = true
		_set_light(entry)
