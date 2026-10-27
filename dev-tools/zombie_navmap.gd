extends SceneTree
## Dev helper: prints the Dead Block's navmesh against its solids at 2 m:
## '#' walkable, '=' solid (a body at 1 m height), '!' both, '.' neither.
##   godot --headless --path . -s res://dev-tools/zombie_navmap.gd
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	root.get_node("ZombieMode").begin(false)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	var city := current_scene
	var nav := city.get_node("NavRegion") as NavigationRegion3D
	print("polygons ", nav.navigation_mesh.get_polygon_count())
	var map := nav.get_navigation_map()
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	for z in range(10, -104, -2):
		var line := "%4d " % z
		for x in range(-80, 82, 2):
			var p := NavigationServer3D.map_get_closest_point(map, Vector3(x, 0, z))
			var walk := Vector2(p.x - x, p.z - z).length() < 0.3
			var q := PhysicsPointQueryParameters3D.new()
			q.position = Vector3(x, 1.0, z)
			q.collision_mask = 1
			var solid: bool = space.intersect_point(q, 1).size() > 0
			line += "!" if walk and solid else ("#" if walk else ("=" if solid else "."))
		print(line)
	quit()
