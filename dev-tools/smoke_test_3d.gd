extends SceneTree
## Headless gameplay smoke test for the 3D rooms. Drives the real scenes
## (no mocks): steal in the Shop, get spotted, check the police actually
## path toward the player, carry the chase through a door, sell to a Dive Bar
## patron, then buy a fix and sleep in the Apartment.
##   godot --headless --path . -s res://dev-tools/smoke_test_3d.gd
## Exit code 0 = all checks passed.

var _failures := 0

func _initialize() -> void:
	await _run()
	print("\n%s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _load(path: String) -> Node:
	change_scene_to_file(path)
	await _frames(10)
	return current_scene

func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D

func _gs() -> Node:
	return root.get_node("GameState")

func _run() -> void:
	var gs := _gs()

	print("== Every 3D room loads with a player, HUD, and baked navmesh")
	for path in ["res://world/Apartment3D.tscn", "res://world/City3D.tscn", "res://world/DiveBar3D.tscn", "res://world/Shop3D.tscn"]:
		var scene := await _load(path)
		var nav := scene.get_node_or_null("NavRegion") as NavigationRegion3D
		var polys := nav.navigation_mesh.get_polygon_count() if nav and nav.navigation_mesh else 0
		_check(scene != null and _player() != null and get_first_node_in_group("hud") != null and polys > 0,
			"%s (navmesh polygons: %d)" % [path.get_file(), polys])

	print("== Shop: stealing an item")
	var shop := current_scene
	var player := _player()
	var item := shop.get_node("ItemA") as Area3D
	var item_id: String = item.item_id
	player.global_position = Vector3(item.global_position.x, 0, item.global_position.z + 0.35)
	await _frames(5)
	_check(player.nearby.has(item), "item is in the player's interact zone")
	player.nearby = [item]
	player._try_interact()
	await _frames(2)
	_check(gs.has_item(item_id), "inventory now holds '%s'" % item_id)

	print("== Shop: shopkeeper spots a theft in plain view")
	var keeper := shop.get_node("Shopkeeper") as Node3D
	player.global_position = Vector3(keeper.global_position.x, 0, -1.95)
	player.is_stealing = true
	var spotted := false
	for i in 400:
		await physics_frame
		if gs.wanted:
			spotted = true
			break
	player.is_stealing = false
	_check(spotted, "GameState.wanted set after being seen mid-theft")
	var police := get_first_node_in_group("police") as Node3D
	_check(police != null, "a police officer spawned")

	if police:
		print("== Police: chases along the navmesh")
		player.global_position = Vector3(4.5, 0, 3.0)
		await _frames(3)
		var start_dist := police.global_position.distance_to(player.global_position)
		# Hold the player still (dialogue freeze) so only the officer moves.
		player.dialogue_active = true
		var closed_in := false
		for i in 90:
			await physics_frame
			if police.global_position.distance_to(player.global_position) < start_dist - 1.0:
				closed_in = true
				break
		player.dialogue_active = false
		_check(closed_in, "officer closed at least 1 m on the player (started %.1f m away)" % start_dist)

	print("== Door: chase follows the player into the City")
	var door := shop.get_node("DoorToCity")
	door.interact(player)
	await _frames(10)
	_check(current_scene.name == "City3D", "Shop door leads to City3D")
	var spawn := current_scene.get_node("SpawnFromShop") as Marker3D
	_check(_player().global_position.distance_to(spawn.global_position) < 0.5, "player placed at SpawnFromShop")
	_check(get_first_node_in_group("police") != null and gs.wanted, "officer respawned in the City while still wanted")
	gs.set_wanted(false)
	for p in get_nodes_in_group("police"):
		p.queue_free()

	print("== City doors all lead somewhere real")
	for d in ["DoorToHome", "DoorToBar", "DoorToShop"]:
		var target: String = current_scene.get_node(d).target_scene
		_check(ResourceLoader.exists(target), "%s -> %s" % [d, target])

	print("== Dive Bar: sell to a patron")
	current_scene.get_node("DoorToBar").interact(_player())
	await _frames(10)
	_check(current_scene.name == "DiveBar3D", "Bar door leads to DiveBar3D")
	var patron := current_scene.get_node("Patron1")
	_check(patron.model_root.get_child_count() > 0, "patron has a model (%s)" % patron.npc_name)
	if not gs.has_item(patron.request_id):
		gs.steal_item(patron.request_id)
	var cash_before: int = gs.cash
	patron.interact(_player())
	_check(gs.cash == cash_before + patron.request_price and patron.fulfilled,
		"patron paid $%d for '%s'" % [patron.request_price, patron.request_id])
	get_first_node_in_group("hud").advance_or_close_dialogue()
	_player().dialogue_active = false

	print("== Apartment: buy a fix and sleep")
	current_scene.get_node("DoorToCity").interact(_player())
	await _frames(10)
	current_scene.get_node("DoorToHome").interact(_player())
	await _frames(10)
	_check(current_scene.name == "Apartment3D", "Home door leads to Apartment3D")
	gs.cash = 100
	gs.craving = 10.0
	current_scene.get_node("Phone").interact(_player())
	_check(gs.craving > 50.0, "phone fix restored craving (now %.0f)" % gs.craving)
	get_first_node_in_group("hud").advance_or_close_dialogue()
	var day_before: int = gs.day
	current_scene.get_node("Bed").interact(_player())
	_check(gs.day == day_before + 1, "sleeping advanced the day")
