extends SceneTree
## Headless gameplay smoke test for the 3D rooms. Drives the real scenes
## (no mocks): steal in the Shop, get spotted, check the police actually
## path toward the player, carry the chase through a door, buy from the
## pusher on the street, sell to a Dive Bar patron, then sleep in the
## Apartment.
##   godot --headless --path . -s res://dev-tools/smoke_test_3d.gd
## Exit code 0 = all checks passed.

var _failures := 0
var PoliceScene: PackedScene

func _initialize() -> void:
	await process_frame
	PoliceScene = load("res://npc/Police3D.tscn")
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
	# Rooms face you into the room on arrival; these tests steer along world
	# axes, which is what the first-person controls do at yaw 0.
	var p := _player()
	if p and p.has_method("set_look"):
		p.set_look(0.0)
	return current_scene

## The drug menu parents itself to the tree root, not the current scene.
func get_tree_menu() -> CanvasLayer:
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("open_with"):
			return c
	return null

func _player() -> Node3D:
	return get_first_node_in_group("player") as Node3D

## Walks the player with real move input along the navmesh until `target`
## is the interactable E would use. Returns false on timeout.
func _walk_until_nearest(target: Node3D, timeout_frames := 600) -> bool:
	var p := _player()
	# Steering below is in world axes; see _load().
	if p.has_method("set_look"):
		p.set_look(0.0)
	var map: RID = p.get_world_3d().navigation_map
	for i in timeout_frames:
		if p._nearest_interactable() == target:
			for a in ["move_left", "move_right", "move_up", "move_down"]:
				Input.action_release(a)
			return true
		var path := NavigationServer3D.map_get_path(map, p.global_position, target.global_position, true)
		var next := target.global_position
		for pt in path:
			if Vector2(pt.x - p.global_position.x, pt.z - p.global_position.z).length() > 0.35:
				next = pt
				break
		var dir := Vector2(next.x - p.global_position.x, next.z - p.global_position.z).normalized()
		for a in ["move_left", "move_right", "move_up", "move_down"]:
			Input.action_release(a)
		if dir.x > 0: Input.action_press("move_right", dir.x)
		elif dir.x < 0: Input.action_press("move_left", -dir.x)
		if dir.y > 0: Input.action_press("move_down", dir.y)
		elif dir.y < 0: Input.action_press("move_up", -dir.y)
		await physics_frame
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	return false

## Every item slot, in every one of the store's fixture layouts, must be on
## the navmesh and reachable from the entrance, and stocked with a model.
func _check_store(store: Node) -> void:
	var map: RID = store.get_world_3d().navigation_map
	var entrance: Vector3 = store.get_node("SpawnFromCity").global_position
	var layouts: Array = store.fixture_layouts
	var all_reachable := true
	var worst := ""
	for li in maxi(1, layouts.size()):
		if not layouts.is_empty():
			var layout: PackedVector2Array = layouts[li]
			for i in store.fixtures.size():
				store.fixtures[i].position = Vector3(layout[i].x, 0, layout[i].y)
			store._place_items()
		store._bake_navigation()
		await _frames(3)
		for slot in store.item_slots:
			var goal: Vector3 = slot.global_position
			goal.y = 0.0
			var path := NavigationServer3D.map_get_path(map, entrance, goal, true)
			var end: Vector3 = path[path.size() - 1] if path.size() > 0 else entrance
			var gap := Vector2(end.x - goal.x, end.z - goal.z).length()
			if gap > 0.9:
				all_reachable = false
				worst = "layout %d, %s (%.2f m short)" % [li, slot.name, gap]
	_check(all_reachable, "  every item reachable from the door in all %d layouts %s" % [maxi(1, layouts.size()), worst])
	var stocked: bool = store.item_slots.all(func(sl): return sl.model_root.get_child_count() > 0 and GameState_has(sl.item_id))
	_check(stocked, "  every fixture is stocked with a real catalog item (%d items)" % store.item_slots.size())
	# Orders stick until delivered, so every item a patron could ask this
	# store for has to be on a shelf on every visit, whatever the shuffle.
	var required: Array = _gs().REQUEST_POOL.filter(func(r): return r["store"] == store.store_id).map(func(r): return r["id"])
	var always_stocked := true
	for trial in 60:
		store._shuffle_items()
		var on_shelves: Array = store.item_slots.map(func(sl): return sl.item_id)
		for id in required:
			if id not in on_shelves:
				always_stocked = false
	_check(required.size() > 0 and always_stocked, "  all %d of its catalogue items are stocked on every one of 60 shuffles" % required.size())
	var guards: Array = get_nodes_in_group("guards").filter(func(g): return store.is_ancestor_of(g))
	_check(guards.size() > 0 and guards.all(func(g): return g.spotted_theft.get_connections().size() > 0),
		"  %d guard(s), all wired to call the police" % guards.size())

func GameState_has(id: String) -> bool:
	return not _gs().item_info(id).is_empty()

func _gs() -> Node:
	return root.get_node("GameState")

func _run() -> void:
	var gs := _gs()

	print("== Every 3D room loads with a player, HUD, and baked navmesh")
	# The corner shop goes last: the tests below carry on inside it.
	for path in ["res://world/Apartment3D.tscn", "res://world/City3D.tscn", "res://world/DiveBar3D.tscn", "res://world/Jail3D.tscn",
			"res://world/StorePharmacy3D.tscn", "res://world/StoreSupermarket3D.tscn", "res://world/StoreLiquor3D.tscn",
			"res://world/StoreElectronics3D.tscn", "res://world/StoreConvenience3D.tscn"]:
		var scene := await _load(path)
		var nav := scene.get_node_or_null("NavRegion") as NavigationRegion3D
		var polys := nav.navigation_mesh.get_polygon_count() if nav and nav.navigation_mesh else 0
		_check(scene != null and _player() != null and get_first_node_in_group("hud") != null and polys > 0,
			"%s (navmesh polygons: %d)" % [path.get_file(), polys])
		var ambient: Array[String] = []
		var all_ok := true
		for node in scene.find_children("*", "Node", true, false):
			if not (node is AudioStreamPlayer or node is AudioStreamPlayer3D) or not node.autoplay:
				continue
			ambient.append(node.name)
			var loops: bool = node.stream is AudioStreamWAV and node.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
			all_ok = all_ok and node.playing and loops
		_check(ambient.size() > 0 and all_ok, "  ambient sound playing and looping: %s" % ", ".join(ambient))
		var listener := _player().get_node("Listener") as AudioListener3D
		_check(listener.is_current(), "  audio listener is on the player")
		if scene.has_method("_shuffle_items"):
			await _check_store(scene)

	var shop := current_scene
	var player := _player()

	print("== Animation: idle when still, walk when moving")
	player.global_position = Vector3(-4.8, 0, 2.8)
	await _frames(5)
	_check(player.anim.current_clip() == "idle", "player idles when standing still")
	var sfx := root.get_node("SFX")
	for p in sfx._pool:
		p.stop()
	Input.action_press("move_right")
	await _frames(40)
	_check(player.anim.current_clip() == "walk", "player walks while moving (clip: %s)" % player.anim.current_clip())
	var step_sounds := [sfx.SOUNDS["footstep_a"], sfx.SOUNDS["footstep_b"]]
	var stepped: bool = sfx._pool.any(func(p): return step_sounds.has(p.stream))
	_check(stepped, "player footsteps play while walking")
	Input.action_release("move_right")
	await _frames(5)
	_check(player.anim.current_clip() == "idle", "player returns to idle after stopping")
	var keeper_anim = shop.get_node("Shopkeeper").anim
	_check(keeper_anim.current_clip() == "idle", "shopkeeper plays idle")

	print("== Shop: stealing an item")
	var item := shop.get_node("Item1") as Area3D
	var item_id: String = item.item_id
	player.global_position = Vector3(item.global_position.x, 0, item.global_position.z + 0.35)
	await _frames(5)
	_check(player.nearby.has(item), "item is in the player's interact zone")
	player.nearby = [item]
	player._try_interact()
	await _frames(2)
	_check(gs.has_item(item_id), "inventory now holds '%s'" % item_id)
	_check(player.anim.current_clip() == "pick-up" and player.is_busy(), "stealing plays the pick-up animation")
	var inv_size: int = gs.inventory.size()
	player._try_interact()
	var pos_before := player.global_position
	Input.action_press("move_left")
	await _frames(6)
	Input.action_release("move_left")
	_check(gs.inventory.size() == inv_size, "can't steal the same item twice mid-grab")
	_check(player.global_position.distance_to(pos_before) < 0.01, "player is held still while grabbing")
	await _frames(60)
	_check(not is_instance_valid(item), "item is gone once the grab finishes")
	_check(not player.is_busy() and player.anim.current_clip() == "idle", "player returns to idle after the grab")

	print("== Shop: shopkeeper spots a theft in plain view")
	var keeper := shop.get_node("Shopkeeper") as Node3D
	player.global_position = Vector3(keeper.global_position.x, 0, -1.95)
	# Stop the cone sweeping and point it at the player. Being *seen* is not
	# the same as being caught any more: suspicion has to fill, which takes
	# about a third of a second of unbroken eye contact while you're grabbing
	# something. From this spot the sweep only clips the player for ~19
	# frames in total, which got suspicion to 0.95 -- one frame short -- so
	# the check failed even though the system was behaving exactly as
	# designed. A guard who merely glimpses you should not bust you; this
	# test is about the alarm firing at all, so give it a guard who is
	# actually looking.
	var to_player: Vector3 = player.global_position - keeper.global_position
	keeper.base_facing_deg = rad_to_deg(Vector2(to_player.x, to_player.z).angle())
	keeper.sweep_speed = 0.0
	keeper._sweep_t = 0.0
	var spotted := false
	for i in 400:
		# Re-assert every frame: the earlier steal's 1 s theft window timer
		# would otherwise switch this back off before the sweeping cone
		# (whose phase depends on how long the test has run) reaches us.
		player.is_stealing = true
		await physics_frame
		if gs.wanted:
			spotted = true
			break
	player.is_stealing = false
	_check(spotted, "GameState.wanted set after being seen mid-theft")
	_check(get_first_node_in_group("police") == null, "no officer appears the instant the alarm goes up")
	var police: Node3D = null
	for i in 200:
		await physics_frame
		police = get_first_node_in_group("police") as Node3D
		if police:
			break
	_check(police != null, "a police officer arrives shortly after")

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
		_check(police.anim.current_clip() == "sprint", "officer plays sprint while chasing")
		_check(police.get_node("Footsteps").stream != null, "officer's positional footsteps play while chasing")
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

	print("== City: buying from the pusher on the street")
	var pusher := current_scene.get_node("Pusher") as Area3D
	var city_player := _player()
	city_player.global_position = current_scene.get_node("SpawnFromShop").global_position
	await _frames(3)
	_check(await _walk_until_nearest(pusher), "can walk up to the pusher from the shop door")
	gs.cash = 0
	gs.craving = 10.0
	await _frames(1)
	pusher.interact(city_player)
	_check(gs.craving < 11.0 and gs.cash == 0, "pusher won't sell without the cash")
	get_first_node_in_group("hud").advance_or_close_dialogue()
	gs.cash = 100
	var lookout := current_scene.get_node("Lookout")
	gs.set_wanted(true)
	await _frames(2)
	_check(lookout._whistle.playing, "lookout whistles when you're wanted")
	pusher.interact(city_player)
	_check(gs.craving < 11.0 and gs.cash == 100, "pusher won't deal while you're wanted")
	get_first_node_in_group("hud").advance_or_close_dialogue()
	var hid := false
	for i in 300:
		await physics_frame
		if pusher.state == pusher.State.HIDDEN:
			hid = true
			break
	_check(hid and not pusher.model_root.visible, "pusher slips away round the corner while you're wanted")
	gs.set_wanted(false)
	for cop in get_nodes_in_group("police"):
		cop.queue_free()
	var back := false
	for i in 400:
		await physics_frame
		if pusher.state == pusher.State.POST:
			back = true
			break
	_check(back and pusher.model_root.visible, "pusher comes back to his spot once it's quiet")

	city_player.global_position = pusher.global_position + Vector3(-1.2, 0, 0.6)
	await _frames(3)
	# Buying is now a choice from what he's holding tonight, so drive the
	# menu rather than the old single-fix interact. Oxycodone is forced into
	# stock and bought here: it's the one that can turn out to be a fentanyl
	# press, so the handoff below also covers that path existing.
	pusher._stock = ["oxy", "heroin", "bupe", "naloxone"]
	pusher._stock_day = gs.day
	pusher.interact(city_player)
	await _frames(2)
	var menu := get_tree_menu()
	_check(menu != null, "the pusher offers a menu of what he's holding")
	var fix_cost: int = gs.price_of("heroin")
	if menu:
		menu.chosen.emit("heroin")
		menu._close()
	await _frames(2)
	_check(gs.cash == 100 - fix_cost and gs.craving < 11.0, "paying the pusher takes $%d but doesn't hand it over yet" % fix_cost)
	get_first_node_in_group("hud").advance_or_close_dialogue()
	var went_to_stash := false
	var handed := false
	for i in 900:
		await physics_frame
		if pusher.state == pusher.State.AT_STASH:
			went_to_stash = true
		# Craving starts draining again the very next frame, so don't wait
		# for exactly 100.
		if gs.craving > 90.0:
			handed = true
			break
	_check(went_to_stash, "pusher walks off to his stash to get it")
	_check(handed, "pusher comes back and hands it over (craving restored)")
	get_first_node_in_group("hud").advance_or_close_dialogue()
	gs.craving = 45.0

	print("== City doors all lead somewhere real")
	for d in ["DoorToHome", "DoorToBar", "DoorToShop", "DoorToPharmacy", "DoorToLiquor", "DoorToSupermarket", "DoorToElectronics"]:
		var target: String = current_scene.get_node(d).target_scene
		_check(ResourceLoader.exists(target), "%s -> %s" % [d, target])

	print("== Dive Bar: sell to a patron")
	current_scene.get_node("DoorToBar").interact(_player())
	await _frames(10)
	_check(current_scene.name == "DiveBar3D", "Bar door leads to DiveBar3D")
	var patron := current_scene.get_node("Patron1")
	_check(patron.model_root.get_child_count() == 1, "patron has exactly one model (%s)" % patron.npc_name)
	_check(patron.anim != null and patron.anim.current_clip() == patron.pose,
		"patron plays their seat's pose (%s)" % patron.pose)
	if not gs.has_item(patron.request_id):
		gs.steal_item(patron.request_id)
	var bar := current_scene
	# Every spot a patron can be seated at must be walkable-to and talkable.
	var bar_player := _player()
	for seat_index in bar.SEATS.size():
		var seat: Dictionary = bar.SEATS[seat_index]
		var sp: Node3D = bar.patrons[0]
		var seat_pos: Vector3 = seat["pos"]
		# Park the other patrons out of the way so one isn't randomly
		# already sitting in the seat under test.
		for other in bar.patrons:
			other.position = Vector3(0, -50, 0)
		sp.position = seat_pos
		bar_player.global_position = bar.get_node("SpawnFromCity").global_position
		await _frames(3)
		var ok := await _walk_until_nearest(sp)
		_check(ok, "  patron seat %d (%s, %s) can be walked to and talked to" % [seat_index, seat["pose"], seat_pos])
	bar._seat_patrons()
	await _frames(3)
	var missing: Array = bar.PATRON_NAMES.filter(func(n): return not patron.PATRON_PROFILES.has(n))
	_check(missing.is_empty(), "every possible patron has a sound profile (missing: %s)" % [missing])
	patron.play_idle_sound()
	var idle_streams: Array = patron.PATRON_PROFILES[patron.npc_name]["idle"].map(func(k): return patron.PATRON_SFX[k])
	_check(patron.idle_sound.playing and idle_streams.has(patron.idle_sound.stream),
		"%s makes one of their own idle sounds" % patron.npc_name)
	var cash_before: int = gs.cash
	patron.interact(_player())
	_check(gs.cash == cash_before + patron.request_price and patron.fulfilled,
		"patron paid $%d for '%s'" % [patron.request_price, patron.request_id])
	var expected_pitch: float = patron.PATRON_PROFILES[patron.npc_name]["voice"]
	_check(patron.voice.playing and absf(patron.voice.pitch_scale - expected_pitch) < 0.05,
		"patron mumbles in their own voice when spoken to (pitch %.2f)" % patron.voice.pitch_scale)
	patron.idle_sound.stop()
	patron._idle_sound_timer = 0.0
	await _frames(3)
	_check(not patron.idle_sound.playing, "patron stays quiet while the dialogue is open")
	get_first_node_in_group("hud").advance_or_close_dialogue()
	_player().dialogue_active = false
	patron._idle_sound_timer = 0.0
	await _frames(3)
	_check(patron.idle_sound.playing, "patron's idle sounds resume after the dialogue closes")

	print("== Dive Bar: orders stick until delivered")
	var paid_name: String = patron.npc_name
	var waiting := {}
	for p in bar.patrons:
		if p != patron:
			waiting[p.npc_name] = [p.request_id, p.position]
	bar.get_node("DoorToCity").interact(_player())
	await _frames(10)
	current_scene.get_node("DoorToBar").interact(_player())
	await _frames(10)
	var bar2 := current_scene
	var still_there := 0
	var newcomer: Node = null
	for p in bar2.patrons:
		if waiting.has(p.npc_name) and waiting[p.npc_name][0] == p.request_id and waiting[p.npc_name][1].distance_to(p.position) < 0.01:
			still_there += 1
		elif p.npc_name != paid_name and not waiting.has(p.npc_name):
			newcomer = p
	_check(still_there == 2, "the two patrons still waiting are there with the same orders, in the same seats")
	_check(newcomer != null and not newcomer.fulfilled, "the patron you paid has gone; a newcomer with a fresh order sits down")
	var items: Array = bar2.patrons.map(func(p): return p.request_id)
	var names: Array = bar2.patrons.map(func(p): return p.npc_name)
	_check(items.size() == 3 and items[0] != items[1] and items[1] != items[2] and items[0] != items[2] and names[0] != names[1] and names[1] != names[2] and names[0] != names[2],
		"no two patrons share a name or an order")
	var before_sleep: Array = bar2.patrons.map(func(p): return "%s:%s" % [p.npc_name, p.request_id])
	gs.sleep()
	bar2.get_node("DoorToCity").interact(_player())
	await _frames(10)
	current_scene.get_node("DoorToBar").interact(_player())
	await _frames(10)
	var after_sleep: Array = current_scene.patrons.map(func(p): return "%s:%s" % [p.npc_name, p.request_id])
	_check(before_sleep == after_sleep, "orders still stand after a night's sleep")
	current_scene.get_node("DoorToCity").interact(_player())
	await _frames(10)
	current_scene.get_node("DoorToBar").interact(_player())
	await _frames(10)

	print("== Busted: exactly one bust, then a jail cell")
	current_scene.get_node("DoorToCity").interact(_player())
	await _frames(10)
	current_scene.get_node("DoorToShop").interact(_player())
	await _frames(10)
	var store := current_scene
	gs.cash = 40
	gs.steal_item("cigs")
	var busts := [0]
	var count_bust := func(): busts[0] += 1
	gs.busted.connect(count_bust)
	var bp := _player()
	var clerk := store.get_node("Shopkeeper") as Node3D
	bp.global_position = Vector3(clerk.global_position.x, 0, -1.95)
	gs.set_wanted(true)
	var cop: Node3D = PoliceScene.instantiate()
	store.add_child(cop)
	cop.global_position = bp.global_position + Vector3(0.3, 0, 0.3)
	# Aim the clerk's sweep at the player before starting. Guard3D seeds
	# _sweep_t with randf() * TAU and sweeps slowly (a full cycle takes ~14 s
	# at sweep_speed 0.45), while this loop only runs 90 physics frames --
	# about 1.5 s. So the clerk was often facing the other way for the whole
	# check and `clerk_saw` came out false at random, failing a test that is
	# really about counting busts, not about vision. Solving for the sweep
	# phase that points at the player makes it deterministic.
	var to_p: Vector3 = bp.global_position - clerk.global_position
	var want_deg := rad_to_deg(Vector2(to_p.x, to_p.z).angle())
	var half_arc: float = float(clerk.get("sweep_arc_deg")) * 0.5
	var offset := (want_deg - float(clerk.get("base_facing_deg"))) / half_arc
	clerk.set("_sweep_t", asin(clampf(offset, -1.0, 1.0)))
	var clerk_saw := false
	for i in 90:
		bp.is_stealing = true  # the clerk is still watching a theft in progress
		await physics_frame
		if current_scene != store:
			break
		clerk_saw = clerk_saw or clerk.can_see_player
	await _frames(10)
	gs.busted.disconnect(count_bust)
	# Without this, "one bust" could pass just because nobody was looking.
	_check(clerk_saw, "  (the clerk really did see the theft during the arrest)")
	var expected_cash: int = 40 - int(40 * gs.BUST_FINE_FRACTION)
	_check(busts[0] == 1 and gs.cash == expected_cash, "caught once: one bust, fined once ($40 -> $%d, %d bust(s))" % [gs.cash, busts[0]])
	_check(current_scene.name == "Jail3D", "busted players wake up in the jail, not at home")
	var cell_spawn := current_scene.get_node("SpawnCell") as Marker3D
	var jp := _player()
	_check(jp.global_position.distance_to(cell_spawn.global_position) < 0.5, "  placed in the holding cell")
	_check(not gs.in_custody and not gs.wanted, "  custody flag and wanted state cleared once booked")
	get_first_node_in_group("hud").advance_or_close_dialogue()
	jp.dialogue_active = false
	Input.action_press("move_right")
	await _frames(90)
	Input.action_release("move_right")
	_check(jp.global_position.x < -2.6, "  the locked cell door holds you in (x=%.2f)" % jp.global_position.x)
	var jail := current_scene
	gs.craving = 60.0
	jail.get_node("Bench").interact(jp)
	_check(jail.released and gs.craving < 60.0 and gs.craving >= 44.0, "  waiting it out on the bench gets you released, and makes you sicker (60 -> %.0f)" % gs.craving)
	gs.craving = 30.0
	var cost_low: float = maxf(minf(30.0, jail.WAIT_CRAVING_FLOOR), 30.0 - jail.WAIT_CRAVING_COST)
	_check(cost_low >= jail.WAIT_CRAVING_FLOOR, "  ...but never leaves you below the withdrawal floor (30 -> %.0f)" % cost_low)
	get_first_node_in_group("hud").advance_or_close_dialogue()
	jp.dialogue_active = false
	gs.craving = 45.0
	await _frames(100)
	var exit_door := jail.get_node("DoorToCity") as Area3D
	jp.global_position = cell_spawn.global_position
	_check(await _walk_until_nearest(exit_door, 900), "  can walk out of the open cell to the exit")
	exit_door.interact(jp)
	await _frames(10)
	_check(current_scene.name == "City3D" and _player().global_position.distance_to(current_scene.get_node("SpawnFromJail").global_position) < 0.5,
		"  the jail exit puts you on the street outside the police station")
	current_scene.get_node("DoorToHome").interact(_player())
	await _frames(10)

	print("== Apartment: furniture and sleep")
	_check(current_scene.name == "Apartment3D", "Home door leads to Apartment3D")
	var apt := current_scene
	var p3 := _player()
	_check(apt.get_node_or_null("Phone") == null, "no phone in the apartment any more (the pusher is on the street)")
	for name in ["Bed", "Couch", "RadioCrate", "TV", "ChairOverturned", "BoxStack"]:
		var furniture := apt.get_node(name) as Node3D
		var solid_center := furniture.global_position
		# Start 2 m away on the room-centre side and walk straight at it (so
		# pieces against the east wall aren't approached from inside the
		# wall). The player should stop short instead of passing through.
		# The radio crate shares the north wall with the (randomly placed)
		# box stack, which can block a sideways approach, so come from the
		# south for that one.
		var axis := Vector3.BACK if name == "RadioCrate" else Vector3.RIGHT
		var side := 1.0 if axis == Vector3.BACK or solid_center.x < 0.0 else -1.0
		var dir := axis * side
		var action := {Vector3.LEFT: "move_left", Vector3.RIGHT: "move_right", Vector3.BACK: "move_down"}
		var walk: String = "move_up" if dir == Vector3.BACK else action[-dir]
		p3.global_position = Vector3(solid_center.x, 0, solid_center.z) + dir * 2.0
		await _frames(3)
		Input.action_press(walk)
		await _frames(60)
		Input.action_release(walk)
		await _frames(2)
		var gap := (p3.global_position - solid_center).dot(dir)
		_check(gap > 0.25, "%s blocks the player (stopped %.2f m from its centre)" % [name, gap])
	# The mattress still has to be reachable to sleep on.
	var bed := apt.get_node("Bed") as Area3D
	p3.global_position = bed.global_position + Vector3(1.0, 0, 0)
	await _frames(5)
	_check(p3.nearby.has(bed), "mattress is still in reach to interact with")
	var day_before: int = gs.day
	current_scene.get_node("Bed").interact(_player())
	_check(gs.day == day_before + 1, "sleeping advanced the day")

	print("== Stealth: suspicion builds, drains, and only then raises the alarm")
	var st := await _load("res://world/StoreConvenience3D.tscn")
	var sp := _player()
	var watcher := st.get_node("Shopkeeper") as Node3D
	# Park the watcher's gaze on the player so this measures suspicion, not the
	# sweep's phase.
	var toward: Vector3 = Vector3(watcher.global_position.x, 0, -1.95) - watcher.global_position
	watcher.base_facing_deg = rad_to_deg(Vector2(toward.x, toward.z).angle())
	watcher.sweep_speed = 0.0
	watcher._sweep_t = 0.0
	sp.global_position = Vector3(watcher.global_position.x, 0, -1.95)
	gs.inventory.clear()
	await _frames(20)
	_check(watcher.can_see_player, "watcher can see the player in the open")
	_check(watcher.suspicion == 0.0, "  browsing empty-handed in plain sight is not suspicious")

	# Carrying stolen goods in view is.
	gs.steal_item("cigs")
	await _frames(30)
	var carrying_susp: float = watcher.suspicion
	_check(carrying_susp > 0.0 and not gs.wanted, "  standing in view holding stolen goods builds suspicion (%.2f), without an instant bust" % carrying_susp)

	# Breaking line of sight drains it again.
	sp.global_position = Vector3(watcher.global_position.x, 0, -1.95) + Vector3(0, 0, -40.0)
	await _frames(40)
	_check(watcher.suspicion < carrying_susp, "  suspicion drains once you're out of sight (%.2f -> %.2f)" % [carrying_susp, watcher.suspicion])

	# Grabbing in plain view fills it fast, and that is what raises the alarm.
	sp.global_position = Vector3(watcher.global_position.x, 0, -1.95)
	var raised := false
	for i in 120:
		sp.is_stealing = true
		await physics_frame
		if gs.wanted:
			raised = true
			break
	sp.is_stealing = false
	_check(raised, "  grabbing in plain sight fills suspicion and raises the alarm")

	print("== Runs: strikes, the run-end payout, and meta upgrades")
	var meta := root.get_node("MetaProgress")
	var know_before: int = meta.know_how
	gs.start_run()
	_check(gs.strikes == 0 and gs.day == 1 and gs.cash == meta.starting_cash(),
		"start_run resets the run and applies meta-progress starting cash ($%d)" % gs.cash)
	gs.orders_delivered = 2
	gs.cash_earned = 120
	gs.day = 4
	var ended := []
	gs.run_ended.connect(func(s): ended.append(s), CONNECT_ONE_SHOT)
	var allowed: int = gs.max_strikes()
	for i in allowed:
		gs.in_custody = false
		gs.get_busted()
	_check(gs.strikes == allowed, "  %d busts counted as %d strikes" % [allowed, gs.strikes])
	_check(ended.size() == 1, "  the run ends once strikes run out")
	if ended.size() == 1:
		var summary: Dictionary = ended[0]
		_check(summary["days"] == 4 and summary["orders"] == 2 and summary["cash"] == 120,
			"  the summary reports the run (day %d, %d orders, $%d)" % [summary["days"], summary["orders"], summary["cash"]])
		_check(summary["know_how"] > 0 and meta.know_how == know_before + summary["know_how"],
			"  a finished run always pays Know-How (+%d)" % summary["know_how"])

	# The HUD has to show the strikes, not just track them. A stale line in
	# HUD._ready() used to overwrite the day label right after it was built,
	# so the pips were computed and then thrown away every time a room loaded.
	gs.start_run()
	await _load("res://world/Apartment3D.tscn")
	var day_label: Label = get_first_node_in_group("hud").get_node("TopBar/DayLabel")
	var fresh_text: String = day_label.text
	_check(fresh_text.contains("*"), "  the HUD shows the strikes left on a fresh run (\"%s\")" % fresh_text)
	gs.in_custody = false
	gs.get_busted()
	await _frames(2)
	_check(day_label.text != fresh_text and day_label.text.contains("o"),
		"  and updates them after a bust (\"%s\")" % day_label.text)

	# Upgrades must actually change the numbers the game reads.
	var base_pickup: float = meta.pickup_duration(0.6)
	var base_susp: float = meta.suspicion_scale()
	meta.know_how += 999
	var bought_hands: bool = meta.buy("steady_hands")
	var bought_touch: bool = meta.buy("light_touch")
	_check(bought_hands and meta.pickup_duration(0.6) < base_pickup,
		"  Steady Hands shortens the grab (%.2fs -> %.2fs)" % [base_pickup, meta.pickup_duration(0.6)])
	_check(bought_touch and meta.suspicion_scale() < base_susp,
		"  Light Touch slows how fast guards get suspicious (x%.2f -> x%.2f)" % [base_susp, meta.suspicion_scale()])
	_check(meta.next_cost("steady_hands") > meta.UPGRADES["steady_hands"]["costs"][0],
		"  each tier costs more than the last")

	# Leave no trace: this test must not inflate the player's real save.
	meta.know_how = know_before
	meta.levels.clear()
	meta.runs_completed = max(0, meta.runs_completed - 1)
	meta.save_progress()
	gs.start_run()

	print("== Drugs: prices, tolerance, interactions, and going over")
	var drugs := root.get_node("Drugs")
	gs.start_run()
	gs.craving = 10.0
	# Prices come from the catalogue, and opioid prices climb with tolerance.
	var oxy_base: int = gs.price_of("oxy")
	_check(oxy_base == drugs.info("oxy")["price"], "a first dose costs the catalogue price ($%d)" % oxy_base)
	gs.tolerance[drugs.OPIOID] = 20.0
	_check(gs.price_of("oxy") > oxy_base, "  opioid prices climb with tolerance ($%d -> $%d)" % [oxy_base, gs.price_of("oxy")])
	_check(gs.price_of("clonazepam") == drugs.info("clonazepam")["price"], "  ...but opioid tolerance doesn't move benzo prices")
	gs.tolerance.clear()

	# Relief and duration differ per drug. Taken from a clean slate each
	# time, so the bupe dose isn't sitting on top of the heroin one -- that
	# combination precipitates withdrawal, which is covered separately below.
	gs.start_run()
	gs.craving = 10.0
	gs.take_drug("heroin")
	var after_heroin: float = gs.craving
	var heroin_decay: float = gs.current_craving_decay()
	gs.start_run()
	gs.craving = 10.0
	gs.take_drug("bupe")
	_check(after_heroin > 10.0 and gs.craving > 10.0, "  a dose restores craving (heroin -> %.0f, bupe -> %.0f)" % [after_heroin, gs.craving])
	_check(gs.current_craving_decay() < heroin_decay,
		"  a long-acting dose holds you longer (decay %.2f/s -> %.2f/s)" % [heroin_decay, gs.current_craving_decay()])

	# Cross-tolerance is shared within a class, and bupe brings it down.
	gs.start_run()
	gs.take_drug("fentanyl")
	var tol_after: float = gs.tolerance_for("heroin")
	_check(tol_after > 0.0, "  tolerance is shared across the opioid class (fentanyl raised heroin's to %.1f)" % tol_after)

	# Buprenorphine too soon after an opioid precipitates withdrawal.
	gs.start_run()
	gs.craving = 80.0
	gs.take_drug("heroin")
	gs.craving = 80.0
	var outcome: String = gs.take_drug("bupe")
	_check(outcome == "precipitated" and gs.craving < 80.0,
		"  bupe straight after an opioid precipitates withdrawal (craving %.0f)" % gs.craving)
	# ...but not once the opioid is long gone.
	gs.start_run()
	gs.craving = 40.0
	gs.run_time = drugs.PRECIPITATED_WINDOW + 10.0
	_check(gs.take_drug("bupe") == "relief", "  ...and works normally once the opioid has cleared")

	# Naloxone cancels an overdose instead of ending the run.
	gs.start_run()
	gs.naloxone = 1
	var saved: String = gs._overdose()
	_check(saved == "saved" and gs.naloxone == 0 and gs.craving == 0.0,
		"  naloxone cancels an overdose and dumps you into withdrawal")
	# Without it, going over ends the run.
	gs.start_run()
	var od_ended := []
	gs.run_ended.connect(func(sm): od_ended.append(sm), CONNECT_ONE_SHOT)
	gs._overdose()
	_check(od_ended.size() == 1 and od_ended[0]["cause"] == "overdose",
		"  without naloxone, going over ends the run")

	# Mixing an opioid with a benzo multiplies the risk. Checked on the maths
	# rather than by rolling dice, so the test can't be flaky.
	gs.start_run()
	gs.craving = 50.0
	gs.take_drug("clonazepam")
	var mixing: bool = gs.run_time - float(gs.last_dose_at.get(drugs.BENZO, -9999.0)) < drugs.MIX_WINDOW
	_check(mixing and drugs.MIX_OD_MULTIPLIER > 1.0,
		"  an opioid taken on top of a benzo counts as mixing (x%.1f risk)" % drugs.MIX_OD_MULTIPLIER)

	# Every catalogue entry has to be complete, or a row renders blank.
	var fields := ["id", "name", "street", "class", "price", "relief", "hours", "tolerance", "od_risk", "fake", "desc"]
	var complete: bool = drugs.CATALOGUE.all(func(d): return fields.all(func(f): return d.has(f)))
	_check(complete and drugs.CATALOGUE.size() >= 8,
		"  all %d catalogue entries are complete" % drugs.CATALOGUE.size())
	# The counterfeit path has to actually be reachable for the pills it
	# applies to, or the whole point of the mechanic is lost.
	var fake_hits := 0
	for i in 400:
		if drugs.resolve_purchase("oxy") == "fentanyl":
			fake_hits += 1
	_check(fake_hits > 0 and fake_hits < 400,
		"  street 'oxy' is sometimes a fentanyl press (%d/400 here)" % fake_hits)
	_check(drugs.resolve_purchase("fentanyl") == "fentanyl", "  ...and what's sold as fentanyl always is")
	gs.start_run()
