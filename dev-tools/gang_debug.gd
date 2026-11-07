extends "res://dev-tools/smoke_test_3d.gd"
func _run() -> void:
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	var city := await _load("res://world/City3D.tscn")
	await _frames(240)
	var block := city.get_node("ZombieBlock")
	var sp: Node = block.spawner
	sp.enabled = false
	for g in get_nodes_in_group("gangsters"):
		g.queue_free()
	await _frames(3)
	var player := _player()
	var map: RID = player.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_closest_point(map, player.global_position + Vector3(20, 0, 0))
	var g1 = sp.spawn_one("grunt", p)
	await _frames(3)
	var cover = block.cover
	var pl := player.global_position
	var options: Array = cover.candidates(pl, 30.0, pl, g1.global_position, 10, 7.0, g1.cover_ok)
	var pick := -1
	var hid := 0
	var fireable := 0
	var near_street := []
	for i in cover.points.size():
		var cv2: Dictionary = cover.points[i]
		var pos2: Vector3 = cv2["pos"]
		if Vector2(pos2.x - pl.x, pos2.z - pl.z).length() > 40.0:
			continue
		if g1.CoverMapScript.hides(cv2, pl):
			hid += 1
			if g1._fire_spot(cv2) != Vector3.INF:
				fireable += 1
				near_street.append(pos2)
	print("hide-from-player within 40 m: ", hid, " fireable: ", fireable, " ", near_street.slice(0, 8))
	var tot_low := 0
	for cv3 in cover.points:
		if not cv3["high"] and Vector2(cv3["pos"].x - pl.x, cv3["pos"].z - pl.z).length() < 40.0:
			tot_low += 1
	print("low cover points within 40 m: ", tot_low)
	for o in options:
		var cv: Dictionary = cover.points[o]
		print("  opt ", o, " pos ", cv["pos"], " high ", cv["high"], " dir ", cv["dir"], " fire ", g1._fire_spot(cv), " reach ", cover.reachable(map, g1.global_position, o), " ok ", g1.cover_ok(o))
	print("player ", pl, " head ", g1._player_head())
	for o in options:
		if g1.cover_ok(o) and cover.reachable(map, g1.global_position, o):
			pick = o
			break
	print("options ", options.size(), " pick ", pick, " pos ", cover.points[pick]["pos"] if pick >= 0 else "-")
	g1.go_to_cover(pick)
	var got := false
	for i in 1500:
		await physics_frame
		if g1.is_in_cover():
			got = true
			break
	print("got ", got, " after ", 0, " cover_i ", g1.cover_i, " pick ", pick, " dist ", g1.global_position.distance_to(cover.points[pick]["pos"]), " goal ", g1._goal, " pos ", g1.global_position, " mode ", g1.mode)
	await _frames(20)
	print("later dist ", g1.global_position.distance_to(cover.points[pick]["pos"]), " mode ", g1.mode, " cover_i ", g1.cover_i)
