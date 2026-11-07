extends "res://dev-tools/smoke_test_3d.gd"
## Windowed: the last man hidden for 25 s, his marker on the HUD (.pilot/laststand_*.png).
##   flatpak run org.godotengine.Godot --path . --resolution 1280x720 -s res://dev-tools/capture_laststand.gd
func _shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.pilot/laststand_%s.png" % label))

func _run() -> void:
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	var city := await _load("res://world/City3D.tscn")
	await _frames(30)
	var block := city.get_node("ZombieBlock")
	for i in 900:
		if block.purchases_ready and block.cover != null and not block.cover.points.is_empty():
			break
		await physics_frame
	var sp: Node = block.spawner
	sp.enabled = false
	for g in get_nodes_in_group("gangsters"):
		g.queue_free()
	var player := _player()
	zm.round = 1
	sp.round_no = 1
	sp.total = 1
	sp.released = 1
	var map: RID = player.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, player.global_position + Vector3(-34, 0, -14))
	var g = sp.spawn_one("grunt", p)
	await _frames(20)
	var ls: Node
	for c in sp.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("LastStand.gd"):
			ls = c
	var d: Vector3 = g.global_position - player.global_position
	player.set_look(atan2(-d.x, -d.z), 0.0)
	ls.hidden_t = 24.8
	await _frames(40)
	await _shot("marker_ahead")
	await _frames(120)
	player.set_look(atan2(-d.x, -d.z) + 2.2, 0.0)
	ls.hidden_t = 33.9
	await _frames(40)
	await _shot("marker_side")
	print("hidden %.1f reveals %d pushed %s mode %s" % [ls.hidden_t, ls.reveals, ls.pushed, g.mode])
