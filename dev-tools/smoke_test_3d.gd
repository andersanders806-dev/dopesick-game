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
	# Don't touch the player's progress, settings or saved run.
	Engine.set_meta("sandbox", true)
	await process_frame
	# A quiet day every day unless a check asks for something else.
	root.get_node("Headlines").forced = "quiet"
	root.get_node("Headlines").roll(root.get_node("GameState").day)
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
	# Freeze the clock at 17:00: every store, the bar, and the pusher are
	# open, and nothing closes while the checks below run. The day/night
	# section at the end moves it deliberately.
	gs.clock_running = false
	gs.clock = 17 * 60

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
			var loops: bool = (node.stream is AudioStreamWAV and node.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD) \
				or (node.stream is AudioStreamOggVorbis and node.stream.loop)
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
	var step_sounds: Array = sfx.FOOTSTEPS["concrete"] + sfx.FOOTSTEPS["wood"]
	var stepped: bool = sfx._pool.any(func(p): return step_sounds.has(p.stream))
	_check(stepped, "player footsteps play while walking")
	Input.action_release("move_right")
	# Stopping eases out over about a sixth of a second (Player3D.DECEL).
	await _frames(15)
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
	# The beat cop gets his own section; here he'd just chase the pusher off.
	_clear_patrol(current_scene)
	var pusher := current_scene.get_node("Pusher") as Area3D
	await _until_pusher_on_post(pusher)
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
	# Spoken aloud by Voice (Piper), generated on first use if need be.
	var voice := root.get_node("Voice")
	var waited_voice := 0
	while not voice.is_speaking() and waited_voice < 240:
		await _frames(5)
		waited_voice += 5
	_check(voice.is_speaking(), "patron says it out loud in their own voice (Piper speaker %d)" % voice.cast_for(patron.npc_name)["id"])
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
	gs.clock = 17 * 60  # sleep wakes you at 08:00, before the bar opens
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
	gs.clock = 23 * 60
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
	await _day_night_checks(gs)
	await _withdrawal_checks(gs)
	await _debt_checks(gs)
	await _street_checks(gs)
	await _places_checks(gs)
	await _walkman_checks(gs)
	await _pool_checks(gs)
	await _darts_checks(gs)
	await _menu_and_save_checks(gs)
	await _recovery_checks(gs)
	await _regulars_checks(gs)
	await _round4_checks(gs)
	await _street_life_checks(gs)
	await _kart_checks(gs)
	await _headline_checks(gs)
	await _rep_checks(gs)
	await _hustle_checks(gs)
	await _search_checks(gs)
	await _sick_world_checks(gs)
	gs.start_run()

func _day_night_checks(gs: Node) -> void:
	print("== Day and night: the clock, opening hours, shifts, and the pusher's hours")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 23 * 60 + 59
	var day_before: int = gs.day
	gs.advance_clock(2.0)
	_check(gs.day == day_before + 1 and int(gs.clock) == 1, "  midnight rolls the clock into the next day (%s)" % gs.clock_text())
	gs.sleep()
	_check(gs.day == day_before + 1 and gs.clock_text() == "08:00", "  sleeping after midnight wakes you at 08:00 the same day")
	gs.clock = 2 * 60
	var night_light: float = gs.daylight()
	var night_alert: float = gs.staff_alertness()
	gs.clock = 13 * 60
	_check(night_light == 0.0 and gs.daylight() == 1.0, "  daylight is 0 at 02:00 and 1 at 13:00")
	_check(night_alert < gs.staff_alertness(), "  the graveyard shift is less alert than the midday rush (x%.2f vs x%.2f)" % [night_alert, gs.staff_alertness()])

	gs.clock = 23 * 60 + 30
	var city := await _load("res://world/City3D.tscn")
	city.get_node("DoorToPharmacy").interact(_player())
	await _frames(5)
	_check(current_scene.name == "City3D", "  the pharmacy is locked at 23:30")
	current_scene.get_node("DoorToShop").interact(_player())
	await _frames(10)
	_check(current_scene.name == "StoreConvenience3D", "  ...but the 24/7 shop lets you in")

	gs.clock = 9 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var pusher := city.get_node("Pusher")
	_check(pusher.state == pusher.State.OFF_SHIFT and not pusher.model_root.visible, "  no pusher on the corner at 09:00")
	gs.clock = 16 * 60 + 30
	await _frames(240)
	_check(pusher.state != pusher.State.OFF_SHIFT and pusher.model_root.visible, "  he's back on his spot by 16:30")

	gs.clock = 14 * 60
	var market := await _load("res://world/StoreSupermarket3D.tscn")
	_check(market.get_node_or_null("Stocker") != null, "  a stocker works the supermarket floor at 14:00")
	gs.clock = 21 * 60
	market = await _load("res://world/StoreSupermarket3D.tscn")
	await _frames(2)
	_check(not is_instance_valid(market.get_node_or_null("Stocker")), "  ...and has gone home by 21:00")

	gs.clock = 20 * 60 + 59
	var pharmacy := await _load("res://world/StorePharmacy3D.tscn")
	gs.clock = 21 * 60 + 1
	await _frames(20)
	var hud := current_scene.get_tree().get_first_node_in_group("hud")
	_check(current_scene == pharmacy and hud.dialogue_panel.visible, "  staff tell you they're closing at 21:00")
	var waited := 0
	while (current_scene == null or current_scene.name != "City3D") and waited < 60 * 8:
		await _frames(10)
		waited += 10
	_check(current_scene != null and current_scene.name == "City3D", "  ...and you're shown out onto the street")

func _withdrawal_checks(gs: Node) -> void:
	print("== Withdrawal: the senses, the hands, the cramps, and things that aren't there")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	var shop := await _load("res://world/StoreConvenience3D.tscn")
	var p := _player()
	var sfx := root.get_node("SFX")
	gs.craving = 60.0
	_check(gs.sickness() == 0.0, "  no sickness with the meter at 60")
	var well_grab: float = p.play_pickup(p.global_position + Vector3.FORWARD)
	await _frames(60)
	gs.craving = 0.0
	gs.craving_changed.emit(0.0)
	_check(gs.sickness() == 1.0, "  full sickness with the meter empty")
	var hud := shop.get_tree().get_first_node_in_group("hud")
	var shader_s: float = (hud.get_node("PostFX").material as ShaderMaterial).get_shader_parameter("sickness")
	_check(shader_s == 1.0, "  the screen effects get the sickness level")
	var sick_grab: float = p.play_pickup(p.global_position + Vector3.FORWARD)
	_check(sick_grab > well_grab * 1.4, "  shaking hands make a grab slower (%.2fs -> %.2fs)" % [well_grab, sick_grab])
	await _frames(90)
	var base: Transform3D = p._camera_base
	await _frames(5)
	_check(not p.camera.transform.is_equal_approx(base), "  the camera shakes")
	p._cramp_timer = 0.01
	await _frames(3)
	_check(p.is_busy(), "  a cramp doubles you over and roots you in place")
	await _frames(90)
	for kind in ["siren", "whistle", "steps", "knock", "voice"]:
		sfx.play_phantom(kind)
	await _frames(2)
	var phantoms := shop.get_tree().get_nodes_in_group("phantom_sounds")
	var dist := INF
	for ph in phantoms:
		dist = minf(dist, ph.global_position.distance_to(p.global_position))
	_check(phantoms.size() == 5 and dist >= 3.9, "  phantom sounds play a few metres away (%d, nearest %.1f m)" % [phantoms.size(), dist])
	gs.craving = 60.0  # well again, so no new ones start while we wait
	await _frames(60 * 6)
	_check(shop.get_tree().get_nodes_in_group("phantom_sounds").is_empty(), "  ...and clean up after themselves")
	gs.craving = 60.0

## If the beat cop had already sent him into hiding before we cleared him.
func _until_pusher_on_post(pusher: Node) -> void:
	var waited := 0
	while pusher.state != pusher.State.POST and waited < 900:
		await _frames(10)
		waited += 10

func _clear_patrol(city: Node) -> void:
	for cop in city.get_tree().get_nodes_in_group("patrol"):
		cop.remove_from_group("patrol")
		cop.queue_free()
	city.set("_patrol_timer", 99999.0)

func _debt_checks(gs: Node) -> void:
	print("== Debt: fronting, paying back, and the collector")
	# An earlier section can leave a drug menu open on the root.
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("open_with"):
			c.free()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	gs.cash = 2
	gs.craving = 60.0
	var city := await _load("res://world/City3D.tscn")
	# No beat cop for this section: he'd send the pusher into hiding.
	_clear_patrol(city)
	var pusher := city.get_node("Pusher")
	await _until_pusher_on_post(pusher)
	var p := _player()
	p.global_position = pusher.global_position + Vector3(-1.2, 0, 0.6)
	await _frames(5)
	pusher.interact(p)
	await _frames(2)
	var menu := get_tree_menu()
	var front_buttons := []
	if menu:
		for b in menu.find_children("*", "Button", true, false):
			if b.text.begins_with("Front") and not b.disabled:
				front_buttons.append(b)
	_check(front_buttons.size() > 0, "  short on cash, he offers to front you something (%d options)" % front_buttons.size())
	if front_buttons.is_empty():
		return
	front_buttons[0].pressed.emit()
	await _frames(2)
	_check(gs.debt > 0 and gs.cash == 2, "  fronted: you owe him $%d and kept your cash" % gs.debt)
	_check(absf(gs.debt_due - gs.now_minutes() - gs.DEBT_GRACE_MINUTES) < 1.0, "  ...due back in 24 hours (%s)" % gs.debt_due_text())
	var hud := city.get_tree().get_first_node_in_group("hud")
	_check(hud.debt_label.visible and hud.debt_label.text.contains("$%d" % gs.debt), "  the HUD shows what you owe (\"%s\")" % hud.debt_label.text)
	var waited := 0
	while pusher.state != pusher.State.AWAIT_BUYER and waited < 1200:
		await _frames(10)
		waited += 10
	p.dialogue_active = false
	p.global_position = pusher.global_position + Vector3(-1.0, 0, 0.5)
	await _frames(20)
	_check(pusher.state in [pusher.State.HANDOFF, pusher.State.POST], "  ...and still hands it over")
	_check(gs.can_front(10) == false, "  only one front at a time")

	var debt_before: int = gs.debt
	gs.cash = 5
	# A dollar, so there's always some left for the collector to come for.
	_check(gs.pay_debt(1) == 1 and gs.debt == debt_before - 1, "  paying some back brings the debt down")

	# Overdue, broke: the collector comes.
	gs.cash = 0
	gs.debt_due = gs.now_minutes() - 1.0
	var hud2 = hud
	p.dialogue_active = false
	hud2.dialogue_panel.visible = false
	p.global_position = Vector3(18.0, 0, 1.0)
	waited = 0
	while city.get_tree().get_first_node_in_group("collector") == null and waited < 600:
		await _frames(10)
		waited += 10
	var collector := city.get_tree().get_first_node_in_group("collector") as Node3D
	_check(collector != null, "  overdue, and the collector turns up on the block")
	var owed: int = gs.debt
	var craving_before: float = gs.craving
	waited = 0
	while is_instance_valid(collector) and gs.debt == owed and waited < 900:
		await _frames(10)
		waited += 10
	_check(gs.debt == owed + gs.LATE_FEE, "  broke when he catches you: a late fee on top ($%d -> $%d)" % [owed, gs.debt])
	_check(gs.craving < craving_before and gs.is_hurt(), "  ...and a beating: sicker, and limping")
	_check(not gs.debt_overdue(), "  ...and until tomorrow to find it")
	gs.debt_due = gs.now_minutes() - 1.0
	pusher.state = pusher.State.POST
	p.dialogue_active = false
	pusher.interact(p)
	await _frames(2)
	_check(get_tree_menu() == null and hud2.text_label.text.contains("owe"), "  overdue, the pusher won't sell you anything")
	gs.start_run()

func _street_checks(gs: Node) -> void:
	print("== Street life: passersby, Ray, and the beat cop")
	for c in root.get_children():
		if c is CanvasLayer and (c.has_method("open_with") or c.has_method("open")):
			c.free()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	var city := await _load("res://world/City3D.tscn")
	var day_walkers := city.get_tree().get_nodes_in_group("pedestrians").size()
	gs.clock = 2 * 60
	city = await _load("res://world/City3D.tscn")
	var night_walkers := city.get_tree().get_nodes_in_group("pedestrians").size()
	_check(day_walkers > night_walkers and night_walkers >= 1, "  busier by day than at night (%d vs %d passersby)" % [day_walkers, night_walkers])
	var walker := city.get_tree().get_nodes_in_group("pedestrians")[0] as Node3D
	var x0 := walker.global_position.x
	await _frames(30)
	_check(is_instance_valid(walker) and absf(walker.global_position.x - x0) > 0.3, "  passersby actually walk the block")

	# Ray: gifts earn trust; trust earns tips.
	var ray := city.get_node("Ray")
	var p := _player()
	var hud := city.get_tree().get_first_node_in_group("hud")
	gs.cash = 10
	ray._on_choice(2, p, hud)
	var cold_tip: String = hud.text_label.text
	ray._on_choice(0, p, hud)
	_check(gs.cash == 8 and gs.homeless_trust == 1, "  giving Ray $2 earns his trust")
	gs.debt = 20
	gs.debt_due = gs.now_minutes() + 600.0
	ray._on_choice(2, p, hud)
	_check(not cold_tip.contains("black jacket") and hud.text_label.text.contains("black jacket"), "  ...and then he warns you who's been asking after you")
	gs.debt = 0

	# The beat cop: watching a hand-to-hand at the pusher's corner calls it in.
	gs.clock = 22 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var pusher := city.get_node("Pusher")
	p = _player()
	city.set("_patrol_timer", 99999.0)  # only the cops this test places
	city._spawn_patrol(pusher.global_position + Vector3(-5.0, 0, 2.3))
	var cop := city.get_tree().get_first_node_in_group("patrol") as Node3D
	cop.heading = 1.0
	await _frames(60)
	_check(pusher.state in [pusher.State.TO_HIDE, pusher.State.HIDDEN], "  the pusher melts away when the beat cop comes near")
	cop.remove_from_group("patrol")
	cop.queue_free()
	var waited := 0
	while pusher.state != pusher.State.POST and waited < 900:
		await _frames(10)
		waited += 10
	_check(pusher.state == pusher.State.POST, "  ...and comes back once he's gone")
	# Put a hand-to-hand in plain view.
	city._spawn_patrol(pusher.global_position + Vector3(-5.5, 0, 2.3))
	cop = city.get_tree().get_first_node_in_group("patrol") as Node3D
	# Standing still, looking east straight at the corner.
	cop.heading = 1.0
	cop.set("_pause_timer", 999.0)
	cop.base_facing_deg = 0.0
	cop.set("sweep_arc_deg", 0.0)
	pusher.state = pusher.State.AWAIT_BUYER
	pusher.set("_owes_fix", true)
	p.global_position = pusher.global_position + Vector3(-1.0, 0, 0.3)
	p.dialogue_active = true
	waited = 0
	while not gs.wanted and waited < 600:
		# He'd rather hide from the cop; hold him on his corner for the test.
		pusher.state = pusher.State.AWAIT_BUYER
		pusher.global_position = pusher._post_position
		pusher._set_hidden(false)
		await _frames(10)
		waited += 10
	_check(gs.wanted and city.get_tree().get_first_node_in_group("police") != null, "  a beat cop who sees you buy calls it in and gives chase")
	p.dialogue_active = false
	gs.start_run()

func _close_menus() -> void:
	for c in root.get_children():
		if c is CanvasLayer and (c.has_method("open_with") or c.has_method("open")):
			c.free()

func _places_checks(gs: Node) -> void:
	print("== New places: the shelter, the pawnshop, and the lot out back")
	_close_menus()
	gs.start_run()
	gs.clock_running = false

	# The City fronts lead to all three.
	gs.clock = 18 * 60
	var city := await _load("res://world/City3D.tscn")
	for pair in [["DoorToShelter", "Shelter3D"], ["DoorToBackyard", "Backyard3D"]]:
		city = await _load("res://world/City3D.tscn")
		city.get_node(pair[0]).interact(_player())
		await _frames(10)
		_check(current_scene.name == pair[1], "  %s leads to %s" % pair)
	gs.clock = 12 * 60
	city = await _load("res://world/City3D.tscn")
	city.get_node("DoorToShelter").interact(_player())
	await _frames(5)
	_check(current_scene.name == "City3D", "  the shelter is shut through the day (12:00)")

	# Shelter: a meal, once per sitting; the outreach desk.
	gs.clock = 18 * 60
	var shelter := await _load("res://world/Shelter3D.tscn")
	var hud := shelter.get_tree().get_first_node_in_group("hud")
	var p := _player()
	gs.craving = 40.0
	shelter.interact_zone(shelter.find_child("ServingCounter"), p)
	var after_meal: float = gs.craving
	shelter.interact_zone(shelter.find_child("ServingCounter"), p)
	_check(after_meal > 40.0 and gs.craving == after_meal, "  dinner steadies you a little, once per sitting (%.0f -> %.0f)" % [40.0, after_meal])
	var outreach := shelter.get_node("Outreach")
	var nal_before: int = gs.naloxone
	outreach._on_choice(0, p, hud)
	_check(gs.naloxone == nal_before + 1 and not gs.daily_available("shelter_naloxone"), "  the outreach worker hands out a naloxone kit, once a day")
	gs.last_dose_at[drugs_class_opioid()] = gs.run_time
	gs.craving = 10.0
	outreach._on_choice(1, p, hud)
	_check(gs.craving == 10.0 and gs.daily_available("shelter_bupe"), "  ...won't give bupe right after an opioid")
	gs.last_dose_at.clear()
	outreach._on_choice(1, p, hud)
	_check(gs.craving > 10.0 and not gs.daily_available("shelter_bupe"), "  ...but will once you're in withdrawal (craving %.0f)" % gs.craving)
	gs.clock = 22 * 60
	var day_before: int = gs.day
	shelter.interact_zone(shelter.find_child("Cot1"), p)
	_check(gs.day == day_before + 1 and gs.clock_text() == "08:00", "  a cot for the night")

	# Pawnshop: better than the bar's flat fence, less for electronics.
	gs.clock = 14 * 60
	var pawn := await _load("res://world/Pawn3D.tscn")
	hud = pawn.get_tree().get_first_node_in_group("hud")
	p = _player()
	var broker := pawn.get_node("Pawnbroker")
	gs.cash = 0
	gs.inventory.clear()
	gs.steal_item("cognac")
	gs.steal_item("smartphone")
	var cognac_offer: int = broker.offer_for("cognac")
	var phone_offer: int = broker.offer_for("smartphone")
	_check(cognac_offer > gs.FENCE_PRICE and float(phone_offer) / 80.0 < float(cognac_offer) / 55.0, "  pawn pays more than the fence ($%d for cognac), less on electronics ($%d for an $80 phone)" % [cognac_offer, phone_offer])
	broker._sell("cognac", p, hud)
	_check(gs.cash == cognac_offer and not gs.has_item("cognac"), "  selling hands over the cash")

	# Backyard: the morning delivery, the dumpster, and hiding.
	gs.clock = 7 * 60
	var yard := await _load("res://world/Backyard3D.tscn")
	_check(yard.get_node_or_null("Item1") != null and yard.get_node_or_null("Driver") != null, "  a delivery sits on the dock in the morning, with its driver")
	gs.clock = 14 * 60
	yard = await _load("res://world/Backyard3D.tscn")
	await _frames(2)
	_check(not is_instance_valid(yard.get_node_or_null("Item1")) and not is_instance_valid(yard.get_node_or_null("Driver")), "  ...and is gone by the afternoon")
	hud = yard.get_tree().get_first_node_in_group("hud")
	p = _player()
	yard.interact_zone(yard.find_child("Dumpster"), p)
	var first_dive: String = hud.text_label.text
	yard.interact_zone(yard.find_child("Dumpster"), p)
	_check(not first_dive.contains("already") and hud.text_label.text.contains("already"), "  the dumpster: one dig a day")
	p.dialogue_active = false
	var hide := yard.find_child("HideSpot") as Node3D
	p.global_position = hide.global_position
	await _frames(3)
	yard.interact_zone(hide, p)
	var police := PoliceScene.instantiate()
	yard.add_child(police)
	police.global_position = hide.global_position + Vector3(6.0, 0, 3.0)
	await _frames(5)
	_check(p.hiding and not police._has_line_of_sight(p), "  crouched behind the dumpster, the police can't see you")
	var waited := 0
	while gs.wanted and waited < 60 * 8:
		await _frames(10)
		waited += 10
	_check(not gs.wanted and not gs.in_custody, "  ...and they give up and leave")
	p.set_hiding(false)
	gs.start_run()

func drugs_class_opioid() -> String:
	return root.get_node("Drugs").OPIOID

func _walkman_checks(gs: Node) -> void:
	print("== Walkman: tapes at home, music everywhere, Tape Deck")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var walkman := root.get_node("Walkman")
	_check(gs.tapes.size() == walkman.STARTING_TAPES.size() and not gs.has_walkman, "  a run starts with the shoebox of tapes and the walkman at home")
	var apt := await _load("res://world/Apartment3D.tscn")
	var pickup := apt.get_node("Walkman")
	pickup.interact(_player())
	_check(gs.has_walkman, "  picking it up off the mattress")
	_player().dialogue_active = false
	walkman.open_menu()
	await _frames(2)
	var menu: Node = null
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("open"):
			menu = c
	_check(menu != null, "  [T] opens the shoebox")
	if menu:
		menu._on_pick(1)  # 0 is "Shuffle the shoebox"
	await _frames(5)
	_check(walkman.is_playing() and gs.tapes.has(walkman.current) and not walkman.shuffle, "  a tape goes in and plays (%s)" % walkman.current)
	var first: String = walkman.current
	walkman.next()
	_check(walkman.shuffle and walkman.current != first, "  [N] skips on and switches to shuffle (%s)" % walkman.current)
	var city := await _load("res://world/City3D.tscn")
	await _frames(10)
	var sfx := root.get_node("SFX")
	_check(walkman._player.playing and sfx._music_track == "", "  it keeps playing outside, and the street music drops out")
	walkman.stop()
	await _frames(5)
	_check(sfx._music_track != "", "  stop the tape and the street comes back")

	var store := await _load("res://world/MusicStore3D.tscn")
	var slots: Array = store.item_slots.filter(func(sl): return is_instance_valid(sl) and not sl.is_queued_for_deletion())
	_check(slots.size() > 0 and slots.all(func(sl): return sl.item_id.begins_with("tape:") and not gs.tapes.has(sl.item_id.trim_prefix("tape:"))), "  Tape Deck's racks hold tapes you don't own yet")
	var before: int = gs.tapes.size()
	gs.steal_item(slots[0].item_id)
	_check(gs.tapes.size() == before + 1 and gs.inventory.is_empty(), "  a lifted tape goes into the shoebox, not your pockets")
	gs.cash = 50
	var hud := store.get_tree().get_first_node_in_group("hud")
	var to_buy: String = walkman.dealer_stock()[0]
	# Through the counter's own trigger, not straight into _buy: the trigger
	# once got auto-renamed and the menu never opened.
	var counter := store.get_node_or_null("CounterZone") as Area3D
	_check(counter != null, "  the counter has its trigger")
	if counter:
		store.interact_zone(counter, _player())
		var till_menu: Node = null
		for c in root.get_children():
			if c is CanvasLayer and c.has_method("open") and c.has_signal("chosen"):
				till_menu = c
		_check(till_menu != null, "  the counter opens the clerk's menu")
		if till_menu:
			till_menu.queue_free()
		_player().dialogue_active = false
	store._buy(to_buy, _player(), hud)
	_check(gs.tapes.has(to_buy) and gs.cash == 50 - walkman.TAPES[to_buy]["price"], "  or buy one at the counter ($%d)" % walkman.TAPES[to_buy]["price"])
	gs.start_run()

func _pool_checks(gs: Node) -> void:
	print("== Pool: a full game for money at the Dive Bar")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 20 * 60
	var bar := await _load("res://world/DiveBar3D.tscn")
	_check(bar.find_child("PoolZone", true, false) != null, "  the pool table can be played")
	gs.cash = 60
	var p := _player()
	bar._start_pool(bar.POOL_TABLES[3], p)
	await _frames(2)
	var game: Node = null
	for c in root.get_children():
		if c.has_method("_ai_plan"):
			game = c
	_check(game != null, "  a game starts ($%d against %s)" % [bar.POOL_TABLES[3]["bet"], bar.POOL_TABLES[3]["name"]])
	_check(game._howto, "  the first game opens on the how-to")
	game._howto = false
	var result := []
	game.finished.connect(func(won): result.append(won))
	# Let our side play with the same AI so a whole game runs through.
	var frames := 0
	while result.is_empty() and frames < 60 * 900:
		if game._shooter == 0 and not game._moving and not game._over:
			if game._ball_in_hand:
				game._ai_place_cue()
			game._ai_plan()
			game._shoot(game._ai_target_aim, game._ai_power, game._ai_follow, 0.0)
		await process_frame
		frames += 1
	var left := func(who: int) -> int: return game._remaining(game._groups[who]) if game._groups[who] != -1 else 7
	_check(result.size() == 1, "  the game plays out to a winner (%s, %d-%d left, %.0fs)" % ["won" if result and result[0] else "lost", left.call(0), left.call(1), frames / 60.0])
	_check(game._groups[0] != -1 and game._groups[0] != game._groups[1], "  the table got split into solids and stripes")
	var expected := 110 if result and result[0] else 10
	_check(gs.cash == expected, "  the pot changes hands ($60 -> $%d)" % gs.cash)
	game._close()
	await _frames(3)
	_check(not p.dialogue_active, "  and you can walk away from the table")
	gs.start_run()

func _darts_checks(gs: Node) -> void:
	print("== Darts: three rounds for money at the Dive Bar")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 20 * 60
	var Darts = load("res://ui/DartsGame.gd")
	var c: Vector2 = Darts.CENTRE
	var mm: float = Darts.MM
	_check(Darts.score_at(c)["points"] == 50, "  dead centre is the bull")
	_check(Darts.score_at(c + Vector2(0, -103 * mm))["label"] == "T20", "  straight up at 103 mm is the treble 20")
	_check(Darts.score_at(c + Vector2(0, 166 * mm))["label"] == "D3", "  straight down at 166 mm is the double 3")
	_check(Darts.score_at(c + Vector2(130 * mm, 0))["label"] == "6", "  to the right is the 6")
	_check(Darts.score_at(c + Vector2(0, 200 * mm))["points"] == 0, "  off the board scores nothing")
	var bar := await _load("res://world/DiveBar3D.tscn")
	_check(bar.find_child("DartsZone", true, false) != null, "  the dartboard can be played")
	gs.cash = 40
	bar._start_darts(bar.DART_TABLES[0], _player())
	await _frames(2)
	var game: Node = null
	for n in root.get_children():
		if n.has_method("score_at"):
			game = n
	_check(game != null, "  a game starts ($%d against %s)" % [bar.DART_TABLES[0]["bet"], bar.DART_TABLES[0]["name"]])
	if game == null:
		return
	game._howto = false
	var result := []
	game.finished.connect(func(won): result.append(won))
	var frames := 0
	while not game._over and frames < 60 * 120:
		if game._player_turn and game._flying.is_empty() and game._darts_left > 0:
			game._mouse = c + Vector2(0, -103 * mm)
			game._click()
		await process_frame
		frames += 1
	var tied: bool = game._totals[0] == game._totals[1]
	_check(game._round_scores[1].size() == 9, "  they throw exactly nine darts (%d)" % game._round_scores[1].size())
	_check(game._over and (result.size() == 1 or tied), "  nine darts each and a result (%d-%d, %.0fs)" % [game._totals[0], game._totals[1], frames / 60.0])
	var expected := 40 if tied else (45 if result[0] else 35)
	_check(gs.cash == expected, "  the pot changes hands ($40 -> $%d)" % gs.cash)
	game._close()
	await _frames(3)
	_check(not _player().dialogue_active, "  and you can walk away from the board")
	gs.start_run()

func _menu_and_save_checks(gs: Node) -> void:
	print("== Title, pause and save/continue")
	_close_menus()
	var save := root.get_node("SaveGame")
	save.delete()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	var city := await _load("res://world/City3D.tscn")
	await _frames(3)
	_check(save.has_save(), "  walking into a room autosaves")
	gs.cash = 77
	gs.day = 4
	gs.tapes.append("reggae")
	var p := _player()
	p.global_position = Vector3(3.0, 0, 1.0)
	_check(save.save(), "  saving mid-room works")
	gs.start_run()
	_check(gs.cash != 77, "  (a fresh run has other numbers)")
	save.continue_run()
	await _frames(8)
	_check(gs.cash == 77 and gs.day == 4 and gs.tapes.has("reggae"), "  continue restores cash, day and tapes")
	_check(current_scene.name == "City3D", "  ...in the same room")
	_check(_player().global_position.distance_to(Vector3(3.0, 0, 1.0)) < 0.3, "  ...standing where you were")
	gs.set_wanted(true)
	_check(not save.save(), "  no saving while the cops are after you")
	gs.set_wanted(false)
	gs.end_run("busted")
	await _frames(3)
	_check(not save.has_save(), "  a run that ends deletes its save")
	_close_menus()
	for n in root.get_children():
		if n.has_method("show_summary"):
			n.queue_free()
	var pause = load("res://ui/PauseMenu.gd").new()
	root.add_child(pause)
	pause.open()
	await _frames(2)
	_check(paused, "  the pause menu stops the game")
	pause._close()
	await _frames(2)
	_check(not paused, "  ...and resume starts it again")
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _frames(20)
	_check(current_scene.name == "TitleScreen", "  the title screen loads")
	gs.start_run()

func _recovery_checks(gs: Node) -> void:
	print("== Getting out: the program, slips, and stacking doses")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	var ended := []
	var on_end := func(s): ended.append(s["cause"])
	gs.run_ended.connect(on_end)
	gs.clinic_dose()
	gs.sleep()
	_check(gs.in_treatment and gs.treatment_streak == 1, "  a clinic dose enrolls you, and a clean day counts")
	gs.clinic_dose()
	gs.take_drug("heroin")
	gs.sleep()
	_check(gs.treatment_streak == 0 and gs.in_treatment, "  a street dose that day resets the count, not the program")
	gs.sleep()
	_check(gs.treatment_streak == 0, "  a day without the clinic dose doesn't count")
	for i in gs.RECOVERY_DAYS:
		gs.clinic_dose()
		gs.sleep()
	_check(gs.recovered(), "  %d clean days in a row and you've got out" % gs.RECOVERY_DAYS)
	gs.end_run("recovered")
	await _frames(3)
	_check(ended.has("recovered"), "  ...which ends the run as the good ending")
	gs.run_ended.disconnect(on_end)
	for n in root.get_children():
		if n.has_method("show_summary"):
			n.queue_free()
	# Stacking: the same drug that's survivable spaced out is deadly piled up.
	var deaths := 0
	for trial in 200:
		gs.start_run()
		# Naloxone turns each would-be death into "saved", so this counts
		# them without ending 200 runs (and paying Know-How for each).
		gs.naloxone = 99
		for dose in 6:
			if gs.take_drug("fentanyl") == "saved":
				deaths += 1
				break
	_check(deaths > 150, "  six fentanyl doses back to back kill most of the time (%d/200)" % deaths)
	for n in root.get_children():
		if n.has_method("show_summary"):
			n.queue_free()
	gs.start_run()

func _regulars_checks(gs: Node) -> void:
	print("== The block's regulars")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 22 * 60
	var city := await _load("res://world/City3D.tscn")
	var scenes := city.get_node_or_null("StreetScenes")
	_check(scenes != null, "  the regulars are on the block")
	if scenes == null:
		return
	var pusher := city.get_node("Pusher") as Node3D
	var doors := city.find_children("Door*", "Area3D", true, false)
	var crowding := []
	for p in scenes._people:
		var n: Node3D = p["node"]
		if Vector2(n.global_position.x - pusher.global_position.x, n.global_position.z - pusher.global_position.z).length() < 2.5:
			crowding.append("%s by the pusher" % n.name)
		for d in doors:
			if Vector2(n.global_position.x - d.global_position.x, n.global_position.z - d.global_position.z).length() < 1.2:
				crowding.append("%s by %s" % [n.name, d.name])
	_check(crowding.is_empty(), "  none of them crowds the pusher or a door %s" % str(crowding))
	var here: Array = scenes._people.filter(func(p): return p["node"].visible).map(func(p): return String(p["node"].name))
	_check(here.has("Dee") and here.has("Marcus") and not here.has("Carl"), "  at 22:00 Dee and Marcus are out, Carl isn't asleep yet (%s)" % str(here))
	gs.clock = 4 * 60
	gs._emit_clock()
	await _frames(2)
	here = scenes._people.filter(func(p): return p["node"].visible).map(func(p): return String(p["node"].name))
	_check(here == ["Carl"], "  at 04:00 only Carl, asleep on the steps (%s)" % str(here))
	gs.start_run()

func _round4_checks(gs: Node) -> void:
	print("== Honest work, the notebook, temptation, the diary, the camera")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	var jobs := root.get_node("Jobs")
	# The dock, 6-10.
	gs.clock = 7 * 60
	var yard := await _load("res://world/Backyard3D.tscn")
	await _frames(4)
	_check(yard.get_node_or_null("DockAsk") != null and yard.get_node_or_null("DockPallet") != null, "  mornings, the driver has work")
	var cash_before: int = gs.cash
	jobs._on_dock_ask(null, _player())
	for i in jobs.DOCK_BOXES:
		jobs._on_dock_truck(null, _player())
		jobs._on_dock_pallet(null, _player())
	_check(jobs.job.is_empty() and gs.cash == cash_before + jobs.DOCK_PAY, "  five boxes truck to pallet pays $%d" % jobs.DOCK_PAY)
	jobs._on_dock_ask(null, _player())
	_check(jobs.job.is_empty(), "  ...once a day")
	_player().dialogue_active = false
	# Flyers from the shelter board, posted on the block.
	jobs.job = {"kind": "flyers", "left": [-21.0, -1.7]}
	var city := await _load("res://world/City3D.tscn")
	await _frames(4)
	var spots := city.find_children("FlyerSpot*", "Area3D", true, false)
	_check(spots.size() == 2, "  flyer spots are marked on the block (%d)" % spots.size())
	cash_before = gs.cash
	for s in spots:
		jobs._on_flyer_spot(s, _player())
	_check(jobs.job.is_empty() and gs.cash == cash_before + jobs.FLYER_PAY, "  putting the last one up pays $%d" % jobs.FLYER_PAY)
	# Bottles.
	var bottles := city.find_children("Bottle*", "Area3D", true, false)
	_check(bottles.size() == jobs.BOTTLES_PER_DAY, "  bottles in the gutter (%d)" % bottles.size())
	for b in bottles:
		jobs._on_bottle(b, _player())
	cash_before = gs.cash
	jobs._on_machine(null, _player())
	_check(gs.cash == cash_before + jobs.BOTTLES_PER_DAY / jobs.BOTTLES_PER_DOLLAR and jobs.bottles == jobs.BOTTLES_PER_DAY % jobs.BOTTLES_PER_DOLLAR, "  the machine pays a dollar a %d, keeps the change" % jobs.BOTTLES_PER_DOLLAR)
	_player().dialogue_active = false
	# The camera eases after you and settles back on you.
	_player().global_position.x += 3.0
	await _frames(90)
	var off: Vector3 = _player()._cam_focus - _player().global_position
	_check(Vector2(off.x, off.z).length() < 0.2, "  the camera settles back on you (%.2f m off)" % Vector2(off.x, off.z).length())
	# The notebook.
	var book = load("res://ui/Notebook.gd").new()
	root.add_child(book)
	book.open(3)
	await _frames(2)
	_check(paused, "  the notebook stops the clock while it's out")
	book._close()
	await _frames(2)
	_check(not paused, "  ...and putting it away starts it again")
	# Temptation, in the program.
	gs.clinic_dose()
	var t: Node = city.get_node("Temptation")
	var streak_used: bool = gs.used_today
	await t._decide(false, _player(), "Held on.")
	_check(not gs.used_today and gs.craving >= 0.0, "  holding on doesn't count as using")
	await t._decide(true, _player(), "Gave in.")
	_check(gs.used_today, "  giving in does -- the day won't count")
	_check(gs.diary.any(func(e): return "Gave in" in e["text"]) and gs.diary.any(func(e): return "Unloaded a truck" in e["text"]), "  it's all in the diary (%d entries)" % gs.diary.size())
	gs.start_run()

func _street_life_checks(gs: Node) -> void:
	print("== Street life II: traffic, steam, rain, and the bigger stash")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	var city := await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var life := city.get_node("StreetLife")
	_check(life.get_children().filter(func(c): return c is GPUParticles3D and c != life._rain).size() == 2, "  steam rises from both manholes")
	var p := _player()
	p.global_position = Vector3(0.0, 0, life.LANE_Z)
	for car in life._cars:
		car.queue_free()
	life._cars.clear()
	life._spawn_car(-8.0)
	await _frames(120)
	var car: Node3D = life._cars[0]
	_check(car.position.x < p.global_position.x - 3.0 and car.get_meta("honked"), "  a car stops short of you in the road and leans on the horn (%.1f m away)" % (p.global_position.x - car.position.x))
	p.global_position = Vector3(0.0, 0, -3.0)
	await _frames(60)
	_check(car.position.x > 0.5, "  ...and drives on once you step out of the way")
	gs.set_raining(true)
	await _frames(3)
	_check(life._rain.emitting and life._rain_sound.playing and life._wet_materials.size() > 0 and life._wet_materials[0].roughness < 0.5, "  rain: streaks, the sound, and a wet shiny street")
	gs.set_raining(false)
	await _frames(3)
	_check(not life._rain.emitting and life._wet_materials[0].roughness > 0.5, "  ...and it dries off when it stops")
	var pusher := city.get_node("Pusher")
	gs.day = 5
	var stock: Array = pusher._todays_stock()
	_check(stock.size() >= 12, "  the pusher's holding a lot more (%d kinds tonight)" % stock.size())
	gs.start_run()

func _kart_checks(gs: Node) -> void:
	print("== Southside Speedway: $5 a ride, three laps, prize money once a day")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	var city := await _load("res://world/City3D.tscn")
	var door := city.find_child("DoorToKarts", true, false)
	_check(door != null and door.target_scene.ends_with("KartCenter3D.tscn"), "  the kart track has a door on the block")
	_check(not gs.is_open("karts"), "  ...shut at 13:00")
	gs.clock = 19 * 60
	_check(gs.is_open("karts"), "  ...open at 19:00")
	var track := await _load("res://world/KartCenter3D.tscn")
	_check(track.find_child("KartDesk", true, false) != null, "  there's a desk to sign up at")
	var p := _player()
	gs.cash = 20
	track._start_race(p)
	await _frames(2)
	var race: Node = null
	for c in root.get_children():
		if c.has_method("_ai_inputs"):
			race = c
	_check(race != null and gs.cash == 15, "  a ride costs $5 ($20 -> $%d)" % gs.cash)
	_check(race._karts.size() == 6, "  six karts on the grid")
	var clock_before: float = gs.clock
	var placed := []
	race.finished.connect(func(place): placed.append(place))
	race.autopilot = true
	var frames := 0
	while not race._results_shown and frames < 60 * 240:
		await physics_frame
		frames += 1
	_check(race._results_shown and placed.size() == 1, "  the race runs three laps to a result (%s, %.0fs)" % [race.ORDINALS[placed[0] - 1] if placed else "none", frames / 60.0])
	var laps_ok := true
	for k in race._karts:
		laps_ok = laps_ok and k["finished"] and float(k["best_lap"]) > 15.0 and float(k["best_lap"]) < 60.0
	_check(laps_ok, "  every kart finishes with a sane lap time")
	var prize: int = race.PRIZES[placed[0] - 1] if placed and placed[0] <= race.PRIZES.size() else 0
	_check(gs.cash == 15 + prize, "  the podium pays ($15 -> $%d)" % gs.cash)
	_check(is_equal_approx(gs.clock, clock_before), "  the day waits while you race")
	race._close()
	await _frames(3)
	_check(not p.dialogue_active and track.visible, "  and you're back in the office afterwards")
	# Second race of the day: no prize money.
	track._start_race(p)
	await _frames(2)
	for c in root.get_children():
		if c.has_method("_ai_inputs"):
			race = c
	race.autopilot = true
	var cash_before: int = gs.cash
	frames = 0
	while not race._results_shown and frames < 60 * 240:
		await physics_frame
		frames += 1
	_check(gs.cash == cash_before, "  the prize only pays once a day")
	race._close()
	await _frames(3)
	# Drifting: held through the longest bend, steering to match it like a
	# player would, ~1 s charges a blue turbo and ~2 s an orange one.
	race = load("res://ui/KartRace.gd").new()
	root.add_child(race)
	race.start()
	race._phase = race.Phase.RACE
	var n: int = race._pts.size()
	var bend := 0
	var bend_sum := 0.0
	for k in n:
		var sum := 0.0
		for o in 40:
			sum += race._curv[(k + o) % n]
		if absf(sum) > bend_sum:
			bend_sum = absf(sum)
			bend = k
	for want in [[1.2, 1, "blue"], [2.2, 2, "orange"]]:
		var you: Dictionary = race._karts[0]
		var k0 := (bend - 8 + n) % n
		you["pos"] = race._pts[k0]
		you["k"] = k0
		you["yaw"] = atan2(-race._tan[k0].x, -race._tan[k0].z)
		you["vel"] = race._tan[k0] * 15.0
		for key in ["boost", "drift_t", "steer", "hop"]:
			you[key] = 0.0
		you["drift"] = 0
		you["boost_kind"] = 0
		var t := 0.0
		var held := true
		while t < want[0]:
			var kk: int = you["k"]
			var fwd := Vector3(-sin(you["yaw"]), 0, -cos(you["yaw"]))
			var head_err: float = fwd.signed_angle_to(race._tan[kk], Vector3.UP)
			var lat: float = race._lateral(you["pos"], kk)
			var kappa: float = race._curv[(kk + 3) % n] + lat * 0.02 - head_err * 0.15
			var steer := signf(race._curv[(bend + 5) % n])
			if int(you["drift"]) != 0:
				var f: float = (absf(kappa) - 1.0 / race.DRIFT_RADIUS.y) / (1.0 / race.DRIFT_RADIUS.x - 1.0 / race.DRIFT_RADIUS.y)
				steer = float(you["drift"]) * clampf(2.0 * f - 1.0, -1.0, 1.0)
			race._drive(you, steer, 1.0, true, 1.0 / 60.0, true)
			you["k"] = race._nearest(you["pos"], you["k"])
			if t > 0.2 and int(you["drift"]) == 0:
				held = false
			t += 1.0 / 60.0
		race._drive(you, 0.0, 1.0, false, 1.0 / 60.0, true)
		_check(held and int(you["boost_kind"]) == want[1] and float(you["boost"]) > 0.0, "  hold a drift %.1fs through the bend, let go: %s turbo (%.2fs)" % [want[0], want[2], you["boost"]])
	race._close()
	await _frames(3)
	gs.start_run()

func _headline_checks(gs: Node) -> void:
	print("== Word on the block: one thing different every day")
	_close_menus()
	var hl := root.get_node("Headlines")
	gs.start_run()
	hl.forced = ""
	hl.roll(1)
	_check(hl.today() == "quiet", "  day one is always quiet")
	var seen := {}
	for d in range(2, 60):
		hl.roll(d)
		seen[hl.today()] = true
	_check(seen.size() >= 6, "  and after that it varies (%d kinds in 58 days)" % seen.size())
	gs.clock = 12 * 60
	hl.forced = "strike"
	hl.roll(gs.day)
	_check(not gs.is_open("supermarket") and not hl.delivery_today(), "  delivery strike: supermarket shut, no truck")
	gs.clock = 7 * 60
	var yard := await _load("res://world/Backyard3D.tscn")
	await _frames(2)
	_check(not is_instance_valid(yard.get_node_or_null("Item1")), "  ...and nothing on the dock")
	gs.clock = 12 * 60
	hl.forced = "quiet"
	hl.roll(gs.day)
	var calm: float = gs.staff_alertness()
	var calm_price: int = gs.price_of("heroin")
	hl.forced = "crackdown"
	hl.roll(gs.day)
	_check(gs.staff_alertness() > calm * 1.2 and gs.price_of("heroin") > calm_price, "  crackdown: staff x%.2f, heroin $%d -> $%d" % [gs.staff_alertness() / calm, calm_price, gs.price_of("heroin")])
	hl.forced = "drought"
	hl.roll(gs.day)
	var r: Vector2i = hl.pusher_stock_range(Vector2i(12, 17))
	_check(r.y <= 8 and gs.price_of("heroin") >= int(calm_price * 1.4), "  dry spell: %d-%d kinds, heroin $%d" % [r.x, r.y, gs.price_of("heroin")])
	hl.forced = "payday"
	hl.roll(gs.day)
	_check(gs.order_price("Wiry Guy", 50) == 70, "  payday: a $50 order pays $%d" % gs.order_price("Wiry Guy", 50))
	gs.clock = 12 * 60 + 30
	hl.forced = "kart_cup"
	hl.roll(gs.day)
	_check(gs.is_open("karts") and hl.kart_prize_mult() == 3, "  Speedway Cup: karts open at 12:30, triple prizes")
	hl.forced = "storm"
	hl.roll(gs.day)
	gs._roll_weather()
	_check(gs.raining, "  storm: raining, and it stays raining")
	gs.set_raining(false)
	hl.forced = ""
	gs.sabotage_day = gs.day + 1
	hl.roll(gs.day + 1)
	_check(hl.today() == "track_shut" and not gs.is_open("karts"), "  the day after the carburetor goes missing, the track's shut")
	# The banner, once a day.
	hl.forced = "payday"
	hl.roll(gs.day)
	hl.announced_day = -1
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var hud = city.get_tree().get_first_node_in_group("hud")
	_check(hud._headline_panel.visible and hud._headline_title.text.contains("PAYDAY"), "  the HUD announces it (\"%s\")" % hud._headline_title.text)
	# It saves with the run.
	gs.clock_running = false
	root.get_node("SaveGame").save()
	hl.forced = "quiet"
	hl.roll(gs.day)
	hl.forced = ""
	root.get_node("SaveGame").continue_run()
	await _frames(10)
	_check(gs.headline == "payday", "  a saved run keeps its headline (%s)" % gs.headline)
	root.get_node("SaveGame").delete()
	hl.forced = "quiet"
	gs.start_run()
	hl.roll(gs.day)

func _rep_checks(gs: Node) -> void:
	print("== The regulars remember you")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 20 * 60
	var bar := await _load("res://world/DiveBar3D.tscn")
	var p := _player()
	var hud = bar.get_tree().get_first_node_in_group("hud")
	var patron = bar.patrons[0]
	var who: String = patron.npc_name
	var item: String = patron.request_id
	var base_price: int = gs.bar_patrons[0]["price"]
	gs.steal_item(item)
	var cash_before: int = gs.cash
	patron.interact(p)
	_check(gs.rep_of(who) == 1 and gs.cash == cash_before + base_price, "  delivering: %s likes you more (%d), and pays $%d" % [who, gs.rep_of(who), gs.cash - cash_before])
	hud.advance_or_close_dialogue()
	# A friend tips you off about a store.
	var patron2 = bar.patrons[1]
	var who2: String = patron2.npc_name
	var store: String = gs.item_info(patron2.request_id)["store"]
	gs.rep[who2] = 2
	var before: float = gs.store_alertness(store)
	patron2.interact(p)
	_check(gs.store_alertness(store) < before * 0.8 and hud.text_label.text.contains("listen"), "  a friend tips you off: %s watches x%.2f today" % [store, gs.store_alertness(store) / before])
	hud.advance_or_close_dialogue()
	# Sell what someone wanted to someone else, twice over: a grudge.
	var patron3 = bar.patrons[2]
	var who3: String = patron3.npc_name
	var item3: String = patron3.request_id
	var store3: String = gs.item_info(item3)["store"]
	gs.rep[who3] = -1
	var heat_before: float = gs.store_alertness(store3)
	gs.steal_item(item3)
	gs.fence_everything()
	_check(gs.rep_of(who3) == -2 and gs.store_alertness(store3) > heat_before * 1.2, "  sell their order elsewhere: %s holds a grudge and talks to the clerk (x%.2f)" % [who3, gs.store_alertness(store3) / heat_before])
	patron3.interact(p)
	_check(hud.text_label.text.find("$") == -1, "  ...and won't give you work (\"%s\")" % hud.text_label.text.left(40))
	hud.advance_or_close_dialogue()
	gs.start_run()

func _hustle_checks(gs: Node) -> void:
	print("== The kart hustle: Eddie's money, the runner's book, the spares box")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 19 * 60
	var track := await _load("res://world/KartCenter3D.tscn")
	var p := _player()
	var hud = track.get_tree().get_first_node_in_group("hud")
	var eddie := track.find_child("BigEddie", true, false)
	_check(eddie != null, "  Big Eddie's hanging around the office")
	track.accept_throw("Big Eddie", 30)
	_check(track.throw_deal_active(), "  ...and you can take his money to lose")
	# Score the throw three ways without running whole races.
	var race = load("res://ui/KartRace.gd").new()
	root.add_child(race)
	race.start("player", {"kind": "throw", "by": "Big Eddie", "pay": 30})
	var cash0: int = gs.cash
	race._finish_order.assign([1, 2, 3])
	race._karts[3]["time"] = 95.0
	race._karts[0]["time"] = 99.0
	race._settle_deal(4)
	_check(gs.cash == cash0 + 30 and gs.rep_of("Big Eddie") == 1, "  4th, four seconds back: Eddie pays $%d" % (gs.cash - cash0))
	cash0 = gs.cash
	race._karts[0]["time"] = 120.0
	race._settle_deal(4)
	_check(gs.cash == cash0 and gs.rep_of("Big Eddie") == 0, "  4th but 25 seconds back: too obvious, no pay")
	race._finish_order.assign([1])
	race._settle_deal(2)
	_check(gs.rep_of("Big Eddie") == -2, "  2nd: you crossed him (%d)" % gs.rep_of("Big Eddie"))
	race._deal = {"kind": "bet", "stake": 10, "pays": 25}
	cash0 = gs.cash
	race._settle_deal(3)
	_check(gs.cash == cash0 + 25, "  $10 on yourself, 3rd: the runner pays $25")
	race._close()
	await _frames(3)
	# Burned him: he doesn't show next time.
	track = await _load("res://world/KartCenter3D.tscn")
	_check(track.find_child("BigEddie", true, false) == null, "  ...and once you've burned Eddie he stays away")
	# The spares box.
	p = _player()
	hud = track.get_tree().get_first_node_in_group("hud")
	track.parts_seen_chance = 1.0
	track._on_parts(null, p)
	_check(not gs.has_item("carburetor") and not gs.daily_available("kart_banned"), "  caught in the spares box: thrown out for the day")
	hud.advance_or_close_dialogue()
	gs.daily_used.erase("kart_parts")
	gs.daily_used.erase("kart_banned")
	track.parts_seen_chance = 0.0
	track._on_parts(null, p)
	_check(gs.has_item("carburetor") and gs.sabotage_day == gs.day + 1, "  not seen: a carburetor in your jacket, and the track's shut tomorrow")
	hud.advance_or_close_dialogue()
	_check(load("res://npc/PawnBroker3D.gd").offer_for("carburetor") == 30, "  the pawnshop gives $30 for it")
	gs.start_run()

func _search_checks(gs: Node) -> void:
	print("== Losing the police: crowds, hiding spots, and a search")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	var city := await _load("res://world/City3D.tscn")
	var p := _player()
	_check(city.find_child("AlleyHide", true, false) != null and get_nodes_in_group("hide_spots").size() >= 2, "  hiding spots on the block (%d)" % get_nodes_in_group("hide_spots").size())
	# In a crowd.
	var walker: Node3D = null
	for w in get_nodes_in_group("pedestrians"):
		walker = w
		break
	if walker:
		p.global_position = walker.global_position + Vector3(0.6, 0, 0)
		var cop = PoliceScene.instantiate()
		city.add_child(cop)
		cop.global_position = p.global_position + Vector3(7.0, 0, 1.5)
		await _frames(2)
		p.global_position = walker.global_position + Vector3(0.6, 0, 0)
		_check(p.in_crowd() and not cop._has_line_of_sight(p), "  walking among passersby, a cop 7 m off loses you")
		cop.queue_free()
		gs.set_wanted(false)
		await _frames(2)
	# Seen ducking in: he checks the spot and finds you.
	var spot := city.find_child("AlleyHide", true, false) as Node3D
	for w in get_nodes_in_group("pedestrians"):
		w.queue_free()
	p.global_position = spot.global_position
	await _frames(3)
	city._on_hide_spot(spot, p)
	var cop2 = PoliceScene.instantiate()
	city.add_child(cop2)
	cop2.global_position = spot.global_position + Vector3(-6.0, 0, 3.0)
	cop2._saw_player = true
	cop2._last_seen = spot.global_position + Vector3(-1.0, 0, 0.5)
	var waited := 0
	while not gs.in_custody and is_instance_valid(cop2) and waited < 60 * 20:
		await _frames(10)
		waited += 10
	var found: bool = gs.in_custody or current_scene.name == "Jail3D"
	# Let the arrest finish (cutscene, then the cell) before moving on.
	var settle := 0
	while current_scene.name != "Jail3D" and settle < 60 * 15:
		await _frames(10)
		settle += 10
	_check(found and current_scene.name == "Jail3D", "  seen going in: he searches the spot and finds you (%.1fs)" % (waited / 60.0))
	await _frames(10)
	gs.start_run()
	gs.clock_running = false
	gs.clock = 13 * 60
	city = await _load("res://world/City3D.tscn")
	p = _player()
	spot = city.find_child("DumpsterHide", true, false) as Node3D
	for w in get_nodes_in_group("pedestrians"):
		w.queue_free()
	p.global_position = spot.global_position
	await _frames(3)
	city._on_hide_spot(spot, p)
	var cop3 = PoliceScene.instantiate()
	city.add_child(cop3)
	cop3.global_position = Vector3(2.0, 0, 1.0)
	cop3._saw_player = true
	cop3._last_seen = Vector3(8.0, 0, -2.5)
	waited = 0
	while gs.wanted and waited < 60 * 25:
		await _frames(10)
		waited += 10
	_check(not gs.wanted and not gs.in_custody, "  out of sight first, then hidden: he searches where he lost you and gives up (%.1fs)" % (waited / 60.0))
	p.set_hiding(false)
	gs.start_run()

func _sick_world_checks(gs: Node) -> void:
	print("== Withdrawal you can see")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 21 * 60
	var city := await _load("res://world/City3D.tscn")
	var hud = city.get_tree().get_first_node_in_group("hud")
	gs.craving = 100.0
	await _frames(3)
	var well_sat: float = hud._graded_env.adjustment_saturation
	var life = city.get_node("StreetLife")
	var well_signs: int = life._flicker.size()
	gs.craving = 0.0
	await _frames(3)
	_check(hud._graded_env.adjustment_saturation < well_sat * 0.5, "  sick, the colour drains out (saturation %.2f -> %.2f)" % [well_sat, hud._graded_env.adjustment_saturation])
	_check(life._flicker.size() > well_signs, "  ...and the neon starts to stutter (%d signs -> %d)" % [well_signs, life._flicker.size()])
	var book = load("res://ui/Notebook.gd").new()
	var name: String = "a bottle of good whiskey"
	_check(book._misread(name) != name, "  ...and your notes swim (\"%s\")" % book._misread(name))
	book.free()
	var npc = load("res://npc/NPC3D.gd").new()
	var reacted := 0
	for i in 40:
		if npc._sick_prefix() != "":
			reacted += 1
	npc.free()
	_check(reacted > 5, "  ...and people notice ( %d of 40 lines)" % reacted)
	gs.craving = 100.0
	await _frames(3)
	_check(absf(hud._graded_env.adjustment_saturation - well_sat) < 0.01, "  well again, the colour comes back")
	gs.start_run()
