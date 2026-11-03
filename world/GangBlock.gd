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
	ZombieMode.start_round()

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
