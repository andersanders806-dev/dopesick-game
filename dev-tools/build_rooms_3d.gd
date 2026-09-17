extends Node
## Generates world/Apartment3D.tscn, City3D.tscn, DiveBar3D.tscn and Shop3D.tscn.
##
## These rooms are mostly repeated boxes, lights, and Kenney model instances,
## which is far less error-prone to build in code than to hand-write as .tscn
## text. Re-run after changing a layout here:
##   godot --headless --path . res://dev-tools/BuildRooms3D.tscn
## (Run as a scene, not with -s, so the GameState/SFX autoloads exist and
## the room scripts compile.)
##
## Conventions shared by every room:
## - 1 unit = 1 metre, floor top at y = 0, camera looks north (-z), so the
##   south wall is kept low and doors go on the side walls.
## - Floors are StaticBody3D on collision layer 5 (value 16) so they feed the
##   navmesh bake without blocking bodies or line-of-sight rays (mask 1).
## - Interactables are Area3D on layer 3 (value 4), matching the player's
##   InteractZone mask.

const KENNEY := "res://assets/kenney/"
const WALL_H := 2.4
const LOW_WALL_H := 0.5

var PlayerScene: PackedScene = load("res://player/Player3D.tscn")
var HUDScene: PackedScene = load("res://ui/HUD.tscn")
var NPCScene: PackedScene = load("res://npc/NPC3D.tscn")
var GuardScene: PackedScene = load("res://npc/Guard3D.tscn")
var ItemScene: PackedScene = load("res://items/StealableItem3D.tscn")
var DoorScript: Script = load("res://interactables/Door3D.gd")
var PusherScene: PackedScene = load("res://npc/Pusher3D.tscn")
var InteractableScript: Script = load("res://interactables/Interactable3D.gd")

var _root: Node3D

func _ready() -> void:
	_save(_build_apartment(), "res://world/Apartment3D.tscn")
	_save(_build_store_convenience(), "res://world/StoreConvenience3D.tscn")
	_save(_build_store_pharmacy(), "res://world/StorePharmacy3D.tscn")
	_save(_build_store_supermarket(), "res://world/StoreSupermarket3D.tscn")
	_save(_build_store_liquor(), "res://world/StoreLiquor3D.tscn")
	_save(_build_store_electronics(), "res://world/StoreElectronics3D.tscn")
	_save(_build_jail(), "res://world/Jail3D.tscn")
	_save(_build_dive_bar(), "res://world/DiveBar3D.tscn")
	_save(_build_city(), "res://world/City3D.tscn")
	get_tree().quit()

func _save(root: Node3D, path: String) -> void:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		return
	err = ResourceSaver.save(packed, path)
	print("saved ", path, " -> ", err)
	root.free()

# --- generic helpers --------------------------------------------------------

func _new_root(name: String, script_path: String) -> Node3D:
	_root = Node3D.new()
	_root.name = name
	_root.set_script(load(script_path))
	return _root

func _add(parent: Node, node: Node) -> Node:
	parent.add_child(node)
	node.owner = _root
	return node

func _instance(parent: Node, name: String, scene: PackedScene, pos := Vector3.ZERO, scale := 1.0, rot_y_deg := 0.0) -> Node3D:
	var inst := scene.instantiate() as Node3D
	inst.name = name
	_add(parent, inst)
	inst.position = pos
	inst.rotation_degrees.y = rot_y_deg
	inst.scale = Vector3.ONE * scale
	return inst

func _model(parent: Node, name: String, file: String, pos := Vector3.ZERO, scale := 1.0, rot_y_deg := 0.0) -> Node3D:
	return _instance(parent, name, load(KENNEY + file), pos, scale, rot_y_deg)

func _tex_mat(tex_path: String, uv_scale: float, roughness := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(tex_path)
	mat.roughness = roughness
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * uv_scale
	return mat

func _color_mat(color: Color, roughness := 0.8, emission := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func _box_mesh(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	_add(parent, mi)
	mi.position = pos
	return mi

func _collision(parent: Node, shape: Shape3D, pos := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	_add(parent, cs)
	cs.position = pos
	return cs

func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s

## A solid box: StaticBody3D at `center` with a matching mesh (if `mat`) and
## collision shape. `layer` 1 blocks bodies and sight; 16 is floor-only.
func _solid(parent: Node, name: String, size: Vector3, center: Vector3, mat: Material, layer := 1, mesh_size := Vector3.ZERO, mesh_offset := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = layer
	body.collision_mask = 0
	_add(parent, body)
	body.position = center
	if mat:
		_box_mesh(body, "Mesh", mesh_size if mesh_size != Vector3.ZERO else size, mesh_offset, mat)
	_collision(body, _box_shape(size))
	return body

func _light(parent: Node, name: String, pos: Vector3, color: Color, energy: float, light_range: float, shadows := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = name
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = shadows
	_add(parent, l)
	l.position = pos
	return l

func _environment(ambient: Color, ambient_energy: float, fog := false) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	if fog:
		env.fog_enabled = true
		env.fog_light_color = Color(0.08, 0.09, 0.14)
		env.fog_density = 0.02
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	_add(_root, we)
	var nav := NavigationRegion3D.new()
	nav.name = "NavRegion"
	_add(_root, nav)

## Floor slab plus four walls around a (w x d) room centred on the origin.
## The south wall is only LOW_WALL_H tall so it never hides the player from
## the camera, but its collision is full height.
func _room_shell(w: float, d: float, floor_tex: String, floor_uv: float, tint := Color.WHITE) -> void:
	var floor_mat := _tex_mat(floor_tex, floor_uv, 0.85)
	floor_mat.albedo_color = tint
	_solid(_root, "Floor", Vector3(w, 0.1, d), Vector3(0, -0.05, 0), floor_mat, 16)
	var wall_mat := _tex_mat("res://assets/env/wall_tile.png", 0.5, 0.95)
	wall_mat.albedo_color = tint
	var t := 0.2
	_solid(_root, "WallNorth", Vector3(w + 2 * t, WALL_H, t), Vector3(0, WALL_H / 2, -d / 2 - t / 2), wall_mat)
	_solid(_root, "WallSouth", Vector3(w + 2 * t, WALL_H, t), Vector3(0, WALL_H / 2, d / 2 + t / 2), wall_mat, 1,
		Vector3(w + 2 * t, LOW_WALL_H, t), Vector3(0, LOW_WALL_H / 2 - WALL_H / 2, 0))
	_solid(_root, "WallWest", Vector3(t, WALL_H, d), Vector3(-w / 2 - t / 2, WALL_H / 2, 0), wall_mat)
	_solid(_root, "WallEast", Vector3(t, WALL_H, d), Vector3(w / 2 + t / 2, WALL_H / 2, 0), wall_mat)

## A door Area3D. `facing` is the direction the room lies in from the door
## (e.g. Vector3.RIGHT for a door on the west wall): the door slab sits
## against the wall behind it.
func _door(name: String, pos: Vector3, facing: Vector3, target_scene: String, target_spawn: String) -> Area3D:
	var door := Area3D.new()
	door.name = name
	door.collision_layer = 4
	door.collision_mask = 0
	door.monitoring = false
	door.set_script(DoorScript)
	door.set("target_scene", target_scene)
	door.set("target_spawn", target_spawn)
	_add(_root, door)
	door.position = pos
	var along_x := absf(facing.x) > 0.5
	var slab := Vector3(0.1, 2.0, 1.0) if along_x else Vector3(1.0, 2.0, 0.1)
	_box_mesh(door, "Mesh", slab, Vector3(0, 1.0, 0) - facing * 0.44, _tex_mat("res://assets/env/door.png", 1.0, 0.7))
	_collision(door, _box_shape(Vector3(1.0, 2.0, 1.4) if along_x else Vector3(1.4, 2.0, 1.0)), Vector3(0, 1.0, 0))
	return door

const SFX_DIR := "res://assets/sfx/"

## A positional sound source. Looping files loop on their own (their
## .import sets loop_mode forward); one-shots leave `autoplay` off.
## `unit_size` is roughly how close you must be to hear it at full volume.
func _sound(parent: Node, name: String, file: String, pos: Vector3, volume_db: float, unit_size: float, max_distance := 20.0, autoplay := true) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = name
	p.stream = load(SFX_DIR + file)
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.autoplay = autoplay
	_add(parent, p)
	p.position = pos
	return p

## Non-positional room tone, heard the same everywhere in the room.
func _room_tone(file: String, volume_db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.name = "RoomTone"
	p.stream = load(SFX_DIR + file)
	p.volume_db = volume_db
	p.autoplay = true
	_add(_root, p)

func _marker(name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = name
	_add(_root, m)
	m.position = pos

func _player_and_hud(spawn: Vector3) -> void:
	_instance(_root, "Player3D", PlayerScene, spawn)
	var hud := HUDScene.instantiate()
	hud.name = "HUD"
	_add(_root, hud)

# --- Apartment --------------------------------------------------------------
#
# Squalor details grounded in documentary and news photos of drug houses:
# windows boarded or foiled over so only slivers of light get in, a single
# bare bulb, a stained mattress on the floor instead of a bed, next to no
# real furniture (what there is is broken or knocked over), water-damaged
# and punched walls, and trash, bottles, and burnt foil everywhere.

const ENV3D := "res://assets/env3d/"

## Decal projecting `tex` onto whatever is behind it. `wall` is "floor",
## "north", "west", or "east" and orients the projection into that surface.
func _decal(name: String, tex: String, pos: Vector3, width: float, height: float, wall := "floor", spin_deg := 0.0, modulate := Color.WHITE) -> void:
	var d := Decal.new()
	d.name = name
	d.texture_albedo = load(tex)
	d.modulate = modulate
	d.size = Vector3(width, 0.5, height)
	_add(_root, d)
	d.position = pos
	match wall:
		"north":
			d.rotation_degrees = Vector3(90, 0, spin_deg)
		"west":
			d.rotation_degrees = Vector3(spin_deg, 0, -90)
		"east":
			d.rotation_degrees = Vector3(spin_deg, 0, 90)
		_:
			d.rotation_degrees = Vector3(0, spin_deg, 0)

func _cylinder(parent: Node, name: String, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	_add(parent, mi)
	mi.position = pos
	return mi

## A static collider child for a piece of furniture that lives under an
## interactable Area3D (the Area's own shape is only the interact trigger).
func _blocker(parent: Node, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_mask = 0
	_add(parent, body)
	_collision(body, _box_shape(size), center)

## A decorative pile of trash: cans and bottles lying on their sides, a
## crumpled bag, a flattened takeaway box, paper wads, and burnt foil scraps.
## Seeded per pile so each looks different but rebuilds identically.
func _trash_pile(name: String, seed_value: int, spread := 0.7) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pile := Node3D.new()
	pile.name = name
	_add(_root, pile)
	var paper := _color_mat(Color(0.78, 0.76, 0.7), 0.95)
	var foil := _color_mat(Color(0.55, 0.52, 0.48), 0.35)
	foil.metallic = 0.9
	var scorch := _color_mat(Color(0.12, 0.1, 0.08), 0.6)
	var takeaway := _color_mat(Color(0.55, 0.4, 0.26), 0.9)
	var spot := func() -> Vector3:
		return Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
	for i in 2:
		var can := _model(pile, "Can%d" % i, "food/can-small.glb", spot.call() + Vector3(0, 0.1, 0), 0.6)
		can.rotation_degrees = Vector3(90, rng.randf_range(0, 360), 0)
	var bottle := _model(pile, "Bottle", ["food/wine-red.glb", "food/soda-bottle.glb"][rng.randi() % 2], spot.call() + Vector3(0, 0.07, 0), 0.7)
	bottle.rotation_degrees = Vector3(0, rng.randf_range(0, 360), 90)
	_model(pile, "Bag", "food/bag.glb", spot.call(), 0.8, rng.randf_range(0, 360))
	var box := _box_mesh(pile, "TakeawayBox", Vector3(0.45, 0.04, 0.45), spot.call() + Vector3(0, 0.02, 0), takeaway)
	box.rotation_degrees.y = rng.randf_range(0, 90)
	for i in 5:
		var wad := _box_mesh(pile, "Paper%d" % i, Vector3.ONE * rng.randf_range(0.06, 0.11), spot.call() + Vector3(0, 0.04, 0), paper)
		wad.rotation_degrees = Vector3(rng.randf_range(0, 90), rng.randf_range(0, 90), rng.randf_range(0, 90))
	for i in 3:
		var scrap := _box_mesh(pile, "Foil%d" % i, Vector3(0.14, 0.015, 0.1), spot.call() + Vector3(0, 0.01, 0), foil)
		scrap.rotation_degrees = Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 180), rng.randf_range(-15, 15))
		_box_mesh(scrap, "Burn", Vector3(0.06, 0.02, 0.03), Vector3(0.01, 0.002, 0), scorch)
	return pile

func _build_apartment() -> Node3D:
	_new_root("Apartment3D", "res://world/Apartment3D.gd")
	# Very little ambient: the room should read as nearly dark, lit only by
	# the bare bulb, the TV, and what leaks through the boarded window.
	_environment(Color(0.4, 0.42, 0.5), 0.14)
	_room_shell(10.0, 7.0, "res://assets/env/floor_wood_worn.png", 0.5, Color(0.62, 0.56, 0.5))

	var planks := _tex_mat(ENV3D + "plank_weathered.png", 1.0, 0.95)
	var sliver := _color_mat(Color(0.6, 0.75, 1.0), 0.5, 2.5)
	var frame := _color_mat(Color(0.2, 0.17, 0.14), 0.9)

	# Boarded-up window on the north wall: dark opening, crooked planks,
	# pale streetlight showing through the gaps and a cold shaft on the floor.
	var window := Node3D.new()
	window.name = "BoardedWindow"
	_add(_root, window)
	window.position = Vector3(-1.4, 1.45, -3.44)
	_box_mesh(window, "Opening", Vector3(1.3, 1.0, 0.04), Vector3.ZERO, _color_mat(Color(0.02, 0.02, 0.03), 1.0))
	_box_mesh(window, "Sliver1", Vector3(1.2, 0.03, 0.02), Vector3(0, 0.2, 0.03), sliver)
	_box_mesh(window, "Sliver2", Vector3(1.2, 0.025, 0.02), Vector3(0, -0.16, 0.03), sliver)
	var plank_ys := [0.36, 0.03, -0.32]
	var plank_tilts := [4.0, -3.0, 7.0]
	for i in 3:
		var pl := _box_mesh(window, "Plank%d" % (i + 1), Vector3(1.55, 0.24, 0.04), Vector3(0, plank_ys[i], 0.06), planks)
		pl.rotation_degrees.z = plank_tilts[i]
	_box_mesh(window, "FrameTop", Vector3(1.45, 0.08, 0.06), Vector3(0, 0.54, 0.02), frame)
	_box_mesh(window, "FrameBottom", Vector3(1.45, 0.08, 0.06), Vector3(0, -0.54, 0.02), frame)
	var shaft := SpotLight3D.new()
	shaft.name = "WindowShaft"
	shaft.light_color = Color(0.55, 0.68, 1.0)
	shaft.light_energy = 4.0
	shaft.spot_range = 6.0
	shaft.spot_angle = 22.0
	shaft.shadow_enabled = true
	_add(window, shaft)
	shaft.position = Vector3(0, 0.3, 0.15)
	# Spotlights shine down -Z; turn it round to face into the room (+Z),
	# then tilt it down onto the floor.
	shaft.rotation_degrees = Vector3(-50, 180, 0)

	# A second window taped over with foil, a common way to black one out.
	var foil := _color_mat(Color(0.6, 0.58, 0.55), 0.3)
	foil.metallic = 0.85
	var foiled := _box_mesh(_root, "FoilWindow", Vector3(1.1, 0.9, 0.03), Vector3(1.6, 1.5, -3.47), foil)
	_box_mesh(foiled, "TapeTop", Vector3(1.15, 0.06, 0.01), Vector3(0, 0.43, 0.02), _color_mat(Color(0.5, 0.45, 0.3), 0.9))
	_box_mesh(foiled, "TapeSide", Vector3(0.06, 0.95, 0.01), Vector3(-0.53, 0, 0.02), _color_mat(Color(0.5, 0.45, 0.3), 0.9))

	# One bare bulb on a cord -- Apartment3D.gd makes it flicker.
	var bulb := Node3D.new()
	bulb.name = "BareBulb"
	_add(_root, bulb)
	bulb.position = Vector3(-0.4, 0, -0.2)
	_cylinder(bulb, "Cord", 0.01, 0.5, Vector3(0, 2.15, 0), _color_mat(Color(0.05, 0.05, 0.05), 0.8))
	var glass := SphereMesh.new()
	glass.radius = 0.07
	glass.height = 0.16
	glass.material = _color_mat(Color(1.0, 0.85, 0.55), 0.3, 6.0)
	var glass_mi := MeshInstance3D.new()
	glass_mi.name = "Glass"
	glass_mi.mesh = glass
	_add(bulb, glass_mi)
	glass_mi.position = Vector3(0, 1.86, 0)
	_light(bulb, "Light", Vector3(0, 1.8, 0), Color(1.0, 0.8, 0.5), 1.8, 7.5)
	_sound(bulb, "Buzz", "bulb_buzz_loop.wav", Vector3(0, 1.8, 0), -20.0, 2.0, 12.0)
	_sound(bulb, "Crackle", "bulb_crackle.wav", Vector3(0, 1.8, 0), -10.0, 3.0, 15.0, false)

	# Mattress on the floor, no frame: the Bed interactable.
	var bed := Area3D.new()
	bed.name = "Bed"
	bed.collision_layer = 4
	bed.collision_mask = 0
	bed.monitoring = false
	bed.set_script(load("res://interactables/Bed3D.gd"))
	_add(_root, bed)
	bed.position = Vector3(-4.3, 0, -2.4)
	bed.rotation_degrees.y = 6.0
	_box_mesh(bed, "Mattress", Vector3(1.15, 0.2, 2.0), Vector3(0, 0.1, 0), _tex_mat(ENV3D + "mattress_stained.png", 0.8, 0.95))
	_model(bed, "Pillow", "furniture/pillow.glb", Vector3(-0.3, 0.2, -0.75), 2.5, -10.0)
	var blanket := _color_mat(Color(0.16, 0.2, 0.28), 1.0)
	var b1 := _box_mesh(bed, "BlanketA", Vector3(0.9, 0.07, 0.7), Vector3(0.1, 0.23, 0.35), blanket)
	b1.rotation_degrees = Vector3(0, 18, 4)
	var b2 := _box_mesh(bed, "BlanketB", Vector3(0.6, 0.12, 0.45), Vector3(0.35, 0.18, 0.85), blanket)
	b2.rotation_degrees = Vector3(8, -25, -6)
	_blocker(bed, Vector3(1.15, 0.5, 2.0), Vector3(0, 0.25, 0))
	_collision(bed, _box_shape(Vector3(1.9, 1.2, 2.8)), Vector3(0, 0.6, 0))

	# Sagging couch against the west wall, stuffing-side cushion on the floor.
	var couch := StaticBody3D.new()
	couch.name = "Couch"
	_add(_root, couch)
	couch.position = Vector3(-4.5, 0, 1.4)
	var upholstery := _tex_mat(ENV3D + "couch_worn.png", 1.2, 1.0)
	_box_mesh(couch, "Base", Vector3(0.9, 0.35, 2.2), Vector3(0, 0.175, 0), upholstery)
	_box_mesh(couch, "Back", Vector3(0.25, 0.55, 2.2), Vector3(-0.33, 0.62, 0), upholstery)
	_box_mesh(couch, "ArmN", Vector3(0.9, 0.28, 0.2), Vector3(0, 0.49, -1.0), upholstery)
	_box_mesh(couch, "ArmS", Vector3(0.9, 0.28, 0.2), Vector3(0, 0.49, 1.0), upholstery)
	var cushion := _box_mesh(couch, "SaggingCushion", Vector3(0.62, 0.12, 0.85), Vector3(0.08, 0.38, -0.45), upholstery)
	cushion.rotation_degrees = Vector3(-6, 0, 5)
	var fallen := _box_mesh(couch, "FallenCushion", Vector3(0.62, 0.12, 0.85), Vector3(0.95, 0.06, 0.5), upholstery)
	fallen.rotation_degrees = Vector3(0, 35, 0)
	_collision(couch, _box_shape(Vector3(0.9, 0.9, 2.2)), Vector3(0, 0.45, 0))

	# An old radio on an upturned crate by the north wall. Just decor: you buy
	# from the pusher out on the street, not over the phone.
	var radio := StaticBody3D.new()
	radio.name = "RadioCrate"
	_add(_root, radio)
	radio.position = Vector3(3.9, 0, -3.0)
	_model(radio, "Crate", "furniture/cardboardBoxClosed.glb", Vector3(-0.26, 0, 0.26), 2.5)
	_model(radio, "Radio", "furniture/radio.glb", Vector3(-0.3, 0.7, 0.1), 1.6, 12.0)
	_collision(radio, _box_shape(Vector3(0.55, 0.7, 0.55)), Vector3(0, 0.35, 0))

	# Old TV on a box by the east wall, facing into the room.
	var tv := StaticBody3D.new()
	tv.name = "TV"
	_add(_root, tv)
	tv.position = Vector3(4.55, 0, 1.5)
	_model(tv, "Box", "furniture/cardboardBoxClosed.glb", Vector3(0.26, 0, 0.26), 2.5, -90.0)
	_model(tv, "Set", "furniture/televisionVintage.glb", Vector3(0.27, 0.7, -0.4), 2.0, -90.0)
	_collision(tv, _box_shape(Vector3(0.6, 1.3, 0.85)), Vector3(0, 0.65, 0))
	_light(tv, "Glow", Vector3(-0.6, 0.95, 0), Color(0.35, 0.55, 1.0), 1.4, 3.5)
	_sound(tv, "Static", "tv_static_loop.wav", Vector3(-0.3, 0.95, 0), -22.0, 1.5, 10.0)

	# Movable clutter -- Apartment3D.gd picks where each of these ends up.
	var chair := StaticBody3D.new()
	chair.name = "ChairOverturned"
	_add(_root, chair)
	var chair_model := _model(chair, "Model", "furniture/chairDesk.glb", Vector3(0.35, 0.4, 0.4), 2.5)
	chair_model.rotation_degrees = Vector3(0, 30, 90)
	_collision(chair, _box_shape(Vector3(0.8, 0.8, 0.8)), Vector3(0, 0.4, 0))

	var boxes := StaticBody3D.new()
	boxes.name = "BoxStack"
	_add(_root, boxes)
	_model(boxes, "Bottom", "furniture/cardboardBoxClosed.glb", Vector3(-0.26, 0, 0.26), 2.5)
	_model(boxes, "Top", "furniture/cardboardBoxOpen.glb", Vector3(-0.2, 0.7, 0.28), 2.0, 15.0)
	_model(boxes, "Side", "furniture/cardboardBoxClosed.glb", Vector3(0.3, 0, 0.3), 2.0, -20.0)
	_collision(boxes, _box_shape(Vector3(1.1, 1.2, 0.6)), Vector3(0.1, 0.6, 0))

	_trash_pile("TrashA", 11)
	_trash_pile("TrashB", 23)
	_trash_pile("TrashC", 37, 0.5)

	var clothes := Node3D.new()
	clothes.name = "ClothesPile"
	_add(_root, clothes)
	var cloth_colors := [Color(0.15, 0.2, 0.32), Color(0.3, 0.3, 0.3), Color(0.35, 0.1, 0.08), Color(0.2, 0.18, 0.14)]
	for i in cloth_colors.size():
		var c := _box_mesh(clothes, "Cloth%d" % i, Vector3(0.6, 0.08, 0.45), Vector3(0.15 * i - 0.2, 0.04 + i * 0.05, 0.1 * (i % 2)), _color_mat(cloth_colors[i], 1.0))
		c.rotation_degrees = Vector3(i * 3, i * 47, -i * 2)

	# Fixed decor: overflowing trashcan, a knocked-over floor lamp, a punched
	# hole in the drywall with crumbs below it, stains everywhere.
	_model(_root, "Trashcan", "furniture/trashcan.glb", Vector3(2.7, 0, 3.0), 2.0)
	_model(_root, "TrashcanBag", "food/bag.glb", Vector3(2.2, 0, 3.1), 0.9, 40.0)
	var lamp := _model(_root, "LampKnockedOver", "furniture/lampRoundFloor.glb", Vector3(-2.4, 0.1, 3.0), 2.2)
	lamp.rotation_degrees = Vector3(0, -20, 90)

	_decal("HoleInWall", ENV3D + "drywall_hole.png", Vector3(0.4, 1.05, -3.5), 0.45, 0.4, "north")
	var crumbs := _color_mat(Color(0.82, 0.79, 0.72), 1.0)
	for i in 4:
		var crumb := _box_mesh(_root, "Drywall%d" % i, Vector3.ONE * (0.05 + 0.02 * i), Vector3(0.25 + 0.12 * i, 0.03, -3.3 + 0.05 * (i % 2)), crumbs)
		crumb.rotation_degrees = Vector3(i * 20, i * 33, i * 11)

	_decal("WaterStainNorth", ENV3D + "stain_water.png", Vector3(-3.2, 1.9, -3.5), 2.2, 1.6, "north")
	_decal("WaterStainEast", ENV3D + "stain_water.png", Vector3(5.0, 1.6, -2.4), 1.6, 1.8, "east", 30.0)
	_decal("GrimeWest", ENV3D + "stain_grime.png", Vector3(-5.0, 0.7, -2.2), 2.0, 1.2, "west")
	_decal("GrimeWestCouch", ENV3D + "stain_grime.png", Vector3(-5.0, 0.9, 1.4), 2.6, 1.0, "west")
	_decal("FloorGrimeMattress", ENV3D + "stain_grime.png", Vector3(-3.4, 0, -2.2), 1.6, 2.4, "floor", 20.0)
	_decal("FloorGrimeCouch", ENV3D + "stain_grime.png", Vector3(-3.6, 0, 1.4), 1.4, 2.2)
	_decal("FloorWaterCenter", ENV3D + "stain_water.png", Vector3(1.0, 0, 0.8), 2.4, 1.8, "floor", 70.0)
	_decal("FloorGrimeDoor", ENV3D + "stain_grime.png", Vector3(3.8, 0, -0.9), 1.2, 1.4, "floor", 10.0, Color(1, 1, 1, 0.7))

	_door("DoorToCity", Vector3(4.55, 0, -0.9), Vector3.LEFT, "res://world/City3D.tscn", "SpawnFromHome")
	_marker("SpawnDefault", Vector3(-1.5, 0, -0.5))
	_marker("SpawnFromCity", Vector3(3.6, 0, -0.9))
	_player_and_hud(Vector3(-1.5, 0, -0.5))
	return _root

# --- Stores -----------------------------------------------------------------
#
# Five stores to steal from, picked from what gets shoplifted to fund a habit
# (see GameState.REQUEST_POOL): a corner shop, a pharmacy, a supermarket, a
# liquor store, and an electronics store. Security scales with what's on the
# shelves: the supermarket's one cashier is far from the aisles (packaged meat
# famously has little security), the pharmacist watches the aisles from a
# raised back counter, the liquor store clerk sits behind plexiglass with a
# convex mirror and a clear view, and the electronics store has a guard at the
# door as well as a clerk, and low glass cases that hide nothing.
#
# Every store follows the same contract with world/Store3D.gd: Fixture1..N
# (StaticBody3D, with "item_offset" and optional "stock" metadata),
# Item1..N, one or more Guard3D instances, PoliceSpawn, SpawnFromCity.

## Room, painted walls, fluorescent strip lights with their hum, the door out
## on the west wall, and the spawn markers every store needs.
func _store_shell(name: String, w: float, d: float, floor_tex: String, floor_uv: float, city_spawn: String, wall_color: Color, ambient_energy := 0.32, light_color := Color(0.85, 0.95, 1.0), strip_energy := 1.6, floor_tint := Color.WHITE) -> void:
	_new_root(name, "res://world/Store3D.gd")
	_environment(Color(0.55, 0.6, 0.65), ambient_energy)
	_room_shell(w, d, floor_tex, floor_uv)
	var paint := _color_mat(wall_color, 0.85)
	for wall in ["WallNorth", "WallSouth", "WallWest", "WallEast"]:
		(_root.get_node(wall + "/Mesh") as MeshInstance3D).material_override = paint
	((_root.get_node("Floor/Mesh") as MeshInstance3D).mesh.material as StandardMaterial3D).albedo_color = floor_tint
	var strips_x := int(w / 4.5)
	for ix in strips_x:
		for iz in 2:
			var x := -w / 2 + (ix + 0.5) * w / strips_x
			var z := -d / 4 + iz * d / 2
			_light(_root, "Strip%d_%d" % [ix, iz], Vector3(x, 2.3, z), light_color, strip_energy, 6.0, iz == 0)
			_box_mesh(_root, "StripFixture%d_%d" % [ix, iz], Vector3(1.6, 0.05, 0.2), Vector3(x, 2.38, z), _color_mat(light_color, 0.5, 3.0))
	_sound(_root, "FluorescentHum", "fluorescent_hum_loop.wav", Vector3(0, 2.3, 0), -21.0, 6.0, 24.0)
	var door_z := d / 2 - 1.2
	_door("DoorToCity", Vector3(-w / 2 + 0.45, 0, door_z), Vector3.RIGHT, "res://world/City3D.tscn", city_spawn)
	_marker("SpawnFromCity", Vector3(-w / 2 + 1.2, 0, door_z))
	_marker("SpawnDefault", Vector3(-w / 2 + 1.2, 0, door_z))
	_marker("PoliceSpawn", Vector3(-w / 2 + 1.2, 0, door_z + 0.6))

func _store_finish(items: Array[String], layouts: Array, spawn: Vector3) -> void:
	var store_ids := {"StoreConvenience3D": "convenience", "StorePharmacy3D": "pharmacy", "StoreSupermarket3D": "supermarket", "StoreLiquor3D": "liquor", "StoreElectronics3D": "electronics"}
	_root.set("store_id", store_ids[_root.name])
	_root.set("item_ids", items)
	_root.set("fixture_layouts", layouts)
	_player_and_hud(spawn)

## Kenney counter pieces run along +x from `start`, origin at the front edge.
func _counter(parent: Node, name: String, pos: Vector3, pieces: int) -> StaticBody3D:
	var counter := StaticBody3D.new()
	counter.name = name
	_add(parent, counter)
	counter.position = pos
	var piece_w := 0.43 * 2.5
	for i in pieces:
		_model(counter, "Piece%d" % i, "furniture/kitchenBar.glb", Vector3(i * piece_w, 0, 0), 2.5)
	_collision(counter, _box_shape(Vector3(pieces * piece_w, 1.05, 0.53)), Vector3(pieces * piece_w / 2, 0.52, -0.26))
	return counter

func _guard(name: String, pos: Vector3, facing_deg: float, vision_range: float, angle: float, sweep_arc: float, sweep_speed: float, talk_name := "", lines := "", portrait := "") -> Node3D:
	var guard := _instance(_root, name, GuardScene, pos)
	guard.set("vision_range", vision_range)
	guard.set("vision_angle_deg", angle)
	guard.set("sweep_arc_deg", sweep_arc)
	guard.set("sweep_speed", sweep_speed)
	guard.set("base_facing_deg", facing_deg)
	guard.set("talk_name", talk_name)
	guard.set("talk_lines", lines)
	guard.set("talk_portrait_path", portrait)
	return guard

func _label(parent: Node, name: String, text: String, pos: Vector3, rot_y_deg: float, color: Color, font_size := 48, emissive := false) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.005
	l.outline_size = 0
	l.modulate = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2) if emissive else color
	l.shaded = not emissive
	_add(parent, l)
	l.position = pos
	l.rotation_degrees.y = rot_y_deg
	return l

## A tall two-bay shelf unit (2 m wide, 2.2 m tall -- fully blocks sight),
## dressed with rows of small product boxes in the given colours.
func _fixture_shelf(index: int, stock_colors: Array, stock: Array = []) -> StaticBody3D:
	var shelf := StaticBody3D.new()
	shelf.name = "Fixture%d" % index
	_add(_root, shelf)
	_model(shelf, "Left", "furniture/bookcaseOpen.glb", Vector3(-1.0, 0, 0.31), 2.5)
	_model(shelf, "Right", "furniture/bookcaseOpen.glb", Vector3(0.0, 0, 0.31), 2.5)
	for row in 3:
		for k in 8:
			var c: Color = stock_colors[(k + row) % stock_colors.size()]
			_box_mesh(shelf, "Stock%d_%d" % [row, k], Vector3(0.18, 0.2 + 0.05 * ((k * 7 + row) % 3), 0.18), Vector3(-0.88 + k * 0.25, 0.72 + row * 0.5, 0.05), _color_mat(c, 0.7))
	_collision(shelf, _box_shape(Vector3(2.0, 2.2, 0.63)), Vector3(0, 1.1, 0))
	shelf.set_meta("item_offset", Vector3(0, 0.45, 0.5))
	if not stock.is_empty():
		shelf.set_meta("stock", stock)
	_instance(_root, "Item%d" % index, ItemScene)
	return shelf

## An open, waist-high refrigerated case (supermarket meat, deli): low, so
## it doesn't block anyone's view.
func _fixture_cooler(index: int, stock: Array) -> StaticBody3D:
	var cooler := StaticBody3D.new()
	cooler.name = "Fixture%d" % index
	_add(_root, cooler)
	_box_mesh(cooler, "Base", Vector3(2.2, 0.75, 0.9), Vector3(0, 0.375, 0), _color_mat(Color(0.9, 0.9, 0.92), 0.4))
	_box_mesh(cooler, "Well", Vector3(2.0, 0.05, 0.7), Vector3(0, 0.76, 0), _color_mat(Color(0.2, 0.22, 0.25), 0.6))
	_box_mesh(cooler, "Back", Vector3(2.2, 0.5, 0.1), Vector3(0, 1.0, -0.4), _color_mat(Color(0.9, 0.9, 0.92), 0.4))
	_box_mesh(cooler, "Glow", Vector3(2.0, 0.04, 0.04), Vector3(0, 1.22, -0.33), _color_mat(Color(0.75, 0.9, 1.0), 0.3, 3.0))
	for k in 6:
		_box_mesh(cooler, "Pack%d" % k, Vector3(0.25, 0.05, 0.18), Vector3(-0.8 + k * 0.32, 0.8, -0.1 + 0.15 * (k % 2)), _color_mat(Color(0.65, 0.12, 0.12) if k % 3 else Color(0.95, 0.75, 0.25), 0.6))
	_collision(cooler, _box_shape(Vector3(2.2, 1.25, 0.9)), Vector3(0, 0.62, 0))
	cooler.set_meta("item_offset", Vector3(0, 0.78, 0.2))
	cooler.set_meta("stock", stock)
	_instance(_root, "Item%d" % index, ItemScene)
	return cooler

## A low glass display case: stock sits on top, lit from inside. Hides
## nothing from a watching clerk.
func _fixture_glass_case(index: int, glow: Color) -> StaticBody3D:
	var case := StaticBody3D.new()
	case.name = "Fixture%d" % index
	_add(_root, case)
	_box_mesh(case, "Base", Vector3(1.8, 0.55, 0.7), Vector3(0, 0.275, 0), _color_mat(Color(0.12, 0.12, 0.14), 0.4))
	var glass := _color_mat(Color(0.7, 0.85, 0.95, 0.18), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mesh(case, "Glass", Vector3(1.8, 0.35, 0.7), Vector3(0, 0.73, 0), glass)
	_box_mesh(case, "Inside", Vector3(1.6, 0.02, 0.5), Vector3(0, 0.57, 0), _color_mat(glow, 0.3, 1.5))
	for k in 4:
		_box_mesh(case, "Demo%d" % k, Vector3(0.18, 0.1, 0.12), Vector3(-0.6 + k * 0.4, 0.63, 0), _color_mat(Color(0.1, 0.1, 0.1), 0.3))
	_collision(case, _box_shape(Vector3(1.8, 0.9, 0.7)), Vector3(0, 0.45, 0))
	case.set_meta("item_offset", Vector3(0, 0.92, 0.1))
	_instance(_root, "Item%d" % index, ItemScene)
	return case

## Liquor wall: a tall shelf unit packed with bottles.
func _fixture_bottles(index: int) -> StaticBody3D:
	var shelf := StaticBody3D.new()
	shelf.name = "Fixture%d" % index
	_add(_root, shelf)
	_model(shelf, "Left", "furniture/bookcaseOpen.glb", Vector3(-1.0, 0, 0.31), 2.5)
	_model(shelf, "Right", "furniture/bookcaseOpen.glb", Vector3(0.0, 0, 0.31), 2.5)
	var files := ["food/wine-red.glb", "food/soda-bottle.glb"]
	for row in 3:
		for k in 8:
			_model(shelf, "Bottle%d_%d" % [row, k], files[(k * 3 + row) % 2], Vector3(-0.88 + k * 0.25, 0.62 + row * 0.5, 0.05), 0.42)
	_collision(shelf, _box_shape(Vector3(2.0, 2.2, 0.63)), Vector3(0, 1.1, 0))
	shelf.set_meta("item_offset", Vector3(0, 0.45, 0.5))
	_instance(_root, "Item%d" % index, ItemScene)
	return shelf

# Corner shop -----------------------------------------------------------------

func _build_store_convenience() -> Node3D:
	_store_shell("StoreConvenience3D", 12.0, 8.0, "res://assets/env/floor_checkered.png", 0.5, "SpawnFromShop", Color(0.72, 0.78, 0.7))
	var colors := [Color(0.8, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.45, 0.8), Color(0.3, 0.7, 0.3)]
	for i in 5:
		_fixture_shelf(i + 1, colors)
	var counter := _counter(_root, "Counter", Vector3(-3.2, 0, -2.5), 9)
	_model(counter, "Register", "furniture/radio.glb", Vector3(5.2, 1.05, -0.45), 1.6)
	# The cigarette wall behind the counter, and a lottery sign.
	for row in 4:
		for k in 16:
			_box_mesh(_root, "CigWall%d_%d" % [row, k], Vector3(0.16, 0.1, 0.06), Vector3(-2.4 + k * 0.2, 1.1 + row * 0.16, -3.95), _color_mat([Color(0.9, 0.9, 0.9), Color(0.8, 0.15, 0.1), Color(0.2, 0.3, 0.7), Color(0.85, 0.75, 0.2)][(k + row) % 4], 0.6))
	_label(_root, "LottoSign", "LOTTO", Vector3(3.2, 1.9, -3.97), 0.0, Color(1.0, 0.8, 0.1), 64, true)
	_model(_root, "Cooler", "furniture/kitchenFridge.glb", Vector3(4.9, 0, -3.3), 2.5)
	_sound(_root, "CoolerHum", "cooler_hum_loop.wav", Vector3(5.4, 1.0, -3.6), -9.0, 2.5, 14.0)
	_light(_root, "LightCooler", Vector3(5.4, 1.2, -2.6), Color(0.6, 0.85, 1.0), 0.8, 2.5, false)
	_guard("Shopkeeper", Vector3(0.5, 0, -3.4), 90.0, 7.0, 55.0, 110.0, 0.5)
	var layouts := [
		PackedVector2Array([Vector2(-3.25, -0.2), Vector2(0.0, -0.2), Vector2(3.25, -0.2), Vector2(-1.75, 1.8), Vector2(1.75, 1.8)]),
		PackedVector2Array([Vector2(-4.25, -0.95), Vector2(-0.6, -0.95), Vector2(2.9, -0.95), Vector2(-2.5, 1.55), Vector2(1.25, 1.55)]),
		PackedVector2Array([Vector2(-3.5, -0.7), Vector2(1.5, -0.7), Vector2(-1.0, 0.8), Vector2(-3.5, 2.1), Vector2(1.5, 2.1)]),
	]
	var items: Array[String] = ["cigs", "charger", "batteries", "energy", "sunglasses"]
	_store_finish(items, layouts, Vector3(-4.8, 0, 2.8))
	return _root

# Pharmacy ---------------------------------------------------------------------

func _build_store_pharmacy() -> Node3D:
	_store_shell("StorePharmacy3D", 14.0, 9.0, ENV3D + "vinyl_tile.png", 0.5, "SpawnFromPharmacy", Color(0.92, 0.94, 0.95), 0.42, Color(0.95, 1.0, 1.0), 2.0)
	var colors := [Color(0.95, 0.95, 0.95), Color(0.3, 0.55, 0.9), Color(0.85, 0.35, 0.5), Color(0.5, 0.8, 0.6)]
	for i in 4:
		_fixture_shelf(i + 1, colors)
	# Razors live in a locked, glass-fronted case near the pharmacy counter.
	var locked := _fixture_shelf(5, [Color(0.2, 0.35, 0.8), Color(0.9, 0.5, 0.1)], ["razors", "whitening"])
	var glass := _color_mat(Color(0.75, 0.9, 1.0, 0.22), 0.05)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mesh(locked, "GlassDoors", Vector3(2.0, 1.6, 0.04), Vector3(0, 1.3, 0.34), glass)
	_box_mesh(locked, "Lock", Vector3(0.06, 0.1, 0.03), Vector3(0.0, 1.2, 0.37), _color_mat(Color(0.8, 0.7, 0.3), 0.3))
	_label(locked, "AssistSign", "ASK FOR ASSISTANCE", Vector3(0, 2.3, 0.35), 0.0, Color(0.9, 0.15, 0.1), 28)
	# The pharmacy counter at the back, raised so the pharmacist sees over the
	# aisles' ends, with its sign and a green cross.
	var counter := _counter(_root, "PharmacyCounter", Vector3(1.5, 0, -2.9), 6)
	_box_mesh(counter, "Raise", Vector3(6.45, 0.25, 1.4), Vector3(3.2, 0.125, -0.95), _color_mat(Color(0.8, 0.8, 0.78), 0.6))
	_label(_root, "PharmacySign", "PHARMACY", Vector3(4.7, 2.15, -4.45), 0.0, Color(0.2, 0.85, 0.35), 80, true)
	_box_mesh(_root, "CrossV", Vector3(0.14, 0.45, 0.03), Vector3(1.8, 2.12, -4.47), _color_mat(Color(0.2, 0.9, 0.35), 0.4, 3.0))
	_box_mesh(_root, "CrossH", Vector3(0.45, 0.14, 0.03), Vector3(1.8, 2.12, -4.47), _color_mat(Color(0.2, 0.9, 0.35), 0.4, 3.0))
	var bp := StaticBody3D.new()
	bp.name = "BloodPressureKiosk"
	_add(_root, bp)
	bp.position = Vector3(-5.9, 0, -3.8)
	_box_mesh(bp, "Chair", Vector3(0.7, 0.9, 0.7), Vector3(0, 0.45, 0), _color_mat(Color(0.15, 0.3, 0.55), 0.5))
	_box_mesh(bp, "Screen", Vector3(0.5, 0.35, 0.05), Vector3(0.1, 1.15, -0.3), _color_mat(Color(0.3, 0.7, 0.9), 0.3, 1.5))
	_collision(bp, _box_shape(Vector3(0.7, 1.3, 0.7)), Vector3(0, 0.65, 0))
	var g := _guard("Pharmacist", Vector3(4.2, 0.25, -3.7), 115.0, 8.5, 55.0, 130.0, 0.45, "Pharmacist",
		"Can I help you find something?\nRazors are locked up. I'll have to get those for you.\nWe've had a lot of theft lately. The cameras are on.\nPrescriptions are at the counter, not in the aisles.",
		"res://assets/portraits/pharmacist.png")
	var layouts := [
		PackedVector2Array([Vector2(-4.5, -1.6), Vector2(-4.5, 1.2), Vector2(-0.8, -0.4), Vector2(-0.8, 2.3), Vector2(3.6, 1.0)]),
		PackedVector2Array([Vector2(-4.8, -0.2), Vector2(-1.6, -0.2), Vector2(-4.8, 2.5), Vector2(-1.6, 2.5), Vector2(3.8, 0.6)]),
	]
	var items: Array[String] = ["coldmeds", "formula", "makeup", "whitening", "razors"]
	_store_finish(items, layouts, Vector3(-5.8, 0, 3.3))
	return _root

# Supermarket ------------------------------------------------------------------

func _build_store_supermarket() -> Node3D:
	_store_shell("StoreSupermarket3D", 18.0, 11.0, ENV3D + "vinyl_tile.png", 0.5, "SpawnFromSupermarket", Color(0.93, 0.9, 0.8), 0.38, Color(1.0, 1.0, 0.95), 1.8)
	var colors := [Color(0.95, 0.5, 0.05), Color(0.2, 0.4, 0.85), Color(0.9, 0.9, 0.9), Color(0.8, 0.15, 0.15), Color(0.95, 0.8, 0.25)]
	# Long aisles: each aisle is two shelf fixtures end to end.
	for i in 6:
		_fixture_shelf(i + 1, colors)
	# The meat and deli cooler along the back wall.
	_fixture_cooler(7, ["steak", "steak", "cheese"])
	_fixture_cooler(8, ["steak", "cheese"])
	_label(_root, "MeatSign", "FRESH MEAT", Vector3(2.0, 2.2, -5.45), 0.0, Color(0.9, 0.2, 0.15), 64, true)
	# Two checkout lanes by the door: conveyor, register, candy rack.
	for lane in 2:
		var lx := -5.2 + lane * 2.6
		var lane_body := StaticBody3D.new()
		lane_body.name = "Checkout%d" % (lane + 1)
		_add(_root, lane_body)
		lane_body.position = Vector3(lx, 0, 3.4)
		_box_mesh(lane_body, "Counter", Vector3(0.7, 0.85, 2.0), Vector3(0, 0.425, 0), _color_mat(Color(0.75, 0.75, 0.72), 0.5))
		_box_mesh(lane_body, "Belt", Vector3(0.5, 0.02, 1.4), Vector3(0, 0.86, 0.2), _color_mat(Color(0.05, 0.05, 0.05), 0.8))
		_model(lane_body, "Register", "furniture/radio.glb", Vector3(-0.15, 0.85, -0.8), 1.4, 90.0)
		_box_mesh(lane_body, "LaneLight", Vector3(0.1, 0.25, 0.1), Vector3(0, 1.7, -0.9), _color_mat(Color(1.0, 0.95, 0.3), 0.3, 3.0))
		_label(lane_body, "LaneNumber", str(lane + 1), Vector3(0, 1.95, -0.9), 0.0, Color(0.1, 0.1, 0.1), 64)
		_collision(lane_body, _box_shape(Vector3(0.7, 0.85, 2.0)), Vector3(0, 0.425, 0))
	# A few abandoned shopping carts.
	for c in 2:
		var cart := _box_mesh(_root, "Cart%d" % c, Vector3(0.55, 0.5, 0.85), Vector3(-7.6 + c * 0.25, 0.55, -3.0 + c * 0.55), _color_mat(Color(0.7, 0.72, 0.75, 0.6), 0.3))
		cart.rotation_degrees.y = 12.0 * c
	# One bored cashier, looking up the aisles from the front of the store.
	_guard("Cashier", Vector3(-4.0, 0, 3.0), -90.0, 8.0, 45.0, 80.0, 0.35, "Cashier",
		"...Hey.\nI don't get paid enough to chase anyone.\nLane two's closed. Lane one's also kind of closed.\nMy manager says watch the meat aisle. I watch my phone.",
		"res://assets/portraits/cashier.png")
	var layouts := [
		PackedVector2Array([Vector2(-5.0, -1.6), Vector2(-3.0, -1.6), Vector2(1.0, -1.6), Vector2(3.0, -1.6), Vector2(1.0, 1.4), Vector2(3.0, 1.4), Vector2(-2.0, -4.3), Vector2(3.5, -4.3)]),
		PackedVector2Array([Vector2(-4.0, -2.0), Vector2(-2.0, -2.0), Vector2(2.0, -2.0), Vector2(4.0, -2.0), Vector2(6.0, 0.9), Vector2(4.0, 0.9), Vector2(-3.5, -4.3), Vector2(2.0, -4.3)]),
	]
	# Steaks and cheese only ever go in the coolers (their "stock" meta).
	var items: Array[String] = ["detergent", "detergent", "cheese", "energy", "formula", "coldmeds"]
	_store_finish(items, layouts, Vector3(-7.8, 0, 4.3))
	return _root

# Liquor store -------------------------------------------------------------------

func _build_store_liquor() -> Node3D:
	_store_shell("StoreLiquor3D", 11.0, 8.0, ENV3D + "linoleum_worn.png", 0.8, "SpawnFromLiquor", Color(0.55, 0.42, 0.3), 0.3, Color(1.0, 0.9, 0.75), 1.5)
	for i in 4:
		_fixture_bottles(i + 1)
	# Counter behind a scratched plexiglass screen, pints and cigarettes
	# behind the clerk, a convex security mirror in the corner.
	var counter := _counter(_root, "Counter", Vector3(-2.2, 0, -2.6), 6)
	var plexi := _color_mat(Color(0.85, 0.9, 0.95, 0.2), 0.15)
	plexi.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box_mesh(counter, "Plexiglass", Vector3(6.45, 1.2, 0.03), Vector3(3.2, 1.65, 0.0), plexi)
	_box_mesh(counter, "PassThrough", Vector3(0.5, 0.15, 0.04), Vector3(3.2, 1.12, 0.0), _color_mat(Color(0.3, 0.3, 0.3), 0.5))
	for row in 3:
		for k in 14:
			_model(_root, "Pint%d_%d" % [row, k], "food/soda-bottle.glb" if k % 2 else "food/wine-red.glb", Vector3(-2.1 + k * 0.4, 0.65 + row * 0.5, -3.85), 0.35)
	var mirror_mesh := SphereMesh.new()
	mirror_mesh.radius = 0.35
	mirror_mesh.height = 0.35
	mirror_mesh.is_hemisphere = true
	var mirror_mat := _color_mat(Color(0.8, 0.8, 0.85), 0.02)
	mirror_mat.metallic = 1.0
	mirror_mesh.material = mirror_mat
	var mirror := MeshInstance3D.new()
	mirror.name = "SecurityMirror"
	mirror.mesh = mirror_mesh
	_add(_root, mirror)
	mirror.position = Vector3(-5.2, 2.1, -3.7)
	mirror.rotation_degrees = Vector3(110, 45, 0)
	_label(_root, "CameraSign", "SMILE, YOU'RE ON CAMERA", Vector3(-1.0, 2.25, -3.97), 0.0, Color(0.9, 0.9, 0.85), 32)
	_label(_root, "LiquorNeon", "COLD BEER & WINE", Vector3(2.8, 2.25, -3.97), 0.0, Color(1.0, 0.2, 0.15), 44, true)
	_label(_root, "LottoNeon", "LOTTO", Vector3(5.47, 1.8, 1.0), -90.0, Color(1.0, 0.8, 0.1), 60, true)
	_guard("Clerk", Vector3(1.0, 0, -3.4), 90.0, 7.5, 60.0, 120.0, 0.55, "Clerk",
		"You buying or browsing?\nI see you in the mirror. I see everybody in the mirror.\nNo, I don't do credit.\nTouch the top shelf and I'm calling it in.",
		"res://assets/portraits/liquor_clerk.png")
	var layouts := [
		PackedVector2Array([Vector2(-3.2, -0.4), Vector2(0.3, -0.4), Vector2(-3.2, 2.1), Vector2(2.9, 1.6)]),
		PackedVector2Array([Vector2(-3.0, 0.4), Vector2(0.6, 0.4), Vector2(3.4, -0.2), Vector2(1.9, 2.6)]),
	]
	var items: Array[String] = ["whiskey", "vodka", "cognac", "vodka"]
	_store_finish(items, layouts, Vector3(-4.3, 0, 2.8))
	return _root

# Electronics store ---------------------------------------------------------------

func _build_store_electronics() -> Node3D:
	_store_shell("StoreElectronics3D", 14.0, 9.0, ENV3D + "concrete_floor.png", 0.35, "SpawnFromElectronics", Color(0.2, 0.22, 0.26), 0.35, Color(0.9, 0.95, 1.0), 1.7, Color(0.55, 0.57, 0.62))
	var glows := [Color(0.3, 0.6, 1.0), Color(0.8, 0.3, 0.9), Color(0.3, 0.9, 0.6), Color(1.0, 0.6, 0.2)]
	for i in 4:
		_fixture_glass_case(i + 1, glows[i])
	# One tall peg wall for headphones and games.
	_fixture_shelf(5, [Color(0.1, 0.1, 0.1), Color(0.2, 0.45, 0.2), Color(0.85, 0.85, 0.85)], ["headphones", "videogame"])
	# The TV wall: a grid of screens all showing something different.
	var screen_colors := [Color(0.2, 0.5, 1.0), Color(0.9, 0.3, 0.2), Color(0.2, 0.8, 0.4), Color(0.9, 0.8, 0.2), Color(0.6, 0.3, 0.9), Color(0.2, 0.8, 0.9)]
	for row in 2:
		for k in 6:
			var sx := -4.8 + k * 1.3
			_box_mesh(_root, "TVFrame%d_%d" % [row, k], Vector3(1.2, 0.72, 0.06), Vector3(sx, 1.25 + row * 0.8, -4.45), _color_mat(Color(0.03, 0.03, 0.03), 0.3))
			_box_mesh(_root, "TVScreen%d_%d" % [row, k], Vector3(1.1, 0.62, 0.02), Vector3(sx, 1.25 + row * 0.8, -4.41), _color_mat(screen_colors[(k + row * 2) % screen_colors.size()], 0.2, 2.2))
	_light(_root, "TVWallGlow", Vector3(-1.5, 1.6, -3.4), Color(0.5, 0.6, 1.0), 1.5, 6.0, false)
	var counter := _counter(_root, "Counter", Vector3(2.5, 0, -2.6), 4)
	_model(counter, "Register", "furniture/radio.glb", Vector3(2.0, 1.05, -0.4), 1.6)
	# Anti-theft gates either side of the entrance.
	for gz in [-0.9, 0.9]:
		var gate := StaticBody3D.new()
		gate.name = "EASGate%s" % ("N" if gz < 0 else "S")
		_add(_root, gate)
		gate.position = Vector3(-5.9, 0, 3.3 + gz)
		_box_mesh(gate, "Pedestal", Vector3(0.12, 1.5, 0.45), Vector3(0, 0.75, 0), _color_mat(Color(0.8, 0.82, 0.85, 0.7), 0.2))
		_box_mesh(gate, "Strip", Vector3(0.13, 1.2, 0.04), Vector3(0, 0.75, 0), _color_mat(Color(0.3, 0.8, 1.0), 0.3, 2.0))
		_collision(gate, _box_shape(Vector3(0.12, 1.5, 0.45)), Vector3(0, 0.75, 0))
	_label(_root, "SaleSign", "BIG SALE", Vector3(4.5, 2.2, -4.47), 0.0, Color(1.0, 0.85, 0.1), 64, true)
	_guard("Clerk", Vector3(4.0, 0, -3.4), 110.0, 8.5, 50.0, 110.0, 0.5, "Clerk",
		"Those are display models, they don't even turn on.\nLet me know if you want me to open a case.\nWe tag everything. The gates will scream.")
	_guard("SecurityGuard", Vector3(-4.6, 0, 1.8), -20.0, 6.5, 60.0, 140.0, 0.4, "Security",
		"Keep moving.\nBags stay where I can see them.\nI've got your face on six cameras, pal.\nNot today.",
		"res://assets/portraits/security_guard.png")
	var layouts := [
		PackedVector2Array([Vector2(-2.6, -1.2), Vector2(1.0, -1.2), Vector2(-2.6, 1.3), Vector2(1.0, 1.3), Vector2(4.8, 0.8)]),
		PackedVector2Array([Vector2(-1.8, -1.6), Vector2(1.8, -1.6), Vector2(-0.8, 0.8), Vector2(2.6, 1.6), Vector2(5.0, -0.4)]),
	]
	var items: Array[String] = ["headphones", "smartphone", "watch", "videogame", "headphones"]
	_store_finish(items, layouts, Vector3(-5.8, 0, 3.3))
	return _root

# --- Jail -------------------------------------------------------------------
#
# Where you wake up after getting busted. The holding cell follows first-hand
# accounts and news photos of police holding cells: concrete block walls
# "painted and repainted in an inoffensively offensive beige"; a concrete
# shelf for a bed with a plastic-covered foam mattress; a lidless, seatless
# stainless steel toilet with a small sink inset in the wall above it; a
# small window of reinforced glass behind bars; an intercom reading "Press
# for medical attention"; a steel door with an observation slot; nothing
# with a hard edge or anything loose. Outside it: the booking desk, the
# mugshot height chart, bagged property, and the way out.

func _build_jail() -> Node3D:
	_new_root("Jail3D", "res://world/Jail3D.gd")
	_environment(Color(0.6, 0.62, 0.6), 0.3)
	var w := 13.0
	var d := 8.0
	_room_shell(w, d, ENV3D + "concrete_floor.png", 0.4)
	var block := _tex_mat(ENV3D + "cinder_block_beige.png", 0.6, 0.55)
	for wall in ["WallNorth", "WallSouth", "WallWest", "WallEast"]:
		(_root.get_node(wall + "/Mesh") as MeshInstance3D).material_override = block
	var steel := _color_mat(Color(0.62, 0.64, 0.66), 0.35)
	steel.metallic = 0.85
	var hw := w / 2
	var hd := d / 2

	# --- The cell: west end of the room, x from -hw to -2.5.
	var cell_right := -2.5
	var cell_front := 0.2
	_solid(_root, "CellWallEast", Vector3(0.2, WALL_H, hd + cell_front - 1.1), Vector3(cell_right, WALL_H / 2, -hd + (hd + cell_front - 1.1) / 2), block)
	_solid(_root, "CellWallSouth", Vector3(cell_right + hw, WALL_H, 0.2), Vector3((-hw + cell_right) / 2, WALL_H / 2, cell_front), block, 1,
		Vector3(cell_right + hw, 0.9, 0.2), Vector3(0, 0.45 - WALL_H / 2, 0))

	# Steel door in the cell's east wall, with an observation slot. It slides
	# north into the wall when you're released (Jail3D.gd).
	var door := StaticBody3D.new()
	door.name = "CellDoor"
	_add(_root, door)
	door.position = Vector3(cell_right, 0, cell_front - 0.55)
	_box_mesh(door, "Slab", Vector3(0.12, 2.1, 0.95), Vector3(0, 1.05, 0), steel)
	_box_mesh(door, "Slot", Vector3(0.13, 0.08, 0.3), Vector3(0, 1.45, 0), _color_mat(Color(0.05, 0.05, 0.05), 0.8))
	_box_mesh(door, "Hatch", Vector3(0.13, 0.12, 0.35), Vector3(0, 0.95, 0), _color_mat(Color(0.5, 0.52, 0.54), 0.4))
	_collision(door, _box_shape(Vector3(0.2, 2.1, 0.95)), Vector3(0, 1.05, 0))
	var door_talk := Area3D.new()
	door_talk.name = "CellDoorKnock"
	door_talk.collision_layer = 4
	door_talk.collision_mask = 0
	door_talk.monitoring = false
	door_talk.set_script(InteractableScript)
	_add(door, door_talk)
	_collision(door_talk, _box_shape(Vector3(1.4, 2.0, 1.2)), Vector3(-0.6, 1.0, 0))

	# Concrete bench along the cell's north wall with a blue plastic mattress
	# -- also where you "wait it out".
	var bench := Area3D.new()
	bench.name = "Bench"
	bench.collision_layer = 4
	bench.collision_mask = 0
	bench.monitoring = false
	bench.set_script(InteractableScript)
	_add(_root, bench)
	bench.position = Vector3(-4.6, 0, -hd + 0.45)
	var concrete := _color_mat(Color(0.7, 0.67, 0.6), 0.9)
	_box_mesh(bench, "Shelf", Vector3(2.6, 0.45, 0.7), Vector3(0, 0.225, 0), concrete)
	_box_mesh(bench, "Mattress", Vector3(1.9, 0.08, 0.62), Vector3(-0.2, 0.49, 0), _color_mat(Color(0.15, 0.3, 0.6), 0.2))
	_blocker(bench, Vector3(2.6, 0.5, 0.7), Vector3(0, 0.25, 0))
	_collision(bench, _box_shape(Vector3(2.8, 1.2, 1.6)), Vector3(0, 0.6, 0.4))

	# Steel toilet with the little sink set into the wall above it.
	var toilet := StaticBody3D.new()
	toilet.name = "Toilet"
	_add(_root, toilet)
	toilet.position = Vector3(-hw + 0.35, 0, -0.9)
	_box_mesh(toilet, "Base", Vector3(0.5, 0.42, 0.45), Vector3(0.05, 0.21, 0), steel)
	_cylinder(toilet, "Bowl", 0.19, 0.06, Vector3(0.15, 0.43, 0), _color_mat(Color(0.2, 0.22, 0.24), 0.2))
	_box_mesh(toilet, "SinkBox", Vector3(0.22, 0.35, 0.5), Vector3(-0.1, 0.95, 0), steel)
	_box_mesh(toilet, "Basin", Vector3(0.16, 0.04, 0.3), Vector3(0.0, 1.12, 0), _color_mat(Color(0.25, 0.27, 0.28), 0.2))
	_collision(toilet, _box_shape(Vector3(0.55, 1.1, 0.5)), Vector3(0.05, 0.55, 0))

	# Small barred window of reinforced glass high on the back wall.
	var win := Node3D.new()
	win.name = "CellWindow"
	_add(_root, win)
	win.position = Vector3(-4.6, 1.95, -hd + 0.02)
	_box_mesh(win, "Glass", Vector3(0.7, 0.3, 0.02), Vector3.ZERO, _color_mat(Color(0.55, 0.65, 0.75), 0.1, 0.6))
	for b in 5:
		_cylinder(win, "Bar%d" % b, 0.015, 0.3, Vector3(-0.28 + b * 0.14, 0, 0.03), steel)
	var daylight := SpotLight3D.new()
	daylight.name = "WindowLight"
	daylight.light_color = Color(0.75, 0.85, 1.0)
	daylight.light_energy = 2.0
	daylight.spot_range = 5.0
	daylight.spot_angle = 25.0
	daylight.shadow_enabled = true
	_add(win, daylight)
	daylight.position = Vector3(0, 0, 0.2)
	daylight.rotation_degrees = Vector3(-55, 180, 0)

	# Intercom by the door, a caged ceiling light, a CCTV dome, a floor drain.
	var intercom := Area3D.new()
	intercom.name = "Intercom"
	intercom.collision_layer = 4
	intercom.collision_mask = 0
	intercom.monitoring = false
	intercom.set_script(InteractableScript)
	_add(_root, intercom)
	intercom.position = Vector3(cell_right - 0.12, 0, -1.4)
	_box_mesh(intercom, "Panel", Vector3(0.03, 0.25, 0.18), Vector3(0, 1.35, 0), steel)
	_box_mesh(intercom, "Button", Vector3(0.02, 0.05, 0.05), Vector3(-0.02, 1.3, 0), _color_mat(Color(0.8, 0.1, 0.1), 0.4, 1.5))
	_label(intercom, "Label", "PRESS FOR\nMEDICAL ATTENTION", Vector3(-0.03, 1.6, 0), -90.0, Color(0.15, 0.15, 0.15), 18)
	_collision(intercom, _box_shape(Vector3(1.0, 1.6, 0.9)), Vector3(-0.4, 0.8, 0))
	var cage := _box_mesh(_root, "CagedLight", Vector3(0.6, 0.1, 0.3), Vector3(-4.4, 2.35, -1.9), _color_mat(Color(0.95, 1.0, 0.9), 0.4, 2.5))
	for b in 4:
		_box_mesh(cage, "Cage%d" % b, Vector3(0.02, 0.12, 0.34), Vector3(-0.27 + b * 0.18, -0.02, 0), steel)
	_light(_root, "CellLight", Vector3(-4.4, 2.2, -1.9), Color(0.92, 1.0, 0.88), 1.6, 5.5)
	var cctv_mesh := SphereMesh.new()
	cctv_mesh.radius = 0.12
	cctv_mesh.height = 0.12
	cctv_mesh.is_hemisphere = true
	cctv_mesh.material = _color_mat(Color(0.1, 0.1, 0.12), 0.1)
	var cctv := MeshInstance3D.new()
	cctv.name = "CCTVDome"
	cctv.mesh = cctv_mesh
	_add(_root, cctv)
	cctv.position = Vector3(-2.75, 2.35, -hd + 0.25)
	cctv.rotation_degrees.x = 180.0
	_cylinder(_root, "FloorDrain", 0.1, 0.01, Vector3(-4.0, 0.005, -1.4), _color_mat(Color(0.2, 0.2, 0.2), 0.6))

	# --- Booking area, east of the cell.
	var desk := _counter(_root, "BookingDesk", Vector3(1.0, 0, -2.4), 5)
	_model(desk, "Computer", "furniture/televisionVintage.glb", Vector3(2.2, 1.05, -0.45), 1.3, 180.0)
	_label(_root, "BookingSign", "BOOKING", Vector3(3.6, 2.1, -hd + 0.03), 0.0, Color(0.1, 0.15, 0.3), 72)
	var jailer := _instance(_root, "Jailer", NPCScene, Vector3(3.6, 0, -3.3))
	jailer.set("npc_name", "Booking Officer")
	jailer.set("fences_items", false)
	jailer.set("model_path", KENNEY + "characters/character-male-c.glb")
	jailer.set("flavor_lines", "Door's that way. Don't make me see you again this week.\nYour property? Evidence now.\nNext time it's a judge, not me.")
	# Mugshot height chart on the wall by the desk.
	var chart := _box_mesh(_root, "HeightChart", Vector3(1.0, 2.0, 0.02), Vector3(-1.2, 1.0, -hd + 0.02), _color_mat(Color(0.85, 0.85, 0.82), 0.8))
	for mark in 5:
		_box_mesh(chart, "Line%d" % mark, Vector3(1.0, 0.015, 0.01), Vector3(0, -0.8 + mark * 0.4, 0.015), _color_mat(Color(0.1, 0.1, 0.1), 0.8))
		_label(chart, "Mark%d" % mark, str(4 + mark) + "'", Vector3(-0.42, -0.74 + mark * 0.4, 0.02), 0.0, Color(0.1, 0.1, 0.1), 24)
	# Bagged property on a shelf behind the desk.
	_model(_root, "PropertyShelf", "furniture/bookcaseOpenLow.glb", Vector3(5.2, 0, -hd + 0.63), 2.5)
	for k in 4:
		_box_mesh(_root, "PropertyBag%d" % k, Vector3(0.22, 0.3, 0.15), Vector3(5.35 + k * 0.23, 0.55, -hd + 0.35), _color_mat(Color(0.85, 0.85, 0.8, 0.7), 0.3))
	_light(_root, "BookingLight", Vector3(2.5, 2.3, -1.0), Color(0.95, 1.0, 0.9), 1.8, 7.0)
	_sound(_root, "FluorescentHum", "fluorescent_hum_loop.wav", Vector3(1.0, 2.3, 0), -24.0, 5.0, 20.0)

	_door("DoorToCity", Vector3(hw - 0.45, 0, 2.6), Vector3.LEFT, "res://world/City3D.tscn", "SpawnFromJail")
	_marker("SpawnCell", Vector3(-3.8, 0, -1.5))
	_marker("SpawnDefault", Vector3(-3.8, 0, -1.5))
	_player_and_hud(Vector3(-3.8, 0, -1.5))
	return _root

# --- Dive Bar ---------------------------------------------------------------
#
# Based on write-ups of what makes a "true" dive bar (The Takeout, Wikipedia,
# Toast, and dive bar reviews): dim, lit mostly by old neon beer signs
# (dimmed with age, hung at different heights) and Christmas lights left up
# year-round; dated wood-panelled walls; sticky linoleum tile floors; red
# vinyl booths and ripped, duct-taped stools; a bar top worn by forearms; a
# small TV behind the bar with a discoloured screen; a pool table with faded
# felt under a hanging stained-glass lamp; a jukebox with burnt-out bulbs;
# darts; an ATM at the back; cash only; pretzels on the bar; and the one
# window that isn't boarded up. Sign text is generic, never real brands.

const BAR_W := 15.0
const BAR_D := 9.0

## A neon sign: glowing Label3D text (HDR colour, so the environment's glow
## blooms it) on a dark backing board, plus a small light for the colour
## spill. `dim` < 1 for signs that have faded over the decades.
func _neon(name: String, text: String, pos: Vector3, rot_y_deg: float, color: Color, font_size := 72, dim := 1.0) -> Label3D:
	var holder := Node3D.new()
	holder.name = name
	_add(_root, holder)
	holder.position = pos
	holder.rotation_degrees.y = rot_y_deg
	var label := Label3D.new()
	label.name = "Text"
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.005
	label.outline_size = 0
	label.modulate = Color(color.r * 2.6 * dim, color.g * 2.6 * dim, color.b * 2.6 * dim)
	label.shaded = false
	_add(holder, label)
	label.position = Vector3(0, 0, 0.03)
	var width := text.length() * font_size * 0.005 * 0.62 + 0.25
	_box_mesh(holder, "Backing", Vector3(width, font_size * 0.005 + 0.12, 0.03), Vector3.ZERO, _color_mat(Color(0.03, 0.03, 0.03), 0.8))
	_light(holder, "Glow", Vector3(0, 0, 0.5), color, 1.1 * dim, 3.2, false)
	return label

## A string of Christmas lights sagging between `from` and `to`. Every
## `dead_every`-th bulb is burnt out.
func _string_lights(name: String, from: Vector3, to: Vector3, count: int, sag: float, dead_every := 7) -> void:
	var holder := Node3D.new()
	holder.name = name
	_add(_root, holder)
	var colors := [Color(1, 0.15, 0.1), Color(0.2, 1, 0.3), Color(0.25, 0.4, 1), Color(1, 0.8, 0.2), Color(1, 0.45, 0.1)]
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.08
	var dead := _color_mat(Color(0.15, 0.15, 0.15), 0.6)
	for i in count:
		var t := float(i) / float(count - 1)
		var p := from.lerp(to, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		var mi := MeshInstance3D.new()
		mi.name = "Bulb%d" % i
		mi.mesh = bulb
		mi.material_override = dead if (i % dead_every == dead_every - 1) else _color_mat(colors[i % colors.size()], 0.4, 4.0)
		_add(holder, mi)
		mi.position = p
	# A few coloured lights along the string for the glow on the panelling.
	for k in 3:
		var t := (k + 0.5) / 3.0
		_light(holder, "Glow%d" % k, from.lerp(to, t) - Vector3(0, sag, -0.3), colors[k * 2 % colors.size()], 0.35, 3.0, false)

## A red vinyl booth against the west wall: formica table between two
## benches. Patrons sit on the north bench, facing the room.
func _booth(name: String, center_z: float) -> void:
	var booth := StaticBody3D.new()
	booth.name = name
	_add(_root, booth)
	booth.position = Vector3(-BAR_W / 2 + 0.8, 0, center_z)
	var vinyl := _tex_mat(ENV3D + "vinyl_red.png", 1.5, 0.35)
	var formica := _color_mat(Color(0.55, 0.38, 0.22), 0.3)
	var chrome := _color_mat(Color(0.7, 0.7, 0.72), 0.25)
	chrome.metallic = 0.9
	var tape := _color_mat(Color(0.62, 0.62, 0.6), 0.5)
	tape.metallic = 0.4
	_box_mesh(booth, "TableTop", Vector3(1.5, 0.05, 0.75), Vector3(0.05, 0.75, 0), formica)
	_cylinder(booth, "TableLeg", 0.05, 0.72, Vector3(0.1, 0.37, 0), chrome)
	for side in [-1, 1]:
		var z: float = side * 0.85
		_box_mesh(booth, "Seat%s" % ("N" if side < 0 else "S"), Vector3(1.6, 0.18, 0.5), Vector3(0, 0.4, z), vinyl)
		_box_mesh(booth, "SeatBase%s" % ("N" if side < 0 else "S"), Vector3(1.6, 0.32, 0.46), Vector3(0, 0.16, z), _color_mat(Color(0.2, 0.08, 0.06), 0.8))
		_box_mesh(booth, "Back%s" % ("N" if side < 0 else "S"), Vector3(1.6, 0.8, 0.16), Vector3(0, 0.85, z + side * 0.3), vinyl)
	var patch := _box_mesh(booth, "DuctTape", Vector3(0.28, 0.01, 0.16), Vector3(0.35, 0.495, 0.9), tape)
	patch.rotation_degrees.y = 25.0
	_collision(booth, _box_shape(Vector3(1.6, 1.25, 2.3)), Vector3(0, 0.62, 0))
	# A dim amber wall sconce over each booth.
	_box_mesh(booth, "Sconce", Vector3(0.12, 0.2, 0.25), Vector3(-0.72, 1.75, 0), _color_mat(Color(1.0, 0.65, 0.3), 0.4, 3.0))
	_light(booth, "SconceLight", Vector3(-0.4, 1.7, 0), Color(1.0, 0.62, 0.32), 1.3, 3.2)

func _build_dive_bar() -> Node3D:
	_new_root("DiveBar3D", "res://world/DiveBar3D.gd")
	_environment(Color(0.5, 0.32, 0.28), 0.3)
	_room_shell(BAR_W, BAR_D, ENV3D + "linoleum_worn.png", 0.8)
	# One tired, yellowed ceiling light over the middle of the room.
	_light(_root, "CeilingLight", Vector3(-1.5, 2.35, 1.0), Color(1.0, 0.78, 0.5), 1.1, 7.0)
	# Wood panelling over the brick on every wall.
	var panelling := _tex_mat(ENV3D + "wood_paneling.png", 0.55, 0.7)
	for wall in ["WallNorth", "WallSouth", "WallWest", "WallEast"]:
		(_root.get_node(wall + "/Mesh") as MeshInstance3D).material_override = panelling

	var hw := BAR_W / 2
	var hd := BAR_D / 2

	# --- The bar: worn counter with a brass foot rail, back bar with a
	# mirror and bottles, beer taps, pretzels, an old till, a CASH ONLY card.
	var counter := StaticBody3D.new()
	counter.name = "BarCounter"
	_add(_root, counter)
	counter.position = Vector3(0, 0, -2.5)
	var piece_w := 0.43 * 2.5
	var start_x := -5.2
	var count := 6
	for i in count:
		_model(counter, "Piece%d" % i, "furniture/kitchenBar.glb", Vector3(start_x + i * piece_w, 0, 0), 2.5)
	_model(counter, "EndR", "furniture/kitchenBarEnd.glb", Vector3(start_x + count * piece_w, 0, 0), 2.5)
	var counter_len := count * piece_w + 0.25
	var worn_top := _color_mat(Color(0.3, 0.17, 0.08), 0.25)
	_box_mesh(counter, "WornTop", Vector3(counter_len, 0.05, 0.62), Vector3(start_x + counter_len / 2, 1.07, -0.26), worn_top)
	var brass := _color_mat(Color(0.75, 0.55, 0.25), 0.3)
	brass.metallic = 0.9
	var rail := _cylinder(counter, "FootRail", 0.03, counter_len, Vector3(start_x + counter_len / 2, 0.22, 0.12), brass)
	rail.rotation_degrees.z = 90.0
	_collision(counter, _box_shape(Vector3(counter_len, 1.1, 0.62)), Vector3(start_x + counter_len / 2, 0.55, -0.26))
	var chrome := _color_mat(Color(0.8, 0.8, 0.82), 0.2)
	chrome.metallic = 1.0
	for i in 3:
		_cylinder(counter, "Tap%d" % i, 0.025, 0.32, Vector3(-3.2 + i * 0.35, 1.25, -0.4), chrome)
		_box_mesh(counter, "TapHandle%d" % i, Vector3(0.05, 0.16, 0.05), Vector3(-3.2 + i * 0.35, 1.47, -0.4), _color_mat([Color(0.8, 0.1, 0.1), Color(0.1, 0.1, 0.1), Color(0.9, 0.7, 0.1)][i], 0.5))
	for i in 2:
		var bowl := _cylinder(counter, "PretzelBowl%d" % i, 0.14, 0.06, Vector3(-4.4 + i * 3.6, 1.12, -0.15), _color_mat(Color(0.6, 0.6, 0.62), 0.4))
		for k in 5:
			var pretzel := _box_mesh(bowl, "Pretzel%d" % k, Vector3(0.05, 0.02, 0.03), Vector3(-0.06 + k * 0.03, 0.04, 0.02 * (k % 2)), _color_mat(Color(0.55, 0.32, 0.12), 0.8))
			pretzel.rotation_degrees.y = k * 40.0
	_model(counter, "Till", "furniture/radio.glb", Vector3(0.1, 1.09, -0.55), 1.6, 180.0)

	var bottle_files := ["food/wine-red.glb", "food/soda-bottle.glb"]
	for i in 6:
		var bx := -5.2 + i * 1.05
		_model(_root, "BackBar%d" % (i + 1), "furniture/bookcaseOpen.glb", Vector3(bx, 0, -hd + 0.63), 2.5)
		for shelf_y in [0.62, 1.12]:
			for j in 4:
				_model(_root, "Bottle%d_%d_%d" % [i + 1, int(shelf_y * 10), j], bottle_files[(i + j) % 2], Vector3(bx + 0.18 + j * 0.2, shelf_y, -hd + 0.3), 0.42)
	var mirror := _color_mat(Color(0.55, 0.5, 0.45), 0.05)
	mirror.metallic = 1.0
	_box_mesh(_root, "BackBarMirror", Vector3(6.3, 1.0, 0.02), Vector3(-2.05, 1.55, -hd + 0.02), mirror)
	_light(_root, "BackBarGlow", Vector3(-2.05, 0.9, -hd + 0.8), Color(1.0, 0.6, 0.3), 1.2, 4.0, false)

	# Small TV up in the corner behind the bar, screen gone blue-green.
	_model(_root, "BarTV", "furniture/televisionVintage.glb", Vector3(1.6, 2.0, -hd + 0.05), 1.8)
	_light(_root, "BarTVGlow", Vector3(1.8, 2.1, -hd + 0.9), Color(0.3, 0.9, 0.75), 0.9, 3.0, false)

	var cash_card := _box_mesh(_root, "CashOnlyCard", Vector3(0.7, 0.28, 0.02), Vector3(-4.6, 2.05, -hd + 0.03), _color_mat(Color(0.85, 0.82, 0.72), 0.9))
	var cash_text := Label3D.new()
	cash_text.name = "CashOnlyText"
	cash_text.text = "CASH ONLY"
	cash_text.font_size = 48
	cash_text.pixel_size = 0.0045
	cash_text.modulate = Color(0.1, 0.08, 0.06)
	cash_text.outline_size = 0
	_add(cash_card, cash_text)
	cash_text.position = Vector3(0, 0, 0.015)

	# Ripped vinyl stools, a couple patched with duct tape.
	var tape := _color_mat(Color(0.62, 0.62, 0.6), 0.5)
	tape.metallic = 0.4
	for i in 5:
		var stool := _model(_root, "Stool%d" % (i + 1), "furniture/stoolBar.glb", Vector3(-4.7 + i * 1.2, 0, -1.8), 2.5, i * 23.0)
		if i % 2 == 1:
			var patch := _box_mesh(stool, "DuctTape", Vector3(0.08, 0.004, 0.05), Vector3(0.13, 0.445, -0.1), tape)
			patch.rotation_degrees.y = 30.0

	var bartender := _instance(_root, "Bartender", NPCScene, Vector3(-2.0, 0, -3.45))
	bartender.set("npc_name", "Bartender")
	bartender.set("model_path", KENNEY + "characters/character-male-d.glb")
	bartender.set("flavor_lines", "Rough night?\nYou look like hell, you know that.\nDrink first, talk later.\nStill breathing. That's something.\nCash only. Machine's in the back if you're short.")

	# Christmas lights, up all year: along the top of the back wall and the
	# west wall.
	_string_lights("XmasLightsNorth", Vector3(-hw + 0.3, 2.3, -hd + 0.08), Vector3(hw - 0.3, 2.3, -hd + 0.08), 44, 0.18)
	_string_lights("XmasLightsWest", Vector3(-hw + 0.08, 2.3, -hd + 0.3), Vector3(-hw + 0.08, 2.3, hd - 0.3), 30, 0.15, 5)

	# --- Neon beer signs at different heights, a couple faded with age.
	_neon("NeonBeer", "BEER", Vector3(3.2, 1.95, -hd + 0.06), 0.0, Color(1.0, 0.15, 0.1))
	_neon("NeonOnTap", "ON TAP", Vector3(-hw + 0.06, 1.7, -3.2), 90.0, Color(1.0, 0.6, 0.1), 60, 0.6)
	_neon("NeonColdBeer", "COLD BEER", Vector3(hw - 0.06, 1.55, -2.9), -90.0, Color(0.2, 0.55, 1.0), 60, 0.8)

	# --- Booths along the west wall.
	_booth("BoothA", -0.9)
	_booth("BoothB", 1.9)

	# --- Pool table with faded felt under a stained-glass lamp.
	var pool := StaticBody3D.new()
	pool.name = "PoolTable"
	_add(_root, pool)
	pool.position = Vector3(3.3, 0, 1.1)
	var wood := _color_mat(Color(0.28, 0.14, 0.06), 0.45)
	for lx in [-1.05, 1.05]:
		for lz in [-0.5, 0.5]:
			_box_mesh(pool, "Leg", Vector3(0.14, 0.62, 0.14), Vector3(lx, 0.31, lz), wood)
	_box_mesh(pool, "Body", Vector3(2.5, 0.2, 1.4), Vector3(0, 0.7, 0), wood)
	_box_mesh(pool, "Felt", Vector3(2.2, 0.03, 1.1), Vector3(0, 0.81, 0), _tex_mat(ENV3D + "felt_faded.png", 1.0, 1.0))
	for rz in [-0.62, 0.62]:
		_box_mesh(pool, "RailLong", Vector3(2.5, 0.08, 0.16), Vector3(0, 0.84, rz), wood)
	for rx in [-1.17, 1.17]:
		_box_mesh(pool, "RailShort", Vector3(0.16, 0.08, 1.4), Vector3(rx, 0.84, 0), wood)
	var pocket := _color_mat(Color(0.02, 0.02, 0.02), 1.0)
	for px in [-1.08, 0.0, 1.08]:
		for pz in [-0.53, 0.53]:
			_cylinder(pool, "Pocket", 0.06, 0.02, Vector3(px, 0.83, pz), pocket)
	var ball_rng := RandomNumberGenerator.new()
	ball_rng.seed = 8
	var ball := SphereMesh.new()
	ball.radius = 0.04
	ball.height = 0.08
	var ball_colors := [Color(0.95, 0.95, 0.9), Color(0.05, 0.05, 0.05), Color(0.9, 0.75, 0.1), Color(0.1, 0.2, 0.8), Color(0.8, 0.1, 0.1), Color(0.45, 0.1, 0.5), Color(0.9, 0.4, 0.05), Color(0.1, 0.5, 0.2), Color(0.5, 0.1, 0.1)]
	for i in ball_colors.size():
		var b := MeshInstance3D.new()
		b.name = "Ball%d" % i
		b.mesh = ball
		b.material_override = _color_mat(ball_colors[i], 0.15)
		_add(pool, b)
		b.position = Vector3(ball_rng.randf_range(-0.95, 0.95), 0.865, ball_rng.randf_range(-0.42, 0.42))
	var cue := _cylinder(pool, "Cue", 0.015, 1.45, Vector3(0.1, 0.87, 0.15), _color_mat(Color(0.75, 0.6, 0.35), 0.4))
	cue.rotation_degrees = Vector3(0, 25, 90)
	_collision(pool, _box_shape(Vector3(2.5, 0.9, 1.4)), Vector3(0, 0.45, 0))

	var lamp := Node3D.new()
	lamp.name = "PoolLamp"
	_add(_root, lamp)
	lamp.position = Vector3(3.3, 2.0, 1.1)
	_box_mesh(lamp, "Shade", Vector3(1.3, 0.14, 0.42), Vector3.ZERO, _color_mat(Color(0.12, 0.08, 0.04), 0.6))
	var panes := [Color(0.9, 0.55, 0.1), Color(0.7, 0.1, 0.08), Color(0.15, 0.5, 0.2), Color(0.9, 0.55, 0.1)]
	for i in panes.size():
		_box_mesh(lamp, "Glass%d" % i, Vector3(0.28, 0.1, 0.02), Vector3(-0.45 + i * 0.3, -0.02, 0.215), _color_mat(panes[i], 0.3, 2.5))
	for cx in [-0.5, 0.5]:
		_cylinder(lamp, "Chain", 0.008, 0.45, Vector3(cx, 0.3, 0), _color_mat(Color(0.3, 0.3, 0.3), 0.5))
	var pool_light := SpotLight3D.new()
	pool_light.name = "Light"
	pool_light.light_color = Color(1.0, 0.8, 0.5)
	pool_light.light_energy = 3.5
	pool_light.spot_range = 3.5
	pool_light.spot_angle = 50.0
	pool_light.shadow_enabled = true
	_add(lamp, pool_light)
	pool_light.position = Vector3(0, -0.1, 0)
	pool_light.rotation_degrees.x = -90.0
	var leaning_cue := _cylinder(_root, "WallCue", 0.015, 1.45, Vector3(hw - 0.15, 0.72, -0.6), _color_mat(Color(0.75, 0.6, 0.35), 0.4))
	leaning_cue.rotation_degrees.z = 8.0

	# --- High-top tables for the patrons who stand.
	for t in [["HighTopA", Vector3(-2.7, 0, 0.9)], ["HighTopB", Vector3(-0.6, 0, 3.0)]]:
		var top := StaticBody3D.new()
		top.name = t[0]
		_add(_root, top)
		top.position = t[1]
		_cylinder(top, "Top", 0.35, 0.05, Vector3(0, 1.0, 0), _color_mat(Color(0.5, 0.33, 0.18), 0.3))
		_cylinder(top, "Post", 0.04, 1.0, Vector3(0, 0.5, 0), chrome)
		_cylinder(top, "Foot", 0.22, 0.03, Vector3(0, 0.015, 0), chrome)
		_model(top, "Glass", "food/soda-bottle.glb", Vector3(0.1, 1.03, 0.05), 0.4)
		var shape := CylinderShape3D.new()
		shape.radius = 0.35
		shape.height = 1.05
		_collision(top, shape, Vector3(0, 0.52, 0))

	# The patrons themselves -- DiveBar3D.gd seats them.
	for i in 3:
		var patron := _instance(_root, "Patron%d" % (i + 1), NPCScene)
		patron.set("is_patron", true)

	# --- Jukebox (a few bulbs burnt out), darts, the ATM at the back, the
	# restrooms, and the one unboarded window with its OPEN sign.
	var jukebox := StaticBody3D.new()
	jukebox.name = "Jukebox"
	_add(_root, jukebox)
	jukebox.position = Vector3(hw - 0.6, 0, -hd + 0.55)
	_model(jukebox, "Cabinet", "furniture/speaker.glb", Vector3(-0.22, 0, 0.22), 3.0)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.03
	bulb_mesh.height = 0.06
	for i in 9:
		var a := PI * i / 8.0
		var jb := MeshInstance3D.new()
		jb.name = "Bulb%d" % i
		jb.mesh = bulb_mesh
		jb.material_override = _color_mat(Color(0.15, 0.12, 0.1), 0.6) if i in [2, 6] else _color_mat([Color(1, 0.5, 0.1), Color(1, 0.2, 0.3), Color(0.3, 0.6, 1)][i % 3], 0.4, 4.0)
		_add(jukebox, jb)
		jb.position = Vector3(cos(a) * 0.32, 1.35 + sin(a) * 0.35, 0.25)
	_collision(jukebox, _box_shape(Vector3(0.7, 1.9, 0.6)), Vector3(0, 0.95, 0))
	_light(jukebox, "Glow", Vector3(0, 1.2, 0.7), Color(1.0, 0.45, 0.15), 1.3, 3.0, false)
	_sound(jukebox, "JukeboxMusic", "jukebox_loop.wav", Vector3(0, 1.0, 0), -15.0, 3.0, 25.0)
	_room_tone("bar_murmur_loop.wav", -12.0)

	var dart_mesh := CylinderMesh.new()
	dart_mesh.top_radius = 0.24
	dart_mesh.bottom_radius = 0.24
	dart_mesh.height = 0.04
	dart_mesh.material = _color_mat(Color(0.12, 0.3, 0.12), 0.9)
	var dart := MeshInstance3D.new()
	dart.name = "Dartboard"
	dart.mesh = dart_mesh
	_add(_root, dart)
	dart.position = Vector3(5.2, 1.55, -hd + 0.03)
	dart.rotation_degrees.x = 90.0
	_cylinder(dart, "Bullseye", 0.05, 0.05, Vector3(0, 0.01, 0), _color_mat(Color(0.7, 0.05, 0.05), 0.6))
	_box_mesh(_root, "Chalkboard", Vector3(0.5, 0.7, 0.03), Vector3(6.05, 1.5, -hd + 0.03), _color_mat(Color(0.08, 0.09, 0.08), 0.95))

	var atm := StaticBody3D.new()
	atm.name = "ATM"
	_add(_root, atm)
	atm.position = Vector3(-hw + 0.45, 0, -hd + 0.5)
	_box_mesh(atm, "Body", Vector3(0.6, 1.5, 0.55), Vector3(0, 0.75, 0), _color_mat(Color(0.35, 0.36, 0.38), 0.5))
	_box_mesh(atm, "Screen", Vector3(0.02, 0.22, 0.3), Vector3(0.31, 1.15, 0), _color_mat(Color(0.3, 0.6, 1.0), 0.3, 2.0))
	var atm_label := Label3D.new()
	atm_label.name = "Sign"
	atm_label.text = "ATM"
	atm_label.font_size = 64
	atm_label.pixel_size = 0.004
	atm_label.modulate = Color(0.9, 0.9, 0.9)
	_add(atm, atm_label)
	atm_label.position = Vector3(0.31, 1.4, 0)
	atm_label.rotation_degrees.y = 90.0
	_collision(atm, _box_shape(Vector3(0.6, 1.5, 0.55)), Vector3(0, 0.75, 0))

	_box_mesh(_root, "RestroomDoor", Vector3(0.06, 2.0, 0.9), Vector3(-hw + 0.03, 1.0, hd - 0.9), _tex_mat("res://assets/env/door.png", 1.0, 0.7))
	var wc := Label3D.new()
	wc.name = "RestroomSign"
	wc.text = "RESTROOMS"
	wc.font_size = 40
	wc.pixel_size = 0.004
	wc.modulate = Color(0.85, 0.8, 0.7)
	_add(_root, wc)
	wc.position = Vector3(-hw + 0.07, 2.15, hd - 0.9)
	wc.rotation_degrees.y = 90.0

	var window := Node3D.new()
	window.name = "FrontWindow"
	_add(_root, window)
	window.position = Vector3(hw - 0.05, 1.45, 0.9)
	window.rotation_degrees.y = -90.0
	_box_mesh(window, "Glass", Vector3(1.4, 1.0, 0.02), Vector3.ZERO, _color_mat(Color(0.08, 0.1, 0.18), 0.1, 0.6))
	_box_mesh(window, "FrameTop", Vector3(1.5, 0.07, 0.06), Vector3(0, 0.53, 0.02), wood)
	_box_mesh(window, "FrameBottom", Vector3(1.5, 0.07, 0.06), Vector3(0, -0.53, 0.02), wood)
	# The OPEN sign faces the street, so from inside it reads backwards.
	var open_sign := _neon("NeonOpen", "OPEN", Vector3(hw - 0.12, 1.45, 0.9), 90.0, Color(1.0, 0.1, 0.15), 64)
	open_sign.get_parent().get_node("Backing").visible = false
	_light(_root, "StreetGlow", Vector3(hw - 0.8, 1.6, 0.9), Color(0.5, 0.6, 1.0), 0.6, 3.5, false)

	# Sticky spills and grime on the linoleum, worst in front of the bar.
	_decal("SpillBar1", ENV3D + "stain_grime.png", Vector3(-3.4, 0, -1.6), 1.2, 0.9, "floor", 15.0, Color(1, 1, 1, 0.8))
	_decal("SpillBar2", ENV3D + "stain_water.png", Vector3(-0.6, 0, -1.7), 1.0, 0.8, "floor", 60.0)
	_decal("SpillPool", ENV3D + "stain_grime.png", Vector3(4.9, 0, 2.3), 1.0, 1.2, "floor", 40.0, Color(1, 1, 1, 0.6))
	_decal("SpillDoor", ENV3D + "stain_grime.png", Vector3(6.2, 0, 3.0), 1.4, 1.2, "floor", 0.0, Color(1, 1, 1, 0.7))

	_door("DoorToCity", Vector3(hw - 0.45, 0, 3.0), Vector3.LEFT, "res://world/City3D.tscn", "SpawnFromBar")
	_marker("SpawnFromCity", Vector3(hw - 1.2, 0, 3.0))
	_marker("SpawnDefault", Vector3(hw - 1.2, 0, 3.0))
	_player_and_hud(Vector3(hw - 1.2, 0, 3.0))
	return _root

# --- City -------------------------------------------------------------------

func _streetlight(name: String, x: float, z: float, index: int) -> void:
	var sl := StaticBody3D.new()
	sl.name = name
	_add(_root, sl)
	sl.position = Vector3(x, 0, z)
	_cylinder(sl, "Pole", 0.07, 3.4, Vector3(0, 1.7, 0), _color_mat(Color(0.12, 0.12, 0.13), 0.6))
	_box_mesh(sl, "Head", Vector3(0.5, 0.12, 0.25), Vector3(0, 3.4, -0.1), _color_mat(Color(1.0, 0.7, 0.3), 0.5, 5.0))
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.15
	cyl.height = 3.4
	_collision(sl, cyl, Vector3(0, 1.7, 0))
	_light(sl, "Light", Vector3(0, 3.2, 0.2), Color(1.0, 0.65, 0.3), 2.5, 7.0)
	var buzz := _sound(sl, "Buzz", "bulb_buzz_loop.wav", Vector3(0, 3.2, 0), -28.0, 1.5, 8.0)
	buzz.pitch_scale = 0.88 + 0.04 * index  # detuned so neighbouring lamps don't phase

## A parked car built from boxes; its "Body" joins the car_bodies group so
## City3D.gd can give each a random paint colour.
func _car(name: String, pos: Vector3, facing_left := false) -> void:
	var car := StaticBody3D.new()
	car.name = name
	_add(_root, car)
	car.position = pos
	if facing_left:
		car.rotation_degrees.y = 180.0
	var body := _box_mesh(car, "Body", Vector3(3.8, 0.7, 1.7), Vector3(0, 0.55, 0), _color_mat(Color(0.5, 0.1, 0.1), 0.35))
	body.add_to_group("car_bodies", true)
	_box_mesh(car, "Cabin", Vector3(2.0, 0.55, 1.5), Vector3(-0.2, 1.15, 0), _color_mat(Color(0.08, 0.1, 0.12), 0.1))
	for wx in [-1.2, 1.2]:
		for wz in [-0.8, 0.8]:
			_box_mesh(car, "Wheel", Vector3(0.6, 0.6, 0.2), Vector3(wx, 0.3, wz), _color_mat(Color(0.03, 0.03, 0.03), 0.9))
	_box_mesh(car, "Headlights", Vector3(0.05, 0.12, 1.3), Vector3(1.91, 0.65, 0), _color_mat(Color(1.0, 0.95, 0.8), 0.3, 2.0))
	_collision(car, _box_shape(Vector3(3.8, 1.4, 1.7)), Vector3(0, 0.7, 0))

func _build_city() -> Node3D:
	_new_root("City3D", "res://world/City3D.gd")
	_environment(Color(0.35, 0.4, 0.6), 0.3, true)

	var w := 58.0
	var d := 9.0
	var street_z := -4.5
	_solid(_root, "Floor", Vector3(w, 0.1, d), Vector3(0, -0.05, 0), null, 16)
	_box_mesh(_root, "Sidewalk", Vector3(w, 0.1, 3.0), Vector3(0, -0.04, street_z + 1.5), _tex_mat("res://assets/env/sidewalk_tile.png", 0.5, 0.9))
	_box_mesh(_root, "Road", Vector3(w, 0.1, d - 3.0), Vector3(0, -0.05, street_z + 3.0 + (d - 3.0) / 2), _tex_mat("res://assets/env/road_tile.png", 0.25, 0.8))

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.25
	moon.shadow_enabled = true
	_add(_root, moon)
	moon.rotation_degrees = Vector3(-50, 30, 0)

	# Invisible boundary: the building row to the north, and the edges of the
	# block everywhere else.
	_solid(_root, "BoundsNorth", Vector3(w, WALL_H, 0.2), Vector3(0, WALL_H / 2, street_z - 0.1), null)
	_solid(_root, "BoundsSouth", Vector3(w, WALL_H, 0.2), Vector3(0, WALL_H / 2, d / 2 + 0.1), null)
	_solid(_root, "BoundsWest", Vector3(0.2, WALL_H, d), Vector3(-w / 2 - 0.1, WALL_H / 2, 0), null)
	_solid(_root, "BoundsEast", Vector3(0.2, WALL_H, d), Vector3(w / 2 + 0.1, WALL_H / 2, 0), null)

	# The block, west to east. The police station's door is where you come
	# out after a night in a cell; you can't walk in.
	var fronts := [
		{"name": "Police", "file": "city/building-c.glb", "x": -24.5, "sign": "POLICE", "color": Color(0.35, 0.55, 1.0),
			"scene": "", "door": "PoliceDoor", "spawn": "SpawnFromJail"},
		{"name": "Home", "file": "city/building-a.glb", "x": -17.5, "sign": "APTS", "color": Color(0.9, 0.85, 0.7),
			"scene": "res://world/Apartment3D.tscn", "door": "DoorToHome", "spawn": "SpawnFromHome"},
		{"name": "Pharmacy", "file": "city/building-d.glb", "x": -10.5, "sign": "PHARMACY", "color": Color(0.3, 0.95, 0.45),
			"scene": "res://world/StorePharmacy3D.tscn", "door": "DoorToPharmacy", "spawn": "SpawnFromPharmacy"},
		{"name": "Bar", "file": "city/building-b.glb", "x": -3.5, "sign": "BAR", "color": Color(1.0, 0.25, 0.55),
			"scene": "res://world/DiveBar3D.tscn", "door": "DoorToBar", "spawn": "SpawnFromBar"},
		{"name": "Shop", "file": "city/building-d.glb", "x": 3.5, "sign": "24/7 SHOP", "color": Color(0.95, 0.85, 0.3),
			"scene": "res://world/StoreConvenience3D.tscn", "door": "DoorToShop", "spawn": "SpawnFromShop"},
		{"name": "Liquor", "file": "city/building-c.glb", "x": 10.5, "sign": "LIQUOR", "color": Color(1.0, 0.2, 0.15),
			"scene": "res://world/StoreLiquor3D.tscn", "door": "DoorToLiquor", "spawn": "SpawnFromLiquor"},
		{"name": "Supermarket", "file": "city/building-e.glb", "x": 17.5, "sign": "SUPERMARKET", "color": Color(0.95, 0.95, 1.0),
			"scene": "res://world/StoreSupermarket3D.tscn", "door": "DoorToSupermarket", "spawn": "SpawnFromSupermarket", "scale": 3.6},
		{"name": "Electronics", "file": "city/building-a.glb", "x": 24.5, "sign": "ELECTRONICS", "color": Color(0.3, 0.9, 1.0),
			"scene": "res://world/StoreElectronics3D.tscn", "door": "DoorToElectronics", "spawn": "SpawnFromElectronics"},
	]
	for f in fronts:
		var x: float = f["x"]
		var bscale: float = f.get("scale", 5.0)
		_model(_root, f["name"] + "Building", f["file"], Vector3(x, 0, street_z - 0.5 * bscale - 0.05), bscale)
		if f["name"] not in ["Home", "Police"]:
			_model(_root, f["name"] + "Awning", "city/detail-awning.glb", Vector3(x, 2.0, street_z - 0.4), 5.0)
		var sign := Label3D.new()
		sign.name = f["name"] + "Sign"
		sign.text = f["sign"]
		sign.font_size = 96 if f["sign"].length() <= 9 else 72
		sign.pixel_size = 0.006
		sign.modulate = f["color"]
		sign.outline_modulate = Color(0, 0, 0, 0.8)
		_add(_root, sign)
		sign.position = Vector3(x, 3.1, street_z + 0.02)
		_light(_root, f["name"] + "SignGlow", Vector3(x, 2.8, street_z + 0.8), f["color"], 1.2, 4.0, false)
		if f["scene"] == "":
			_box_mesh(_root, f["door"], Vector3(1.0, 2.0, 0.1), Vector3(x, 1.0, street_z + 0.01), _tex_mat("res://assets/env/door.png", 1.0, 0.7))
		else:
			_door(f["door"], Vector3(x, 0, street_z + 0.45), Vector3.BACK, f["scene"], "SpawnFromCity")
		_marker(f["spawn"], Vector3(x, 0, street_z + 1.5))
	# A police cruiser parked out front of the station.
	_car("PoliceCruiser", Vector3(-24.0, 0, 2.6))
	var cruiser := _root.get_node("PoliceCruiser") as Node3D
	var cruiser_body := cruiser.get_node("Body") as MeshInstance3D
	cruiser_body.remove_from_group("car_bodies")
	cruiser_body.mesh.material = _color_mat(Color(0.9, 0.9, 0.92), 0.3)
	_box_mesh(cruiser, "Lightbar", Vector3(0.3, 0.1, 1.2), Vector3(-0.2, 1.48, 0), _color_mat(Color(0.2, 0.3, 1.0), 0.3, 2.0))
	_box_mesh(cruiser, "Stripe", Vector3(3.82, 0.15, 1.72), Vector3(0, 0.55, 0), _color_mat(Color(0.1, 0.15, 0.4), 0.3))

	# Low filler buildings in the gaps, except the two alleys at x = 14 and
	# x = 21: the pusher's stash and his hiding spot.
	for gx in [-21.0, -14.0, -7.0, 0.0, 7.0]:
		_model(_root, "Filler%d" % int(gx), "city/low-detail-building-a.glb" if int(gx) % 2 == 0 else "city/low-detail-building-b.glb", Vector3(gx, 0, street_z - 1.45), 5.0)
	_model(_root, "FillerWestEnd", "city/building-e.glb", Vector3(-30.5, 0, street_z - 2.6), 5.0)
	_model(_root, "FillerEastEnd", "city/building-c.glb", Vector3(30.5, 0, street_z - 2.8), 5.0)
	for ax in [14.0, 21.0]:
		_box_mesh(_root, "Alley%d" % int(ax), Vector3(2.2, 0.1, 5.0), Vector3(ax, -0.04, street_z - 2.5), _tex_mat("res://assets/env/road_tile.png", 0.3, 0.9))
		_box_mesh(_root, "AlleyFence%d" % int(ax), Vector3(2.2, 2.2, 0.08), Vector3(ax, 1.1, street_z - 5.0), _color_mat(Color(0.25, 0.25, 0.27), 0.6))

	# Streetlights: steady along the west and middle of the block, and none at
	# the east end, which is where the pusher works.
	var light_xs := [-27.0, -21.0, -14.0, -7.0, 0.0, 7.0]
	for i in light_xs.size():
		_streetlight("Streetlight%d" % (i + 1), light_xs[i], street_z + 2.7, i)

	_car("CarA", Vector3(-12.0, 0, 2.6))
	_car("CarB", Vector3(5.5, 0, 2.6))
	_car("CarC", Vector3(20.0, 0, 2.8), true)

	var hydrant := StaticBody3D.new()
	hydrant.name = "Hydrant"
	_add(_root, hydrant)
	hydrant.position = Vector3(-8.8, 0, street_z + 2.3)
	_cylinder(hydrant, "Mesh", 0.16, 0.75, Vector3(0, 0.375, 0), _color_mat(Color(0.75, 0.1, 0.08), 0.5))
	_collision(hydrant, _box_shape(Vector3(0.4, 0.75, 0.4)), Vector3(0, 0.375, 0))
	_solid(_root, "Dumpster", Vector3(1.8, 1.2, 1.0), Vector3(21.0, 0.6, street_z + 0.6), _color_mat(Color(0.12, 0.28, 0.16), 0.7))

	_room_tone("city_ambience_loop.wav", -14.0)

	# The pusher works a fixed, badly lit spot at the dark east end, at the
	# mouth of an alley. He keeps nothing on him: the stash is behind the
	# dumpster at the next alley along, and when the lookout whistles he slips
	# down his own alley out of sight.
	var pusher := _instance(_root, "Pusher", PusherScene, Vector3(14.0, 0, street_z + 1.0))
	pusher.set("street_facing_deg", -90.0)
	pusher.set("stash_position", Vector3(21.0, 0, street_z + 1.35))
	pusher.set("hide_position", Vector3(14.0, 0, street_z - 3.5))
	_box_mesh(_root, "StashBag", Vector3(0.18, 0.08, 0.12), Vector3(20.2, 0.04, street_z + 1.2), _color_mat(Color(0.45, 0.33, 0.2), 0.95))

	# His lookout stands between the pharmacy and the bar, watching west
	# toward the police station.
	var lookout := _instance(_root, "Lookout", NPCScene, Vector3(-7.0, 0, street_z + 1.2))
	lookout.set_script(load("res://npc/Lookout3D.gd"))
	lookout.set("npc_name", "Lookout")
	lookout.set("model_path", KENNEY + "characters/character-male-b.glb")
	lookout.set("clothes_tint", Color(0.55, 0.62, 0.9))
	lookout.set("flavor_lines", "Keep walking.\nI ain't seen nothing, and neither have you.\nYou want him, he's down past the liquor store.\nDon't stand here. You're drawing eyes.")
	(lookout.get_node("ModelRoot") as Node3D).rotation_degrees.y = -90.0

	_marker("SpawnDefault", Vector3(-17.5, 0, street_z + 1.5))
	_player_and_hud(Vector3(-17.5, 0, street_z + 1.5))
	return _root
