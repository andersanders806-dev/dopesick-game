extends "res://world/ZombieBlock.gd"
## Ghetto Wars' arena: the same block, laid over like Dead Block's (the story's people out, the doors out, the
## wrecks, the navmesh with the buildings carved out), but at dusk with the street lamps on and not a zombie
## in it. You defend a corner on Main Street against waves of the rival crew (npc/GangSpawner.gd): the cover they
## fight from is found in the geometry (npc/CoverMap.gd), the guns are on the walls as in Dead Block, and
## armour plates are sold the same way (world/ArmorBuy.gd).

const GangHudScript := preload("res://ui/GangHud.gd")
const GangSpawnerScript := preload("res://npc/GangSpawner.gd")
const GangsterScript := preload("res://npc/Gangster3D.gd")
const GangFXScript := preload("res://fx/GangFX.gd")
const CoverMapScript := preload("res://npc/CoverMap.gd")
const ArmorBuyScript := preload("res://world/ArmorBuy.gd")
const GhettoStoryScript := preload("res://fx/GhettoStory.gd")
const GangAmbienceScript := preload("res://fx/GangAmbience.gd")
const GhettoVoice := preload("res://fx/GhettoVoice.gd")

## Where the plates are sold (probe point, direction), as the guns are.
const PLATE_SPOT := [Vector3(-4, 1.3, -3), Vector3(0, 0, -1)]
const GANG_BOX_SPOTS := [
	[Vector3(-16, 1.3, -3), Vector3(0, 0, -1)],
	[Vector3(72, 1.3, -30), Vector3(1, 0, 0)],
	[Vector3(-72, 1.3, -66), Vector3(-1, 0, 0)],
	[Vector3(-12, 1.3, -92), Vector3(0, 0, -1)],
]
## Dusk: a deep blue sky going orange at the horizon, warm lamps.
const DUSK_SKY := Color(0.09, 0.07, 0.14)
const DUSK_AMBIENT := Color(0.45, 0.4, 0.5)
const DUSK_AMBIENT_ENERGY := 0.3
const DUSK_FOG := Color(0.24, 0.15, 0.13)
const DUSK_MOON := Color(0.65, 0.6, 0.75)

var gang_fx: Node3D
var cover: CoverMapScript
var armor_buy: Area3D
## The story layer (fx/GhettoStory.gd): chapters over the waves, the raid, the endings.
var story: Node
var ambience: Node

func setup(block: Node3D) -> void:
	city = block
	_strip_story()
	_set_dusk()
	_pick_flickering()
	_build_camp_fires()
	_build_wrecks()
	_use_zombie_navmesh()
	_hide_story_hud()
	hud = GangHudScript.new()
	hud.name = "ZombieHud"
	city.add_child(hud)
	gang_fx = GangFXScript.new()
	add_child(gang_fx)
	prewarm_gang_bodies()
	_arm_player()
	spawner = GangSpawnerScript.new()
	spawner.holder = city
	spawner.spawn_points.assign(SPAWN_POINTS)
	add_child(spawner)
	_build_cover()
	_build_purchases()
	_install_story()
	ZombieMode.start_round()

# --- The story drives the war -------------------------------------------------------------

func _install_story() -> void:
	story = GhettoStoryScript.install(GhettoMode, self)
	story.props_parent = city
	story.chapter_started.connect(_on_chapter)
	story.story_finished.connect(_on_story_finished)
	story.hud.ending_dismissed.connect(_end_run)
	ambience = GangAmbienceScript.new()
	add_child(ambience)
	ambience.attach(story)
	ZombieMode.game_over_override = _story_takes_the_end

## The bust brings the police: from then on the waves are the warrant team, not the Dock Boys.
func _on_chapter(id: String) -> void:
	if spawner != null:
		spawner.crew_name = "Police" if id == "bust" else "Dock Boys"

## Down in the raid is the BUSTED ending; after an ending nothing else ends the run but the card.
func _story_takes_the_end() -> bool:
	if story == null or not is_instance_valid(story):
		return false
	if story.finished:
		return true
	if story.raid_active:
		story.bust("downed")
		return true
	return false

func _exit_tree() -> void:
	GhettoVoice.reset_duck()
	if ZombieMode.game_over_override == _story_takes_the_end:
		ZombieMode.game_over_override = Callable()

func _on_story_finished(_ending: String) -> void:
	if spawner != null:
		spawner.enabled = false
	await get_tree().create_timer(1.2, true, false, true).timeout
	for g in get_tree().get_nodes_in_group("gangsters"):
		if is_instance_valid(g):
			g.queue_free()

## The ending card is dismissed: the run's own summary, headed by how it ended.
func _end_run() -> void:
	ZombieMode.game_over_override = Callable()
	Engine.time_scale = 1.0
	var d: Dictionary = story.ending_data()
	ZombieMode.death_cause = String(d.get("title", ""))
	ZombieMode.game_over()

func prewarm_gang_bodies() -> void:
	prewarmed = 0
	for b in GangsterScript.GANG_BODIES:
		CharacterCastScript.scene_for(GangsterScript.MODEL_DIR + b + ".glb")
		prewarmed += 1

## The navmesh is baked once the first frames have passed, so cover is built a couple of physics frames in.
func _build_cover() -> void:
	cover = CoverMapScript.new()
	GangsterScript.cover_map = cover
	await get_tree().physics_frame
	await get_tree().physics_frame
	var map := city.get_world_3d().navigation_map
	var player := get_tree().get_first_node_in_group("player") as Node3D
	# The navmesh is handed to the server a few frames in: wait until the player's own spot is on it.
	for i in 240:
		if not is_inside_tree():
			return
		var at := player.global_position if player != null else Vector3.ZERO
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, at).distance_to(at) < 3.0:
			break
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	cover.build(city.get_world_3d(), map)

func _set_dusk() -> void:
	var env: Environment = city._env
	var night: Dictionary = city._night
	night["sky"] = DUSK_SKY
	night["ambient"] = DUSK_AMBIENT
	night["ambient_energy"] = DUSK_AMBIENT_ENERGY
	night["fog_light"] = DUSK_FOG
	night["fog_density"] = 0.012
	night["vol_density"] = 0.012
	night["moon_color"] = DUSK_MOON
	night["moon_energy"] = 0.35
	env.fog_enabled = true
	env.fog_sky_affect = 1.0
	env.volumetric_fog_albedo = Color(0.7, 0.55, 0.5)
	city._apply_daylight()

func _build_purchases() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	for w in WALL_BUYS:
		var t := _snap(w[1], w[2], WALL_GAP)
		var buy: Area3D = WallBuyScript.new()
		city.add_child(buy)
		buy.setup(load("res://weapons/%s.tres" % w[0]))
		buy.transform = t
		wall_buys.append(buy)
	armor_buy = ArmorBuyScript.new()
	city.add_child(armor_buy)
	armor_buy.setup()
	armor_buy.transform = _snap(PLATE_SPOT[0], PLATE_SPOT[1], WALL_GAP)
	var places: Array = []
	for b in GANG_BOX_SPOTS:
		places.append(_snap(b[0], b[1], BOX_GAP))
	mystery_box = MysteryBoxScript.new()
	city.add_child(mystery_box)
	mystery_box.setup(places)
	purchases_ready = true
