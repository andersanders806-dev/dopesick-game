extends SceneTree
## Playtest bot: plays one full loop of the 3D game through real input
## (analog move actions and interact key events), finding its way with the
## game's own navmesh. It takes a patron's order, finds the right store,
## steals the item, delivers it, buys from the pusher, and sleeps -- logging
## every dialogue line, cash/craving, busts, and any spot it gets stuck, with
## screenshots along the way. Needs a display (not --headless):
##   godot --path . -s res://dev-tools/playtest_bot.gd -- <screenshot_dir>

var out_dir: String
var shot := 0
var t_start := 0

func _initialize() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	t_start = Time.get_ticks_msec()
	change_scene_to_file("res://world/Apartment3D.tscn")
	await _wait(1.0)
	var gs := root.get_node("GameState")
	gs.busted.connect(func():
		var pl := player()
		var cops := get_nodes_in_group("police").map(func(c): return "%s@%s" % [c.name, c.global_position.snapped(Vector3.ONE * 0.1)])
		log_line("BUSTED! player@%s police=%s" % [pl.global_position.snapped(Vector3.ONE * 0.1) if pl else "?", cops]))
	gs.wanted_changed.connect(func(w):
		var pl := player()
		log_line("wanted -> %s (player@%s, stealing=%s)" % [w, pl.global_position.snapped(Vector3.ONE * 0.1) if pl else "?", pl.is_stealing if pl else "?"]))
	await _play()
	log_line("DONE")
	quit()

func log_line(msg: String) -> void:
	var gs := root.get_node("GameState")
	print("[%5.1fs] %-11s cash=$%-3d crave=%3.0f day=%d wanted=%s inv=%s | %s" % [
		(Time.get_ticks_msec() - t_start) / 1000.0, current_scene.name if current_scene else "?",
		gs.cash, gs.craving, gs.day, gs.wanted, gs.inventory, msg])

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	shot += 1
	root.get_texture().get_image().save_png("%s/play_%02d_%s.png" % [out_dir, shot, label])

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func player() -> Node3D:
	return get_first_node_in_group("player") as Node3D

func hud() -> Node:
	return get_first_node_in_group("hud")

func release_moves() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)

func press_interact() -> void:
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = "interact"
	up.pressed = false
	Input.parse_input_event(up)
	await physics_frame

## Walks along a navmesh path until `node` is in the interact zone (or within
## `stop_dist` when it isn't interactable). Returns false if stuck.
func walk_to(node: Node3D, stop_dist := 0.6, timeout := 25.0) -> bool:
	var p := player()
	var map: RID = p.get_world_3d().navigation_map
	var started := Time.get_ticks_msec()
	var best := INF
	var last_progress := Time.get_ticks_msec()
	while true:
		await physics_frame
		p = player()
		if p == null or not is_instance_valid(node):
			release_moves()
			return false
		# Like a player would: keep walking until the thing you want is the
		# one E will actually use.
		if node is Area3D and p._nearest_interactable() == node:
			break
		var goal := node.global_position
		var d := Vector2(goal.x - p.global_position.x, goal.z - p.global_position.z).length()
		if not (node is Area3D) and d < stop_dist:
			break
		if d < best - 0.05:
			best = d
			last_progress = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_progress > 3000:
			release_moves()
			log_line("STUCK walking to %s (%.1f m away)" % [node.name, d])
			await screenshot("stuck_" + str(node.name))
			return false
		if Time.get_ticks_msec() - started > timeout * 1000:
			release_moves()
			log_line("TIMEOUT walking to %s" % node.name)
			return false
		var path := NavigationServer3D.map_get_path(map, p.global_position, goal, true)
		var next := goal
		for pt in path:
			if Vector2(pt.x - p.global_position.x, pt.z - p.global_position.z).length() > 0.35:
				next = pt
				break
		var dir := Vector2(next.x - p.global_position.x, next.z - p.global_position.z).normalized()
		release_moves()
		if dir.x > 0: Input.action_press("move_right", dir.x)
		elif dir.x < 0: Input.action_press("move_left", -dir.x)
		if dir.y > 0: Input.action_press("move_down", dir.y)
		elif dir.y < 0: Input.action_press("move_up", -dir.y)
	release_moves()
	return true

## Interact, log whatever dialogue comes up, then close it.
func talk() -> String:
	await press_interact()
	await _wait(0.4)
	var h := hud()
	var text := ""
	if h and h.dialogue_panel.visible:
		text = "%s: %s" % [h.speaker_label.text if h.speaker_label.visible else "(narration)", h.text_label.text]
		log_line("DIALOGUE " + text)
	return text

func close_dialogue() -> void:
	await press_interact()
	await _wait(0.3)

func use_door(door_name: String) -> bool:
	var door := current_scene.get_node_or_null(door_name) as Node3D
	if door == null:
		log_line("MISSING door " + door_name)
		return false
	if not await walk_to(door):
		return false
	var before := current_scene
	await press_interact()
	await _wait(0.8)
	log_line("went through %s" % door_name)
	return current_scene != before

const STORE_DOORS := {
	"convenience": "DoorToShop", "pharmacy": "DoorToPharmacy", "supermarket": "DoorToSupermarket",
	"liquor": "DoorToLiquor", "electronics": "DoorToElectronics",
}

func _play() -> void:
	var gs := root.get_node("GameState")
	log_line("start")
	await screenshot("apartment_start")
	await use_door("DoorToCity")
	await use_door("DoorToBar")

	# Take an order from whichever patron is nearest the door.
	var patron: Node3D = current_scene.get_node("Patron1")
	var want_id: String = patron.request_id
	await walk_to(patron)
	await talk()
	await screenshot("patron_request")
	await close_dialogue()
	var store: String = gs.item_info(want_id)["store"]
	log_line("order: %s wants '%s' from %s" % [patron.npc_name, want_id, store])

	await use_door("DoorToCity")
	await use_door(STORE_DOORS[store])
	await screenshot("store_" + store)

	var item: Node3D = null
	for slot in current_scene.item_slots:
		if slot.item_id == want_id:
			item = slot
	log_line("target on %s" % (item.name if item else "NOT STOCKED THIS VISIT"))
	if item and await walk_to(item):
		await press_interact()
		await _wait(1.2)
		log_line("after steal attempt")
	await use_door("DoorToCity")
	for i in 20:
		if not gs.wanted or current_scene.name != "City3D":
			break
		await _wait(0.5)

	if current_scene.name == "Jail3D":
		log_line("in jail -- waiting it out")
		await screenshot("jail")
		await close_dialogue()
		await walk_to(current_scene.get_node("Bench"))
		await talk()
		await close_dialogue()
		await _wait(1.6)
		await use_door("DoorToCity")

	if current_scene.name == "City3D" and not gs.inventory.is_empty():
		await use_door("DoorToBar")
		var buyer: Node3D = null
		for n in ["Patron1", "Patron2", "Patron3"]:
			var p = current_scene.get_node(n)
			if gs.has_item(p.request_id):
				buyer = p
		if buyer:
			log_line("delivering to %s" % buyer.npc_name)
			await walk_to(buyer)
		else:
			log_line("nobody wants it this visit -- fencing to the bartender")
			await walk_to(current_scene.get_node("Bartender"))
		await talk()
		await screenshot("deliver")
		await close_dialogue()
		await use_door("DoorToCity")

	if current_scene.name == "City3D":
		gs.cash = maxi(gs.cash, gs.current_fix_cost())
		var pusher := current_scene.get_node("Pusher") as Node3D
		log_line("walking down the block to the pusher")
		await walk_to(pusher)
		await talk()
		await screenshot("pusher_pay")
		await close_dialogue()
		for i in 40:
			if gs.craving > 90.0:
				break
			await _wait(0.5)
		log_line("after the handoff")
		await screenshot("pusher_handoff")
		await close_dialogue()
		await use_door("DoorToHome")

	if current_scene.name == "Apartment3D":
		await walk_to(current_scene.get_node("Bed"))
		await talk()
		await screenshot("sleep")
		await close_dialogue()
