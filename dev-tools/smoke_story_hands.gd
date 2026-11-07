extends "res://dev-tools/smoke_test_3d.gd"
## Story first person's own hands (player/StoryHands.gd): there in first person and
## gone in third, bare skin on the shared arm rig, carrying what you lifted, the dock box,
## the Walkman, a dose, a reach, and a tremor that grows with the sickness.
##   godot --headless --path . -s res://dev-tools/smoke_story_hands.gd

func _hand_pos(h: Node, side: String) -> Vector3:
	return h._pos[side]

func _run() -> void:
	var gs := _gs()
	var gfx := root.get_node("Graphics")
	gs.intro_pending = false
	gs.mode = "story"
	gfx.set_first_person(true)
	await _load("res://world/Apartment3D.tscn")
	await _frames(10)
	var p := _player()
	p.dialogue_active = false
	gs.clock_running = false
	var h = p.story_hands
	_check(h != null, "first person: the player has hands")
	if h == null:
		return
	_check(h.vm.arms != null and h.vm.visible, "  ...the same arm rig as the gun modes, drawn")
	var mats: Array = h.vm.materials().filter(func(m): return m is ShaderMaterial and m.shader == preload("res://player/viewmodel.gdshader"))
	_check(mats.size() > 0, "  ...on the viewmodel shader (%d surfaces)" % mats.size())
	var arm_mat: ShaderMaterial = null
	for m in mats:
		if m.get_shader_parameter("arms"):
			arm_mat = m
	_check(arm_mat != null and float(arm_mat.get_shader_parameter("bare")) > 0.5, "  ...bare skin, not gloves")
	# Idle: low in the view, both hands in front of you.
	gs.craving = 90.0
	await _frames(30)
	var r: Vector3 = _hand_pos(h, "R")
	var l: Vector3 = _hand_pos(h, "L")
	_check(r.x > 0.05 and l.x < -0.05 and r.y < -0.08 and l.y < -0.08 and r.z < -0.25, "  idle: both hands low in the view (%s, %s)" % [r, l])

	# The look drags the hands; walking bobs them.
	p.set_look(0.0, 0.0)
	await _frames(3)
	var before: Vector3 = _hand_pos(h, "R")
	p.set_look(0.4, 0.0)
	await _frames(2)
	_check((_hand_pos(h, "R") - before).length() > 0.0005, "  turning the view swings the hands")

	# Reaching.
	var rest: Vector3 = _hand_pos(h, "R")
	h.reach(p.global_position + Vector3(0, 1.4, -1.5), true)
	await _frames(12)
	var reaching: Vector3 = _hand_pos(h, "R")
	_check(reaching.z < rest.z - 0.04 and reaching.y > rest.y + 0.03, "  reach: the right hand goes out and up (%s -> %s)" % [rest, reaching])
	await _frames(60)
	_check((_hand_pos(h, "R") - rest).length() < 0.04, "  ...and comes back")

	# The sickness: tremor grows, the skin goes grey, sweat comes.
	var jitter := func(level: float) -> float:
		gs.craving = level
		await _frames(30)
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for i in 90:
			await _frames(1)
			var q: Vector3 = _hand_pos(h, "L")
			lo = lo.min(q)
			hi = hi.max(q)
		return (hi - lo).length()
	var well: float = await jitter.call(95.0)
	var sick: float = await jitter.call(2.0)
	_check(sick > well * 2.0, "withdrawal: the hands shake (%.4f well, %.4f sick)" % [well, sick])
	_check(float(arm_mat.get_shader_parameter("sick")) > 0.5 and float(arm_mat.get_shader_parameter("sweat")) > 0.5, "  ...grey and sweating")
	gs.craving = 90.0
	await _frames(30)
	_check(float(arm_mat.get_shader_parameter("sick")) < 0.05, "  ...and clear again when you're well")

	# Carrying what you lifted.
	_check(h.shown_item == "", "carrying: nothing in hand to start with")
	gs.inventory.append("charger")
	gs.inventory_changed.emit()
	await _frames(40)
	_check(h.shown_item == "charger" and h._item != null and h._item.visible, "  a charger lifted shows in the hand")
	gs.inventory.clear()
	gs.inventory_changed.emit()
	await _frames(20)
	_check(h._item == null, "  ...and is gone when it's handed over")
	var jobs := root.get_node("Jobs")
	jobs.job = {"kind": "dock", "holding": true}
	await _frames(40)
	_check(h._box_prop.visible, "  a dock box is held in both hands")
	_check(absf(_hand_pos(h, "R").x - _hand_pos(h, "L").x) < 0.5 and _hand_pos(h, "R").x > 0.1, "  ...one hand each side")
	jobs.job = {}
	await _frames(40)
	_check(not h._box_prop.visible, "  ...and put down")

	# The Walkman.
	var wm := root.get_node("Walkman")
	var tape: String = wm.TAPES.keys()[0]
	wm.add_tape(tape)
	_check(h._walkman != null, "walkman: a model for it")
	wm.play(tape)
	await _frames(20)
	_check(h._walkman != null and h._walkman.visible, "  a tape started: the Walkman is in hand")
	var up: Vector3 = _hand_pos(h, "L")
	await _frames(150)
	var held: Vector3 = _hand_pos(h, "L")
	_check(h._walkman.visible and held.y < up.y - 0.03, "  ...then lowered, still held while it plays (%s -> %s)" % [up, held])
	wm.stop()
	await _frames(150)
	_check(not h._walkman.visible, "  stopped: put away")

	# Taking a dose: pills to the mouth, the rest out of the picture with a bowed head.
	gs.emit_signal("dose_taken", "oxy", "relief")
	await _frames(40)
	_check(h._use_t >= 0.0 and h._use_pills, "dose: a pill goes to the mouth")
	await _frames(240)
	_check(h._use_t < 0.0, "  ...and it's over")
	gs.emit_signal("dose_taken", "heroin", "relief")
	await _frames(30)
	var dipped: float = p.fp_dip
	_check(h._use_t >= 0.0 and not h._use_pills and dipped > 0.05, "  a shot: hands drop away, the head bows (%.2f)" % dipped)
	await _frames(240)
	_check(p.fp_dip < 0.01, "  ...and the head comes back up")

	# A shown pill is not left in the air.
	_check(not h._pill.visible, "  no pill left floating")

	# Third person: no hands.
	gfx.set_first_person(false)
	await _frames(5)
	_check(p.story_hands == null, "third person: no hands")
	gfx.set_first_person(true)
	await _frames(5)
	_check(p.story_hands != null, "  ...and back in first person they return")
