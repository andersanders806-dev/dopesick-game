extends "res://dev-tools/video_high_ground.gd"
## Dev helper: a live demo in a window. A bot plays the real rounds from round 1
## until the first quake (round 3 or 4) and its tsunami (the real 2:00 clock),
## runs the passable route to the high ground, watches the wave, then plays the
## round after to its end. The bot can't die and never runs dry (a demo, not a test).
##   flatpak run org.godotengine.Godot --path . -s res://dev-tools/demo_rounds.gd

func _initialize() -> void:
	Engine.set_meta("sandbox", true)
	await process_frame
	zm = root.get_node("ZombieMode")
	root.get_node("GameState").no_sickness = true
	zm.begin(true)
	change_scene_to_file("res://world/City3D.tscn")
	for i in 30:
		await process_frame
	block = current_scene.get_node("ZombieBlock")
	while not block.purchases_ready:
		await process_frame
	p = get_first_node_in_group("player") as CharacterBody3D
	ts = block.tsunami
	hg = block.high_ground
	zm.health = 1e9
	var h: Node = p.get_node("WeaponHolder")
	h.give(load("res://weapons/ar.tres"))
	h.refill_all()
	p.global_position = START
	p.set_look(PI / 2.0, 0.0)
	var last_round := -1
	# The rounds, until the warning.
	while not ts.warned:
		await process_frame
		if zm.round != last_round:
			last_round = zm.round
			print("DEMO round %d" % last_round)
		_fight(h, 45.0)
	print("DEMO quake + tsunami warning in round %d, clock %.0f s" % [zm.round, ts.remaining])
	var ok := await _run_route(h)
	print("DEMO reached the high ground: %s, clock left %.0f s" % [ok, ts.remaining])
	Input.action_release("sprint")
	Input.action_release("move_up")
	while ts.phase == ts.Phase.COUNTDOWN and ts.remaining > 7.0:
		_hold_stair(h)
		if h.mag <= 3:
			h.refill_all()
		await process_frame
	Input.action_release("fire")
	await _face_west(7.0, h)
	# The wave and the flood.
	var t := 0.0
	while t < 60.0 and not (ts.phase == ts.Phase.IDLE and t > 6.0):
		await process_frame
		t += 1.0 / 60.0
		if _shoot_nearest(h, 7.0):
			continue
		Input.action_release("fire")
		p.set_look(lerp_angle(float(p.get("_look_yaw")), PI / 2.0 - 0.3, 0.04), lerpf(float(p.get("_look_pitch")), -0.45, 0.04))
	print("DEMO after the flood: survived=%s swept=%d round=%d" % [ts.survived, ts.swept, zm.round])
	# The round after: play on until the next round has started and ended.
	var after: int = int(zm.round) + 1
	var limit := 0.0
	while zm.round <= after and limit < 600.0:
		await process_frame
		limit += 1.0 / 60.0
		if zm.round != last_round:
			last_round = zm.round
			print("DEMO round %d" % last_round)
		_fight(h, 45.0)
	Input.action_release("fire")
	print("DEMO done, round %d reached" % zm.round)
	await _secs(3.0)
	zm.leave()
	quit()

func _fight(h: Node, reach: float) -> void:
	if h.mag <= 3:
		h.refill_all()
	if not _shoot_nearest(h, reach):
		Input.action_release("fire")
		p.set_look(float(p.get("_look_yaw")) + 0.01, lerpf(float(p.get("_look_pitch")), 0.0, 0.05))
