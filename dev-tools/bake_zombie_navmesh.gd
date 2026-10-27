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
	for i in 40:
		await process_frame
	var city := current_scene
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
	print("bodies ", bodies, " shapes ", shapes)
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
