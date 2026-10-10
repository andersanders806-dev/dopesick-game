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
	# Graphics has already read the player's settings.cfg by now. Put the
	# defaults back (the sandbox never saves) so checks don't depend on
	# whether you last played in first person or on High.
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	gfx.set_preset(gfx.Preset.MEDIUM)
	# A quiet day every day unless a check asks for something else.
	root.get_node("Headlines").forced = "quiet"
	root.get_node("Headlines").roll(root.get_node("GameState").day)
	PoliceScene = load("res://npc/Police3D.tscn")
	await _run()
	print("\n%s (%d failure(s))" % ["PASS" if _failures == 0 else "FAIL", _failures])
	await _finished()
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1

## Hooks for watch_playtest.gd, which runs these same checks in a window.
func _section(title: String) -> void:
	print("== " + title)

func _finished() -> void:
	pass

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _load(path: String) -> Node:
	# A door's fade still running would change the room again under us.
	while root.get_node("SceneLoader").busy():
		await process_frame
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

	await _section("The test sandbox ignores the player's own settings")
	# Whatever you picked in your own game (first person, High) mustn't
	# change what the checks below see.
	var gfx := root.get_node("Graphics")
	_check(not gfx.first_person and gfx.preset == gfx.Preset.MEDIUM, "  third person, Medium, whatever settings.cfg says (fp %s, %s)" % [gfx.first_person, gfx.PRESET_NAMES[gfx.preset]])

	await _section("Every 3D room loads with a player, HUD, and baked navmesh")
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

	await _section("Animation: idle when still, walk when moving")
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

	await _section("Shop: stealing an item")
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

	await _section("Shop: shopkeeper spots a theft in plain view")
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
		await _section("Police: chases along the navmesh")
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

	await _section("Door: chase follows the player into the City")
	var door := shop.get_node("DoorToCity")
	door.interact(player)
	await _transition()
	_check(current_scene.name == "City3D", "Shop door leads to City3D")
	var spawn := current_scene.get_node("SpawnFromShop") as Marker3D
	_check(_player().global_position.distance_to(spawn.global_position) < 0.5, "player placed at SpawnFromShop")
	_check(get_first_node_in_group("police") != null and gs.wanted, "officer respawned in the City while still wanted")
	gs.set_wanted(false)
	for p in get_nodes_in_group("police"):
		p.queue_free()

	await _section("City: buying from the pusher on the street")
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

	await _section("City doors all lead somewhere real")
	for d in ["DoorToHome", "DoorToBar", "DoorToShop", "DoorToPharmacy", "DoorToLiquor", "DoorToSupermarket", "DoorToElectronics"]:
		var target: String = current_scene.get_node(d).target_scene
		_check(ResourceLoader.exists(target), "%s -> %s" % [d, target])

	await _section("Dive Bar: sell to a patron")
	current_scene.get_node("DoorToBar").interact(_player())
	await _transition()
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

	await _section("Dive Bar: orders stick until delivered")
	var paid_name: String = patron.npc_name
	var waiting := {}
	for p in bar.patrons:
		if p != patron:
			waiting[p.npc_name] = [p.request_id, p.position]
	bar.get_node("DoorToCity").interact(_player())
	await _transition()
	current_scene.get_node("DoorToBar").interact(_player())
	await _transition()
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
	await _transition()
	current_scene.get_node("DoorToBar").interact(_player())
	await _transition()
	var after_sleep: Array = current_scene.patrons.map(func(p): return "%s:%s" % [p.npc_name, p.request_id])
	_check(before_sleep == after_sleep, "orders still stand after a night's sleep")
	current_scene.get_node("DoorToCity").interact(_player())
	await _transition()
	current_scene.get_node("DoorToBar").interact(_player())
	await _transition()

	await _section("Busted: exactly one bust, then a jail cell")
	current_scene.get_node("DoorToCity").interact(_player())
	await _transition()
	current_scene.get_node("DoorToShop").interact(_player())
	await _transition()
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
	await _transition()
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
	await _transition()
	_check(current_scene.name == "City3D" and _player().global_position.distance_to(current_scene.get_node("SpawnFromJail").global_position) < 0.5,
		"  the jail exit puts you on the street outside the police station")
	current_scene.get_node("DoorToHome").interact(_player())
	await _transition()

	await _section("Apartment: furniture and sleep")
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

	await _section("Stealth: suspicion builds, drains, and only then raises the alarm")
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

	await _section("Runs: strikes, the run-end payout, and meta upgrades")
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

	await _section("Drugs: prices, tolerance, interactions, and going over")
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
	await _batch1_checks(gs)
	await _batch2_checks(gs)
	await _controller_checks(gs)
	await _view_checks(gs)
	await _aa_checks(gs)
	await _perf_checks(gs)
	await _ambience_checks(gs)
	await _cast_checks(gs)
	await _world_art_checks(gs)
	await _polish_checks(gs)
	await _cutscene_video_checks()
	await _lean_checks(gs)
	await _low_checks(gs)
	_scaler_checks()
	await _darknet_checks(gs)
	await _world_art_2_checks()
	await _story_checks(gs)
	await _story_review_checks(gs)
	await _gameplay3_checks(gs)
	await _sound4_checks(gs)
	await _one_load_at_a_time_checks()
	gs.start_run()

func _day_night_checks(gs: Node) -> void:
	await _section("Day and night: the clock, opening hours, shifts, and the pusher's hours")
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
	await _transition()
	_check(current_scene.name == "City3D", "  the pharmacy is locked at 23:30")
	current_scene.get_node("DoorToShop").interact(_player())
	await _transition()
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
	await _section("Withdrawal: the senses, the hands, the cramps, and things that aren't there")
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
	await _section("Debt: fronting, paying back, and the collector")
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
	await _section("Street life: passersby, Ray, and the beat cop")
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
	await _section("New places: the shelter, the pawnshop, and the lot out back")
	_close_menus()
	gs.start_run()
	gs.clock_running = false

	# The City fronts lead to all three.
	gs.clock = 18 * 60
	var city := await _load("res://world/City3D.tscn")
	for pair in [["DoorToShelter", "Shelter3D"], ["DoorToBackyard", "Backyard3D"]]:
		city = await _load("res://world/City3D.tscn")
		city.get_node(pair[0]).interact(_player())
		await _transition()
		_check(current_scene.name == pair[1], "  %s leads to %s" % pair)
	gs.clock = 12 * 60
	city = await _load("res://world/City3D.tscn")
	city.get_node("DoorToShelter").interact(_player())
	await _transition()
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
	await _section("Walkman: tapes at home, music everywhere, Tape Deck")
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
	await _section("Pool: a full game for money at the Dive Bar")
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
	await _section("Darts: three rounds for money at the Dive Bar")
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
	await _section("Title, pause and save/continue")
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
	await _transition()
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
	await _section("Getting out: the program, slips, and stacking doses")
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
	await _section("The block's regulars")
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
	await _section("Honest work, the notebook, temptation, the diary, the camera")
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
	await _section("Street life II: traffic, steam, rain, and the bigger stash")
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
	await _section("Southside Speedway: $5 a ride, three laps, prize money once a day")
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
	await _section("Word on the block: one thing different every day")
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
	await _transition()
	_check(gs.headline == "payday", "  a saved run keeps its headline (%s)" % gs.headline)
	root.get_node("SaveGame").delete()
	hl.forced = "quiet"
	gs.start_run()
	hl.roll(gs.day)

func _rep_checks(gs: Node) -> void:
	await _section("The regulars remember you")
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
	await _section("The kart hustle: Eddie's money, the runner's book, the spares box")
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
	await _section("Losing the police: crowds, hiding spots, and a search")
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
	await _section("Withdrawal you can see")
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

func _batch1_checks(gs: Node) -> void:
	await _belongings_checks(gs)
	await _pawn_ticket_checks(gs)
	await _rent_checks(gs)
	await _court_checks(gs)
	await _status_checks(gs)
	await _batch1_save_checks(gs)
	await _batch1_review_checks(gs)

func _belongings_checks(gs: Node) -> void:
	await _section("Your own things: belongings")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	_check(gs.BELONGINGS.all(func(id): return gs.belongings[id] == "home"), "  a run starts with all five belongings at home")
	_check(gs.is_belonging("tv") and not gs.is_belonging("cognac"), "  the TV is a belonging, cognac isn't")
	gs.take_belonging("tv")
	_check(gs.has_item("tv") and gs.belongings["tv"] == "carried", "  taking the TV puts it in your pockets")
	_check(not gs.carrying_stolen(), "  ...and it doesn't count as stolen goods")
	gs.steal_item("cognac")
	gs.get_busted()
	gs.in_custody = false
	_check(gs.has_item("tv") and not gs.has_item("cognac"), "  a bust takes the cognac but leaves you your TV")
	gs.steal_item("cigs")
	var earned: int = gs.fence_everything()
	_check(earned == gs.FENCE_PRICE and gs.has_item("tv"), "  the bar fences the cigarettes, not your TV")
	gs.inventory.erase("tv")
	gs._reconcile_belongings()
	_check(gs.belongings["tv"] == "gone", "  a belonging that left your pockets some other way is gone")
	gs.take_belonging("radio")
	var back: Array = gs.return_belongings_home()
	_check(back == ["radio"] and gs.belongings["radio"] == "home" and not gs.has_item("radio"), "  carrying it home puts it back")
	gs.start_run()
	gs.clock_running = false
	var apt := await _load("res://world/Apartment3D.tscn")
	for id in gs.BELONGINGS:
		_check(apt.get_node_or_null("Belonging_" + id) != null, "  the apartment has a %s you can take" % id)
	apt.get_node("Belonging_tv").take()
	await _frames(2)
	_check(gs.has_item("tv") and not apt.get_node("TV").visible, "  taking the TV leaves an empty box")
	_check(not apt.get_node("Belonging_tv").is_in_group("interactable"), "  ...with nothing left there to take")
	gs.take_belonging("guitar")
	gs.take_belonging("coat")
	gs.inventory.erase("coat")
	apt = await _load("res://world/Apartment3D.tscn")
	_check(apt.get_node("TV").visible and apt.get_node("Guitar").visible and gs.belongings["tv"] == "home", "  walking back in with them puts them back")
	_check(not apt.get_node("CoatHook/Coat").visible and gs.belongings["coat"] == "gone", "  ...but the coat you lost is gone for good")
	gs.take_belonging("tv")
	gs.take_belonging("radio")
	gs.inventory.clear()
	gs._reconcile_belongings()
	apt = await _load("res://world/Apartment3D.tscn")
	await _frames(3)
	var hud := apt.get_tree().get_first_node_in_group("hud")
	_check(gs.apartment_echo_seen and hud.text_label.text.contains("echo"), "  three things gone, and the room echoes")
	_player().dialogue_active = false
	gs.start_run()

func _pawn_ticket_checks(gs: Node) -> void:
	await _section("Pawn tickets: selling your things, buying them back")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var pawn := await _load("res://world/Pawn3D.tscn")
	var hud = pawn.get_tree().get_first_node_in_group("hud")
	var broker := pawn.get_node("Pawnbroker")
	_check(broker.offer_for("tv") == 24 and broker.offer_for("ring") == 45, "  he pays full value for your own things ($24 TV, $45 ring)")
	gs.cash = 0
	gs.take_belonging("tv")
	broker._sell("tv", _player(), hud)
	_check(gs.cash == 24 and gs.belongings["tv"] == "pawned" and gs.pawn_tickets.get("tv", -1) == gs.day, "  selling the TV writes a ticket")
	_check(gs.buyback_price("tv") == 36 and gs.ticket_last_day("tv") == gs.day + 4, "  buying back costs $36 and holds four days")
	gs.cash = 35
	_check(not gs.buy_back("tv"), "  can't buy it back short")
	gs.cash = 40
	_check(gs.buy_back("tv") and gs.has_item("tv") and gs.belongings["tv"] == "carried" and gs.cash == 4, "  buying back puts it in your pockets")
	gs.take_belonging("ring")
	broker._sell("ring", _player(), hud)
	for i in 4:
		gs.advance_clock(24 * 60)
	_check(gs.belongings["ring"] == "pawned", "  the ticket holds through day +4")
	gs.advance_clock(24 * 60)
	_check(gs.belongings["ring"] == "gone" and not gs.pawn_tickets.has("ring"), "  ...and then it's sold to someone else")
	_player().dialogue_active = false
	gs.start_run()

func _rent_checks(gs: Node) -> void:
	await _section("Rent day")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	_check(gs.rent_due_day == 5 and gs.rent_amount() == 35, "  rent is $35, due day 5")
	gs.cash = 100
	_check(gs.pay_rent() and gs.cash == 65 and gs.rent_due_day == 10, "  paying moves it to day 10")
	_check(not gs.pay_rent() and gs.cash == 65, "  ...and you can't pay next week's early")
	gs.start_run()
	gs.clock_running = false
	gs.cash = 0
	for i in 5:
		gs.advance_clock(24 * 60)
	_check(gs.day == 6 and gs.rent_stage == 1 and gs.rent_amount() == 45, "  missed: a final notice, $45 with the late fee")
	gs.advance_clock(24 * 60)
	_check(gs.rent_stage == 2 and gs.locked_out() and gs.rent_amount() == 65, "  missed again: locked out, $65 with the locksmith")
	gs.advance_clock(24 * 60)
	_check(gs.rent_stage == 2 and gs.rent_amount() == 65, "  ...and it stops there")
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	city.get_node("DoorToHome").interact(_player())
	await _transition()
	_check(current_scene.name == "City3D", "  the lock's been changed")
	_close_menus()
	gs.cash = 80
	city.get_node("DoorToHome")._pay_landlord(_player())
	await _transition()
	_check(current_scene.name == "Apartment3D" and gs.rent_stage == 0 and gs.cash == 15 and gs.rent_due_day == gs.day + 5, "  paying the landlord lets you back in")
	var slot := current_scene.get_node("RentSlot")
	gs.cash = 50
	current_scene._on_rent_slot(slot, _player())
	_check(gs.cash == 50, "  the slot won't take next week's rent early")
	gs.rent_due_day = gs.day
	gs.rent_stage = 1
	gs.rent_owed = 45
	_player().dialogue_active = false
	gs.advance_clock(24 * 60)
	await _frames(60 * 7)
	_check(current_scene.name == "City3D", "  locked out while you're home, you're shown out")
	_player().dialogue_active = false
	gs.start_run()

func _court_checks(gs: Node) -> void:
	await _section("Court, probation, and the warrant")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	gs.get_busted()
	gs.in_custody = false
	_check(gs.court_day == gs.day + 2, "  a bust sets a court date two days out")
	gs.advance_clock(2 * 24 * 60 - 4 * 60)  # day+2, 10:00
	gs.in_treatment = true
	var strikes_before: int = gs.strikes
	_check(gs.appear_in_court() == "diverted" and gs.strikes == strikes_before - 1 and gs.court_day == -1, "  in the program, drug court takes a strike off")
	gs.in_treatment = false
	gs.get_busted()
	gs.in_custody = false
	gs.advance_clock(2 * 24 * 60)  # busted at 10:00, so day+2 at 10:00 -- not past noon
	_check(not gs.warrant and gs.appear_in_court() == "probation" and gs.probation_days == [gs.day + 1, gs.day + 2, gs.day + 3], "  otherwise, three days' probation")
	gs.advance_clock(24 * 60)
	_check(gs.probation_check_in() == "passed" and gs.probation_days.size() == 2, "  a clean check-in passes")
	# Naloxone on hand so a random overdose can't end the run mid-test.
	gs.naloxone = 5
	gs.clock = 16 * 60
	gs.take_drug("heroin")
	_check(gs.now_minutes() - gs.last_street_use < 1.0, "  a street dose is remembered for the test")
	var strikes_mid: int = gs.strikes
	gs.advance_clock(18 * 60)  # next morning, 10:00
	_check(gs.tested_dirty() and gs.probation_check_in() == "failed" and gs.strikes == strikes_mid + 1 and gs.probation_days.is_empty(), "  using the day before fails the test: a strike")
	gs.in_custody = false
	gs.court_day = gs.day
	gs.clock = 11 * 60
	gs.advance_clock(3 * 60)
	_check(gs.warrant and gs.court_day == -1, "  missing court gets you a warrant")
	gs.advance_clock(24 * 60)
	_check(gs.warrant and gs.diary.filter(func(e): return e["text"].contains("warrant")).size() == 1, "  ...once")
	gs.probation_days.assign([gs.day])
	gs.warrant = false
	gs.clock = 16 * 60
	gs.advance_clock(2 * 60)
	_check(gs.warrant and gs.probation_days.is_empty(), "  missing a check-in gets you one too")
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	var cop = city.get_tree().get_first_node_in_group("patrol")
	var p := _player()
	gs.inventory.clear()
	cop.suspicion = 0.0
	cop.can_see_player = true
	cop._update_suspicion(p, 0.5)
	_check(cop.suspicion > 0.3, "  with a warrant, the beat cop knows your face (%.2f)" % cop.suspicion)
	gs.warrant = false
	cop.suspicion = 0.0
	cop.can_see_player = true
	cop._update_suspicion(p, 0.5)
	_check(cop.suspicion == 0.0, "  ...without one, an empty-handed man is nobody")
	gs.warrant = true
	var strikes_now: int = gs.strikes
	city.get_node("StationDoor").to_cell()
	await _transition()
	_check(not gs.warrant and gs.strikes == strikes_now and gs.court_day == gs.day + 2 and current_scene.name == "Jail3D", "  turning yourself in: no strike, a new court date, a night in the cell")
	_player().dialogue_active = false
	gs.start_run()

func _status_checks(gs: Node) -> void:
	await _section("What's hanging over you: HUD and notebook")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	_check(gs.status_line().is_empty(), "  day 1, nothing pressing")
	gs.day = 5
	_check(gs.status_line() == ["Rent $35 due tonight", false], "  rent day")
	gs.court_day = 5
	_check(String(gs.status_line()[0]).begins_with("Court 09-12"), "  court beats rent")
	gs.warrant = true
	_check(gs.status_line() == ["WARRANT", true], "  a warrant beats everything")
	var city := await _load("res://world/City3D.tscn")
	var hud = city.get_tree().get_first_node_in_group("hud")
	hud._update_status()
	_check(hud.status_label.visible and hud.status_label.text == "WARRANT", "  the HUD shows it")
	gs.warrant = false
	gs.court_day = -1
	gs.day = 2
	hud._update_status()
	_check(not hud.status_label.visible, "  ...and hides when there's nothing")
	gs.take_belonging("guitar")
	gs.pawn_belonging("guitar")
	var book = load("res://ui/Notebook.gd").new()
	var lines: Array = book._obligations().map(func(l): return l[0])
	book.free()
	_check(lines.any(func(l): return l.begins_with("Rent: $35 due day 5")) and lines.any(func(l): return l.contains("guitar, $45 by day 6")), "  the notebook lists rent and the pawn ticket: %s" % [lines])
	gs.start_run()

func _batch1_save_checks(gs: Node) -> void:
	await _section("Belongings, rent and court survive save and continue")
	_close_menus()
	var save := root.get_node("SaveGame")
	save.delete()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	await _load("res://world/City3D.tscn")
	gs.day = 6
	gs.take_belonging("ring")
	gs.inventory.erase("ring")
	gs.pawn_belonging("ring")
	gs.take_belonging("tv")
	gs.rent_stage = 1
	gs.rent_due_day = 6
	gs.rent_owed = 45
	gs.court_day = 7
	gs.probation_days.assign([8, 9])
	gs.warrant = true
	gs.apartment_echo_seen = true
	gs.last_street_use = gs.now_minutes() - 60.0
	_check(save.save(), "  saved")
	gs.start_run()
	save.continue_run()
	await _transition()
	_check(gs.belongings["ring"] == "pawned" and int(gs.pawn_tickets.get("ring", -1)) == 6 and gs.belongings["tv"] == "carried" and gs.has_item("tv"), "  belongings and tickets come back")
	_check(gs.rent_stage == 1 and gs.rent_owed == 45 and gs.rent_due_day == 6, "  ...the final notice, not rolled on by loading")
	_check(gs.court_day == 7 and gs.warrant and gs.tested_dirty() and gs.apartment_echo_seen, "  ...the court date, the warrant, and what's in your system")
	_check(gs.probation_days.size() == 2 and int(gs.probation_days[0]) == 8, "  ...and the probation days")
	save.delete()
	gs.start_run()

func _batch2_checks(gs: Node) -> void:
	await _bad_batch_checks(gs)
	await _strip_checks(gs)
	await _alley_checks(gs)
	await _booster_checks(gs)
	await _batch2_save_checks(gs)

func _bad_batch_checks(gs: Node) -> void:
	await _section("Bad batch and test strips")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 18 * 60
	var hl := root.get_node("Headlines")
	hl.forced = "bad_batch"
	hl.roll(gs.day)
	var hits := 0
	for i in 2000:
		if gs.roll_contaminated("heroin"):
			hits += 1
	_check(hits > 700 and hits < 900, "  about 40%% of opioids are cut on a bad batch day (%d/2000)" % hits)
	_check(not gs.roll_contaminated("meth"), "  ...only the opioids")
	hl.forced = "quiet"
	hl.roll(gs.day)
	_check(not gs.roll_contaminated("heroin"), "  ...and none on an ordinary day")
	gs.take_drug("bupe")
	var base: float = gs.last_risk
	gs.start_run()
	gs.take_drug("bupe", 1.0, gs.CONTAMINATED_RISK)
	_check(base > 0.0 and absf(gs.last_risk - base * 3.0) < 1e-9, "  contaminated is three times the risk")
	gs.start_run()
	gs.craving = 10.0
	gs.take_drug("bupe", 0.5)
	var relief: float = float(root.get_node("Drugs").info("bupe")["relief"])
	_check(absf(gs.last_risk - base * 0.5) < 1e-9 and gs.craving <= 10.0 + relief * 0.5 + 0.01, "  a little at a time: half the risk, half the relief")
	_check(gs.strip_reading("oxy", "fentanyl", false).contains("Fentanyl"), "  a strip shows the blue was a press")
	_check(gs.strip_reading("heroin", "heroin", true).contains("cut"), "  ...and a cut bag")
	_check(gs.strip_reading("heroin", "heroin", false).contains("nothing"), "  ...and a clean one")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 18 * 60
	var shelter := await _load("res://world/Shelter3D.tscn")
	var outreach := shelter.get_node("Outreach")
	var hud = shelter.get_tree().get_first_node_in_group("hud")
	outreach._on_choice(2, _player(), hud)
	outreach._on_choice(2, _player(), hud)
	_check(gs.test_strips == 2, "  outreach hands out two strips, once a day")
	_player().dialogue_active = false
	gs.start_run()

func _choice_menu() -> CanvasLayer:
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("open") and c.has_signal("chosen"):
			return c
	return null

func _strip_checks(gs: Node) -> void:
	await _section("Testing what he sold you")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 18 * 60
	var city := await _load("res://world/City3D.tscn")
	var pusher := city.get_tree().get_first_node_in_group("pusher")
	var p := _player()
	gs.craving = 20.0
	_check(pusher._consume(p, "heroin", false, "toss") == "tossed" and gs.craving == 20.0 and gs.doses_taken == 0, "  thrown away: nothing goes in")
	gs.naloxone = 5
	pusher._consume(p, "heroin", true, "half")
	var heroin_risk: float = float(root.get_node("Drugs").info("heroin")["od_risk"])
	_check(gs.last_risk > heroin_risk * 1.0 and gs.last_risk <= heroin_risk * 1.5 + 1e-9, "  a cut bag taken slow: x3 risk, halved (%.4f)" % gs.last_risk)
	gs.test_strips = 1
	var answer := [""]
	var asking = func(): answer[0] = await pusher._dose_choice(p, "heroin", "heroin", false)
	asking.call()
	await _frames(2)
	_choice_menu()._on_cancel()
	await _frames(2)
	_check(answer[0] == "take" and gs.test_strips == 1, "  closing the menu just takes it, strip unspent")
	asking.call()
	await _frames(2)
	_choice_menu()._on_pick(0)
	await _frames(2)
	var reading_menu := _choice_menu()
	_check(gs.test_strips == 0 and reading_menu != null, "  testing spends the strip and shows the reading")
	reading_menu._on_pick(1)
	await _frames(2)
	_check(answer[0] == "half", "  ...then you can take a little at a time")
	p.dialogue_active = false
	gs.start_run()

func _alley_checks(gs: Node) -> void:
	await _section("Someone goes over in the alley")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	_check(gs.REGULARS == load("res://world/DiveBar3D.gd").PATRON_NAMES, "  one list of regulars")
	var hl := root.get_node("Headlines")
	var rolled := 0
	gs.day = 3
	for i in 400:
		gs._roll_overdose()
		if gs.od_event.get("state", "") == "pending":
			rolled += 1
	_check(rolled > 70 and rolled < 130, "  about one night in four (%d/400)" % rolled)
	gs.day = 1
	gs._roll_overdose()
	_check(gs.od_event.get("state", "") == "", "  never on day 1")
	gs.day = 3
	hl.forced = "bad_batch"
	hl.roll(3)
	gs._roll_overdose()
	_check(gs.od_event.get("state", "") == "pending" and gs.od_event["who"] in gs.REGULARS and gs.od_event["minute"] >= 18 * 60, "  always on a bad batch night, a regular, after 18:00")
	hl.forced = "quiet"
	# The start time passes whether you're there or not.
	gs.clock = float(gs.od_event["minute"]) - 30.0
	gs.advance_clock(60)
	_check(gs.od_event["state"] == "down", "  at the time, they go down")
	var city := await _load("res://world/City3D.tscn")
	var alley := city.get_node("AlleyOverdose")
	await _frames(3)
	_check(alley.victim != null and alley.victim.visible, "  ...and they're in the alley")
	# Lying beside the dumpster (1.8 x 1.0), not inside it: a body is ~1.7 m
	# long, so its centre wants a good half-metre of clear ground past the box.
	var bin: Vector3 = city.find_child("Dumpster", true, false).global_position
	var vp: Vector3 = alley.victim.global_position
	_check(absf(vp.x - bin.x) > 0.9 + 0.5 or absf(vp.z - bin.z) > 0.5 + 0.5, "  ...beside the dumpster, not inside it (%s vs %s)" % [vp, bin])
	var vap: AnimationPlayer = alley.victim.find_child("AnimationPlayer", true, false)
	var lying: bool = alley.victim.get_meta("lying", false)
	_check(lying or (vap != null and String(vap.current_animation).to_lower().ends_with("death")), "  ...on the ground, not standing there (%s)" % (vap.current_animation if vap else "no player"))
	var who: String = gs.od_event["who"]
	gs.naloxone = 1
	_check(alley._choose("naloxone") == "saved" and gs.naloxone == 0 and gs.rep_of(who) == 3, "  naloxone: saved, and they owe you (rep 3)")
	await _frames(2)
	_check(not alley.victim.visible, "  ...and they get up and go")
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Quiet Kid", "state": "down", "left": 90.0}
	alley.refresh()
	gs.rep.clear()
	var cops: int = city.get_tree().get_nodes_in_group("patrol").size()
	_check(alley._choose("payphone") == "saved" and gs.rep_of("Quiet Kid") == 2 and city.get_tree().get_nodes_in_group("patrol").size() == cops + 1, "  the payphone: saved, and a cop comes with the ambulance")
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Quiet Kid", "state": "down", "left": 90.0}
	alley.refresh()
	var cash0: int = gs.cash
	_check(alley._choose("pockets") == "dead" and gs.cash >= cash0 + 8 and gs.dead_regulars.has("Quiet Kid") and gs.vigil_day == gs.day + 1, "  their pockets: $%d, and they die" % (gs.cash - cash0))
	_player().dialogue_active = false
	var died := 0
	for i in 300:
		gs.dead_regulars.clear()
		gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Old Sailor", "state": "down", "left": 90.0}
		if gs.resolve_overdose("walk") == "dead":
			died += 1
	_check(died > 170 and died < 230, "  walking away: two in three die (%d/300)" % died)
	gs.dead_regulars.clear()
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Old Sailor", "state": "down", "left": 0.5}
	alley.refresh()
	await _frames(60)
	_check(gs.od_event["state"] in ["saved", "dead"], "  run out the clock and it's decided for you")
	gs.dead_regulars.clear()
	gs.od_event = {"day": gs.day, "minute": 20 * 60, "who": "Nervous Dave", "state": "down", "left": 90.0}
	_close_menus()
	await _load("res://world/Pawn3D.tscn")
	var diary_before: int = gs.diary.size()
	gs.clock = 23 * 60
	gs.advance_clock(120)
	var about_dave: Array = gs.diary.slice(diary_before).filter(func(e): return e["text"].contains("Nervous Dave"))
	_check(about_dave.size() == 1, "  the night ends while they're down somewhere you aren't: decided, once (%s)" % [about_dave.map(func(e): return e["text"])])
	gs.dead_regulars.clear()
	gs.od_event = {"day": gs.day - 1, "minute": 23 * 60, "who": "Nervous Dave", "state": "down", "left": 90.0}
	gs._regular_died("Nervous Dave", false)
	_check(gs.vigil_day == gs.day, "  dying after midnight, the vigil is today, not tomorrow")
	# The dead stay dead.
	gs.dead_regulars.assign(["Big Eddie", "Wiry Guy"])
	gs.bar_patrons.clear()
	gs.bar_patrons.append({"name": "Big Eddie", "model": "", "seat": 0, "request_id": "cigs", "price": 22, "fulfilled": false})
	gs.clock = 18 * 60
	await _load("res://world/DiveBar3D.tscn")
	var names: Array = gs.bar_patrons.map(func(p): return p["name"])
	_check(names.size() == 3 and not names.any(func(n): return n in gs.dead_regulars), "  nobody who died sits in the bar again: %s" % [names])
	for p in gs.bar_patrons:
		p["fulfilled"] = true
	await _load("res://world/DiveBar3D.tscn")
	_check(gs.bar_patrons.size() == 3, "  ...and with four left, the bar still fills when they all go home")
	var none := true
	for i in 50:
		gs._roll_overdose()
		if gs.od_event.get("state", "") == "pending":
			none = false
	_check(none, "  with only four regulars left, nobody else goes over")
	gs.dead_regulars.clear()
	gs.vigil_day = gs.day + 1
	gs.vigil_for = "Quiet Kid"
	hl.forced = ""
	gs.advance_clock(24 * 60)
	hl.forced = "quiet"
	_check(hl.is_today("vigil") and absf(hl.pusher_price_mult() - 0.9) < 1e-6, "  the next day is a vigil, and he charges less")
	gs.clock = 20 * 60
	city = await _load("res://world/City3D.tscn")
	_check(city.get_node("AlleyOverdose").get_node_or_null("Vigil") != null, "  ...with candles in the alley")
	gs.start_run()

func _booster_checks(gs: Node) -> void:
	await _section("Tasha, working the same stores")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	var days := 0
	for i in 400:
		gs.day = 3
		gs._roll_booster()
		if gs.booster_day == 3:
			days += 1
	_check(days > 130 and days < 190, "  out about two days in five (%d/400)" % days)
	gs.day = 1
	gs._roll_booster()
	_check(gs.booster_day != 1, "  never day 1")
	gs.day = 3
	gs.vigil_day = 3
	gs._roll_booster()
	_check(gs.booster_day != 3, "  never on a vigil day")
	gs.vigil_day = -1
	gs.booster_day = 3
	gs.clock = 9 * 60 + 50
	gs.advance_clock(20)
	_check(gs.booster_present() and gs.booster_store != "", "  at ten she's out, casing %s" % gs.booster_store)
	var first: String = gs.booster_store
	gs.advance_clock(60)
	_check(gs.booster_hit == [first] and gs.store_alertness(first) > gs.staff_alertness() * 1.25, "  an hour later it's hit, and its staff are jumpy")
	gs.booster_team_up("liquor")
	_check(gs.booster_team == "liquor" and gs.store_alertness("liquor") < gs.staff_alertness() * 0.7 and gs.booster_cut_pending, "  teaming up: she works the liquor clerk")
	var hits: int = gs.booster_hit.size()
	gs.advance_clock(120)
	_check(gs.booster_hit.size() == hits, "  ...and stops hitting other stores")
	gs.inventory.append("vodka")
	var cash0: int = gs.cash
	gs.sell_item("vodka", 30)
	_check(gs.cash - cash0 == int(round(30 * root.get_node("MetaProgress").payout_scale())) / 2 and not gs.booster_cut_pending, "  ...and takes half your next order")
	gs.start_run()
	gs.clock_running = false
	gs.day = 3
	gs.booster_day = 3
	gs.clock = 10 * 60 + 5
	gs.advance_clock(60)
	var hit: String = gs.booster_hit[0] if gs.booster_hit.size() > 0 else ""
	gs.warrant = true
	gs.homeless_trust = 3
	gs.change_rep("Big Eddie", 2)
	gs.booster_rat()
	_check(gs.booster_gone and not gs.booster_present() and not gs.store_heat.has(hit) and not gs.warrant, "  ratting her out: gone, heat cleared, warrant lost")
	_check(gs.homeless_trust == 0 and gs.rep_of("Big Eddie") == 1, "  ...and the street knows")
	gs.day = 9
	gs._roll_booster()
	_check(gs.booster_day != 9, "  ...for good")
	gs.start_run()
	gs.day = 3
	gs.booster_day = 3
	gs.clock = 14 * 60
	gs._booster_hour()
	var city := await _load("res://world/City3D.tscn")
	await _frames(3)
	_check(city.get_node("Booster").npc.visible, "  she's on the block")
	gs.start_run()

func _batch2_save_checks(gs: Node) -> void:
	await _section("The alley, strips and Tasha survive save and continue")
	_close_menus()
	var save := root.get_node("SaveGame")
	var hl := root.get_node("Headlines")
	save.delete()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60 + 30
	hl.forced = "quiet"
	await _load("res://world/City3D.tscn")
	gs.day = 5
	hl.roll(5)
	gs.test_strips = 2
	gs.od_event = {"day": 5, "minute": 14 * 60, "who": "Old Sailor", "state": "down", "left": 42.0}
	gs.dead_regulars.assign(["Quiet Kid"])
	gs.vigil_day = 4
	gs.vigil_for = "Quiet Kid"
	gs.booster_day = 5
	gs.booster_gone = false
	gs.booster_store = "liquor"
	gs.booster_hit.assign(["pharmacy"])
	gs.booster_team = ""
	gs.booster_cut_pending = true
	_check(save.save(), "  saved")
	gs.start_run()
	save.continue_run()
	await _transition()
	_check(gs.test_strips == 2 and gs.dead_regulars == ["Quiet Kid"] and gs.vigil_day == 4 and gs.vigil_for == "Quiet Kid", "  strips, the dead, and the vigil come back")
	_check(gs.od_event.get("state", "") == "down" and gs.od_event.get("who", "") == "Old Sailor" and absf(float(gs.od_event.get("left", 0.0)) - 42.0) < 1.0, "  ...someone still down, with the time they had left (%s)" % [gs.od_event])
	_check(gs.booster_day == 5 and gs.booster_store == "liquor" and gs.booster_hit == ["pharmacy"] and gs.booster_cut_pending and not gs.booster_gone, "  ...and Tasha's day, not rerolled by loading (%s %s %s %s)" % [gs.booster_day, gs.booster_store, gs.booster_hit, gs.booster_cut_pending])
	save.delete()
	hl.forced = ""
	gs.start_run()

## A pad button or stick, as if from a DualSense. Device 1, not 0: on Linux
## a PS5 pad often isn't the first joypad Godot sees.
func _pad(button: int, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 1
	ev.button_index = button
	ev.pressed = pressed
	ev.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func _tap(button: int) -> void:
	_pad(button, true)
	await _frames(2)
	_pad(button, false)
	await _frames(2)

func _stick(axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 1
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)

## Parsed input is buffered until the next process frame, and a heavy
## scene can run several physics frames before that comes.
func _settle() -> void:
	await process_frame
	await process_frame

func _trigger(axis: int, value: float) -> void:
	_stick(axis, value)

func _find_root_child(method: String) -> Node:
	for n in root.get_children():
		if n.has_method(method):
			return n
	return null

func _controller_checks(gs: Node) -> void:
	await _section("Playing on a PS5 controller")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 20 * 60
	var missing := []
	for a in ["move_up", "move_down", "move_left", "move_right", "look_left", "look_right", "look_up", "look_down",
			"interact", "sprint", "cancel_ui", "pause", "fire", "steady", "aim_left", "aim_right", "aim_up", "aim_down", "drift",
			"notebook", "walkman", "walkman_next", "page_next", "page_prev",
			"throttle", "brake", "ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		if not InputMap.has_action(a) or not InputMap.action_get_events(a).any(func(e): return (e is InputEventJoypadButton or e is InputEventJoypadMotion) and e.device == -1):
			missing.append(a)
	_check(missing.is_empty(), "  every control is on the pad, whichever pad it is (missing: %s)" % [missing])
	var city := await _load("res://world/City3D.tscn")
	var p := _player()
	_stick(JOY_AXIS_LEFT_X, 1.0)
	await _frames(2)
	_check(Input.get_vector("move_left", "move_right", "move_up", "move_down").x > 0.5, "  the left stick walks")
	_check(not p._sprinting, "  ...at a walk")
	await _tap(JOY_BUTTON_LEFT_STICK)
	await _frames(3)
	_check(p._sprinting, "  ...click L3 and you sprint, like COD")
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await _frames(20)
	_stick(JOY_AXIS_LEFT_X, 1.0)
	await _frames(3)
	_check(not p._sprinting, "  ...and stopping ends it")
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await _frames(1)
	_check(InputMap.action_get_events("interact").any(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X), "  square is use")
	var z0: float = p._user_zoom
	_stick(JOY_AXIS_RIGHT_Y, 1.0)
	await _frames(20)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	_check(p._user_zoom > z0, "  the right stick pulls the camera back (%.2f -> %.2f)" % [z0, p._user_zoom])
	await _tap(JOY_BUTTON_TOUCHPAD)
	var book := _find_root_child("_draw_map")
	_check(book != null, "  the touchpad opens the notebook")
	if book:
		var page0: int = book._page
		await _tap(JOY_BUTTON_RIGHT_SHOULDER)
		_check(book._page == page0 + 1, "  ...R1 turns the page")
		await _tap(JOY_BUTTON_B)
		await _frames(2)
		_check(not is_instance_valid(book) or book.is_queued_for_deletion() or _find_root_child("_draw_map") == null, "  ...circle closes it")
	await _frames(2)
	gs.has_walkman = true
	await _tap(JOY_BUTTON_Y)
	var ChoiceMenuScript = load("res://ui/ChoiceMenu.gd")
	_check(root.get_children().any(func(n): return n.get_script() == ChoiceMenuScript), "  triangle opens the shoebox of tapes")
	_close_menus()
	p.dialogue_active = false
	await _tap(JOY_BUTTON_START)
	var PauseScript = load("res://ui/PauseMenu.gd")
	_check(paused and root.get_children().any(func(n): return n.get_script() == PauseScript), "  options pauses")
	paused = false
	_close_menus()
	# Darts: the stick aims, cross throws.
	var bar := await _load("res://world/DiveBar3D.tscn")
	gs.cash = 40
	bar._start_darts(bar.DART_TABLES[0], _player())
	await _frames(2)
	var darts := _find_root_child("score_at")
	if darts:
		darts._howto = false
		darts._player_turn = true
		var m0: Vector2 = darts._mouse
		_stick(JOY_AXIS_LEFT_X, 1.0)
		await _frames(20)
		_stick(JOY_AXIS_LEFT_X, 0.0)
		_check(darts._mouse.x > m0.x + 20.0, "  darts: the stick aims (%.0f -> %.0f)" % [m0.x, darts._mouse.x])
		var left0: int = darts._darts_left
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await _frames(2)
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		await _frames(2)
		_check(not darts._flying.is_empty() or darts._darts_left < left0, "  ...R2 throws")
		# A trigger is analogue: held down, it keeps sending events. One
		# squeeze is one dart.
		await _frames(30)
		var left1: int = darts._darts_left
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await _settle()
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.9)
		await _settle()
		await _frames(30)
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.95)
		await _settle()
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		await _settle()
		_check(left1 - darts._darts_left == 1, "  ...one squeeze, one dart, however long you hold it (%d thrown)" % (left1 - darts._darts_left))
		darts.free()
	else:
		_check(false, "  darts: a game starts")
	# Pool: the stick aims, hold cross to draw the cue back, let go to shoot.
	gs.cash = 60
	bar._start_pool(bar.POOL_TABLES[3], _player())
	await _frames(2)
	var pool := _find_root_child("_ai_plan")
	if pool:
		# Earlier checks may have seen the how-to already; show it again.
		pool._howto = true
		await _tap(JOY_BUTTON_A)
		_check(not pool._howto, "  pool: any button gets past the how-to")
		pool._shooter = 0
		pool._ball_in_hand = false
		var a0: float = pool._aim
		_stick(JOY_AXIS_LEFT_X, 1.0)
		await _frames(20)
		_stick(JOY_AXIS_LEFT_X, 0.0)
		_check(absf(pool._aim - a0) > 0.1, "  ...the stick aims")
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		await _frames(20)
		_check(pool._charging, "  ...hold R2 and the cue draws back")
		_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		await _frames(2)
		_check(not pool._charging and pool._moving, "  ...let go and it's struck")
		pool.free()
	else:
		_check(false, "  pool: a game starts")
	# The karts: R2 is the throttle, options pauses, cross carries on.
	var race = load("res://ui/KartRace.gd").new()
	root.add_child(race)
	race.start("player")
	await _frames(2)
	_trigger(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _settle()
	_check(race._player_throttle() > 0.5, "  karts: R2 is the throttle")
	_trigger(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_trigger(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _settle()
	_check(race._player_throttle() < -0.5, "  ...L2 brakes")
	_trigger(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _tap(JOY_BUTTON_START)
	_check(race._paused_confirm and paused, "  ...options pauses the race")
	await _tap(JOY_BUTTON_A)
	_check(not race._paused_confirm and not paused, "  ...and cross carries on")
	race.free()
	paused = false
	gs.start_run()

func _view_checks(gs: Node) -> void:
	await _section("First person or third, picked when the run starts")
	_close_menus()
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(false)
	# New run asks which.
	var title := await _load("res://ui/TitleScreen.tscn")
	title._on_new_run()
	await _frames(2)
	var labels: Array = title._buttons.get_children().filter(func(b): return b is Button and b.visible).map(func(b): return b.text)
	_check(labels.has("First person") and labels.has("Third person"), "  new run asks: first person or third (%s)" % [labels])
	var fp_button: Button = title._buttons.get_children().filter(func(b): return b is Button and b.text == "First person")[0] if labels.has("First person") else null
	if fp_button:
		fp_button.pressed.emit()
	await _frames(20)
	_check(gfx.first_person and current_scene != null and current_scene.name == "Apartment3D", "  ...first person, and you wake up in the apartment")
	var p := _player()
	gs.clock_running = false
	p.dialogue_active = false
	await _frames(3)
	var cam: Camera3D = p.camera
	var eye: Vector3 = cam.global_position
	_check(Vector2(eye.x - p.global_position.x, eye.z - p.global_position.z).length() < 0.35 and eye.y > 1.4 and eye.y < 1.8, "  the camera is your eyes (%s, feet at %s)" % [eye, p.global_position])
	var meshes: Array = p.model.find_children("*", "GeometryInstance3D", true, false)
	_check(meshes.size() > 0 and meshes.all(func(m): return m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY), "  ...you don't see your own insides, just your shadow")
	_check(current_scene.find_child("FPCeiling", true, false) != null, "  the room has a ceiling")
	var south := current_scene.find_child("WallSouth", true, false)
	var south_mesh: MeshInstance3D = south.get_node("Mesh") if south else null
	_check(south_mesh != null and (south_mesh.mesh as BoxMesh).size.y > 2.0, "  ...and its front wall is full height again")
	# Walking goes where you look.
	p.global_position = Vector3(0, 0, 0.5)
	p.set_look(deg_to_rad(90.0), 0.0)
	await _frames(3)
	var start: Vector3 = p.global_position
	Input.action_press("move_up")
	await _frames(20)
	Input.action_release("move_up")
	var moved: Vector3 = p.global_position - start
	_check(moved.x < -0.3 and absf(moved.z) < absf(moved.x) * 0.5, "  facing west, forward walks west (%s)" % moved)
	var yaw0: float = p._look_yaw
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await _settle()
	await _frames(10)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	await _settle()
	_check(p._look_yaw < yaw0 - 0.1, "  the right stick looks round (%.2f -> %.2f)" % [yaw0, p._look_yaw])
	var pitch0: float = p._look_pitch
	_stick(JOY_AXIS_RIGHT_Y, -1.0)
	await _settle()
	await _frames(60)
	_stick(JOY_AXIS_RIGHT_Y, 0.0)
	await _settle()
	_check(p._look_pitch > pitch0 and p._look_pitch <= deg_to_rad(80.0), "  ...up, but not over backwards (%.0f deg)" % rad_to_deg(p._look_pitch))
	# The street, in first person.
	await _load("res://world/City3D.tscn")
	_check(_player().camera.global_position.y < 2.0 and current_scene.find_child("FPCeiling", true, false) == null, "  out on the street: eye level, open sky")
	# Third person is the old camera, high and behind.
	gfx.set_first_person(false)
	await _load("res://world/Apartment3D.tscn")
	p = _player()
	await _frames(3)
	_check(p.camera.global_position.y > 4.0 and current_scene.find_child("FPCeiling", true, false) == null, "  third person: the camera's back up over the room, no lid on it")
	var shown: Array = p.model.find_children("*", "GeometryInstance3D", true, false)
	_check(shown.all(func(m): return m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY), "  ...and you can see yourself")
	# Switchable mid-run from settings.
	var SettingsMenu = load("res://ui/SettingsMenu.gd")
	var sm = SettingsMenu.new()
	root.add_child(sm)
	sm.open()
	await _frames(2)
	var fp_check: Array = sm.find_children("*", "CheckButton", true, false).filter(func(c): return c.text.begins_with("First person"))
	_check(fp_check.size() == 1, "  settings has a first-person switch")
	if fp_check.size() == 1:
		fp_check[0].button_pressed = true
		await _frames(3)
		_check(gfx.first_person and p.camera.global_position.y < 2.0, "  ...which takes effect right away")
	sm.queue_free()
	gfx.set_first_person(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	gs.start_run()

## What batch 1's final review found.
func _batch1_review_checks(gs: Node) -> void:
	await _section("Batch 1 review: surrender, a lockout in your sleep, old saves, Ray and the ring")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	# Turning yourself in while they're after you ends the chase too.
	var city := await _load("res://world/City3D.tscn")
	gs.warrant = true
	gs.set_wanted(true)
	var strikes0: int = gs.strikes
	city.find_child("StationDoor", true, false).to_cell()
	await _transition()
	_check(gs.strikes == strikes0, "  turning yourself in mid-chase: no strike for it (%d -> %d)" % [strikes0, gs.strikes])
	_check(current_scene.name == "Jail3D" and not gs.wanted, "  turning yourself in mid-chase: the chase is over (wanted %s)" % gs.wanted)
	_check(get_nodes_in_group("police").is_empty(), "  ...and no cop follows you into the cell (%d)" % get_nodes_in_group("police").size())
	# Locked out while a cutscene's up (sleeping in your bed): it waits.
	gs.start_run()
	gs.clock_running = false
	gs.clock = 22 * 60
	await _load("res://world/Apartment3D.tscn")
	var cut := root.get_node("Cutscene")
	cut._playing = true
	paused = true
	gs.rent_due_day = gs.day
	gs.rent_stage = 1
	gs.rent_owed = 45
	gs.advance_clock(24 * 60)
	await _frames(60 * 7)
	_check(current_scene.name == "Apartment3D", "  locked out mid-cutscene: the landlord waits for it to end")
	paused = false
	cut._playing = false
	cut.finished.emit()
	await _frames(60 * 7)
	_check(current_scene.name == "City3D", "  ...then shows you out")
	_player().dialogue_active = false
	# A save from before rent existed starts a fresh rent cycle.
	gs.start_run()
	gs.clock_running = false
	var save := root.get_node("SaveGame")
	save.delete()
	await _load("res://world/City3D.tscn")
	gs.day = 9
	_check(save.save(), "  saved")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save.PATH))
	for k in ["rent_due_day", "rent_stage", "rent_owed"]:
		data.erase(k)
	var f := FileAccess.open(save.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	gs.start_run()
	save.continue_run()
	await _transition()
	_check(gs.rent_stage == 0 and gs.rent_due_day > gs.day, "  an old save: no instant final notice (stage %d, due day %d on day %d)" % [gs.rent_stage, gs.rent_due_day, gs.day])
	save.delete()
	# Ray: you choose what you give him.
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	city = await _load("res://world/City3D.tscn")
	var ray := city.get_node("Ray")
	gs.take_belonging("ring")
	gs.inventory.append("vodka")
	ray._on_choice(1, _player(), get_first_node_in_group("hud"))
	await _frames(2)
	var ChoiceMenuScript = load("res://ui/ChoiceMenu.gd")
	var pick: Array = root.get_children().filter(func(n): return n.get_script() == ChoiceMenuScript)
	_check(pick.size() == 1 and gs.has_item("ring") and gs.has_item("vodka"), "  give him something: you get to pick, nothing's gone yet")
	if pick.size() == 1:
		pick[0]._on_pick(gs.inventory.find("vodka"))
		await _frames(2)
	_check(gs.has_item("ring") and not gs.has_item("vodka"), "  ...the vodka goes, your mother's ring stays")
	_close_menus()
	_player().dialogue_active = false
	gs.start_run()

func _aa_checks(gs: Node) -> void:
	await _section("Smooth edges at every preset")
	var gfx := root.get_node("Graphics")
	var before: int = gfx.preset
	var vp := root.get_viewport()
	for p in [gfx.Preset.LOW, gfx.Preset.MEDIUM]:
		gfx.set_preset(p)
		_check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "  %s: SMAA, not FXAA" % gfx.PRESET_NAMES[p])
	gfx.set_preset(gfx.Preset.HIGH)
	# On an integrated GPU FSR 2 from ~59% crawls at 20-25 FPS; FSR 1 from
	# 77% with TAA and SMAA measured faster and smoother on a UHD 620.
	_check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR and vp.use_taa and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "  High: FSR 1 with TAA and SMAA")
	_check(gfx.SCALE_RANGE[gfx.Preset.HIGH][0] >= 0.67 and absf(vp.scaling_3d_scale - 0.77) < 0.01, "  ...from at least 67%%, starting at 77%% (%.2f)" % vp.scaling_3d_scale)
	gfx.set_preset(gfx.Preset.PS5)
	_check(vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and not vp.use_taa, "  PS5 keeps FSR 2 (a desktop GPU's preset)")
	gfx.set_preset(before)

func _perf_checks(gs: Node) -> void:
	await _section("A shadow budget: only the lamps near you cast shadows")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 21 * 60
	var gfx := root.get_node("Graphics")
	var before: int = gfx.preset
	gfx.set_preset(gfx.Preset.MEDIUM)
	var city := await _load("res://world/City3D.tscn")
	var p := _player()
	var lamps: Array = city.find_children("*", "Light3D", true, false).filter(func(l): return not (l is DirectionalLight3D) and l.get_meta("built_shadow", false))
	_check(lamps.size() > 2, "  the street has more shadowed lamps than the budget (%d)" % lamps.size())
	for x in [-20.0, 20.0]:
		p.global_position = Vector3(x, 0, -2.5)
		await _frames(40)
		var on: Array = lamps.filter(func(l): return l.shadow_enabled)
		var by_dist: Array = lamps.duplicate()
		by_dist.sort_custom(func(a, b): return a.global_position.distance_to(p.global_position) < b.global_position.distance_to(p.global_position))
		_check(on.size() == gfx.SHADOW_BUDGET[gfx.Preset.MEDIUM] and on.all(func(l): return l in by_dist.slice(0, on.size())), "  Medium at x=%d: the %d nearest lamps cast shadows, the rest don't (%d on)" % [x, gfx.SHADOW_BUDGET[gfx.Preset.MEDIUM], on.size()])
	# The moon: barely there at night, and its shadow pass costs ~3.5 ms on
	# the street. Medium and Low drop it after dark; the sun keeps its own.
	var moon: DirectionalLight3D = city.get_node("Moon")
	_check(not moon.shadow_enabled, "  Medium at night: the moon casts no shadow")
	gs.clock = 13 * 60
	gs.advance_clock(1)
	await _frames(40)
	_check(moon.shadow_enabled, "  ...by day the sun does")
	gfx.set_preset(gfx.Preset.HIGH)
	gs.clock = 21 * 60
	gs.advance_clock(1)
	await _frames(40)
	_check(moon.shadow_enabled, "  High keeps the moon's shadow at night")
	var env: Environment = city.find_children("*", "WorldEnvironment", true, false)[0].environment
	gfx.set_preset(gfx.Preset.MEDIUM)
	await _frames(5)
	_check(env.glow_enabled, "  Medium keeps the neon glow")
	gfx.set_preset(gfx.Preset.LOW)
	await _frames(40)
	_check(not env.glow_enabled, "  Low: no glow pass (3.5 ms)")
	_check(lamps.all(func(l): return not l.shadow_enabled), "  Low: no lamp shadows")
	gfx.set_preset(gfx.Preset.PS5)
	await _frames(40)
	_check(lamps.all(func(l): return l.shadow_enabled), "  PS5: every lamp, as built")
	gfx.set_preset(before)
	# An integrated GPU left on High (or PS5) is moved to Medium, once.
	_check(gfx.migrate_preset(gfx.Preset.HIGH, 2, true) == gfx.Preset.MEDIUM and gfx.migrate_preset(gfx.Preset.PS5, 2, true) == gfx.Preset.MEDIUM, "  integrated GPU on High: moved to Medium")
	_check(gfx.migrate_preset(gfx.Preset.HIGH, 3, true) == gfx.Preset.HIGH, "  ...once: put it back with F3 and it stays")
	_check(gfx.migrate_preset(gfx.Preset.HIGH, 2, false) == gfx.Preset.HIGH and gfx.migrate_preset(gfx.Preset.LOW, 2, true) == gfx.Preset.LOW, "  ...a real GPU, or Low, is left alone")
	gs.start_run()

func _ambience_checks(gs: Node) -> void:
	await _section("Every place sounds like itself: a real recording each")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	var Ambience = load("res://world/PlaceAmbience.gd")
	var credits := FileAccess.get_file_as_string("res://assets/sfx/places/CREDITS.txt")
	for scene in Ambience.PLACES:
		var room := await _load("res://world/%s.tscn" % scene)
		var p := room.get_node_or_null("PlaceAmbience") as AudioStreamPlayer
		var stream := p.stream if p else null
		var ok: bool = p != null and p.playing and p.bus == "Ambience" and stream is AudioStreamOggVorbis and stream.loop and stream.get_length() >= 30.0
		var tone := room.get_node_or_null("RoomTone") as AudioStreamPlayer
		var no_double: bool = tone == null or not tone.playing
		var file: String = Ambience.PLACES[scene][0]
		_check(ok and no_double and credits.contains(file.get_file()), "  %s: %s, looping on Ambience, credited%s" % [scene, file.get_file(), "" if no_double else " (old room tone still on)"])
	gs.start_run()

func _cast_checks(gs: Node) -> void:
	await _section("Realistic people: Microsoft Rocketbox avatars for the whole cast")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var Cast = load("res://npc/CharacterCast.gd")
	var roles: Array = Cast.CAST.keys() + Cast.PATRONS.keys() + ["homeless"]
	var bad := []
	for role in roles:
		var path: String = Cast.model_for(role)
		if not path.begins_with("res://assets/rocketbox/") or not ResourceLoader.exists(path):
			bad.append("%s (%s)" % [role, path])
	for e in Cast.PASSERSBY:
		if not String(e["model"]).begins_with("res://assets/rocketbox/") or not ResourceLoader.exists(e["model"]):
			bad.append("passerby " + e["model"])
	_check(bad.is_empty(), "  every role, regular and passer-by is a Rocketbox person (%s)" % [bad])
	var model: Node3D = load(Cast.model_for("player")).instantiate()
	root.add_child(model)
	Cast.dress(model, "player")
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var clips: Array = Array(ap.get_animation_list()) if ap else []
	_check(["idle", "walk", "sprint", "sit", "walk_sick", "idle_sick"].all(func(c): return c in clips), "  ...with the clips the game plays (%s)" % [clips])
	var skins := 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat = mi.get_active_material(i)
			if mat is BaseMaterial3D and mat.albedo_texture != null:
				skins += 1
	# Tasha has hair cards (an "*_opacity" surface); the player doesn't.
	var tasha: Node3D = load(Cast.model_for("booster")).instantiate()
	root.add_child(tasha)
	Cast.dress(tasha, "booster")
	var cutout := false
	for mi in tasha.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var mat = mi.get_active_material(i)
			if mat is BaseMaterial3D and mat.resource_name.ends_with("opacity"):
				cutout = mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	tasha.free()
	_check(cutout and skins >= 2, "  ...textured, with hair and lashes cut out rather than blended (%d textured surfaces)" % skins)
	var aabb := AABB()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		aabb = mi.get_aabb() if aabb.size == Vector3.ZERO else aabb.merge(mi.get_aabb())
	model.free()
	# In withdrawal you walk like it.
	var apt := await _load("res://world/Apartment3D.tscn")
	var p := _player()
	p.dialogue_active = false
	gs.craving = 5.0
	Input.action_press("move_right")
	await _frames(20)
	var sick_walk: String = p.anim._player.current_animation
	Input.action_release("move_right")
	await _frames(20)
	var sick_idle: String = p.anim._player.current_animation
	gs.craving = 80.0
	Input.action_press("move_right")
	await _frames(20)
	var well_walk: String = p.anim._player.current_animation
	Input.action_release("move_right")
	_check(sick_walk == "walk_sick" and sick_idle == "idle_sick" and well_walk == "walk", "  sick, you shuffle and fidget; well, you walk (%s / %s / %s)" % [sick_walk, sick_idle, well_walk])
	gs.start_run()

const WORLD_ART_PBR := ["road_worn", "sidewalk_slabs", "curb", "tiles_white", "tiles_beige", "plaster_painted",
	"bricks_old", "wood_dark", "leather_red", "felt", "metal_worn", "metal_brushed"]
const WORLD_ART_MODELS := ["modular_urban_apartments_facade", "modular_factory_facade", "modular_fire_escape",
	"street_lamp_01", "covered_car", "exterior_aircon_unit", "rollershutter_window_01", "security_camera_02",
	"old_bed_frame", "metal_trash_can", "pull_chain_light_socket", "wall_clock",
	"bar_chair_round_01", "metal_stool_01", "wine_bottles_01", "WoodenTable_01", "hanging_industrial_lamp",
	"steel_frame_shelves_01", "mounted_fluorescent_lights"]

func _world_art_checks(gs: Node) -> void:
	await _section("World art: real places, same game")
	var missing := []
	for s in WORLD_ART_PBR:
		for m in ["_diff.jpg", "_nor.jpg", "_rough.jpg"]:
			if not ResourceLoader.exists("res://assets/pbr/" + s + m):
				missing.append(s + m)
	for id in WORLD_ART_MODELS:
		if not ResourceLoader.exists("res://assets/polyhaven/%s/%s.gltf" % [id, id]):
			missing.append(id)
	_check(missing.is_empty(), "  every material and model is on disk (%s)" % [missing])
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	var kenney := city.find_children("*", "Node3D", false, false).filter(func(n): return String(n.scene_file_path).contains("kenney/city"))
	_check(kenney.is_empty(), "  no Kenney toy buildings left on the street (%s)" % [kenney.map(func(n): return n.name)])
	var fronts: Node = city.get_node_or_null("Facades")
	var names := ["Police", "Home", "Pharmacy", "Bar", "Shop", "Liquor", "Supermarket", "Electronics", "Karts", "Pawn", "Music", "Shelter"]
	_check(fronts != null and names.all(func(n): return fronts.get_node_or_null("Front" + n) != null), "  every building has a real front")
	# Gameplay stays: doors and the station door where they were.
	var doors := ["DoorToHome", "DoorToPharmacy", "DoorToBar", "DoorToShop", "DoorToLiquor", "DoorToSupermarket",
		"DoorToElectronics", "DoorToKarts", "DoorToPawn", "DoorToMusic", "DoorToShelter", "StationDoor"]
	_check(doors.all(func(d): return city.find_child(d, true, false) != null), "  every door is still there")
	if fronts:
		# Fronts sit behind the signs: nothing of a facade pokes in front of
		# z = -4.5 at sign height or below (fire escapes stand out above it).
		var poking := []
		for mi in fronts.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			if b.end.z > -4.5 + 0.001 and b.position.y < 3.45:
				poking.append(mi.name)
		_check(poking.is_empty(), "  fronts sit behind the signs and plates (%s)" % [poking.slice(0, 5)])
	# Shutters by opening hours, right from load.
	gs.clock = 3 * 60
	city = await _load("res://world/City3D.tscn")
	var ph: Node = city.get_node_or_null("Facades/FrontPharmacy")
	_check(ph != null and ph.get_node("Shutter").visible and not ph.get_node("Glow").visible, "  a closed shop has its shutter down on load (state on load)")
	gs.clock = 14 * 60
	gs.advance_clock(1)
	await _frames(2)
	_check(ph != null and not ph.get_node("Shutter").visible and ph.get_node("Glow").visible, "  ...and up, lit, when it opens")
	# Posters still land on a wall: each wall decal's box reaches the facade plane.
	var short := city.find_children("*", "Decal", true, false).filter(func(d): return d.global_position.z > -4.8 and d.global_position.z - d.size.y / 2.0 > -4.5 - 0.02 and absf(d.global_rotation_degrees.x) > 45)
	_check(short.is_empty(), "  posters and graffiti still reach the wall (%s)" % [short.map(func(d): return d.name)])
	gs.clock = 14 * 60
	city = await _load("res://world/City3D.tscn")
	var lamps := city.find_children("Streetlight*", "StaticBody3D", false, false)
	_check(lamps.size() > 0 and lamps.all(func(l): return l.get_node_or_null("Model") != null and l.get_node_or_null("Light") != null and l.get_node_or_null("Pole") == null),
		"  street lamps are real lamps, same light (%d)" % lamps.size())
	var cars := city.find_children("Car*", "StaticBody3D", false, false) + city.find_children("PoliceCruiser", "StaticBody3D", false, false)
	_check(cars.size() > 0 and cars.all(func(c): return c.get_node_or_null("Body") == null and c.get_node_or_null("Model") != null and c.find_children("*", "CollisionShape3D", false, false).size() > 0),
		"  parked cars are cars, not boxes, and still solid (%d)" % cars.size())
	var road := city.get_node("Road") as MeshInstance3D
	var walk := city.get_node("Sidewalk") as MeshInstance3D
	var road_tex := String((road.mesh.material as StandardMaterial3D).albedo_texture.resource_path) if road.mesh.material else ""
	var walk_tex := String((walk.mesh.material as StandardMaterial3D).albedo_texture.resource_path) if walk.mesh.material else ""
	_check(road_tex.contains("road_worn") and walk_tex.contains("sidewalk_slabs") and city.get_node_or_null("Curb") != null,
		"  worn asphalt, paving slabs and a curb underfoot (%s, %s)" % [road_tex.get_file(), walk_tex.get_file()])
	_check(city.get_node("Facades").find_children("FireEscape*", "Node3D", true, false).size() >= 2, "  fire escapes on the apartment blocks")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var apt := await _load("res://world/Apartment3D.tscn")
	var uses := func(node: Node, id: String) -> bool: return node.find_children("*", "Node3D", true, false).any(func(n): return String(n.scene_file_path).contains("/" + id + "/"))
	_check(uses.call(apt.get_node("Bed"), "old_bed_frame") and uses.call(apt.get_node("Couch"), "sofa_02") and uses.call(apt.get_node("ChairOverturned"), "plastic_monobloc_chair_01"),
		"  apartment: a real bed frame, sofa and chair")
	_check(apt.get_node("Bed").get_node_or_null("Mattress") != null, "  ...the stained mattress still on the frame")
	var toys: Array = apt.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("kenney/furniture"))
	_check(toys.size() <= 2, "  ...and little left of the toy furniture (%s)" % [toys.map(func(n): return n.name)])
	# A belonging that's away (pawned) still disappears with its new model
	# (Review Focus 5). Carried ones go back home when you walk in.
	gs.take_belonging("tv")
	gs.inventory.erase("tv")
	gs.pawn_belonging("tv")
	apt = await _load("res://world/Apartment3D.tscn")
	_check(not apt.get_node("TV").visible, "  a taken TV is gone from the room")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 20 * 60
	var bar := await _load("res://world/DiveBar3D.tscn")
	var stools := bar.find_children("Stool*", "Node3D", false, false)
	_check(stools.size() == 5 and stools.all(func(s): return String(s.scene_file_path).contains("polyhaven")), "  bar: real stools (%d)" % stools.size())
	var tex_of := func(mi: MeshInstance3D) -> String:
		var m := (mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)) as StandardMaterial3D
		return String(m.albedo_texture.resource_path) if m and m.albedo_texture else ""
	_check(tex_of.call(bar.get_node("BarCounter/WornTop")).contains("wood_dark") and tex_of.call(bar.get_node("BoothA/SeatN")).contains("leather_red") and tex_of.call(bar.get_node("PoolTable/Felt")).contains("felt"),
		"  ...wood, vinyl and felt that look like wood, vinyl and felt")
	_check(bar.find_children("BackBarBottles*", "Node3D", true, false).size() > 0 and bar.get_node_or_null("PoolLamp/Model") != null, "  ...real bottles behind the bar and a lamp over the pool table")
	_check(bar.get_node_or_null("PoolTable/PoolZone") != null and bar.get_node_or_null("Jukebox") != null, "  ...and the pool table and jukebox still play")
	gs.clock = 14 * 60
	for store in ["StoreConvenience3D", "StorePharmacy3D", "StoreSupermarket3D", "StoreLiquor3D", "StoreElectronics3D"]:
		var room := await _load("res://world/%s.tscn" % store)
		var toy := room.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("bookcaseOpen") or String(n.scene_file_path).contains("kitchenBar"))
		var tubes := room.find_children("StripFixture*", "Node3D", false, false)
		var blockers := room.find_children("Fixture*", "StaticBody3D", false, false).all(func(f): return f.find_children("*", "CollisionShape3D", false, false).size() > 0)
		_check(toy.is_empty() and tubes.size() > 0 and tubes.all(func(t): return String(t.scene_file_path).contains("mounted_fluorescent")) and blockers,
			"  %s: steel shelving, real tube lights, same sight blockers (toys %d)" % [store, toy.size()])

## Chapter 2: going through a door shouldn't freeze the game for seconds,
## and the game should say where you are and what E does.
func _polish_checks(gs: Node) -> void:
	await _section("Polish: fast rooms, fades, prompts")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	var piece := _kit_piece(city)
	var mesh_id := piece.mesh.get_instance_id()
	var dressing := func(c: Node) -> Array:
		return ["FireEscapeHome", "AirCon", "Camera", "Shutter"].map(func(n): return c.get_node("Facades").find_child(n + "*", true, false).find_children("*", "MeshInstance3D", true, false)[0].mesh.get_instance_id())
	var dress_ids: Array = dressing.call(city)
	var Cast = load("res://npc/CharacterCast.gd")
	var booster: String = Cast.model_for("booster")
	var cast_id: int = Cast.scene_for(booster).get_instance_id()
	piece = null
	await _load("res://world/Apartment3D.tscn")
	await _load("res://world/DiveBar3D.tscn")
	var t0 := Time.get_ticks_msec()
	city = await _load("res://world/City3D.tscn")
	var reentry := Time.get_ticks_msec() - t0
	var again := _kit_piece(city)
	_check(again.mesh.get_instance_id() == mesh_id, "  facade kit pieces are loaded once per session")
	_check(dressing.call(city) == dress_ids, "  ...and so are fire escapes, air-con units, cameras and shutters")
	_check(Cast.scene_for(booster).get_instance_id() == cast_id
		and Cast.scene_for(booster) is PackedScene, "  character models are loaded once per session")
	print("  (City re-entry %d ms)" % reentry)
	# Rooms stay loaded, materials and all: leaving in the rain mustn't
	# leave the street wet for good.
	root.get_node("SceneLoader")._scene("res://world/City3D.tscn")
	gs.set_raining(true)
	city = await _load("res://world/City3D.tscn")
	await _load("res://world/Apartment3D.tscn")
	city = await _load("res://world/City3D.tscn")
	gs.set_raining(false)
	await _frames(3)
	var wet: Array = city.get_node("StreetLife")._wet_materials
	_check(wet.size() > 0 and wet.all(func(m): return m.roughness > 0.5), "  the street dries off after rain, even across visits")
	await _room_change_checks(gs)
	await _loader_edge_checks(gs)
	_step_down_checks()
	await _prompt_checks(gs)

## The first facade piece that came out of a Poly Haven kit (not a box or
## quad the builder made itself).
func _kit_piece(city: Node) -> MeshInstance3D:
	for mi in city.get_node("Facades").find_children("*", "MeshInstance3D", true, false):
		if not (mi.mesh is PrimitiveMesh):
			return mi
	return null

## Interacts with a door and waits for the room change (fade and all).
func _through(door: Node) -> void:
	door.interact(_player())
	await _transition()

func _transition() -> void:
	var loader := root.get_node("SceneLoader")
	for i in 600:
		await process_frame
		if not loader.busy():
			break
	await _frames(10)

func _room_change_checks(gs: Node) -> void:
	var loader := root.get_node("SceneLoader")
	# The street is the hub: it starts loading in the background as soon
	# as you're anywhere, facade kits and all.
	await _load("res://world/Apartment3D.tscn")
	var warm: Array = ["res://world/City3D.tscn"] + load("res://world/Facades.gd").WARM
	for i in 600:
		await _frames(1)
		if warm.all(func(p): return loader.cached(p)):
			break
	_check(warm.all(func(p): return loader.cached(p)), "  the street warms up in the background from the first room")
	var city := await _load("res://world/City3D.tscn")
	var door := city.get_node("DoorToBar")
	var target: String = door.target_scene
	var spawn: String = door.target_spawn
	var player := _player()
	player.global_position = door.global_position + Vector3(0, 0, 2.5)
	for i in 300:
		await _frames(1)
		if loader.cached(target):
			break
	_check(loader.cached(target), "  walking up to a door loads the room behind it")
	door.interact(player)
	_check(loader.busy(), "  doors go through the scene loader")
	var longest := 0
	var last := Time.get_ticks_msec()
	var darkest := 0.0
	for i in 600:
		await process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
		darkest = maxf(darkest, loader.find_child("Fade", true, false).color.a)
		if not loader.busy():
			break
	await _frames(30)
	var fade: ColorRect = loader.find_child("Fade", true, false)
	var card: Label = loader.find_child("ArrivalCard", true, false)
	_check(current_scene.name == "DiveBar3D" and darkest > 0.99 and fade.color.a < 0.01,
		"  the room fades to black and back in (darkest %.2f, now %.2f)" % [darkest, fade.color.a])
	_check(longest < 500, "  no frame of the change froze for half a second (longest %d ms)" % longest)
	_check(card.text.begins_with("THE DIVE BAR") and card.text.ends_with(gs.clock_text()) and card.modulate.a > 0.5,
		"  an arrival card says where and when ('%s')" % card.text)
	_check(_player().global_position.distance_to(current_scene.get_node(spawn).global_position) < 0.5,
		"  the player arrives at the door's spawn point")

func _step_down_checks() -> void:
	var gfx := root.get_node("Graphics")
	var feed := func(fps: float, windows: int) -> void:
		for i in windows:
			gfx.watch_high(fps, 0.5)
	gfx._integrated = true
	gfx._stepped_down = false
	gfx.set_preset(gfx.Preset.HIGH)
	feed.call(15.0, 9)
	_check(gfx.preset == gfx.Preset.HIGH, "  4.5 s too slow on High: not yet")
	feed.call(60.0, 1)
	feed.call(15.0, 9)
	_check(gfx.preset == gfx.Preset.HIGH, "  a good half-second starts the count over")
	feed.call(15.0, 10)
	_check(gfx.preset == gfx.Preset.MEDIUM and gfx._toast.text.contains("F3"),
		"  5 s too slow on High, laptop graphics: down to Medium, and it says why ('%s')" % gfx._toast.text)
	gfx.set_preset(gfx.Preset.HIGH)
	feed.call(15.0, 40)
	_check(gfx.preset == gfx.Preset.HIGH, "  pick High again and it stays High this session")
	gfx._integrated = false
	gfx._stepped_down = false
	feed.call(15.0, 40)
	_check(gfx.preset == gfx.Preset.HIGH, "  a real graphics card is left alone")
	gfx.set_preset(gfx.Preset.MEDIUM)

const PROMPT_ROOMS := ["Apartment3D", "Backyard3D", "City3D", "DiveBar3D", "Jail3D", "KartCenter3D", "MusicStore3D",
	"Pawn3D", "Shelter3D", "StoreConvenience3D", "StoreElectronics3D", "StoreLiquor3D", "StorePharmacy3D", "StoreSupermarket3D"]

func _prompt_checks(gs: Node) -> void:
	var Prompts = load("res://ui/Prompts.gd")
	gs.clock = 20 * 60
	var city := await _load("res://world/City3D.tscn")
	_check(Prompts.text_for(city.get_node("DoorToBar")) == "Enter the Dive Bar", "  a door says where it goes ('%s')" % Prompts.text_for(city.get_node("DoorToBar")))
	_check(Prompts.text_for(city.get_node("DoorToHome")) == "Go home", "  your own door says 'Go home'")
	var pusher := get_first_node_in_group("pusher")
	if pusher == null:
		pusher = city.find_children("*", "Area3D", true, false).filter(func(n): return n.get_script() and n.get_script().resource_path.ends_with("Pusher3D.gd")).front()
	_check(Prompts.text_for(pusher).begins_with("Talk to"), "  the dealer: '%s'" % Prompts.text_for(pusher))
	# Walk up to the bar door: the prompt floats over it with the key.
	var door := city.get_node("DoorToBar")
	_player().global_position = door.global_position
	await _frames(12)
	var prompt: Label = get_first_node_in_group("hud").find_child("InteractPrompt", true, false)
	_check(prompt != null and prompt.visible and prompt.text == "%s  Enter the Dive Bar" % gs.control_name("interact"),
		"  standing at a door shows '%s'" % (prompt.text if prompt else "no prompt"))
	_player().dialogue_active = true
	await _frames(3)
	_check(not prompt.visible, "  hidden while talking")
	_player().dialogue_active = false
	var bar := await _load("res://world/DiveBar3D.tscn")
	var patron: Node = bar.patrons[0]
	_check(Prompts.text_for(patron).begins_with("Talk to ") and Prompts.text_for(bar.get_node("Bartender")) == "Talk to the bartender",
		"  people: '%s', '%s'" % [Prompts.text_for(patron), Prompts.text_for(bar.get_node("Bartender"))])
	var shop := await _load("res://world/StoreConvenience3D.tscn")
	var item: Node = shop.find_children("*", "Area3D", true, false).filter(func(n): return "item_id" in n).front()
	_check(Prompts.text_for(item) == "Steal %s" % gs.item_info(item.item_id)["name"], "  a shelf item: '%s'" % Prompts.text_for(item))
	var home := await _load("res://world/Apartment3D.tscn")
	_check(Prompts.text_for(home.get_node("Bed")) == "Sleep" and Prompts.text_for(home.get_node("Belonging_guitar")) == "Your guitar",
		"  the bed and your things: '%s', '%s'" % [Prompts.text_for(home.get_node("Bed")), Prompts.text_for(home.get_node("Belonging_guitar"))])
	# Zones named after what they are keep their words even when Godot has
	# to rename one (two bottles at the same spot), and the people the
	# street spawns by name say who they are.
	city = await _load("res://world/City3D.tscn")
	var jobs := root.get_node("Jobs")
	var b1: Node = jobs._zone(city, "Bottle77", Vector3(1, 0, -2), func(_z, _p): pass)
	var b2: Node = jobs._zone(city, "Bottle77", Vector3(1, 0, -2), func(_z, _p): pass)
	_check(Prompts.text_for(b1) == "Pick up the bottle" and Prompts.text_for(b2) == "Pick up the bottle", "  two bottles in one spot both say 'Pick up the bottle' ('%s')" % Prompts.text_for(b2))
	var alley: Node = city.find_child("AlleyOverdose", true, false)
	alley._build_victim("Quiet Kid")
	_check(Prompts.text_for(alley.victim) == "Help them", "  someone down in the alley: '%s'" % Prompts.text_for(alley.victim))
	# Everything you can use, in every room, says something.
	var silent := []
	for room in PROMPT_ROOMS:
		var r := await _load("res://world/%s.tscn" % room)
		for n in get_nodes_in_group("interactable"):
			if n.has_method("interact") and (Prompts.text_for(n) == "" or Prompts.text_for(n) == n.name.capitalize()):
				silent.append("%s/%s (%s)" % [room, n.name, n.get_script().resource_path.get_file() if n.get_script() else "-"])
	_check(silent.is_empty(), "  every interactable in every room has a prompt (silent: %s)" % [silent])

## The review's edge cases for SceneLoader.
func _loader_edge_checks(gs: Node) -> void:
	var loader := root.get_node("SceneLoader")
	var fade: ColorRect = loader.find_child("Fade", true, false)
	var card: Label = loader.find_child("ArrivalCard", true, false)
	var city := await _load("res://world/City3D.tscn")
	loader.go("res://world/NoSuchRoom3D.tscn")
	await _transition()
	await _frames(30)
	_check(current_scene == city and not paused and fade.color.a < 0.01 and not loader.busy(),
		"  a room that won't load leaves you where you were, not in the dark")
	# Through a door just as a bust lands: the cell wins.
	city.get_node("DoorToBar").interact(_player())
	loader.go("res://world/Jail3D.tscn", "SpawnCell")
	for i in 3:
		await _transition()
	_check(current_scene.name == "Jail3D" and _player().global_position.distance_to(current_scene.get_node("SpawnCell").global_position) < 0.5,
		"  a bust during a door's fade still ends in the cell (%s)" % current_scene.name)
	# Under a cutscene (the last bust's "sent away"): no fade, no card over it.
	await _load("res://world/City3D.tscn")
	root.get_node("Cutscene")._playing = true
	var darkest := 0.0
	loader.go("res://world/Jail3D.tscn", "SpawnCell")
	for i in 120:
		await process_frame
		darkest = maxf(darkest, fade.color.a)
		if not loader.busy():
			break
	await _frames(10)
	root.get_node("Cutscene")._playing = false
	_check(current_scene.name == "Jail3D" and darkest < 0.01 and card.modulate.a < 0.01,
		"  under a cutscene the room changes unseen (darkest %.2f, card %.2f)" % [darkest, card.modulate.a])

## Cutscenes are real footage now: one clip each, three seconds at most.
func _cutscene_video_checks() -> void:
	await _section("Cutscenes: real footage, 3 s max")
	var cut := root.get_node("Cutscene")
	var missing := []
	for id in cut.SCENES:
		var path: String = cut.video_for(id)
		if path == "" or not ResourceLoader.exists(path) or not (load(path) is VideoStream):
			missing.append(id)
	_check(missing.is_empty(), "  every cutscene has a clip (missing %s)" % [missing])
	_check(cut.VIDEO_MAX <= 3.0, "  a cutscene lasts at most 3 s (%.1f)" % cut.VIDEO_MAX)
	var long := []
	for id in cut.SCENES:
		if cut.VIDEOS[id]["text"].length() > 60:
			long.append(id)
	_check(long.is_empty(), "  every caption reads in 3 s (too long: %s)" % [long])

## Laptop graphics on Medium: the lean profile that holds 60 FPS walking.
func _lean_checks(gs: Node) -> void:
	await _section("Smooth: Medium holds 60 on laptop graphics")
	var gfx := root.get_node("Graphics")
	gfx._integrated = true
	gfx.set_preset(gfx.Preset.MEDIUM)
	gs.clock = 21 * 60
	var city := await _load("res://world/City3D.tscn")
	await _frames(20)
	var env: Environment = city.get_node("WorldEnvironment").environment
	var kit_mat: BaseMaterial3D = _kit_piece(city).get_active_material(0)
	var shadows: int = city.find_children("*", "OmniLight3D", true, false).filter(func(l): return l.shadow_enabled).size() \
		+ city.find_children("*", "SpotLight3D", true, false).filter(func(l): return l.shadow_enabled).size()
	_check(gfx.lean() and not env.ssao_enabled and env.glow_enabled and not env.get_glow_level(4) and not kit_mat.normal_enabled and shadows <= 1,
		"  lean Medium: no AO, near glow only, flat facades, one lamp shadow (ssao %s, glow4 %s, normals %s, shadows %d)" % [env.ssao_enabled, env.get_glow_level(4), kit_mat.normal_enabled, shadows])
	_check(gfx.SCALE_RANGE_LEAN[0] <= 0.6, "  and resolution may drop to 60% to hold it")
	_check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "  FXAA instead of SMAA (-1.3 ms)")
	_check(gfx._shadow_filter == RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "  cheaper soft-shadow filtering (-1.1 ms)")
	var sun: DirectionalLight3D = city.get_node("Moon")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and sun.directional_shadow_max_distance <= 35.0,
		"  the sun's shadow covers what the camera sees, not 100 m (%d splits mode, %.0f m)" % [sun.directional_shadow_mode, sun.directional_shadow_max_distance])
	_check(gfx.STEP_DOWN_FPS >= 45.0, "  High on laptop graphics steps down below 45 FPS, not 24")
	gfx._integrated = false
	gfx.set_preset(gfx.Preset.MEDIUM)
	await _frames(20)
	_check(not gfx.lean() and gfx._shadow_filter == RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM and env.ssao_enabled and kit_mat.normal_enabled and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"  a real graphics card keeps the full Medium")

## Background loads fight the game for the CPU: several at once (the street
## has doors every few metres) made the first seconds there stutter.
func _one_load_at_a_time_checks() -> void:
	var loader := root.get_node("SceneLoader")
	var most := 0
	for path in ["res://world/StoreLiquor3D.tscn", "res://world/StorePharmacy3D.tscn", "res://world/Pawn3D.tscn"]:
		loader._scenes.erase(path)
		loader.prefetch(path)
		most = maxi(most, loader._loading.size())
	var done := false
	for i in 900:
		await _frames(1)
		most = maxi(most, loader._loading.size())
		if loader.cached("res://world/StoreLiquor3D.tscn") and loader.cached("res://world/StorePharmacy3D.tscn") and loader.cached("res://world/Pawn3D.tscn"):
			done = true
			break
	_check(most <= 1 and done, "  rooms load in the background one at a time, and all get there (most at once %d)" % most)

## Low on laptop graphics, and the HUD's screen pass when you're well.
func _low_checks(gs: Node) -> void:
	await _section("Smooth: Low and the HUD pass")
	var gfx := root.get_node("Graphics")
	gfx._integrated = true
	gfx.set_preset(gfx.Preset.LOW)
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	_check(gfx.lean() and root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA and not _kit_piece(city).get_active_material(0).normal_enabled,
		"  Low on laptop graphics is lean too: FXAA, flat facades")
	var post: ColorRect = get_first_node_in_group("hud").get_node("PostFX")
	gs.craving = 100.0
	gs.craving_changed.emit(gs.craving)
	await _frames(2)
	var lite: bool = not String((post.material as ShaderMaterial).shader.code).contains("hint_screen_texture")
	_check(lite, "  well: vignette and grain without copying the screen")
	gs.craving = 0.0
	gs.craving_changed.emit(gs.craving)
	await _frames(2)
	_check(gs.sickness() > 0.0 and String((post.material as ShaderMaterial).shader.code).contains("hint_screen_texture"),
		"  sick: the full swimming, doubled, drained screen")
	gs.craving = 100.0
	gs.craving_changed.emit(gs.craving)
	gfx._integrated = false
	gfx.set_preset(gfx.Preset.MEDIUM)

## Resolution follows the GPU's frame time, so it settles under 60 FPS's
## 16.7 ms instead of creeping up whenever vsync shows 58.
func _scaler_checks() -> void:
	var gfx := root.get_node("Graphics")
	gfx._integrated = true
	gfx.set_preset(gfx.Preset.LOW)
	var s: float = 0.8
	_check(gfx.next_scale(s, 58.0, 16.2) < s, "  GPU over budget (16.2 ms at 58 FPS): resolution comes down")
	_check(is_equal_approx(gfx.next_scale(s, 60.0, 14.0), s), "  14 ms: stays put")
	_check(gfx.next_scale(s, 60.0, 11.0) > s, "  11 ms: room to sharpen, goes up")
	_check(gfx.next_scale(s, 40.0, 0.0) < s, "  no GPU timing: falls back to the frame rate")
	gfx._integrated = false
	gfx.set_preset(gfx.Preset.MEDIUM)

## The laptop at home: a darknet market. Cheaper than the corner and fewer
## fakes, but you wait a day, and some vendors take your money and vanish,
## and some packages get opened by the post office.
func _darknet_checks(gs: Node) -> void:
	await _section("Silk Lane: ordering from the laptop at home")
	var Darknet = load("res://world/Darknet.gd")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var home := await _load("res://world/Apartment3D.tscn")
	var laptop: Node = home.get_node_or_null("Laptop")
	_check(laptop != null and laptop.is_in_group("interactable") and load("res://ui/Prompts.gd").text_for(laptop) == "Use the laptop",
		"  a laptop at home says 'Use the laptop'")
	_check(laptop.find_children("*", "Node3D", true, false).any(func(n): return String(n.scene_file_path).contains("classic_laptop")), "  ...and it's a real laptop, not two boxes")
	_check(SaveGame_has_field("parcel"), "  an order in the post is saved with the run")
	var street: int = gs.price_of("heroin")
	var price: int = Darknet.price("heroin")
	_check(price < street, "  cheaper than the corner ($%d vs $%d)" % [price, street])
	gs.cash = 100
	_check(Darknet.order("heroin", "ok"), "  ordering works")
	_check(gs.cash == 100 - price and not gs.parcel.is_empty() and gs.parcel["day"] == gs.day + 1, "  paid, and it ships for tomorrow")
	_check(not Darknet.order("heroin", "ok"), "  one order at a time")
	_check(home.get_node_or_null("Package") == null, "  nothing on the mat today")
	# Next morning.
	gs.day += 1
	gs.clock = 10 * 60
	home = await _load("res://world/Apartment3D.tscn")
	var box: Node = home.get_node_or_null("Package")
	_check(box != null and load("res://ui/Prompts.gd").text_for(box) == "Open the package", "  next morning there's a package inside the door")
	gs.craving = 10.0
	var outcome: String = Darknet.open_package(box, false)
	_check(gs.parcel.is_empty() and outcome in ["relief", "precipitated", "overdose", "saved"] and gs.craving > 10.0 or outcome != "relief",
		"  opening it, you take what came (%s, craving %.0f)" % [outcome, gs.craving])
	await _frames(2)
	_check(home.get_node_or_null("Package") == null or home.get_node("Package").is_queued_for_deletion(), "  ...and the box is gone")
	# The vendor who took the money and ran.
	gs.cash = 100
	Darknet.order("oxy", "scam")
	gs.day += 1
	gs.clock = 9 * 60 + 59
	gs._last_minute = 9 * 60 + 59
	gs.clock = 10 * 60
	gs._emit_clock()
	home = await _load("res://world/Apartment3D.tscn")
	_check(home.get_node_or_null("Package") == null and gs.parcel.get("fate", "") == "scam", "  an exit scam: no package")
	_check(Darknet.laptop_text().contains("gone") and gs.parcel.is_empty(), "  the laptop tells you the vendor's gone, and the order's done with")
	# Opened at the post office.
	gs.warrant = false
	Darknet.order("meth", "seized")
	gs.day += 1
	gs._last_minute = 9 * 60 + 30
	gs.clock = 10 * 60
	gs._emit_clock()
	_check(gs.warrant and gs.parcel.is_empty(), "  a package seized in the post: there's a warrant out")
	gs.warrant = false

func SaveGame_has_field(f: String) -> bool:
	return f in root.get_node("SaveGame").FIELDS

## The second world-art pass: jail, pawnshop, shelter, Tape Deck, kart
## track, backyard. Real models in, toy boxes out -- and nothing the game
## touches moved (dev-tools/world_art2_baseline.json, gameplay_snapshot.gd).
const WORLD_ART_2_MIN_MODELS := 6

## Same position and shape, to the centimetre.
func _same_place(a: Dictionary, b: Dictionary) -> bool:
	for key in ["pos", "shape"]:
		var x: Array = a.get(key, [])
		var y: Array = b.get(key, [])
		if x.size() != y.size():
			return false
		for i in x.size():
			if absf(float(x[i]) - float(y[i])) > 0.011:
				return false
	return true
func _world_art_2_checks() -> void:
	await _section("World art II: the rest of the block")
	var Snap = load("res://dev-tools/gameplay_snapshot.gd")
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dev-tools/world_art2_baseline.json"))
	# As recorded: a quiet morning, so the backyard has its delivery.
	var gs := _gs()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 7 * 60
	root.get_node("Headlines").forced = "quiet"
	root.get_node("Headlines").roll(gs.day)
	for r in base:
		var room: Node = load("res://world/%s.tscn" % r).instantiate()
		root.add_child(room)
		var now: Dictionary = Snap.snapshot(room)
		var moved := []
		for k in base[r]:
			if not now.has(k) or not _same_place(now[k], base[r][k]):
				moved.append("%s %s->%s" % [k, base[r][k], now.get(k, "gone")])
		var models: int = room.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("assets/polyhaven")).size()
		_check(moved.is_empty(), "  %s: every door, zone, spawn and collider where it was (moved %s)" % [r, moved.slice(0, 4)])
		_check(models >= WORLD_ART_2_MIN_MODELS, "  %s: real models, not toy boxes (%d)" % [r, models])
		room.free()
		await process_frame

## The story: Mia, Ray and Dana across the week (autoload/Story.gd).
func _hour(gs: Node, d: int, h: int) -> void:
	gs.day = d
	gs._last_minute = h * 60 - 1
	gs.clock = h * 60
	gs._emit_clock()

func _story_checks(gs: Node) -> void:
	await _section("Story: Mia, Ray and Dana")
	var story := root.get_node("Story")
	gs.start_run()
	gs.clock_running = false
	_check("story" in root.get_node("SaveGame").FIELDS, "  the story is saved with the run")
	_hour(gs, 1, 10)
	_check(story.messages().any(func(m): return m["from"] == "Mia" and m["text"].contains("birthday")), "  day 1: Mia texts about Mom's birthday")
	_check("Messages" in load("res://ui/Notebook.gd").PAGES, "  the notebook has a Messages page")
	# Ray, day 2: wants out. Help him and he lives.
	_hour(gs, 2, 12)
	_check(story.ray_wants_out(), "  day 2: Ray says he wants to stop")
	gs.naloxone = 1
	story.help_ray("naloxone")
	_check(story.state()["ray"] == "helped" and gs.naloxone == 0, "  giving him your naloxone: he's helped")
	_hour(gs, 4, 9)
	_check(gs.od_event.get("who", "") != "Ray", "  ...and he isn't the one in the alley on day 4")
	# Mia's visit, day 3 evening, at home.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 3, 19)
	var home := await _load("res://world/Apartment3D.tscn")
	_check(home.get_node_or_null("Mia") != null, "  day 3 evening: Mia's at your door")
	var cash0: int = gs.cash
	story.mia_choice("promise")
	_check(story.state()["mia"] == "close" and story.state()["mia_promise"] and gs.cash == cash0 + 20, "  promising to see Dana: $20 and she believes you")
	# The ring.
	gs.start_run()
	gs.clock_running = false
	gs.belongings["ring"] = "sold"
	_hour(gs, 3, 19)
	await _load("res://world/Apartment3D.tscn")
	_check(story.mia_opening().contains("ring"), "  she notices Mom's ring is gone")
	story.mia_choice("steal")
	_check(story.state()["mia"] == "blocked", "  stealing from her bag: she blocks you")
	var before: int = story.messages().size()
	_hour(gs, 5, 9)
	_check(story.messages().size() == before, "  ...and the texts stop")
	# Ray, left alone, is the one in the alley on day 4.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 4, 9)
	_check(gs.od_event.get("who", "") == "Ray" and gs.od_event.get("state", "") == "pending", "  nobody helped Ray: day 4, he's the one down in the alley")
	gs.od_event["state"] = "down"
	gs.resolve_overdose("pockets")
	_check(story.state()["ray"] == "dead", "  ...and if he dies, he's gone")
	var city := await _load("res://world/City3D.tscn")
	_check(city.find_child("Ray", true, false) == null, "  ...gone from the street too")
	# Dana: book, miss twice, lose the bed.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 2, 14)
	story.book_dana()
	_check(story.state()["dana"] == "booked" and story.appointment_text().contains("17"), "  Dana books you in: tomorrow, 17 to 20")
	_hour(gs, 3, 21)
	_check(story.state()["dana_missed"] == 1 and story.state()["dana"] == "booked", "  miss it: one strike, a new time")
	_hour(gs, 4, 21)
	_check(story.state()["dana"] == "lost", "  miss it twice: the bed goes to someone else")
	_check(not story.can_start_program(), "  ...and the program's full")
	# Keep it, and you're in.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 2, 14)
	story.book_dana()
	_hour(gs, 3, 17)
	_check(story.keep_appointment() and story.state()["dana"] == "in" and story.can_start_program(), "  turn up at 17: the bed's yours")
	# Endings.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 4, 9)
	_check(story.ending_line("overdose").contains("Mia"), "  overdose, Mia still around: she's the one who finds you")
	story.state()["mia"] = "blocked"
	_check(story.ending_line("overdose").contains("Nobody"), "  ...blocked: nobody finds you")
	# Alone: Mia gone, Ray dead, the bed lost.
	var ended := [""]
	var grab := func(s): ended[0] = s.get("cause", "")
	gs.run_ended.connect(grab)
	story.state()["ray"] = "dead"
	story.state()["dana"] = "lost"
	_hour(gs, 5, 10)
	gs.run_ended.disconnect(grab)
	_check(ended[0] == "alone", "  nobody left -- the 'alone' ending (%s)" % ended[0])
	var end_screen = load("res://ui/RunEndScreen.gd").new()
	end_screen._summary = {"cause": "alone"}
	_check(end_screen._cutscene_id() != "sent_away" and end_screen.heading_for("alone")[0] == "ALONE", "  the run-end screen knows 'alone'")
	end_screen.free()
	gs.start_run()
	gs.clock = 14 * 60
	var shelter := await _load("res://world/Shelter3D.tscn")
	var dana: Node = shelter.find_child("Outreach", true, false)
	_check(dana != null and dana.npc_name == "Dana", "  the outreach worker is Dana")
	gs.start_run()

## From the story review: the holes a player would fall through.
func _story_review_checks(gs: Node) -> void:
	await _section("Story: review fixes")
	var story := root.get_node("Story")
	# Dana's hours are hours St. Jude's is open.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 2, 18)
	story.book_dana()
	_hour(gs, 3, story.DANA_HOURS[0])
	_check(gs.is_open("shelter") and story.appointment_open(), "  the appointment is while St. Jude's is open")
	# Helping Ray on day 4 calls off his night in the alley.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 4, 9)
	story.help_ray("dana")
	_check(gs.od_event.get("who", "") != "Ray", "  helped on day 4 morning: he isn't down that night")
	# Saved (by someone else calling it in), then a new day: he stays saved.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 4, 9)
	gs.od_event["state"] = "down"
	gs.resolve_overdose("payphone")
	gs.od_event = {}
	_check(story.state()["ray"] == "saved", "  Ray saved stays saved after the night's cleared")
	# A late load doesn't plant a day-4 overdose on day 6.
	gs.start_run()
	gs.clock_running = false
	gs.od_event = {"day": 6, "minute": 21 * 60, "who": "Big Eddie", "state": "pending", "left": 90.0}
	_hour(gs, 6, 10)
	_check(gs.od_event.get("who", "") == "Big Eddie", "  loading on day 6 keeps that night's own overdose")
	# One Ray at a time.
	gs.start_run()
	gs.clock_running = false
	gs.od_event = {"day": 4, "minute": 20 * 60, "who": "Ray", "state": "down", "left": 90.0}
	gs.day = 4
	var city := await _load("res://world/City3D.tscn")
	var sitting: Node = city.find_child("Ray", true, false)
	_check(sitting == null or not sitting.visible, "  while Ray's down in the alley he isn't also sitting on the sidewalk")
	gs.od_event = {}
	# Mia in the room doesn't 'wait outside'.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 3, 20)
	await _load("res://world/Apartment3D.tscn")
	_hour(gs, 3, 23)
	_check(story.state()["mia"] == "close", "  Mia standing in your room isn't 'waiting outside the door'")
	# Promising Mia books Dana.
	story.mia_choice("promise")
	_check(story.state()["dana"] == "booked", "  promising Mia books you in with Dana")
	gs.start_run()

## #3 gameplay: a dishwashing shift, your own Silk Lane shop, and runs
## that remember the last one.
func _gameplay3_checks(gs: Node) -> void:
	await _section("Gameplay: shifts, a shop, and the last run")
	var jobs := root.get_node("Jobs")
	var Darknet = load("res://world/Darknet.gd")
	var meta := root.get_node("MetaProgress")
	# The dishwasher job.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 1, 16)
	var bar := await _load("res://world/DiveBar3D.tscn")
	await _frames(5)
	var sign: Node = bar.get_node_or_null("HelpWanted")
	_check(sign != null and load("res://ui/Prompts.gd").text_for(sign) == "Ask about the dishwasher job", "  a help-wanted sign by the kitchen in the Dive Bar")
	jobs.hire()
	_check(jobs.shift["hired"], "  hired")
	gs.craving = 90.0
	_hour(gs, 1, 17)
	var cash0: int = gs.cash
	_check(jobs.clock_in() and gs.hour() == jobs.SHIFT[1] and gs.cash == cash0 + jobs.SHIFT_PAY, "  clock in at 17: the shift passes and pays $%d (now %02d:00)" % [jobs.SHIFT_PAY, gs.hour()])
	_check(not jobs.clock_in(), "  one shift a day")
	_hour(gs, 2, 19)
	_check(jobs.shift["missed"] == 1, "  no-show the next day: a strike")
	_hour(gs, 3, 19)
	_check(jobs.shift["fired"], "  two no-shows: fired")
	gs.start_run()
	gs.clock_running = false
	jobs.reset()
	jobs.hire()
	gs.craving = 0.0
	_hour(gs, 1, 17)
	var cash1: int = gs.cash
	_check(not jobs.clock_in() and gs.cash == cash1 and jobs.shift["missed"] == 1, "  turning up dopesick: sent home, no pay, a strike")
	jobs.reset()
	# Your own shop.
	gs.start_run()
	gs.clock_running = false
	gs.cash = 200
	_hour(gs, 1, 14)
	_check(Darknet.vendor_order("ok"), "  ordering a wholesale lot")
	_check(gs.cash == 200 - Darknet.WHOLESALE_PRICE, "  ...$%d up front" % Darknet.WHOLESALE_PRICE)
	_hour(gs, 2, 9)
	_hour(gs, 2, 10)
	var v: Dictionary = gs.vendor
	_check(v.get("sold", 0) >= 2 and v.get("stock", 0) == Darknet.WHOLESALE_UNITS - v.get("sold", 0) and gs.cash > 200 - Darknet.WHOLESALE_PRICE, "  next morning it's in, and some sells (%d sold, %d left)" % [v.get("sold", 0), v.get("stock", 0)])
	_check(float(v.get("heat", 0.0)) > 0.0, "  every sale leaves a trace")
	gs.warrant = false
	Darknet.raid_check(1.0)
	_check(gs.warrant and gs.vendor.get("stock", 0) == 0, "  traced: a warrant, and the stock's gone")
	gs.warrant = false
	_check("vendor" in root.get_node("SaveGame").FIELDS, "  the shop is saved with the run")
	# The last run, remembered.
	gs.start_run()
	gs.clock_running = false
	root.get_node("Story").state()["ray"] = "dead"
	gs.belongings["guitar"] = "pawned"
	gs.end_run("overdose")
	_check(meta.last_run.get("cause", "") == "overdose" and meta.last_run.get("ray", "") == "dead" and meta.last_run.get("guitar", "") == "pawned", "  the run's end is remembered (%s)" % [meta.last_run])
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 1, 8)
	_check(root.get_node("Story").messages().any(func(m): return m["from"] == "Voicemail"), "  next run: a voicemail from Mia that remembers")
	var city := await _load("res://world/City3D.tscn")
	_check(city.find_child("RipRay", true, false) != null, "  'RIP RAY' still on the alley wall")
	_check(load("res://npc/PawnBroker3D.gd").greeting().contains("guitar"), "  the pawnbroker still has your guitar")
	meta.last_run = {}
	gs.start_run()

## #4 sound: music where it was silent, a drone and a muffle for the
## sickness, rain heard through the walls, wood underfoot at the pawnshop.
func _sound4_checks(gs: Node) -> void:
	await _section("Sound: music, the muffle, rain through the walls")
	var sfx := root.get_node("SFX")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 19 * 60
	gs.craving = 90.0
	gs.set_raining(false)
	await _load("res://world/Shelter3D.tscn")
	await _frames(5)
	_check(sfx._music_track == "shelter", "  St. Jude's has its own piano (%s)" % sfx._music_track)
	await _load("res://world/Jail3D.tscn")
	await _frames(5)
	_check(sfx._music_track == "jail", "  the jail has its own music (%s)" % sfx._music_track)
	await _load("res://world/City3D.tscn")
	await _frames(5)
	var well_cut: float = sfx.muffle_cutoff()
	gs.craving = 0.0
	gs.craving_changed.emit(gs.craving)
	await _frames(5)
	_check(sfx._music_track == "sick", "  deep in withdrawal the music gives way to a drone (%s)" % sfx._music_track)
	_check(sfx._muffles.size() == 2 and sfx._muffles.all(func(f): return f.cutoff_hz < 3000.0), "  the muffle is on the music and room-tone buses")
	_check(sfx.muffle_cutoff() < 3000.0 and well_cut > 15000.0, "  ...and everything goes muffled (%.0f Hz, well %.0f Hz)" % [sfx.muffle_cutoff(), well_cut])
	gs.craving = 90.0
	gs.craving_changed.emit(gs.craving)
	await _frames(5)
	_check(sfx._music_track != "sick", "  well again: the drone lets go")
	gs.set_raining(true)
	await _load("res://world/Apartment3D.tscn")
	await _frames(5)
	_check(sfx._rain_indoor.playing, "  raining out: you hear it through the walls at home")
	await _load("res://world/City3D.tscn")
	await _frames(5)
	_check(not sfx._rain_indoor.playing, "  ...but not as a second rain outside")
	gs.set_raining(false)
	_check(sfx.ROOM_SURFACE.get("Pawn3D", "") == "wood", "  wooden steps on the pawnshop floor")
