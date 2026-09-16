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

var _root: Node3D

func _ready() -> void:
	_save(_build_apartment(), "res://world/Apartment3D.tscn")
	_save(_build_shop(), "res://world/Shop3D.tscn")
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

	# The phone (radio model) sits on an upturned crate by the north wall.
	var phone := Area3D.new()
	phone.name = "Phone"
	phone.collision_layer = 4
	phone.collision_mask = 0
	phone.monitoring = false
	phone.set_script(load("res://interactables/Phone3D.gd"))
	_add(_root, phone)
	phone.position = Vector3(3.9, 0, -3.0)
	_model(phone, "Crate", "furniture/cardboardBoxClosed.glb", Vector3(-0.26, 0, 0.26), 2.5)
	_model(phone, "Radio", "furniture/radio.glb", Vector3(-0.3, 0.7, 0.1), 1.6, 12.0)
	_blocker(phone, Vector3(0.55, 0.7, 0.55), Vector3(0, 0.35, 0))
	_collision(phone, _box_shape(Vector3(1.6, 1.2, 1.6)), Vector3(0, 0.6, 0.2))

	# Old TV on a box by the east wall, facing into the room.
	var tv := StaticBody3D.new()
	tv.name = "TV"
	_add(_root, tv)
	tv.position = Vector3(4.55, 0, 1.5)
	_model(tv, "Box", "furniture/cardboardBoxClosed.glb", Vector3(0.26, 0, 0.26), 2.5, -90.0)
	_model(tv, "Set", "furniture/televisionVintage.glb", Vector3(0.27, 0.7, -0.4), 2.0, -90.0)
	_collision(tv, _box_shape(Vector3(0.6, 1.3, 0.85)), Vector3(0, 0.65, 0))
	_light(tv, "Glow", Vector3(-0.6, 0.95, 0), Color(0.35, 0.55, 1.0), 1.4, 3.5)

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

# --- Shop -------------------------------------------------------------------

func _build_shop() -> Node3D:
	_new_root("Shop3D", "res://world/Shop3D.gd")
	_environment(Color(0.55, 0.6, 0.65), 0.3)
	_room_shell(12.0, 8.0, "res://assets/env/floor_checkered.png", 0.5)

	# Cold, flat fluorescent strip lights over the aisles.
	for i in 3:
		var x := -4.0 + i * 4.0
		_light(_root, "LightStrip%d" % (i + 1), Vector3(x, 2.3, 0.2), Color(0.85, 0.95, 1.0), 1.6, 6.5)
		_box_mesh(_root, "StripFixture%d" % (i + 1), Vector3(1.6, 0.05, 0.2), Vector3(x, 2.38, 0.2), _color_mat(Color(0.9, 0.97, 1.0), 0.5, 3.0))

	# Counter runs from near the west side to the east wall; the gap at the
	# west end is the staff way round. Kenney counter pieces have their
	# origin at the front edge and extend back (-z).
	var counter := StaticBody3D.new()
	counter.name = "Counter"
	_add(_root, counter)
	counter.position = Vector3(0, 0, -2.5)
	var piece_w := 0.43 * 2.5
	var start_x := -3.2
	var count := 9
	for i in count:
		_model(counter, "Piece%d" % i, "furniture/kitchenBar.glb", Vector3(start_x + i * piece_w, 0, 0), 2.5)
	_model(counter, "End", "furniture/kitchenBarEnd.glb", Vector3(start_x - 0.25, 0, 0), 2.5)
	var counter_len := count * piece_w
	_collision(counter, _box_shape(Vector3(counter_len, 1.05, 0.53)), Vector3(start_x + counter_len / 2, 0.52, -0.26))
	_model(counter, "Register", "furniture/radio.glb", Vector3(2.0, 1.05, -0.45), 1.6)
	_model(_root, "Cooler", "furniture/kitchenFridge.glb", Vector3(4.9, 0, -3.3), 2.5)
	_light(_root, "LightCooler", Vector3(5.4, 1.2, -2.6), Color(0.6, 0.85, 1.0), 0.8, 2.5, false)

	var guard := _instance(_root, "Shopkeeper", GuardScene, Vector3(0.5, 0, -3.4))
	guard.set("vision_range", 7.0)
	guard.set("vision_angle_deg", 55.0)
	guard.set("sweep_arc_deg", 110.0)
	guard.set("sweep_speed", 0.5)
	guard.set("base_facing_deg", 90.0)

	# Shelf units: two tall open bookcases side by side (2 m wide, 2.2 m
	# tall, so they fully block the shopkeeper's line of sight), topped with
	# stock boxes. Shop3D.gd repositions these and the items per layout.
	var shelf_names := ["ShelfA", "ShelfB", "ShelfC", "ShelfD", "ShelfE"]
	var item_names := ["ItemA", "ItemB", "ItemC", "ItemD", "ItemE"]
	for i in 5:
		var shelf := StaticBody3D.new()
		shelf.name = shelf_names[i]
		_add(_root, shelf)
		_model(shelf, "Left", "furniture/bookcaseOpen.glb", Vector3(-1.0, 0, 0.31), 2.5)
		_model(shelf, "Right", "furniture/bookcaseOpen.glb", Vector3(0.0, 0, 0.31), 2.5)
		_collision(shelf, _box_shape(Vector3(2.0, 2.2, 0.63)), Vector3(0, 1.1, 0))
		if i % 2 == 0:
			_model(shelf, "BoxOpen", "furniture/cardboardBoxOpen.glb", Vector3(-0.6, 2.2, 0.2), 1.8)
			_model(shelf, "BoxClosed", "furniture/cardboardBoxClosed.glb", Vector3(0.4, 2.2, 0.2), 1.8, 20.0)
		var item := _instance(_root, item_names[i], ItemScene)
		item.set("item_id", "whiskey")

	_door("DoorToCity", Vector3(-5.55, 0, 2.8), Vector3.RIGHT, "res://world/City3D.tscn", "SpawnFromShop")
	_marker("SpawnFromCity", Vector3(-4.8, 0, 2.8))
	_marker("SpawnDefault", Vector3(-4.8, 0, 2.8))
	_marker("PoliceSpawn", Vector3(-4.8, 0, 3.4))
	_player_and_hud(Vector3(-4.8, 0, 2.8))
	return _root

# --- Dive Bar ---------------------------------------------------------------

func _build_dive_bar() -> Node3D:
	_new_root("DiveBar3D", "res://world/DiveBar3D.gd")
	_environment(Color(0.55, 0.4, 0.45), 0.4)
	_room_shell(13.0, 8.0, "res://assets/env/floor_wood_dark.png", 0.5)

	# Bar counter along the north wall, back-bar shelves with bottles behind.
	var counter := StaticBody3D.new()
	counter.name = "BarCounter"
	_add(_root, counter)
	counter.position = Vector3(0, 0, -2.2)
	var piece_w := 0.43 * 2.5
	var start_x := -3.2
	var count := 6
	for i in count:
		_model(counter, "Piece%d" % i, "furniture/kitchenBar.glb", Vector3(start_x + i * piece_w, 0, 0), 2.5)
	_model(counter, "EndL", "furniture/kitchenBarEnd.glb", Vector3(start_x - 0.25, 0, 0), 2.5)
	_model(counter, "EndR", "furniture/kitchenBarEnd.glb", Vector3(start_x + count * piece_w, 0, 0), 2.5)
	var counter_len := count * piece_w + 0.5
	_collision(counter, _box_shape(Vector3(counter_len, 1.05, 0.53)), Vector3(start_x - 0.25 + counter_len / 2, 0.52, -0.26))

	var bottle_files := ["food/wine-red.glb", "food/soda-bottle.glb"]
	for i in 3:
		var bx := -2.5 + i * 2.2
		_model(_root, "BackBar%d" % (i + 1), "furniture/bookcaseOpen.glb", Vector3(bx, 0, -3.37), 2.5)
		for j in 4:
			_model(_root, "Bottle%d_%d" % [i + 1, j + 1], bottle_files[(i + j) % 2], Vector3(bx + 0.18 + j * 0.2, 1.12, -3.6), 0.45)
	for i in 4:
		_model(_root, "Stool%d" % (i + 1), "furniture/stoolBar.glb", Vector3(-2.6 + i * 1.6, 0, -1.3), 2.2)

	var bartender := _instance(_root, "Bartender", NPCScene, Vector3(0.0, 0, -3.0))
	bartender.set("npc_name", "Bartender")
	bartender.set("model_path", KENNEY + "characters/character-male-a.glb")
	bartender.set("flavor_lines", "Rough night?\nYou look like hell, you know that.\nDrink first, talk later.\nStill breathing. That's something.")

	# Tables and patrons -- DiveBar3D.gd picks the actual layout.
	var table_names := ["TableA", "TableB", "TableC"]
	for i in 3:
		var table := StaticBody3D.new()
		table.name = table_names[i]
		_add(_root, table)
		_model(table, "Top", "furniture/sideTable.glb", Vector3(-0.66, 0, 0), 2.5)
		_model(table, "Glass", "food/soda-bottle.glb", Vector3(0.3, 0.95, -0.3), 0.4)
		_collision(table, _box_shape(Vector3(1.3, 0.95, 0.55)), Vector3(0, 0.47, -0.27))
		var patron := _instance(_root, "Patron%d" % (i + 1), NPCScene)
		patron.set("is_patron", true)

	# Jukebox, neon sign, dartboard.
	_model(_root, "Jukebox", "furniture/speaker.glb", Vector3(5.8, 0, -3.3), 3.0)
	_light(_root, "LightJukebox", Vector3(5.6, 1.0, -2.8), Color(1.0, 0.45, 0.15), 1.4, 3.0, false)
	_box_mesh(_root, "NeonSign", Vector3(1.8, 0.35, 0.05), Vector3(4.2, 1.9, -3.97), _color_mat(Color(1.0, 0.2, 0.6), 0.4, 4.0))
	var neon_label := Label3D.new()
	neon_label.name = "NeonText"
	neon_label.text = "OPEN LATE"
	neon_label.font_size = 64
	neon_label.pixel_size = 0.004
	neon_label.modulate = Color(0.2, 0.9, 1.0)
	neon_label.outline_size = 0
	_add(_root, neon_label)
	neon_label.position = Vector3(4.2, 2.3, -3.94)
	_light(_root, "LightNeon", Vector3(4.2, 1.9, -3.4), Color(1.0, 0.25, 0.6), 1.5, 4.0, false)
	var dart_mesh := CylinderMesh.new()
	dart_mesh.top_radius = 0.3
	dart_mesh.bottom_radius = 0.3
	dart_mesh.height = 0.05
	dart_mesh.material = _color_mat(Color(0.15, 0.35, 0.15), 0.9)
	var dart := MeshInstance3D.new()
	dart.name = "Dartboard"
	dart.mesh = dart_mesh
	_add(_root, dart)
	dart.position = Vector3(-6.47, 1.5, -1.0)
	dart.rotation_degrees.z = 90.0

	_light(_root, "LightBar", Vector3(0, 2.2, -2.2), Color(1.0, 0.7, 0.4), 2.0, 6.0)
	_light(_root, "LightTables", Vector3(0, 2.2, 1.6), Color(1.0, 0.6, 0.35), 1.6, 7.0)

	_door("DoorToCity", Vector3(6.05, 0, 2.8), Vector3.LEFT, "res://world/City3D.tscn", "SpawnFromBar")
	_marker("SpawnFromCity", Vector3(5.3, 0, 2.8))
	_marker("SpawnDefault", Vector3(5.3, 0, 2.8))
	_player_and_hud(Vector3(5.3, 0, 2.8))
	return _root

# --- City -------------------------------------------------------------------

func _build_city() -> Node3D:
	_new_root("City3D", "res://world/City3D.gd")
	_environment(Color(0.35, 0.4, 0.6), 0.3, true)

	var w := 18.0
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

	# Three buildings: Home, Dive Bar, Shop, plus filler at either end.
	var fronts := [
		{"name": "Home", "file": "city/building-a.glb", "x": -6.0, "sign": "APTS", "color": Color(0.9, 0.85, 0.7),
			"scene": "res://world/Apartment3D.tscn", "door": "DoorToHome", "spawn": "SpawnFromHome"},
		{"name": "Bar", "file": "city/building-b.glb", "x": 0.0, "sign": "BAR", "color": Color(1.0, 0.25, 0.55),
			"scene": "res://world/DiveBar3D.tscn", "door": "DoorToBar", "spawn": "SpawnFromBar"},
		{"name": "Shop", "file": "city/building-d.glb", "x": 6.0, "sign": "24/7 SHOP", "color": Color(0.35, 0.95, 0.5),
			"scene": "res://world/Shop3D.tscn", "door": "DoorToShop", "spawn": "SpawnFromShop"},
	]
	var bscale := 5.0
	for f in fronts:
		var x: float = f["x"]
		_model(_root, f["name"] + "Building", f["file"], Vector3(x, 0, street_z - 0.47 * bscale - 0.05), bscale)
		if f["name"] != "Home":
			_model(_root, f["name"] + "Awning", "city/detail-awning.glb", Vector3(x, 2.0, street_z - 0.4), 5.0)
		var sign := Label3D.new()
		sign.name = f["name"] + "Sign"
		sign.text = f["sign"]
		sign.font_size = 96
		sign.pixel_size = 0.006
		sign.modulate = f["color"]
		sign.outline_modulate = Color(0, 0, 0, 0.8)
		_add(_root, sign)
		sign.position = Vector3(x, 3.1, street_z + 0.02)
		_light(_root, f["name"] + "SignGlow", Vector3(x, 2.8, street_z + 0.8), f["color"], 1.2, 4.0, false)
		var door := _door(f["door"], Vector3(x, 0, street_z + 0.45), Vector3.BACK, f["scene"], "SpawnFromCity")
		door.name = f["door"]
		_marker(f["spawn"], Vector3(x, 0, street_z + 1.5))
	_model(_root, "FillerWest", "city/building-c.glb", Vector3(-11.0, 0, street_z - 2.8), bscale)
	_model(_root, "FillerEast", "city/building-e.glb", Vector3(11.5, 0, street_z - 2.6), bscale)
	_model(_root, "FillerMidA", "city/low-detail-building-a.glb", Vector3(-3.0, 0, street_z - 1.4), 5.0)
	_model(_root, "FillerMidB", "city/low-detail-building-b.glb", Vector3(3.0, 0, street_z - 1.4), 5.0)

	# Sodium streetlights.
	var pole_mat := _color_mat(Color(0.12, 0.12, 0.13), 0.6)
	var light_xs := [-8.5, -3.0, 3.0]
	for i in light_xs.size():
		var sx: float = light_xs[i]
		var sl := StaticBody3D.new()
		sl.name = "Streetlight%d" % (i + 1)
		_add(_root, sl)
		sl.position = Vector3(sx, 0, street_z + 2.7)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.06
		pole.bottom_radius = 0.09
		pole.height = 3.4
		pole.material = pole_mat
		var pmi := MeshInstance3D.new()
		pmi.name = "Pole"
		pmi.mesh = pole
		_add(sl, pmi)
		pmi.position = Vector3(0, 1.7, 0)
		_box_mesh(sl, "Head", Vector3(0.5, 0.12, 0.25), Vector3(0, 3.4, -0.1), _color_mat(Color(1.0, 0.7, 0.3), 0.5, 5.0))
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.15
		cyl.height = 3.4
		_collision(sl, cyl, Vector3(0, 1.7, 0))
		_light(sl, "Light", Vector3(0, 3.2, 0.2), Color(1.0, 0.65, 0.3), 2.5, 7.0)

	# Parked car built from boxes -- City3D.gd picks its paint colour.
	var car := StaticBody3D.new()
	car.name = "Car"
	_add(_root, car)
	car.position = Vector3(1.5, 0, 2.6)
	_box_mesh(car, "Body", Vector3(3.8, 0.7, 1.7), Vector3(0, 0.55, 0), _color_mat(Color(0.5, 0.1, 0.1), 0.35))
	_box_mesh(car, "Cabin", Vector3(2.0, 0.55, 1.5), Vector3(-0.2, 1.15, 0), _color_mat(Color(0.08, 0.1, 0.12), 0.1))
	for wx in [-1.2, 1.2]:
		for wz in [-0.8, 0.8]:
			_box_mesh(car, "Wheel", Vector3(0.6, 0.6, 0.2), Vector3(wx, 0.3, wz), _color_mat(Color(0.03, 0.03, 0.03), 0.9))
	_box_mesh(car, "Headlights", Vector3(0.05, 0.12, 1.3), Vector3(1.91, 0.65, 0), _color_mat(Color(1.0, 0.95, 0.8), 0.3, 2.0))
	_collision(car, _box_shape(Vector3(3.8, 1.4, 1.7)), Vector3(0, 0.7, 0))

	# Hydrant and dumpster.
	var hydrant := StaticBody3D.new()
	hydrant.name = "Hydrant"
	_add(_root, hydrant)
	hydrant.position = Vector3(-4.2, 0, street_z + 2.3)
	var hmesh := CylinderMesh.new()
	hmesh.top_radius = 0.14
	hmesh.bottom_radius = 0.18
	hmesh.height = 0.75
	hmesh.material = _color_mat(Color(0.75, 0.1, 0.08), 0.5)
	var hmi := MeshInstance3D.new()
	hmi.name = "Mesh"
	hmi.mesh = hmesh
	_add(hydrant, hmi)
	hmi.position = Vector3(0, 0.375, 0)
	_collision(hydrant, _box_shape(Vector3(0.4, 0.75, 0.4)), Vector3(0, 0.375, 0))

	_solid(_root, "Dumpster", Vector3(1.8, 1.2, 1.0), Vector3(3.0, 0.6, street_z + 0.6), _color_mat(Color(0.12, 0.28, 0.16), 0.7))

	_marker("SpawnDefault", Vector3(0, 0, street_z + 1.5))
	_player_and_hud(Vector3(0, 0, street_z + 1.5))
	return _root
