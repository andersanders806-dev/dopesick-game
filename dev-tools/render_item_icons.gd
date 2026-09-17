extends SceneTree
## Renders a HUD icon for every item in GameState.REQUEST_POOL from the same
## primitive model the shelves use (items/ItemModels.gd), on a transparent
## background, into assets/icons/item_<id>.png. Needs a display (not
## --headless):
##   godot --path . -s res://dev-tools/render_item_icons.gd

const ItemModels := preload("res://items/ItemModels.gd")
const SIZE := 96

func _initialize() -> void:
	# Autoloads (GameState) are only in the tree once the main loop starts.
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/icons"))
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.current = true
	for entry in root.get_node("GameState").REQUEST_POOL:
		var id: String = entry["id"]
		var model := ItemModels.build(id)
		vp.add_child(model)
		var aabb := _aabb(model)
		var center := aabb.get_center()
		var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		cam.size = extent * 1.35
		cam.position = center + Vector3(0.6, 0.55, 1.0).normalized() * 3.0
		cam.look_at(center)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "res://assets/icons/item_%s.png" % id
		vp.get_texture().get_image().save_png(path)
		print("rendered ", path)
		model.queue_free()
		await process_frame
	quit()

func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
