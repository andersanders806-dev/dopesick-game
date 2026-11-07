extends "res://dev-tools/full_playthrough.gd"
## Demo: the main Story mode, six in-game days, played by the playtest bot
## through real input with withdrawal ON. Each day is one hustle (an order
## stolen and delivered, or a morning on the loading dock first), a score
## from the pusher, and sleep. Busts are played out (chase, cell, release)
## and the day goes on. Stops once the sixth night is slept (the day counter
## reads 7) or at a safety limit, and prints why.
##
##   godot --path . --resolution 1280x720 --write-movie story_raw.avi \
##       --fixed-fps 30 -s res://dev-tools/demo_story_6days.gd -- <shot_dir>

const DAYS := 6
const SAFETY_SECONDS := 3000.0

## "days=N" after the shot dir plays N days instead of six.
var days_to_play := DAYS

var _card: Label
var _day_offset := 0     # days lived in earlier runs, if a run ended
var _run_ended := false
var _stop_reason := ""

func story_day() -> int:
	return root.get_node("GameState").day + _day_offset

func _initialize() -> void:
	# Don't touch the player's progress, settings or saved run.
	Engine.set_meta("sandbox", true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="):
			days_to_play = int(a.substr(5))
	out_dir = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() and OS.get_cmdline_user_args()[0] != "fp" else "user://"
	t_start = Time.get_ticks_msec()
	_build_title()
	var gs := root.get_node("GameState")
	gs.run_ended.connect(func(_s): _run_ended = true)
	gs.busted.connect(func(): log_line("BUSTED"))
	root.get_node("SaveGame").delete()
	change_scene_to_file("res://ui/TitleScreen.tscn")
	await _wait(0.8)
	_title.text = "Dope Sick  -  Story mode"
	await _wait(4.0)
	await screenshot("title")
	current_scene._start_run(OS.get_cmdline_user_args().has("fp"))  # a new run; "fp" after the shot dir = first person
	await _wait(1.5)
	await _days()
	log_line("STOP: %s (story day %d, gs.day %d)" % [_stop_reason, story_day(), gs.day])
	print("DEMO RESULT: %s" % _stop_reason)
	await _wait(2.0)
	quit()

func _build_title() -> void:
	super._build_title()
	var layer := CanvasLayer.new()
	layer.layer = 129
	root.add_child.call_deferred(layer)
	_title.position = Vector2(380, 10)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 96)
	_card.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_card.add_theme_color_override("font_outline_color", Color.BLACK)
	_card.add_theme_constant_override("outline_size", 16)
	_card.modulate.a = 0.0
	layer.add_child.call_deferred(_card)

## A phone buzzing out on the street opens a message and freezes the
## walk, as it would for a player: read it, dismiss it, carry on.
func walk_to(node: Node3D, stop_dist := 0.6, timeout := 70.0) -> bool:
	await close_dialogue()
	var ok: bool = await super.walk_to(node, stop_dist, timeout)
	if not ok and is_instance_valid(node) and player() and player().dialogue_active:
		await _wait(1.0)
		await close_dialogue()
		ok = await super.walk_to(node, stop_dist, timeout)
	return ok

func chapter(text: String) -> void:
	_title.text = "DAY %d   -   %s" % [story_day(), text]
	log_line("=== " + _title.text)

func day_card(n: int) -> void:
	_card.text = "DAY %d" % n
	var tw := create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.8)
	tw.tween_property(_card, "modulate:a", 0.0, 0.6)
	await tw.finished

func _days() -> void:
	var gs := root.get_node("GameState")
	var safety_start := Time.get_ticks_msec()
	var played := 0
	while story_day() <= days_to_play:
		if (Time.get_ticks_msec() - safety_start) / 1000.0 > SAFETY_SECONDS:
			_stop_reason = "safety time limit"
			return
		if played > days_to_play + 6:
			_stop_reason = "safety day-attempt limit"
			return
		var d := story_day()
		played += 1
		await day_card(d)
		await play_day(d)
		if _run_ended:
			await _handle_run_end()
		await settle()
	_stop_reason = "day %d ended, counter advanced to %d" % [days_to_play, story_day()]

## The run ended (overdose, three strikes...): watch it, then start over
## and keep counting days.
func _handle_run_end() -> void:
	var gs := root.get_node("GameState")
	log_line("RUN ENDED early at story day %d" % story_day())
	await watch_cutscene(4.0)
	await _wait(3.0)
	await screenshot("run_end")
	_day_offset = story_day()
	_run_ended = false
	root.get_node("SaveGame").delete()
	gs.start_run()
	change_scene_to_file("res://world/Apartment3D.tscn")
	await _wait(2.0)

## Anywhere -> the street, playing out any bust on the way.
func go_street() -> void:
	await to_street()
	await settle()

func at_home() -> bool:
	return current_scene != null and current_scene.name == "Apartment3D"

func hungry_for_a_fix() -> bool:
	var gs := root.get_node("GameState")
	return gs.craving < 40.0

func play_day(n: int) -> void:
	var gs := root.get_node("GameState")
	var walkman := root.get_node("Walkman")
	chapter("waking up" if n == 1 else "morning")
	if n == 1 or gs.intro_pending:
		await watch_cutscene()
	await settle()
	await _wait(1.5)
	await close_dialogue()

	if n == 1 and at_home() and current_scene.get_node_or_null("Walkman") and not gs.has_walkman:
		chapter("the walkman and a punk tape")
		await walk_to(current_scene.get_node("Walkman"))
		await talk()
		await _wait(2.0)
		await close_dialogue()
		await key(KEY_T)
		await _wait(1.0)
		var menu := choice_menu()
		if menu:
			menu._on_pick(1)
		await _wait(2.5)
		log_line("now playing: %s" % walkman.current)

	# Variety: some mornings on the loading dock before the bar opens.
	if n % 2 == 0 and gs.hour() < 10.0:
		await dock_job()

	await order_loop()
	await go_street()
	await score()
	await go_street()
	await pay_rent_if_due()
	await go_to_bed()

# --- the dock -------------------------------------------------------------

func dock_job() -> void:
	var gs := root.get_node("GameState")
	chapter("a morning unloading the truck")
	await go_street()
	if not await use_door("DoorToBackyard"):
		return
	await _wait(1.5)
	var room := current_scene
	var ask := room.get_node_or_null("DockAsk") as Node3D
	if ask == null:
		log_line("no dock job here today")
		await use_door("DoorToCity")
		return
	await walk_to(ask)
	await talk()
	await _wait(1.5)
	await close_dialogue()
	var jobs := root.get_node("Jobs")
	for i in 14:
		if jobs.job.get("kind", "") != "dock":
			break
		var truck := room.get_node_or_null("DockTruck") as Node3D
		var pallet := room.get_node_or_null("DockPallet") as Node3D
		if truck == null or pallet == null:
			break
		if await walk_to(truck):
			await press_interact()
			await _wait(0.4)
		if await walk_to(pallet):
			await press_interact()
			await _wait(0.4)
	await _wait(1.0)
	await close_dialogue()
	log_line("dock job done, cash=$%d" % gs.cash)
	await screenshot("dock_done")
	await go_street()

# --- the order --------------------------------------------------------------

func pick_patron() -> Node3D:
	var gs := root.get_node("GameState")
	var bar := current_scene
	for i in 3:
		var p := bar.get_node_or_null("Patron%d" % (i + 1)) as Node3D
		if p and not gs.bar_patrons[i]["fulfilled"] and p.request_id != "":
			return p
	return null

func order_loop() -> void:
	var gs := root.get_node("GameState")
	chapter("an order at the Dive Bar")
	await go_street()
	await wait_for("bar")
	if not await use_door("DoorToBar"):
		return
	var patron := pick_patron()
	if patron == null:
		log_line("nobody wants anything today")
		await use_door("DoorToCity")
		return
	var want_id: String = patron.request_id
	await walk_to(patron)
	await talk()
	await _wait(2.0)
	await close_dialogue()
	var store: String = gs.item_info(want_id)["store"]
	log_line("order: %s wants '%s' from %s" % [patron.npc_name, want_id, store])

	chapter("lifting it: %s from the %s" % [gs.item_name_for(want_id), store])
	await use_door("DoorToCity")
	await wait_for(store)
	var shop: Node = current_scene
	if store in WALK_INS:
		shop = await enter_walk_in(WALK_INS[store])
	else:
		await use_door(STORE_DOORS[store])
		shop = current_scene
	var item: Node3D = null
	if shop and "item_slots" in shop:
		for slot in shop.item_slots:
			if is_instance_valid(slot) and slot.item_id == want_id:
				item = slot
	log_line("target on %s" % (item.name if item else "NOT STOCKED THIS VISIT"))
	if item and await walk_to(item):
		await press_interact()
		await _wait(1.4)
		await screenshot("stolen")
	await to_street()
	await settle()
	if current_scene.name != "City3D" and current_scene.get_node_or_null("DoorToCity"):
		await use_door("DoorToCity")
	await go_street()

	if not gs.inventory.is_empty():
		chapter("getting paid")
		await use_door("DoorToBar")
		var buyer: Node3D = null
		for i in 3:
			var p := current_scene.get_node_or_null("Patron%d" % (i + 1)) as Node3D
			if p and gs.has_item(p.request_id):
				buyer = p
		await walk_to(buyer if buyer else current_scene.get_node("Bartender"))
		await talk()
		await _wait(2.0)
		await screenshot("paid")
		await close_dialogue()
		await use_door("DoorToCity")

# --- the score --------------------------------------------------------------

func score() -> void:
	var gs := root.get_node("GameState")
	chapter("the pusher")
	if current_scene.name != "City3D":
		await go_street()
	await wait_for("pusher")
	await go_street()
	if gs.cash < gs.cheapest_opioid_cost():
		log_line("short by $%d -- the bot borrows it (dev top-up)" % (gs.cheapest_opioid_cost() - gs.cash))
		gs.cash = gs.cheapest_opioid_cost()
	await walk_to(current_scene.get_node("Pusher"), 1.3)
	await talk()
	await _wait(0.8)
	var dm := open_menu()
	if dm:
		var pick := ""
		var best := 99999
		for id in dm._stock:
			var info: Dictionary = root.get_node("Drugs").info(id)
			if info["class"] != "opioid":
				continue
			var c: int = gs.price_of(id)
			if c < best and c <= gs.cash:
				best = c
				pick = id
		if pick == "":
			pick = dm._stock[0]
		log_line("bought %s" % root.get_node("Drugs").name_for(pick))
		dm.chosen.emit(pick)
		dm._close()
		await watch_cutscene(3.5)
	await _wait(0.8)
	await close_dialogue()
	for i in 40:
		if gs.craving > 90.0:
			break
		await _wait(0.5)
	await screenshot("handoff")
	await close_dialogue()

# --- home -------------------------------------------------------------------

func pay_rent_if_due() -> void:
	var gs := root.get_node("GameState")
	if not (gs.rent_payable() and gs.cash >= gs.rent_amount()):
		return
	await go_street()
	if not await use_door("DoorToHome"):
		return
	var slot := current_scene.get_node_or_null("RentSlot") as Node3D
	if slot and await walk_to(slot):
		chapter("paying the rent")
		await talk()
		await _wait(2.0)
		await close_dialogue()

func go_to_bed() -> void:
	var gs := root.get_node("GameState")
	chapter("home to sleep")
	await go_street()
	if not at_home():
		if not await use_door("DoorToHome"):
			return
	await settle()
	var day_before: int = gs.day
	var bed := current_scene.get_node("Bed") as Node3D
	await walk_to(bed)
	await talk()
	await watch_cutscene(3.5)
	await screenshot("sleep")
	await _wait(2.0)
	await close_dialogue()
	log_line("slept: day %d -> %d" % [day_before, gs.day])
