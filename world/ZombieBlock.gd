extends Node
## The block as Dead Block's arena. City3D adds this when GameState.mode is
## "zombies", after it has left the story's people, traffic and chores out:
## what's placed in the scene itself goes here (the shops' doors, the pusher
## and the rest of the cast); then permanent night under a dense, red fog,
## streetlights that stutter, the zombie HUD, and round 1.
##
## The street is littered with wrecks (assets/cars/wreck_*.glb): burnt-out
## and rusted hulks on the roads, and a few of the parked cars swapped for
## them. They're obstacles like the parked cars were.

const ZombieHudScript := preload("res://ui/ZombieHud.gd")
const WeaponHolderScript := preload("res://player/WeaponHolder.gd")
const WallBuyScript := preload("res://world/WallBuy.gd")
const MysteryBoxScript := preload("res://world/MysteryBox.gd")
const UpgradeMachineScript := preload("res://world/UpgradeMachine.gd")
const CarPaint := preload("res://world/CarPaint.gd")
const BarricadeScript := preload("res://world/Barricade.gd")
const SpawnerScript := preload("res://npc/ZombieSpawner.gd")
const SurgeScript := preload("res://npc/ZombieSurge.gd")
const TsunamiScript := preload("res://fx/Tsunami.gd")
const HighGroundScript := preload("res://world/HighGround.gd")
const QuakeScript := preload("res://fx/Quake.gd")
const NightAtmosScript := preload("res://world/NightAtmos.gd")
## The block's navmesh as zombies need it: with the buildings' masses and the
## wrecks carved out (dev-tools/bake_zombie_navmesh.gd makes it).
const NAVMESH := "res://world/block/zombie_navmesh.res"

## Boards across the alley mouths onto Main Street: [name, position, yaw].
## The dead come through from the service lane behind the shops.
const BARRICADES := [
	["BarricadeAlleyW", Vector3(14.0, 0, -5.6), 0.0],
	["BarricadeAlleyE", Vector3(21.0, 0, -5.6), 0.0],
]
## Where the dead come from: the service lane behind the shops, the avenues,
## Back Street, the lot and the park. The spawner picks the ones out of sight.
const SPAWN_POINTS := [
	Vector3(14.0, 0, -17.5), Vector3(21.0, 0, -17.5),
	Vector3(71.0, 0, -30.0), Vector3(71.0, 0, -70.0), Vector3(-71.0, 0, -30.0), Vector3(-71.0, 0, -70.0),
	Vector3(-40.0, 0, -91.0), Vector3(0.0, 0, -91.0), Vector3(40.0, 0, -91.0),
	Vector3(-72.0, 0, 1.0), Vector3(72.0, 0, 1.0),
	Vector3(45.0, 0, -45.0), Vector3(-45.0, 0, -45.0),
]

## Scene-placed nodes of the story: the doors to every shop, the people.
const STORY_NODES := ["StationDoor", "Pusher", "Lookout", "Ray"]
const STORY_NODE_PREFIXES := ["DoorTo"]

## Wrecks dumped on the roads: [model, cell, position, yaw]. They sit in the
## parking lanes and at the road's edge, never mid-road, so the player's
## routes along the block stay open (a metre-wide bottleneck is a death trap
## here). Cells are the roots world/BlockCells.gd puts to sleep.
const WRECKS := [
	["wreck_burnt_a", "Cell_Main", Vector3(-66.0, 0, 3.0), 15.0],
	["wreck_sedan", "Cell_Main", Vector3(63.0, 0, 2.9), 165.0],
	["wreck_suv", "Cell_West", Vector3(-73.0, 0, -28.0), 85.0],
	["wreck_burnt_b", "Cell_East", Vector3(73.0, 0, -25.0), -95.0],
	["wreck_burnt_a", "Cell_Back", Vector3(-37.0, 0, -92.6), 186.0],
]
## Parked cars that become wrecks: [car node, model].
const SWAPS := [
	["CarMainW2", "wreck_sedan"], ["CarMainE1", "wreck_suv"], ["CarBackS2", "wreck_burnt_a"],
]

## Where the guns are sold. Each is a probe point at chest height and the
## direction to look from it: the first wall the ray meets is where the board,
## the box or the machine goes, facing back along the ray. [gun, from, direction].
const WALL_BUYS := [
	["magnum", Vector3(-12, 1.3, -3), Vector3(0, 0, -1)],
	["smg", Vector3(-21, 1.3, -3), Vector3(0, 0, -1)],
	["shotgun", Vector3(8, 1.3, -3), Vector3(0, 0, -1)],
	["ar", Vector3(25, 1.3, -3), Vector3(0, 0, -1)],
	["sniper", Vector3(-72, 1.3, -36), Vector3(-1, 0, 0)],
]
## The mystery box's places, one at a time: it moves between them.
const BOX_SPOTS := [
	[Vector3(-4, 1.3, -3), Vector3(0, 0, -1)],
	[Vector3(72, 1.3, -30), Vector3(1, 0, 0)],
	[Vector3(-72, 1.3, -66), Vector3(-1, 0, 0)],
	[Vector3(-12, 1.3, -92), Vector3(0, 0, -1)],
]
const MACHINE_SPOT := [Vector3(72, 1.3, -66), Vector3(1, 0, 0)]
## How far in front of the wall things stand (m).
const WALL_GAP := 0.02
const BOX_GAP := 0.55
const MACHINE_GAP := 0.45

## A cold, wet night. The sky is what the fog fades into (a blue-black), the moon is a thin cool fill and
## the ambient a dim blue; the warmth is the sodium streetlamps' (world/NightAtmos.gd tunes their pools)
## and the neon. Depth fog plus a low layer of ground mist; volumetric fog on High.
const SKY := Color(0.03, 0.03, 0.058)
const AMBIENT := Color(0.40, 0.50, 0.72)
const AMBIENT_ENERGY := 0.38
const FOG_LIGHT := Color(0.055, 0.075, 0.105)
const FOG_DENSITY := 0.021
const VOL_FOG_DENSITY := 0.022
const MOON_COLOR := Color(0.5, 0.64, 0.95)
const MOON_ENERGY := 0.5
## Ground mist: fog_height is its top (m), the density it adds below that.
const MIST_HEIGHT := 1.8
const MIST_DENSITY := 0.5
const EXPOSURE := 1.15
## A faint sodium-and-cloud glow low in the sky, which the wet paving and the glass catch (reflections only).
const GLOW_HORIZON := Color(0.34, 0.2, 0.11)
const GLOW_ZENITH := Color(0.035, 0.05, 0.085)

## Every third streetlight stutters: a steady spell, then a burst of
## on-and-off, now and then dead for a moment.
const FLICKER_EVERY := 3
const STEADY_TIME := Vector2(1.2, 6.0)
const BURST_TIME := Vector2(0.15, 0.6)
const DEAD_CHANCE := 0.25

## Burning barrels at the underpass camp (Place_UnderpassCamp), offsets from it.
const CAMP_FIRES := [Vector3(-1.6, 0, 0.6), Vector3(1.9, 0, -0.9), Vector3(0.3, 0, 2.3)]
const CAMP_CELL := "Cell_Inner"
const FIRE_LIGHT := Color(1.0, 0.5, 0.18)
const FIRE_ENERGY := 2.2
const FIRE_RANGE := 7.0

var city: Node3D
var hud: CanvasLayer
var spawner: Node
## The Richter 8.0 surge's director (npc/ZombieSurge.gd).
var surge: Node
var barricades: Array[Node3D] = []
var holder: Node
var wall_buys: Array = []
var mystery_box: Area3D
var upgrade_machine: Area3D
var purchases_ready := false
## [light, full energy, seconds to the next change, in a burst, dead]
var _flickering: Array = []
## world/NightAtmos.gd: wet paving, lamp haze and the rain.
var atmos
## fx/Quake.gd: the presentation of the horde surge.
var quake
## fx/Tsunami.gd: the countdown that can follow a surge (two Drowned to kill, or the wave).
var tsunami
## world/HighGround.gd: the overpass deck with its stair and safe zone (what survives the wave).
var high_ground
## How many streetlights stutter (the smoke test reads it).
var flicker_count: int:
	get: return _flickering.size()

func setup(block: Node3D) -> void:
	city = block
	_strip_story()
	_set_night()
	atmos = NightAtmosScript.new()
	city.add_child(atmos)
	atmos.setup(city)
	_pick_flickering()
	_build_camp_fires()
	_build_wrecks()
	_use_zombie_navmesh()
	_build_barricades()
	_hide_story_hud()
	hud = ZombieHudScript.new()
	hud.name = "ZombieHud"
	city.add_child(hud)
	# RICHTER 8.0: the surge's lights, alarms, dust, shake and seismograph.
	quake = QuakeScript.new()
	quake.city = city
	add_child(quake)
	prewarm_bodies()
	prewarm_render()
	spawner = SpawnerScript.new()
	spawner.holder = city
	spawner.spawn_points.assign(SPAWN_POINTS)
	add_child(spawner)
	spawner.setup_entrances(city)
	surge = SurgeScript.new()
	surge.spawner = spawner
	add_child(surge)
	high_ground = HighGroundScript.new()
	high_ground.city = city
	add_child(high_ground)
	tsunami = TsunamiScript.new()
	tsunami.city = city
	tsunami.spawner = spawner
	tsunami.high = high_ground
	add_child(tsunami)
	_arm_player()
	_build_purchases()
	ZombieMode.start_round()

## How many bodies setup has loaded ahead of the first round (the tests read it).
var prewarmed := 0
const ZombieScript := preload("res://npc/Zombie3D.gd")
const CharacterCastScript := preload("res://npc/CharacterCast.gd")

## Everything a zombie loads the first time one is spawned, loaded now (behind
## the loading fade) so that no spawn in a round stalls its frame: the rot
## noise, and every Rocketbox body the dead can wear (a GLB is 35-45 ms each).
func prewarm_bodies() -> void:
	ZombieScript.warm_shared()
	prewarmed = 0
	for b in ZombieScript.BODIES:
		CharacterCastScript.scene_for(ZombieScript.MODEL_DIR + b + ".glb")
		prewarmed += 1

## Draws every body once, under the street where the camera's frustum still
## takes them in and the pavement hides them, for a few frames: this is when
## the rot shader's pipeline compiles and the skins reach the GPU, not in the
## middle of round 1. They are not in the "zombies" group and don't think.
func prewarm_render() -> void:
	var bay := Node3D.new()
	bay.name = "ZombiePrewarm"
	city.add_child(bay)
	var player := city.get_tree().get_first_node_in_group("player") as Node3D
	var at: Vector3 = player.global_position if player else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in ZombieScript.BODIES.size():
		var z: CharacterBody3D = ZombieScript.new()
		z.configure("walker", 1, rng)
		z.set_meta("body", ZombieScript.BODIES[i])
		z.set_meta("prewarm", true)
		bay.add_child(z)
		z.global_position = at + Vector3(-5.0 + i * 0.5, -4.0, 0.0)
	_free_prewarm(bay)

func _free_prewarm(bay: Node3D) -> void:
	for i in 3:
		if not is_inside_tree():
			break
		await get_tree().process_frame
	if is_instance_valid(bay):
		bay.queue_free()

## The player gets their guns.
func _arm_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	holder = WeaponHolderScript.new()
	player.add_child(holder)

## The wall guns, the box and the upgrade machine, once the walls they stand
## against are in the physics space to be found.
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
	var places: Array = []
	for b in BOX_SPOTS:
		places.append(_snap(b[0], b[1], BOX_GAP))
	mystery_box = MysteryBoxScript.new()
	city.add_child(mystery_box)
	mystery_box.setup(places)
	upgrade_machine = UpgradeMachineScript.new()
	city.add_child(upgrade_machine)
	upgrade_machine.transform = _snap(MACHINE_SPOT[0], MACHINE_SPOT[1], MACHINE_GAP)
	purchases_ready = true

## The spot `gap` metres in front of the first wall met looking from `from`
## along `dir`, turned so +Z faces back along the ray (the street). With no wall
## in reach, the point 6 m on.
func _snap(from: Vector3, dir: Vector3, gap: float) -> Transform3D:
	var space := city.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 14.0)
	var r := space.intersect_ray(q)
	var at := from + dir * 6.0
	if not r.is_empty():
		at = r.position - dir * gap
	at.y = 0.0
	var facing := Basis.looking_at(dir, Vector3.UP)
	return Transform3D(facing, at)

func _strip_story() -> void:
	for child in city.get_children():
		var n := String(child.name)
		if n in STORY_NODES or STORY_NODE_PREFIXES.any(func(pre): return n.begins_with(pre)):
			# Out of the tree now (find_child, groups), freed at frame end.
			city.remove_child(child)
			child.queue_free()

## Over City3D's night baseline, which its daylight blend starts from (and
## which GameState.daylight() == 0 keeps us on).
func _set_night() -> void:
	var env: Environment = city._env
	var night: Dictionary = city._night
	night["sky"] = SKY
	night["ambient"] = AMBIENT
	night["ambient_energy"] = AMBIENT_ENERGY
	night["fog_light"] = FOG_LIGHT
	night["fog_density"] = FOG_DENSITY
	night["vol_density"] = VOL_FOG_DENSITY
	night["moon_color"] = MOON_COLOR
	night["moon_energy"] = MOON_ENERGY
	_hold_atmosphere(env)
	env.volumetric_fog_albedo = Color(0.62, 0.7, 0.82)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.tonemap_exposure = EXPOSURE
	# Reflections come from a dim sky (cheap: one small radiance cube), the background stays the fog colour.
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = GLOW_ZENITH
	mat.sky_horizon_color = GLOW_HORIZON
	mat.ground_horizon_color = GLOW_HORIZON * 0.6
	mat.ground_bottom_color = SKY
	mat.sky_curve = 0.18
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	city._apply_daylight()

## What the fog and the haze are, put back whenever F3 (Graphics) has changed them for a preset.
func _hold_atmosphere(env: Environment) -> void:
	env.fog_enabled = true
	env.fog_sky_affect = 1.0
	env.fog_height = MIST_HEIGHT
	env.fog_height_density = MIST_DENSITY
	env.fog_aerial_perspective = 0.0
	env.fog_sun_scatter = 0.0

func _pick_flickering() -> void:
	var i := 0
	for entry in city._night_lights:
		var light := entry[0] as Light3D
		if not light.get_parent().name.begins_with("Streetlight"):
			continue
		if i % FLICKER_EVERY == 0:
			_flickering.append([light, light.light_energy, randf_range(0.0, STEADY_TIME.y), false, false])
		i += 1

## The navmesh with the buildings and wrecks carved out.
func _use_zombie_navmesh() -> void:
	var nav := city.get_node_or_null("NavRegion") as NavigationRegion3D
	var mesh := load(NAVMESH) as NavigationMesh if ResourceLoader.exists(NAVMESH) else null
	if nav and mesh:
		nav.navigation_mesh = mesh

func _build_barricades() -> void:
	for b in BARRICADES:
		var bar := BarricadeScript.new()
		bar.name = b[0]
		city.add_child(bar)
		bar.global_position = b[1]
		bar.rotation_degrees.y = b[2]
		barricades.append(bar)

## How many wrecks stand on the block (the smoke test reads it).
var wreck_count: int:
	get: return get_tree().get_nodes_in_group("wrecks").size()

func _build_wrecks() -> void:
	for w in WRECKS:
		var body := StaticBody3D.new()
		body.name = "Wreck_%s_%d" % [w[0], hash(w[2]) % 1000]
		var cell := city.get_node_or_null(w[1] as String) as Node3D
		(cell if cell else city).add_child(body)
		body.position = w[2]
		body.rotation_degrees.y = w[3]
		_fit_wreck(body, w[0])
	for swap in SWAPS:
		var car := city.find_child(swap[0], true, false) as StaticBody3D
		if car == null:
			continue
		var old := car.get_node_or_null("Model")
		if old:
			car.remove_child(old)
			old.queue_free()
		# The old box stays: the wreck is about the car's size.
		_add_wreck_model(car, swap[1])

## The wreck's model, and a box round it (never its mesh: scan wrecks are
## thousands of triangles).
func _fit_wreck(body: StaticBody3D, kind: String) -> void:
	var box := _add_wreck_model(body, kind)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(box.size.x, box.size.y, maxf(box.size.z - 0.2, 1.0))
	shape.shape = bs
	shape.position = Vector3(0, box.size.y / 2.0, 0)
	body.add_child(shape)

func _add_wreck_model(body: StaticBody3D, kind: String) -> AABB:
	var model: Node3D = load("res://assets/cars/%s.glb" % kind).instantiate()
	model.name = "Model"
	body.add_child(model)
	body.add_to_group("wrecks")
	CarPaint.limit_range(model, CarPaint.PARKED_REACH)
	return CarPaint.bounds(model)

## [light, seconds to the next jump, current energy factor]
var _fires: Array = []
var _fire_root: Node3D
var _camp_cell: Node3D

## A few burning barrels at the underpass camp: an orange light that jumps
## about (no shadows), a handful of billboard flames and embers. They sleep
## with the camp's cell.
func _build_camp_fires() -> void:
	var camp := city.find_child("Place_UnderpassCamp", true, false) as Node3D
	if camp == null:
		return
	_fire_root = Node3D.new()
	_fire_root.name = "CampFires"
	add_child(_fire_root)
	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.16, 0.12, 0.1)
	barrel_mat.metallic = 0.6
	barrel_mat.roughness = 0.7
	var flame_tex := GradientTexture2D.new()
	flame_tex.fill = GradientTexture2D.FILL_RADIAL
	flame_tex.fill_from = Vector2(0.5, 0.5)
	flame_tex.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.0, 0.0))
	flame_tex.gradient = grad
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.albedo_texture = flame_tex
	for off in CAMP_FIRES:
		var fire := Node3D.new()
		_fire_root.add_child(fire)
		fire.global_position = camp.global_position + off
		var barrel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.85
		barrel.mesh = cyl
		barrel.material_override = barrel_mat
		barrel.position.y = 0.425
		fire.add_child(barrel)
		var light := OmniLight3D.new()
		light.light_color = FIRE_LIGHT
		light.light_energy = FIRE_ENERGY
		light.omni_range = FIRE_RANGE
		light.shadow_enabled = false
		light.position.y = 1.2
		fire.add_child(light)
		var flames := GPUParticles3D.new()
		flames.amount = 14
		flames.lifetime = 0.9
		flames.position.y = 0.9
		flames.local_coords = false
		flames.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 14.0
		pm.initial_velocity_min = 0.7
		pm.initial_velocity_max = 1.3
		pm.gravity = Vector3(0, 0.6, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.18
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.7))
		curve.add_point(Vector2(1, 0.05))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
		flames.process_material = pm
		var quad := QuadMesh.new()
		quad.size = Vector2(0.55, 0.7)
		quad.material = flame_mat
		flames.draw_pass_1 = quad
		fire.add_child(flames)
		_fires.append([light, randf_range(0.05, 0.2), 1.0])
	_camp_cell = city.get_node_or_null(CAMP_CELL) as Node3D
	var cells: Node = city._cells
	if cells and _camp_cell:
		_fire_root.visible = cells.is_awake(_camp_cell)
		cells.cell_changed.connect(func(c: Node3D, awake: bool):
			if c == _camp_cell:
				_fire_root.visible = awake)

## The story's cash, craving and clock mean nothing here.
func _hide_story_hud() -> void:
	var story_hud := get_tree().get_first_node_in_group("hud") as CanvasLayer
	if story_hud:
		story_hud.visible = false

func _process(delta: float) -> void:
	# Graphics (F3) puts the sky out of the fog again on the lower presets.
	var env: Environment = city._env
	if env.fog_sky_affect != 1.0 or not is_equal_approx(env.fog_height_density, MIST_DENSITY):
		_hold_atmosphere(env)
	if not is_equal_approx(env.fog_density, city._night["fog_density"]):
		env.fog_density = city._night["fog_density"]
	for fire in _fires:
		fire[1] -= delta
		if fire[1] <= 0.0:
			fire[1] = randf_range(0.04, 0.16)
			fire[2] = randf_range(0.65, 1.15)
		(fire[0] as OmniLight3D).light_energy = FIRE_ENERGY * fire[2]
	for f in _flickering:
		var light := f[0] as Light3D
		if not is_instance_valid(light):
			continue
		f[2] -= delta
		if f[2] <= 0.0:
			f[3] = not f[3]
			f[2] = randf_range(BURST_TIME.x, BURST_TIME.y) if f[3] else randf_range(STEADY_TIME.x, STEADY_TIME.y)
			f[4] = f[3] and randf() < DEAD_CHANCE
		# Full energy is the lamp's night one, kept when the burst began; a
		# sleeping cell's lamps are hidden by BlockCells, whatever we set.
		var base: float = f[1]
		var lit := base
		if f[3]:
			lit = 0.0 if f[4] else base * (1.0 if randf() > 0.45 else randf_range(0.0, 0.35))
		light.light_energy = lit
