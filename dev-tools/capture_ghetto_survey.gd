extends SceneTree
## Dev helper: Ghetto Wars' void survey. Eye-height shots in four directions from spots all over the block, and
## high shots looking down, to .pilot/gw3_survey/NN_name.png (then dev-tools/_tmp or any PIL script makes a sheet).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/capture_ghetto_survey.gd
## `-- raid` runs it with THE BUST dressing on.
const SPOTS := {
	"corner": Vector3(13.6, 0, -1.0), "laundry": Vector3(33.0, 0, 0.5), "mid_west": Vector3(-20.0, 0, 0.5),
	"east_end": Vector3(70.0, 0, 1.0), "west_end": Vector3(-70.0, 0, 1.0), "lot": Vector3(46.0, 0, -60.0),
	"back_st": Vector3(0.0, 0, -91.0), "lane": Vector3(35.0, 0, -17.5), "west_ave": Vector3(-71.0, 0, -40.0),
	"east_ave": Vector3(71.0, 0, -40.0), "in_shop": Vector3(33.3, 0, -6.0), "back_room": Vector3(33.0, 0, -13.0),
}
const HIGH := {
	"high_corner": [Vector3(13.6, 16.0, 9.0), Vector3(13.6, 0, -3.0)], "high_laundry": [Vector3(33.0, 14.0, 8.0), Vector3(33.0, 0, -8.0)],
	"high_lot": [Vector3(46.0, 18.0, -30.0), Vector3(46.0, 0, -60.0)], "high_west": [Vector3(-40.0, 15.0, 8.0), Vector3(-40.0, 0, -4.0)],
}
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var out := ProjectSettings.globalize_path("res://.pilot/gw3_survey")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	root.get_node("ZombieMode").begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40: await process_frame
	var city := current_scene
	var block := city.get_node("ZombieBlock")
	while not block.purchases_ready: await process_frame
	block.spawner.enabled = false
	block.surge.enabled = false
	for z in get_nodes_in_group("zombies"): z.free()
	for c in root.get_children():
		if c is CanvasLayer and c != root.get_node("SceneLoader"): c.visible = false
	for c in city.get_children():
		if c is CanvasLayer: c.visible = false
	get_first_node_in_group("player").global_position = Vector3(-60, 0, 0)
	var set_ := city.get_node("GhettoSet")
	if "raid" in OS.get_cmdline_user_args():
		set_.on_story_beat("raid_start")
		set_.set_chapter("THE BUST")
	var cam := Camera3D.new()
	cam.fov = 80
	cam.far = 500
	city.add_child(cam)
	cam.make_current()
	for i in 40: await process_frame
	var n := 0
	for k in SPOTS:
		for d in 4:
			var yaw := d * 90.0
			cam.global_position = SPOTS[k] + Vector3(0, 1.65, 0)
			cam.rotation_degrees = Vector3(0, yaw, 0)
			for i in 14: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%02d_%s_%d.png" % [out, n, k, d])
			n += 1
	for k in HIGH:
		cam.global_position = HIGH[k][0]
		cam.look_at(HIGH[k][1], Vector3.UP)
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, k])
		n += 1
	print("shot survey ", n)
	quit()
