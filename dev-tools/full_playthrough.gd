extends "res://dev-tools/playtest_bot.gd"
## The whole game, start to finish, played through real input by the
## playtest bot's navmesh walking -- meant to be recorded:
##
##   godot --path . --write-movie /tmp/dopesick.avi --fixed-fps 30 \
##       -s res://dev-tools/full_playthrough.gd -- /tmp/shots
##
## Chapters, each titled on screen: the opening cutscene and waking up;
## finding the walkman and putting a punk tape in; taking an order at the
## Dive Bar; a full game of eight-ball for money; stealing the order,
## delivering it, and scoring from the pusher; lifting a tape at Tape Deck;
## sleeping it off; getting caught in the electronics store (the arrest
## cutscene, the cell, release); and the end of the run -- mixing fentanyl
## with a benzo, the overdose cutscene, and the run-end screen.

var _title: Label

func _initialize() -> void:
	out_dir = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://"
	t_start = Time.get_ticks_msec()
	_build_title()
	change_scene_to_file("res://world/Apartment3D.tscn")
	await _wait(0.8)
	await _run()
	log_line("DONE")
	await _wait(2.0)
	quit()

func _build_title() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	root.add_child.call_deferred(layer)
	_title = Label.new()
	_title.position = Vector2(16, 12)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 6)
	layer.add_child.call_deferred(_title)

func chapter(text: String) -> void:
	_title.text = text
	log_line("=== " + text)

func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame

## Watches a cutscene, giving each panel a few seconds before moving on.
func watch_cutscene(per_panel := 4.0) -> void:
	var cs := root.get_node("Cutscene")
	var waited := 0.0
	while not cs.is_playing() and waited < 3.0:
		await _wait(0.1)
		waited += 0.1
	var n := 0
	while cs.is_playing():
		await _wait(per_panel)
		if not cs.is_playing():
			break
		n += 1
		await screenshot("cutscene_%d" % n)
		await key(KEY_SPACE)  # finish the caption
		await _wait(0.2)
		await key(KEY_SPACE)  # next panel
	await _wait(0.5)

## Places keep hours; like a player with nowhere to be, hang around until
## `place` opens (a scene-file place name, or "pusher" for his shift).
func wait_for(place: String) -> void:
	var gs := root.get_node("GameState")
	var open_at: float
	if place == "pusher":
		if gs.pusher_on_shift():
			return
		open_at = gs.PUSHER_HOURS[0]
	else:
		if gs.is_open(place):
			return
		open_at = gs.opening_hour(place)
	var minutes := fposmod(open_at + 0.25 - gs.hour(), 24.0) * 60.0
	log_line("killing time until %s opens (%.0f min)" % [place, minutes])
	_title.text += "   (killing time until %d:15)" % int(open_at)
	gs.advance_clock(minutes)
	await _wait(1.0)

func choice_menu() -> CanvasLayer:
	for c in root.get_children():
		if c is CanvasLayer and c.has_method("open") and c.has_signal("chosen"):
			return c
	return null

func _run() -> void:
	var gs := root.get_node("GameState")
	var walkman := root.get_node("Walkman")

	chapter("1. Day one: waking up sick")
	await watch_cutscene()
	await screenshot("wake_nudge")
	await _wait(2.0)
	await close_dialogue()

	chapter("2. The walkman and the shoebox of punk tapes")
	await walk_to(current_scene.get_node("Walkman"))
	await talk()
	await screenshot("walkman_pickup")
	await _wait(2.5)
	await close_dialogue()
	await key(KEY_T)
	await _wait(1.2)
	await screenshot("shoebox")
	var menu := choice_menu()
	if menu:
		menu._on_pick(1)  # the first punk tape
	await _wait(3.0)
	log_line("now playing: %s" % walkman.current)
	await screenshot("tape_in")

	chapter("3. The Dive Bar: an order")
	await use_door("DoorToCity")
	await _wait(1.0)
	await wait_for("bar")
	await use_door("DoorToBar")
	var patron: Node3D = current_scene.get_node("Patron1")
	var want_id: String = patron.request_id
	await walk_to(patron)
	await talk()
	await _wait(2.0)
	await close_dialogue()
	var store: String = gs.item_info(want_id)["store"]
	log_line("order: %s wants '%s' from %s" % [patron.npc_name, want_id, store])

	chapter("4. Eight-ball for $5 against the Old Sailor")
	gs.cash = maxi(gs.cash, 20)
	await walk_to(current_scene.find_child("PoolZone", true, false))
	await press_interact()
	await _wait(1.2)
	menu = choice_menu()
	if menu:
		menu._on_pick(0)
	await _wait(1.0)
	await play_pool()

	chapter("5. Lifting the order: %s from the %s" % [gs.item_name_for(want_id), store])
	await use_door("DoorToCity")
	await key(KEY_N)  # next tape on the walk over
	await wait_for(store)
	await use_door(STORE_DOORS[store])
	var item: Node3D = null
	for slot in current_scene.item_slots:
		if slot.item_id == want_id:
			item = slot
	if item and await walk_to(item):
		await press_interact()
		await _wait(1.4)
		await screenshot("stolen")
	await settle()
	if current_scene.name == "Jail3D":
		await jail_time()
	else:
		await use_door("DoorToCity")
		for i in 30:
			if not gs.wanted:
				break
			await _wait(0.5)

	chapter("6. Getting paid")
	if current_scene.name == "City3D" and not gs.inventory.is_empty():
		await use_door("DoorToBar")
		var buyer: Node3D = null
		for n in ["Patron1", "Patron2", "Patron3"]:
			var p = current_scene.get_node(n)
			if gs.has_item(p.request_id):
				buyer = p
		await walk_to(buyer if buyer else current_scene.get_node("Bartender"))
		await talk()
		await screenshot("paid")
		await _wait(2.0)
		await close_dialogue()
		await use_door("DoorToCity")

	chapter("7. The pusher at the dark end of the block")
	await wait_for("pusher")
	gs.cash = maxi(gs.cash, gs.cheapest_opioid_cost())
	await walk_to(current_scene.get_node("Pusher"))
	await talk()
	await _wait(0.8)
	var dm := open_menu()
	if dm:
		var pick := ""
		for id in dm._stock:
			if root.get_node("Drugs").info(id)["class"] == "opioid" and gs.price_of(id) <= gs.cash:
				pick = id
		if pick == "":
			pick = dm._stock[0]
		log_line("bought %s" % root.get_node("Drugs").name_for(pick))
		dm.chosen.emit(pick)
		dm._close()
	await _wait(0.8)
	await close_dialogue()
	for i in 40:
		if gs.craving > 90.0:
			break
		await _wait(0.5)
	await screenshot("handoff")
	await close_dialogue()

	chapter("8. Tape Deck: lifting a cassette")
	if gs.is_open("music") and await use_door("DoorToMusic"):
		var tape: Node3D = null
		for slot in current_scene.item_slots:
			if is_instance_valid(slot):
				tape = slot
				break
		var before: int = gs.tapes.size()
		if tape and await walk_to(tape):
			await press_interact()
			await _wait(1.4)
		log_line("shoebox %d -> %d tapes" % [before, gs.tapes.size()])
		await screenshot("tape_deck")
		await settle()
		if current_scene.name == "MusicStore3D":
			await use_door("DoorToCity")
		for i in 30:
			if not gs.wanted:
				break
			await _wait(0.5)
		await settle()
		if current_scene.name == "Jail3D":
			await jail_time()

	chapter("9. Home to sleep it off")
	if current_scene.name == "City3D":
		await use_door("DoorToHome")
	if current_scene.name == "Apartment3D":
		await walk_to(current_scene.get_node("Bed"))
		await talk()
		await screenshot("sleep")
		await _wait(2.0)
		await close_dialogue()
		await use_door("DoorToCity")

	chapter("10. Caught: stealing in front of the electronics clerk")
	await wait_for("electronics")
	await use_door("DoorToElectronics")
	var clerk := current_scene.get_node("Clerk") as Node3D
	var target: Node3D = null
	for slot in current_scene.item_slots:
		if target == null or slot.global_position.distance_to(clerk.global_position) < target.global_position.distance_to(clerk.global_position):
			target = slot
	await walk_to(target)
	for attempt in 30:
		if gs.wanted:
			break
		if is_instance_valid(target) and player().nearby.has(target):
			await press_interact()
		await _wait(0.3)
		player().is_stealing = true
	log_line("spotted -- standing still for the police")
	while not gs.in_custody and current_scene.name != "Jail3D":
		await _wait(0.2)
	await watch_cutscene(3.5)
	await settle()
	await jail_time()

	chapter("11. The end of the run")
	# Fentanyl on top of a benzo: the thing the game warns you about most.
	gs.naloxone = 0
	var ended := [false]
	gs.run_ended.connect(func(_s): ended[0] = true)
	for i in 40:
		if ended[0]:
			break
		var outcome: String = gs.take_drug("alprazolam" if i % 2 == 0 else "fentanyl")
		log_line("dose %d: %s" % [i, outcome])
		await _wait(0.3)
	await watch_cutscene(4.0)
	await _wait(2.0)
	await screenshot("run_end")
	await _wait(4.0)

## Eight-ball with the game's own shot-finding standing in for the mouse:
## it lines up, the cue pulls back, and it lets go.
func play_pool() -> void:
	var game: Node = null
	for c in root.get_children():
		if c.has_method("_ai_plan"):
			game = c
	if game == null:
		log_line("pool game didn't open")
		return
	await screenshot("pool_break")
	var shots := 0
	while not game._over and shots < 60:
		await process_frame
		if game._moving or game._shooter != 0:
			continue
		shots += 1
		if game._ball_in_hand:
			await _wait(0.6)
			game._ai_place_cue()
		await _wait(0.5)
		game._ai_plan()
		var from: float = game._aim
		for i in 24:
			game._aim = lerp_angle(from, game._ai_target_aim, (i + 1) / 24.0)
			await process_frame
		game._charging = true
		game._charge_t = 0.0
		for i in 18:
			game._charge = game._ai_power * (i + 1) / 18.0
			await process_frame
		game._shoot(game._ai_target_aim, game._ai_power, game._ai_follow, 0.0)
		if shots == 1:
			await _wait(0.8)
			await screenshot("pool_after_break")
	log_line("pool over: %s" % game._message)
	await screenshot("pool_result")
	await _wait(3.0)
	game._close()
	await _wait(0.5)

func jail_time() -> void:
	chapter("   ...a night in the cell")
	await screenshot("cell")
	await _wait(2.0)
	await close_dialogue()
	await walk_to(current_scene.get_node("Bench"))
	await talk()
	await _wait(2.0)
	await close_dialogue()
	await _wait(1.6)
	await use_door("DoorToCity")
