extends SceneTree
## Windowed: the warrant team in the game's own light, first person: three policemen at 6, 9 and 12 m (rifle, shotgun,
## SMG), one lead in plates, and a Dock Boys man for comparison -> .pilot/gw_police_*.png
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_police.gd
func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	var out := ProjectSettings.globalize_path("res://.pilot")
	await process_frame
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	change_scene_to_file("res://world/City3D.tscn")
	for i in 40:
		await process_frame
	var block := current_scene.get_node("ZombieBlock")
	while not block.purchases_ready or block.cover == null or block.cover.points.is_empty():
		await process_frame
	block.spawner.enabled = false
	for g in get_nodes_in_group("gangsters"):
		g.free()
	var player := get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(-14.0, 0, 1.2)
	player.set_look(-PI / 2.0, 0.0)
	var specs := [["Police", "grunt", "ar", 6.0, 1.5], ["Police", "grunt", "shotgun", 9.0, -2.0], ["Police", "grunt", "smg", 12.0, 2.5],
		["Police", "heavy", "lmg", 16.0, -1.0], ["Dock Boys", "grunt", "pistol", 5.0, -3.0]]
	for s in specs:
		block.spawner.crew_name = s[0]
		var g = block.spawner.spawn_one(s[1], Vector3(-14.0 + s[3], 0, 1.2 + s[4]), "", s[2])
		g.mode = g.Mode.HOLD
		g.target = player
		g.set_physics_process(false)
		g.global_rotation.y = 0.0
	block.spawner.crew_name = "Police"
	for i in 90:
		zm.health = zm.MAX_HEALTH
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/gw_police_fp.png")
	print("saved police")
	quit(0)
