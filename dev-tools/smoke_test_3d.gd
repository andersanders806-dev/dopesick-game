extends SceneTree
## Headless gameplay smoke test for the 3D rooms. Drives the real scenes
## (no mocks): steal in the Shop, get spotted, check the police actually
## path toward the player, carry the chase through a door, buy from the
## pusher on the street, sell to a Dive Bar patron, then sleep in the
## Apartment.
##   godot --headless --path . -s res://dev-tools/smoke_test_3d.gd
## Exit code 0 = all checks passed.

const CharacterCast := preload("res://npc/CharacterCast.gd")
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
	# The checks jump the clock days at a time; the body would starve on the
	# way. Survival's own checks switch it back on.
	root.get_node("Survival").enabled = false
	# The checks start from a fresh profile, whatever the player's own save
	# and settings hold (bought upgrades, laptop mode...): nothing is saved
	# back in sandbox mode.
	gfx.laptop_mode = false
	var meta := root.get_node("MetaProgress")
	meta.know_how = 0
	meta.levels = {}
	meta.runs_completed = 0
	meta.best_day = 0
	meta.last_run = {}
	meta.achievements = {}
	meta.history = []
	meta.hints_seen = {"move": true, "craving": true, "body": true, "keys": true, "goal": true}
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
			# A sleeping cell's sounds are paused with it (world/BlockCells.gd).
			if not node.can_process():
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
	# Earlier checks have left the clock at night, when he's under the
	# overpass: make it his afternoon and let him come back to the corner.
	gs.clock = 17 * 60
	var corner_wait := 0
	while corner_wait < 1800 and not (pusher.state == pusher.State.POST and pusher.global_position.distance_to(Vector3(14.0, 0, -3.5)) < 3.0):
		await _frames(10)
		corner_wait += 10
	var city_player := _player()
	city_player.global_position = current_scene.get_node("SpawnFromShop").global_position
	await _frames(3)
	var reached := await _walk_until_nearest(pusher)
	var nearest = city_player._nearest_interactable()
	_check(reached, "can walk up to the pusher from the shop door (pusher %s state %d, nearest %s, player %s)" % [pusher.global_position, pusher.state, nearest.name if nearest else "-", city_player.global_position])
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
	for d in ["DoorToHome", "DoorToBar", "DoorToPharmacy", "DoorToSupermarket", "DoorToElectronics"]:
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
	# The corner shop is a room on Main Street: walk in through its doorway.
	var store := current_scene
	var shop_node := store.get_node("Cell_Main/WalkIn_Convenience")
	_player().global_position = shop_node.get_node("SpawnInside").global_position
	_player().reset_physics_interpolation()
	await _frames(30)
	gs.cash = 40
	gs.steal_item("cigs")
	var busts := [0]
	var count_bust := func(): busts[0] += 1
	gs.busted.connect(count_bust)
	var bp := _player()
	var clerk := shop_node.get_node("Shopkeeper") as Node3D
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
	bp.reset_physics_interpolation()
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
	# A dose rolls its overdose risk; take it at zero risk so this checks the relief.
	gs.take_drug("heroin", 1.0, 0.0)
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
	await _slot_checks(gs)
	await _survival_checks(gs)
	await _crafting_checks(gs)
	await _camp_checks(gs)
	await _fight_checks(gs)
	await _objective_checks(gs)
	await _juice_checks(gs)
	await _recap_checks(gs)
	await _showcase_checks(gs)
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
	await _menus5_checks(gs)
	await _anim6_checks(gs)
	await _atmosphere7_checks(gs)
	await _achievements8_checks(gs)
	await _smooth_quick_checks(gs)
	await _one_load_at_a_time_checks()
	await _block_layout_checks(gs)
	await _block_cells_checks(gs)
	await _walk_in_checks(gs)
	await _schedules_checks(gs)
	await _zombie_shell_checks(gs)
	await _zombie_anim_checks(gs)
	await _zombie_dead_checks(gs)
	await _zombie_weapons_checks(gs)
	await _zombie_fp_checks(gs)
	await _zombie_horde_checks(gs)
	await _zombie_gore_checks(gs)
	await _car_checks(gs)
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
	var open_shop := current_scene.get_node("Cell_Main/WalkIn_Convenience")
	var shut_shop := current_scene.get_node("Cell_Main/WalkIn_Liquor")
	_check((open_shop.get_node("Gate") as CollisionObject3D).collision_layer == 0 and (shut_shop.get_node("Gate") as CollisionObject3D).collision_layer == 1, "  ...but the 24/7 shop's doorway is open (and the liquor store's is shut)")

	gs.clock = 9 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var pusher := city.get_node("Pusher")
	_check(pusher.state == pusher.State.OFF_SHIFT and not pusher.model_root.visible, "  no pusher on the corner at 09:00")
	# (He steps out of hiding when nobody could see him do it.)
	root.get_node("Schedules").seen_override = 0
	gs.clock = 10 * 60 + 30
	await _frames(240)
	root.get_node("Schedules").seen_override = -1
	_check(pusher.state != pusher.State.OFF_SHIFT and pusher.model_root.visible, "  he's back on his spot by 10:30")

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

	# The beat cop: watching a hand-to-hand at the pusher's corner calls it in
	# (the corner is his post until 20:00; after that he works the overpass).
	gs.clock = 18 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var pusher := city.get_node("Pusher")
	p = _player()
	city.set("_patrol_timer", 99999.0)  # only the cops this test places
	city._spawn_patrol(pusher.global_position + Vector3(-5.0, 0, 2.3))
	var cop := city.get_tree().get_first_node_in_group("patrol") as Node3D
	cop.heading = 1.0
	await _frames(60)
	# The characters face +Z; the guard code was written for Kenney's, which
	# faced -Z, so the beat cop walked the block backwards.
	var cop_fwd: Vector3 = (cop.get_node("Body") as Node3D).global_transform.basis.z
	_check(cop_fwd.dot(Vector3.RIGHT) > 0.5, "  the beat cop faces the way he walks (forward %s)" % str(cop_fwd.snapped(Vector3.ONE * 0.01)))
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

func _slot_checks(gs: Node) -> void:
	await _section("Slot machine: the Lucky Devil at the Dive Bar")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 21 * 60
	var Slots = load("res://ui/SlotMachine.gd")
	var strips: Array = Slots.strips()
	_check(strips.size() == 3 and strips.all(func(s): return s.size() == 22), "  three reels of 22 stops")
	var rtp: float = Slots.rtp()
	_check(rtp > 0.86 and rtp < 0.94, "  it keeps about a dime on the dollar (pays back %.1f%%)" % (rtp * 100.0))
	_check(Slots.payout(Slots.SEVEN, Slots.SEVEN, Slots.SEVEN) == 150, "  three sevens pay 150x")
	_check(Slots.payout(Slots.CHERRY, Slots.CHERRY, Slots.LEMON) == 6, "  two cherries pay 6x")
	_check(Slots.payout(Slots.CHERRY, Slots.LEMON, Slots.LEMON) == 1, "  one cherry gives the bet back")
	_check(Slots.payout(Slots.LEMON, Slots.CHERRY, Slots.CHERRY) == 0, "  cherries only count from the first reel")
	_check(Slots.payout(Slots.BAR, Slots.BAR, Slots.BELL) == 0, "  two of a kind and a miss is nothing")
	var bar := await _load("res://world/DiveBar3D.tscn")
	_check(bar.find_child("SlotZone", true, false) != null, "  the slot machine can be played")
	_check(bar.get_node_or_null("SlotMachine") is StaticBody3D, "  and it's solid -- you walk round it")
	var hm := func(sym: int, reel: int) -> int: return strips[reel].find(sym)
	gs.cash = 20
	var game: Node = bar._start_slots(_player())
	await _frames(2)
	_check(_player().dialogue_active, "  sitting down at it holds the player")
	game.bet_index = 0
	game._howto = false
	var spun := []
	game.spun.connect(func(w): spun.append(w))
	# Three sevens.
	var t0: float = gs.clock
	_check(game.spin([hm.call(Slots.SEVEN, 0), hm.call(Slots.SEVEN, 1), hm.call(Slots.SEVEN, 2)]), "  a $1 pull goes in")
	_check(gs.cash == 19, "  the dollar's taken up front ($%d)" % gs.cash)
	_check(not game.spin(), "  you can't pull again while the reels turn")
	_check(game._reels[2]["stop_at"] > game._reels[1]["stop_at"] + 1.0, "  two matching reels make the third hang on")
	# Headless frames aren't capped, so wait on the wall clock.
	var t_start := Time.get_ticks_msec()
	while spun.is_empty() and Time.get_ticks_msec() - t_start < 8000:
		await process_frame
	_check(spun.size() == 1 and spun[0] == 150, "  the reels stop and pay out (%s after %.1fs)" % [str(spun), (Time.get_ticks_msec() - t_start) / 1000.0])
	var shown := [game._sym_at(0, game._reels[0]["pos"]), game._sym_at(1, game._reels[1]["pos"]), game._sym_at(2, game._reels[2]["pos"])]
	_check(shown == [Slots.SEVEN, Slots.SEVEN, Slots.SEVEN], "  the line shows what it paid for (%s)" % str(shown))
	_check(gs.cash == 169, "  $150 lands in your pocket ($%d)" % gs.cash)
	_check(root.get_node("MetaProgress").achievements.has("jackpot"), "  and the jackpot is an achievement")
	# A losing pull.
	spun.clear()
	game.spin([hm.call(Slots.LEMON, 0), hm.call(Slots.PLUM, 1), hm.call(Slots.BELL, 2)])
	t_start = Time.get_ticks_msec()
	while spun.is_empty() and Time.get_ticks_msec() - t_start < 8000:
		await process_frame
	_check(spun == [0] and gs.cash == 168, "  a losing pull just takes the dollar ($%d)" % gs.cash)
	_check(game._message != "", "  and the machine has something to say about it")
	# Broke.
	gs.cash = 0
	_check(not game.spin() and gs.cash == 0, "  no money, no pull")
	game._close()
	await _frames(3)
	_check(not _player().dialogue_active, "  you can walk away from it")
	_check(absf(gs.clock - (t0 + 2 * Slots.MINUTES_PER_SPIN)) < 0.01, "  and the pulls took time (%.1f min)" % (gs.clock - t0))
	_check(gs.is_processing(), "  the clock runs again once you're up")
	gs.start_run()

func _survival_checks(gs: Node) -> void:
	await _section("Survival: health, hunger, cold, rest, bleeding -- and death")
	_close_menus()
	var sv := root.get_node("Survival")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 12 * 60
	gs.raining = false
	_check(sv.health == sv.MAX and sv.hunger > 50.0 and not sv.bleeding and not sv.dead, "  a run starts healthy and fed")
	# Ten hours indoors at noon: hungrier, tireder, warm.
	var h0: float = sv.hunger
	var r0: float = sv.rest
	sv.tick(600.0, false)
	_check(is_equal_approx(sv.hunger, h0 - 40.0) and is_equal_approx(sv.rest, r0 - 50.0) and sv.warmth == sv.MAX,
		"  ten hours: hunger and rest run down, a room keeps you warm (%.0f, %.0f, %.0f)" % [sv.hunger, sv.rest, sv.warmth])
	# A night outside.
	gs.clock = 23 * 60
	sv.warmth = 80.0
	gs.belongings["coat"] = "pawned"
	sv.tick(120.0, true)
	var no_coat: float = 80.0 - sv.warmth
	sv.warmth = 80.0
	gs.belongings["coat"] = "home"
	sv.tick(120.0, true)
	var coat: float = 80.0 - sv.warmth
	_check(no_coat > 20.0 and coat < no_coat * 0.7, "  a night outside chills you, slower in your coat (-%.0f vs -%.0f in two hours)" % [no_coat, coat])
	# Sleep fills rest.
	sv.rest = 10.0
	gs.sleep()
	_check(sv.rest == sv.MAX, "  a night's sleep and you're rested")
	# A beating bleeds; bandages close it.
	gs.debt = 50
	gs.cash = 0
	var hp: float = sv.health
	gs.collect_debt()
	_check(sv.bleeding and sv.health < hp, "  the collector's beating hurts and opens you up (%.0f -> %.0f)" % [hp, sv.health])
	var hp2: float = sv.health
	gs.clock = 12 * 60
	sv.tick(60.0, false)
	_check(sv.health < hp2, "  bleeding costs health by the hour")
	_check(sv.warnings().has("BLEEDING"), "  ...and the HUD says so")
	# The vending machine on the block.
	gs.debt = 0
	var city := await _load("res://world/City3D.tscn")
	var vm := city.get_node_or_null("VendingMachine")
	_check(vm != null and vm.find_child("VendingZone", true, false) != null, "  a vending machine on the block")
	gs.cash = 12
	sv.hunger = 20.0
	_check(vm.buy(1) and gs.cash == 7 and sv.hunger == 70.0, "  a sandwich: $5, and fed ($%d, hunger %.0f)" % [gs.cash, sv.hunger])
	_check(vm.buy(3) and not sv.bleeding, "  bandages stop the bleeding")
	gs.cash = 1
	_check(not vm.buy(1) and gs.cash == 1, "  no money, no sandwich")
	var hud := get_first_node_in_group("hud")
	_check(hud.get_node_or_null("TopBar/SurvivalBg") != null, "  the HUD shows health, food, warmth and rest")
	# Starving to death ends the run.
	var ended := []
	gs.run_ended.connect(func(s): ended.append(s), CONNECT_ONE_SHOT)
	sv.hunger = 0.0
	sv.health = 10.0
	sv.tick(240.0, false)
	_check(sv.dead and ended.size() == 1 and ended[0]["cause"] == "health" and sv.last_cause == "starved",
		"  health at 0: you die, and the run says why (%s)" % sv.last_cause)
	var End = load("res://ui/RunEndScreen.gd")
	_check(End.new().heading_for("health")[0] == "YOU DIED", "  'YOU DIED'")
	await _frames(3)
	for c in root.get_children():
		if c is CanvasLayer and String(c.get_script().resource_path if c.get_script() else "").ends_with("RunEndScreen.gd"):
			c.free()
	# Survival days (autoload/Headlines.gd).
	var hl := root.get_node("Headlines")
	gs.start_run()
	gs.clock_running = false
	hl.forced = "cold_snap"
	hl.roll(gs.day)
	gs.clock = 13 * 60
	sv.warmth = 80.0
	sv.tick(60.0, true)
	_check(sv.warmth < 80.0 - 5.0, "  cold snap: the cold bites outside even at midday (%.0f)" % sv.warmth)
	gs.clock = 23 * 60
	sv.warmth = 80.0
	sv.tick(60.0, true)
	var snap_night: float = 80.0 - sv.warmth
	hl.forced = "quiet"
	hl.roll(gs.day)
	sv.warmth = 80.0
	sv.tick(60.0, true)
	_check(snap_night > (80.0 - sv.warmth) * 1.5, "  ...and harder at night than a normal night (-%.0f vs -%.0f)" % [snap_night, 80.0 - sv.warmth])
	hl.forced = "food_bank"
	hl.roll(gs.day)
	gs.clock = 13 * 60
	_check(gs.is_open("shelter") and gs.meal_service() >= 0, "  food bank day: the shelter kitchen serves at 1 pm")
	hl.forced = "sweep"
	hl.roll(gs.day)
	gs.clock = 23 * 60
	_check(not hl.can_sleep_rough(), "  police sweep: no sleeping rough tonight")
	hl.forced = "quiet"
	hl.roll(gs.day)
	_check(hl.can_sleep_rough(), "  ...any other night you can")
	# And the title has no Continue.
	var title = load("res://ui/TitleScreen.tscn").instantiate()
	root.add_child(title)
	await _frames(2)
	var labels: Array = title.find_children("*", "Button", true, false).map(func(b): return b.text)
	_check(not labels.has("Continue") and labels.has("New run"), "  every start is a fresh run: no Continue (%s)" % ", ".join(labels))
	title.queue_free()
	await _frames(2)
	sv.enabled = false
	gs.start_run()

func _crafting_checks(gs: Node) -> void:
	await _section("Scavenging and crafting")
	_close_menus()
	var sv := root.get_node("Survival")
	var cr := root.get_node("Crafting")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	var spots: Array = city.get_tree().get_nodes_in_group("scavenge")
	var trash := spots.filter(func(z): return not z.get_meta("car"))
	var cars := spots.filter(func(z): return z.get_meta("car"))
	_check(trash.size() >= 6 and cars.size() == 3, "  trash bags and parked cars to search (%d, %d)" % [trash.size(), cars.size()])
	_check(load("res://ui/Prompts.gd").text_for(trash[0]) == "Search the trash", "  'Search the trash'")
	var first: String = cr.search("TestBag")
	_check(cr.search("TestBag").begins_with("You've already"), "  each spot once a day")
	# Enough searches turn up every material.
	var got := {}
	for i in 200:
		var before: Array = gs.inventory.duplicate()
		cr.search("Bag%d" % i)
		for id in gs.inventory:
			if id in cr.MATERIALS:
				got[id] = true
	_check(got.size() == 3, "  searching turns up rags, scrap and tape (%s)" % ", ".join(got.keys()))
	_check(not gs.carrying_stolen(), "  scavenged stuff isn't stolen goods -- the cops don't care")
	# Crafting.
	gs.inventory.clear()
	gs.inventory.append_array(["rags", "rags", "rags", "rags", "rags", "tape", "tape", "scrap"])
	var bedroll := 1
	var shiv := 2
	_check(cr.make(bedroll) and gs.inventory.has("bedroll") and cr.count("rags") == 2 and cr.count("tape") == 1, "  a bedroll from 3 rags and tape")
	_check(cr.make(shiv) and gs.inventory.has("shiv") and cr.count("scrap") == 0, "  a shiv from scrap and tape")
	_check(not cr.make(0), "  no rag bandage when you're not bleeding")
	sv.hurt(5.0, true)
	_check(cr.make(0) and not sv.bleeding and cr.count("rags") == 0, "  ...and when you are, it stops it")
	_check(not cr.make(shiv), "  out of parts, nothing to make")
	# The bedroll keeps the cold off.
	gs.clock = 23 * 60
	gs.belongings["coat"] = "pawned"
	sv.warmth = 80.0
	sv.tick(60.0, true)
	var with_roll: float = 80.0 - sv.warmth
	gs.inventory.erase("bedroll")
	sv.warmth = 80.0
	sv.tick(60.0, true)
	_check(with_roll < 80.0 - sv.warmth, "  a bedroll keeps the cold off outside (-%.0f vs -%.0f)" % [with_roll, 80.0 - sv.warmth])
	gs.belongings["coat"] = "home"
	# C opens the menu.
	var menu: CanvasLayer = _player().open_craft_menu()
	await _frames(2)
	_check(is_instance_valid(menu) and menu.visible, "  C opens what you can make")
	menu.queue_free()
	_player().dialogue_active = false
	sv.enabled = false
	gs.start_run()

func _camp_checks(gs: Node) -> void:
	await _section("Your camp out back: fire barrel, lean-to, stash")
	_close_menus()
	var sv := root.get_node("Survival")
	var camp := root.get_node("Camp")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 23 * 60
	_check(camp.built.is_empty() and camp.stash.is_empty(), "  a new run starts with no camp")
	var yard := await _load("res://world/Backyard3D.tscn")
	_check(yard.get_node_or_null("CampZone") != null, "  a corner of the lot to make yours")
	_check(not camp.build(0), "  nothing to build it with, nothing built")
	gs.inventory.append_array(["scrap", "scrap", "scrap", "scrap", "scrap", "rags", "rags", "rags", "rags", "rags", "tape", "tape"])
	_check(camp.build(0) and camp.has("fire") and gs.inventory.count("scrap") == 3, "  a fire barrel from 2 scrap")
	await _frames(2)
	_check(yard.find_child("FireBarrel", true, false) != null, "  ...and there it is")
	_check(camp.light_fire() and camp.fire_lit() and gs.inventory.count("rags") == 4, "  a rag lights it")
	gs.belongings["coat"] = "pawned"
	sv.warmth = 30.0
	sv.tick(60.0, true)
	_check(sv.warmth > 30.0, "  at your fire on a night outside, you warm up (%.0f)" % sv.warmth)
	gs.belongings["coat"] = "home"
	_check(camp.build(1) and camp.has("leanto"), "  a lean-to over the mattress")
	_check(camp.build(2) and camp.has("stash"), "  a stash box")
	gs.inventory.clear()
	gs.inventory.append("watch")
	_check(camp.put("watch") and not gs.inventory.has("watch") and camp.stash.has("watch"), "  what's in the stash isn't on you")
	_check(not gs.carrying_stolen(), "  ...so the cops can't find it on you")
	_check(camp.take("watch") and gs.inventory.has("watch"), "  and you can take it back")
	# Sleeping under the lean-to keeps the cold off.
	gs.clock = 23 * 60
	sv.warmth = 80.0
	sv.on_sleep(540.0, true)
	var under: float = 80.0 - sv.warmth
	camp.built.erase("leanto")
	sv.warmth = 80.0
	sv.on_sleep(540.0, true)
	_check(under < (80.0 - sv.warmth) * 0.5, "  a night under the lean-to is far warmer (-%.0f vs -%.0f)" % [under, 80.0 - sv.warmth])
	var menu: CanvasLayer = yard.open_camp_menu(_player())
	await _frames(2)
	_check(is_instance_valid(menu), "  the camp has a menu")
	menu.queue_free()
	_player().dialogue_active = false
	sv.enabled = false
	gs.start_run()

func _fight_checks(gs: Node) -> void:
	await _section("Muggers and fighting back")
	_close_menus()
	var sv := root.get_node("Survival")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 23 * 60
	var Fight = load("res://ui/FightGame.gd")
	# Hand it over.
	gs.cash = 30
	var f: CanvasLayer = Fight.new()
	root.add_child(f)
	f.start(false)
	f.choose(1)
	_check(f.outcome == "paid" and gs.cash == 0 and sv.health == sv.MAX, "  hand it over: the cash goes, you don't get hurt")
	f._close()
	# Fight: a dodge at the last moment leaves him open, and that hit counts double.
	f = Fight.new()
	root.add_child(f)
	f.start(false)
	f.choose(0)
	_check(f.phase == "fight", "  fight: it's on")
	f.state = "windup"
	f.windup_len = 1.0
	f.t = 0.3
	f.dodge()
	_check(f.state == "windup", "  dodging too early does nothing")
	f.t = 0.85
	_check(f.in_dodge_window(), "  ...the last moment of the wind-up is the window")
	f.dodge()
	_check(f.state == "open", "  ...dodge in it and he's wide open")
	var hp: float = f.mugger_hp
	f.punch()
	_check(is_equal_approx(hp - f.mugger_hp, f.PUNCH * f.OPEN_MULT), "  an open hit counts double (%.0f)" % (hp - f.mugger_hp))
	# Getting caught by the swing costs health; enough of it and you're down.
	var h0: float = sv.health
	f.state = "windup"
	f.t = 0.0
	f.windup_len = 0.1
	f.step(0.2)
	_check(sv.health < h0 and not sv.bleeding, "  his swing lands: health, no bleeding (%.0f -> %.0f)" % [h0, sv.health])
	gs.cash = 12
	f.lost = f.GO_DOWN - 1.0
	f._take_hit()
	_check(f.outcome == "lost" and gs.cash == 0 and sv.bleeding, "  go down and he takes everything, and you're bleeding")
	f._close()
	# Put him down.
	sv.reset()
	f = Fight.new()
	root.add_child(f)
	f.start(true)
	f.choose(0)
	_check(f.mugger_hp > f.MUGGER_HP, "  a knife: harder to put down")
	f.mugger_hp = 3.0
	f.state = "open"
	f._cooldown = 0.0
	f.punch()
	_check(f.outcome == "won", "  put him down and he runs")
	f._close()
	# A shiv and the sickness.
	gs.inventory.append("shiv")
	f = Fight.new()
	root.add_child(f)
	f.start(false)
	_check(is_equal_approx(f.damage_mult(), f.SHIV_MULT), "  a shiv: %.1fx the damage" % f.damage_mult())
	var calm: float = f.run_chance()
	gs.craving = 0.0
	_check(f.run_chance() < calm and f.dodge_window() < f.DODGE_WINDOW, "  sick: slower legs and a smaller window")
	f._close()
	gs.craving = 45.0
	gs.inventory.erase("shiv")
	# On the street at night.
	var city := await _load("res://world/City3D.tscn")
	var m: Node3D = city.spawn_mugger(false)
	await _frames(3)
	_check(city.get_tree().get_nodes_in_group("mugger").size() == 1, "  a mugger comes for you on the block at night")
	var game: CanvasLayer = m.confront(_player())
	await _frames(2)
	_check(_player().dialogue_active and is_instance_valid(game), "  ...and when he reaches you, it's your call")
	game.choose(1)
	game._close()
	await _frames(3)
	_check(not _player().dialogue_active and not is_instance_valid(m), "  ...and then he's gone and you can walk on")
	sv.enabled = false
	city._maybe_mugger()
	_check(city.get_tree().get_first_node_in_group("mugger") == null, "  (no muggers with the survival layer off)")
	gs.start_run()

func _objective_checks(gs: Node) -> void:
	await _section("What now: the objective line and first-run hints")
	_close_menus()
	var sv := root.get_node("Survival")
	var Obj = load("res://ui/Objectives.gd")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 12 * 60
	await _load("res://world/Apartment3D.tscn")
	var hud := get_first_node_in_group("hud")
	var label: Label = hud.get_node_or_null("TopBar/Objective")
	_check(label != null and label.text.length() > 5, "  there's always a line saying what to do (\"%s\")" % (label.text if label else ""))
	_check(Obj.current().contains("rent"), "  a fresh run: make rent")
	sv.hunger = 10.0
	_check(Obj.current().begins_with("Eat"), "  hungry: eat, and where")
	sv.hurt(5.0, true)
	_check(Obj.current().begins_with("Stop the bleeding"), "  bleeding beats hungry")
	gs.wanted = true
	_check(Obj.current().begins_with("Lose the police"), "  the police beat everything")
	gs.wanted = false
	sv.reset()
	gs.craving = 0.0
	_check(Obj.current().contains("dope sick"), "  dope sick: where the pusher is")
	gs.craving = 45.0
	# First-run hints, once each, across runs.
	var meta := root.get_node("MetaProgress")
	meta.hints_seen = {}
	hud._hint_t = 0.0
	hud._tick_objective(0.01)
	_check(meta.hints_seen.size() == 1, "  the first run walks you through, one hint at a time")
	for i in 10:
		hud._hint_t = 0.0
		hud._tick_objective(0.01)
	_check(meta.hints_seen.size() == Obj.FIRST_STEPS.size(), "  ...all %d of them" % Obj.FIRST_STEPS.size())
	sv.enabled = false
	gs.start_run()

func _juice_checks(gs: Node) -> void:
	await _section("Game feel: everything answers back")
	_close_menus()
	var sv := root.get_node("Survival")
	sv.enabled = true
	gs.start_run()
	gs.clock_running = false
	gs.clock = 12 * 60
	await _load("res://world/City3D.tscn")
	var hud := get_first_node_in_group("hud")
	var b := Button.new()
	root.add_child(b)
	await _frames(1)
	_check(b.has_meta("ui_sounds"), "  every button gets a focus tick and a press sound")
	b.queue_free()
	gs.cash += 7
	gs.cash_changed.emit(gs.cash)
	await _frames(1)
	_check(hud.get_node("TopBar").get_children().any(func(n): return n is Label and n.text == "+$7"), "  money in: '+$7' floats off the cash")
	gs.inventory.append("rags")
	gs.inventory_changed.emit()
	await _frames(1)
	var icons: Node = hud.inventory_icons
	_check(icons.get_child_count() > 0 and (icons.get_child(icons.get_child_count() - 1) as Control).modulate.r > 1.0, "  something new in your pockets pops in")
	sv.hurt(20.0, false)
	await _frames(1)
	var flash: ColorRect = hud.get_node_or_null("HurtFlash")
	_check(flash != null and flash.color.a > 0.1 and _player()._kick > 0.0, "  a hit: red flash and the view jolts")
	var Fight = load("res://ui/FightGame.gd")
	var f: CanvasLayer = Fight.new()
	root.add_child(f)
	f.start(false)
	f.choose(0)
	f.state = "open"
	f.punch()
	_check(Engine.time_scale < 1.0 and f._shake > 0.0, "  a punch that lands: hit-stop and shake")
	var t0 := Time.get_ticks_msec()
	while Engine.time_scale < 1.0 and Time.get_ticks_msec() - t0 < 1000:
		await process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "  ...and time comes back")
	f._close()
	sv.enabled = false
	gs.start_run()

func _showcase_checks(gs: Node) -> void:
	await _section("Showcase: photo mode, title cards, a HUD that steps back, camera feel")
	_close_menus()
	var gfx := root.get_node("Graphics")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 12 * 60
	var city := await _load("res://world/City3D.tscn")
	var hud := get_first_node_in_group("hud")
	var bar: Control = hud.get_node("TopBar")
	await _frames(2)
	# Photo mode.
	var PM = load("res://ui/PhotoMode.gd")
	var game_cam := root.get_viewport().get_camera_3d()
	_check(PM.open_over(self), "  photo mode opens over the street")
	var pm: Node = root.get_node("PhotoMode")
	await _frames(2)
	_check(paused and pm.cam.current and not bar.visible, "  the world stops, a free camera takes over, the HUD goes")
	pm.set_filter(1)
	pm.set_dof(true)
	var attrs := pm.cam.attributes as CameraAttributesPractical
	_check(pm._look.visible and attrs.dof_blur_far_enabled and attrs.dof_blur_far_distance > 0.0, "  a look (Noir) and depth of field")
	pm.zoom(-100.0)
	_check(is_equal_approx(pm.cam.fov, 20.0), "  zoom stops at 20 degrees")
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	var path: String = PM.save_image(img)
	_check(path.ends_with(".png") and FileAccess.file_exists(path), "  a photo saves as a PNG ('%s')" % path)
	DirAccess.remove_absolute(path)
	pm.close()
	await _frames(2)
	_check(not paused and game_cam.current and bar.visible and root.get_node_or_null("PhotoMode") == null, "  leaving puts the game, its camera and the HUD back")
	var cover := CanvasLayer.new()
	root.add_child(cover)
	_check(not PM.open_over(self), "  ...but not over a screen of its own (the run's end, a menu)")
	cover.free()
	# The day card.
	var loader := root.get_node("SceneLoader")
	gs.day = 2
	gs.day_changed.emit(2)
	await _frames(20)
	var day_card: Label = loader.find_child("DayCard", true, false)
	_check(day_card.text == "DAY 2" and day_card.modulate.a > 0.05, "  a new day gets its card ('%s')" % day_card.text)
	# The HUD steps back while you walk and nothing needs you.
	gfx.immersive_hud = true
	hud._awake = 0.0
	hud._still = 0.0
	_check(not hud.hud_needed(), "  walking, nothing wrong: the HUD can fade")
	gs.cash_changed.emit(gs.cash)
	_check(hud.hud_needed(), "  money changing hands brings it back")
	hud._awake = 0.0
	gs.wanted = true
	_check(hud.hud_needed(), "  so does being wanted")
	gs.wanted = false
	gfx.immersive_hud = false
	_check(hud.hud_needed(), "  and the setting turns the fading off")
	# Camera feel.
	var p := _player()
	var base: float = p._tp_fov
	gfx.camera_motion = true
	p._sprinting = true
	p.velocity = Vector3(5, 0, 0)
	for i in 30:
		p._update_camera_feel(0.05)
	_check(p.camera.fov > base + 4.0, "  breaking into a run pushes the field of view (%.1f -> %.1f)" % [base, p.camera.fov])
	gfx.camera_motion = false
	for i in 60:
		p._update_camera_feel(0.05)
	_check(absf(p.camera.fov - base) < 0.5, "  camera motion off: no push")
	gfx.camera_motion = true
	p._first_person = true
	var bobbed := 0.0
	for i in 30:
		bobbed = maxf(bobbed, p._update_camera_feel(0.05).length())
	_check(bobbed > 0.01, "  first person: the head bobs as you walk (%.3f m)" % bobbed)
	p._first_person = false
	p._sprinting = false
	p.velocity = Vector3.ZERO
	# The prompt eases in.
	p.global_position = city.get_node("DoorToBar").global_position
	await _frames(2)
	var prompt: Label = hud.find_child("InteractPrompt", true, false)
	var early := prompt.modulate.a
	await _frames(30)
	_check(prompt.visible and prompt.has_theme_stylebox_override("normal") and prompt.modulate.a > 0.99 and early < 0.99,
		"  a prompt fades in on its pill (%.2f -> %.2f)" % [early, prompt.modulate.a])
	gs.start_run()

func _recap_checks(gs: Node) -> void:
	await _section("The ending: your run told back, your record, the credits")
	_close_menus()
	var End = load("res://ui/RunEndScreen.gd")
	gs.start_run()
	gs.stat("walked", 2400.0)
	gs.stat("meals")
	gs.stat("fights_won")
	_check(gs.run_stats["walked"] == 2400.0 and gs.run_stats["meals"] == 1.0, "  the run counts what you did (walked, meals, fights...)")
	var meta := root.get_node("MetaProgress")
	meta.best_day = 3
	gs.day = 5
	var got := []
	gs.run_ended.connect(func(s): got.append(s), CONNECT_ONE_SHOT)
	gs.end_run("health")
	_check(got.size() == 1 and got[0]["prev_best"] == 3 and got[0]["stats"]["walked"] == 2400.0, "  the summary carries the stats and the old best")
	_check(End.is_new_best(got[0]) and End.record_line(got[0]).contains("NEW BEST"), "  beat your best and it says so ('%s')" % End.record_line(got[0]))
	_check(not End.is_new_best({"days": 2, "prev_best": 5}) and End.record_line({"days": 2, "prev_best": 5, "run": 4}).contains("best so far: day 5"), "  ...and otherwise shows the record to beat")
	await _frames(2)
	for c in root.get_children():
		if c is CanvasLayer and c.get_script() == End:
			c.free()
	var screen: CanvasLayer = End.new()
	root.add_child(screen)
	screen._summary = got[0]
	screen._build()
	await _frames(2)
	var walked := screen.find_children("*", "Label", true, false).filter(func(l): return l.has_meta("final") and String(l.get_meta("final")).ends_with("km"))
	_check(walked.size() == 1 and walked[0].get_meta("final") == "2.4 km", "  'Walked 2.4 km', counting up")
	var credits: Control = screen.roll_credits()
	await _frames(2)
	_check(is_instance_valid(credits) and credits.find_children("*", "Label", false, false).size() > 0, "  the credits roll")
	screen.queue_free()
	await _frames(2)
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
	_check(pause.find_children("*", "Button", true, false).any(func(b): return b.text.begins_with("Fullscreen")), "  ...and has a fullscreen button")
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
	# The box truck and the garbage truck stood a head over everything else
	# and filled the screen going under the camera; traffic is cars now.
	var heights := []
	for kind in life.CARS:
		var m: Node3D = load("res://assets/cars/%s.glb" % kind).instantiate()
		heights.append([kind, life.CarPaint.bounds(m).size.y])
		m.free()
	_check(life.CARS.size() >= 8 and heights.all(func(h): return h[1] <= 2.95), "  traffic is cars, nothing taller than the taxi's roof sign (%s)" % ", ".join(heights.map(func(h): return "%s %.1f m" % h)))
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
	# Morning: the pusher isn't on his corner yet (he'd be standing in the
	# alley mouth this hides in) and the street is busy.
	gs.clock = 9 * 60
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
	# Random by design (seeded off the clock): over a few lines, at least
	# one swims.
	var lines := ["a bottle of good whiskey", "a carton of cigarettes", "the electronics store", "a pair of wireless headphones"]
	_check(lines.any(func(t): return book._misread(t) != t), "  ...and your notes swim (\"%s\")" % book._misread(lines[0]))
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
	gfx.set_preset(gfx.Preset.MEDIUM)
	_check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA, "  Medium: SMAA, not FXAA")
	# Low: FXAA, the cheap pass -- without one the street crawled as you walked.
	gfx.set_preset(gfx.Preset.LOW)
	_check(vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "  Low: FXAA")
	# Fullscreen with one key, F11, from anywhere.
	var was_full: bool = gfx.fullscreen
	var f11 := InputEventKey.new()
	f11.physical_keycode = KEY_F11
	f11.pressed = true
	gfx._unhandled_input(f11)
	_check(gfx.fullscreen != was_full, "  F11 switches fullscreen")
	gfx._unhandled_input(f11)
	_check(gfx.fullscreen == was_full, "  ...and back")
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
	# (Every one that's drawn: those in cells asleep this far off are hidden
	# -- world/BlockCells.gd -- and Graphics gives hidden lamps no shadow.)
	var drawn := lamps.filter(func(l): return l.is_visible_in_tree())
	_check(drawn.size() > 2 and drawn.all(func(l): return l.shadow_enabled), "  PS5: every lamp, as built (%d drawn)" % drawn.size())
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
	var kenney := city.find_children("*", "Node3D", true, false).filter(func(n): return String(n.scene_file_path).contains("kenney/city"))
	_check(kenney.is_empty(), "  no Kenney toy buildings left on the street (%s)" % [kenney.map(func(n): return n.name)])
	var fronts: Node = city.get_node_or_null("Facades")
	var names := ["Police", "Home", "Pharmacy", "Bar", "Shop", "Liquor", "Supermarket", "Electronics", "Karts", "Pawn", "Music", "Shelter"]
	_check(fronts != null and names.all(func(n): return fronts.get_node_or_null("Front" + n) != null), "  every building has a real front")
	# Gameplay stays: doors and the station door where they were.
	var doors := ["DoorToHome", "DoorToPharmacy", "DoorToBar", "DoorToSupermarket",
		"DoorToElectronics", "DoorToKarts", "DoorToShelter", "StationDoor",
		"WalkIn_Convenience", "WalkIn_Liquor", "WalkIn_Pawn", "WalkIn_Music"]
	_check(doors.all(func(d): return city.find_child(d, true, false) != null), "  every door is still there (the four shops' are doorways now)")
	if fronts:
		# Fronts sit behind the signs: nothing of a facade pokes in front of
		# z = -4.5 at sign height or below (fire escapes stand out above it)
		# along the shops (the block's other streets have their own lines).
		var poking := []
		for mi in fronts.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = mi.global_transform * mi.get_aabb()
			if b.end.x < -29.5 or b.position.x > 29.5:
				continue
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
	var lamps := city.find_children("Streetlight*", "StaticBody3D", true, false)
	_check(lamps.size() > 0 and lamps.all(func(l): return l.get_node_or_null("Model") != null and l.get_node_or_null("Light") != null and l.get_node_or_null("Pole") == null),
		"  street lamps are real lamps, same light (%d)" % lamps.size())
	var cars := city.find_children("Car*", "StaticBody3D", true, false) + city.find_children("PoliceCruiser", "StaticBody3D", true, false)
	_check(cars.size() > 0 and cars.all(func(c): return c.get_node_or_null("Body") == null and c.get_node_or_null("Model") != null and c.find_children("*", "CollisionShape3D", false, false).size() > 0),
		"  parked cars are cars, not boxes, and still solid (%d)" % cars.size())
	var road := city.get_node("Cell_Main/Road") as MeshInstance3D
	var walk := city.get_node("Cell_Main/Sidewalk") as MeshInstance3D
	var road_tex := String((road.mesh.material as StandardMaterial3D).albedo_texture.resource_path) if road.mesh.material else ""
	var walk_tex := String((walk.mesh.material as StandardMaterial3D).albedo_texture.resource_path) if walk.mesh.material else ""
	_check(road_tex.contains("road_worn") and walk_tex.contains("sidewalk_slabs") and city.get_node_or_null("Cell_Main/Curb") != null,
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
	var when: Label = card.get_node("When")
	_check(card.text == "THE DIVE BAR" and when.text.ends_with(gs.clock_text()) and card.modulate.a > 0.5,
		"  an arrival card says where and when ('%s' / '%s')" % [card.text, when.text])
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
	# Laptop graphics keep headroom: down above 13 ms, up below 10.
	_check(gfx.next_scale(s, 58.0, 16.2) < s, "  GPU over budget (16.2 ms at 58 FPS): resolution comes down")
	_check(gfx.next_scale(s, 60.0, 14.0) < s, "  14 ms on a laptop GPU: comes down too, before it warms up")
	_check(is_equal_approx(gfx.next_scale(s, 60.0, 11.5), s), "  11.5 ms: stays put")
	_check(gfx.next_scale(s, 60.0, 9.0) > s, "  9 ms: room to sharpen, goes up")
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
	var due: float = float(gs.parcel["arrive_at"]) - gs.now_minutes()
	var due_hour: int = int(fposmod(float(gs.parcel["arrive_at"]), 1440.0) / 60.0)
	_check(gs.cash == 100 - price and due > 0.0 and due <= 24 * 60 and due_hour >= 8 and due_hour < 20,
		"  paid, and it lands within 24 hours, in the postman's hours (%.1f h, at %02d:00)" % [due / 60.0, due_hour])
	_check(not Darknet.order("heroin", "ok"), "  one order at a time")
	_check(home.get_node_or_null("Package") == null, "  nothing comes inside the flat any more")
	var city := await _load("res://world/City3D.tscn")
	var mailbox: Node = city.get_node_or_null("Mailbox")
	_check(mailbox != null and load("res://ui/Prompts.gd").text_for(mailbox.get_node("MailboxZone")) == "Check the mailbox", "  a mailbox by your door on the block")
	_check(not mailbox.has_mail(), "  ...empty until it comes")
	# The postman, when it's due and you're out on the block.
	_set_minutes(gs, float(gs.parcel["arrive_at"]) - 10.0)
	city._check_post()
	_check(city.get_tree().get_first_node_in_group("postman") != null, "  the postman comes down the block when it's due")
	_set_minutes(gs, float(gs.parcel["arrive_at"]) + 5.0)
	city._check_post()
	await _frames(2)
	_check(mailbox.has_mail(), "  ...and then it's in the mailbox, flag up")
	gs.craving = 10.0
	var outcome: String = Darknet.open_package(null, false)
	mailbox.refresh()
	_check(gs.parcel.is_empty() and outcome in ["relief", "precipitated", "overdose", "saved"] and gs.craving > 10.0 or outcome != "relief",
		"  opening it, you take what came (%s, craving %.0f)" % [outcome, gs.craving])
	_check(not mailbox.has_mail(), "  ...and the mailbox is empty again")
	home = await _load("res://world/Apartment3D.tscn")
	# The vendor who took the money and ran.
	gs.cash = 100
	Darknet.order("oxy", "scam")
	_set_minutes(gs, float(gs.parcel["arrive_at"]) + 61.0)
	gs._emit_clock()
	home = await _load("res://world/Apartment3D.tscn")
	_check(home.get_node_or_null("Package") == null and gs.parcel.get("fate", "") == "scam", "  an exit scam: no package")
	_check(Darknet.laptop_text().contains("gone") and gs.parcel.is_empty(), "  the laptop tells you the vendor's gone, and the order's done with")
	# Opened at the post office.
	gs.warrant = false
	Darknet.order("meth", "seized")
	_set_minutes(gs, float(gs.parcel["arrive_at"]) - 61.0)
	var land: float = float(gs.parcel["arrive_at"]) + 1.0
	gs.day = int(land / 1440.0) + 1
	gs.clock = fposmod(land, 1440.0)
	gs._emit_clock()
	_check(gs.warrant and gs.parcel.is_empty(), "  a package seized in the post: there's a warrant out")
	gs.warrant = false

## Puts the clock at an absolute game minute (day and time).
func _set_minutes(gs: Node, m: float) -> void:
	gs.day = int(m / 1440.0) + 1
	gs.clock = fposmod(m, 1440.0)
	gs._last_minute = int(gs.clock)

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
	# Each day's sales roll a small chance of a raid (heat * RAID_SCALE, ~4%
	# here) that empties the shop; switch it off so this checks the sale.
	Darknet.raid_chance = 0.0
	_hour(gs, 2, 10)
	Darknet.raid_chance = -1.0
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

## #5 menus and HUD: controls in settings, what's next on the HUD, unread
## messages, and a title screen that remembers and credits.
func _menus5_checks(gs: Node) -> void:
	await _section("Menus & HUD")
	var gfx := root.get_node("Graphics")
	var story := root.get_node("Story")
	# Controls.
	var menu = load("res://ui/SettingsMenu.gd").new()
	root.add_child(menu)
	menu.open()
	await _frames(2)
	var sliders: Array = menu.find_children("*", "HSlider", true, false)
	var checks: Array = menu.find_children("*", "CheckButton", true, false)
	_check(menu.find_child("LookSensitivity", true, false) is HSlider and menu.find_child("InvertLook", true, false) is CheckButton, "  settings: look sensitivity and invert look")
	_check(menu.find_children("*", "Label", true, false).any(func(l): return l.text.contains("Interact")), "  settings: the controls are listed")
	menu.queue_free()
	gfx.set_look_sensitivity(1.5)
	gfx.set_invert_look(true)
	_check(is_equal_approx(gfx.look_sensitivity, 1.5) and gfx.invert_look, "  sensitivity and invert stick")
	gfx.set_look_sensitivity(1.0)
	gfx.set_invert_look(false)
	# Next up and unread.
	gs.start_run()
	gs.clock_running = false
	_hour(gs, 2, 14)
	story.book_dana()
	gs.day = 3
	_check(gs.status_line().size() > 0 and gs.status_line()[0].contains("Dana"), "  the HUD's next-up line: Dana today (%s)" % [gs.status_line()])
	var home := await _load("res://world/Apartment3D.tscn")
	await _frames(2)
	var before: int = story.unread()
	story.send("Mia", "test")
	await _frames(2)
	var badge: Label = get_first_node_in_group("hud").find_child("UnreadLabel", true, false)
	_check(story.unread() == before + 1 and badge != null and badge.visible, "  a new message shows a badge on the HUD")
	var nb = load("res://ui/Notebook.gd").new()
	root.add_child(nb)
	nb.open(4)
	await _frames(2)
	_check(story.unread() == 0 and not badge.visible, "  reading Messages clears it")
	nb._close()
	await _frames(2)
	# Title screen.
	root.get_node("MetaProgress").last_run = {"cause": "overdose", "day": 4}
	var title := await _load("res://ui/TitleScreen.tscn")
	await _frames(5)
	_check(title.find_children("*", "Button", true, false).any(func(b): return b.text == "Credits"), "  the title screen has Credits")
	_check(title.find_children("*", "Label", true, false).any(func(l): return l.text.contains("Last time")), "  ...and remembers how the last run ended")
	root.get_node("MetaProgress").last_run = {}
	gs.start_run()

## #6 animation: feet that match the ground, a crowd that isn't in step,
## heads that turn to you, and a player who moves like they're high.
func _anim6_checks(gs: Node) -> void:
	await _section("Animation")
	var Anim = load("res://npc/CharacterAnimator.gd")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	await _frames(10)
	var peds: Array = get_nodes_in_group("pedestrians")
	var walker: Node = peds[0]
	var ap: AnimationPlayer = walker.anim._player
	_check(absf(ap.speed_scale - walker.speed / walker.anim.natural_speed("walk")) < 0.05, "  a passerby's steps match their pace (%.2f for %.2f m/s)" % [ap.speed_scale, walker.speed])
	# Your own feet: walking and sprinting both inside what the clips can
	# plant, rather than skating along at a jog.
	var me: Node = _player()
	var walk_rate: float = me.BASE_SPEED / me.anim.natural_speed("walk")
	var run_rate: float = me.BASE_SPEED * me.SPRINT_MULT / me.anim.natural_speed("sprint")
	_check(walk_rate <= Anim.STRIDE_LIMITS.y + 0.01 and run_rate <= Anim.STRIDE_LIMITS.y + 0.01, "  your feet keep up when you walk (%.2fx) and sprint (%.2fx)" % [walk_rate, run_rate])
	var police: float = load("res://npc/Police3D.gd").SPEED
	var mugger: float = load("res://npc/Mugger3D.gd").MUGGER_SPEED
	_check(me.BASE_SPEED * me.SPRINT_MULT > maxf(police, mugger), "  ...and a sprint still outruns the police and the mugger")
	var idle_a = Anim.new(load(load("res://npc/CharacterCast.gd").model_for("player")).instantiate())
	var idle_b = Anim.new(load(load("res://npc/CharacterCast.gd").model_for("player")).instantiate())
	_check(not is_equal_approx(idle_a._player.current_animation_position, idle_b._player.current_animation_position) or not is_equal_approx(idle_a._idle_rate, idle_b._idle_rate), "  two people standing about aren't breathing in step")
	# Walking in place: the Rocketbox clips carry the hips ~1.2 m forward
	# per loop and snap them back, which jerked everyone back a step.
	for clip in ["walk", "sprint", "walk_sick", "idle_sick"]:
		var a: Animation = idle_a._player.get_animation(idle_a._resolved.get(clip, ""))
		var worst := 0.0
		for t in a.get_track_count():
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D and a.track_get_key_count(t) > 1:
				var d: Vector3 = a.track_get_key_value(t, a.track_get_key_count(t) - 1) - a.track_get_key_value(t, 0)
				worst = maxf(worst, Vector2(d.x, d.z).length())
		_check(worst < 0.5, "  %s loops in place: no snap back (%.2f)" % [clip, worst])
	# Heads turn.
	var ray: Node = city.find_child("Ray", true, false)
	var look: Node = ray.find_children("*", "LookAtModifier3D", true, false).front() if ray else null
	_check(look != null, "  Ray's head can turn to you")
	_player().global_position = ray.global_position + Vector3(1.5, 0, 0.8)
	await _frames(30)
	_check(look.influence > 0.3, "  ...and does when you're close (%.2f)" % look.influence)
	_player().global_position = ray.global_position + Vector3(12, 0, 0)
	await _frames(60)
	_check(look.influence < 0.1, "  ...and lets you go when you walk off (%.2f)" % look.influence)
	# High.
	var p := _player()
	_check(not p.is_high(), "  not high to begin with")
	gs.craving = 20.0
	gs.take_drug("heroin")
	_check(p.is_high(), "  after a dose: high, and moving like it")
	gs.start_run()

## #7 weather and atmosphere (world/Atmosphere.gd): morning fog, puddles,
## and the block at night -- sirens far off, a couple fighting on a corner.
func _atmosphere7_checks(gs: Node) -> void:
	await _section("Atmosphere: fog, puddles, the block at night")
	gs.start_run()
	gs.clock_running = false
	gs.set_raining(false)
	gs.clock = 12 * 60
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var atmo: Node = city.get_node_or_null("Atmosphere")
	_check(atmo != null, "  the street has its atmosphere")
	var env: Environment = city.get_node("WorldEnvironment").environment
	_dry_emit(gs, city)
	await _frames(2)
	var noon_fog := env.fog_density
	gs.clock = 6 * 60 + 30
	_dry_emit(gs, city)
	await _frames(2)
	_check(env.fog_density > noon_fog + 0.01, "  early morning: fog (%.3f vs %.3f at noon)" % [env.fog_density, noon_fog])
	gs.clock = 12 * 60
	_dry_emit(gs, city)
	await _frames(2)
	_check(absf(env.fog_density - noon_fog) < 0.002, "  ...burned off by noon")
	# Puddles. (Jumping the clock rolls the weather: pin it dry.)
	gs.set_raining(false)
	atmo.advance_wet(atmo.DRY_MINUTES * 2.0)
	_check(atmo.puddles_shown() == 0, "  dry: no puddles (%d, wet %.2f, raining %s)" % [atmo.puddles_shown(), atmo._wet, gs.raining])
	gs.set_raining(true)
	atmo.advance_wet(60.0)
	_check(atmo.puddles_shown() >= 6, "  an hour of rain: puddles (%d)" % atmo.puddles_shown())
	gs.set_raining(false)
	atmo.advance_wet(240.0)
	_check(atmo.puddles_shown() == 0, "  four dry hours later: gone")
	# Night.
	gs.clock = 14 * 60
	_dry_emit(gs, city)
	await _frames(2)
	_check(not atmo.night() and city.find_child("Argument", true, false) == null, "  afternoon: no fight on the corner")
	gs.clock = 23 * 60
	_dry_emit(gs, city)
	await _frames(5)
	var fight: Node = city.find_child("Argument", true, false)
	_check(atmo.night() and fight != null and fight.find_children("*", "Skeleton3D", true, false).size() == 2, "  23:00: two people fighting on the corner")
	await _frames(10)
	_check(fight.find_children("*", "Label3D", true, false).any(func(l): return l.visible and l.text != ""), "  ...and you can read what they're shouting")
	_check(atmo.distant_siren() != null, "  a siren somewhere a few streets over")
	gs.clock = 14 * 60
	_dry_emit(gs, city)
	await _frames(5)
	_check(city.find_child("Argument", true, false) == null or city.find_child("Argument", true, false).is_queued_for_deletion(), "  by day they're gone")

## Jumping the clock rolls the weather; a check about fog or the night
## mustn't depend on it. Emit, and if it started raining, stop it and let
## the street recompute.
func _dry_emit(gs: Node, city: Node) -> void:
	gs._emit_clock()
	if gs.raining:
		gs.set_raining(false)
		city._apply_daylight()
		var atmo: Node = city.get_node_or_null("Atmosphere")
		if atmo:
			atmo._apply_fog()

## #8 achievements and stats: a record of every run, achievements across
## runs, and a Record page.
func _achievements8_checks(gs: Node) -> void:
	await _section("Achievements & record")
	var meta := root.get_node("MetaProgress")
	meta.achievements = {}
	meta.history = []
	gs.start_run()
	gs.clock_running = false
	_check(meta.ACHIEVEMENTS.size() >= 12, "  a dozen achievements (%d)" % meta.ACHIEVEMENTS.size())
	_hour(gs, 2, 9)
	_check(meta.achievements.has("first_morning"), "  day 2: First Morning")
	# Saving a life.
	gs.naloxone = 1
	gs.od_event = {"day": gs.day, "minute": 0, "who": "Big Eddie", "state": "down", "left": 90.0}
	gs.resolve_overdose("naloxone")
	_check(meta.achievements.has("saved_a_life"), "  naloxone in the alley: Saved a Life")
	_check(meta.unlocked_this_run.has("saved_a_life"), "  ...noted for this run's end screen")
	var count: int = meta.achievements.size()
	meta.unlock("saved_a_life")
	_check(meta.achievements.size() == count, "  an achievement unlocks once")
	# The run ends: history and the ending's own achievements.
	gs.end_run("recovered")
	_check(meta.history.size() == 1 and meta.history[0]["cause"] == "recovered" and int(meta.history[0]["day"]) == 2, "  the run goes in the record (%s)" % [meta.history])
	_check(meta.achievements.has("got_out") and meta.achievements.has("moms_ring"), "  getting out, ring still at home: Got Out, Mom's Ring")
	gs.start_run()
	_check(meta.unlocked_this_run.is_empty(), "  a new run starts a fresh list")
	# The title screen's Record.
	var title := await _load("res://ui/TitleScreen.tscn")
	await _frames(5)
	var rec: Button = title.find_children("*", "Button", true, false).filter(func(b): return b.text == "Record").front()
	_check(rec != null, "  the title screen has a Record")
	rec.pressed.emit()
	await _frames(3)
	var texts: Array = title.find_children("*", "Label", true, false).map(func(l): return l.text)
	_check(texts.any(func(t): return t.contains("Saved a Life")) and texts.any(func(t): return t.contains("Got out on day 2")), "  ...listing runs and achievements")
	meta.achievements = {}
	meta.history = []
	gs.start_run()

## Smooth: warm the shaders on the title screen, a hitch meter on F4, and a
## steady-30 laptop mode.
func _smooth_quick_checks(gs: Node) -> void:
	await _section("Smooth: people preloaded, hitch meter, laptop mode")
	var gfx := root.get_node("Graphics")
	# The street's people load in the background from the first room, like
	# the street itself: they were most of the first visit's freeze.
	var loader := root.get_node("SceneLoader")
	var Cast = load("res://npc/CharacterCast.gd")
	_check(Cast.all_models().size() >= 20, "  every character model, listed (%d)" % Cast.all_models().size())
	gs.start_run()
	await _load("res://world/Apartment3D.tscn")
	loader._warmed = false
	var want: Array = Cast.all_models()
	for i in 3000:
		await _frames(1)
		if want.all(func(p): return loader.cached(p)):
			break
	_check(want.all(func(p): return loader.cached(p)), "  ...and loaded in the background from the first room (%d of %d)" % [want.filter(func(p): return loader.cached(p)).size(), want.size()])
	# Responsive: the camera stays close, you're up to speed fast, and the
	# screen isn't three frames behind.
	var P = load("res://player/Player3D.gd")
	_check(P.ACCEL >= 40.0 and P.DECEL >= 45.0, "  up to speed in a tenth of a second (accel %.0f)" % P.ACCEL)
	_check(P.CAM_FOLLOW >= 14.0, "  the camera keeps up (follow %.0f)" % P.CAM_FOLLOW)
	_check(int(ProjectSettings.get_setting("rendering/rendering_device/vsync/swapchain_image_count", 3)) == 2, "  two frames in the swapchain, not three")
	_check(gfx.VSYNC == DisplayServer.VSYNC_ENABLED, "  plain vsync: one frame per refresh, one physics step per frame")
	# Every passerby look drawn once while the street loads (under the
	# street, behind the fade), so the first of each walking on doesn't
	# hitch (42 ms each, measured).
	gs.start_run()
	var city := await _load("res://world/City3D.tscn")
	_check(city.get("looks_warmed") != null and int(city.looks_warmed) == load("res://npc/CharacterCast.gd").PASSERSBY.size(), "  every passerby look is warmed on arrival (%s)" % [city.get("looks_warmed")])
	await _frames(10)
	_check(city.find_child("LookWarmup", true, false) == null, "  ...and the warm-up is gone after")
	# Hitch meter.
	gfx.set_show_fps(true)
	for i in 30:
		await process_frame
	var graph: Node = gfx.find_child("FrameGraph", true, false)
	_check(graph != null and graph.visible and gfx.frame_times.size() >= 20, "  F4 shows a frame-time graph (%d frames)" % gfx.frame_times.size())
	gfx.set_show_fps(false)
	_check(not graph.visible, "  ...and hides it")
	# Laptop mode.
	gfx.set_laptop_mode(true)
	# A 30 cap on a 59.82 Hz panel came out uneven (every frame 'slow' in
	# perf.log) and walking looked choppy: laptop mode keeps the full frame
	# rate and saves the GPU with resolution instead.
	_check(Engine.max_fps == 0 and gfx.laptop_mode, "  laptop mode: never a frame-rate cap")
	_check(gfx.next_scale(0.95, 60.0, 5.0) <= gfx.LAPTOP_MAX_SCALE, "  ...it holds the resolution down instead (<= %.0f%%)" % (gfx.LAPTOP_MAX_SCALE * 100.0))
	gfx.set_laptop_mode(false)
	# First person: the camera is drawn every frame from the player's
	# interpolated position and the latest mouse look, not stepped on the
	# physics tick (Godot's jitter/stutter guide, 'first-person cameras').
	gs.start_run()
	await _load("res://world/City3D.tscn")
	var pl := _player()
	gfx.set_first_person(true)
	await _frames(2)
	var mount := pl.get_node("CameraMount") as Node3D
	_check(mount.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "  first person: the camera isn't physics-interpolated")
	pl.set_look(1.0, 0.2)
	pl._process(0.016)
	_check(is_equal_approx(mount.rotation.y, 1.0) and is_equal_approx(mount.rotation.x, 0.2), "  ...and turns with the mouse the same frame, not on the next physics tick")
	_check(mount.global_position.distance_to(pl.get_global_transform_interpolated().origin + Vector3(0, pl.EYE_HEIGHT, 0)) < 0.01, "  ...from where the body is drawn")
	gfx.set_first_person(false)
	await _frames(2)
	_check(mount.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_OFF, "  third person: interpolated as before")
	# Mailbox vsync doesn't cap anything: the title screen ran at 515 FPS on
	# the UHD 620, heating it into throttling. Off, it's held at the screen's
	# refresh (60 where there's no screen to ask).
	_check(Engine.max_fps == 0, "  ...off again: vsync holds it to the screen's own refresh, exactly (%d)" % Engine.max_fps)
	var menu = load("res://ui/SettingsMenu.gd").new()
	root.add_child(menu)
	menu.open()
	await _frames(2)
	_check(menu.find_child("LaptopMode", true, false) is CheckButton, "  laptop mode is in Settings")
	menu.queue_free()
	await _laptop_street_checks(gs)

## Low on the street, measured on the UHD 620 (dev-tools/gpu_probe.gd): the
## lamps and sign glows 3.5 ms, the sun's shadow 2, FXAA 1.3 -- and the GPU
## slows as it warms, 19 -> 24 ms for the same view inside a minute.
func _laptop_street_checks(gs: Node) -> void:
	await _section("Smooth: Low on the street leaves the laptop GPU headroom")
	var gfx := root.get_node("Graphics")
	var loader := root.get_node("SceneLoader")
	var saved: int = gfx.preset
	gs.start_run()
	gs.clock_running = false
	gs.clock = 14 * 60
	var city := await _load("res://world/City3D.tscn")
	gfx.set_preset(gfx.Preset.LOW)
	await _frames(20)
	var sun := city.get_node("Moon") as DirectionalLight3D
	_check(not sun.shadow_enabled, "  no sun shadow on Low, even by day")
	var lamps: Array = city.find_children("*", "Light3D", true, false).filter(func(l): return not l is DirectionalLight3D)
	_check(not lamps.is_empty() and lamps.all(func(l): return l.distance_fade_enabled and l.distance_fade_begin <= 15.0),
		"  lamps and sign glows fade out past ~14 m from the camera (%d lights)" % lamps.size())
	_check(root.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, "  FXAA on Low")
	# At night the 6 lamps and 12 sign glows were 6 ms: light cost goes with
	# the screen they cover, so on Low they reach less far.
	var glow := city.get_node("Cell_Main/BarSignGlow") as OmniLight3D
	var lamp := city.get_node("Cell_Main/Streetlight1/Light") as OmniLight3D
	_check(glow.omni_range <= 0.45 * glow.get_meta("built_range") and lamp.omni_range <= 0.75 * lamp.get_meta("built_range"),
		"  sign glows and lamps reach less far on Low (%.1f, %.1f m)" % [glow.omni_range, lamp.omni_range])
	# A laptop GPU slows as it warms (13 -> 20 ms in a few minutes): with plain
	# vsync any frame over 16.7 ms shows twice, so the lean profile keeps
	# real headroom and steps down at 13 ms, not 15.5.
	var was_int: bool = gfx._integrated
	gfx._integrated = true
	_check(gfx.lean() and gfx.next_scale(0.8, 60.0, 14.0) < 0.8 and is_equal_approx(gfx.next_scale(0.8, 60.0, 11.0), 0.8),
		"  laptop graphics: resolution comes down from 13 ms, holds at 11")
	gfx._integrated = was_int
	gfx.set_preset(gfx.Preset.MEDIUM)
	await _frames(5)
	_check(lamps.all(func(l): return not l.distance_fade_enabled or l.get_meta("built_fade", false)), "  ...and Medium gets the far lamps back")
	_check(is_equal_approx(lamp.omni_range, lamp.get_meta("built_range")), "  ...at their full reach")
	# Background loads finish on the main thread in bursts (38-83 ms in
	# perf.log): they wait while you're walking.
	var p := _player()
	loader._queue.clear()
	p.velocity = Vector3(4.0, 0, 0)
	await _frames(2)
	_check(not loader.may_start(), "  no background load starts while you walk")
	p.velocity = Vector3.ZERO
	await _frames(2)
	_check(not loader.may_start(), "  ...nor the moment you stop (turning round, a bump)")
	var still_t := Time.get_ticks_msec()
	while not loader.may_start() and Time.get_ticks_msec() - still_t < 3000:
		await _frames(1)
	_check(loader.may_start(), "  ...they go on once you've stood still a moment")
	# A load that finished while you walk is taken off the loader once you stop.
	loader._scenes.erase("res://world/Pawn3D.tscn")
	loader.prefetch("res://world/Pawn3D.tscn")
	p.velocity = Vector3(4.0, 0, 0)
	for i in 600:
		await _frames(1)
		p.velocity = Vector3(4.0, 0, 0)
		if ResourceLoader.load_threaded_get_status("res://world/Pawn3D.tscn") == ResourceLoader.THREAD_LOAD_LOADED:
			break
	await _frames(3)
	_check(not loader.cached("res://world/Pawn3D.tscn"), "  a finished load waits while you walk")
	p.velocity = Vector3.ZERO
	for i in 120:
		await _frames(1)
		if loader.cached("res://world/Pawn3D.tscn"):
			break
	_check(loader.cached("res://world/Pawn3D.tscn"), "  ...and is picked up when you stop")
	gfx.set_preset(saved)
	gs.start_run()

# --- The block: four streets round an interior (open world, task 1) ---------

## Main Street's doors, spawns and fixed people as they stood before the
## block was built round them: everything here must not have moved.
const MAIN_STREET_POSITIONS := {
	"DoorToBackyard": Vector3(-21.0, 0.0, -4.05), "DoorToBar": Vector3(-3.5, 0.0, -4.05),
	"DoorToElectronics": Vector3(24.5, 0.0, -4.05), "DoorToHome": Vector3(-17.5, 0.0, -4.05),
	"DoorToKarts": Vector3(-14.0, 0.0, -4.05),
	"DoorToPharmacy": Vector3(-10.5, 0.0, -4.05), "DoorToShelter": Vector3(7.0, 0.0, -4.05),
	"DoorToSupermarket": Vector3(17.5, 0.0, -4.05),
	# The corner shop, liquor store, pawnshop and Tape Deck have no door
	# node since task 3: their doorways are at the same x, and their shops'
	# origins (WalkIn_*) are just inside it.
	"WalkIn_Convenience": Vector3(3.5, 0.0, -4.8), "WalkIn_Liquor": Vector3(10.5, 0.0, -4.8),
	"WalkIn_Pawn": Vector3(0.0, 0.0, -4.8), "WalkIn_Music": Vector3(-7.0, 0.0, -4.8),
	"StationDoor": Vector3(-24.5, 0.0, -4.05),
	"SpawnDefault": Vector3(-17.5, 0.0, -3.0), "SpawnFromBackyard": Vector3(-21.0, 0.0, -3.0),
	"SpawnFromBar": Vector3(-3.5, 0.0, -3.0), "SpawnFromElectronics": Vector3(24.5, 0.0, -3.0),
	"SpawnFromHome": Vector3(-17.5, 0.0, -3.0), "SpawnFromJail": Vector3(-24.5, 0.0, -3.0),
	"SpawnFromKarts": Vector3(-14.0, 0.0, -3.0), "SpawnFromLiquor": Vector3(10.5, 0.0, -3.0),
	"SpawnFromMusic": Vector3(-7.0, 0.0, -3.0), "SpawnFromPawn": Vector3(0.0, 0.0, -3.0),
	"SpawnFromPharmacy": Vector3(-10.5, 0.0, -3.0), "SpawnFromShelter": Vector3(7.0, 0.0, -3.0),
	"SpawnFromShop": Vector3(3.5, 0.0, -3.0), "SpawnFromSupermarket": Vector3(17.5, 0.0, -3.0),
	"Alley14": Vector3(14.0, -0.04, -7.0), "Alley21": Vector3(21.0, -0.04, -7.0),
	"RayCrate": Vector3(-12.1, 0.0, -3.95), "Lookout": Vector3(-8.7, 0.0, -3.2),
	"VendingMachine": Vector3(-19.25, 0.0, -3.95), "Mailbox": Vector3(-16.1, 0.0, -3.7),
}
## The same, for things that move once the street's running (the rats run
## the wall line; Ray and the cars should never move): checked as built.
const MAIN_STREET_BUILT := {
	"Ray": Vector3(-12.1, 0.0, -3.95), "Rat1": Vector3(-2.0, 0.0, -4.38), "Rat2": Vector3(17.0, 0.0, -4.38),
	"PoliceCruiser": Vector3(-24.0, 0.0, 2.6), "CarA": Vector3(-12.0, 0.0, 2.6), "CarB": Vector3(5.5, 0.0, 2.6),
	"CarC": Vector3(20.0, 0.0, 2.8), "Hydrant": Vector3(-8.8, 0.0, -2.2), "Dumpster": Vector3(21.0, 0.6, -3.9),
	"Manhole1": Vector3(-9.0, 0.005, 1.6), "Manhole2": Vector3(12.0, 0.005, 0.4),
	"Streetlight1": Vector3(-27.0, 0.0, -1.8), "Streetlight2": Vector3(-21.0, 0.0, -1.8), "Streetlight3": Vector3(-14.0, 0.0, -1.8),
	"Streetlight4": Vector3(-7.0, 0.0, -1.8), "Streetlight5": Vector3(0.0, 0.0, -1.8), "Streetlight6": Vector3(7.0, 0.0, -1.8),
}
## Down every street, at eye level: [axis, the line's other coordinate,
## from, to]. Main's three sidewalk lanes and its road, then Back Street's,
## the avenues' (inner sidewalk, outer sidewalk, road).
## Both driving lanes of every road too (Main: the traffic lane and the
## parking lane; the others both directions).
const BLOCK_SIGHT_LINES := [
	["x", -3.0, -70.0, 70.0], ["x", -2.6, -70.0, 70.0], ["x", -2.2, -70.0, 70.0],
	["x", 0.0, -70.0, 70.0], ["x", 0.35, -70.0, 70.0], ["x", 1.5, -70.0, 70.0], ["x", 2.6, -70.0, 70.0],
	["x", -95.0, -70.0, 70.0], ["x", -85.6, -70.0, 70.0],
	["x", -92.5, -70.0, 70.0], ["x", -91.0, -70.0, 70.0], ["x", -89.5, -70.0, 70.0],
	["z", -66.6, -90.0, 0.0], ["z", -76.2, -90.0, 0.0], ["z", -69.5, -90.0, 0.0], ["z", -71.0, -90.0, 0.0], ["z", -72.5, -90.0, 0.0],
	["z", 66.6, -90.0, 0.0], ["z", 76.2, -90.0, 0.0], ["z", 69.5, -90.0, 0.0], ["z", 71.0, -90.0, 0.0], ["z", 72.5, -90.0, 0.0],
]
const BLOCK_PLACES := ["Place_BusStop", "Place_ParkBench", "Place_Court", "Place_UnderpassCamp",
	"Place_AlleyDumpsters", "Place_Stoop1", "Place_Stoop2", "Place_Stoop3", "Place_PoliceStation",
	"Place_PusherCorner", "Place_PusherNight", "Place_RayCrate"]
const BLOCK_CELLS := ["Cell_Main", "Cell_West", "Cell_East", "Cell_Back", "Cell_Inner"]
## The longest clear straight line you may see down a street at eye level.
const MAX_SIGHTLINE := 55.0
## Loading the street behind the door's fade (the spec's budget).
const CITY_LOAD_BUDGET_MS := 2500

## A fresh game: the street and its facade kits load in the background
## from boot (SceneLoader), and the first time onto the block -- "Continue"
## from the title, or the first door -- is only what's left behind the fade.
## In smoke_block.gd this is the process's first City3D; late in the full
## suite it holds all the more (everything's long in).
func _block_cold_load_checks(gs: Node) -> void:
	await _section("The block: the first time onto the street in a fresh game")
	var loader := root.get_node("SceneLoader")
	# (The walk-in shops' rooms are part of what loads in the title screen's time.)
	var warm: Array = ["res://world/City3D.tscn"] + load("res://world/Facades.gd").WARM + load("res://world/Facades.gd").walk_in_scenes()
	# ...and the cast's bodies, which SceneLoader queues after them: "Continue"
	# is a few seconds after boot, long enough for those too.
	warm += load("res://npc/CharacterCast.gd").all_models()
	var t_boot := Time.get_ticks_msec()
	while not warm.all(func(p): return loader.cached(p)) and Time.get_ticks_msec() - t_boot < 30000:
		await process_frame
	var warm_up := Time.get_ticks_msec() - t_boot
	_check(warm.all(func(p): return loader.cached(p)), "  the street and its kits load in the background from boot (%d ms of title screen)" % warm_up)
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	var t0 := Time.get_ticks_msec()
	change_scene_to_file("res://world/City3D.tscn")
	await process_frame
	await process_frame
	var first := Time.get_ticks_msec() - t0
	_check(first <= CITY_LOAD_BUDGET_MS, "  ...so the first time onto it takes %d ms (budget %d; _ready %d ms, of which the people %d ms)" % [first, CITY_LOAD_BUDGET_MS, current_scene.get("ready_ms"), current_scene.get("people_ms")])
	await _frames(10)
	# Continue / New Game, then walk at once: no frame stalls while the
	# background prefetch finishes and the traffic spawns (a car model loaded
	# on the spawn that first picked it, the taxi's, was half a second).
	var StreetLife := load("res://world/StreetLife.gd")
	var picks_cached := true
	for i in 300:
		if not ResourceLoader.has_cached(StreetLife.car_path(StreetLife._pick_car())):
			picks_cached = false
	_check(picks_cached, "  traffic only picks cars whose model is loaded already")
	var walker := _player()
	var worst := 0.0
	var frames := 0
	var last_usec := Time.get_ticks_usec()
	var walk_t0 := last_usec
	Input.action_press("sprint")
	while Time.get_ticks_usec() - walk_t0 < 20e6:
		var right := int((Time.get_ticks_usec() - walk_t0) / 5e6) % 2 == 0
		Input.action_release("move_left" if right else "move_right")
		Input.action_press("move_right" if right else "move_left")
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last_usec) / 1000.0)
		last_usec = now
		frames += 1
	Input.action_release("sprint")
	Input.action_release("move_left")
	Input.action_release("move_right")
	_check(walker != null and worst < 100.0, "  walking off at once for 20 s: no frame over 100 ms (%d frames, worst %.0f ms)" % [frames, worst])

func _block_layout_checks(gs: Node) -> void:
	await _block_cold_load_checks(gs)
	await _section("The block: four streets, an alley loop, a park and an underpass")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	var t0 := Time.get_ticks_msec()
	var city := await _load("res://world/City3D.tscn")
	print("  (City3D load %d ms with %d frames of settling; _ready %d ms, navmesh bake %d ms)" % [Time.get_ticks_msec() - t0, 10, city.get("ready_ms"), city.get("nav_bake_ms")])
	await _frames(5)
	# Cells: the five roots the block's areas are built under.
	var cells: Array = BLOCK_CELLS.map(func(n): return city.get_node_or_null(n))
	_check(cells.all(func(c): return c is Node3D and c.get_parent() == city and c.get_meta("bounds", null) is AABB),
		"  five cells, each a Node3D with its bounds (%s)" % [BLOCK_CELLS.filter(func(n): return not (city.get_node_or_null(n) is Node3D and city.get_node(n).has_meta("bounds")))])
	var outline := AABB()
	for c in cells:
		if c is Node3D and c.get_meta("bounds", null) is AABB:
			outline = c.get_meta("bounds") if outline.size == Vector3.ZERO else outline.merge(c.get_meta("bounds"))
	_check(outline.position.x <= -72.0 and outline.end.x >= 72.0 and outline.position.z <= -92.0 and outline.end.z >= 6.0,
		"  the block covers x -72..72, z -92..6 (%s)" % [outline])
	# Main Street hasn't moved.
	var moved := []
	for n in MAIN_STREET_POSITIONS:
		var node := city.find_child(n, true, false) as Node3D
		if node == null or node.global_position.distance_to(MAIN_STREET_POSITIONS[n]) > 0.001:
			moved.append("%s %s" % [n, node.global_position if node else "missing"])
	var pusher := city.find_child("Pusher", true, false)
	if pusher == null or pusher._post_position.distance_to(Vector3(14.0, 0, -3.5)) > 0.001 \
			or pusher.stash_position.distance_to(Vector3(21.0, 0, -3.15)) > 0.001 or pusher.hide_position.distance_to(Vector3(14.0, 0, -8.0)) > 0.001:
		moved.append("Pusher")
	var built: Node = load("res://world/City3D.tscn").instantiate()
	for n in MAIN_STREET_BUILT:
		var node := built.find_child(n, true, false) as Node3D
		var at := Vector3.INF
		if node:
			at = node.position
			var up := node.get_parent() as Node3D
			while up != built and up != null:
				at = up.transform * at
				up = up.get_parent() as Node3D
		if at.distance_to(MAIN_STREET_BUILT[n]) > 0.001:
			moved.append("%s %s (as built)" % [n, at])
	built.free()
	var C = load("res://world/City3D.gd")
	if C.HIDE_SPOTS[0]["pos"] != Vector3(14.0, 0, -4.05) or C.HIDE_SPOTS[1]["pos"] != Vector3(22.6, 0, -3.95):
		moved.append("hide spots")
	if C.MAILBOX_POS != Vector3(-16.1, 0, -3.7) or C.VENDING_POS != Vector3(-19.25, 0, -3.95) \
			or C.PATROL_START != Vector3(-24.5, 0, -1.3) or C.COLLECTOR_ENTRY != Vector3(27.5, 0, 1.0):
		moved.append("City3D constants")
	_check(moved.is_empty(), "  Main Street's doors, spawns and regulars are where they were (%s)" % [moved])
	# The places people will keep (Task 4's schedules) are on the map.
	var places: Array = get_nodes_in_group("places").filter(func(m): return city.is_ancestor_of(m) and m is Marker3D)
	var names: Array = places.map(func(m): return String(m.name))
	var missing: Array = BLOCK_PLACES.filter(func(n): return not names.has(n))
	_check(missing.is_empty() and names.all(func(n): return n.begins_with("Place_")), "  %d named places on the block (missing %s)" % [places.size(), missing])
	_check(get_nodes_in_group("landmark").filter(func(n): return city.is_ancestor_of(n)).size() >= 2, "  a landmark at each end (%d)" % get_nodes_in_group("landmark").size())
	# Everywhere is reachable from everywhere on foot.
	var map: RID = city.get_world_3d().navigation_map
	var broken := []
	for i in places.size():
		for j in range(i + 1, places.size()):
			var a: Vector3 = places[i].global_position
			var b: Vector3 = places[j].global_position
			var path := NavigationServer3D.map_get_path(map, a, b, true)
			if path.is_empty() or path[path.size() - 1].distance_to(b) > 0.5:
				broken.append("%s->%s (ends %s)" % [places[i].name, places[j].name, path[path.size() - 1] if path.size() > 0 else "nowhere"])
	_check(places.size() >= BLOCK_PLACES.size() and broken.is_empty(), "  a walkable path between every pair of places (%d pairs; broken %s)" % [places.size() * (places.size() - 1) / 2, broken.slice(0, 6)])
	# No street runs dead straight and clear for more than MAX_SIGHTLINE.
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var long := []
	for m in places:
		for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var from: Vector3 = m.global_position + Vector3(0, 1.5, 0)
			if not _ray_hits_static(space, from, from + dir * MAX_SIGHTLINE):
				long.append("%s %s" % [m.name, dir])
	_check(long.is_empty(), "  no clear sightline over %d m from any place (%s)" % [int(MAX_SIGHTLINE), long])
	# ...nor down any street: every 10 m along each sidewalk lane and road,
	# at eye level, both ways.
	var open := []
	for line in BLOCK_SIGHT_LINES:
		var along: Vector3 = Vector3.RIGHT if line[0] == "x" else Vector3.BACK
		var t: float = line[2]
		while t <= line[3] + 0.01:
			var from: Vector3 = (Vector3(t, 1.5, line[1]) if line[0] == "x" else Vector3(line[1], 1.5, t))
			# A point inside a newsstand or a truck sees nothing.
			var probe := PhysicsPointQueryParameters3D.new()
			probe.position = from
			probe.collision_mask = 1
			if space.intersect_point(probe, 1).size() > 0:
				t += 10.0
				continue
			for dir in [along, -along]:
				if not _ray_hits_static(space, from, from + dir * MAX_SIGHTLINE):
					open.append("%s %s" % [from.snapped(Vector3.ONE * 0.1), dir])
			t += 10.0
	_check(open.is_empty(), "  no clear run over %d m down any street, sidewalk or road (%d open: %s)" % [int(MAX_SIGHTLINE), open.size(), open.slice(0, 6)])
	await _block_structure_checks(gs, city)
	# Baked with the scene: a runtime bake of the whole block was 0.9-1.8 s.
	var nav := city.get_node("NavRegion") as NavigationRegion3D
	_check(int(city.get("nav_bake_ms")) == 0 and nav.navigation_mesh.get_polygon_count() > 0,
		"  the navmesh comes baked, nothing to bake behind the door (%d polygons)" % nav.navigation_mesh.get_polygon_count())
	# Warm (the loader has it cached, as after any first visit): the time
	# behind the door's fade.
	var loader := root.get_node("SceneLoader")
	loader._scene("res://world/City3D.tscn")
	await _load("res://world/Apartment3D.tscn")
	t0 = Time.get_ticks_msec()
	change_scene_to_file("res://world/City3D.tscn")
	await process_frame
	await process_frame
	var warm := Time.get_ticks_msec() - t0
	_check(warm <= CITY_LOAD_BUDGET_MS, "  City3D loads in %d ms once cached (budget %d)" % [warm, CITY_LOAD_BUDGET_MS])
	await _frames(10)
	gs.start_run()

## Cells hold only what's inside them; the night's lights go off by day;
## the overpass clears the camera; and there are no dead ends.
func _block_structure_checks(gs: Node, city: Node) -> void:
	# Task 2 sleeps a cell by its bounds: nothing of it may stand outside.
	var strays := []
	for cn in BLOCK_CELLS:
		var cell := city.get_node(cn) as Node3D
		var bounds: AABB = (cell.get_meta("bounds") as AABB).grow(1.0)
		for n in cell.find_children("*", "Node3D", true, false):
			var inside := bounds.has_point(n.global_position)
			if inside and n is VisualInstance3D and not (n is Light3D):
				var b: AABB = n.global_transform * n.get_aabb()
				inside = b.size == Vector3.ZERO or bounds.encloses(b)
			if not inside:
				strays.append("%s/%s" % [cn, cell.get_path_to(n)])
	_check(strays.is_empty(), "  everything in a cell lies inside its bounds (%d strays: %s)" % [strays.size(), strays.slice(0, 5)])
	# The overpass: nothing hangs below the camera's highest zoom plus half
	# a metre (its pillars aside).
	var player := _player()
	var cam_top: float = player._cam_offset.y * player.CAM_ZOOM * player.CAM_USER_ZOOM.y
	var low := []
	for mi in city.get_node("Overpass").find_children("*", "VisualInstance3D", true, false):
		if String(mi.name).begins_with("Pillar") or String(mi.get_parent().name).begins_with("Pillar"):
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.position.y < cam_top + 0.5:
			low.append("%s %.2f" % [mi.name, b.position.y])
	_check(low.is_empty(), "  the overpass clears the camera at its highest zoom (%.2f m + 0.5): %s" % [cam_top, low.slice(0, 4)])
	# By day the block's after-dark lights are off; at night they're on.
	gs.clock = 14 * 60
	# A dry afternoon: in the rain the lamps come half on (City3D).
	gs.raining = false
	gs.advance_clock(1)
	# (A random hour's rain would leave the lamps half on.)
	gs.set_raining(false)
	await _frames(3)
	var night := get_nodes_in_group("night_lights").filter(func(l): return city.is_ancestor_of(l))
	var lit_by_day := night.filter(func(l): return l.is_visible_in_tree() and l.light_energy > 0.01).map(func(l): return l.name)
	# Every light in the block's cells is one of the switched kinds (or a
	# fire, lit all day).
	var unswitched := []
	for l in city.find_children("*", "Light3D", true, false):
		var top: Node = l
		while top.get_parent() != city:
			top = top.get_parent()
		if not (String(top.name).begins_with("Cell_") or top.name == "Overpass"):
			continue
		if not (l.is_in_group("night_lights") or l.is_in_group("always_lit") or String(l.name).ends_with("SignGlow") or String(l.get_parent().name).begins_with("Streetlight")):
			unswitched.append(l.name)
	_check(night.size() > 10 and lit_by_day.is_empty() and unswitched.is_empty(),
		"  at 14:00 the block's %d after-dark lights are off (lit: %s; never switched: %s)" % [night.size(), lit_by_day.slice(0, 4), unswitched.slice(0, 4)])
	gs.clock = 22 * 60
	gs.advance_clock(1)
	await _frames(3)
	# (Those in cells asleep this far from you stay off: world/BlockCells.gd.)
	var cells_node: Node = city.get_node("BlockCells")
	var awake_night := night.filter(func(l): return cells_node.cell_of(l) == null or cells_node.is_awake(cells_node.cell_of(l)))
	_check(awake_night.size() > 0 and awake_night.all(func(l): return l.is_visible_in_tree() and l.light_energy > 0.01)
		and night.all(func(l): return l in awake_night or not l.is_visible_in_tree()), "  ...and on at 22:00 (the %d in cells awake; the rest asleep and dark)" % awake_night.size())
	gs.clock = 17 * 60
	# No dead ends. Each joint below is a short walk (under 1.4x the straight
	# line, plus 3 m): both of the pusher's alleys run through to the service
	# lane, the back alley to Back Street, every street joins the next at
	# both ends, the park and the lot each have two ways in, the underpass
	# three. (The basketball court has one door on purpose: it's somewhere
	# you go, not through.)
	var map: RID = city.get_world_3d().navigation_map
	var joints := [
		["alley 14", Vector3(13.6, 0, -5.0), Vector3(13.6, 0, -17.4)],
		["alley 21", Vector3(21.4, 0, -5.0), Vector3(21.4, 0, -17.4)],
		["the back alley", Vector3(-7.5, 0, -20.0), Vector3(-7.5, 0, -86.5)],
		["Main to West Ave", Vector3(-60.0, 0, -3.0), Vector3(-66.6, 0, -20.0)],
		["West Ave to Back St", Vector3(-66.6, 0, -70.0), Vector3(-55.0, 0, -86.5)],
		["Back St to East Ave", Vector3(55.0, 0, -86.5), Vector3(66.6, 0, -70.0)],
		["East Ave to Main", Vector3(66.6, 0, -20.0), Vector3(60.0, 0, -3.0)],
		["park, West Ave gate", Vector3(-67.0, 0, -24.0), Vector3(-60.0, 0, -24.0)],
		["park, Back St gate", Vector3(-36.5, 0, -86.6), Vector3(-36.5, 0, -80.0)],
		["lot, from the lane", Vector3(30.0, 0, -17.5), Vector3(40.0, 0, -17.5)],
		["lot, Back St gate", Vector3(46.0, 0, -86.6), Vector3(46.0, 0, -80.0)],
		["underpass, from Main", Vector3(61.0, 0, -3.0), Vector3(61.0, 0, -20.0)],
		["underpass, East Ave gap", Vector3(66.6, 0, -42.0), Vector3(62.0, 0, -42.0)],
		["underpass, Back St", Vector3(61.0, 0, -86.6), Vector3(61.0, 0, -78.0)],
	]
	var stuck := []
	for j in joints:
		var path := NavigationServer3D.map_get_path(map, j[1], j[2], true)
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		var straight: float = (j[1] as Vector3).distance_to(j[2])
		if path.is_empty() or path[path.size() - 1].distance_to(j[2]) > 0.6 or length > straight * 1.4 + 3.0:
			stuck.append("%s (%.0f m for %.0f)" % [j[0], length, straight])
	_check(stuck.is_empty(), "  no dead ends: every street, alley and gate goes through (%s)" % [stuck])

## A layer-1 static body somewhere along the ray: people and the player
## (bodies that move) don't count as blocking the view.
func _ray_hits_static(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var exclude: Array[RID] = []
	for i in 16:
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		if hit["collider"] is StaticBody3D:
			return true
		exclude.append(hit["rid"])
	return false

# --- The block: cells sleep and wake, walls dither out (open world, task 2) ---

## What stays drawn when a cell sleeps: the buildings Facades.gd raises for
## it (masses, fronts, roof units), its ground, cars and bundles of
## MultiMesh props.
func _cell_drawn(city: Node, cell: Node3D) -> Array:
	var out: Array = []
	for n in city.get_node("Facades").get_children():
		if n.get_meta("cell", "") == String(cell.name):
			out.append(n)
	for n in cell.get_children():
		var nm := String(n.name)
		if n is MultiMeshInstance3D or (n is MeshInstance3D and (nm.contains("Road") or nm.contains("Sidewalk") or nm.contains("Curb"))) or (n is StaticBody3D and nm.contains("Car")):
			out.append(n)
	return out

func _block_cells_checks(gs: Node) -> void:
	await _section("The block: far cells sleep, near ones wake; walls between you and the camera dither out")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 22 * 60
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var cells_node := city.get_node_or_null("BlockCells")
	_check(cells_node != null and cells_node.get("WAKE_MARGIN") == 25.0 and cells_node.has_signal("cell_changed") and cells_node.has_method("is_awake"),
		"  BlockCells is on the block (margin %s)" % [cells_node.get("WAKE_MARGIN") if cells_node else "-"])
	if cells_node == null:
		return
	var player := _player()
	var cells: Array = BLOCK_CELLS.map(func(n): return city.get_node(n))
	# Each cell in turn: stand in it, and it and whatever's within the
	# margin wake; the rest sleep, landmarks still standing.
	var wrong := []
	var spots := {"Cell_Main": Vector3(-17.5, 0, -2.6), "Cell_West": Vector3(-66.6, 0, -47.8), "Cell_East": Vector3(66.6, 0, -47.8),
		"Cell_Back": Vector3(-20.0, 0, -95.0), "Cell_Inner": Vector3(-7.5, 0, -50.0)}
	var asleep_seen := 0
	for cn in spots:
		player.global_position = spots[cn]
		player.reset_physics_interpolation()
		await _frames(BLOCK_SETTLE_FRAMES)
		var at: Vector3 = spots[cn]
		for c in cells:
			# Within the wake margin it's awake; past the sleep margin, asleep;
			# in between it keeps whatever it was (hysteresis).
			var box: AABB = c.get_meta("bounds")
			var near := box.grow(cells_node.WAKE_MARGIN).has_point(Vector3(at.x, 1.0, at.z))
			var far := not box.grow(cells_node.SLEEP_MARGIN).has_point(Vector3(at.x, 1.0, at.z))
			if not near and not far:
				continue
			var want := near
			var drawn := _cell_drawn(city, c)
			var ok: bool = cells_node.is_awake(c) == want
			# Asleep or not, the buildings, ground and cars are drawn.
			ok = ok and drawn.size() > 3 and drawn.all(func(n): return n.visible)
			if want:
				ok = ok and c.process_mode != Node.PROCESS_MODE_DISABLED
			else:
				asleep_seen += 1
				ok = ok and c.process_mode == Node.PROCESS_MODE_DISABLED
			if not ok:
				var odd := drawn.filter(func(n): return not n.visible).map(func(n): return n.name)
				wrong.append("%s at %s: want %s (awake %s, mode %d, hidden %s)" % [c.name, cn, "awake" if want else "asleep", cells_node.is_awake(c), c.process_mode, odd.slice(0, 3)])
	_check(wrong.is_empty() and asleep_seen >= 5, "  standing in each cell wakes it and its neighbours and sleeps the rest (%d asleep seen; wrong %s)" % [asleep_seen, wrong.slice(0, 4)])
	print("    (the last switch took %.2f ms)" % [cells_node.last_switch_usec / 1000.0])
	# From the Back Street corner Main is fast asleep, and the landmarks stand.
	player.global_position = spots["Cell_Back"]
	await _frames(BLOCK_SETTLE_FRAMES)
	var main := city.get_node("Cell_Main") as Node3D
	var marks := get_nodes_in_group("landmark").filter(func(n): return city.is_ancestor_of(n))
	_check(not cells_node.is_awake(main) and marks.size() >= 2 and marks.all(func(n): return n.is_visible_in_tree()),
		"  from Back Street, Main sleeps and the %d landmarks are still there" % marks.size())
	# ...and so are its buildings: masses and fronts are drawn, not hidden
	# at the edge of a margin.
	var masses := city.get_node("Facades").get_children().filter(func(n): return n.name.begins_with("Mass") and n.get_meta("cell", "") == "Cell_Main")
	var fronts := city.get_node("Facades").get_children().filter(func(n): return n.name.begins_with("Front") and n.get_meta("cell", "") == "Cell_Main")
	_check(masses.size() >= 8 and fronts.size() >= 8 and masses.all(func(n): return n.is_visible_in_tree()) and fronts.all(func(n): return n.is_visible_in_tree()),
		"  ...Main's %d building masses and %d fronts are still drawn while it sleeps" % [masses.size(), fronts.size()])
	# The small props thin out with distance instead (a fade, not a hide).
	var props: Array = cells_node.props(main)
	var unfaded := []
	for pr in props:
		for g in [pr] + pr.find_children("*", "GeometryInstance3D", true, false):
			if g is GeometryInstance3D and not (g.visibility_range_end > 0.0 and g.visibility_range_end + g.visibility_range_end_margin <= 25.0 and g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF):
				unfaded.append(pr.name)
	var hidden_props := props.filter(func(n): return not n.visible)
	_check(props.size() >= 10 and unfaded.is_empty() and hidden_props.is_empty(),
		"  ...Main's %d small props fade by distance (within 25 m) and aren't hidden by sleep (unfaded %s, hidden %s)" % [props.size(), unfaded.slice(0, 3), hidden_props.slice(0, 3)])
	var big: Array = cells_node.props(main).filter(func(n): return String(n.name).begins_with("Car") or String(n.name).begins_with("Truck") or String(n.name).begins_with("Building"))
	_check(big.is_empty(), "  ...cars and building bodies are not among them (%s)" % [big.slice(0, 3)])
	await create_timer(0.8).timeout
	# Lights: a sleeping cell's are off; waking it at night brings them back
	# on, by day it leaves them off.
	# (Sign glows aside: two of them flicker -- StreetLife.)
	var main_lights := city.find_children("*", "Light3D", true, false).filter(func(l): return main.is_ancestor_of(l) and (l.is_in_group("night_lights") or String(l.get_parent().name).begins_with("Streetlight")))
	_check(main_lights.size() > 5 and main_lights.all(func(l): return not l.is_visible_in_tree()), "  Main asleep: its %d after-dark lights are off (on: %s)" % [main_lights.size(), main_lights.filter(func(l): return l.is_visible_in_tree()).map(func(l): return main.get_path_to(l)).slice(0, 4)])
	player.global_position = spots["Cell_Main"]
	# A lamp pool fades in; it doesn't pop on.
	var first_lamp := main_lights[0] as Light3D
	var base_energy: float = city._night_lights.filter(func(e): return e[0] == first_lamp)[0][1]
	var t_end := Time.get_ticks_msec() + 1000
	var mid := 0
	var peak := 0.0
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var e: float = first_lamp.light_energy if first_lamp.visible else 0.0
		peak = maxf(peak, e)
		if e > 0.05 * base_energy and e < 0.95 * base_energy:
			mid += 1
	_check(mid >= 2 and peak >= 0.95 * base_energy, "  ...a woken lamp fades up over a few frames (%d in between, peak %.1f of %.1f)" % [mid, peak, base_energy])
	_check(main_lights.all(func(l): return l.is_visible_in_tree() and l.light_energy > 0.01), "  ...woken at 22:00, they come back on (off: %s)" % [main_lights.filter(func(l): return not (l.is_visible_in_tree() and l.light_energy > 0.01)).map(func(l): return "%s v%s e%.2f" % [main.get_path_to(l), l.visible, l.light_energy]).slice(0, 4)])
	var buzz := main.find_children("Buzz", "AudioStreamPlayer3D", true, false)
	_check(buzz.size() > 3 and buzz.all(func(a): return a.playing), "  ...and its %d lamps buzz again" % buzz.size())
	player.global_position = spots["Cell_Back"]
	await _frames(BLOCK_SETTLE_FRAMES)
	gs.clock = 14 * 60
	gs.advance_clock(1)
	# A dry afternoon: in the rain the lamps come half on (City3D).
	gs.raining = false
	city._apply_daylight()
	await _frames(3)
	player.global_position = spots["Cell_Main"]
	await _frames(BLOCK_SETTLE_FRAMES)
	_check(cells_node.is_awake(main) and main_lights.all(func(l): return not l.is_visible_in_tree() or l.light_energy <= 0.01),
		"  ...and woken at 14:00 they stay off (on: %s)" % [main_lights.filter(func(l): return l.is_visible_in_tree() and l.light_energy > 0.01).map(func(l): return "%s e%.2f" % [main.get_path_to(l), l.light_energy]).slice(0, 4)])
	# Anything in "cell_sleepers" stops with its cell.
	var sleeper := Node3D.new()
	sleeper.add_to_group("cell_sleepers")
	city.add_child(sleeper)
	sleeper.global_position = Vector3(-20.0, 0, -95.0)
	player.global_position = spots["Cell_Main"]
	await _frames(BLOCK_SETTLE_FRAMES)
	var froze := not sleeper.can_process()
	player.global_position = spots["Cell_Back"]
	await _frames(BLOCK_SETTLE_FRAMES)
	_check(froze and sleeper.can_process(), "  a cell_sleeper on Back Street freezes when it sleeps and runs when it wakes")
	sleeper.queue_free()
	# Hysteresis: a cell wakes at WAKE_MARGIN but sleeps only past
	# SLEEP_MARGIN, so stepping back and forth over the line is one switch,
	# not one a frame or two.
	var back := city.get_node("Cell_Back") as Node3D
	var back_box: AABB = back.get_meta("bounds")
	var line_z := back_box.end.z + float(cells_node.get("WAKE_MARGIN"))
	player.global_position = Vector3(-7.0, 0, line_z + 14.0)
	await _frames(BLOCK_SETTLE_FRAMES)
	var flips := [0]
	var counter := func(c: Node3D, _on: bool):
		if c == back:
			flips[0] += 1
	cells_node.cell_changed.connect(counter)
	for i in 8:
		player.global_position = Vector3(-7.0, 0, line_z + (-1.0 if i % 2 == 0 else 1.0))
		await _frames(6)
	cells_node.cell_changed.disconnect(counter)
	var sleep_m: float = float(cells_node.get("SLEEP_MARGIN")) if cells_node.get("SLEEP_MARGIN") != null else 0.0
	_check(sleep_m > float(cells_node.get("WAKE_MARGIN")) and flips[0] == 1,
		"  hysteresis: sleep margin %.0f m over wake %.0f m, and 8 steps over the line give %d switch of Back (want exactly the one wake)" % [sleep_m, cells_node.get("WAKE_MARGIN"), flips[0]])
	# One rule for the rain's dimming: the clock's daylight and the lamps
	# both read City3D._effective_daylight (0.55 in rain), the lamps off
	# the value _apply_daylight worked out.
	gs.clock = 18 * 60 + 40
	gs.raining = true
	city._apply_daylight()
	var eff = city.call("_effective_daylight") if city.has_method("_effective_daylight") else -1.0
	var lamps = city.get("_lamps_on")
	var want_lamps := 1.0 - smoothstep(0.35, 0.75, gs.daylight() * 0.55)
	var src := FileAccess.get_file_as_string("res://world/City3D.gd")
	_check(is_equal_approx(eff, gs.daylight() * 0.55) and lamps != null and is_equal_approx(lamps, want_lamps) and src.count("GameState.raining") == 1,
		"  rain dims the sky and the lamps by one rule (effective %.3f, lamps %s want %.3f, %d reads of GameState.raining in City3D.gd)" % [eff, lamps, want_lamps, src.count("GameState.raining")])
	gs.raining = false
	city._apply_daylight()
	# The camera never hangs inside a building: on Back Street's south
	# sidewalk, with a building right behind you, it comes in instead. The
	# check asks the physics world, not Facades.
	var in_wall := []
	for bx in [-55.0, -40.0, -20.0, 5.0, 25.0]:
		player.global_position = Vector3(bx, 0, -86.5)
		player.reset_physics_interpolation()
		await _frames(BLOCK_SETTLE_FRAMES)
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = player.camera.global_position
		pq.collision_mask = 1
		var inside: Array = city.get_world_3d().direct_space_state.intersect_point(pq, 8).filter(func(r): return String(r["collider"].name).begins_with("Building"))
		var dist: float = player.camera.global_position.distance_to(player.global_position + Vector3(0, 1.2, 0))
		if not inside.is_empty() or dist < 1.0:
			in_wall.append("x%.0f %s cam %s %.1f m from you" % [bx, inside.map(func(r): return r["collider"].name), player.camera.global_position, dist])
	_check(in_wall.is_empty(), "  on Back Street's south sidewalk the camera stays out of the buildings behind you (%s)" % [in_wall.slice(0, 3)])
	# The walls: standing at the service lane's east end, a shop's roof and
	# walls are between you and the camera (which is out in the open above
	# them), and they're cutaway material.
	player.global_position = Vector3(16.0, 0, -18.0)
	player.reset_physics_interpolation()
	await _frames(BLOCK_SETTLE_FRAMES)
	var cam: Camera3D = player.camera
	var from := cam.global_position
	var to := player.global_position + Vector3(0, 1.0, 0)
	var between := []
	var plain := []
	for mi in get_nodes_in_group("cutaway"):
		if not (mi is GeometryInstance3D and city.is_ancestor_of(mi) and mi.is_visible_in_tree()):
			continue
		var box: AABB = (mi as GeometryInstance3D).global_transform * (mi as VisualInstance3D).get_aabb()
		if box.intersects_segment(from, to):
			between.append(mi)
	var builds := city.get_node("Cell_Main").find_children("Building*", "StaticBody3D", false, false)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	# The camera hangs inside the building's box.
	q.hit_from_inside = true
	var hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(q)
	for mi in between:
		for s in _surface_mats(mi):
			if not (s is ShaderMaterial and (s as ShaderMaterial).shader and (s as ShaderMaterial).shader.resource_path.begins_with("res://assets/shaders/cutaway")):
				plain.append("%s" % mi.name)
				break
	_check(not hit.is_empty() and hit["collider"] in builds and between.size() > 0 and plain.is_empty(),
		"  from the lane's east end a Main Street building (%s) stands between camera and you, and its %d meshes there dither (plain: %s)" % [hit["collider"].name if hit else "nothing", between.size(), plain.slice(0, 3)])
	# The globals as the player last set them (a headless RenderingServer
	# keeps no values to read back).
	var pw: Vector3 = player.cutaway_globals[0]
	var radius: float = player.cutaway_globals[1]
	_check(pw.distance_to(player.get_global_transform_interpolated().origin) < 0.05 and radius > 0.5,
		"  player_world_pos follows you (%s vs %s), cutaway radius %.1f m" % [pw, player.global_position, radius])
	root.get_node("Graphics").set_first_person(true)
	await _frames(3)
	radius = player.cutaway_globals[1]
	_check(radius == 0.0, "  in first person nothing dithers (radius %.1f)" % radius)
	root.get_node("Graphics").set_first_person(false)
	await _frames(3)
	# Static occluders: a box per building, in its cell.
	var buildings := 0
	var boxed := 0
	for cn in BLOCK_CELLS:
		var c := city.get_node(cn)
		for body in c.find_children("Building*", "StaticBody3D", false, false):
			buildings += 1
			var occ := body.get_node_or_null("Occluder") as OccluderInstance3D
			if occ and occ.occluder is BoxOccluder3D:
				boxed += 1
	_check(buildings > 50 and boxed == buildings, "  every building has its occluder box (%d of %d)" % [boxed, buildings])
	# Repeated props: a MultiMesh per mesh per cell (per 16 m tile of it,
	# so they still cull), not a node each.
	var loose := city.find_children("*Bags*", "Node3D", true, false).filter(func(n): return n.get_parent().name.begins_with("Cell_") and not (n is MultiMeshInstance3D))
	var mms := city.find_children("MM_*", "MultiMeshInstance3D", true, false).filter(func(n): return n.get_parent().name.begins_with("Cell_"))
	var instanced := 0
	for mm in mms:
		instanced += (mm as MultiMeshInstance3D).multimesh.instance_count
	_check(loose.is_empty() and mms.size() >= 5 and instanced > 100 and instanced > mms.size() * 3, "  bags, bins and road dashes are %d MultiMeshes in the cells (%d instances; loose: %s)" % [mms.size(), instanced, loose.slice(0, 3)])
	gs.clock = 17 * 60
	gs.start_run()

## Frames for every cell to settle after a move (one changes per frame,
## a big one spread over a few).
const BLOCK_SETTLE_FRAMES := 40

func _surface_mats(gi: GeometryInstance3D) -> Array:
	if gi.material_override:
		return [gi.material_override]
	var out := []
	if gi is MeshInstance3D:
		var mi := gi as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			out.append(mi.get_active_material(i))
	elif gi is MultiMeshInstance3D:
		var mesh: Mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		for i in mesh.get_surface_count():
			out.append(mesh.surface_get_material(i))
	return out


# --- Real cars (assets/cars/, world/CarPaint.gd) -----------------------------------

func _car_checks(gs: Node) -> void:
	await _section("Cars: real models, old paint, wheels that turn, wrecks in Dead Block")
	_close_menus()
	var CarPaint := load("res://world/CarPaint.gd")
	var files: Array = Array(DirAccess.get_files_at("res://assets/cars")).filter(func(f: String): return f.ends_with(".glb"))
	var bad := []
	var most := 0
	var no_wheels := []
	for f in files:
		var scene := load("res://assets/cars/" + f) as PackedScene
		if scene == null:
			bad.append(f)
			continue
		var m: Node3D = scene.instantiate()
		var tris := 0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (mi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(i)
				tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		most = maxi(most, tris)
		if tris > 30000:
			bad.append("%s (%d tris)" % [f, tris])
		if not f.begins_with("wreck") and CarPaint.wheels(m).size() != 4:
			no_wheels.append(f)
		m.free()
	_check(files.size() >= 12 and bad.is_empty(), "  all %d car files load, none over 30k triangles (the most: %d) %s" % [files.size(), most, bad])
	_check(no_wheels.is_empty() and not files.has("sedan_e30.glb"), "  every drivable car has its four wheel_* nodes %s" % [no_wheels])

	# Traffic: the new models, wheels turning, lamps at the car's own ends.
	gs.start_run()
	gs.clock_running = false
	gs.clock = 22 * 60
	var city := await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	var life := city.get_node("StreetLife")
	for car in life._cars:
		car.queue_free()
	life._cars.clear()
	life.traffic = false
	life._spawn_car(-30.0)
	var car: Node3D = life._cars[0]
	var model := car.get_child(0) as Node3D
	_check(String(model.scene_file_path).begins_with("res://assets/cars/") and not String(model.scene_file_path).contains("kenney"),
		"  a car in traffic is one of the new models (%s)" % model.scene_file_path.get_file())
	var wheels: Array = car.get_meta("wheels")
	var spin_before: Basis = (wheels[0] as Node3D).transform.basis
	life.traffic = true
	await _frames(20)
	_check(wheels.size() == 4 and not (wheels[0] as Node3D).transform.basis.is_equal_approx(spin_before), "  its wheels turn as it drives")
	var box: AABB = CarPaint.bounds(model)
	var lamp_x := []
	for lamp in car.get_children():
		if lamp is MeshInstance3D and (lamp as MeshInstance3D).mesh is BoxMesh:
			lamp_x.append((lamp as MeshInstance3D).position.x)
	_check(lamp_x.size() == 4 and absf(lamp_x.max() - (box.end.x - 0.05)) < 0.01 and absf(lamp_x.min() - (box.position.x + 0.05)) < 0.01,
		"  headlights and tail-lights sit at its own ends (%.2f, %.2f for a %.1f m car)" % [lamp_x.max() if not lamp_x.is_empty() else 0.0, lamp_x.min() if not lamp_x.is_empty() else 0.0, box.size.x])
	var glass := model.find_child("glass", true, false) as MeshInstance3D
	_check(glass != null and glass.get_surface_override_material(0) is StandardMaterial3D
		and (glass.get_surface_override_material(0) as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "  glass is dark and opaque, cheap on Low")
	life._spawn_car(-20.0)
	gs.set_raining(true)
	await _frames(3)
	var body_mat := (model.find_child("body", true, false) as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	_check(body_mat != null and float(body_mat.get_shader_parameter("wet")) == 1.0, "  rain makes the paint shine")
	gs.set_raining(false)
	await _frames(3)
	_check(float(body_mat.get_shader_parameter("wet")) == 0.0, "  ...and it dries")

	# Parked cars.
	var parked := city.find_children("Car*", "StaticBody3D", true, false)
	var real := parked.filter(func(c): return c.get_node_or_null("Model") != null and String(c.get_node("Model").scene_file_path).begins_with("res://assets/cars/"))
	var scene_text := FileAccess.get_file_as_string("res://world/City3D.tscn")
	_check(real.size() >= 10 and not scene_text.contains("assets/kenney/cars") and scene_text.contains("assets/cars/"),
		"  %d parked cars use assets/cars and the scene no longer refers to the Kenney kit" % real.size())
	var painted := real.filter(func(c): return (c.get_node("Model").find_child("body", true, false) as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial)
	_check(not painted.is_empty(), "  ...in old paint of their own (%d dressed)" % painted.size())
	var shapes := real.map(func(c): return c.find_children("*", "CollisionShape3D", false, false)[0].shape)
	_check(shapes.all(func(sh): return sh is BoxShape3D), "  ...each with a box to bump into, never its mesh")
	var cruiser_body := city.find_child("PoliceCruiser", true, false).get_node("Model").find_child("body", true, false) as MeshInstance3D
	_check(cruiser_body.get_surface_override_material(0) is ShaderMaterial and cruiser_body.visibility_range_end == life.CarPaint.PARKED_REACH,
		"  the cruiser is dressed too, and parked cars aren't drawn past %.0f m" % life.CarPaint.PARKED_REACH)

	# Dead Block: wrecks.
	var zm := root.get_node("ZombieMode")
	zm.begin(false)
	var zcity := await _load("res://world/City3D.tscn")
	await _frames(3)
	var block := zcity.get_node("ZombieBlock")
	var wrecks := get_nodes_in_group("wrecks")
	var placed := wrecks.filter(func(w): return String(w.name).begins_with("Wreck_"))
	_check(placed.size() >= 4 and block.wreck_count >= placed.size(), "  Dead Block has %d wrecks put on the road (%d with the swapped cars)" % [placed.size(), block.wreck_count])
	var meshy := wrecks.filter(func(w): return not w.find_children("*", "CollisionShape3D", false, false).all(func(c): return c.shape is BoxShape3D))
	_check(meshy.is_empty() and wrecks.all(func(w): return String(w.get_node("Model").scene_file_path).contains("wreck_")), "  all of them wreck models with box colliders")
	var space: PhysicsDirectSpaceState3D = zcity.get_world_3d().direct_space_state
	var overlapping := []
	for w in wrecks:
		for cs in w.find_children("*", "CollisionShape3D", false, false):
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (cs as CollisionShape3D).shape
			q.transform = (cs as CollisionShape3D).global_transform
			q.collision_mask = 0xFFFFFFFF & ~16
			q.exclude = [w.get_rid()]
			var hit: Array = space.intersect_shape(q, 8)
			if not hit.is_empty() and not String(w.name).begins_with("Car"):
				overlapping.append("%s x %s at %s" % [w.name, hit[0]["collider"].get_parent().name if hit[0]["collider"].name == "Solid" else hit[0]["collider"].name, (hit[0]["collider"] as Node3D).global_position.snappedf(0.1)])
	_check(overlapping.is_empty(), "  none of the new ones is in a wall or a parked car %s" % [overlapping])
	_check(zcity.find_children("Car*", "StaticBody3D", true, false).filter(func(c): return String(c.get_node("Model").scene_file_path).contains("wreck_")).size() >= 2,
		"  and some of the parked cars have become wrecks")
	# Leaving writes the zombie best; it was nothing, so leave no file behind
	# (the shell checks start from none).
	zm.leave()
	DirAccess.remove_absolute(zm.PATH)
	zm.best_round = 0
	zm.best_kills = 0
	zm.best_headshots = 0
	zm.best_time = 0.0
	gs.start_run()
	await _frames(20)

# --- Dead Block: the mode shell (autoload/ZombieMode.gd, world/ZombieBlock.gd) ----
func _story_snapshot(gs: Node) -> String:
	var d := {}
	for f in root.get_node("SaveGame").FIELDS:
		d[f] = gs.get(f)
	d["wanted"] = gs.wanted
	d["in_custody"] = gs.in_custody
	return var_to_str(d)

func _key_action(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev

func _buttons_named(node: Node, text: String) -> Array:
	return node.find_children("*", "Button", true, false).filter(func(b): return b.text == text)

func _zombie_shell_checks(gs: Node) -> void:
	await _section("Dead Block: rounds, points, the block, the end -- and the story untouched")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var sg := root.get_node("SaveGame")

	# Rounds.
	_check(zm.zombie_health(1) == 150 and zm.zombie_health(9) == 950 and zm.zombie_health(10) == 1045,
		"  health: 150 at round 1, 950 at 9, 1045 at 10 (%d, %d, %d)" % [zm.zombie_health(1), zm.zombie_health(9), zm.zombie_health(10)])
	_check(absi(zm.zombie_health(20) - 2710) <= 5, "  health at round 20 is about 2710 (%d)" % zm.zombie_health(20))
	var counts: Array = [6, 7, 8, 9, 10].map(func(r): return zm.zombies_in_round(r))
	_check(counts == [68, 70, 70, 73, 83], "  zombies per round 6..10 are 68, 70, 70, 73, 83 (2.5x the first design) (%s)" % [counts])
	var early: Array = [1, 2, 3, 4, 5].map(func(r): return zm.zombies_in_round(r))
	var rising := true
	for i in range(1, early.size()):
		rising = rising and early[i] > early[i - 1]
	_check(early[0] == 15 and rising and early[4] < counts[0], "  rounds 1..5 ramp up from 15 and stay under round 6 (%s)" % [early])

	# Points. A run has to be on for earning.
	zm.begin(false)
	_check(zm.points == 500 and zm.round == 0, "  a run starts with 500 points")
	_check(zm.try_spend(500) and zm.points == 0, "  exactly enough buys it, leaving 0")
	_check(not zm.try_spend(1) and zm.points == 0, "  with 0 points one point is too much, and nothing goes negative")
	zm.add_points(100, "test")
	_check(zm.points == 100 and not zm.try_spend(101) and zm.points == 100, "  one short fails and takes nothing")
	_check(zm.try_spend(100) and zm.points == 0, "  100 buys a 100")
	zm.double_points = true
	zm.add_points(60, "kill")
	_check(zm.points == 120, "  Double Points doubles what a 60 kill pays (%d)" % zm.points)
	_check(not zm.try_spend(121) and zm.try_spend(120) and zm.points == 0, "  ...but not a price: 120 still buys a 120, 121 does not")
	zm.double_points = false
	zm.leave()

	# Starting the mode and dying leave the story exactly as it was.
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	gs.cash = 37
	var street := await _load("res://world/City3D.tscn")
	_check(not street.zombie_mode and street.find_child("DoorToBar", true, false) != null, "  the story's block still has its doors")
	# The story's craft and notebook keys work on the story's block.
	var story_player := _player()
	story_player._unhandled_input(_key_action("craft"))
	_check(story_player.dialogue_active, "  C opens the craft menu in the story")
	_close_menus()
	story_player.dialogue_active = false
	# Leave it hurt, sick and raining: none of that may follow into Dead Block.
	gs.hurt_until = gs.now_minutes() + 600.0
	gs.craving = 5.0
	gs.raining = true
	_check(sg.save() and FileAccess.file_exists(sg.PATH), "  a story save exists to compare against")
	var save_hash := FileAccess.get_sha256(sg.PATH)
	var before := _story_snapshot(gs)
	DirAccess.remove_absolute(zm.PATH)

	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	_check(gs.mode == "zombies" and city.zombie_mode and city.get_node_or_null("ZombieBlock") != null, "  the block loads as the zombie variant")
	_check(zm.round == 1, "  round 1 has started (%d)" % zm.round)
	_check(not gs.is_hurt() and not gs.withdrawn(20.0) and not gs.is_raining() and gs.sickness() == 0.0,
		"  the story's wound, craving and weather don't follow you in")
	var zplayer := _player()
	zplayer._unhandled_input(_key_action("craft"))
	var roots_before := root.get_child_count()
	zplayer._unhandled_input(_key_action("notebook"))
	_check(not zplayer.dialogue_active and root.get_child_count() == roots_before, "  the craft and notebook keys do nothing in Dead Block")
	_check(city.get_node_or_null("Facades") != null and city.get_node_or_null("StreetDressing") != null, "  the buildings' faces and the street's wear are still up")
	_check(city.get_node_or_null("Atmosphere") == null and city.get_node_or_null("StreetScenes") == null, "  but not the story's weather and regulars")
	var doors := city.find_children("DoorTo*", "Area3D", true, false)
	_check(doors.is_empty() and city.find_child("StationDoor", true, false) == null, "  no door leads anywhere (%d left)" % doors.size())
	_check(city.find_child("Pusher", true, false) == null and city.find_child("Lookout", true, false) == null and city.find_child("Ray", true, false) == null,
		"  the pusher, lookout and Ray are gone")
	await _frames(40)
	var alive := ["pedestrians", "patrol", "collector", "mugger", "postman", "scavenge", "hide_spots"].filter(func(g): return get_nodes_in_group(g).size() > 0)
	_check(alive.is_empty(), "  no passers-by, cops, collector, post, scavenging or hiding (%s)" % [alive])
	var life := city.get_node_or_null("StreetLife")
	_check(life != null and not life.traffic and life._cars.is_empty(), "  no traffic")
	# The shops' rooms are furnished and empty: built when you come near, with
	# their floor and walls, but no clerk, no pawnbroker, nothing to lift.
	var z_shops := WALK_INS.map(func(w): return city.get_node("Cell_Main/" + String(w["node"])))
	_check(z_shops.all(func(sh): return sh._inert), "  the four walk-in shops are inert (no clerks, no theft)")
	for w in WALK_INS:
		var zs := city.get_node("Cell_Main/" + String(w["node"]))
		zplayer.global_position = Vector3(w["x"], 0, -2.6)
		zplayer.reset_physics_interpolation()
		var built := await _wait_loaded(zs)
		await _frames(3)
		var lifted: Array = zs.find_children("*", "Area3D", true, false).filter(func(a): return a.name != "Inside" and not a.is_queued_for_deletion())
		var staff: Array = get_nodes_in_group("guards").filter(func(g): return zs.is_ancestor_of(g) and not g.is_queued_for_deletion())
		_check(built and zs.get_node_or_null("FloorTiles") != null and zs.get_node_or_null("WallBack") != null and zs.get_node_or_null("Ceiling") != null,
			"  Dead Block: %s is built when you come near, floor and walls" % w["node"])
		_check(staff.is_empty() and lifted.is_empty() and zs.get_node_or_null("Pawnbroker") == null and zs.get_node("Gate").collision_layer == 0,
			"  ...empty (no clerk, no triggers) and the doorway open")
	# Night, dense red fog, a red sky -- whatever the hour was.
	var env: Environment = city.get_node("WorldEnvironment").environment
	_check(gs.daylight() == 0.0, "  permanent night (daylight %.2f)" % gs.daylight())
	_check(env.fog_enabled and env.fog_density >= 0.04, "  dense fog (%.3f)" % env.fog_density)
	_check(env.background_color.r > env.background_color.b * 2.0 and env.fog_light_color.r > env.fog_light_color.b, "  a red-tinged sky and fog")
	# Streetlights flicker: some lamp changes its energy over a second or two.
	var block := city.get_node("ZombieBlock")
	var lamps: Array = block._flickering.map(func(f): return f[0])
	var seen := {}
	for i in 150:
		await physics_frame
		for l in lamps:
			seen[l] = true if seen.has(l) or absf(l.light_energy - block._flickering[lamps.find(l)][1]) > 0.01 else false
	_check(block.flicker_count >= 3 and seen.values().any(func(v): return v), "  %d streetlights stutter, and some dimmed in 150 frames" % block.flicker_count)
	var fires: Node = city.get_node("ZombieBlock").get_node_or_null("CampFires")
	var fire_lights: Array = fires.find_children("*", "OmniLight3D", true, false) if fires else []
	var fire_flames: Array = fires.find_children("*", "GPUParticles3D", true, false) if fires else []
	_check(fire_lights.size() >= 3 and fire_flames.size() == fire_lights.size() and fire_lights.all(func(l): return not l.shadow_enabled),
		"  %d burning barrels at the camp, lit without shadows" % fire_lights.size())
	var camp_pos: Vector3 = city.find_child("Place_UnderpassCamp", true, false).global_position
	_check(fire_lights.all(func(l): return l.global_position.distance_to(camp_pos) < 5.0), "  ...at the underpass camp")
	# F3 through the presets: the fog stays the zombie's.
	var gfx_node := root.get_node("Graphics")
	gfx_node.set_preset(gfx_node.Preset.LOW)
	await _frames(5)
	var env_low: Environment = city.get_node("WorldEnvironment").environment
	_check(env_low.fog_sky_affect == 1.0 and env_low.fog_density >= 0.04 and env_low.background_color.r > env_low.background_color.b * 2.0,
		"  the fog survives a change to Low (sky affect %.1f, density %.3f)" % [env_low.fog_sky_affect, env_low.fog_density])
	gfx_node.set_preset(gfx_node.Preset.MEDIUM)
	await _frames(3)
	# The story's clock does not run.
	gs.clock_running = true
	var clock_then: float = gs.clock
	var craving_then: float = gs.craving
	await _frames(30)
	_check(gs.clock == clock_then and gs.craving == craving_then, "  the story's clock and craving stand still")
	gs.clock_running = false
	# The HUD.
	var zhud := get_first_node_in_group("zombie_hud")
	_check(zhud != null and zhud.round_label.text == "1" and zhud.points_label.text == "500", "  the HUD shows round 1 and 500 points")
	if zhud:
		var screen := Rect2(Vector2.ZERO, zhud.get_viewport().get_visible_rect().size)
		zhud.banner.text = "ROUND 104"
		zhud.round_label.text = "104"
		await _frames(2)
		var text_w: float = zhud.banner.get_theme_font("font").get_string_size(zhud.banner.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
		var banner_mid: float = zhud.banner.get_global_rect().get_center().x
		_check(abs(banner_mid - screen.size.x * 0.5) < 2.0 and text_w < zhud.banner.size.x, "  the round banner sits centred, all of it in the window")
		_check(screen.encloses(zhud.round_label.get_global_rect()) and screen.encloses(zhud.points_label.get_global_rect()), "  the round and points numbers sit inside the window")
		zhud._refresh()
	zm.add_points(70, "neck")
	_check(zhud.points_label.text == "570", "  ...and follows the points (%s)" % zhud.points_label.text)
	_check(not (get_first_node_in_group("hud") as CanvasLayer).visible, "  the story's HUD is hidden")
	# The end.
	zm.kills = 4
	zm.headshots = 2
	zm.game_over()
	await _frames(2)
	var screen := root.get_node_or_null("ZombieGameOver")
	_check(screen != null and paused and zm.over, "  dying shows the game-over screen")
	zm.game_over()
	_check(root.get_children().filter(func(n): return n.name.begins_with("ZombieGameOver")).size() == 1, "  ...once")
	var text: String = screen.stats_label.text if screen else ""
	_check(text.contains("Round 1") and text.contains("4 kills, 2 headshots"), "  it shows the round, kills and headshots (%s)" % text.replace("\n", " | "))
	var cfg := ConfigFile.new()
	_check(cfg.load(zm.PATH) == OK and cfg.get_value("best", "round", 0) == 1 and cfg.get_value("best", "kills", 0) == 4
		and cfg.get_value("best", "headshots", 0) == 2, "  the best went to the zombie save")
	await _frames(40)
	_check(FileAccess.get_sha256(sg.PATH) == save_hash, "  the story's save file is byte-identical")
	_check(_story_snapshot(gs) == before, "  the story's GameState is unchanged")
	# Title: back out through the screen's button.
	var to_title := _buttons_named(screen, "Title")
	_check(to_title.size() == 1, "  the screen offers Title")
	if to_title.size() == 1:
		to_title[0].pressed.emit()
	await _frames(15)
	_check(not paused and not zm.active and gs.mode == "story" and current_scene.scene_file_path.ends_with("TitleScreen.tscn"),
		"  Title leaves the mode and unpauses")
	# (Idle on the title, the story's own clock runs again, as it always did.)
	_check(FileAccess.get_sha256(sg.PATH) == save_hash, "  ...with the story's save still as it was")

	# Quitting mid-round (the pause menu's way out) keeps the best too.
	DirAccess.remove_absolute(zm.PATH)
	zm.load_best()
	zm.best_round = 0
	zm.begin(false)
	zm.start_round()
	zm.advance_round()
	zm.advance_round()
	zm.leave()
	var cfg2 := ConfigFile.new()
	_check(cfg2.load(zm.PATH) == OK and int(cfg2.get_value("best", "round", 0)) == 3 and gs.mode == "story", "  leaving mid-round keeps the round reached (3)")

	# The title screen's entry, with its view choice.
	var title := current_scene
	var entry := _buttons_named(title, "Zombies")
	_check(entry.size() == 1, "  the title screen has a Zombies button")
	if entry.size() == 1:
		root.get_node("Graphics").set_first_person(false)
		entry[0].pressed.emit()
		_check(_buttons_named(title, "Third person").is_empty(), "  it asks no view: Dead Block is first person")
		while root.get_node("SceneLoader").busy():
			await process_frame
		await _frames(15)
		_check(zm.active and gs.mode == "zombies" and root.get_node("Graphics").first_person and current_scene.get("zombie_mode") == true,
			"  Zombies starts the run on the zombie block, in first person")
		zm.game_over()
		await _frames(2)
	for s in root.get_children().filter(func(n): return n.name.begins_with("ZombieGameOver")):
		s.queue_free()
	paused = false
	zm.leave()
	DirAccess.remove_absolute(zm.PATH)
	root.get_node("Graphics").set_first_person(false)
	gs.start_run()

## Clips that have a real source: Quaternius UAL1/UAL2 retargeted onto Bip01, and the
## Kimodo (SOMA-RP) takes. All 21 of CharacterAnimator.ZOMBIE_CLIPS.
const ZOMBIE_REAL_CLIPS := ["z_idle", "z_scratch", "z_walk", "z_walk2", "z_walk3", "z_run", "z_crawl", "z_scream",
	"z_attack", "z_attack2", "z_attack3", "z_hit_head", "z_hit_chest", "z_hit_leg", "z_hit_knockback",
	"z_death", "z_death2", "z_standup", "z_climb", "p_stab", "p_kick"]

func _zombie_anim_checks(gs: Node) -> void:
	await _section("Zombie animations: the library, every alias, the fallbacks")
	var CA := load("res://npc/CharacterAnimator.gd")
	var lib := load("res://assets/zombie_anims/zombie_clips.res") as AnimationLibrary
	_check(lib != null and lib.get_animation_list().size() >= ZOMBIE_REAL_CLIPS.size(), "  the zombie library loads with its clips (%d)" % (lib.get_animation_list().size() if lib else 0))
	if lib == null:
		return
	var untidy := []
	for clip in lib.get_animation_list():
		var a := lib.get_animation(clip)
		var on_bip := a.get_track_count() > 20 and a.length > 0.1
		for t in a.get_track_count():
			on_bip = on_bip and String(a.track_get_path(t)).begins_with("Bip01/Skeleton3D:Bip01 ")
		if not on_bip:
			untidy.append(clip)
	_check(untidy.is_empty(), "  every clip is a real animation on Bip01 bones (%s)" % [untidy])
	_check(ZOMBIE_REAL_CLIPS.all(func(c): return lib.has_animation(c)), "  every clip with a source is in the library")

	# A Rocketbox avatar with the library: every alias plays something.
	var model := (load("res://assets/rocketbox/Male_Adult_04.glb") as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * 1.5
	root.add_child(model)
	_check(CA.install_zombie_library(model) and CA.install_zombie_library(model), "  the library installs on an avatar (twice is fine)")
	var anim = CA.new(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var unresolved := []
	var not_real := []
	for logical in CA.ZOMBIE_CLIPS:
		var real: String = anim.resolved_clip(logical)
		if real == "" or not player.has_animation(real):
			unresolved.append(logical)
		elif logical in ZOMBIE_REAL_CLIPS and not real.begins_with("zombie/"):
			not_real.append("%s->%s" % [logical, real])
	_check(unresolved.is_empty(), "  every zombie alias resolves to a clip on the avatar (%s)" % [unresolved])
	_check(not_real.is_empty(), "  every clip with a source plays the library's (%s)" % [not_real])
	var played := []
	for logical in CA.ZOMBIE_CLIPS:
		anim.play(logical)
		if player.current_animation != anim.resolved_clip(logical):
			played.append(logical)
		anim._current = ""
	_check(played.is_empty(), "  play() starts the resolved clip for each (%s)" % [played])
	_check(ZOMBIE_REAL_CLIPS.size() == CA.ZOMBIE_CLIPS.size() and CA.ZOMBIE_CLIPS.all(func(c): return c in ZOMBIE_REAL_CLIPS),
		"  every one of the %d zombie clip names has a real clip behind it" % CA.ZOMBIE_CLIPS.size())

	# A clip really drives the bones, at the avatar's own scale, with planted feet.
	var sk := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var thigh := sk.find_bone("Bip01 L Thigh")
	anim.play("z_walk")
	player.speed_scale = 0.0
	player.seek(0.3, true)
	player.advance(0.0)
	sk.force_update_all_bone_transforms()
	var swing := sk.get_bone_pose_rotation(thigh).angle_to(sk.get_bone_rest(thigh).basis.get_rotation_quaternion())
	_check(swing > 0.15, "  z_walk swings the thigh off its rest pose (%.2f rad)" % swing)
	player.play("walk")
	player.seek(0.3, true)
	player.advance(0.0)
	sk.force_update_all_bone_transforms()
	var toes := [sk.find_bone("Bip01 L Toe0"), sk.find_bone("Bip01 R Toe0")]
	var lowest := func(clip: String) -> float:
		player.stop()
		player.play(clip)
		player.speed_scale = 0.0
		var low := 99.0
		for st in 30:
			player.seek(float(st) / 30.0, true)
			player.advance(0.0)
			sk.force_update_all_bone_transforms()
			for tb in toes:
				low = minf(low, (sk.global_transform * sk.get_bone_global_pose(tb)).origin.y)
		return low
	var low_own: float = lowest.call("walk")
	var low_new: float = lowest.call("zombie/z_walk")
	_check(absf(low_new - low_own) < 0.08 and low_new > -0.08, "  the zombie walk's feet reach the floor like the avatar's own (toes %.3f vs %.3f m)" % [low_new, low_own])
	var fwd := (sk.global_transform * sk.get_bone_global_rest(toes[0])).origin - (sk.global_transform * sk.get_bone_global_rest(sk.find_bone("Bip01 L Foot"))).origin
	fwd.y = 0.0
	fwd = fwd.normalized()
	for clip in ["z_walk", "z_walk2", "z_run"]:
		var speed: float = anim.natural_speed(clip)
		var slowest := 99.0
		var prev := {}
		var real: String = anim.resolved_clip(clip)
		player.stop()
		player.play(real)
		player.speed_scale = 0.0
		var clip_len := player.get_animation(real).length
		var steps := int(clip_len * 30.0)
		for st in steps + 1:
			player.seek(float(st) / 30.0, true)
			player.advance(0.0)
			sk.force_update_all_bone_transforms()
			for b in ["Bip01 L Foot", "Bip01 R Foot"]:
				var p := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b))).origin
				if prev.has(b):
					var v: Vector3 = (p - prev[b]) * 30.0 + fwd * speed
					v.y = 0.0
					slowest = minf(slowest, v.length())
				prev[b] = p
		_check(speed > 0.5 and slowest < 0.25, "  %s: moving at its own pace (%.2f m/s) a foot stays planted (slowest %.2f m/s)" % [clip, speed, slowest])
	# The attacks are grabs, not punches: the hands must get well in front of the chest
	# (z_attack: both at the same moment, shoulder-high), never fists drawn up at the face.
	var chest := sk.find_bone("Bip01 Spine2")
	for clip in ["z_attack", "z_attack2", "z_attack3"]:
		var real: String = anim.resolved_clip(clip)
		player.stop()
		player.play(real)
		player.speed_scale = 0.0
		var best_both := 0.0
		var best_each := [0.0, 0.0]
		var clip_len := player.get_animation(real).length
		var worst_air := -9.0
		for st in int(clip_len * 30.0) + 1:
			player.seek(float(st) / 30.0, true)
			player.advance(0.0)
			sk.force_update_all_bone_transforms()
			var c := (sk.global_transform * sk.get_bone_global_pose(chest)).origin
			var ahead := []
			for h in ["Bip01 L Hand", "Bip01 R Hand"]:
				var hp := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(h))).origin
				ahead.append((hp - c).dot(fwd))
			# Feet on the floor: the lower of the two feet (foot or toe bone) never leaves it.
			var foot_y := []
			for side in ["L", "R"]:
				foot_y.append(minf((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 %s Foot" % side))).origin.y,
					(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 %s Toe0" % side))).origin.y))
			worst_air = maxf(worst_air, minf(foot_y[0], foot_y[1]))
			best_both = maxf(best_both, minf(ahead[0], ahead[1]))
			best_each = [maxf(best_each[0], ahead[0]), maxf(best_each[1], ahead[1])]
		# The avatar is scaled 1.5 here: a standing toe bone sits about 0.03 m up; a leap goes past 0.2.
		_check(worst_air < 0.12, "  %s: a foot stays on the floor throughout (lowest foot's peak height %.3f m)" % [clip, worst_air])
		if clip == "z_attack":
			_check(best_both > 0.3, "  z_attack: both hands reach out in front of the chest at once (%.2f m)" % best_both)
		else:
			_check(minf(best_each[0], best_each[1]) > 0.3, "  %s: each hand gets out in front of the chest (%.2f / %.2f m)" % [clip, best_each[0], best_each[1]])
	# The legless crawler (Z2b/Z6): lies low, drags itself along in place, and loops without a pop.
	var crawl_real: String = anim.resolved_clip("z_crawl")
	var crawl_anim := player.get_animation(crawl_real)
	player.stop()
	player.play(crawl_real)
	player.speed_scale = 0.0
	var pelvis_b := sk.find_bone("Bip01 Pelvis")
	var pel_hi := 0.0
	var pel_min := Vector2(99.0, 99.0)
	var pel_max := Vector2(-99.0, -99.0)
	for st in int(crawl_anim.length * 30.0) + 1:
		player.seek(float(st) / 30.0, true)
		player.advance(0.0)
		sk.force_update_all_bone_transforms()
		var pp := (sk.global_transform * sk.get_bone_global_pose(pelvis_b)).origin
		pel_hi = maxf(pel_hi, pp.y)
		pel_min = Vector2(minf(pel_min.x, pp.x), minf(pel_min.y, pp.z))
		pel_max = Vector2(maxf(pel_max.x, pp.x), maxf(pel_max.y, pp.z))
	_check(crawl_anim.loop_mode != Animation.LOOP_NONE and crawl_anim.has_meta("in_place"), "  z_crawl loops and is flagged in place")
	_check(pel_hi < 0.3 and (pel_max - pel_min).length() < 0.4,
		"  z_crawl lies low and stays in place (pelvis at most %.2f m high, wanders %.2f m)" % [pel_hi, (pel_max - pel_min).length()])
	var loop_gap := 0.0   # rotation jump from the last key back to the first, against the largest step inside
	var biggest_step := 0.0
	for t in crawl_anim.get_track_count():
		if crawl_anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var n := crawl_anim.track_get_key_count(t)
		var first: Quaternion = crawl_anim.track_get_key_value(t, 0)
		var last: Quaternion = crawl_anim.track_get_key_value(t, n - 1)
		loop_gap = maxf(loop_gap, first.angle_to(last))
		for k in range(1, n):
			biggest_step = maxf(biggest_step, (crawl_anim.track_get_key_value(t, k - 1) as Quaternion).angle_to(crawl_anim.track_get_key_value(t, k)))
	# Prone belly crawl: the chest's front stays facing the floor (no rolling onto the side), and
	# the hands take turns reaching forward along the body (not both together).
	var chest_b := sk.find_bone("Bip01 Spine2")
	var local_front: Vector3 = sk.get_bone_global_rest(chest_b).basis.inverse() * (sk.global_transform.basis.inverse() * fwd).normalized()
	var worst_off := 0.0
	var reach_l: Array[float] = []
	var reach_r: Array[float] = []
	for st in int(crawl_anim.length * 30.0) + 1:
		player.seek(float(st) / 30.0, true)
		player.advance(0.0)
		sk.force_update_all_bone_transforms()
		var front_w := (sk.global_transform.basis * sk.get_bone_global_pose(chest_b).basis * local_front).normalized()
		worst_off = maxf(worst_off, rad_to_deg(acos(clampf(-front_w.y, -1.0, 1.0))))
		var pelvis_p := (sk.global_transform * sk.get_bone_global_pose(pelvis_b)).origin
		var axis := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Head"))).origin - pelvis_p
		axis.y = 0.0
		axis = axis.normalized()
		reach_l.append(((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 L Hand"))).origin - pelvis_p).dot(axis))
		reach_r.append(((sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 R Hand"))).origin - pelvis_p).dot(axis))
	_check(worst_off < 25.0 and cos(deg_to_rad(worst_off)) > 0.8, "  z_crawl stays prone: the chest's front is never more than %.0f degrees off straight down (down component %.2f, must stay above 0.8)" % [worst_off, cos(deg_to_rad(worst_off))])
	var mean_l := 0.0
	var mean_r := 0.0
	for k in reach_l.size():
		mean_l += reach_l[k] / reach_l.size()
		mean_r += reach_r[k] / reach_r.size()
	var cov := 0.0
	var var_l := 0.0
	var var_r := 0.0
	for k in reach_l.size():
		cov += (reach_l[k] - mean_l) * (reach_r[k] - mean_r)
		var_l += pow(reach_l[k] - mean_l, 2.0)
		var_r += pow(reach_r[k] - mean_r, 2.0)
	var corr := cov / maxf(sqrt(var_l * var_r), 0.0001)
	var span_l: float = reach_l.max() - reach_l.min()
	var span_r: float = reach_r.max() - reach_r.min()
	_check(span_l > 0.2 and span_r > 0.2 and corr < 0.5,
		"  z_crawl: both hands pull forward in turn (reach %.2f / %.2f m, left-right correlation %.2f; in step would be near 1)" % [span_l, span_r, corr])
	_check(loop_gap <= biggest_step * 1.5 + 0.02, "  z_crawl closes its loop (last key to first: %.3f rad, biggest step inside %.3f)" % [loop_gap, biggest_step])
	model.queue_free()

	# Fallbacks: no library, and a library missing a clip.
	var bare := (load("res://assets/rocketbox/Male_Adult_04.glb") as PackedScene).instantiate() as Node3D
	root.add_child(bare)
	var bare_anim = CA.new(bare)
	var bare_player := bare.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var missing: Array = CA.ZOMBIE_CLIPS.filter(func(c): return bare_anim.resolved_clip(c) == "" or not bare_player.has_animation(bare_anim.resolved_clip(c)) or bare_anim.resolved_clip(c).begins_with("zombie/"))
	_check(missing.is_empty(), "  without the library every zombie alias falls back to a Rocketbox clip (%s)" % [missing])
	_check(bare_anim.resolved_clip("z_walk") == "walk_sick" and bare_anim.resolved_clip("z_run") == "sprint" and bare_anim.resolved_clip("z_attack") == "take",
		"  the fallbacks are the ones meant: walk_sick, sprint, take (%s, %s, %s)" % [bare_anim.resolved_clip("z_walk"), bare_anim.resolved_clip("z_run"), bare_anim.resolved_clip("z_attack")])
	bare.queue_free()
	var cut := (load("res://assets/rocketbox/Male_Adult_04.glb") as PackedScene).instantiate() as Node3D
	root.add_child(cut)
	var short_lib := lib.duplicate(true) as AnimationLibrary
	short_lib.remove_animation("z_death")
	short_lib.remove_animation("z_hit_head")
	var cut_player := cut.find_child("AnimationPlayer", true, false) as AnimationPlayer
	cut_player.add_animation_library("zombie", short_lib)
	var cut_anim = CA.new(cut)
	_check(cut_anim.resolved_clip("z_hit_head") == "zombie/z_hit_chest" and cut_anim.resolved_clip("z_death") == "crouch" and cut_anim.resolved_clip("z_walk") == "zombie/z_walk",
		"  a clip missing from the library falls back (hit_head -> %s, death -> %s), the rest stay (%s)" % [cut_anim.resolved_clip("z_hit_head"), cut_anim.resolved_clip("z_death"), cut_anim.resolved_clip("z_walk")])
	cut.queue_free()
	# The story's own casting is untouched.
	var man := (load("res://assets/rocketbox/Male_Adult_04.glb") as PackedScene).instantiate() as Node3D
	root.add_child(man)
	CA.install_zombie_library(man)
	var man_anim = CA.new(man)
	_check(man_anim.resolved_clip("walk") == "walk" and man_anim.resolved_clip("sprint") == "sprint" and man_anim.resolved_clip("idle") == "idle",
		"  the story's walk, sprint and idle still resolve to the avatar's own clips with the library installed")
	man.queue_free()

# --- Dead Block: the dead (npc/Zombie3D.gd, ZombieSpawner.gd, ZombieHitboxes.gd, world/Barricade.gd) --
func _zombie_dead_checks(gs: Node) -> void:
	await _section("Dead Block: the dead -- spawning, hit zones, the navmesh, barricades")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	await _frames(5)
	var block := city.get_node("ZombieBlock")
	var spawner: Node = block.spawner
	_check(spawner != null and spawner.is_in_group("zombie_spawner"), "  the block has a spawner")
	# Round 1 has started by itself; park it while the checks run their own rounds.
	spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player := _player()
	player.global_position = Vector3(-17.5, 0.0, -3.0)
	player.velocity = Vector3.ZERO
	var Hit := preload("res://npc/ZombieHitboxes.gd")

	# --- Health, kinds ---
	var healths := {}
	for r in [1, 5, 10, 20]:
		spawner.round_no = r
		var hz = spawner.spawn_one("walker", Vector3(0, 0, 30))
		healths[r] = hz.max_health == float(zm.zombie_health(r)) and hz.health == hz.max_health
		hz.free()
	_check(healths.values().all(func(v): return v), "  a zombie's health is zombie_health(round) at rounds 1, 5, 10, 20 (%s)" % [healths])
	var plan5: Array = spawner._plan_kinds(5, 24)
	var plan6: Array = spawner._plan_kinds(6, 27)
	var plan15: Array = spawner._plan_kinds(15, 44)
	_check(plan5.count("runner") == 0 and plan6.count("runner") >= 1 and plan6.count("runner") < 27 and plan15.count("runner") == 44,
		"  runners: none by round 5, some from round 6 (%d of 27), all by round 15" % plan6.count("runner"))

	# --- Hit zones ---
	spawner.round_no = 1
	var z = spawner.spawn_one("walker", Vector3(0.0, 0.0, 1.5))
	z.set_physics_process(false)
	z._anim_player.pause()
	z._model_root.rotation.y = 0.0
	await _frames(4)
	z.sync_hitboxes()
	_check(z.hitboxes.size() == 11 and Hit.PARTS.all(func(p): return z.hitboxes.has(p)), "  a zombie has 11 hit zones (%d)" % z.hitboxes.size())
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var head_c: Vector3 = (z.hitboxes["head"].get_child(0) as Node3D).global_position
	var q := PhysicsRayQueryParameters3D.create(head_c + Vector3(0, 0.1, 3.0), head_c)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = Hit.HITBOX_LAYER
	var res := space.intersect_ray(q)
	_check(not res.is_empty() and res["collider"].get_meta("part") == "head" and res["collider"].get_meta("zombie") == z,
		"  a ray at the head hits part == head (%s)" % [res.get("collider")])
	var wrong := []
	for p in Hit.PARTS:
		var c: Vector3 = (z.hitboxes[p].get_child(0) as Node3D).global_position
		var others: Array[RID] = []
		for o in Hit.PARTS:
			if o != p:
				others.append((z.hitboxes[o] as Area3D).get_rid())
		var q2 := PhysicsRayQueryParameters3D.create(c + Vector3(0.0, 0.0, 2.0), c)
		q2.collide_with_areas = true
		q2.collide_with_bodies = false
		q2.collision_mask = Hit.HITBOX_LAYER
		q2.exclude = others
		var r2 := space.intersect_ray(q2)
		if r2.is_empty() or r2["collider"].get_meta("part") != p:
			wrong.append(p)
	_check(wrong.is_empty(), "  a ray at each zone's centre hits that part (wrong: %s)" % [wrong])
	var ys := {}
	for p in Hit.PARTS:
		ys[p] = (z.hitboxes[p].get_child(0) as Node3D).global_position.y
	_check(ys["head"] > ys["neck"] and ys["neck"] > ys["torso"] and ys["torso"] > ys["upper_leg_l"] and ys["upper_leg_l"] > ys["lower_leg_l"]
		and ys["lower_leg_l"] > 0.0 and ys["head"] < 2.0, "  zones stack head over neck over torso over legs, on a person's scale (head %.2f m)" % ys["head"])
	var hits_seen := []
	z.hit.connect(func(_zz, part, dmg, killed): hits_seen.append([part, dmg, killed]))
	var died_log := []
	z.died.connect(func(_zz, part, melee): died_log.append([part, melee]))
	z.take_hit("torso", 50.0, Vector3.FORWARD, null)
	_check(is_equal_approx(z.health, z.max_health - 50.0) and z.is_alive() and z.is_in_group("zombies"), "  take_hit subtracts the damage")
	z.take_hit("head", z.max_health, Vector3.FORWARD, null)
	z.take_hit("head", 999.0, Vector3.FORWARD, null)
	await _frames(2)
	_check(died_log == [["head", false]] and not z.is_alive() and not z.is_in_group("zombies") and z.is_in_group("corpses"),
		"  the killing hit emits died once, with the part (%s)" % [died_log])
	_check(hits_seen.size() == 2 and hits_seen[1][2] == true, "  hit says which blow killed")
	z.free()
	# Insta-Kill and a melee flag.
	z = spawner.spawn_one("walker", Vector3(0.0, 0.0, 1.5))
	z.set_physics_process(false)
	zm.insta_kill = true
	var melee_log := []
	z.died.connect(func(_zz, part, melee): melee_log.append([part, melee]))
	z.take_hit("upper_leg_l", 1.0, Vector3.FORWARD, null, true)
	zm.insta_kill = false
	_check(melee_log == [["upper_leg_l", true]], "  Insta-Kill kills on any hit, and melee is passed on (%s)" % [melee_log])
	z.free()

	# --- Spawning ---
	spawner.time_scale = 0.01
	spawner.adaptive = false
	zm.max_alive = 32
	for r in [5, 6, 15]:
		for old in get_nodes_in_group("zombies"):
			old.free()
		var made := []
		var on_spawn := func(zz): made.append(zz.kind)
		spawner.spawned.connect(on_spawn)
		zm.round = r - 1
		spawner.enabled = true
		zm.start_round()
		var max_alive := 0
		var at_cap := false
		var frames := 0
		while spawner.released < spawner.total and frames < 3000:
			await physics_frame
			frames += 1
			for zz in get_nodes_in_group("zombies"):
				zz.set_physics_process(false)
			max_alive = maxi(max_alive, spawner.alive())
			if spawner.alive() >= zm.max_alive:
				at_cap = true
				# Mow down five and let the reserve come out.
				var live := get_nodes_in_group("zombies")
				for i in 5:
					live[i].take_hit("torso", 1.0e6, Vector3.FORWARD, null)
		spawner.enabled = false
		var kinds := {"walker": 0, "runner": 0}
		for k in made:
			kinds[k] += 1
		spawner.spawned.disconnect(on_spawn)
		_check(made.size() == zm.zombies_in_round(r) and max_alive <= zm.max_alive and (at_cap or zm.zombies_in_round(r) <= zm.max_alive),
			"  round %d: exactly %d came out, never more than %d alive (made %d, peak %d, capped %s)" % [r, zm.zombies_in_round(r), zm.max_alive, made.size(), max_alive, at_cap])
		if r == 5:
			_check(kinds["runner"] == 0, "  ...all walkers in round 5 (%s)" % [kinds])
		elif r == 6:
			_check(kinds["runner"] >= 1 and kinds["walker"] >= 1, "  ...runners among them from round 6 (%s)" % [kinds])
		else:
			_check(kinds["walker"] == 0, "  ...nothing but runners by round 15 (%s)" % [kinds])
	# Corpses: 20 dead in a row leave 12.
	for old in get_nodes_in_group("zombies"):
		old.free()
	for old in get_nodes_in_group("corpses"):
		old.free()
	spawner._corpses.clear()
	var kills_before: int = zm.kills
	var hs_before: int = zm.headshots
	for i in 20:
		var cz = spawner.spawn_one("walker", Vector3(-30.0 + i * 3.0, 0.0, 1.0))
		cz.set_physics_process(false)
		cz.take_hit("head" if i % 2 == 0 else "torso", 1.0e6, Vector3.FORWARD, null)
	await _frames(3)
	_check(spawner.corpse_count() <= 12, "  at most 12 corpses lie about (%d)" % spawner.corpse_count())
	_check(zm.kills - kills_before == 20 and zm.headshots - hs_before == 10, "  every kill is counted once, headshots among them (%d, %d)" % [zm.kills - kills_before, zm.headshots - hs_before])
	for old in get_nodes_in_group("corpses"):
		old.free()
	spawner._corpses.clear()

	# --- The navmesh ---
	var nav := city.get_node("NavRegion") as NavigationRegion3D
	var map := nav.get_navigation_map()
	_check(nav.navigation_mesh.resource_path.ends_with("zombie_navmesh.res"), "  zombie mode walks the zombie navmesh")
	# (A building's inside is an island on the mesh, cut off by its walls: what
	# matters is that no route goes through one.)
	var home := Vector3(-17.5, 0.0, -3.0)
	var into_pawn := NavigationServer3D.map_get_path(map, home, Vector3(0.0, 0.0, -10.0), true)
	_check(into_pawn.is_empty() or into_pawn[into_pawn.size() - 1].distance_to(Vector3(0.0, 0.0, -10.0)) > 1.0,
		"  there is no way into a building's mass from the street")
	var wreck_clear := true
	for w in block.WRECKS:
		var wp: Vector3 = w[2]
		var wpath := NavigationServer3D.map_get_path(map, home, wp, true)
		if not wpath.is_empty() and wpath[wpath.size() - 1].distance_to(wp) < 0.5:
			wreck_clear = false
	_check(wreck_clear, "  ...nor onto a wreck")
	var stuck := []
	var through := []
	var far_route := 0.0
	var space2: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	for sp in block.SPAWN_POINTS:
		var path := NavigationServer3D.map_get_path(map, sp, home, true)
		var plen := 0.0
		for i in range(1, path.size()):
			plen += path[i - 1].distance_to(path[i])
			# Walk the leg: nothing solid at chest height along it.
			var seg_len: float = path[i - 1].distance_to(path[i])
			var steps := int(seg_len / 0.5)
			for k in steps + 1:
				var pt: Vector3 = path[i - 1].lerp(path[i], float(k) / maxf(steps, 1)) + Vector3(0, 1.0, 0)
				var pq := PhysicsPointQueryParameters3D.new()
				pq.position = pt
				pq.collision_mask = 1
				var hits := space2.intersect_point(pq, 4).filter(func(h): return not (h["collider"] as Node).is_in_group("barricades"))
				if not hits.is_empty():
					through.append(sp)
					break
			if through.has(sp):
				break
		if path.size() < 2 or path[path.size() - 1].distance_to(home) > 1.0 or plen > sp.distance_to(home) * 4.0 + 20.0:
			stuck.append(sp)
		far_route = maxf(far_route, plen)
	_check(stuck.is_empty(), "  every spawn point has a route to Main Street (unreachable or absurd: %s; longest %.0f m)" % [stuck, far_route])
	_check(through.is_empty(), "  and no route goes through anything solid (%s)" % [through])

	# --- Walking across the block ---
	spawner.round_no = 8
	player.global_position = Vector3(30.0, 0.0, -2.0)
	player.velocity = Vector3.ZERO
	var runner = spawner.spawn_one("runner", Vector3(71.0, 0.0, -30.0))
	var hit_log := []
	runner.attacked.connect(func(zz, _dmg): hit_log.append(zz.global_position.distance_to(player.global_position)))
	var start_d: float = runner.global_position.distance_to(player.global_position)
	var best_d := start_d
	for i in 2400:
		await physics_frame
		best_d = minf(best_d, runner.global_position.distance_to(player.global_position))
		if not hit_log.is_empty():
			break
	_check(not hit_log.is_empty() and hit_log[0] < 2.0 and absf(runner.global_position.y) < 0.3,
		"  a runner crosses the block (%.0f m, East Ave to Main) and claws the player from %s m (closest %.1f m, y %.2f)" % [start_d, hit_log.map(func(d): return snappedf(d, 0.1)).slice(0, 1), best_d, runner.global_position.y])
	runner.free()

	# --- Barricades ---
	var bars: Array = get_nodes_in_group("barricades")
	_check(bars.size() >= 2 and bars.all(func(b): return b.boards == b.BOARD_COUNT), "  the alley mouths are boarded (%d barricades, all %d boards)" % [bars.size(), 6])
	var bar: Node3D = block.barricades[0]
	var bar_z: float = bar.global_position.z
	player.global_position = Vector3(bar.global_position.x, 0.0, -2.0)
	player.velocity = Vector3.ZERO
	var gate_runner = spawner.spawn_one("runner", Vector3(bar.global_position.x, 0.0, -17.5))
	var crossed_early := false
	var last_boards: int = bar.boards
	var monotone := true
	var open_at := -1
	for i in 2400:
		await physics_frame
		if bar.boards > last_boards:
			monotone = false
		last_boards = bar.boards
		if gate_runner.global_position.z > bar_z + 0.3 and bar.boards > 0:
			crossed_early = true
		if bar.boards == 0 and open_at < 0:
			open_at = i
		if open_at >= 0 and gate_runner.global_position.z > bar_z + 1.5:
			break
	_check(bar.boards == 0 and monotone, "  the dead tear every board off (boards left %d)" % bar.boards)
	_check(not crossed_early, "  and don't get through before the last is down")
	_check(gate_runner.global_position.z > bar_z + 1.0, "  then they come through (z %.1f past the boards at %.1f)" % [gate_runner.global_position.z, bar_z])
	gate_runner.free()
	# Nailing them back: ten points a board.
	zm.points = 0
	player.global_position = Vector3(bar.global_position.x, 0.0, bar.global_position.z + 0.1)
	_check(not bar.repair_board(player), "  you can't board it up while you stand in the gap")
	player.global_position = Vector3(bar.global_position.x, 0.0, -3.0)
	var ok1: bool = bar.repair_board(player)
	var ok2: bool = bar.repair_board(player)
	await create_timer(0.6).timeout
	var ok3: bool = bar.repair_board(player)
	_check(ok1 and not ok2 and ok3 and bar.boards == 2 and zm.points == 20, "  each board nailed back pays 10 points, one a press (boards %d, points %d)" % [bar.boards, zm.points])
	zm.double_points = true
	await create_timer(0.6).timeout
	bar.repair_board(player)
	zm.double_points = false
	_check(zm.points == 40, "  Double Points doubles the 10 (points %d)" % zm.points)
	await _frames(2)
	var blocker := bar.get_child(0) as CollisionShape3D
	_check(blocker != null and not blocker.disabled, "  with boards up it blocks the way again")
	bar.repair_all()
	await _frames(2)
	_check(bar.boards == bar.BOARD_COUNT and zm.points == 40, "  repair_all restores the rest without paying (%d points)" % zm.points)

	# --- A hit to the leg: down on a knee, then up (or on, legless) ---
	player.global_position = Vector3(-17.5, 0.0, -3.0)
	var knee = spawner.spawn_one("walker", Vector3(-17.5, 0.0, 14.0))
	await _frames(10)
	var knee_from: Vector3 = knee.global_position
	knee.take_hit("lower_leg_l", knee.max_health * 0.2, Vector3.FORWARD, null)
	await _frames(3)
	var knelt: bool = knee.is_kneeling() and knee.anim.current_clip() == "z_hit_leg"
	await _frames(30)
	var held: bool = knee.is_kneeling() and knee.global_position.distance_to(knee_from) < 0.5 and Vector2(knee.velocity.x, knee.velocity.z).length() < 0.2
	await _frames(int(knee.KNEEL_TIME * 60.0))
	var rose: bool = knee.state == knee.State.STANDUP and knee.anim.current_clip() == "z_standup"
	await _frames(int(knee.anim.play_once("z_standup", 1.0) * 60.0) + 20)
	_check(knelt and held and rose and knee.state == knee.State.CHASE and knee.anim.current_clip() in ["z_walk", "z_walk2", "z_walk3"],
		"  a leg hit drops it to a knee, held, then z_standup, then walking again (knelt %s, held %s, rose %s, now %s %s)" % [knelt, held, rose, knee.state, knee.anim.current_clip()])
	var knee2 = spawner.spawn_one("walker", Vector3(-17.5, 0.0, 14.0))
	await _frames(5)
	knee2.take_hit("lower_leg_r", knee2.max_health * 0.2, Vector3.FORWARD, null)
	knee2.set_legless(true)
	await _frames(int(knee2.KNEEL_TIME * 60.0) + 40)
	_check(knee2.state == knee2.State.CHASE and knee2.anim.current_clip() == "z_crawl", "  a legless one that was kneeling crawls on (%s)" % knee2.anim.current_clip())
	_check(knee.kneel_handoff_live and knee2.kneel_handoff_live, "  ...both hand the knee over to the next clip while z_hit_leg still plays, so it blends (stand-up %s, crawl %s)" % [knee.kneel_handoff_live, knee2.kneel_handoff_live])
	knee.free()
	knee2.free()

	# --- Crawlers and the far ones ---
	player.global_position = Vector3(-17.5, 0.0, -3.0)
	var crawler = spawner.spawn_one("walker", Vector3(-17.5, 0.0, 12.0))
	crawler.set_legless(true)
	await _frames(40)
	_check(crawler.legless and crawler.anim.current_clip() == "z_crawl", "  a legless zombie crawls (%s)" % crawler.anim.current_clip())
	crawler.free()
	var near_z = spawner.spawn_one("walker", Vector3(-17.5, 0.0, 4.0))
	var far_z = spawner.spawn_one("walker", Vector3(60.0, 0.0, 1.0))
	await _frames(30)
	var shadow_of := func(zz): return (zz.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).cast_shadow
	_check(shadow_of.call(near_z) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and shadow_of.call(far_z) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		and far_z._anim_player.callback_mode_process == AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		and near_z._anim_player.callback_mode_process == AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE,
		"  far zombies cast no shadow and animate every other frame; near ones do both")
	near_z.free()
	far_z.free()
	# The rot shader is on the body and the head.
	var shaded = spawner.spawn_one("walker", Vector3(0.0, 0.0, 30.0))
	var rot_surfaces := 0
	var total_surfaces := 0
	for mi in shaded.model.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			total_surfaces += 1
			var m := (mi as MeshInstance3D).get_surface_override_material(i)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("zombie_rot.gdshader"):
				rot_surfaces += 1
	_check(rot_surfaces >= 2 and rot_surfaces <= total_surfaces, "  the body and head wear the rot shader (%d of %d surfaces)" % [rot_surfaces, total_surfaces])
	shaded.free()
	await _zombie_fix1_checks(city, block, spawner, zm, player)
	for old in get_nodes_in_group("zombies"):
		old.free()
	zm.leave()
	DirAccess.remove_absolute(zm.PATH)
	root.get_node("Graphics").set_first_person(false)
	gs.start_run()
# --- Dead Block: fix round 1 (spawn hitches, round loop, stuck dead, attack ring) --
func _zombie_fix1_checks(city: Node3D, block: Node, spawner: Node, zm: Node, player: Node3D) -> void:
	await _section("Dead Block: spawn hitches, the round loop, stuck dead, the attack ring")
	var ZS: GDScript = load("res://npc/Zombie3D.gd")
	var CC := preload("res://npc/CharacterCast.gd")
	var Hit := preload("res://npc/ZombieHitboxes.gd")
	spawner.enabled = false
	spawner.time_scale = 1.0
	for old in get_nodes_in_group("zombies"):
		old.free()
	for old in get_nodes_in_group("corpses"):
		old.free()
	spawner._corpses.clear()
	var home := Vector3(-17.5, 0.0, -3.0)
	player.global_position = home
	player.velocity = Vector3.ZERO

	# --- Spawn hitches: nothing loads for the first time inside a round ---
	_check(city.get_node_or_null("ZombiePrewarm") == null and get_nodes_in_group("zombies").is_empty(),
		"  the prewarm's offscreen dead are gone again and never counted as alive")
	_check(block.get("prewarmed") == ZS.BODIES.size(), "  setup prewarmed all %d bodies (%s)" % [ZS.BODIES.size(), block.get("prewarmed")])
	# Cold caches (as on a first run): drop every body, the noise and the materials, let the block warm
	# them as its setup does, then each of the 20 bodies must spawn in under 25 ms.
	ZS._noise = null
	ZS._materials.clear()
	for b in ZS.BODIES:
		CC._scenes.erase(ZS.MODEL_DIR + b + ".glb")
	if block.has_method("prewarm_bodies"):
		block.prewarm_bodies()
	spawner.round_no = 2
	var worst_ms := 0.0
	var worst_body := ""
	for b in ZS.BODIES:
		var sz = spawner.spawn_one("walker", Vector3(0.0, 0.0, 30.0), b)
		var ms: float = spawner.last_spawn_usec / 1000.0
		if ms > worst_ms:
			worst_ms = ms
			worst_body = b
		sz.free()
	_check(worst_ms < 25.0, "  a zombie of any of the 20 bodies spawns in under 25 ms (worst %.1f ms, %s)" % [worst_ms, worst_body])

	# --- The round loop: all dead -> round_cleared -> next round spawns ---
	spawner.enabled = true
	spawner.time_scale = 0.01
	var cleared := []
	var on_cleared := func(r): cleared.append(r)
	spawner.round_cleared.connect(on_cleared)
	var round_seen := []
	var on_round := func(r): round_seen.append(r)
	zm.round_started.connect(on_round)
	zm.round = 0
	zm.start_round()
	var killed := 0
	var next_spawned := false
	for i in 3000:
		await physics_frame
		for zz in get_nodes_in_group("zombies"):
			zz.set_physics_process(false)
			if spawner.round_no == 1:
				zz.take_hit("torso", 1.0e6, Vector3.FORWARD, null)
				killed += 1
			elif spawner.round_no == 2:
				next_spawned = true
		if next_spawned:
			break
	spawner.enabled = false
	spawner.round_cleared.disconnect(on_cleared)
	zm.round_started.disconnect(on_round)
	_check(killed == zm.zombies_in_round(1) and cleared == [1] and round_seen == [1, 2] and zm.round == 2,
		"  the last dead of round 1 ends it: cleared %s, rounds started %s, killed %d of %d" % [cleared, round_seen, killed, zm.zombies_in_round(1)])
	_check(next_spawned and spawner.total == zm.zombies_in_round(2) and spawner.released >= 1,
		"  ...and round 2 sends its dead (owes %d, out %d)" % [spawner.total, spawner.released])
	for old in get_nodes_in_group("zombies"):
		old.free()
	for old in get_nodes_in_group("corpses"):
		old.free()
	spawner._corpses.clear()
	spawner.time_scale = 1.0

	# --- A tear still lands when the swing clip is short ---
	var bar: Node3D = block.barricades[0]
	bar.repair_all()
	await _frames(3)
	var bx: float = bar.global_position.x
	player.global_position = Vector3(bx, 0.0, -2.0)
	spawner.round_no = 3
	var tearer = spawner.spawn_one("walker", Vector3(bx, 0.0, bar.global_position.z - 2.4))
	var boards_before: int = bar.boards
	for i in 900:
		await physics_frame
		if tearer.state == tearer.State.TEAR and tearer._anim_player:
			# a clip a sixth of its length: the swing is over long before the board is due
			tearer._anim_player.speed_scale = 8.0
		if bar.boards < boards_before:
			break
	_check(bar.boards < boards_before, "  a board is torn even when the attack clip is shorter than 0.55 s (%d -> %d)" % [boards_before, bar.boards])
	tearer.free()
	bar.repair_all()

	# --- A torn plank put straight back stays up ---
	var bar2: Node3D = block.barricades[1]
	bar2.repair_all()
	await _frames(3)
	var idx: int = bar2.boards - 1
	var plank: Node3D = bar2._planks[idx]
	bar2.tear_board(null)
	var up_again: bool = bar2.repair_board(null, false)
	await create_timer(0.6).timeout
	var home_xf: Transform3D = bar2._home[idx]
	_check(up_again and bar2.boards == bar2.BOARD_COUNT and plank.transform.origin.distance_to(home_xf.origin) < 0.01,
		"  a plank nailed back right after a tear ends up in place, not on the ground (%.2f m off)" % plank.transform.origin.distance_to(home_xf.origin))

	# --- legless is a property ---
	var lz = spawner.spawn_one("walker", Vector3(0.0, 0.0, 30.0))
	var cap := lz._shape.shape as CapsuleShape3D
	lz.legless = true
	var legs_off: bool = (lz.hitboxes["lower_leg_l"] as Area3D).collision_layer == 0 and (lz.hitboxes["upper_leg_r"] as Area3D).collision_layer == 0
	var short: bool = cap.height < 1.0
	lz.legless = false
	_check(legs_off and short and cap.height > 1.6 and (lz.hitboxes["lower_leg_l"] as Area3D).collision_layer == Hit.HITBOX_LAYER,
		"  assigning legless shrinks the capsule and turns the leg zones off (and back on) (off %s, short %s)" % [legs_off, short])
	lz.free()

	# --- Boxed in, out of sight: put back on the map; in sight: left alone ---
	player.global_position = home
	player.velocity = Vector3.ZERO
	await _frames(40)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var behind := cam.global_position - fwd * 8.0
	behind.y = 0.0
	var ahead := cam.global_position + fwd * 6.0
	ahead.y = 0.0
	_check(not cam.is_position_in_frustum(behind + Vector3.UP) and cam.is_position_in_frustum(ahead + Vector3.UP) and not cam.is_position_behind(ahead + Vector3.UP),
		"  (the test's two spots: one out of the camera's view, one in front of it)")
	var boxes := []
	var boxed := {}
	for spot in [["behind", behind], ["ahead", ahead]]:
		var at: Vector3 = spot[1]
		var walls := Node3D.new()
		city.add_child(walls)
		for off in [Vector3(1.0, 0, 0), Vector3(-1.0, 0, 0), Vector3(0, 0, 1.0), Vector3(0, 0, -1.0)]:
			var w := StaticBody3D.new()
			w.collision_layer = 1
			var sh := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.3, 2.2, 2.3) if off.x != 0.0 else Vector3(2.3, 2.2, 0.3)
			sh.shape = bs
			w.add_child(sh)
			walls.add_child(w)
			w.global_position = at + off + Vector3(0, 1.1, 0)
		boxes.append(walls)
		var bz = spawner.spawn_one("walker", at)
		bz.set("stuck_limit", 1.0)
		boxed[spot[0]] = [bz, at]
	await create_timer(2.8).timeout
	var bz_behind = boxed["behind"][0]
	var bz_ahead = boxed["ahead"][0]
	var moved_behind: float = bz_behind.global_position.distance_to(boxed["behind"][1])
	var moved_ahead: float = bz_ahead.global_position.distance_to(boxed["ahead"][1])
	_check(moved_behind > 10.0 and bz_behind.global_position.distance_to(player.global_position) >= spawner.MIN_SPAWN_DISTANCE - 0.5,
		"  a dead one boxed in out of sight is put back on a spawn point (moved %.1f m, now %.0f m from the player)" % [moved_behind, bz_behind.global_position.distance_to(player.global_position)])
	_check(moved_ahead < 2.0, "  ...but one boxed in where the player can see it stays put (moved %.1f m)" % moved_ahead)
	for walls in boxes:
		walls.queue_free()
	bz_behind.free()
	bz_ahead.free()

	# --- 20 dead round the player: a ring, not a pile ---
	var ring_at := Vector3(-8.0, 0.0, -1.0)
	player.global_position = ring_at
	player.velocity = Vector3.ZERO
	spawner.round_no = 8
	# Twenty claws would put the player down long before the ring forms.
	root.get_node("ZombieMode").health = 1e9
	var horde := []
	for i in 20:
		var at := ring_at + Vector3(4.0 + (i % 5) * 1.0, 0.0, -1.5 + (i / 5) * 1.0)
		horde.append(spawner.spawn_one("runner" if i % 2 == 0 else "walker", at))
	var closest_pair := 99.0
	var closest_all := 99.0
	var attackers_seen := 0
	var pair_info := ""
	for f in 1500:
		await physics_frame
		if f >= 900 and f % 30 == 0:
			var near: Array = []
			for zz in horde:
				var d: float = Vector2(zz.global_position.x - ring_at.x, zz.global_position.z - ring_at.z).length()
				if d <= zz.ATTACK_RANGE + 0.35:
					near.append(zz)
			attackers_seen = maxi(attackers_seen, near.size())
			for a in near.size():
				for b in range(a + 1, near.size()):
					var pd: float = Vector2(near[a].global_position.x - near[b].global_position.x, near[a].global_position.z - near[b].global_position.z).length()
					if pd < closest_pair:
						closest_pair = pd
						pair_info = "slots %d/%d states %d/%d at (%.1f,%.1f) / (%.1f,%.1f)" % [near[a]._slot, near[b]._slot, near[a].state, near[b].state, near[a].global_position.x - ring_at.x, near[a].global_position.z - ring_at.z, near[b].global_position.x - ring_at.x, near[b].global_position.z - ring_at.z]
			for a in horde.size():
				for b in range(a + 1, horde.size()):
					closest_all = minf(closest_all, Vector2(horde[a].global_position.x - horde[b].global_position.x, horde[a].global_position.z - horde[b].global_position.z).length())
	root.get_node("ZombieMode").health = 100.0
	_check(attackers_seen >= 8, "  the horde closes on the player (%d within claw reach)" % attackers_seen)
	_check(closest_pair >= 0.4, "  no two dead within reach are closer than 0.4 m (a pile is under 0.3; the ring keeps 0.6) (closest %.2f m; any two of the 20: %.2f m; %s)" % [closest_pair, closest_all, pair_info])
	for zz in horde:
		zz.free()
# --- Dead Block: guns, wall-buys, the box, the upgrade machine (Task Z3) -----------

## Shots to kill a round-1 zombie (150 health) at 4 m: [torso, head].
const ZW_SHOTS := {"pistol": [4, 1], "smg": [6, 2], "shotgun": [1, 1], "ar": [4, 1], "sniper": [1, 1],
	"magnum": [2, 1], "lmg": [4, 2], "wonder": [1, 1]}
## The wall's prices (spec): the guns it sells.
const ZW_PRICES := {"smg": 1000, "shotgun": 1200, "ar": 1400, "sniper": 1500, "magnum": 1000}

## A real Zombie3D (the block's spawner makes it) `dist` m east of (x, z) on the
## street: held still (no brain), posed (animation paused), facing west, toward the
## shooter. It logs its hits in meta "hits" ([part, damage]).
func _zw_target(parent: Node, x: float, z: float, dist: float, rnd := 1) -> Node:
	var sp: Node = parent.get_node("ZombieBlock").spawner
	sp.enabled = false
	sp.round_no = rnd
	var zed: Node = sp.spawn_one("walker", Vector3(x + dist, 0.0, z))
	zed.set_physics_process(false)
	zed._anim_player.pause()
	# A zombie starts its walk at a random point; the targets stand at the same one, so a
	# sweep for gaps always meets the same pose (a head leaning off the torso's line is a gap).
	zed._anim_player.seek(0.0, true)
	zed._model_root.rotation.y = -PI / 2.0
	zed.set_meta("hits", [])
	zed.hit.connect(func(_z, part, dmg, _k): zed.get_meta("hits").append([part, dmg]))
	# The hit zones ride the skeleton: they are in the physics space a step later.
	await physics_frame
	await physics_frame
	await process_frame
	await physics_frame
	return zed

## The world height of a bone of the zombie's skeleton.
func _zw_bone_y(zed: Node, bone: String) -> float:
	var sk: Skeleton3D = zed._skeleton
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin.y

func _zw_hits(zed: Node) -> Array:
	return zed.get_meta("hits")

## Where the middle of one of the zombie's hit zones is now.
func _zw_part_at(zed: Node, part: String) -> Vector3:
	zed.sync_hitboxes()
	return (zed.hitboxes[part].get_child(0) as Node3D).global_position

## Aim along +X at the middle of `part`, from x = `from_x` (looked up on every shot,
## so it follows the pose).
func _zw_aim_part(holder: Node, zed: Node, part: String, from_x := -20.0) -> void:
	holder.aim_source = func():
		var c := _zw_part_at(zed, part)
		return [Vector3(from_x, c.y, c.z), Vector3.RIGHT]

func _zw_aim(holder: Node, x: float, y: float, z: float) -> void:
	holder.aim_source = func(): return [Vector3(x, y, z), Vector3.RIGHT]

## Fires `data` at `part` of a fresh round-1 zombie until it is dead; returns
## the shots it took (or -1).
func _zw_shots_to_kill(holder: Node, data: Resource, city: Node, part: String) -> int:
	holder.give(data)
	holder.no_spread = true
	var zed: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, zed, part)
	var shots := 0
	while zed.is_alive() and shots < 40:
		holder.advance(10.0)
		holder.refill_current()
		holder.fire()
		shots += 1
	var dead: bool = not zed.is_alive()
	zed.queue_free()
	return shots if dead else -1

## Every action's events as text ("event@device"), sorted: the story's controls, to compare.
func _zw_bindings() -> Dictionary:
	var out := {}
	for a in InputMap.get_actions():
		var evs: Array = []
		for ev in InputMap.action_get_events(a):
			evs.append("%s@%d" % [ev.as_text(), ev.device])
		evs.sort()
		out[String(a)] = evs
	return out

## The pad Square / Cross events.
func _zw_pad_button(button: int, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	return ev

func _zw_mouse(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev

## Rays along `dir` at the given heights and sideways offsets (round the zone
## `around`'s middle) that find no zombie at all: [y, offset] pairs.
func _zw_gaps(holder: Node, zed: Node, heights: Array, offsets: Array, along_x: bool) -> Array:
	var mid := _zw_part_at(zed, "torso")
	var neck := _zw_part_at(zed, "neck")
	var head := _zw_part_at(zed, "head")
	var gaps := []
	for y in heights:
		# The spine leans on some bodies and poses: the core line follows the torso, neck and head
		# centres (straight lines between them), not a plumb line through the torso.
		var lean_n: float = (neck.z - mid.z) if along_x else (neck.x - mid.x)
		var lean_h: float = (head.z - mid.z) if along_x else (head.x - mid.x)
		var lean := 0.0
		if y >= head.y:
			lean = lean_h
		elif y >= neck.y:
			lean = lerpf(lean_n, lean_h, (y - neck.y) / maxf(head.y - neck.y, 0.01))
		elif y > mid.y:
			lean = lerpf(0.0, lean_n, (y - mid.y) / maxf(neck.y - mid.y, 0.01))
		for o in offsets:
			if y >= head.y - 0.07 and absf(o) > 0.021:
				continue  # the head is small and tilts: up there only its middle line counts
			var origin := Vector3(mid.x - 4.0, y, mid.z + o + lean) if along_x else Vector3(mid.x + o + lean, y, mid.z - 4.0)
			var r: Dictionary = holder._cast(origin, Vector3.RIGHT if along_x else Vector3(0, 0, 1), 8.0)
			if r.get("zombie") == null:
				gaps.append([snappedf(y, 0.01), snappedf(o, 0.01)])
	return gaps

func _zombie_weapons_checks(gs: Node) -> void:
	await _section("Dead Block: guns by part, ammo and reload, points, wall-buys, the box, the upgrade machine")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var WD := load("res://weapons/WeaponData.gd")
	var HolderScript := load("res://player/WeaponHolder.gd")
	# The story's own controls, to compare with after the mode is left.
	zm.leave()
	var story_binds := _zw_bindings()

	# The data.
	var ids := ["pistol", "smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]
	var all_ok := true
	for id in ids:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var u: Resource = d.upgrade if d else null
		all_ok = all_ok and d != null and u != null and u.upgraded and u.base_id == id and u.family() == id and d.family() == id \
			and u.damage > d.damage and u.mag_size > d.mag_size and u.reserve_max > d.reserve_max and u.display_name != d.display_name \
			and u.tint.a > 0.0 and (d.model == "" or FileAccess.file_exists(d.model))
	_check(all_ok, "  all 8 guns have an upgraded version: more damage, mag and reserve, a new name and look")
	_check(load("res://weapons/knife.tres").melee and not load("res://weapons/knife.tres").in_box, "  the knife is its own melee data, not in the box")
	var prices_ok := true
	for id in ZW_PRICES:
		var d: Resource = load("res://weapons/%s.tres" % id)
		prices_ok = prices_ok and d.price == ZW_PRICES[id] and d.ammo_price == ZW_PRICES[id] / 2
	_check(prices_ok, "  wall prices are the spec's (SMG 1000, shotgun 1200, AR 1400, sniper 1500, magnum 1000), ammo half")
	var pd: Resource = load("res://weapons/pistol.tres")
	_check(pd.damage_at("head") == pd.damage * pd.head_mult and pd.damage_at("torso") == pd.damage and pd.damage_at("upper_leg_l") == pd.damage * pd.limb_mult
		and pd.damage_at("neck") == pd.damage * pd.neck_mult and pd.damage_at("head", 500.0) < pd.damage_at("head"),
		"  damage by part: head, neck, torso, limbs, and less at long range")
	var sg: Resource = load("res://weapons/shotgun.tres")
	_check(sg.pellets > 1 and sg.damage_at("torso", 4.0) > sg.damage_at("torso", 14.0) * 2.0, "  the shotgun throws pellets and loses most of them at range")

	# Into the block.
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	var block: Node = city.get_node_or_null("ZombieBlock")
	for i in 90:
		if block != null and block.purchases_ready:
			break
		await physics_frame
	await _frames(5)
	# Round 1 has started by itself: park it, the checks bring their own dead.
	block.spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player := _player()
	var holder: Node = player.get_node_or_null("WeaponHolder")
	_check(block != null and holder != null and block.purchases_ready, "  the block arms the player and builds its purchases")
	if holder == null or not block.purchases_ready:
		zm.leave()
		return
	_check(holder.current != null and holder.current.id == "pistol" and holder.mag == 8 and holder.reserve == 80,
		"  you start with the pistol, 8 in the mag and 80 in reserve")
	player.global_position = Vector3(-30, 0, -3)

	# Controls: Call of Duty's layout, no button doing two jobs.
	var lmb := _zw_mouse(MOUSE_BUTTON_LEFT)
	var r2 := InputEventJoypadMotion.new()
	r2.axis = JOY_AXIS_TRIGGER_RIGHT
	r2.axis_value = 1.0
	_check(InputMap.event_is_action(lmb, "fire") and InputMap.event_is_action(r2, "fire"), "  the left mouse button and R2 fire")
	_check(InputMap.event_is_action(_zw_mouse(MOUSE_BUTTON_RIGHT), "aim") and InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_RIGHT_STICK, true), "melee"),
		"  the right mouse button aims, R3 is the knife")
	var shared: Array = []
	var zacts := ["fire", "aim", "interact", "reload", "swap_weapon", "melee", "walkman", "weapon_slot_1", "weapon_slot_2"]
	for i in zacts.size():
		for j in range(i + 1, zacts.size()):
			for e1 in InputMap.action_get_events(zacts[i]):
				for e2 in InputMap.action_get_events(zacts[j]):
					if e1.is_match(e2, true):
						shared.append("%s/%s: %s" % [zacts[i], zacts[j], e1.as_text()])
	_check(shared.is_empty(), "  no button is bound to two of fire, aim, use, reload, swap, knife, tapes (%s)" % [shared])
	var all_devices := true
	for a in zacts + ["walkman_next"]:
		for ev in InputMap.action_get_events(a):
			all_devices = all_devices and ev.device == -1
	_check(all_devices, "  every binding is for any device (-1), not pad 0 only")
	_check(InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_X, true), "reload") and InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_Y, true), "swap_weapon")
		and not InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_A, true), "fire") and not InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_X, true), "interact")
		and not InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_Y, true), "walkman"),
		"  pad: Square reloads, Triangle swaps; Cross doesn't fire, Square isn't use, Triangle isn't the tapes")
	_check(InputMap.event_is_action(_zw_mouse(MOUSE_BUTTON_WHEEL_UP), "swap_weapon") and InputMap.action_get_events("weapon_slot_1").size() == 1
		and InputMap.action_get_events("interact").size() == 1, "  the wheel swaps, 1 and 2 pick a slot, E uses")
	# The buttons act, through events.
	holder.give(load("res://weapons/pistol.tres"))
	holder.give(load("res://weapons/smg.tres"))
	holder._unhandled_input(_key_action("weapon_slot_1"))
	_check(holder.current.id == "pistol", "  1 picks the first gun")
	holder._unhandled_input(_key_action("weapon_slot_2"))
	_check(holder.current.id == "smg", "  2 picks the second")
	holder._unhandled_input(_zw_mouse(MOUSE_BUTTON_WHEEL_DOWN))
	_check(holder.current.id == "pistol", "  a turn of the wheel swaps")
	holder.give(load("res://weapons/pistol.tres"))
	holder.mag = 3
	holder._unhandled_input(_key_action("reload"))
	_check(holder.reloading, "  R reloads")
	holder.advance(10.0)
	holder.mag = 3
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, true))
	_check(holder.reloading, "  away from anything to buy, Square reloads at once")
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, false))
	holder.advance(10.0)

	# Damage by part kills a round-1 zombie in the expected shots, through real raycasts.
	for id in ids:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var body := await _zw_shots_to_kill(holder, d, city, "torso")
		var head := await _zw_shots_to_kill(holder, d, city, "head")
		_check(body == ZW_SHOTS[id][0] and head == ZW_SHOTS[id][1], "  %s: a round-1 zombie takes %d to the body and %d to the head (%d, %d)" % [id, ZW_SHOTS[id][0], ZW_SHOTS[id][1], body, head])
	var up_shots := await _zw_shots_to_kill(holder, load("res://weapons/pistol_up.tres"), city, "torso")
	_check(up_shots == 2, "  the upgraded pistol needs 2 to the body, not 4 (%d)" % up_shots)

	# A real round-1 Zombie3D (the spawner's own, with its bone-riding hit zones) and the pistol's head multiplier.
	var pistol: Resource = load("res://weapons/pistol.tres")
	holder.give(pistol)
	holder.no_spread = true
	zm.points = 0
	var kills0: int = zm.kills
	var heads0: int = zm.headshots
	var zr: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_check(zr.get_script().resource_path == "res://npc/Zombie3D.gd" and zr.max_health == 150.0 and zr.hitboxes.size() == 11,
		"  the target is a real Zombie3D with 150 health and 11 hit zones")
	_zw_aim_part(holder, zr, "head")
	var head_dmg: float = pistol.damage_at("head", 4.0)
	zr.health = 300.0
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(zr).size() == 1 and _zw_hits(zr)[0][0] == "head" and is_equal_approx(_zw_hits(zr)[0][1], head_dmg) and head_dmg > pistol.damage_at("torso", 4.0) * 1.9
		and is_equal_approx(zr.health, 300.0 - head_dmg),
		"  the first pistol shot lands in the head for the head multiplier (%s, %.0f of 300)" % [_zw_hits(zr), 300.0 - zr.health])
	holder.advance(10.0)
	holder.fire()
	_check(not zr.is_alive() and _zw_hits(zr).size() == 2, "  a round-1 zombie is dead after 2 pistol headshots (%d hits)" % _zw_hits(zr).size())
	_check(zm.kills - kills0 == 1 and zm.headshots - heads0 == 1 and zm.points == 10 + 100,
		"  the kill is counted once (the spawner's), as a headshot, and pays 10 + 100 (kills +%d, heads +%d, %d points)" % [zm.kills - kills0, zm.headshots - heads0, zm.points])
	zr.queue_free()
	zm.points = 0

	# The hit zones cover the body: rays over its silhouette find no gap, and the
	# neck is a zone of its own on the neck, between the torso and the head.
	var zbody: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	var y_torso: float = _zw_part_at(zbody, "torso").y
	var y_neck: float = _zw_part_at(zbody, "neck").y
	var y_head: float = _zw_part_at(zbody, "head").y
	var neck_lo: float = _zw_bone_y(zbody, "Bip01 Neck")
	var neck_hi: float = _zw_bone_y(zbody, "Bip01 Head")
	_check(y_neck >= neck_lo - 0.01 and y_neck <= neck_hi + 0.01, "  the neck zone sits on the neck, between the Neck and Head bones (%.2f in %.2f..%.2f)" % [y_neck, neck_lo, neck_hi])
	var heights := []
	var yy := y_torso - 0.2
	while yy <= y_head + 0.05:
		heights.append(yy)
		yy += 0.02
	var core := []
	var off := -0.04
	while off <= 0.0401:
		core.append(off)
		off += 0.02
	var shoulders := []
	off = -0.16
	while off <= 0.1601:
		shoulders.append(off)
		off += 0.02
	var shoulder_heights := heights.filter(func(h): return h <= y_neck - 0.06)
	var gaps_front: Array = _zw_gaps(holder, zbody, heights, core, true)
	var gaps_side: Array = _zw_gaps(holder, zbody, heights, core, false)
	var gaps_shoulder: Array = _zw_gaps(holder, zbody, shoulder_heights, shoulders, true)
	_check(gaps_front.is_empty() and gaps_side.is_empty(), "  no gap over the body's core from belly to crown, front or side (%s %s; body %s)" % [gaps_front.slice(0, 4), gaps_side.slice(0, 4), zbody.get_meta("body", "?")])
	_check(gaps_shoulder.is_empty(), "  no gap across the shoulders (%s)" % [gaps_shoulder.slice(0, 4)])
	var order := []
	for h in heights:
		var r: Dictionary = holder._cast(Vector3(-24.0, h, _zw_part_at(zbody, "torso").z), Vector3.RIGHT, 8.0)
		var part: String = r.get("part", "")
		if part != "" and (order.is_empty() or order.back() != part):
			order.append(part)
	_check(order.has("neck") and order.find("torso") < order.find("neck") and order.find("neck") < order.find("head"),
		"  up the centre line the rays meet the torso, then the neck, then the head (%s)" % [order])
	zbody.queue_free()

	# A shotgun at point blank spreads over several parts and still pays once per shot.
	holder.give(load("res://weapons/shotgun.tres"))
	holder.no_spread = false
	var zsp: Node = await _zw_target(city, -20.0, -3.0, 2.0, 40)
	zsp.health = 1.0e6
	zsp.max_health = 1.0e6
	_zw_aim_part(holder, zsp, "neck", -20.0)
	var parts_seen := {}
	var paid_ok := true
	var shots_landed := 0
	for i in 8:
		var before: int = zm.points
		var n0: int = _zw_hits(zsp).size()
		holder.advance(10.0)
		holder.refill_current()
		holder.fire()
		var landed: int = _zw_hits(zsp).size() - n0
		for h in _zw_hits(zsp).slice(n0):
			parts_seen[h[0]] = true
		if landed > 0:
			shots_landed += 1
		paid_ok = paid_ok and zm.points - before == (10 if landed > 0 else 0)
	_check(shots_landed >= 4 and parts_seen.size() >= 2 and paid_ok,
		"  shotgun pellets hit %d parts (%s) over %d shots and each shot paid 10 once, %d in all" % [parts_seen.size(), parts_seen.keys(), shots_landed, zm.points])
	holder.no_spread = true
	zsp.queue_free()
	zm.points = 0

	# Parts and what's in the way.
	holder.give(load("res://weapons/pistol.tres"))
	holder.no_spread = true
	var z1: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, z1, "lower_leg_l")
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(z1).size() == 1 and _zw_hits(z1)[0][0] == "lower_leg_l" and absf(_zw_hits(z1)[0][1] - 40.0 * holder.current.limb_mult) < 0.01,
		"  a shot at the shin hits the lower leg for the limb share (%s)" % [_zw_hits(z1)])
	z1.queue_free()
	var wall_z: Node = await _zw_target(city, -16.0, -6.0, 0.0)
	holder.aim_source = func(): return [Vector3(-16.0, 1.1, -3.0), Vector3(0, 0, -1)]
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(wall_z).is_empty(), "  a zombie behind a wall can't be shot through it")
	wall_z.queue_free()
	var front: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	var back: Node = await _zw_target(city, -20.0, -3.0, 6.0)
	_zw_aim_part(holder, front, "torso")
	front.health = 1.0
	holder.advance(10.0)
	holder.fire()
	_check(not front.is_alive() and _zw_hits(back).is_empty(), "  a bullet stops at the first zombie")
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(back).size() == 1, "  with the first one down (its zones switched off), the next in line is hit")
	front.queue_free()
	back.queue_free()

	# Ammo, mag, reserve, reload.
	holder.give(load("res://weapons/ar.tres"))
	holder.no_spread = true
	_zw_aim(holder, -20.0, 5.0, -3.0)
	_check(holder.mag == 30 and holder.reserve == 150, "  the AR comes with 30 + 150")
	holder.advance(10.0)
	_check(holder.fire() and holder.mag == 29, "  a shot takes one round")
	_check(not holder.fire() and holder.mag == 29, "  but not before the gun has cycled (rate of fire)")
	holder.advance(60.0 / 660.0 + 0.01)
	_check(holder.fire() and holder.mag == 28, "  after one interval the next shot goes")
	var fired_n := [0]
	holder.fired.connect(func(): fired_n[0] += 1)
	holder.advance(1.0)
	holder.fire()
	_check(fired_n[0] == 1, "  the fired signal comes with each shot")
	_check(holder.reload() and holder.reloading and not holder.fire(), "  reloading starts, and you can't shoot meanwhile")
	holder.advance(holder.current.reload_time - 0.3)
	_check(holder.reloading and holder.mag == 27, "  still reloading just before the time is up")
	holder.advance(0.4)
	_check(not holder.reloading and holder.mag == 30 and holder.reserve == 147, "  done: a full mag, the three rounds out of reserve (%d + %d)" % [holder.mag, holder.reserve])
	_check(not holder.reload(), "  a full mag doesn't reload")
	holder.mag = 0
	holder.reserve = 2
	holder.advance(1.0)
	_check(not holder.fire() and holder.reloading, "  an empty mag won't fire, and starts the reload")
	holder.advance(10.0)
	_check(holder.mag == 2 and holder.reserve == 0, "  a short reserve loads what there is")
	holder.mag = 0
	_check(not holder.reload() and not holder.fire(), "  no reserve, no reload, no shot")
	holder.refill_current()
	holder.mag = 10
	holder.reload_mult = 0.5
	holder.reload()
	holder.advance(holder.current.reload_time * 0.5 + 0.01)
	_check(not holder.reloading, "  a reload multiplier (Quickhands) shortens the reload")
	holder.reload_mult = 1.0
	holder.refill_current()
	var emptied := load("res://weapons/magnum.tres")
	holder.give(emptied)
	holder.mag = 1
	holder.advance(10.0)
	holder.fire()
	_check(holder.mag == 0, "  the magnum fires its last round")

	# Slots and swapping.
	holder.slots = [null, null]
	holder.give(load("res://weapons/pistol.tres"))
	holder.give(load("res://weapons/smg.tres"))
	_check(holder.slot_data(0) != null and holder.slot_data(1) != null and holder.current.id == "smg", "  a second gun goes in the free slot and into your hands")
	holder.mag = 12
	_check(holder.swap() and holder.current.id != "smg" and holder.swap() and holder.current.id == "smg" and holder.mag == 12, "  swap goes between the two and keeps each gun's mag")
	holder.give(load("res://weapons/shotgun.tres"))
	_check(holder.has_weapon("shotgun") and holder.has_weapon("pistol") and not holder.has_weapon("smg"), "  a third gun replaces the one in your hands")
	holder.give(load("res://weapons/shotgun_up.tres"))
	_check(holder.has_weapon("shotgun") and holder.current.upgraded and holder.slots.filter(func(s): return s != null).size() == 2, "  a gun you carry is never doubled up")
	holder.give(load("res://weapons/pistol.tres"))
	holder.give(load("res://weapons/pistol.tres"))
	var solo = HolderScript.new()
	_check(not solo.swap(), "  with one gun there is nothing to swap to")
	solo.free()

	# Points: a hit, a kill, a headshot, a neck, a knife, a shotgun blast.
	zm.points = 0
	holder.give(load("res://weapons/pistol.tres"))
	holder.no_spread = true
	var hit_log := []
	holder.hit.connect(func(part: String, killed: bool): hit_log.append([part, killed]))
	var zh: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, zh, "head")
	zh.health = 300.0
	holder.advance(10.0)
	holder.fire()
	_check(zm.points == 10 and zh.is_alive() and hit_log == [["head", false]], "  a hit that doesn't kill pays 10 and says so (%d, %s)" % [zm.points, hit_log])
	holder.advance(10.0)
	holder.fire()
	_check(not zh.is_alive() and zm.points == 110 and hit_log.back() == ["head", true], "  the killing headshot pays 100 (not 100 + 10): %d" % zm.points)
	zh.queue_free()
	zm.points = 0
	var zb: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, zb, "torso")
	for i in 4:
		holder.advance(10.0)
		holder.fire()
	_check(not zb.is_alive() and zm.points == 3 * 10 + 60, "  three hits and a body kill pay 3 x 10 + 60 (%d)" % zm.points)
	zb.queue_free()
	zm.points = 0
	holder.give(load("res://weapons/magnum.tres"))
	var zn: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, zn, "neck")
	holder.advance(10.0)
	holder.fire()
	_check(not zn.is_alive() and zn.last_part == "neck" and zm.points == 70, "  a neck kill pays 70 (%d, %s)" % [zm.points, zn.last_part])
	zn.queue_free()
	zm.points = 0
	holder.give(load("res://weapons/shotgun.tres"))
	var zs: Node = await _zw_target(city, -20.0, -3.0, 4.0, 5)
	_zw_aim_part(holder, zs, "torso")
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(zs).size() == 8 and zs.is_alive() and zm.points == 10, "  a shotgun blast lands 8 pellets and pays one hit, 10 (%d pellets, %d)" % [_zw_hits(zs).size(), zm.points])
	zs.queue_free()
	zm.points = 0
	var zs1: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	_zw_aim_part(holder, zs1, "torso")
	holder.advance(10.0)
	holder.refill_current()
	holder.fire()
	_check(not zs1.is_alive() and zm.points == 60, "  a blast that kills pays the kill once, 60 (%d)" % zm.points)
	zs1.queue_free()
	zm.points = 0
	zm.double_points = true
	holder.give(load("res://weapons/pistol.tres"))
	var zd: Node = await _zw_target(city, -20.0, -3.0, 4.0, 5)
	_zw_aim_part(holder, zd, "torso")
	holder.advance(10.0)
	holder.fire()
	_check(zm.points == 20, "  Double Points doubles a hit's 10 (%d)" % zm.points)
	zm.double_points = false
	zm.insta_kill = true
	holder.advance(10.0)
	holder.fire()
	_check(not zd.is_alive(), "  Insta-Kill: one hit kills even a round-5 zombie")
	zm.insta_kill = false
	zd.queue_free()
	zm.points = 0
	var zk: Node = await _zw_target(city, -20.0, -3.0, 1.0)
	_zw_aim_part(holder, zk, "torso")
	_check(holder.melee() and not zk.is_alive() and zm.points == 130, "  a knife kill pays 130 (%d)" % zm.points)
	_check(not holder.melee(), "  the knife has a cooldown")
	zk.queue_free()
	var zfar: Node = await _zw_target(city, -20.0, -3.0, 6.0)
	_zw_aim_part(holder, zfar, "torso")
	holder.advance(10.0)
	holder.melee()
	_check(_zw_hits(zfar).is_empty(), "  the knife only reaches what's right in front of you")
	zfar.queue_free()
	zm.points = 0
	holder.advance(10.0)
	zm.active = false
	zm.add_points(100, "test")
	zm.active = true
	_check(zm.points == 0, "  points are only awarded while a run is on (add_points ignores the rest)")

	# From the player's own view: first person aims through the screen centre.
	var gfx := root.get_node("Graphics")
	gfx.set_first_person(true)
	await _frames(4)
	_check(holder.viewmodel != null and holder.viewmodel.get_parent() == player.camera, "  in first person the gun is on the camera")
	player.global_position = Vector3(-20, 0, -3)
	player.set_look(-PI / 2.0, 0.02)
	await _frames(3)
	await process_frame
	holder.give(load("res://weapons/ar.tres"))
	holder.aim_source = Callable()
	holder.no_spread = true
	var zf: Node = await _zw_target(city, -20.0, -3.0, 5.0, 3)
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(zf).size() == 1 and (_zw_hits(zf)[0][0] == "head" or _zw_hits(zf)[0][0] == "neck"), "  first person: the shot goes where the crosshair points (%s)" % [_zw_hits(zf)])
	zf.queue_free()
	gfx.set_first_person(false)
	await _frames(4)
	_check(holder.viewmodel == null, "  back in third person the camera carries no gun")

	# Third person: from the chest to what the active camera sees under the crosshair.
	player.global_position = Vector3(-20, 0, -3)
	await _frames(10)
	var cam: Camera3D = player.camera
	var pistol3: Resource = load("res://weapons/pistol.tres")
	holder.give(pistol3)
	holder.aim_source = Callable()
	holder.no_spread = true
	zm.points = 0
	var ztp: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	holder.screen_aim_source = func(): return cam.unproject_position(_zw_part_at(ztp, "head"))
	ztp.health = 300.0
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(ztp).size() == 1 and _zw_hits(ztp)[0][0] == "head" and _zw_hits(ztp)[0][1] > pistol3.damage_at("torso", 4.0) * 1.9,
		"  third person: aiming the crosshair at the head hits it for the head multiplier (%s)" % [_zw_hits(ztp)])
	holder.advance(10.0)
	holder.fire()
	_check(not ztp.is_alive() and zm.points == 110, "  ...and a third-person headshot kill pays 100 (+10 for the first): %d" % zm.points)
	ztp.queue_free()
	var zneck: Node = await _zw_target(city, -20.0, -3.0, 4.0)
	holder.screen_aim_source = func(): return cam.unproject_position(_zw_part_at(zneck, "torso"))
	holder.advance(10.0)
	holder.fire()
	_check(_zw_hits(zneck).size() == 1 and _zw_hits(zneck)[0][0] == "torso", "  ...and where the crosshair is on the torso, the torso (%s)" % [_zw_hits(zneck)])
	# The pad has no pointer: its crosshair is 6 m ahead of the chest, whatever the mouse did.
	holder.screen_aim_source = Callable()
	gs.using_pad = true
	var ahead: Vector2 = cam.unproject_position(player.global_position + Vector3(0, 1.25, 0) + holder._facing() * 6.0)
	_check(holder.aim_screen_point().is_equal_approx(ahead), "  with the pad the crosshair is ahead of the player, not at the stale mouse (%s)" % [holder.aim_screen_point()])
	gs.using_pad = false
	_check(holder.aim_screen_point().is_equal_approx(root.get_mouse_position()), "  with the mouse it is under the mouse")
	zneck.queue_free()

	# Wall-buys.
	_check(block.wall_buys.size() == 5, "  five wall guns on the block (%d)" % block.wall_buys.size())
	var wall_ok := true
	for buy in block.wall_buys:
		var o: Vector3 = buy.global_position
		# On a wall: a ray from the board straight back at it meets one close behind.
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, 1.3, 0) + buy.global_transform.basis.z * 0.5, o + Vector3(0, 1.3, 0) - buy.global_transform.basis.z * 0.6)
		var r := space.intersect_ray(q)
		var good: bool = not r.is_empty() and r.position.distance_to(o + Vector3(0, 1.3, 0)) < 0.2
		if not good:
			print("   board ", buy.name, " at ", o, " ray ", r)
		wall_ok = wall_ok and good
	_check(wall_ok, "  every board hangs against a wall")
	var buy_ids: Array = block.wall_buys.map(func(b): return b.data.id)
	buy_ids.sort()
	_check(buy_ids == ["ar", "magnum", "shotgun", "smg", "sniper"], "  they sell the AR, magnum, shotgun, SMG and sniper (%s)" % [buy_ids])
	holder.give(load("res://weapons/pistol.tres"))
	var smg_buy: Node = block.wall_buys.filter(func(b): return b.data.id == "smg")[0]
	zm.points = 999
	_check(smg_buy.try_buy(holder) == "poor" and zm.points == 999 and not holder.has_weapon("smg"), "  one point short of the SMG: nothing bought, nothing taken (%d)" % zm.points)
	zm.points = 1000
	_check(smg_buy.try_buy(holder) == "bought" and zm.points == 0 and holder.current.id == "smg", "  exactly enough: the SMG is yours and you have 0, not less")
	_check(smg_buy.try_buy(holder) == "full" and zm.points == 0, "  a full SMG doesn't buy ammo, and costs nothing")
	holder.mag = 3
	holder.reserve = 7
	zm.points = 499
	_check(smg_buy.try_buy(holder) == "poor" and holder.reserve == 7 and zm.points == 499, "  one short of half price (500): no ammo")
	zm.points = 500
	_check(smg_buy.try_buy(holder) == "ammo" and zm.points == 0 and holder.mag == 30 and holder.reserve == 150, "  the SMG's ammo is 500, half: a full mag and reserve")
	zm.double_points = true
	var shotgun_buy: Node = block.wall_buys.filter(func(b): return b.data.id == "shotgun")[0]
	zm.points = 1199
	_check(shotgun_buy.try_buy(holder) == "poor" and zm.points == 1199, "  under Double Points the price is the same: 1199 is still short of 1200")
	zm.points = 1200
	_check(shotgun_buy.try_buy(holder) == "bought" and zm.points == 0, "  ...and 1200 still buys it (not 2400, not a gain)")
	zm.double_points = false
	zm.points = 0
	var all_nonneg := true
	for buy in block.wall_buys:
		buy.try_buy(holder)
		all_nonneg = all_nonneg and zm.points >= 0
	_check(all_nonneg and zm.points == 0, "  with 0 points nothing can be bought and points never go negative")
	# Through the real E key.
	var ar_buy: Node = block.wall_buys.filter(func(b): return b.data.id == "ar")[0]
	holder.give(load("res://weapons/pistol.tres"))
	player.global_position = ar_buy.global_position + ar_buy.global_transform.basis.z * 0.9
	await _frames(6)
	zm.points = 1400
	_check(player._nearest_interactable() == ar_buy and ar_buy.prompt_text().contains("1400"), "  next to a board E finds it and the prompt names the price (%s)" % ar_buy.prompt_text())
	player._unhandled_input(_key_action("interact"))
	_check(holder.has_weapon("ar") and zm.points == 0, "  pressing E buys the gun")
	_check(ar_buy.prompt_text().contains("Refill") and ar_buy.prompt_text().contains("700"), "  once you carry it the board offers its ammo at 700 (%s)" % ar_buy.prompt_text())
	# The pad's Square is reload and use: a tap at a board reloads, a hold buys.
	holder.reserve = 5
	holder.mag = 2
	zm.points = 700
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, true))
	holder.advance(0.1)
	_check(zm.points == 700 and not holder.reloading, "  Square at a board does nothing yet (a tap or a hold: 0.1 s in)")
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, false))
	_check(holder.reloading and zm.points == 700, "  a tap of Square at a board reloads and buys nothing")
	holder.advance(10.0)
	holder.reserve = 5
	holder.mag = 2
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, true))
	holder.advance(0.6)
	_check(zm.points == 0 and holder.reserve == holder.current.reserve_max, "  holding Square at a board buys its ammo (%d points, %d reserve)" % [zm.points, holder.reserve])
	holder._unhandled_input(_zw_pad_button(JOY_BUTTON_X, false))
	_check(not holder.reloading, "  ...and letting go afterwards doesn't reload")

	# The mystery box.
	var box: Node = block.mystery_box
	holder.give(load("res://weapons/pistol.tres"))
	holder.give(load("res://weapons/smg.tres"))
	var pool_ids: Array = box.pool().map(func(d): return d.id)
	pool_ids.sort()
	_check(pool_ids == ["ar", "lmg", "magnum", "shotgun", "smg", "sniper", "wonder"], "  the box's pool is every gun but the pistol, with the LMG and the wonder weapon (%s)" % [pool_ids])
	zm.points = 949
	_check(box.try_open(holder) == "poor" and zm.points == 949 and box.state == box.State.IDLE, "  one short of 950: the box stays shut and takes nothing")
	zm.points = 950
	zm.double_points = true
	_check(box.try_open(holder) == "opened" and zm.points == 0, "  950 opens it under Double Points too, leaving 0")
	zm.double_points = false
	zm.points = 950
	_check(box.try_open(holder) == "busy" and zm.points == 950, "  while it spins a second go is refused and free")
	box.advance(box.SPIN_TIME + 0.1)
	_check(box.state == box.State.OFFER and box.offered != null and not holder.held_families().has(box.offered.family()), "  it holds out a gun you don't have (%s)" % [box.offered.id if box.offered else "-"])
	var offered_id: String = box.offered.family()
	_check(box.try_take(holder) == "taken" and holder.has_weapon(offered_id) and holder.current.family() == offered_id, "  taking it puts it in your hands")
	_check(box.try_take(holder) == "none", "  nothing is held out afterwards")
	# What it holds out is checked again when you take it.
	holder.give(load("res://weapons/pistol.tres"))
	zm.points = 950
	box.state = box.State.IDLE
	box.uses = 0
	box.move_after = 99
	box.try_open(holder)
	box.advance(box.SPIN_TIME + 0.1)
	var held_out: String = box.offered.family()
	holder.give(load("res://weapons/%s.tres" % held_out))
	holder.upgrade_current()
	var up_id: String = holder.current.id
	_check(box.try_take(holder) == "changed" and box.offered != null and box.offered.family() != held_out and not holder.held_families().has(box.offered.family()),
		"  a gun you've bought since is not handed out again (%s -> %s)" % [held_out, box.offered.id if box.offered else "-"])
	_check(holder.has_weapon(held_out) and holder.slot_data(holder.slot_of(held_out)).id == up_id and box.state == box.State.OFFER,
		"  ...and your upgraded one is still upgraded; the box still holds one out")
	holder.select(1 - holder.active)
	var take_result: String = box.try_take(holder)
	_check(take_result == "taken" and holder.has_weapon(held_out), "  the new offer can be taken (into the other slot), and the other gun stays (%s, %s)" % [take_result, holder.held_families()])
	zm.points = 950
	box.state = box.State.IDLE
	box.uses = 0
	box.move_after = 99
	var never_held := true
	var seen := {}
	for i in 120:
		var want := (box.options_for(holder) as Array)
		var draw: Resource = want[box.rng.randi() % want.size()]
		seen[draw.id] = true
		never_held = never_held and not holder.held_families().has(draw.family())
	_check(never_held and seen.size() >= 4, "  it never offers a gun you carry, whatever else comes (%d different)" % seen.size())
	holder.give(load("res://weapons/pistol.tres"))
	holder.give(load("res://weapons/lmg.tres"))
	var lmg_held := true
	for i in 40:
		zm.points = 950
		box.state = box.State.IDLE
		box.try_open(holder)
		lmg_held = lmg_held and box.offered.family() != "lmg" and box.offered.family() != "pistol"
		box.advance(box.SPIN_TIME + 0.1)
		box.advance(box.OFFER_TIME + 1.0)
	_check(lmg_held, "  carrying the LMG, 40 openings never offer it")
	_check(box.state == box.State.IDLE and box.offered == null, "  a gun left on the box for too long is withdrawn")
	var spot0: int = box.spot
	var pos0: Vector3 = box.global_position
	var moves := []
	box.moved.connect(func(i: int): moves.append(i))
	box.uses = 0
	box.move_after = 3
	for i in 3:
		zm.points = 950
		box.try_open(holder)
		box.advance(box.SPIN_TIME + 0.1)
		if i < 2:
			_check(box.spot == spot0, "  use %d of 3: the box stays where it is" % (i + 1))
		box.advance(box.OFFER_TIME + 1.0)
	_check(moves.size() == 1 and box.spot != spot0 and box.global_position.distance_to(pos0) > 5.0 and box.uses == 0, "  after its third use the box moves to another spot (%d -> %s)" % [spot0, moves])

	# The upgrade machine.
	var mach: Node = block.upgrade_machine
	holder.give(load("res://weapons/pistol.tres"))
	holder.advance(10.0)
	holder.fire()
	zm.points = 4999
	_check(mach.try_upgrade(holder) == "poor" and zm.points == 4999 and holder.current.id == "pistol", "  one short of 5000: no upgrade, no charge")
	zm.points = 5000
	zm.double_points = true
	_check(mach.try_upgrade(holder) == "upgraded" and zm.points == 0 and holder.current.id == "pistol_up", "  5000 under Double Points still costs 5000 and swaps to the upgraded data")
	zm.double_points = false
	_check(holder.mag == holder.current.mag_size and holder.reserve == holder.current.reserve_max and holder.current.display_name != "Service Pistol",
		"  the upgraded gun is full with its bigger mag and reserve (%d + %d)" % [holder.mag, holder.reserve])
	zm.points = 5000
	_check(mach.try_upgrade(holder) == "already" and zm.points == 5000, "  an upgraded gun can't be upgraded again, for free")
	zm.points = 0
	holder.give(load("res://weapons/ar.tres"))
	_check(mach.try_upgrade(holder) == "poor" and zm.points == 0, "  with 0 points the machine does nothing, and nothing goes negative")
	player.global_position = mach.global_position + mach.global_transform.basis.z * 0.9
	await _frames(6)
	zm.points = 5000
	_check(player._nearest_interactable() == mach and mach.prompt_text().contains("5000"), "  the machine answers to E, naming its price (%s)" % mach.prompt_text())
	player._unhandled_input(_key_action("interact"))
	_check(holder.current.id == "ar_up" and zm.points == 0, "  pressing E upgrades the gun in your hands")

	# The HUD.
	var hud: Node = block.hud
	holder.give(load("res://weapons/smg.tres"))
	holder.mag = 7
	await _frames(3)
	await process_frame
	var vp := root.get_visible_rect().size if root.get_visible_rect().size.x > 0 else Vector2(1280, 720)
	var rect: Rect2 = hud.ammo_label.get_global_rect()
	_check(hud.ammo_label.text == "7 / 150", "  the ammo shows mag / reserve bottom-right (%s)" % hud.ammo_label.text)
	_check(rect.position.x >= 0 and rect.end.x <= vp.x + 0.5 and rect.position.y >= 0 and rect.end.y <= vp.y + 0.5 and rect.position.x > vp.x * 0.5,
		"  and sits inside the window on the right (%s of %s)" % [rect, vp])
	var prect: Rect2 = hud.prompt.get_global_rect()
	_check(hud.prompt.text.contains("5000") and prect.position.x >= 0 and prect.end.x <= vp.x + 0.5 and absf(prect.get_center().x - vp.x * 0.5) < 2.0,
		"  the prompt over the middle names the machine's price and sits inside the window (%s: %s)" % [hud.prompt.text, prect])
	holder.mag = 12345
	holder.reserve = 98765
	await process_frame
	await process_frame
	rect = hud.ammo_label.get_global_rect()
	_check(rect.end.x <= vp.x + 0.5 and rect.position.x >= 0, "  even a silly number stays inside the window (%s)" % rect)
	hud.say("Not enough points")
	_check(hud.message.text == "Not enough points" and hud.message.modulate.a > 0.9, "  a refused purchase puts a word on the screen")
	hud.visible = true

	# Guns build to size and the right way round.
	var models_ok := true
	for id in ids:
		var d: Resource = load("res://weapons/%s.tres" % id)
		var gun: Node3D = load("res://weapons/GunModel.gd").build(d)
		var b: AABB = _zw_bounds(gun)
		var long_ok: bool = absf(b.size.z - d.model_length) < d.model_length * 0.15 and b.size.z >= b.size.x
		models_ok = models_ok and long_ok
		if not long_ok:
			print("   model ", id, " ", b.size, " wanted ", d.model_length)
		gun.free()
	_check(models_ok, "  every gun model is built along -Z at its length")

	zm.leave()
	_check(_zw_bindings() == story_binds, "  leaving the mode puts the story's controls back exactly (and drops the mode's own actions)")
	_check(InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_Y, true), "walkman") and InputMap.event_is_action(_zw_pad_button(JOY_BUTTON_A, true), "fire"),
		"  ...Triangle is the tapes and Cross fires darts again")
	DirAccess.remove_absolute(zm.PATH)
	gs.start_run()

func _zw_bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var xf := Transform3D()
		var c: Node = m
		while c != null and c != n.get_parent():
			xf = (c as Node3D).transform * xf
			c = c.get_parent()
		var a := xf * m.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out

# --- Walk-in shops on Main Street (open world, task 3) ----------------------

## The four shops you walk into from the sidewalk: the node under Cell_Main,
## the place id GameState keys hours on, the street spawn out front, who
## watches the shelves ("" = nobody), what to walk up to, the shop's front
## in world/Facades.gd and its door's x.
const WALK_INS := [
	{"node": "WalkIn_Convenience", "place": "convenience", "spawn": "SpawnFromShop", "keeper": "Shopkeeper", "target": "Item1", "front": "Shop", "x": 3.5, "old": "StoreConvenience3D", "track": "convenience.ogg"},
	{"node": "WalkIn_Liquor", "place": "liquor", "spawn": "SpawnFromLiquor", "keeper": "Clerk", "target": "Item1", "front": "Liquor", "x": 10.5, "old": "StoreLiquor3D", "track": "liquor.ogg"},
	{"node": "WalkIn_Pawn", "place": "pawn", "spawn": "SpawnFromPawn", "keeper": "", "target": "Pawnbroker", "front": "Pawn", "x": 0.0, "old": "Pawn3D", "track": "pawn.ogg"},
	{"node": "WalkIn_Music", "place": "music", "spawn": "SpawnFromMusic", "keeper": "Clerk", "target": "Item1", "front": "Music", "x": -7.0, "old": "MusicStore3D", "track": "music.ogg"},
]

## Puts the player on the line x, from z `from` to `to`, a little each
## frame -- crossing a doorway the way walking does.
func _step_player(x: float, from: float, to: float, frames := 50) -> void:
	var p := _player()
	for i in frames + 1:
		p.global_position = Vector3(x, 0.0, lerpf(from, to, float(i) / frames))
		await physics_frame

func _roof_of(city: Node, front: String) -> Node3D:
	return city.get_node("Facades").get_node_or_null("Roof" + front) as Node3D

## Waits (a few seconds at most) for a walk-in's room to be built.
func _wait_loaded(shop: Node, frames := 1500) -> bool:
	for i in frames:
		if shop.loaded:
			return true
		await physics_frame
	return shop.loaded

func _walk_in_checks(gs: Node) -> void:
	await _section("Walk-in shops: the rooms are scenes of their own, built when you come near")
	_close_menus()
	gs.start_run()
	gs.clock_running = false
	gs.clock = 17 * 60
	# City3D.tscn holds the doorways only: the rooms (props, textures, staff)
	# are world/walkin/*.tscn, so the street loads about as fast as before.
	var city_path := "res://world/City3D.tscn"
	var city_file := FileAccess.open(city_path, FileAccess.READ)
	var city_kb := city_file.get_length() / 1024.0
	var city_text := FileAccess.get_file_as_string(city_path)
	_check(city_kb < 740.0 and not city_text.contains("CashRegister_01") and not city_text.contains("Ukulele_01"),
		"  City3D.tscn is %.0f KB (base 675) and none of the shops' props are in it" % city_kb)
	var rooms_ok := true
	for front in ["Shop", "Liquor", "Pawn", "Music"]:
		rooms_ok = rooms_ok and ResourceLoader.exists("res://world/walkin/%s.tscn" % front)
	_check(rooms_ok, "  each room is its own scene (world/walkin/<Front>.tscn)")
	# Far from the shops (the east end) nothing of them is built.
	var save_node := root.get_node("SaveGame")
	save_node.pending_position = Vector3(60.0, 0.0, -2.6)
	var city := await _load(city_path)
	await _frames(30)
	var far_shops := WALK_INS.map(func(w): return city.get_node("Cell_Main/" + String(w["node"])))
	_check(far_shops.all(func(sh): return not sh.loaded and sh.get_child_count() < 12), "  60 m away none of the four rooms is built (%s)" % [far_shops.map(func(sh): return sh.get_child_count())])
	_clear_patrol(city)
	var p := _player()
	# Their scenes come in with the street's, in the background, from the
	# title screen on (SceneLoader); a player walking up finds them in.
	var loader := root.get_node("SceneLoader")
	var room_paths: Array = load("res://world/Facades.gd").walk_in_scenes()
	for i in 4000:
		if room_paths.all(func(rp): return loader.cached(rp)):
			break
		await physics_frame
	_check(room_paths.all(func(rp): return loader.cached(rp)), "  the four rooms' scenes load in the background with the street's")
	# Walking up the street builds them, one at a time, in small steps.
	p.global_position = Vector3(1.5, 0.0, -2.6)
	p.reset_physics_interpolation()
	var slowest := 0
	# (The teleport itself wakes cells: not what's measured, so its first
	# frames are let go by.)
	await _frames(4)
	var last := Time.get_ticks_usec()
	var built_at := []
	for i in 1500:
		await physics_frame
		var now := Time.get_ticks_usec()
		slowest = maxi(slowest, now - last)
		last = now
		var n := far_shops.filter(func(sh): return sh.loaded).size()
		if built_at.is_empty() or built_at[built_at.size() - 1] != n:
			built_at.append(n)
		if n == 4:
			break
	_check(far_shops.all(func(sh): return sh.loaded), "  coming near builds all four (steps %s)" % [built_at])
	_check(slowest < 25000, "  and no frame in between took longer than 25 ms (slowest %.1f ms)" % (slowest / 1000.0))
	await _frames(5)
	var entered := []
	var left := []
	_check(city.has_signal("entered_shop") and city.has_signal("left_shop"), "  City3D announces entered_shop / left_shop")
	if not (city.has_signal("entered_shop") and city.has_signal("left_shop")):
		return
	city.entered_shop.connect(func(place): entered.append(place))
	city.left_shop.connect(func(place): left.append(place))
	for w in WALK_INS:
		var name: String = w["node"]
		var shop := city.get_node_or_null("Cell_Main/" + name)
		_check(shop != null and shop.get_meta("place", "") == w["place"], "%s is on Main Street (place '%s')" % [name, shop.get_meta("place", "") if shop else "-"])
		if shop == null:
			continue
		_check(city.find_child("DoorTo" + String(w["front"]), true, false) == null, "  ...with no door to a separate scene any more")
		var inside := shop.get_node_or_null("Inside") as Area3D
		_check(inside != null and inside.collision_layer == 0 and (inside.collision_mask & 2) != 0, "  an Inside area that looks for the player and nothing else")
		var spawn_in := shop.get_node_or_null("SpawnInside") as Marker3D
		_check(spawn_in != null and inside != null and inside.get_child_count() > 0, "  with a SpawnInside marker")
		# Out front, then in through the doorway.
		var street: Vector3 = city.get_node(w["spawn"]).global_position
		await _step_player(street.x, -2.6, -3.4, 8)
		var roof := _roof_of(city, w["front"])
		_check(roof != null and roof.visible, "  the roof is on while you're out on the sidewalk")
		_check(not shop.player_inside and not entered.has(w["place"]), "  not inside yet")
		await _step_player(street.x, -3.4, -8.0, 60)
		await _frames(3)
		_check(current_scene == city and current_scene.name == "City3D", "  walking in changes no scene (still %s)" % current_scene.name)
		_check(shop.player_inside and inside.overlaps_body(p), "  Inside reports the player")
		_check(entered.has(w["place"]), "  entered_shop('%s') fired" % w["place"])
		_check(roof != null and not roof.visible, "  the building's roof is hidden while you're inside")
		await _step_player(street.x, -8.0, -2.6, 60)
		await _frames(3)
		_check(not shop.player_inside and left.has(w["place"]) and roof != null and roof.visible, "  and back out: left_shop fired, the roof is back")

	await _section("Walk-in shops: real walking through the doorway, to the goods")
	for w in WALK_INS:
		var shop := city.get_node_or_null("Cell_Main/" + String(w["node"]))
		if shop == null:
			continue
		p.global_position = city.get_node(w["spawn"]).global_position
		p.reset_physics_interpolation()
		await _frames(3)
		await _wait_loaded(shop)
		var target := shop.get_node_or_null(w["target"]) as Node3D
		var arrived := target != null and await _walk_until_nearest(target, 900)
		_check(arrived and shop.player_inside, "%s: walked from the street to %s" % [w["node"], w["target"]])
		# Every goods slot is on the navmesh and reachable from the street.
		var map: RID = city.get_world_3d().navigation_map
		var slots := shop.find_children("Item*", "Area3D", false, false)
		var worst := 0.0
		for slot in slots:
			var goal: Vector3 = slot.global_position
			goal.y = 0.0
			var path := NavigationServer3D.map_get_path(map, city.get_node(w["spawn"]).global_position, goal, true)
			var end: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3(1e6, 0, 1e6)
			worst = maxf(worst, Vector2(end.x - goal.x, end.z - goal.z).length())
		_check(worst <= 0.9, "  all %d goods are reachable from the street by navmesh (worst %.2f m short)" % [slots.size(), worst])

	await _section("Walk-in shops: stealing under a clerk's eye is the same as in the old rooms")
	for w in WALK_INS:
		if w["keeper"] == "":
			continue
		gs.set_wanted(false)
		for cop in get_nodes_in_group("police"):
			cop.queue_free()
		await _frames(2)
		var shop := city.get_node("Cell_Main/" + String(w["node"]))
		var keeper := shop.get_node(w["keeper"]) as Node3D
		p.global_position = shop.get_node("SpawnInside").global_position
		p.reset_physics_interpolation()
		await _frames(30)
		_check(shop.player_inside and not gs.wanted, "%s: inside, and the clerk has nothing on you yet" % w["node"])
		var to_p: Vector3 = p.global_position - keeper.global_position
		keeper.base_facing_deg = rad_to_deg(Vector2(to_p.x, to_p.z).angle())
		keeper.sweep_speed = 0.0
		keeper._sweep_t = 0.0
		var spotted := false
		for i in 400:
			p.is_stealing = true
			await physics_frame
			if gs.wanted:
				spotted = true
				break
		p.is_stealing = false
		_check(spotted, "  GameState.wanted set after being seen mid-theft")
		_check(current_scene == city and get_first_node_in_group("police") == null, "  no officer the instant the alarm goes up, and still on the street's scene")
		var police: Node3D = null
		for i in 300:
			await physics_frame
			police = get_first_node_in_group("police") as Node3D
			if police:
				break
		_check(police != null, "  a police officer arrives shortly after")
		gs.set_wanted(false)
		for cop in get_nodes_in_group("police"):
			cop.queue_free()
		await _frames(2)

	await _section("Walk-in shops: out of the shop mid-theft, the chase follows onto the street")
	var cw: Dictionary = WALK_INS[0]
	var cshop := city.get_node("Cell_Main/" + String(cw["node"]))
	var ckeeper := cshop.get_node(cw["keeper"]) as Node3D
	p.global_position = cshop.get_node("SpawnInside").global_position
	p.reset_physics_interpolation()
	await _frames(30)
	var cto: Vector3 = p.global_position - ckeeper.global_position
	ckeeper.base_facing_deg = rad_to_deg(Vector2(cto.x, cto.z).angle())
	ckeeper.sweep_speed = 0.0
	for i in 400:
		p.is_stealing = true
		await physics_frame
		if gs.wanted:
			break
	p.is_stealing = false
	_check(gs.wanted, "  seen mid-theft")
	# Out before the officer is there, and well up the street.
	await _step_player(cw["x"], -5.9, -2.6, 20)
	await _step_player(cw["x"], -2.6, -2.6, 2)
	p.global_position = Vector3(cw["x"] + 7.0, 0, -2.6)
	p.reset_physics_interpolation()
	await _frames(2)
	_check(gs.wanted and not cshop.player_inside and current_scene == city, "  leaving mid-theft keeps you wanted, on the street's scene")
	var cop2: Node3D = null
	for i in 300:
		await physics_frame
		cop2 = get_first_node_in_group("police") as Node3D
		if cop2:
			break
	_check(cop2 != null and gs.wanted, "  the officer is called to the door all the same")
	if cop2:
		var d0 := cop2.global_position.distance_to(p.global_position)
		p.dialogue_active = true
		var closed := false
		for i in 240:
			await physics_frame
			if cop2.global_position.distance_to(p.global_position) < d0 - 3.0:
				closed = true
				break
		p.dialogue_active = false
		_check(closed and cop2.global_position.z > -4.5, "  and comes after you along the street (%.1f m -> %.1f m, z %.1f)" % [d0, cop2.global_position.distance_to(p.global_position), cop2.global_position.z])
		gs.set_wanted(false)
		for cop in get_nodes_in_group("police"):
			cop.queue_free()
		await _frames(2)

	await _section("Walk-in shops: closing time with you inside shows you out onto Main Street")
	for w in WALK_INS:
		var hours: Array = gs.OPENING_HOURS[w["place"]]
		if hours == [0, 24]:
			continue
		gs.set_wanted(false)
		gs.clock = int(hours[1]) * 60 - 1
		city = await _load("res://world/City3D.tscn")
		_clear_patrol(city)
		p = _player()
		var shop := city.get_node("Cell_Main/" + String(w["node"]))
		p.global_position = shop.get_node("SpawnInside").global_position
		p.reset_physics_interpolation()
		await _wait_loaded(shop)
		await _frames(20)
		_check(shop.player_inside and gs.is_open(w["place"]), "%s: inside a minute before closing" % w["node"])
		gs.clock = int(hours[1]) * 60 + 1
		var waited := 0
		var out := false
		while waited < int((city.CLOSING_GRACE + 1.0) * 60.0):
			await _frames(5)
			waited += 5
			if p.global_position.z > -4.4:
				out = true
				break
		_check(out and current_scene == city, "  shown out onto the sidewalk within %.0f s of the clock passing closing time (waited %.1f s)" % [city.CLOSING_GRACE + 1.0, waited / 60.0])
		await _frames(3)
		_check(not shop.player_inside, "  ...and no longer inside")
		p.dialogue_active = false

	await _section("Walk-in shops: locked when closed, lights only when you're near")
	gs.set_wanted(false)
	gs.clock = 3 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	p = _player()
	for w in WALK_INS:
		var shop := city.get_node("Cell_Main/" + String(w["node"]))
		var open: bool = gs.is_open(w["place"])
		var gate := shop.get_node_or_null("Gate") as CollisionObject3D
		_check(gate != null and (gate.collision_layer & 1 != 0) == (not open), "%s at 03:00: the doorway is %s" % [w["node"], "open" if open else "shut"])
		if not open:
			p.global_position = Vector3(city.get_node(w["spawn"]).global_position.x, 0, -3.0)
			p.reset_physics_interpolation()
			await _frames(3)
			Input.action_press("move_up")
			await _frames(70)
			Input.action_release("move_up")
			_check(p.global_position.z > -4.6 and not shop.player_inside, "  you can't walk in (z %.2f)" % p.global_position.z)
	gs.clock = 17 * 60
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	p = _player()
	var conv := city.get_node("Cell_Main/WalkIn_Convenience")
	p.global_position = Vector3(3.5, 0, -8.0)
	p.reset_physics_interpolation()
	await _wait_loaded(conv)
	var lights := conv.find_children("*", "OmniLight3D", true, false).filter(func(l): return l.is_in_group("walk_in_lights"))
	_check(lights.size() >= 2 and lights.all(func(l): return l.light_cull_mask == 2 and not l.shadow_enabled), "  the corner shop has %d interior lights, no shadows, on the interior-only layer" % lights.size())
	p.global_position = Vector3(40.0, 0, -2.6)
	p.reset_physics_interpolation()
	await _frames(40)
	_check(lights.all(func(l): return not l.visible), "  all off with you 40 m away")
	p.global_position = Vector3(3.5, 0, -8.0)
	p.reset_physics_interpolation()
	await _frames(40)
	_check(lights.all(func(l): return l.visible), "  all on when you're inside")
	p.global_position = Vector3(3.5 + 12.5, 0, -2.6)
	p.reset_physics_interpolation()
	await _frames(40)
	_check(lights.all(func(l): return not l.visible), "  and off again 12 m up the street")

	await _section("Walk-in shops: an old save inside one of the old rooms lands in the walk-in")
	var Save := load("res://autoload/SaveGame.gd")
	for w in WALK_INS:
		_check(Save.walk_in_for_scene("res://world/%s.tscn" % w["old"]) == w["node"], "  %s -> %s" % [w["old"], w["node"]])
	_check(Save.walk_in_for_scene("res://world/StorePharmacy3D.tscn") == "" and Save.walk_in_for_scene("res://world/City3D.tscn") == "", "  the pharmacy and the street stay as they are")
	gs.pending_spawn = "WalkIn_Liquor"
	city = await _load("res://world/City3D.tscn")
	p = _player()
	var liquor := city.get_node("Cell_Main/WalkIn_Liquor")
	await _wait_loaded(liquor)
	await _frames(20)
	_check(p.global_position.distance_to(liquor.get_node("SpawnInside").global_position) < 0.5 and liquor.player_inside, "  the spawn puts you at the liquor store's SpawnInside, inside")
	await _section("Walk-in shops: the clerks keep their memory of the store (tips and grudges)")
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	p = _player()
	var liq := city.get_node("Cell_Main/WalkIn_Liquor")
	p.global_position = liq.get_node("SpawnInside").global_position
	p.reset_physics_interpolation()
	await _wait_loaded(liq)
	await _frames(20)
	var clerk := liq.get_node("Clerk")
	gs.store_heat = {}
	var plain: float = clerk._alertness()
	gs.set_store_heat("liquor", 1.3, 1)
	_check(absf(clerk._alertness() - gs.store_alertness("liquor")) < 0.001 and absf(clerk._alertness() - plain) > 0.05,
		"  a grudge on the liquor store makes its walk-in clerk sharper (%.2f -> %.2f)" % [plain, clerk._alertness()])
	gs.store_heat = {}

	await _section("Walk-in shops: Continue puts you back inside the shop")
	# A save made inside a walk-in is a City3D save with a position in the shop.
	gs.store_heat = {}
	gs.cash = 77
	_check(save_node.save() and save_node.has_save(), "  a save made inside the liquor store")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(save_node.PATH))
	_check(String(data["scene"]).ends_with("City3D.tscn") and data.has("position"), "  is the street's scene with where you stood (%s)" % [data["scene"]])
	p.global_position = Vector3(60.0, 0, -2.6)
	p.reset_physics_interpolation()
	await _frames(5)
	_check(save_node.continue_run(), "  continue_run()")
	await _transition()
	await _frames(20)
	city = current_scene
	liq = city.get_node("Cell_Main/WalkIn_Liquor")
	await _wait_loaded(liq)
	p = _player()
	_check(city.name == "City3D" and liq.player_inside and liq.loaded and p.global_position.distance_to(liq.get_node("SpawnInside").global_position) < 1.5 and gs.cash == 77,
		"  lands inside the liquor store, which reports the player (at %s, cash %d)" % [p.global_position, gs.cash])
	var roof := _roof_of(city, "Liquor")
	_check(roof != null and not roof.visible and not p.dialogue_active, "  roof off, nothing stuck on the screen")
	# A save from before the shops moved onto the street: made in the old room.
	for w in WALK_INS:
		data["scene"] = "res://world/%s.tscn" % w["old"]
		data["position"] = [-4.0, 0.0, 2.0]
		var fa := FileAccess.open(save_node.PATH, FileAccess.WRITE)
		fa.store_string(JSON.stringify(data))
		fa.close()
		_check(save_node.continue_run(), "  an old save from %s: continue_run()" % w["old"])
		await _transition()
		await _frames(20)
		city = current_scene
		var shop := city.get_node("Cell_Main/" + String(w["node"]))
		await _wait_loaded(shop)
		p = _player()
		_check(city.name == "City3D" and shop.player_inside and p.global_position.distance_to(shop.get_node("SpawnInside").global_position) < 1.0,
			"  ...lands at %s's SpawnInside, inside it" % w["node"])
	save_node.delete()

	await _section("Walk-in shops: a shop is indoors (cold, rain, floor, sound)")
	gs.clock = 22 * 60
	gs.raining = true
	var sv := root.get_node("Survival")
	var sfx := root.get_node("SFX")
	city = await _load("res://world/City3D.tscn")
	_clear_patrol(city)
	p = _player()
	await _frames(10)
	_check(sv.outside(), "  on the street you are out in the cold")
	var ambience := city.get_node_or_null("PlaceAmbience")
	_check(ambience != null and String(ambience.get_meta("track", "")).ends_with("city.ogg"), "  and hear the street")
	sfx._update_indoor_rain()
	_check(not sfx._rain_indoor.playing, "  with no muffled rain on top")
	for w in WALK_INS:
		var shop := city.get_node("Cell_Main/" + String(w["node"]))
		p.global_position = shop.get_node("SpawnInside").global_position
		p.reset_physics_interpolation()
		await _wait_loaded(shop)
		await _frames(10)
		sfx._update_indoor_rain()
		var wood: bool = w["place"] == "pawn"
		var steps_ok := true
		for i in 12:
			steps_ok = steps_ok and sfx.footstep_stream() in sfx.FOOTSTEPS["wood" if wood else "concrete"]
		_check(shop.player_inside and not sv.outside() and sfx._rain_indoor.playing and steps_ok,
			"%s: indoors -- no cold, muffled rain, %s steps" % [w["node"], "wood" if wood else "tile"])
		_check(ambience != null and String(ambience.get_meta("track", "")).get_file() == String(w["track"]), "  ...and its own ambience (%s)" % ambience.get_meta("track", ""))
		p.global_position = Vector3(w["x"], 0, -2.6)
		p.reset_physics_interpolation()
		await _frames(10)
		sfx._update_indoor_rain()
		_check(not shop.player_inside and sv.outside() and not sfx._rain_indoor.playing and String(ambience.get_meta("track", "")).ends_with("city.ogg"), "  ...and back out on the street")
	gs.raining = false
	gs.clock = 17 * 60


# --- Open world, task 4: people with somewhere to be --------------------------------

func _sched_person(city: Node, id: String) -> Node3D:
	return city.get_node_or_null("People/" + id) as Node3D

## Stands the player `away` metres off the spot and lets the cells around
## settle (and the people in them run a tick or two).
func _sched_visit(spot: Vector3, away := 6.0) -> void:
	var p := _player()
	p.global_position = spot + Vector3(away, 0, away)
	p.reset_physics_interpolation()
	await _frames(BLOCK_SETTLE_FRAMES + 40)

## The block loaded, and the people it makes a frame at a time all made.
func _sched_load() -> Node:
	var c := await _load("res://world/City3D.tscn")
	var frames := 10
	var t0 := Time.get_ticks_msec()
	# Their bodies load in the background (threads), a frame's wait each.
	while not c.people_pending.is_empty() and Time.get_ticks_msec() - t0 < 60000:
		await _frames(1)
		frames += 1
	c.set_meta("people_frames", frames)
	return c


## Stands the player `away` metres off a place, in a fresh block at `minute`.
func _sched_scene(gs: Node, minute: int, place: String, away := 6.0) -> Node:
	gs.clock = minute
	var c := await _sched_load()
	_clear_patrol(c)
	await _frames(5)
	await _sched_visit(root.get_node("Schedules").place_position(place), away)
	return c

## Plays `frames` physics frames at the real pace of the clock with the real
## camera and reports anything that, while it could be seen, appeared,
## vanished, jumped more than a metre in a tick, changed its seat height by
## more than 3 cm in one, or changed its pose in place (a clip change with no
## walking and no new entry or state within the last two seconds: standing
## up out of a chair is fine when they walk off). A person walking into her
## door in sight is the one vanishing that's fine. With `orbit` the camera
## swings once round the player while the clock runs. `until`, if given, ends
## the run early when it returns true.
func _sched_watch(city: Node, frames: int, orbit := false, until := Callable()) -> Array:
	var sch := root.get_node("Schedules")
	var gs := _gs()
	var prev := {}
	var bad: Array = []
	var player := _player()
	var pitch: float = player.get("_look_pitch")
	for f in frames:
		await _frames(1)
		gs.advance_clock(gs.MINUTES_PER_SEC / 60.0)
		if orbit:
			player.set_look(TAU * float(f) / float(frames) - PI, pitch)
		var subjects: Array = []
		for n in get_nodes_in_group("scheduled_people"):
			if city.is_ancestor_of(n):
				subjects.append(n)
		for n in get_nodes_in_group("patrol"):
			subjects.append(n)
		var pusher := city.get_node_or_null("Pusher")
		if pusher != null:
			subjects.append(pusher)
		for n in subjects:
			if not is_instance_valid(n):
				continue
			var is_pusher: bool = n == pusher
			var is_person: bool = n.is_in_group("scheduled_people")
			var vis: bool = pusher.model_root.visible if is_pusher else n.visible
			var pos: Vector3 = n.global_position
			var lift := 0.0
			var clip := ""
			var key := ""
			if is_person:
				lift = float(n.get("_model_root").position.y)
				clip = n.anim.current_clip()
				key = "%s/%s" % [n.goal.get("place", ""), n.goal.get("activity", "")]
			elif is_pusher:
				clip = pusher.anim.current_clip()
				key = str(pusher.state)
			var rec := {"vis": vis, "pos": pos, "lift": lift, "clip": clip, "moved": -999, "changed": -999}
			if prev.has(n):
				var was: Dictionary = prev[n]
				rec["moved"] = f if pos.distance_to(was["pos"]) > 0.004 else was["moved"]
				rec["changed"] = f if key != was.get("key", key) else was["changed"]
				if sch.is_seen(was["pos"], is_pusher) or sch.is_seen(pos, is_pusher):
					var what := ""
					if vis != was["vis"]:
						var at_door := false
						if is_person and was["vis"] and not vis:
							var pl := String(n.goal.get("place", ""))
							at_door = pl.begins_with("Stoop") and pos.distance_to(sch.place_position(pl)) < 0.8
						if not at_door:
							what = "%s %s" % ["appeared" if vis else "vanished", n.name]
					elif vis and pos.distance_to(was["pos"]) > 1.0:
						what = "%s jumped %.1f m" % [n.name, pos.distance_to(was["pos"])]
					elif absf(lift - was["lift"]) > 0.03:
						what = "%s's seat height jumped %.2f" % [n.name, lift - was["lift"]]
					elif vis and clip != was["clip"] and clip != "" and f - rec["moved"] > 20 and f - rec["changed"] > 120 \
							and not (clip == "walk" or was["clip"] == "walk" or is_pusher and (is_playing_once_clip(clip) or is_playing_once_clip(was["clip"]))):
						what = "%s changed pose in place (%s -> %s)" % [n.name, was["clip"], clip]
					if what != "" and bad.size() < 12:
						bad.append("%s (frame %d)" % [what, f])
			rec["key"] = key
			prev[n] = rec
		if until.is_valid() and until.call():
			break
	return bad

## Pusher one-shots (picking up the stash, the hand-off) are his own business.
func is_playing_once_clip(clip: String) -> bool:
	return clip in ["pick-up", "interact", "take"]

func _schedules_checks(gs: Node) -> void:
	await _section("People with somewhere to be: schedules, passers-by, the beat cop's loop, the pusher's two posts")
	_close_menus()
	var sch := root.get_node_or_null("Schedules")
	_check(sch != null, "  Schedules is an autoload")
	if sch == null:
		return
	gs.start_run()
	gs.clock_running = false
	gs.clock = 8 * 60
	# --- the data
	var need := ["beat_cop", "pusher", "ray", "shop_convenience", "shop_liquor", "shop_pawn", "shop_music"]
	var have: PackedStringArray = sch.people()
	_check(need.all(func(n): return have.has(n)) and sch.walkers().size() >= 10 and not have.has("postman"),
		"  beat cop, pusher, Ray, the four shopkeepers and %d regulars are scheduled (the postman is an errand, not a timetable)" % sch.walkers().size())
	var bad := []
	for id in have:
		var last := -1
		for e in sch.info(id)["entries"]:
			if e[0] <= last or e[0] < 0 or e[0] >= 1440 or not (e[2] in sch.ACTIVITIES):
				bad.append(id)
			last = e[0]
	_check(bad.is_empty(), "  every entry is in order of time, in the day, with a known activity (%s)" % [bad])
	_check(sch.entry_at("stoop_a", 23 * 60 + 59)["activity"] == "smoke" and sch.entry_at("stoop_a", 1)["activity"] == "sleep"
		and sch.entry_at("stoop_a", 24 * 60 + 1)["activity"] == "sleep" and sch.entry_at("stoop_b", 30)["place"] == "Stoop2",
		"  across midnight the entry switches (23:59 smoke, 00:01 in), and before a day's first entry yesterday's last still holds")
	var nx: Dictionary = sch.next_entry("stoop_a", 23 * 60 + 59)
	_check(nx["activity"] == "sleep" and nx["in"] == 1, "  next_entry looks across midnight (in %s min)" % nx.get("in"))
	var shops_ok := true
	for id in ["shop_liquor", "shop_pawn", "shop_music", "shop_convenience"]:
		var shop: String = sch.info(id)["shop"]
		for h in range(0, 24):
			gs.clock = h * 60 + 30
			var open_now: bool = gs.is_open(shop)
			var works: bool = sch.entry_at(id, h * 60 + 30)["activity"] == "work"
			shops_ok = shops_ok and open_now == works
	gs.clock = 8 * 60
	_check(shops_ok, "  the shopkeepers are at the counter exactly when GameState.is_open says the shop is")
	var ph: Array = gs.PUSHER_HOURS
	var pusher_ok := true
	for h in range(0, 24):
		var sleeping: bool = sch.entry_at("pusher", h * 60 + 30)["activity"] == "sleep"
		pusher_ok = pusher_ok and sleeping == (not gs.hours_contain(ph, h + 0.5))
		var night: bool = sch.pusher_post(h * 60 + 30) == "PusherNight"
		if not sleeping:
			pusher_ok = pusher_ok and night == (h + 0.5 >= gs.PUSHER_NIGHT_FROM or h + 0.5 < ph[1])
	_check(pusher_ok, "  the pusher's posts follow GameState.PUSHER_HOURS: the corner by day, the overpass from %02d:00" % gs.PUSHER_NIGHT_FROM)

	# --- people on the block at the hours asked
	var city := await _sched_load()
	_clear_patrol(city)
	await _frames(5)
	var guard: int = city.get_meta("people_frames", 0)
	var people := get_nodes_in_group("scheduled_people").filter(func(n): return city.is_ancestor_of(n))
	_check(people.size() == sch.walkers().size(), "  %d people are on the block, made one a frame in the first %d frames (%d scheduled to be)" % [people.size(), guard, sch.walkers().size()])
	var missing: Array = Array(sch.walkers()).filter(func(id): return sch.position_at(id, 12 * 60) == Vector3.INF)
	_check(missing.is_empty(), "  every one of their places is a marker on the block (%s missing)" % [missing])
	var count_before := people.size()
	var nodes_before := city.get_child_count()
	var sample := ["chess_a", "commuter_a", "stoop_b", "camp_c", "court_a"]
	var wrong := []
	for t in [8 * 60, 14 * 60, 23 * 60 + 30, 30]:
		gs.clock = t
		for id in sample:
			var spot: Vector3 = sch.position_for(id, sch.entry_at(id, t)["place"])
			# A clock that jumps puts people in their places only where nobody
			# can see it happen: here, nobody is looking.
			sch.seen_override = 0
			await _sched_visit(spot)
			sch.seen_override = -1
			var person := _sched_person(city, id)
			var e: Dictionary = sch.entry_at(id, t)
			var want_out: bool = e["activity"] != "sleep"
			var near: float = person.global_position.distance_to(sch.position_at(id, t)) if person else 99.0
			var ok: bool = person != null and person.visible == want_out and (not want_out or near <= 2.0)
			if not ok:
				wrong.append("%s at %02d:%02d (%s %s, visible %s, %.1f m off)" % [id, t / 60, t % 60, e["place"], e["activity"], person.visible if person else "-", near])
	_check(wrong.is_empty(), "  at 08:00, 14:00, 23:30 and 00:30 (the clock jumped, unseen) they are where Schedules.position_at says, or indoors (%s)" % [wrong.slice(0, 4)])
	_check(get_nodes_in_group("scheduled_people").size() == count_before and city.get_child_count() == nodes_before,
		"  nobody was made while the clock ran: %d people, %d nodes under the block throughout" % [count_before, nodes_before])

	# --- across midnight, live
	gs.clock = 23 * 60 + 58
	sch.seen_override = 0
	await _sched_visit(sch.place_position("Stoop1"))
	sch.seen_override = -1
	var smoker := _sched_person(city, "stoop_a")
	_check(smoker.visible and smoker.global_position.distance_to(sch.position_at("stoop_a", 23 * 60 + 58)) <= 2.0, "  23:58, the stoop sitter's out on Stoop1")
	gs.advance_clock(3.0)
	await _frames(200)
	_check(not smoker.visible, "  ...and at 00:01 she has walked to the door and gone in (in plain sight, on foot)")

	# --- the walk between two places
	gs.clock = 7 * 60 + 55
	var camp: Vector3 = sch.position_at("camp_c", 7 * 60 + 55)
	sch.seen_override = 0
	await _sched_visit(sch.place_position("AlleyDumpsters"), 3.0)
	await _sched_visit(camp, 6.0)
	sch.seen_override = -1
	var scav := _sched_person(city, "camp_c")
	var home_d: float = scav.global_position.distance_to(camp)
	gs.advance_clock(10.0)
	# The way round to the alley is a hundred metres and more: at four times his pace.
	scav.set("_speed", 4.0)
	var start := scav.global_position
	# Stay close enough that the cell is awake and he is walking in full.
	var dumpsters: Vector3 = sch.position_at("camp_c", 12 * 60)
	var arrived := false
	var moved_by_steps := 0.0
	var prev := scav.global_position
	for i in 90:
		await _frames(60)
		moved_by_steps += scav.global_position.distance_to(prev)
		prev = scav.global_position
		(_player() as Node3D).global_position = scav.global_position + Vector3(6, 0, 6)
		if scav.global_position.distance_to(dumpsters) < 1.5:
			arrived = true
			break
	_check(home_d <= 2.0 and moved_by_steps > 20.0 and arrived, "  at 08:00 the camp's scavenger sets off for the dumpsters and gets there on foot (%.0f m walked, arrived %s)" % [moved_by_steps, arrived])

	# --- a sleeping cell does nothing; woken, the clock is caught up unseen
	gs.clock = 21 * 60
	city = await _sched_load()
	_clear_patrol(city)
	var sitter := _sched_person(city, "stoop_a")
	var stoop: Vector3 = sch.place_position("Stoop1")
	_check(sitter != null and sitter.global_position.distance_to(sch.position_at("stoop_a", 21 * 60)) <= 2.0, "  21:00, loaded from scratch: she is on Stoop1 (not at the spawn)")
	# (Nobody in the camera's view, to keep the camera out of it.)
	sch.seen_override = 0
	_player().global_position = Vector3(-17.5, 0, -2.6)
	await _frames(BLOCK_SETTLE_FRAMES + 10)
	_check(sitter.get("_frozen") and sitter.visible, "  from Main Street Back Street's cell sleeps and, out of sight, so does she (frozen %s), but she is not made to vanish (shown %s)" % [sitter.get("_frozen"), sitter.visible])
	var frozen_at := sitter.global_position
	await _frames(40)
	_check(sitter.global_position == frozen_at and sitter.get("_frozen"), "  ...and she stands as she was while nobody is looking")
	gs.clock = 3 * 60
	await _frames(40)
	_check(not sitter.visible and sitter.get("_frozen"), "  ...a clock that moves on puts her away unseen (the 0.3 s poll), no one watching")
	await _sched_visit(stoop)
	sch.seen_override = -1
	_check(not sitter.get("_frozen") and not sitter.visible, "  walk down to Back Street at 03:00 and, unseen, she's already gone in (caught up on waking)")
	_player().global_position = Vector3(-17.5, 0, -2.6)
	await _frames(BLOCK_SETTLE_FRAMES + 10)
	gs.clock = 21 * 60
	sch.seen_override = 0
	await _sched_visit(stoop)
	sch.seen_override = -1
	_check(sitter.visible and sitter.global_position.distance_to(sch.position_at("stoop_a", 21 * 60)) <= 2.0, "  ...and back at 21:00 she is on the stoop again")
	# In plain sight nobody is moved: she is where she was, and does what her
	# entry says on foot.
	_player().global_position = Vector3(-17.5, 0, -2.6)
	await _frames(BLOCK_SETTLE_FRAMES + 10)
	gs.clock = 3 * 60
	await _sched_visit(stoop)
	await _frames(200)
	_check(not sitter.visible, "  woken in sight at 03:00 she is still on the stoop, then walks in rather than blinking out")
	var bench: Vector3 = sch.place_position("ParkBench")
	sitter = _sched_person(city, "chess_a")

	# --- avoidance only up close
	var near_p := _player()
	near_p.global_position = bench + Vector3(4, 0, 4)
	await _frames(45)
	var near_av: bool = sitter.nav_agent.avoidance_enabled
	near_p.global_position = bench + Vector3(0, 0, -20)
	await _frames(45)
	var far_av: bool = sitter.nav_agent.avoidance_enabled
	_check(near_av and not far_av, "  navigation avoidance is on within 10 m of the player and off beyond (near %s, 20 m %s)" % [near_av, far_av])

	# --- the pusher's two posts
	gs.clock = 12 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _frames(10)
	var pusher := city.get_node("Pusher")
	var corner: Vector3 = sch.place_position("PusherCorner")
	var night_spot: Vector3 = sch.place_position("PusherNight")
	_check(pusher.state == pusher.State.POST and pusher.global_position.distance_to(corner) < 3.0, "  12:00: the pusher is on the corner (%.1f m from it)" % pusher.global_position.distance_to(corner))
	gs.clock = 22 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _frames(10)
	pusher = city.get_node("Pusher")
	_check(pusher.state == pusher.State.POST and pusher.global_position.distance_to(night_spot) < 3.0, "  22:00: he is under the overpass (%.1f m from it)" % pusher.global_position.distance_to(night_spot))
	var lanes_clear := true
	var space: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var pmap: RID = _player().get_world_3d().navigation_map
	for target in [pusher.stash_position, pusher.hide_position]:
		var wp := NavigationServer3D.map_get_path(pmap, pusher.global_position, target, true)
		var wlen := 0.0
		for k in range(1, wp.size()):
			wlen += wp[k].distance_to(wp[k - 1])
		lanes_clear = lanes_clear and wp.size() > 0 and Vector2(wp[wp.size() - 1].x - target.x, wp[wp.size() - 1].z - target.z).length() < 0.5 and wlen < 14.0
	_check(lanes_clear and pusher.stash_position.distance_to(night_spot) < 8.0, "  ...with his stash and his hiding place a short walk away on the navmesh")
	var open_to: Array = []
	for eye in [Vector3(-3.0, 1.6, 0.0), Vector3(0.0, 1.6, 3.0), Vector3(-2.0, 1.6, -3.0)]:
		var rq := PhysicsRayQueryParameters3D.create(night_spot + eye, pusher.hide_position + Vector3(0, 0.9, 0), 1)
		if space.intersect_ray(rq).is_empty():
			open_to.append(eye)
	_check(open_to.is_empty(), "  ...and the hiding place is round the pillar, out of sight from the deck (open from %s)" % [open_to])
	gs.clock = 5 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _frames(10)
	pusher = city.get_node("Pusher")
	_check(pusher.state == pusher.State.OFF_SHIFT and not pusher.model_root.visible, "  05:00: nobody on either post")
	# --- passers-by come out of a pool; the cop walks a loop
	gs.clock = 13 * 60
	city = await _sched_load()
	await _frames(10)
	var kids_before := city.get_child_count()
	var walkers_before := get_nodes_in_group("pedestrians").size()
	for i in 6:
		city._spawn_pedestrian()
	await _frames(3)
	_check(city.get_child_count() == kids_before, "  spawning passers-by while the block is live makes no new nodes (%d -> %d)" % [kids_before, city.get_child_count()])
	_check(get_nodes_in_group("pedestrians").size() >= walkers_before, "  ...but they are out (%d -> %d)" % [walkers_before, get_nodes_in_group("pedestrians").size()])
	var xs: Array = []
	var zs: Array = []
	for walk in city.WALKS:
		for v in walk["points"]:
			xs.append(v.x)
			zs.append(v.z)
	var lanes_ok: bool = xs.min() < -60.0 and xs.max() > 60.0 and zs.min() < -90.0 and zs.max() > -5.0
	_check(lanes_ok, "  passers-by walk all four streets (both loops go round the block)")
	for c in get_nodes_in_group("patrol"):
		c.remove_from_group("patrol")
		c.queue_free()
	city.set("_patrol_timer", 99999.0)
	await _frames(3)
	var route: Array = sch.patrol_route()
	var map: RID = _player().get_world_3d().navigation_map
	var joined := true
	for i in route.size():
		var a: Vector3 = route[i]
		var b: Vector3 = route[(i + 1) % route.size()]
		var path := NavigationServer3D.map_get_path(map, a, b, true)
		joined = joined and path.size() > 0 and path[path.size() - 1].distance_to(b) < 0.8 and path[0].distance_to(a) < 0.8
	_check(route.size() >= 12 and joined, "  the beat cop's loop (%d waypoints) is one unbroken walk on the navmesh" % route.size())
	city._spawn_patrol(route[0])
	var cop := get_first_node_in_group("patrol") as Node3D
	cop.heading = 1.0
	var walked := 0.0
	var last := cop.global_position
	var off_mesh := 0.0
	for i in 40:
		await _frames(60)
		walked += cop.global_position.distance_to(last)
		last = cop.global_position
		var snap := NavigationServer3D.map_get_closest_point(map, cop.global_position)
		off_mesh = maxf(off_mesh, Vector2(snap.x - cop.global_position.x, snap.z - cop.global_position.z).length())
		_player().global_position = Vector3(-17.5, 0, -2.6)
	_check(walked > 25.0 and off_mesh < 1.2 and cop.get("route_index") != null, "  the beat cop walks his loop (%.0f m in 40 s, never more than %.1f m off the navmesh)" % [walked, off_mesh])
	_check(sch.patrol_route()[0].distance_to(sch.place_position("PoliceStation")) < 3.0, "  ...which starts at the police station")

	# --- places are clear of walls and on the navmesh; every walk fits its time
	gs.clock = 12 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _frames(10)
	var phys: PhysicsDirectSpaceState3D = city.get_world_3d().direct_space_state
	var navmap: RID = _player().get_world_3d().navigation_map
	var min_speed: float = load("res://npc/ScheduledPerson.gd").WALK_SPEED * 0.9
	var blocked: Array = []
	var unmeshed: Array = []
	var too_far: Array = []
	var cut_off: Array = []
	for id in sch.walkers():
		var ent: Array = sch.info(id)["entries"]
		for i in ent.size():
			var e: Array = ent[i]
			var here: Vector3 = sch.position_for(id, e[1])
			var door: bool = e[2] == "sleep" and e[1].begins_with("Stoop")
			if door:
				here = sch.place_position(e[1])
			if e[2] != "sleep":
				var q := PhysicsShapeQueryParameters3D.new()
				var ball := SphereShape3D.new()
				ball.radius = 0.4
				q.shape = ball
				q.transform = Transform3D(Basis(), here + Vector3(0, 0.6, 0))
				q.collision_mask = 1
				var names: Array = []
				for h in phys.intersect_shape(q, 8):
					var nm := String(h["collider"].name)
					if not (e[2] == "sit" and nm.begins_with("ParkBench")):
						names.append(nm)
				if not names.is_empty():
					blocked.append("%s at %s (%s)" % [id, e[1], names])
				var snapped := NavigationServer3D.map_get_closest_point(navmap, here)
				if Vector2(snapped.x - here.x, snapped.z - here.z).length() > 0.5 and not (e[2] == "sit" and e[1] == "ParkBench"):
					unmeshed.append("%s at %s" % [id, e[1]])
			var before: Array = ent[posmod(i - 1, ent.size())]
			if before[1] == e[1]:
				continue
			var from: Vector3 = sch.position_for(id, before[1])
			if before[1].begins_with("Stoop") and before[2] == "sleep":
				from = sch.place_position(before[1])
			var path := NavigationServer3D.map_get_path(navmap, from, here, true)
			var length := 0.0
			for k in range(1, path.size()):
				length += path[k].distance_to(path[k - 1])
			if path.size() == 0 or Vector2(path[path.size() - 1].x - here.x, path[path.size() - 1].z - here.z).length() > 0.6:
				cut_off.append("%s %s -> %s" % [id, before[1], e[1]])
			# Until the next entry that is somewhere else.
			var window := 0
			for j in range(1, ent.size()):
				var nxt: Array = ent[(i + j) % ent.size()]
				if nxt[1] != e[1]:
					window = posmod(nxt[0] - e[0] - 1, 1440) + 1
					break
			if window > 0 and length / min_speed * gs.MINUTES_PER_SEC > window:
				too_far.append("%s %s -> %s: %.0f m needs %.0f min, has %d" % [id, before[1], e[1], length, length / min_speed * gs.MINUTES_PER_SEC, window])
	_check(blocked.is_empty(), "  nobody's place is inside a wall, a barrel or a crate (%s)" % [blocked])
	_check(unmeshed.is_empty() and cut_off.is_empty(), "  every place is on the navmesh and every walk between them ends there (%s %s)" % [unmeshed, cut_off])
	_check(too_far.is_empty(), "  every walk fits the time it has, at the slowest walker's pace (%s)" % [too_far])
	var passer_models: Array = CharacterCast.PASSERSBY.map(func(en): return en["model"])
	var twins: Array = Array(sch.walkers()).filter(func(id): return passer_models.has(CharacterCast.model_for(sch.role_of(id))))
	_check(twins.is_empty(), "  none of the regulars is a passer-by's twin (%s)" % [twins])

	# --- nobody pops, jumps or changes pose in view, played live
	# The bench: at 16:30 and 17:00 the chess players' entries end, with the
	# player six metres off. They sit on, seat height and all, until nobody looks.
	city = await _sched_scene(gs, 16 * 60 + 20, "ParkBench", 4.0)
	var chess := [_sched_person(city, "chess_a"), _sched_person(city, "chess_b")]
	var popped: Array = await _sched_watch(city, 1300)
	_check(popped.is_empty(), "  the bench (live, 16:20 to 17:45): nothing popped, jumped or changed pose in view (%s)" % [popped.slice(0, 3)])
	_check(chess.all(func(c): return c.visible and absf(c.get("_model_root").position.y - 0.1) < 0.011),
		"  ...both still sit, at their seat height, after their entries ended")
	sch.seen_override = 0
	await _frames(150)
	sch.seen_override = -1
	_check(chess.all(func(c): return not c.visible), "  ...and go in once nobody could see it")
	# The camp: the sleepers' entries end at 6:30 and 7:00; the scavenger stands up at 8:00.
	city = await _sched_scene(gs, 6 * 60 + 20, "UnderpassCamp", 4.0)
	var camp_pair := [_sched_person(city, "camp_a"), _sched_person(city, "camp_b")]
	popped = await _sched_watch(city, 1250)
	_check(popped.is_empty(), "  the camp (live, 06:20 to 07:43): nothing popped in view (%s)" % [popped.slice(0, 3)])
	_check(camp_pair.all(func(c): return c.visible), "  ...the two who should be asleep wait, in sight, until nobody is looking")
	sch.seen_override = 0
	await _frames(150)
	sch.seen_override = -1
	_check(camp_pair.all(func(c): return not c.visible), "  ...then go")
	city = await _sched_scene(gs, 7 * 60 + 50, "UnderpassCamp", 4.0)
	var scav2 := _sched_person(city, "camp_c")
	var scav_start := scav2.global_position
	popped = await _sched_watch(city, 450)
	_check(popped.is_empty() and scav2.global_position.distance_to(scav_start) > 3.0,
		"  the scavenger gets up and walks off at 08:00 (%.0f m), no snap in view (%s)" % [scav2.global_position.distance_to(scav_start), popped.slice(0, 3)])
	# The stoops: she walks in at midnight; she doesn't come out in front of you.
	city = await _sched_scene(gs, 23 * 60 + 50, "Stoop1", 4.0)
	var door_sitter := _sched_person(city, "stoop_a")
	popped = await _sched_watch(city, 650)
	_check(popped.is_empty() and not door_sitter.visible, "  the stoop at midnight (live): she walks in (%s)" % [popped.slice(0, 3)])
	city = await _sched_scene(gs, 18 * 60 + 20, "Stoop1", 4.0)
	door_sitter = _sched_person(city, "stoop_a")
	popped = await _sched_watch(city, 700)
	_check(popped.is_empty() and not door_sitter.visible, "  ...and at 18:30 she doesn't step out while the stoop is in view (%s)" % [popped.slice(0, 3)])
	sch.seen_override = 0
	await _frames(250)
	sch.seen_override = -1
	_check(door_sitter.visible and door_sitter.global_position.distance_to(sch.position_at("stoop_a", 19 * 60)) <= 2.0, "  ...she comes out when nobody is looking, and stands on the stoop")
	# The bus stop: the two appear only unseen, and face the road.
	city = await _sched_scene(gs, 7 * 60, "BusStop", 4.0)
	var commuters := [_sched_person(city, "commuter_a"), _sched_person(city, "commuter_b")]
	popped = await _sched_watch(city, 700)
	_check(popped.is_empty() and commuters.all(func(c): return not c.visible), "  the bus stop (live, 07:00 to 07:47): nobody materialises in view (%s)" % [popped.slice(0, 3)])
	sch.seen_override = 0
	await _frames(150)
	sch.seen_override = -1
	var facing_road: bool = commuters.all(func(c): return c.visible and absf(wrapf(c.get("_model_root").rotation.y - PI, -PI, PI)) < 0.3)
	_check(facing_road, "  ...they turn up when nobody looks, and face the road (north)")
	var cm_rot: Array = commuters.map(func(c): return snappedf(c.get("_model_root").rotation.y, 0.01))
	gs.advance_clock(78.0)
	await _frames(200)
	_check(commuters.all(func(c): return c.visible), "  ...and past 09:00 they wait in sight to go in (%s)" % [cm_rot])
	# The beat cop, woken after a while, is not put in front of the player.
	gs.clock = 12 * 60
	city = await _sched_load()
	await _frames(10)
	city.set("_patrol_timer", 99999.0)
	var cop2 := get_first_node_in_group("patrol") as Node3D
	var loop_pts: Array = sch.patrol_route()
	var cop_at := Vector3.INF
	for w in loop_pts:
		_player().global_position = loop_pts[3] + Vector3(0, 0, 3)
		if not sch.is_seen(w):
			cop_at = w
			break
	cop2.global_position = cop_at if cop_at != Vector3.INF else cop2.global_position
	await _frames(5)
	var jump_to := -1
	for k in range(30, 1440):
		var pt: Dictionary = sch.patrol_point(gs.now_minutes() + k, int(cop2.heading))
		if (pt["pos"] as Vector3).distance_to(loop_pts[3]) < 6.0:
			jump_to = k
			break
	if cop_at != Vector3.INF and jump_to > 0:
		gs.advance_clock(float(jump_to))
		await _frames(6)
		_check(not sch.is_seen(cop2.global_position) and cop2.visible,
			"  the beat cop, caught up after %d min, isn't set down in the player's sight (%.0f m off)" % [jump_to, cop2.global_position.distance_to(_player().global_position)])
	else:
		_check(true, "  (no unseen spot on the loop from here to test the cop's wake: %s %s)" % [cop_at, jump_to])
	# The pusher walks to the overpass at 20:00, along the navmesh, with the
	# corner in view; nobody pops.
	city = await _sched_scene(gs, 19 * 60 + 40, "PusherCorner", 6.0)
	_clear_patrol(city)
	pusher = city.get_node("Pusher")
	popped = await _sched_watch(city, 700)
	var dist_off: float = pusher.global_position.distance_to(corner)
	_check(popped.is_empty() and pusher.state == pusher.State.RELOCATING and pusher.model_root.visible and dist_off > 15.0,
		"  the pusher's change of post (live, 19:40 to 20:27, corner in view): he walks off in plain sight, %.0f m so far (%s)" % [dist_off, popped.slice(0, 3)])
	popped += await _sched_watch(city, 4000, false, func(): return pusher.state == pusher.State.POST)
	_check(popped.is_empty() and pusher.state == pusher.State.POST and pusher.global_position.distance_to(night_spot) < 3.0 and pusher.model_root.visible,
		"  ...and gets to the overpass on foot, at %02d:%02d (%s)" % [int(gs.clock) / 60, int(gs.clock) % 60, popped.slice(0, 3)])
	# And a player waiting under the overpass sees him come.
	city = await _sched_scene(gs, 19 * 60 + 55, "PusherNight", 4.0)
	_clear_patrol(city)
	pusher = city.get_node("Pusher")
	popped = await _sched_watch(city, 4200, false, func(): return pusher.state == pusher.State.POST and pusher.global_position.distance_to(night_spot) < 3.0)
	_check(popped.is_empty() and pusher.state == pusher.State.POST and pusher.global_position.distance_to(night_spot) < 3.0 and pusher.model_root.visible and gs.clock < 24 * 60,
		"  a player waiting 4 m from the overpass post at 19:55 sees him arrive on foot, ready to sell, at %02d:%02d (%s)" % [int(gs.clock) / 60, int(gs.clock) % 60, popped.slice(0, 3)])
	# A player who catches him on the road at 20:30 can buy there: he stops,
	# turns, hands it over (he has it on him), and walks on.
	city = await _sched_scene(gs, 19 * 60 + 40, "PusherCorner", 6.0)
	_clear_patrol(city)
	pusher = city.get_node("Pusher")
	popped = await _sched_watch(city, 780)
	var on_road: bool = pusher.state == pusher.State.RELOCATING and pusher.global_position.distance_to(corner) > 10.0
	var road_at: Vector3 = pusher.global_position
	var shopper := _player()
	gs.cash = 100
	gs.craving = 5.0
	gs.scored_this_run = true
	shopper.global_position = pusher.global_position + Vector3(-1.2, 0, 0.6)
	await _frames(3)
	pusher._stock = ["heroin", "naloxone"]
	pusher._stock_day = gs.day
	pusher.interact(shopper)
	await _frames(2)
	var road_menu := get_tree_menu()
	var fix_cost2: int = gs.price_of("heroin")
	var had_menu: bool = road_menu != null
	if road_menu:
		road_menu.chosen.emit("heroin")
		road_menu._close()
	await _frames(2)
	var paid_road: bool = gs.cash == 100 - fix_cost2
	get_first_node_in_group("hud").advance_or_close_dialogue()
	var stopped := false
	var handed_road := false
	for i in 400:
		await _frames(1)
		stopped = stopped or pusher.state in [pusher.State.AWAIT_BUYER, pusher.State.HANDOFF]
		if gs.craving > 90.0:
			handed_road = true
			break
	get_first_node_in_group("hud").advance_or_close_dialogue()
	_check(on_road and had_menu and paid_road and stopped and handed_road,
		"  at 20:30 a player who catches him on the road buys there: menu %s, paid %s, he stopped %s, handed over %s (%.0f m from the corner)" % [had_menu, paid_road, stopped, handed_road, road_at.distance_to(corner)])
	popped = await _sched_watch(city, 4200, false, func(): return pusher.state == pusher.State.POST)
	_check(pusher.state == pusher.State.POST and pusher.global_position.distance_to(night_spot) < 3.0,
		"  ...then he walks on to the overpass and takes his post at %02d:%02d" % [int(gs.clock) / 60, int(gs.clock) % 60])
	# The commuters, watched from 45 m while the camera makes a full turn.
	city = await _sched_scene(gs, 7 * 60, "BusStop", 4.0)
	_player().global_position = sch.place_position("BusStop") + Vector3(-45.0, 0.0, 0.7)
	await _frames(BLOCK_SETTLE_FRAMES)
	var ring := [_sched_person(city, "commuter_a"), _sched_person(city, "commuter_b")]
	popped = await _sched_watch(city, 800, true)
	_check(popped.is_empty() and ring.all(func(c): return c.visible),
		"  the bus stop from 45 m with the camera turning a full circle: they came out only when it faced away (%s)" % [popped.slice(0, 3)])

	# --- a real save, mid-schedule
	var save := root.get_node("SaveGame")
	gs.start_run()
	gs.clock_running = false
	gs.clock = 21 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _sched_visit(sch.place_position("Stoop1"), 5.0)
	_check(save.save(), "  saved at 21:00 beside the stoop")
	gs.start_run()
	gs.clock_running = false
	save.continue_run()
	await _transition()
	var back := current_scene
	var waited_pending := 0
	while back.get("people_pending") != null and not back.people_pending.is_empty() and waited_pending < 600:
		await _frames(1)
		waited_pending += 1
	await _frames(20)
	var smoker2 := _sched_person(back, "stoop_a")
	_check(back.name == "City3D" and absf(gs.clock - 21 * 60) < 2.0 and smoker2 != null and smoker2.visible
		and smoker2.global_position.distance_to(sch.position_at("stoop_a", int(gs.clock))) <= 2.0,
		"  Continue puts the stoop sitter on the stoop (not at the spawn) at the saved 21:00")
	save.delete()

	# --- far but in view: a lower frame rate, not a frozen pose
	gs.clock = 8 * 60
	city = await _sched_load()
	_clear_patrol(city)
	await _sched_visit(sch.place_position("Stoop1"), 1.0)
	sch.seen_override = 1
	_player().global_position = sch.place_position("Stoop1") + Vector3(2, 0, 2)
	await _frames(BLOCK_SETTLE_FRAMES + 30)
	var far_one := _sched_person(city, "commuter_a")
	var far_d: float = far_one.global_position.distance_to(_player().global_position)
	var skel := far_one.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var pose_sum := func() -> Vector3:
		var t := Vector3.ZERO
		for b in skel.get_bone_count():
			t += skel.get_bone_global_pose(b).origin
		return t
	var clip_a: float = far_one.anim.clip_position()
	var pose_a: Vector3 = pose_sum.call()
	await _frames(60)
	var clip_b: float = far_one.anim.clip_position()
	var pose_b: Vector3 = pose_sum.call()
	var was_viewed: bool = far_one.get("_viewed")
	var far_ok: bool = far_d > 40.0 and far_one.can_process()
	# Now from Main Street: Back Street's cell sleeps, but the camera sees her.
	_player().global_position = Vector3(-17.5, 0, -2.6)
	await _frames(BLOCK_SETTLE_FRAMES + 30)
	var cells_node: Node = city.get_node("BlockCells")
	var in_sleeping: bool = cells_node.asleep_at(far_one.global_position)
	var clip_c: float = far_one.anim.clip_position()
	await _frames(90)
	var clip_d: float = far_one.anim.clip_position()
	_check(in_sleeping and not far_one.get("_frozen") and absf(clip_d - clip_c) > 0.05,
		"  a person in a sleeping cell the camera can see is animated, not a statue (asleep %s, frozen %s, clip %.2f -> %.2f)" % [in_sleeping, far_one.get("_frozen"), clip_c, clip_d])
	sch.seen_override = -1
	_check(far_ok and was_viewed and far_one.get_node("..") == city.get_node("People")
		and absf(clip_b - clip_a) > 0.05 and pose_a.distance_to(pose_b) > 0.0005,
		"  a far walker the camera sees is stepped by hand, bones and all (%.0f m away, clip %.2f -> %.2f, pose moved %.4f)" % [far_d, clip_a, clip_b, pose_a.distance_to(pose_b)])

	# --- the zombie block has none of it
	gs.mode = "zombies"
	city = await _sched_load()
	await _frames(40)
	var present := ["scheduled_people", "pedestrians", "patrol"].filter(func(g): return get_nodes_in_group(g).size() > 0)
	_check(present.is_empty() and city.get_node_or_null("People") == null, "  Dead Block has no scheduled people, passers-by or beat cop (%s)" % [present])
	gs.mode = "story"
	gs.start_run()


# --- Dead Block: first person that feels like a modern shooter (Task Z4) --------------

## Steps the feel by `n` fixed frames (the tests own the clock: nothing runs by itself).
func _fp_step(feel: Node, holder: Node, n: int, dt := 1.0 / 120.0) -> void:
	for i in n:
		holder.advance(dt)
		feel.advance(dt)

func _zombie_fp_checks(gs: Node) -> void:
	await _section("Dead Block: first-person feel -- ADS, recoil, hitmarker, slide, viewmodel, sound")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gfx := root.get_node("Graphics")
	var Viewmodel := load("res://player/Viewmodel.gd")
	var FPFeel := load("res://player/FPFeel.gd")
	zm.leave()
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	var block: Node = city.get_node_or_null("ZombieBlock")
	for i in 90:
		if block != null and block.purchases_ready:
			break
		await physics_frame
	await _frames(5)
	block.spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player := _player()
	var holder: Node = player.get_node_or_null("WeaponHolder")
	var feel: Node = holder.get("feel") if holder != null else null
	_check(holder != null and feel != null and feel.get_script() == FPFeel and player.get("feel") == feel,
		"  the weapon holder makes the feel and the player knows it")
	if feel == null:
		zm.leave()
		return
	holder.set_process(false)
	feel.auto = false
	holder.no_spread = true
	player.global_position = Vector3(-30, 0, -3)
	gfx.set_first_person(true)
	await _frames(6)
	_check(player.get("_first_person") == true and holder.viewmodel != null, "  first person has a viewmodel")

	# --- Aiming down the sights: 0.2 s for a pistol / SMG, 0.3 for a rifle, 0.4 for an LMG.
	var hip_fov: float = feel.HIP_FOV
	var times := {}
	for id in ["pistol", "smg", "ar", "lmg"]:
		holder.give(load("res://weapons/%s.tres" % id))
		await _frames(2)
		feel.reset_state()
		feel.swap_blend = 0.0
		holder._swap_left = 0.0
		holder.aiming = true
		var target: float = hip_fov * feel.ads_fov_mult()
		var t := 0.0
		var reached := -1.0
		var early_ok := true
		for i in 120:
			_fp_step(feel, holder, 1)
			t += 1.0 / 120.0
			if reached < 0.0 and absf(feel.fov - target) < 0.1:
				reached = t
			if t < 0.14 and absf(feel.fov - target) < 0.5:
				early_ok = false
		times[id] = reached
		holder.aiming = false
	_check(absf(times["pistol"] - 0.2) <= 0.03 and absf(times["smg"] - 0.2) <= 0.03,
		"  pistol and SMG reach the sights' field of view in 0.2 s +- 0.03 (%.3f, %.3f)" % [times["pistol"], times["smg"]])
	_check(absf(times["ar"] - 0.3) <= 0.03 and absf(times["lmg"] - 0.4) <= 0.03,
		"  a rifle takes 0.3 s and an LMG 0.4 s (%.3f, %.3f)" % [times["ar"], times["lmg"]])
	holder.give(load("res://weapons/pistol.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder.aiming = true
	_fp_step(feel, holder, 60)
	var ads_mult: float = feel.ads_fov_mult()
	_check(ads_mult >= 0.78 and ads_mult <= 0.86 and absf(feel.fov - hip_fov * ads_mult) < 0.1,
		"  iron sights narrow the view to 0.8 to 0.85 of the hip's (%.3f, %.1f deg)" % [ads_mult, feel.fov])
	var sens: float = feel.sens_scale()
	_check(sens < 0.9 and sens > 0.7 and absf(feel.speed_mult() - 0.6) < 0.01,
		"  aimed, the mouse turns by the field-of-view ratio (%.2f) and you walk at 0.6x (%.2f)" % [sens, feel.speed_mult()])
	var sniper: Resource = load("res://weapons/sniper.tres")
	holder.give(sniper)
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder.aiming = true
	_fp_step(feel, holder, 120)
	_check(feel.fov < hip_fov * 0.36 and feel.fov > hip_fov * 0.25, "  a scope narrows it to about a third (%.1f deg)" % feel.fov)
	holder.aiming = false

	# --- Spread: hip is wider than aimed, on every gun, and the crosshair shows it.
	var wider := true
	for id in ["pistol", "smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder"]:
		var d: Resource = load("res://weapons/%s.tres" % id)
		wider = wider and d.spread_hip > d.spread_ads
	_check(wider, "  every gun's hip spread is wider than its aimed spread")
	var Hit := load("res://ui/Hitmarker.gd")
	var hm: Control = block.hud.hitmarker
	_check(hm != null and hm.get_script() == Hit, "  the HUD has the crosshair and hitmarker")
	holder.give(load("res://weapons/ar.tres"))
	feel.reset_state()
	holder.aiming = false
	await _frames(30)
	var gap_hip: float = hm.spread_px
	holder.aiming = true
	await _frames(30)
	var gap_ads: float = hm.spread_px
	holder.aiming = false
	_check(gap_hip > gap_ads + 3.0 and hm.aim_amount > 0.9, "  the crosshair opens wider on the hip than aimed (%.1f px, %.1f px), and is gone aimed" % [gap_hip, gap_ads])

	# --- Recoil: two layers, and it recovers.
	holder.give(load("res://weapons/ar.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	player.set_look(-PI / 2.0, 0.0)
	await _frames(3)
	holder.refill_all()
	var pitch_before: float = feel.recoil.x
	var peak := 0.0
	var kick_pos_peak := 0.0
	for k in 8:
		holder._cooldown = 0.0
		holder.fire()
		for i in 6:
			_fp_step(feel, holder, 1)
			peak = maxf(peak, feel.recoil.x)
			kick_pos_peak = maxf(kick_pos_peak, feel.kick_pos.z)
	var burst_deg := rad_to_deg(peak)
	feel.kick_pos = Vector3.ZERO
	feel.kick_pos_v = Vector3.ZERO
	var single_peak := 0.0
	holder._cooldown = 0.0
	holder.fire()
	for i in 20:
		_fp_step(feel, holder, 1)
		single_peak = maxf(single_peak, feel.kick_pos.z)
	_check(burst_deg > 1.0 and burst_deg < 12.0, "  a burst climbs the view (peak %.1f deg over 8 rounds)" % burst_deg)
	_check(single_peak > 0.015 and single_peak < 0.06 and kick_pos_peak < 0.075, "  the gun jumps back 2 to 5 cm on a shot (%.1f cm) and a burst keeps it from walking off (%.1f cm)" % [single_peak * 100.0, kick_pos_peak * 100.0])
	# Release: the view is back on its aim within 0.35 s.
	var t_rec := 0.0
	var step := 1.0 / 120.0
	while feel.recoil.length() > deg_to_rad(0.05) and t_rec < 2.0:
		_fp_step(feel, holder, 1, step)
		t_rec += step
	_check(t_rec <= 0.35, "  the view recovers to the aim within 0.35 s of the last shot (%.3f s)" % t_rec)
	# The shot goes where the crosshair points (recoil is in the camera, not hidden from the ray).
	feel.reset_state()
	holder.refill_all()
	holder.aim_source = Callable()
	holder._cooldown = 0.0
	holder.fire()
	_fp_step(feel, holder, 2)
	feel.apply()
	var cam: Camera3D = player.get("camera")
	var fwd := -cam.global_transform.basis.z
	var aim: Array = holder._aim()
	_check((aim[1] as Vector3).dot(fwd) > 0.9999, "  bullets go where the crosshair is pointing (the camera carries the recoil)")
	# Visual recoil leaves a hit on the camera shake too.
	feel.reset_state()
	feel.add_trauma(0.8)
	var shake_seen := 0.0
	for i in 30:
		_fp_step(feel, holder, 1)
		shake_seen = maxf(shake_seen, feel.shake_angles.length())
	_check(shake_seen > deg_to_rad(0.3) and feel.trauma < 0.7, "  trauma shakes the view and fades (peak %.2f deg)" % rad_to_deg(shake_seen))

	# --- Hit feedback on a real zombie.
	feel.reset_state()
	holder.give(load("res://weapons/pistol.tres"))
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	zm.points = 0
	var zed: Node = await _zw_target(city, -20.0, -3.0, 6.0)
	holder.refill_all()
	await _zw_aim_part(holder, zed, "head")
	zed.health = 400.0
	holder._cooldown = 0.0
	holder.fire()
	await process_frame
	await process_frame
	var kind1: String = hm.kind
	var up1: bool = hm.showing()
	var left1: float = hm.left
	_check(up1 and kind1 == "head" and left1 <= 0.12 and left1 > 0.08, "  a hit shows the hitmarker for 0.12 s, a headshot's bigger and warm (%s, %.3f s left)" % [kind1, left1])
	for i in 7:
		hm._process(0.01)
	var still: bool = hm.showing()
	for i in 6:
		hm._process(0.01)
	_check(still and not hm.showing(), "  it is still up at 0.07 s and gone by 0.13 s")
	zed.health = 20.0
	# The first shot's recoil and the head snap moved the aim: aim again, as a player would.
	feel.reset_state()
	await _zw_aim_part(holder, zed, "head")
	holder._cooldown = 0.0
	holder.fire()
	# Read it the moment the shot lands: a slow first death frame (gore, ragdoll) must not hide it.
	var kill_up: bool = hm.showing()
	await process_frame
	await process_frame
	_check(kill_up and hm.kind == "kill" and hm.KILL.r > 0.8 and hm.KILL.g < 0.2 and hm.KILL.b < 0.2, "  the kill shot's hitmarker is red")
	_check(feel.recent.has("hit_kill") and feel.recent.has("hit_head"), "  and the hit ticks, the kill its own heavy thump (%s)" % [feel.recent])
	hm.flash("torso", false)
	_check(hm.kind == "body" and hm.BODY == Color(1, 1, 1), "  a body hit is white")
	zed.queue_free()
	var popup: Control = block.hud.popups
	var pops0: int = popup.active()
	for k in 12:
		popup.add(10 * (k + 1), "hit")
	_check(popup.active() == 8, "  the points popups are pooled at eight (%d)" % popup.active())

	# --- Sound for every action.
	var missing := []
	var names := ["fire_pistol_a", "fire_pistol_b", "fire_smg_a", "fire_ar_a", "fire_shotgun_a", "fire_sniper_a", "fire_magnum_a", "fire_lmg_a", "fire_wonder_a",
		"dry_click", "mag_out", "mag_in", "rack", "pump", "bolt", "shell_in", "brass_a", "brass_b", "brass_c", "ads_in", "ads_out", "draw", "inspect",
		"slide", "whoosh", "hit_body", "hit_head", "hit_kill"]
	for n in names:
		var st: AudioStream = FPFeel.stream(n)
		if st == null or st.get_length() < 0.01:
			missing.append(n)
	_check(missing.is_empty(), "  every action's sound loads: fire per gun, dry click, mag out/in, rack, pump, bolt, shell, brass, ADS cloth, draw, inspect, slide, whoosh, hit ticks (%s missing)" % [missing])
	holder.give(load("res://weapons/smg.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder.aim_source = Callable()
	holder._cooldown = 0.0
	holder.fire()
	_check(feel.last_sound.begins_with("fire_smg"), "  firing plays the gun's own sound (%s)" % feel.last_sound)
	holder.aiming = true
	_fp_step(feel, holder, 2)
	_check(feel.recent.has("ads_in"), "  raising the sights plays the cloth (%s)" % [feel.recent])
	holder.aiming = false
	_fp_step(feel, holder, 2)
	_check(feel.recent.has("ads_out"), "  lowering them too (%s)" % [feel.recent])
	var heard := []
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	var rt: float = holder.reload_left()
	for i in int(rt * 120.0) + 10:
		var before: String = feel.last_sound
		_fp_step(feel, holder, 1)
		if feel.last_sound != before or (feel.last_sound in ["mag_out", "mag_in", "rack"] and heard.size() < 3 and not heard.has(feel.last_sound)):
			if heard.is_empty() or heard.back() != feel.last_sound:
				heard.append(feel.last_sound)
	heard = heard.filter(func(n): return n in ["mag_out", "mag_in", "rack"])
	_check(heard == ["mag_out", "mag_in", "rack"], "  a reload has its steps in order: mag out, mag in, rack (%s)" % [heard])
	holder.give(load("res://weapons/pistol.tres"))
	_check(feel.last_sound == "draw", "  drawing a gun has its sound (%s)" % feel.last_sound)

	# --- The shot's effects: flash, shells, tracers (pooled).
	holder.give(load("res://weapons/ar.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder.refill_all()
	holder.aim_source = Callable()
	player.set_look(-PI / 2.0, 0.0)
	await _frames(3)
	var vm: Node3D = holder.viewmodel
	holder._cooldown = 0.0
	holder.fire()
	_check(vm.flash.visible and feel._flash_left > 0.0, "  a shot lights the muzzle flash")
	_fp_step(feel, holder, 12)
	_check(not vm.flash.visible, "  and it is gone within a few frames")
	for k in 30:
		holder._cooldown = 0.0
		holder.fire()
		_fp_step(feel, holder, 4)
	var shells_on := 0
	for sh in feel._shell_pool:
		if sh["on"]:
			shells_on += 1
	_check(feel._shell_pool.size() > 0 and feel._shell_pool.size() <= feel.SHELLS and feel._tracer_pool.size() >= 1 and feel._tracer_pool.size() <= feel.TRACERS,
		"  shells and tracers are pooled (%d shells, %d tracers) and kept to their caps" % [feel._shell_pool.size(), feel._tracer_pool.size()])
	var lights := 0
	for l in player.find_children("*", "OmniLight3D", true, false):
		if String(l.name) == "MuzzleLight":
			lights += 1
	_check(lights == 1, "  one muzzle light, reused (%d)" % lights)

	# --- The slide: from a sprint only, about 0.8 s.
	feel.reset_state()
	player.velocity = Vector3(0, 0, -5.0)
	player.set("_sprinting", false)
	_check(not feel.try_slide(), "  no slide from a walk")
	player.set("_sprinting", true)
	var ok_slide: bool = feel.try_slide()
	var sprint_speed: float = player.BASE_SPEED * player.SPRINT_MULT
	var v0: float = feel.slide_velocity(1.0 / 120.0).length()
	var total := 1.0 / 120.0
	var v_end := v0
	while feel.sliding and total < 2.0:
		v_end = feel.slide_velocity(1.0 / 120.0).length()
		total += 1.0 / 120.0
	_check(ok_slide and absf(total - 0.8) < 0.04, "  a slide from a sprint lasts about 0.8 s (%.3f s)" % total)
	_check(absf(v0 - sprint_speed * 1.4) < sprint_speed * 0.05 and v_end < v0 * 0.5, "  it starts at 1.4x sprint speed and drops off (%.1f -> %.1f m/s, sprint %.1f)" % [v0, v_end, sprint_speed])
	feel.reset_state()
	player.set("_sprinting", true)
	player.velocity = Vector3(0, 0, -5.0)
	feel.try_slide()
	for i in 40:
		_fp_step(feel, holder, 1)
	_check(feel.eye_drop > 0.5 and feel.fov > hip_fov + 3.0, "  mid-slide the eye is down 0.6 m and the view widens (%.2f m, %.1f deg)" % [feel.eye_drop, feel.fov])
	player.set("_sprinting", false)
	feel.reset_state()
	player.velocity = Vector3.ZERO

	# --- Third person in the middle of aiming and reloading.
	holder.give(load("res://weapons/ar.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder.aiming = true
	_fp_step(feel, holder, 20)
	holder.mag = 3
	holder.aiming = false
	holder.reload()
	_fp_step(feel, holder, 20)
	holder.aiming = true
	_fp_step(feel, holder, 5)
	gfx.set_first_person(false)
	await _frames(8)
	var tp_cam: Camera3D = player.get("camera")
	_check(feel.ads == 0.0 and feel.recoil == Vector2.ZERO and not feel.sliding and holder.viewmodel == null,
		"  switching to third person mid-aim and mid-reload drops the sights, the recoil and the viewmodel")
	_check(absf(tp_cam.fov - player.get("_tp_fov")) < 1.0, "  and the camera has its third-person field of view back (%.1f vs %.1f)" % [tp_cam.fov, player.get("_tp_fov")])
	var still_reloading: bool = holder.reloading
	for i in int(holder.reload_left() * 120.0) + 10:
		holder.advance(1.0 / 120.0)
	_check(still_reloading and not holder.reloading and holder.mag == 30, "  the reload still finishes: the gun is loaded, not stuck (%d)" % holder.mag)
	gfx.set_first_person(true)
	await _frames(8)
	_check(holder.viewmodel != null and feel.ads == 0.0 and not holder.reloading and absf(player.get("camera").fov - hip_fov) < 2.0,
		"  back in first person everything is at the hip (viewmodel %s, ads %.2f, fov %.1f)" % [holder.viewmodel != null, feel.ads, player.get("camera").fov])

	# --- The viewmodel: depth shader on every surface, real arms, hands on the gun.
	var all_shader := true
	var bad := []
	var guns_ok := true
	for id in ["pistol", "smg", "shotgun", "ar", "sniper", "magnum", "lmg", "wonder", "pistol_up", "smg_up"]:
		var gv: Node3D = Viewmodel.new().setup(load("res://weapons/%s.tres" % id))
		for m in gv.materials():
			var is_shader: bool = m is ShaderMaterial and (m.shader == Viewmodel.SHADER or m.shader == Viewmodel.FX_SHADER or m.shader == Viewmodel.DOT_SHADER or m.shader == Viewmodel.GLASS_SHADER)
			if not is_shader:
				all_shader = false
				bad.append(id)
		for mi in gv.find_children("*", "MeshInstance3D", true, false):
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				all_shader = false
				bad.append(id + " shadow")
		guns_ok = guns_ok and gv.arms != null and gv.flash != null and gv.box.size.z > 0.1
		gv.free()
	_check(all_shader, "  every viewmodel surface (gun, arms, flash, props) uses the depth shader and casts no shadow (%s)" % [bad])
	var vmn: Node3D = holder.viewmodel
	var arm_meshes: Array = vmn.arms.find_children("*", "MeshInstance3D", true, false) if vmn.arms != null else []
	var arm_verts := 0
	for mi in arm_meshes:
		arm_verts += (mi as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	_check(guns_ok and arm_verts > 800 and vmn.arms.find_child("Skeleton3D", true, false) != null, "  every gun has skinned Rocketbox arms (%d vertices), a flash and a measured body" % arm_verts)
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	_fp_step(feel, holder, 4)
	feel.apply()
	vmn.aim_hands(vmn.grip_l)
	var skel: Skeleton3D = vmn.arms.find_child("Skeleton3D", true, false)
	var hand_bone := skel.find_bone("Bip01 R Hand")
	var hand_vm: Vector3 = (vmn.arms.transform * vmn._sk_in_arms) * skel.get_bone_global_pose(hand_bone).origin
	var hand_gap := hand_vm.distance_to(vmn.grip_r)
	_check(hand_gap < 0.09, "  the right hand is on the grip (wrist %.1f cm from it)" % (hand_gap * 100.0))
	var lhand_bone := skel.find_bone("Bip01 L Hand")
	var lhand_vm: Vector3 = (vmn.arms.transform * vmn._sk_in_arms) * skel.get_bone_global_pose(lhand_bone).origin
	_check(lhand_vm.distance_to(vmn.grip_l) < 0.12, "  and the left hand is on the foregrip (%.1f cm)" % (lhand_vm.distance_to(vmn.grip_l) * 100.0))

	# --- The first-person controls the mode adds.
	_check(InputMap.has_action("crouch") and InputMap.has_action("inspect"), "  crouch (slide) and inspect are bound in the mode")
	holder.give(load("res://weapons/pistol.tres"))
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	_check(feel.inspect() and feel.inspecting and feel.last_sound == "inspect", "  inspect turns the gun in the hands with a sound")
	_fp_step(feel, holder, 300)
	_check(not feel.inspecting, "  and ends by itself")
	feel.reset_state()
	player.velocity = Vector3.ZERO

	# --- The horde's cost (step 0): hit zones follow the animation when a ray needs them,
	# and a far zombie still gets there.
	gfx.set_first_person(false)
	await _frames(4)
	holder.aim_source = Callable()
	block.spawner.round_no = 1
	var far_z: Node = block.spawner.spawn_one("runner", Vector3(-60.0, 0.0, -1.0))
	player.global_position = Vector3(-20.0, 0, -1.0)
	player.velocity = Vector3.ZERO
	var d0: float = Vector2(far_z.global_position.x - player.global_position.x, far_z.global_position.z - player.global_position.z).length()
	for i in 150:
		await physics_frame
	var d1: float = Vector2(far_z.global_position.x - player.global_position.x, far_z.global_position.z - player.global_position.z).length()
	var want: float = far_z.speed * 150.0 / 60.0
	_check(d0 - d1 > want * 0.6, "  a zombie 40 m away (thinking every second tick) still closes in at its own pace (%.1f m in 2.5 s, speed %.1f)" % [d0 - d1, far_z.speed])
	var hb: Array = []
	far_z.set_physics_process(false)
	far_z._anim_player.pause()
	far_z.sync_hitboxes()
	var skl: Skeleton3D = far_z._skeleton
	var head_bone: Vector3 = (skl.global_transform * skl.get_bone_global_pose(skl.find_bone("Bip01 Head"))).origin
	var head_zone: Vector3 = (far_z.hitboxes["head"] as Node3D).global_position
	_check(head_zone.distance_to(head_bone) < 0.2, "  a hit zone sits on its bone when synced (head zone %.2f m from the head bone)" % head_zone.distance_to(head_bone))
	far_z.queue_free()
	gfx.set_first_person(true)
	await _frames(4)
	await _zombie_fp_look_checks(player, holder, feel, block)
	await _zombie_impact_checks(player, holder, feel, block)
	zm.leave()
	gs.start_run()


## Task Z4b stage (a): sights on the screen's centre, the red dot, sleeves and gloves, a painted
## shotgun, buy prompts only when you look at the thing, zombies that read in the dark.
func _zombie_fp_look_checks(player: Node, holder: Node, feel: Node, block: Node) -> void:
	var Viewmodel := load("res://player/Viewmodel.gd")
	var Hud := load("res://ui/ZombieHud.gd")
	# Aimed, the sight sits on the view's axis for every gun.
	var worst := 0.0
	var worst_id := ""
	var near_relief := true
	for id in ["pistol", "magnum", "smg", "ar", "lmg", "shotgun", "sniper", "wonder", "ar_up", "shotgun_up", "pistol_up"]:
		var vm: Node3D = Viewmodel.new().setup(load("res://weapons/%s.tres" % id))
		var p: Vector3 = vm.ads_position + Basis(Vector3.RIGHT, vm.ads_pitch) * vm.sight_point
		var off := Vector2(p.x, p.y).length()
		if off > worst:
			worst = off
			worst_id = id
		if p.z > -0.1 or p.z < -0.6:
			near_relief = false
		vm.free()
	_check(worst < 0.003, "  aimed, every gun's sight (rear sight or red dot) is on the screen's centre (worst %s %.1f mm)" % [worst_id, worst * 1000.0])
	_check(near_relief, "  at an eye relief between 10 and 60 cm")
	for id in ["ar", "smg"]:
		var vm: Node3D = Viewmodel.new().setup(load("res://weapons/%s.tres" % id))
		var dot := vm.optic.get_node_or_null("Dot") as Node3D if vm.optic != null else null
		_check(vm.has_optic and dot != null and (vm.optic.position + dot.position).distance_to(vm.sight_point) < 0.002,
			"  the %s wears a red dot with its dot on the sight line" % id)
		vm.free()
	var vm_p: Node3D = Viewmodel.new().setup(load("res://weapons/pistol.tres"))
	_check(not vm_p.has_optic and vm_p.optic == null, "  the pistol keeps its iron sights")
	# Sleeves and gloves: the arms carry a mask map and every arm material uses it.
	var arms_ok := true
	var glove := false
	var sleeve := false
	var tip := false
	for mi in vm_p.arms.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for sidx in m.mesh.get_surface_count():
			var mat := m.get_active_material(sidx) as ShaderMaterial
			if mat == null or mat.get_shader_parameter("arms") != true:
				arms_ok = false
			var uv2 = m.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_TEX_UV2]
			if uv2 == null or (uv2 as PackedVector2Array).size() < 800:
				arms_ok = false
				continue
			for uv in (uv2 as PackedVector2Array):
				glove = glove or uv.x > 0.9
				sleeve = sleeve or uv.y > 0.9
				tip = tip or (uv.x < 0.05 and uv.y < 0.05)
	_check(arms_ok and glove and sleeve and tip, "  the arms have sleeves, gloves and bare fingertips (mask: arms %s glove %s sleeve %s tip %s)" % [arms_ok, glove, sleeve, tip])
	vm_p.free()
	# The shotgun is a textured model, not plain grey.
	var vm_s: Node3D = Viewmodel.new().setup(load("res://weapons/shotgun.tres"))
	var textured := 0
	for mat in vm_s.materials():
		if mat is ShaderMaterial and mat.shader == Viewmodel.SHADER and mat.get_shader_parameter("use_tex") == true:
			textured += 1
	_check(textured >= 1, "  the shotgun has a textured (PBR) model (%d textured materials)" % textured)
	vm_s.free()
	# Buy prompts only when you are close and looking at the thing.
	var cam: Camera3D = player.get_viewport().get_camera_3d()
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var thing := Node3D.new()
	root.add_child(thing)
	thing.global_position = player.global_position + fwd * 1.5
	var in_front: bool = Hud.prompt_in_view(player, thing)
	thing.global_position = player.global_position - fwd * 1.5
	var behind: bool = Hud.prompt_in_view(player, thing)
	thing.global_position = player.global_position + fwd * 3.0
	var far_off: bool = Hud.prompt_in_view(player, thing)
	thing.global_position = player.global_position + fwd.rotated(Vector3.UP, deg_to_rad(80.0)) * 1.5
	var aside: bool = Hud.prompt_in_view(player, thing)
	thing.free()
	_check(in_front and not behind and not far_off and not aside,
		"  a buy prompt shows only within 2 m and in view (front %s, behind %s, 3 m %s, 80 deg aside %s)" % [in_front, behind, far_off, aside])
	# Zombies read in the dark: a rim and a lift in the rot shader.
	var z: Node = block.spawner.spawn_one("walker", player.global_position + fwd * 6.0)
	await _frames(2)
	var rim_ok := false
	for mi in z.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var mat := m.get_surface_override_material(0) as ShaderMaterial
		if mat != null and mat.shader != null and mat.shader.code.contains("rim_strength") and mat.shader.code.contains("body_lift"):
			rim_ok = true
	_check(rim_ok, "  a zombie wears a rim light and a body lift so it reads in the dark street")
	z.free()


## Task Z4b stage (b): per-zone damage, falloff, impacts, blood, hit reactions, shotgun knock-back,
## damage numbers (off by default), hit sounds.
func _zombie_impact_checks(player: Node, holder: Node, feel: Node, block: Node) -> void:
	var zmode := root.get_node("ZombieMode")
	var ImpactFX := load("res://fx/ImpactFX.gd")
	var pistol: Resource = load("res://weapons/pistol.tres")
	var ar: Resource = load("res://weapons/ar.tres")
	var shotgun: Resource = load("res://weapons/shotgun.tres")
	_check(pistol.head_mult >= 4.0 and ar.head_mult >= 4.0 and pistol.neck_mult >= 2.0 and ar.neck_mult >= 2.0 and pistol.torso_mult == 1.0 and absf(ar.limb_mult - 0.75) < 0.001,
		"  zone damage is COD-like: head x%.1f / neck x%.1f / torso x%.1f / limbs x%.2f (pistol, AR)" % [pistol.head_mult, pistol.neck_mult, pistol.torso_mult, ar.limb_mult])
	_check(ar.damage_at("torso", 5.0) > ar.damage_at("torso", 120.0) and pistol.damage_at("torso", 5.0) > pistol.damage_at("torso", 60.0) and shotgun.damage_at("torso", 2.0) > shotgun.damage_at("torso", 14.0) * 2.0,
		"  every gun loses damage with distance (shotgun %.0f at 2 m, %.0f at 14 m)" % [shotgun.damage_at("torso", 2.0), shotgun.damage_at("torso", 14.0)])
	_check(zmode.gore_enabled and not zmode.damage_numbers, "  gore is on and damage numbers are off by default")
	var yaw_dir := Vector3(-1, 0, 0)
	player.global_position = Vector3(-20, 0, -3)
	player.set_look(-PI / 2.0, 0.0)
	holder.no_spread = true
	block.spawner.round_no = 1
	await _frames(2)
	var z: Node = block.spawner.spawn_one("walker", Vector3(-24.0, 0.0, -3.0))
	z.set_physics_process(false)
	z._anim_player.pause()
	await _frames(2)
	holder.give(pistol)
	await _frames(2)
	holder._swap_left = 0.0
	holder.refill_all()
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	holder.aim_source = func():
		z.sync_hitboxes()
		var c: Vector3 = (z.hitboxes["torso"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	var fx0: Node3D = ImpactFX.of(holder)
	var puffs0: int = fx0.puffs
	var imp0: int = fx0.impacts
	holder._cooldown = 0.0
	holder.fire()
	await _frames(2)
	_check(z._flinch != null and z._flinch.busy(), "  a hit makes the zombie flinch (a kick on its skeleton)")
	_check(fx0.impacts > imp0 and fx0.puffs > puffs0, "  and spurts blood (%d new puffs)" % (fx0.puffs - puffs0))
	_check(fx0.voices_busy() >= 1, "  with the sound of it, at the zombie")
	# The head snaps further than the shoulder on a head shot.
	var skel: Skeleton3D = z._skeleton
	var hb := skel.find_bone("Bip01 Head")
	z.health = z.max_health
	z.take_hit("head", 10.0, yaw_dir, pistol, false, Vector3.INF)
	var before: Basis = skel.get_bone_global_pose(hb).basis
	z._flinch._process_modification()
	var after: Basis = skel.get_bone_global_pose(hb).basis
	_check((before.get_rotation_quaternion().angle_to(after.get_rotation_quaternion())) > 0.02 or z._flinch.busy(), "  a head shot kicks the head bone")
	# Bullets into the wall: a hole, sparks and grit, within the per-frame budget.
	holder.aim_source = func(): return [eye, Vector3(-0.75, -0.15, 0.65).normalized()]
	var dec0: int = fx0.decals_shown()
	holder.give(shotgun)
	await _frames(2)
	holder._swap_left = 0.0
	holder.refill_all()
	holder._cooldown = 0.0
	holder.fire()
	await _frames(2)
	var made: int = fx0.decals_shown() - dec0
	_check(made >= 1 and made <= ImpactFX.BUDGET["decal"], "  a shotgun blast into the wall leaves 1 to %d holes (%d)" % [ImpactFX.BUDGET["decal"], made])
	# Caps hold under 500 shots.
	var nodes0: int = fx0.get_child_count()
	holder.give(load("res://weapons/smg.tres"))
	await _frames(2)
	holder._swap_left = 0.0
	for i in 500:
		holder.mag = 30
		holder._cooldown = 0.0
		holder.fire()
		if i % 50 == 0:
			await _frames(1)
	_check(fx0.decals_shown() <= ImpactFX.DECALS and fx0.get_child_count() == nodes0,
		"  after 500 shots the holes stay within %d and no impact node was made (%d holes, %d -> %d children)" % [ImpactFX.DECALS, fx0.decals_shown(), nodes0, fx0.get_child_count()])
	# A shotgun at point-blank throws the zombie back; at range it does not.
	var zc: Node = block.spawner.spawn_one("walker", Vector3(-22.0, 0.0, -3.0))
	zc.set_physics_process(true)
	zc.target = null
	holder.give(shotgun)
	await _frames(2)
	holder._swap_left = 0.0
	holder.refill_all()
	holder.aim_source = func():
		zc.sync_hitboxes()
		var c: Vector3 = (zc.hitboxes["torso"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	holder._cooldown = 0.0
	zc.health = 99999.0
	var kn0: float = zc._knock.length()
	holder.fire()
	var kn1: float = zc._knock.length()
	_check(kn1 > kn0 + 1.0, "  a shotgun blast at 2 m shoves the zombie (%.1f m/s)" % kn1)
	zc.queue_free()
	var zf: Node = block.spawner.spawn_one("walker", Vector3(-34.0, 0.0, -3.0))
	zf.set_physics_process(false)
	holder.aim_source = func():
		zf.sync_hitboxes()
		var c: Vector3 = (zf.hitboxes["torso"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	holder._cooldown = 0.0
	holder.fire()
	_check(zf._knock.length() < 0.01, "  and at 14 m it does not")
	zf.queue_free()
	# Damage numbers only when asked.
	holder.give(pistol)
	await _frames(2)
	holder._swap_left = 0.0
	holder.refill_all()
	holder.aim_source = func():
		z.sync_hitboxes()
		var c: Vector3 = (z.hitboxes["torso"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	z.health = 99999.0
	holder._cooldown = 0.0
	var fired_ok: bool = holder.fire()
	await _frames(1)
	var off_shown: int = fx0.numbers_shown()
	zmode.damage_numbers = true
	z.health = z.max_health
	holder._cooldown = 0.0
	holder.fire()
	await _frames(1)
	var on_shown: int = fx0.numbers_shown()
	zmode.damage_numbers = false
	_check(fired_ok and off_shown == 0 and on_shown >= 1, "  damage numbers float only when the option is on (fired %s, off %d, on %d)" % [fired_ok, off_shown, on_shown])
	holder.aim_source = Callable()
	z.queue_free()
	# The sounds the above plays all exist.
	var missing := []
	for n in ["flesh_hit_1", "flesh_hit_2", "flesh_hit_3", "headshot_crunch_1", "headshot_crunch_2", "bullet_impact_concrete_1", "ricochet_1", "kill_thump", "sever_1", "gib_splat_1", "head_pop_1", "blood_squirt_1"]:
		if ImpactFX.stream(n) == null:
			missing.append(n)
	_check(missing.is_empty(), "  every hit / gore sound loads (%s missing)" % [missing])


## Task Z6: gore. Wounds, limbs off at their own thresholds, stumps, gibs, the head pop, legless crawlers,
## decals and pools within their caps, one payout for a blast that takes several parts, no orphans, the option.
func _zombie_gore_checks(gs: Node) -> void:
	await _section("Dead Block: gore -- wounds, severed limbs, head pops, decals, pools, the option")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gfx := root.get_node("Graphics")
	zm.leave()
	zm.begin(false)
	zm.gore_enabled = true
	var city := await _load("res://world/City3D.tscn")
	var block: Node = city.get_node_or_null("ZombieBlock")
	for i in 90:
		if block != null and block.purchases_ready:
			break
		await physics_frame
	await _frames(5)
	block.spawner.enabled = false
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player := _player()
	var holder: Node = player.get_node("WeaponHolder")
	holder.set_process(false)
	holder.no_spread = true
	gfx.set_first_person(true)
	player.global_position = Vector3(-20, 0, -3)
	player.set_look(-PI / 2.0, 0.0)
	await _frames(4)
	var Gore := load("res://fx/gore/Gore.gd")
	var gore: Node3D = Gore.of(holder)
	block.spawner.round_no = 1
	var mk := func(x: float) -> Node:
		var z: Node = block.spawner.spawn_one("walker", Vector3(x, 0.0, -3.0))
		z.set_physics_process(false)
		z._anim_player.pause()
		z.health = 100000.0
		z.max_health = 150.0
		return z
	# Each limb comes off at its own threshold, and only that limb.
	var z1: Node = mk.call(-24.0)
	await _frames(2)
	z1.take_hit("lower_arm_l", 150.0 * 0.12, Vector3.LEFT, null)
	_check(z1.severed.is_empty() and z1.wounds_placed >= 1, "  a graze wounds the skin and keeps the limb (%d wound(s), severed %s, body %s)" % [z1.wounds_placed, z1.severed.keys(), z1.get_meta("body")])
	var g0: int = gore.gibs.spawned
	z1.take_hit("lower_arm_l", 150.0 * 0.20, Vector3.LEFT, null)
	_check(z1.severed.has("forearm_l") and not z1.severed.has("forearm_r") and not z1.severed.has("arm_l") and gore.gibs.spawned == g0 + 1,
		"  the forearm comes off at 30%% of the zombie's health and nothing else does (%s, %d gib, body %s)" % [z1.severed.keys(), gore.gibs.spawned - g0, z1.get_meta("body")])
	_check((z1.sever_bits & (1 << 4)) != 0 and z1._skeleton.find_child("Stump_forearm_l", true, false) != null,
		"  its triangles are clipped from the skin and a stump closes the cut")
	_check((z1.hitboxes["lower_arm_l"] as Area3D).collision_layer == 0 and (z1.hitboxes["upper_arm_l"] as Area3D).collision_layer != 0, "  and only its hit zone is gone")
	z1.take_hit("upper_arm_r", 150.0 * 0.30, Vector3.LEFT, null)
	_check(not z1.severed.has("arm_r"), "  an upper arm takes more than a forearm (42%%): 30%% leaves it")
	z1.take_hit("upper_arm_r", 150.0 * 0.20, Vector3.LEFT, null)
	_check(z1.severed.has("arm_r") and z1.severed.has("forearm_r"), "  and it takes the forearm with it")
	# Both legs: it crawls.
	var z2: Node = mk.call(-26.0)
	await _frames(2)
	z2.take_hit("lower_leg_l", 150.0 * 0.4, Vector3.LEFT, null)
	_check(z2.severed.has("shin_l") and not z2.legless, "  one leg gone: it kneels but is not yet a crawler")
	z2.take_hit("upper_leg_r", 150.0 * 0.55, Vector3.LEFT, null)
	_check(z2.legless and z2.severed.has("leg_r"), "  both legs gone: legless")
	z2.state = z2.State.CHASE
	z2.set_physics_process(true)
	z2.target = player
	await _frames(20)
	_check(z2._anim_player.current_animation.contains("crawl"), "  and it plays the crawl clip (%s)" % z2._anim_player.current_animation)
	z2.queue_free()
	# A lethal headshot with a heavy hit takes the head off and the neck spurts.
	var z3: Node = mk.call(-28.0)
	await _frames(2)
	z3.health = 100.0
	var gh: int = gore.gibs.spawned
	z3.take_hit("head", 150.0 * 0.9, Vector3.LEFT, null)
	await _frames(2)
	_check(z3.head_gone and z3.severed.has("head") and gore.gibs.spawned == gh + 1 and gore.fountains_active() >= 1 and z3._skeleton.find_child("Stump_head", true, false) != null,
		"  a heavy headshot pops the head: stump, gib in the air, neck fountain (%d active)" % gore.fountains_active())
	_check(gore.gibs.chunks_spawned >= 3 and gore.gibs.chunks_spawned <= 5 and gore.gibs.chunks_shown() >= 3, "  with 3 to 5 chunks of skull and flesh thrown with it (%d)" % gore.gibs.chunks_spawned)
	var d_before: int = gore.decals_shown()
	for i in 90:
		await physics_frame
	_check(gore.decals_shown() > d_before, "  and the neck's arcs come down as blood on the ground (%d -> %d decals)" % [d_before, gore.decals_shown()])
	var z3b: Node = mk.call(-30.0)
	await _frames(2)
	z3b.health = 30.0
	z3b.take_hit("head", 40.0, Vector3.LEFT, null)
	_check(z3b.is_alive() == false and not z3b.head_gone, "  a light headshot that kills leaves the head on")
	# Wounds: two on a zombie, the skin shader reads them.
	var z4: Node = mk.call(-32.0)
	await _frames(2)
	z4.take_hit("torso", 30.0, Vector3.LEFT, null)
	await _frames(1)
	z4.take_hit("torso", 30.0, Vector3.LEFT, null)
	var inst: MeshInstance3D = load("res://fx/gore/GoreRig.gd").body_mesh(z4._skeleton)
	var wa: Vector4 = inst.get_instance_shader_parameter("wound_a")
	var wb: Vector4 = inst.get_instance_shader_parameter("wound_b")
	_check(wa.z > 0.0 and wb.z > 0.0 and z4.wounds_placed >= 2, "  two wounds are painted into the skin (%s, %s)" % [wa, wb])
	# Blood decals exist and the corpse pool spreads when it settles.
	var d0: int = gore.decals_shown()
	z4.take_hit("torso", 150.0 * 0.5, Vector3.LEFT, null, false, z4.global_position + Vector3(0, 1.2, 0))
	z4.health = 5.0
	z4.take_hit("torso", 50.0, Vector3.LEFT, null)
	for i in 240:
		await physics_frame
	_check(gore.decals_shown() >= d0 and gore.pools_shown() >= 1, "  blood lands on the ground and a pool spreads under the corpse (%d decals, %d pools)" % [gore.decals_shown(), gore.pools_shown()])
	# One shotgun blast that takes several parts and kills pays once.
	var shotgun: Resource = load("res://weapons/shotgun.tres")
	holder.give(shotgun)
	await _frames(2)
	holder._swap_left = 0.0
	holder.refill_all()
	var z5: Node = block.spawner.spawn_one("walker", Vector3(-22.0, 0.0, -3.0))
	z5.health = 85.0
	z5.set_physics_process(false)
	z5._anim_player.pause()
	z5.target = player
	await _frames(2)
	var eye: Vector3 = player.global_position + Vector3(0, 1.62, 0)
	holder.aim_source = func():
		z5.sync_hitboxes()
		var c: Vector3 = (z5.hitboxes["upper_leg_l"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	var k0: int = zm.kills
	zm.points = 0
	var s0: int = gore.severs
	holder._cooldown = 0.0
	holder.fire()
	await _frames(2)
	_check(zm.kills - k0 == 1 and zm.points <= 110 and zm.points >= 60, "  a shotgun blast that kills pays once (%d kill, %d points)" % [zm.kills - k0, zm.points])
	_check(gore.severs > s0, "  and it took parts off (%d severs)" % (gore.severs - s0))
	holder.aim_source = Callable()
	# Caps hold, no orphans: a crowd of zombies with every limb off.
	var orphans0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var crowd := []
	for i in 14:
		var zc: Node = mk.call(-40.0 - i * 1.2)
		crowd.append(zc)
	await _frames(2)
	for zc in crowd:
		for limb in ["head", "arm_l", "arm_r", "forearm_l", "leg_l", "leg_r", "shin_r"]:
			gore.sever(zc, limb, Vector3.LEFT)
		zc.take_hit("torso", 1.0e6, Vector3.LEFT, null)
	for i in 5:
		await physics_frame
	for i in 600:
		for zc in crowd:
			if is_instance_valid(zc):
				gore.splat(zc.global_position, Vector3.UP, 0.5)
		if i % 20 == 0:
			await physics_frame
	_check(gore.gibs.shown() <= 24 and gore.decals_shown() <= 80 and gore.pools_shown() <= 12,
		"  caps hold: %d gibs of 24, %d blood decals of 80, %d pools of 12" % [gore.gibs.shown(), gore.decals_shown(), gore.pools_shown()])
	for zc in crowd:
		if is_instance_valid(zc):
			zc.free()
	await _frames(3)
	var orphans1: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans1 <= orphans0 + 2, "  no orphan nodes are left behind (%d -> %d)" % [orphans0, orphans1])
	# Ragdolls: ten at once, six running, the rest stopped where they lay; all frozen and freed after 3 s.
	var rg: Node = gore.ragdolls
	var rz := []
	for i in 10:
		rz.append(mk.call(-30.0 - i * 1.0))
	await _frames(2)
	var hb: int = rz[9]._skeleton.find_bone("Bip01 Head")
	var head_y0: float = _rag_head_y(rz[9], hb)
	for q in rz:
		gore.ragdoll(q, Vector3.LEFT, 4.0)
	_check(rg.started >= 10 and rg.active() <= 6, "  ten ragdolls start, no more than six run at once (%d running)" % rg.active())
	for i in 45:
		await physics_frame
	rz[9]._skeleton.advance(0.0)
	var head_y1: float = _rag_head_y(rz[9], hb)
	_check(head_y0 > 1.2 and head_y1 < head_y0 - 0.4, "  and the body drops: its head from %.2f m to %.2f m" % [head_y0, head_y1])
	var rag_node := (rz[9] as Node).find_child("Ragdoll", false, false)
	_check(rag_node != null and rag_node.get_child_count() > 8, "  it is ten bodies and their joints while it runs (%d nodes)" % (rag_node.get_child_count() if rag_node != null else 0))
	for i in 230:
		await physics_frame
	_check(rg.active() == 0 and rag_node.get_child_count() == 0, "  after 3 s every one is frozen and its bodies are freed (%d running, %d nodes)" % [rg.active(), rag_node.get_child_count()])
	rz[9]._skeleton.advance(0.0)
	var head_y2: float = _rag_head_y(rz[9], hb)
	_check(absf(head_y2 - head_y1) < 0.6 and head_y2 < 1.0, "  and the pose is held (head at %.2f m)" % head_y2)
	for q in rz:
		q.free()
	await _frames(2)
	# 500 shots with ragdolls on: 200 into zombies (each dies on its fifth and falls), 300 into the wall.
	var smg: Resource = load("res://weapons/smg.tres")
	holder.give(smg)
	await _frames(2)
	holder._swap_left = 0.0
	var tgt := [null]
	var nodes_g: int = gore.get_child_count()
	var rag0: int = rg.started
	var kills0: int = zm.kills
	var max_active := 0
	var shots_fired := 0
	holder.aim_source = func():
		var t = tgt[0]
		if t == null or not is_instance_valid(t):
			return [eye, Vector3(-0.75, -0.15, 0.65).normalized()]
		t.sync_hitboxes()
		var c: Vector3 = (t.hitboxes["torso"].get_child(0) as Node3D).global_position
		return [eye, c - eye]
	for n in 40:
		var vz: Node = block.spawner.spawn_one("walker", Vector3(-22.0 - (n % 5) * 0.9, 0.0, -3.0 + (n % 3) * 0.5))
		vz.set_physics_process(false)
		vz._anim_player.pause()
		vz.health = 135.0
		vz.max_health = 150.0
		vz.target = player
		tgt[0] = vz
		for k in 5:
			holder.mag = 30
			holder._cooldown = 0.0
			if holder.fire():
				shots_fired += 1
		max_active = maxi(max_active, rg.active())
		await physics_frame
	tgt[0] = null
	for i in 300:
		holder.mag = 30
		holder._cooldown = 0.0
		if holder.fire():
			shots_fired += 1
		if i % 25 == 0:
			await physics_frame
			max_active = maxi(max_active, rg.active())
	for i in 200:
		await physics_frame
	var fx_n: Node3D = get_first_node_in_group("impact_fx")
	_check(shots_fired >= 480 and rg.started - rag0 >= 25 and zm.kills - kills0 >= 25, "  500 shots: %d fired, %d fell as ragdolls, %d kills" % [shots_fired, rg.started - rag0, zm.kills - kills0])
	_check(max_active <= 6 and rg.active() == 0 and block.spawner.corpse_count() <= 12, "  at most 6 ragdolls ran at once (%d), all froze, corpses %d <= 12" % [max_active, block.spawner.corpse_count()])
	_check(gore.get_child_count() == nodes_g and gore.decals_shown() <= 80 and gore.gibs.shown() <= 24 and gore.pools_shown() <= 12 and fx_n.decals_shown() <= 48,
		"  and the caps hold (gore children %d -> %d, %d blood decals, %d gibs, %d pools, %d holes)" % [nodes_g, gore.get_child_count(), gore.decals_shown(), gore.gibs.shown(), gore.pools_shown(), fx_n.decals_shown()])
	holder.aim_source = Callable()
	# Screen blood.
	gore.screen_blood(1.0)
	_check(gore.screen.shown() >= 1, "  a claw leaves blood on the screen")
	# The option: gore off means no severs, no decals, no wounds, but the kills still count.
	zm.gore_enabled = false
	var sv: int = gore.severs
	var dc: int = gore.decals_shown()
	var wd: int = gore.wounds
	var z6: Node = mk.call(-22.0)
	await _frames(2)
	z6.take_hit("lower_arm_l", 150.0 * 0.5, Vector3.LEFT, null)
	z6.take_hit("torso", 20.0, Vector3.LEFT, null)
	var k1: int = zm.kills
	z6.health = 5.0
	z6.take_hit("head", 500.0, Vector3.LEFT, null)
	await _frames(3)
	var before_shown: int = gore.screen.shown()
	gore.screen_blood(1.0)
	_check(gore.severs == sv and gore.decals_shown() == dc and gore.wounds == wd and z6.severed.is_empty() and not z6.head_gone and gore.screen.shown() == before_shown,
		"  with gore off nothing is cut, painted or splattered")
	_check(not z6.is_alive() and zm.kills == k1 + 1, "  and the kill still counts")
	zm.gore_enabled = true
	gfx.set_first_person(true)
	await _frames(4)
	zm.leave()
	gs.start_run()


## Where the ragdoll puts the head bone (the world transform its modifier last used).
func _rag_head_y(z: Node, head_bone: int) -> float:
	for c in z._skeleton.get_children():
		if c.get("entries") != null:
			for e in c.entries:
				if int(e["bone"]) == head_bone:
					return (e["held"] as Transform3D).origin.y
	return (z._skeleton.global_transform * z._skeleton.get_bone_global_pose(head_bone)).origin.y

# --- Dead Block: the bigger horde, its entrances and the Richter 8.0 surge (task Z4c) -------------

func _zombie_horde_checks(gs: Node) -> void:
	await _section("Dead Block: bigger horde -- adaptive cap, round sizes, entrances all round, the surge")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	DirAccess.remove_absolute(zm.PATH)
	var Budget := preload("res://npc/HordeBudget.gd")
	var EntrancesScript := preload("res://npc/Entrances.gd")

	# --- The adaptive cap (pure logic, made-up frame times) ---
	var b = Budget.new(32, zm.MAX_ALIVE_MIN, zm.MAX_ALIVE_MAX)
	_check(zm.MAX_ALIVE_MIN == 24 and zm.MAX_ALIVE_MAX == 48 and b.cap == 32, "  the cap starts at 32 inside 24..48")
	var lo := 99
	var hi := 0
	for i in 60 * 90:
		b.feed(16.0, b.cap, 1.0 / 60.0)
		lo = mini(lo, b.cap)
		hi = maxi(hi, b.cap)
	_check(b.cap == 48 and lo >= 32 and hi == 48, "  60 fps with the horde at its cap: climbs to 48 and no further (cap %d)" % b.cap)
	var floor_seen := 99
	for i in 60 * 30:
		b.feed(40.0, b.cap, 1.0 / 60.0)
		floor_seen = mini(floor_seen, b.cap)
	_check(b.cap == 24 and floor_seen == 24, "  25 fps (40 ms): drops to 24 and never below (cap %d)" % b.cap)
	# Hysteresis: after a drop it holds, then needs two good windows in a row.
	var b2 = Budget.new(40, 24, 48)
	for i in 60 * 3 + 5:
		b2.feed(40.0, 40, 1.0 / 60.0)
	var after_drop: int = b2.cap
	var climbed_at := -1.0
	for i in 60 * 40:
		if b2.feed(15.0, b2.cap, 1.0 / 60.0) and climbed_at < 0.0:
			climbed_at = i / 60.0
	_check(after_drop == 36 and climbed_at >= 8.9, "  after a drop it holds, then climbs only after two good windows (cap %d, first climb at %.1f s)" % [after_drop, climbed_at])
	var b3 = Budget.new(32, 24, 48)
	for i in 60 * 60:
		b3.feed(20.2, b3.cap, 1.0 / 60.0)
	_check(b3.cap == 32 and b3.raised == 0 and b3.lowered == 0, "  the middle band (20 ms) does not move it (cap %d)" % b3.cap)
	var b4 = Budget.new(32, 24, 48)
	for i in 60 * 30:
		b4.feed(16.0, 10, 1.0 / 60.0)
	_check(b4.cap == 32, "  it does not climb while the horde is nowhere near the cap (cap %d)" % b4.cap)
	var b5 = Budget.new(32, 24, 48)
	for i in 60 * 30:
		b5.feed(900.0 if i % 90 == 0 else 16.0, b5.cap, 1.0 / 60.0)
	_check(b5.lowered == 0 and b5.cap >= 32, "  a load hitch (900 ms) is not the horde's doing (cap %d)" % b5.cap)
	var b6 = Budget.new(32, 24, 48)
	for i in 60 * 30:
		b6.feed(50.0 if i % 8 == 0 else 14.0, b6.cap, 1.0 / 60.0)
	_check(b6.cap < 32, "  a steady stutter (1 frame in 8 over 33 ms) lowers it (cap %d)" % b6.cap)

	# --- Round sizes: 2.5x ---
	var old := [6, 8, 13, 18, 24]
	var sizes: Array = [1, 2, 3, 4, 5].map(func(r): return zm.zombies_in_round(r))
	var ratio_ok := true
	for i in 5:
		ratio_ok = ratio_ok and absf(float(sizes[i]) / float(old[i]) - 2.5) < 0.12
	_check(sizes[0] == 15 and ratio_ok, "  rounds 1..5 come to %s: 15 in round 1, 2.5x the first design" % [sizes])
	_check(zm.zombies_in_round(6) > sizes[4] and zm.zombies_in_round(20) > zm.zombies_in_round(10), "  and it keeps rising (r6 %d, r10 %d, r20 %d)" % [zm.zombies_in_round(6), zm.zombies_in_round(10), zm.zombies_in_round(20)])

	# --- The block ---
	zm.begin(false)
	var city := await _load("res://world/City3D.tscn")
	await _frames(8)
	var block := city.get_node("ZombieBlock")
	var spawner: Node = block.spawner
	var surge: Node = block.surge
	spawner.enabled = false
	spawner.adaptive = false
	surge.enabled = true
	for old_z in get_nodes_in_group("zombies"):
		old_z.free()
	_check(spawner.GAP_BASE <= 1.2 and spawner.GAP_MIN <= 0.25, "  spawn gaps are shorter (%.2f s base, %.2f s min)" % [spawner.GAP_BASE, spawner.GAP_MIN])
	var player := _player()
	var ent = spawner.entrances
	_check(ent.manholes.size() >= 5 and ent.escapes.size() >= 10 and ent.shops.size() >= 15,
		"  the block's entrances are found: %d manholes, %d fire escapes, %d shop fronts" % [ent.manholes.size(), ent.escapes.size(), ent.shops.size()])

	# --- Entrance points: valid on the navmesh, and all round the player ---
	player.global_position = Vector3(0.0, 0.0, -45.0)
	player.velocity = Vector3.ZERO
	await _frames(3)
	var cam := player.get_viewport().get_camera_3d()
	var from: Vector3 = player.global_position
	var bad := []
	var by_type := {"rise": 0, "drop": 0, "smash": 0, "plain": 0}
	var sectors := {}
	var min_d := 999.0
	var plain_seen := 0
	var roofs := 0
	var manhole_rises := 0
	for i in 400:
		var e: Dictionary = ent.pick(from, cam)
		by_type[e["type"]] += 1
		sectors[ent.sector_of(e["pos"], from, cam)] = true
		if not ent.on_navmesh(e["pos"], 0.4):
			bad.append("%s off the navmesh at %s" % [e["type"], e["pos"]])
		if not ent.is_clear(e["pos"]):
			bad.append("%s inside something solid at %s" % [e["type"], e["pos"]])
		var d := Vector2(e["pos"].x - from.x, e["pos"].z - from.z).length()
		if e["type"] == "plain":
			plain_seen += 1
			var head: Vector3 = e["pos"] + Vector3.UP
			if not (cam.is_position_behind(head) or not cam.is_position_in_frustum(head)):
				var q := PhysicsRayQueryParameters3D.create(cam.global_position, head)
				q.collision_mask = 1
				if city.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					bad.append("plain spawn in plain view at %s" % [e["pos"]])
			if d < 20.0:
				bad.append("plain spawn %.1f m away" % d)
		else:
			min_d = minf(min_d, d)
			if d < 8.0 or d > 58.5:
				bad.append("%s %.1f m away" % [e["type"], d])
		if e["type"] == "drop":
			roofs += 1 if e["roof"] else 0
			if e["start"].y < 3.0 or e["fall"] < 0.5:
				bad.append("drop from %.1f m" % e["start"].y)
		if e["type"] == "smash" and Vector2(e["start"].x - e["pos"].x, e["start"].z - e["pos"].z).length() > 3.2:
			bad.append("smash start far from landing")
		if e["type"] == "rise" and e["node"] != null:
			manhole_rises += 1
	_check(bad.is_empty(), "  400 entrances: all on the navmesh and clear of solids, shown ones 8..58 m off, hidden ones out of sight and 20+ m (%s)" % [bad.slice(0, 3)])
	_check(by_type["rise"] > 40 and by_type["drop"] > 20 and by_type["smash"] > 20 and by_type["plain"] > 20,
		"  all four kinds come: %s (roof drops %d, manhole rises %d)" % [by_type, roofs, manhole_rises])
	_check(sectors.size() >= 7, "  from %d of 8 eighths of the compass round the player" % sectors.size())
	# Facing north at a corner of the map still gets hits all round (those that have ground).
	var ring := {}
	for ang in [0.0, 90.0, 180.0, 270.0]:
		var q2 := {}
		player.global_position = Vector3(-40.0, 0.0, -45.0) if ang == 0.0 else Vector3(40.0, 0.0, -45.0) if ang == 90.0 else Vector3(0.0, 0.0, -20.0) if ang == 180.0 else Vector3(0.0, 0.0, -70.0)
		var p0: Vector3 = player.global_position
		for i in 120:
			q2[ent.sector_of(ent.pick(p0, cam)["pos"], p0, cam)] = true
		ring[ang] = q2.size()
	_check(ring.values().all(func(n): return n >= 5), "  and from other spots too, never down one street (sectors hit %s)" % [ring])
	player.global_position = from

	# --- A spawner uses them ---
	spawner.enabled = true
	spawner.time_scale = 0.01
	spawner.round_no = 1
	spawner.total = 40
	spawner.released = 0
	spawner._kinds = spawner._plan_kinds(1, 40)
	spawner._timer = 0.0
	surge.enabled = false
	zm.max_alive = 48
	var kinds_out := {}
	var spawned_now := []
	var on_spawn := func(zz): spawned_now.append(zz)
	spawner.spawned.connect(on_spawn)
	var f := 0
	while spawner.released < 40 and f < 2000:
		await physics_frame
		f += 1
		for zz in get_nodes_in_group("zombies"):
			zz.set_physics_process(false)
	spawner.enabled = false
	spawner.spawned.disconnect(on_spawn)
	for zz in spawned_now:
		kinds_out[zz.entrance] = int(kinds_out.get(zz.entrance, 0)) + 1
	_check(spawner.released == 40 and spawner.alive() == 40 and kinds_out.size() >= 3,
		"  a round's dead come by several ways (%s)" % [kinds_out])
	for zz in get_nodes_in_group("zombies"):
		zz.free()

	# --- The ways in, one by one ---
	var fx = preload("res://fx/EntranceFX.gd").of(city)
	var cr0: int = fx.cracks_made
	player.global_position = Vector3(0.0, 0.0, -45.0)
	var land: Vector3 = ent.snap(Vector3(-8.0, 0.0, -1.5))
	var zr = spawner.spawn_entrance("walker", {"type": "rise", "pos": land, "start": land + Vector3(0, -2.1, 0), "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false})
	await physics_frame
	_check(zr.state == zr.State.ENTER and zr._model_root.position.y < -1.5 and zr.collision_layer == 0 and fx.bursts >= 1 and fx.cracks_made > cr0,
		"  a rise starts under the street (%.1f m), no collision, with a ground burst and a crack" % zr._model_root.position.y)
	await _frames(60)
	var mid_y: float = zr._model_root.position.y
	_check(zr.state == zr.State.ENTER and mid_y > -1.9 and mid_y < -0.1, "  ...climbs out (%.2f m after a second)" % mid_y)
	await _frames(70)
	_check(zr.state != zr.State.ENTER and absf(zr._model_root.position.y) < 0.01 and zr.collision_layer == zr.BODY_LAYER and absf(zr.global_position.y) < 0.2,
		"  ...and is a zombie on the street (state %d, y %.2f)" % [zr.state, zr.global_position.y])
	zr.free()
	# Shot while climbing: no corpse half under the street.
	var zk = spawner.spawn_entrance("walker", {"type": "rise", "pos": land, "start": land + Vector3(0, -2.1, 0), "out": Vector3.FORWARD, "fall": 0.0, "node": null, "roof": false})
	await _frames(20)
	zk.take_hit("torso", 1.0e6, Vector3.FORWARD, null)
	_check(not zk.is_alive() and absf(zk._model_root.position.y) < 0.01, "  killed while climbing out it lies on the street, not under it")
	zk.free()
	var esc: Dictionary = ent.escapes[0]
	var drop_e := {}
	for i in 60:
		var cand: Dictionary = ent._candidates("drop", esc["pos"] + esc["out"] * 14.0, cam).pop_back() if not ent._candidates("drop", esc["pos"] + esc["out"] * 14.0, cam).is_empty() else {}
		if not cand.is_empty():
			drop_e = cand
			break
	_check(not drop_e.is_empty(), "  a drop site is found near the first fire escape")
	if not drop_e.is_empty():
		var zd = spawner.spawn_entrance("runner", drop_e)
		await physics_frame
		var y0: float = zd.global_position.y
		await _frames(int(drop_e["fall"] * 60.0 * 0.5))
		var y_half: float = zd.global_position.y
		await _frames(int(drop_e["fall"] * 60.0) + 12)
		_check(y0 > 3.0 and y_half < y0 - 0.5 and y_half > 0.1 and zd.state != zd.State.ENTER and zd.global_position.distance_to(drop_e["pos"]) < 3.5 and absf(zd.global_position.y) < 0.2 and fx.landings >= 1,
			"  a drop falls from %.1f m (%.1f halfway), lands on its spot and the landing is shown" % [y0, y_half])
		zd.free()
	var sm: Dictionary = {}
	for c in ent._candidates("smash", from, cam):
		sm = c
		break
	if not sm.is_empty():
		var zs = spawner.spawn_entrance("runner", sm)
		var p_start: Vector3 = zs.global_position
		await _frames(30)
		var moved: float = Vector2(zs.global_position.x - p_start.x, zs.global_position.z - p_start.z).length()
		_check(fx.smashes >= 1 and moved > 1.0 and zs.state != zs.State.ENTER, "  a smash shoves it out through the shop front (%.1f m in half a second) with glass" % moved)
		zs.free()
	_check(fx.visible_cracks() >= 1 and fx.visible_cracks() <= fx.CRACKS, "  cracks are pooled (%d of %d showing)" % [fx.visible_cracks(), fx.CRACKS])

	# --- The surge ---
	spawner.round_no = 0
	spawner.enabled = true
	surge.enabled = true
	surge.time_scale = 0.02
	zm.round = 4
	var log := []
	var w := func(): log.append("warning")
	var s := func(): log.append("started")
	var e_ := func(): log.append("ended")
	zm.surge_warning.connect(w)
	zm.surge_started.connect(s)
	zm.surge_ended.connect(e_)
	var base_pts: int = zm.points
	zm.add_points(10, "t")
	var normal_pay: int = zm.points - base_pts
	var made := []
	var on_surge := func(zz): made.append(zz)
	surge.spawned.connect(on_surge)
	_check(surge.trigger(32) and zm.surge_busy and not zm.surge_active and surge.phase == surge.Phase.WARNING, "  trigger(): the warning first, no double points yet")
	_check(not surge.trigger(10), "  ...and not another while one is on")
	var pay_warn: int = zm.points
	zm.add_points(10, "t")
	var warn_pay: int = zm.points - pay_warn
	var double_seen := false
	var max_alive_seen := 0
	var f2 := 0
	while zm.surge_busy and f2 < 4000:
		await physics_frame
		f2 += 1
		for zz in get_nodes_in_group("zombies"):
			zz.set_physics_process(false)
		max_alive_seen = maxi(max_alive_seen, spawner.alive())
		if zm.surge_active and not double_seen:
			var p1: int = zm.points
			zm.add_points(10, "t")
			double_seen = zm.points - p1 == 20
	_check(log == ["warning", "started", "ended"], "  the signals come in order: %s" % [log])
	_check(normal_pay == 10 and warn_pay == 10 and double_seen, "  points: 10 normally and in the warning, 20 in the quake")
	var runners := 0
	var types := {}
	for zz in made:
		runners += 1 if zz.kind == "runner" else 0
		types[zz.entrance] = int(types.get(zz.entrance, 0)) + 1
	_check(made.size() == 32 and spawner.alive() == 32, "  the surge let out exactly 32 (%d, alive %d)" % [made.size(), spawner.alive()])
	_check(runners >= 24 and runners <= 27, "  mostly runners (%d of 32)" % runners)
	var from_ground_air := int(types.get("rise", 0)) + int(types.get("drop", 0)) + int(types.get("smash", 0))
	_check(from_ground_air >= 26 and types.size() >= 3, "  from the ground, the fire escapes and the shop fronts (%s)" % [types])
	_check(surge.entrance_counts.size() >= 3 and max_alive_seen <= zm.SURGE_HARD_CAP, "  hard cap respected (peak %d of %d)" % [max_alive_seen, zm.SURGE_HARD_CAP])
	_check(zm.surge_active and not zm.surge_busy, "  after the last one is out the round may end, double points linger")
	var f3 := 0
	while zm.surge_active and f3 < 2000:
		await physics_frame
		f3 += 1
	var p2: int = zm.points
	zm.add_points(10, "t")
	_check(not zm.surge_active and zm.points - p2 == 10 and surge.phase == surge.Phase.IDLE, "  and then single points again")
	_check(surge.next_round - zm.round >= 3 and surge.next_round - zm.round <= 4 and surge.last_round == zm.round,
		"  the next one is 3 or 4 rounds on (round %d -> %d)" % [zm.round, surge.next_round])
	zm.surge_warning.disconnect(w)
	zm.surge_started.disconnect(s)
	zm.surge_ended.disconnect(e_)
	surge.spawned.disconnect(on_surge)
	for zz in get_nodes_in_group("zombies"):
		zz.free()

	# --- When it comes ---
	spawner.round_no = 0
	var sch := 0
	surge.next_round = 3
	surge.last_round = -99
	surge.plan_in = -1.0
	surge._on_round_started(1)
	var none_r1: bool = surge.plan_in < 0.0 and surge.next_round >= 3 and surge.next_round <= 4
	surge.next_round = 3
	surge._on_round_started(3)
	var planned_r3: bool = surge.plan_in >= 0.0
	surge.plan_in = -1.0
	var randoms := 0
	for i in 400:
		surge.plan_in = -1.0
		surge.next_round = 99
		surge.last_round = 2
		surge._on_round_started(6)
		randoms += 1 if surge.plan_in >= 0.0 else 0
	var near := 0
	for i in 200:
		surge.plan_in = -1.0
		surge.next_round = 99
		surge.last_round = 5
		surge._on_round_started(6)
		near += 1 if surge.plan_in >= 0.0 else 0
	surge.plan_in = -1.0
	_check(none_r1 and planned_r3, "  scheduled: none in round 1, one planned from round 3")
	_check(randoms >= 10 and randoms <= 80 and near == 0, "  and now and then at random (%d of 400 rounds), never within 2 rounds of the last (%d)" % [randoms, near])
	_check(surge.surge_size(1) >= 25 and surge.surge_size(30) <= 40, "  25 to 40 of them (%d at round 1, %d at round 30)" % [surge.surge_size(1), surge.surge_size(30)])
	surge.enabled = false
	spawner.enabled = false
