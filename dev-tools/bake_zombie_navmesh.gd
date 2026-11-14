extends SceneTree
## Bakes the Dead Block's navmesh into res://world/block/zombie_navmesh.res.
##
## The block's own navmesh (dev-tools/city/kit.gd bake_navigation) is made at
## build time from the scene's static bodies, which leaves out what is built
## at load: the buildings' masses (world/Facades.gd) and the wrecks the zombie
## block lays on the roads (world/ZombieBlock.gd). That was fine for the story
## (people walk fixed lines) but zombies path across the whole block, so they
## need the real thing: this loads the block in zombie mode, takes every
## static body on the world or floor layers as it stands at runtime (not the
## barricades: zombies tear their way through those), and bakes from that.
##
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/bake_zombie_navmesh.gd
## Run again whenever the block's solids change (build_rooms_3d.gd, Facades,
## WRECKS).

const OUT := "res://world/block/zombie_navmesh.res"
## The walk-ins' fronts stand on this z (a 0.25 m wall, 4.5..4.75 m up the block's lane); the plug is wider
## than the doorway (1.4 m) and deeper than the wall.
const FRONT_Z := -4.6
const DOOR_PLUG_W := 1.9
const DOOR_PLUG_D := 0.9
## Loaded once the autoloads exist (they are not there while this compiles).
var Kit: GDScript
var Room: GDScript

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	Kit = load("res://dev-tools/city/kit.gd")
	Room = load("res://world/WorldRoot3D.gd")
	root.get_node("ZombieMode").begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	# The scene is in (and _ready has run) by the next frame, before any node has had a _process.
	await process_frame
	var city := current_scene
	if city == null:
		push_error("bake_zombie_navmesh: the city did not load")
		quit(1)
		return
	# The walk-in rooms (world/WalkInShop.gd) build themselves when the player is near, a few steps a frame,
	# so which of them were in when a fixed number of frames had passed was luck, and the mesh came out
	# differently from run to run. The bake wants them all out: a walk-in's footprint stays a solid building
	# (the zombies do not go into shops, and a room that is not built has no floor for them to stand on).
	# Hide the player from them and stop them before their first _process.
	for p in get_nodes_in_group("player"):
		p.remove_from_group("player")
	var shops := _walk_ins(city)
	for shop in shops:
		shop.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 40:
		await process_frame
	var built := shops.filter(func(s): return s.loaded or s._room != null)
	print("walk-ins ", shops.size(), ", built: ", built.size())
	if shops.is_empty() or not built.is_empty():
		push_error("bake_zombie_navmesh: expected every walk-in room to be unbuilt (got %d of %d built)" % [built.size(), shops.size()])
		quit(1)
		return
	var source := NavigationMeshSourceGeometryData3D.new()
	var bodies := 0
	var shapes := 0
	for body in city.find_children("*", "StaticBody3D", true, false):
		var sb := body as StaticBody3D
		if (sb.collision_layer & (1 | 16)) == 0 or sb.is_in_group("barricades"):
			continue
		bodies += 1
		for cs in sb.find_children("*", "CollisionShape3D", false, false):
			var c := cs as CollisionShape3D
			if c.disabled or c.shape == null:
				continue
			if _add(source, c.shape, c.global_transform):
				shapes += 1
	# A walk-in's front has a 1.4 m doorway; with the agent's 0.4 m radius that leaves a 0.6 m passage, which
	# the voxel grid squeezes shut or leaves open by where its origin happens to fall (the grid starts at the
	# geometry's corner, so a moved newsstand opened the Pawn's door). The dead stay out of the shops
	# whatever the grid does: a solid plug in every doorway.
	var Fac: GDScript = load("res://world/Facades.gd")
	var plugs := 0
	for front in Fac.WALK_INS:
		var plug := BoxShape3D.new()
		plug.size = Vector3(DOOR_PLUG_W, 3.0, DOOR_PLUG_D)
		if _add(source, plug, Transform3D(Basis.IDENTITY, Vector3(Fac.walk_in_door_x(front), 1.5, FRONT_Z))):
			plugs += 1
	print("bodies ", bodies, " shapes ", shapes, " doorway plugs ", plugs)
	# The rooms' 0.1 m cells are for 12 m rooms; over the whole block they
	# need gigabytes, and the dead are not that picky.
	var nav_mesh: NavigationMesh = Room.new_nav_mesh()
	nav_mesh.cell_size = 0.2
	nav_mesh.cell_height = 0.2
	nav_mesh.agent_max_climb = 0.2
	var t0 := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source)
	print("baked in ", Time.get_ticks_msec() - t0, " ms: ", nav_mesh.get_polygon_count(), " polygons")
	var err := ResourceSaver.save(nav_mesh, OUT, ResourceSaver.FLAG_COMPRESS)
	print("saved ", OUT, " -> ", err)
	quit()

func _walk_ins(city: Node) -> Array:
	var out := []
	for n in city.find_children("*", "Node3D", true, false):
		var sc := n.get_script() as Script
		if sc != null and sc.resource_path.ends_with("/WalkInShop.gd"):
			out.append(n)
	return out

func _add(source: NavigationMeshSourceGeometryData3D, shape: Shape3D, xf: Transform3D) -> bool:
	if shape is BoxShape3D or shape is CylinderShape3D or shape is CapsuleShape3D or shape is SphereShape3D:
		Kit._add_shape(source, shape, xf)
		return true
	if shape is ConcavePolygonShape3D:
		source.add_faces((shape as ConcavePolygonShape3D).get_faces(), xf)
		return true
	if shape is ConvexPolygonShape3D:
		source.add_faces((shape as ConvexPolygonShape3D).get_debug_mesh().get_faces(), xf)
		return true
	push_warning("bake_zombie_navmesh: skipped " + shape.get_class())
	return false
