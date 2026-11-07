extends "res://dev-tools/smoke_test_3d.gd"
## Ghetto Wars: nobody the player cannot reach or hit. The crew is never put down inside the roadworks' fence (a
## closed pit the navmesh has as an island), chain-link is shot through, cover is never behind it, and the last
## men of a wave who stay out of sight are pushed, shown, and put back on the street if they cannot be got at.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_ghetto_reach.gd
const PIT := Rect2(-70.8, -72.0, 2.6, 4.0)

func _near(player: Node3D, dx: float, dz: float) -> Vector3:
	var p := NavigationServer3D.map_get_closest_point(player.get_world_3d().navigation_map, player.global_position + Vector3(dx, 0, dz))
	return Vector3(p.x, 0.0, p.z)

func _run() -> void:
	await _section("Ghetto Wars: reach")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	zm.begin_gangs()
	var city := await _load("res://world/City3D.tscn")
	await _frames(30)
	var block := city.get_node("ZombieBlock")
	for i in 600:
		if block.purchases_ready and block.cover != null and not block.cover.points.is_empty():
			break
		await physics_frame
	var sp: Node = block.spawner
	sp.enabled = false
	for g in get_nodes_in_group("gangsters"):
		g.queue_free()
	var player := _player()
	var map: RID = player.get_world_3d().navigation_map

	# --- Chain-link
	_check(block.fences_open >= 8, "  the arena's chain-link fences are see-through (%d)" % block.fences_open)
	var pit_fence := city.get_node("Cell_West/WestRoadworks70/Fence2/Solid")
	_check(pit_fence.is_in_group("see_through"), "  the roadworks' fence is one of them")
	var holder := get_first_node_in_group("weapon_holder")
	var through: Dictionary = holder._cast(Vector3(-69.5, 1.2, -66.0), Vector3(0, 0, -1), 3.0)
	_check(through.is_empty(), "  a round goes through the fence (nothing stops it in 3 m)")
	pit_fence.remove_from_group("see_through")
	var stopped: Dictionary = holder._cast(Vector3(-69.5, 1.2, -66.0), Vector3(0, 0, -1), 3.0)
	_check(not stopped.is_empty() and stopped.collider == pit_fence, "  (and without the group the same round stops at the wire)")
	pit_fence.add_to_group("see_through")
	var none: Array[RID] = []
	var GS: GDScript = load("res://npc/Gangster3D.gd")
	_check(GS.first_wall(player.get_world_3d().direct_space_state, Vector3(-69.5, 1.2, -66.0), Vector3(-69.5, 1.2, -73.0), none).is_empty(), "  the crew's eyes and guns look through it too")

	# --- Nobody put down in the pit, nor sent to cover in it.
	var inside := 0
	for p in block.cover.points:
		if PIT.grow(0.5).has_point(Vector2(p["pos"].x, p["pos"].z)):
			inside += 1
	_check(inside == 0, "  no cover spot inside the roadworks' fence (%d)" % inside)
	var made: Array = sp.spawn_wave({"count": 6, "from_points": [Vector3(-71.0, 0, -70.0)]})
	await _frames(3)
	var bad := 0
	for g in made:
		var pp: Vector3 = g.global_position
		if PIT.has_point(Vector2(pp.x, pp.z)) or not sp.reachable(map, pp):
			bad += 1
	_check(made.size() == 6 and bad == 0, "  six men from the spawn point beside the pit: none in it, all with a way to the player (%d bad)" % bad)
	for g in made:
		g.queue_free()
	await _frames(2)

	# --- The last men
	var ls: Node = sp.get_child(sp.get_child_count() - 1)
	for c in sp.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("LastStand.gd"):
			ls = c
	_check(ls != null and ls.has_method("_reveal"), "  the spawner has the last-stand watcher")
	zm.round = 1
	sp.round_no = 1
	sp.total = 1
	sp.released = 1
	var trapped = sp.spawn_one("grunt", Vector3(-69.5, 0, -70.0))
	trapped.global_position = Vector3(-69.5, 0, -70.0)
	await _frames(20)
	_check(PIT.has_point(Vector2(trapped.global_position.x, trapped.global_position.z)), "  (a man set down inside the pit by hand, to be sure)")
	_check(not ls._in_sights(trapped), "  the player has no clear line to him")
	ls.hidden_t = 14.7
	await _frames(40)
	_check(ls.pushed, "  hidden 15 s: the last man is pushed")
	var pp2: Vector3 = trapped.global_position
	_check(not PIT.has_point(Vector2(pp2.x, pp2.z)) and sp.reachable(map, pp2), "  he cannot get to the player from the pit: put back on the street at %s" % [pp2.snapped(Vector3.ONE * 0.1)])
	_check(trapped.mode == trapped.Mode.PUSH, "  and he comes on (mode PUSH)")
	var hud := get_first_node_in_group("zombie_hud")
	ls.hidden_t = 24.7
	await _frames(40)
	_check(ls.reveals >= 1 and hud.ping.marks.size() >= 1, "  hidden 25 s: he shouts and the HUD marks where he is (%d marker)" % hud.ping.marks.size())
	ls.hidden_t = 39.7
	var before: int = ls.relocations
	await _frames(40)
	_check(ls.relocations > before and ls.hidden_t < 20.0, "  hidden 40 s: put back on a spawn point near the player, the clock runs on from the push")
	var seen := false
	for off in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6), Vector2(10, 0), Vector2(-10, 0)]:
		trapped.global_position = _near(player, off.x, off.y)
		if ls._in_sights(trapped):
			seen = true
			break
	await _frames(30)
	_check(seen and ls.hidden_t == 0.0 and not ls.pushed, "  once he is in the player's sights the clock goes back to nothing (%.1f s)" % ls.hidden_t)
	trapped.queue_free()
