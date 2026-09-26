extends SceneTree
## Headless test for the first-person layer: the main menu, the rifle,
## armed police, damage and death, loot, reload, pause, and the rooms'
## first-person fixes. Drives the real scenes with real input actions.
##   godot --headless --path . -s res://dev-tools/combat_test.gd
## Exit code 0 = all checks passed.

var _failures := 0
var gs: Node

func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
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

## Points the camera at `pos`.
func _aim_at(p: Node3D, pos: Vector3) -> void:
	var eye: Vector3 = p.camera.global_position
	var d := pos - eye
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

## Holds the trigger on `target` until `done` says stop (or time runs out).
func _shoot_until(p: Node3D, target: Node3D, height: float, done: Callable, max_frames := 300) -> void:
	for i in max_frames:
		if done.call():
			break
		_aim_at(p, target.global_position + Vector3(0, height, 0))
		Input.action_press("fire")
		await physics_frame
	Input.action_release("fire")
	await physics_frame

func _run() -> void:
	print("== Main menu")
	var menu := await _load("res://ui/MainMenu.tscn")
	_check(menu != null and menu.name == "MainMenu", "main menu loads")
	_check(get_first_node_in_group("player") == null, "  the street backdrop has no player in it")
	_check(not gs.run_active, "  craving is frozen on the title screen")
	var c0: float = gs.craving
	await _frames(30)
	_check(is_equal_approx(gs.craving, c0), "  ...and stays frozen (%.2f -> %.2f)" % [c0, gs.craving])
	var labels := menu.find_children("*", "Button", true, false).map(func(b): return b.text)
	_check(labels.has("New run") and labels.has("Settings") and labels.has("Quit"), "  has New run / Settings / Quit (%s)" % str(labels))
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://ui/MainMenu.tscn", "  is the project's main scene")

	print("== Rooms, seen from eye level")
	gs.start_run()
	var store := await _load("res://world/StoreLiquor3D.tscn")
	_check(gs.run_active, "entering a room starts the clock again")
	_check(store.get_node_or_null("Ceiling") != null, "  the store has a ceiling")
	var south := store.get_node("WallSouth")
	var mesh_h: float = (south.get_node("Mesh").mesh as BoxMesh).size.y
	_check(mesh_h > 2.0, "  the south wall is full height again (%.2f m)" % mesh_h)
	var p := _player()
	_check(p.camera.current and p.camera.global_position.y > 1.4, "  the camera is at eye height (%.2f m)" % p.camera.global_position.y)

	print("== Rifle: firing, ammo, and an armed response")
	var guard: Node3D = null
	for g in get_nodes_in_group("guards"):
		if not g.watcher_only and store.is_ancestor_of(g):
			guard = g
	_check(guard != null, "store has a guard to shoot")
	# Stand between the guard and the middle of the room, in the open.
	var inward := -Vector3(guard.global_position.x, 0, guard.global_position.z).normalized()
	p.global_position = guard.global_position + inward * 2.5
	await _frames(3)
	var mag0: int = gs.ammo_mag
	_check(not gs.wanted and not gs.lethal, "  calm before the first shot")
	await _shoot_until(p, guard, 1.1, func(): return guard.dead, 200)
	_check(guard.dead, "  the guard goes down under fire")
	_check(gs.ammo_mag < mag0, "  firing spends rounds (%d -> %d)" % [mag0, gs.ammo_mag])
	_check(gs.wanted and gs.lethal, "  gunfire makes you wanted, with lethal force")
	_check(gs.kills == 1, "  the kill is counted (%d)" % gs.kills)
	_check(not guard.is_in_group("guards") and not guard.vision_cone.visible, "  a dead guard stops watching")

	print("== Police shoot back")
	var police: Node3D = null
	# Back into the open middle of the store, where the officer can see you.
	p.global_position = Vector3(0, 0, 0)
	for i in 400:
		police = get_first_node_in_group("police") as Node3D
		if police:
			break
		await physics_frame
	_check(police != null, "an officer responds to the gunfire")
	var hp0: float = gs.health
	for i in 600:
		if gs.health < hp0:
			break
		await physics_frame
	_check(gs.health < hp0, "  and shoots you (health %.0f -> %.0f)" % [hp0, gs.health])
	_check(not gs.in_custody, "  but doesn't try to cuff an armed suspect")

	print("== Killing an officer")
	gs.health = 100.0
	var reserve0: int = gs.ammo_reserve
	await _shoot_until(p, police, 1.1, func(): return police.dead, 300)
	_check(police.dead, "the officer goes down")
	_check(gs.kills == 2, "  counted as a kill (%d)" % gs.kills)
	var pickups := current_scene.get_children().filter(func(n): return n is Area3D and n.get_script() == load("res://items/Pickup3D.gd"))
	_check(pickups.size() == 1, "  and drops ammo and cash")
	if pickups.size() == 1:
		var cash0: int = gs.cash
		var r0: int = gs.ammo_reserve
		p.global_position = pickups[0].global_position
		await _frames(5)
		_check(gs.ammo_reserve > r0 and gs.cash > cash0, "  walking over it takes it (+%d rounds, +$%d)" % [gs.ammo_reserve - r0, gs.cash - cash0])
	var backup: Node3D = null
	for i in 500:
		for cop in get_nodes_in_group("police"):
			if cop != police:
				backup = cop
		if backup:
			break
		await physics_frame
	_check(backup != null, "  backup arrives after an officer goes down")

	print("== Reload")
	gs.ammo_mag = 3
	gs.ammo_reserve = 50
	Input.action_press("reload")
	await _frames(2)
	Input.action_release("reload")
	_check(p.weapon.is_reloading(), "R starts a reload")
	await _frames(int(p.weapon.RELOAD_TIME * 60.0) + 10)
	_check(gs.ammo_mag == gs.MAG_SIZE and gs.ammo_reserve == 23, "  the mag is topped up from the reserve (%d / %d)" % [gs.ammo_mag, gs.ammo_reserve])
	gs.ammo_mag = 0
	gs.ammo_reserve = 0
	Input.action_press("fire")
	await _frames(5)
	Input.action_release("fire")
	_check(gs.ammo_mag == 0 and not p.weapon.is_reloading(), "  an empty gun with nothing in reserve just clicks")

	print("== Dying")
	gs.ammo_mag = 30
	gs.ammo_reserve = 90
	var strikes0: int = gs.strikes
	gs.damage_player(500.0, p.global_position)
	await _frames(3)
	_check(p.dead, "taking enough fire kills you")
	_check(get_first_node_in_group("hud").busted_overlay.visible, "  WASTED is on screen")
	for i in 400:
		if current_scene and current_scene.name == "Jail3D":
			break
		await physics_frame
	await _frames(10)
	_check(current_scene.name == "Jail3D", "  you come round in a cell")
	_check(gs.strikes == strikes0 + 1, "  it costs a strike (%d -> %d)" % [strikes0, gs.strikes])
	_check(is_equal_approx(gs.health, gs.MAX_HEALTH) and not gs.lethal, "  patched up, and the heat is off")

	print("== Pause")
	var pause_menu: Node = null
	for n in current_scene.get_children():
		if n is CanvasLayer and n.has_method("is_open"):
			pause_menu = n
	_check(pause_menu != null, "every room has a pause menu")
	if pause_menu:
		var craving0: float = gs.craving
		pause_menu.open()
		await process_frame
		_check(paused, "  opening it pauses the game")
		await create_timer(0.5, true).timeout
		_check(is_equal_approx(gs.craving, craving0), "  and the craving with it")
		pause_menu.close()
		await process_frame
		_check(not paused, "  resume unpauses")

	print("== Sleep refills the stash")
	var home := await _load("res://world/Apartment3D.tscn")
	gs.ammo_reserve = 10
	gs.set_wanted(false)
	var bed: Node = home.find_children("*", "Area3D", true, false).filter(func(a): return a.has_method("prompt_text") and a.prompt_text() == "Sleep it off").front()
	bed.interact(_player())
	_check(gs.ammo_reserve == gs.HOME_RESERVE, "  sleeping tops the reserve back up (%d)" % gs.ammo_reserve)
