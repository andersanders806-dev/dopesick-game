extends "res://dev-tools/smoke_test_3d.gd"
## Tolerance eats the high, and withdrawal hits the stealth verbs (the proto-sick-stealth branch):
##   - GameState.high_feel() falls with tolerance and floors; the relief is the same either way; the warm
##     part (high_glow, the HUD's wash, the music) follows it; once a run the thought comes
##   - GameState.emit_noise(): a guard hears it inside its radius (half through a wall), is more suspicious
##     the nearer it was, turns to look and barks -- and does nothing outside it
##   - withdrawal's bursts (player/SickBursts.gd): never when well, tell then burst when sick, shorter and
##     louder with the sickness, held back up to four seconds and then louder
##   - the grab: longer with the sickness, fumbled above 0.6 with a noise, and the thing can be taken again
## Withdrawal stays ON here (no --no-sick).
##   godot --headless --path . -s res://dev-tools/smoke_sick_stealth.gd

var _noises: Array = []

func _on_noise(pos: Vector3, loud: float, kind: String) -> void:
	_noises.append([pos, loud, kind])

## Steps a node's _process by hand, so that time in a check is exact.
func _step(node: Node, seconds: float) -> void:
	var n := int(round(seconds * 60.0))
	for i in n:
		node._process(1.0 / 60.0)

func _fresh(gs: Node, craving := 100.0) -> void:
	gs.start_run()
	gs.intro_pending = false
	gs.mode = "story"
	gs.no_sickness = false
	gs.clock_running = false
	gs.craving = craving

func _run() -> void:
	var gs := _gs()
	var gfx := root.get_node("Graphics")
	_fresh(gs)
	gfx.set_first_person(true)
	gs.noise_made.connect(_on_noise)
	await _load("res://world/Apartment3D.tscn")
	await _frames(10)
	var p := _player()
	p.dialogue_active = false
	gs.clock_running = false
	gs.craving = 100.0

	await _section("Tolerance eats the high")
	_check(is_equal_approx(gs.high_feel("heroin"), 1.0), "naive: a dose feels like 1.0")
	# Regular use: ~3 doses a day, each read before it lands, the day's hours halving tolerance every 36.
	var feels: Array = []
	var day_first: Array = []
	for day in 6:
		for dose in 3:
			var f: float = gs.high_feel("heroin")
			if dose == 0:
				day_first.append(f)
			feels.append(f)
			gs.tolerance["opioid"] = gs.tolerance.get("opioid", 0.0) + 1.3
			gs.advance_clock(8.0 * 60.0)
	print("  (first dose of each day feels: %s)" % [day_first.map(func(v): return snappedf(v, 0.01))])
	_check(day_first[0] > 0.95, "day 1: warm and good (%.2f)" % day_first[0])
	_check(day_first[3] < 0.5 and day_first[4] <= 0.4, "day 4-5 of regular use: it mostly stops the pain (%.2f, %.2f)" % [day_first[3], day_first[4]])
	_check(feels.all(func(v): return v >= gs.HIGH_FEEL_FLOOR and v <= 1.0), "always between the floor and 1.0")
	gs.tolerance["opioid"] = 500.0
	_check(is_equal_approx(gs.high_feel("heroin"), gs.HIGH_FEEL_FLOOR), "a huge tolerance floors at %.2f" % gs.HIGH_FEEL_FLOOR)
	gs.tolerance.clear()
	_check(gs.high_feel("oxy") == 1.0, "untouched: 1.0")
	gs.tolerance["opioid"] = 3.0
	_check(is_equal_approx(gs.high_feel("heroin"), gs.high_feel("oxy")) and gs.high_feel("alprazolam") == 1.0, "tolerance is the class's: cross-tolerance in it, none outside")

	# Relief: the same from a naive dose and a tolerant one (risk off, so chance doesn't enter).
	var relief := func(tol: float) -> float:
		gs.tolerance["opioid"] = tol
		gs.craving = 0.0
		var outcome: String = gs.take_drug("heroin", 1.0, 0.0)
		return gs.craving if outcome == "relief" else -1.0
	var naive_relief: float = relief.call(0.0)
	var tolerant_relief: float = relief.call(9.0)
	_check(naive_relief > 90.0 and is_equal_approx(naive_relief, tolerant_relief), "relief is the same at full strength, naive or not (%.0f / %.0f)" % [naive_relief, tolerant_relief])
	gs.tolerance["opioid"] = 4.0
	gs.resp_load = 0.0
	gs.take_drug("heroin", 1.0, 1.0)
	_check(gs.last_risk > 0.0 and gs.last_risk < 0.006, "the overdose risk is still worked from tolerance, untouched (%.4f)" % gs.last_risk)

	# (Six days of clock jumps tripped the rent and put us out of the flat: start over in it.)
	_fresh(gs)
	gs.rent_stage = 0
	await _load("res://world/Apartment3D.tscn")
	await _frames(20)
	p = _player()
	p.dialogue_active = false
	# The warm part.
	_fresh(gs, 20.0)
	gs.take_drug("heroin", 1.0, 0.0)
	_check(is_equal_approx(gs.high_felt, 1.0), "a naive dose records feel 1.0")
	_check(gs.high_glow() < 0.05, "  the glow hasn't come up yet at the moment of the dose (%.2f)" % gs.high_glow())
	gs.run_time += 10.0
	gs.craving = 90.0
	var glow_naive: float = gs.high_glow()
	_check(glow_naive > 0.9, "  ten seconds in it's at the top (%.2f)" % glow_naive)
	gs.run_time += 200.0
	_check(gs.high_glow() < 0.02, "  and it's worn off a few minutes on (%.2f)" % gs.high_glow())
	var hud := get_first_node_in_group("hud")
	_fresh(gs, 20.0)
	gs.take_drug("heroin", 1.0, 0.0)
	gs.run_time += 10.0
	gs.craving = 95.0
	await _frames(6)
	var tint_naive: float = hud._high_tint.color.a if hud and hud._high_tint else -1.0
	var hud_mat: ShaderMaterial = hud.get_node("PostFX").material
	# (The golden wash was cut by about a third after the review: it washed the whole frame yellow and faded the HUD.)
	_check(tint_naive > 0.015 and tint_naive < 0.03 and float(hud_mat.get_shader_parameter("high")) > 0.9 and hud_mat.shader == hud.POST_FULL,
		"naive: the HUD washes the frame golden (tint alpha %.3f, bloom shader high %.2f)" % [tint_naive, float(hud_mat.get_shader_parameter("high"))])
	var sfx := root.get_node("SFX")
	_check(sfx._boost_db > 2.5, "  and the music swells (%.1f dB)" % sfx._boost_db)
	gs.tolerance["opioid"] = 8.0
	gs.craving = 20.0
	gs.run_time += 400.0
	gs.take_drug("heroin", 1.0, 0.0)
	gs.run_time += 10.0
	gs.craving = 95.0
	await _frames(6)
	var feel_tol: float = gs.high_felt
	var tint_tol: float = hud._high_tint.color.a if hud and hud._high_tint else -1.0
	_check(feel_tol < 0.3 and tint_tol < tint_naive * 0.4 and float(hud_mat.get_shader_parameter("high")) < 0.3, "tolerant: flat -- feel %.2f, the wash %.3f against %.3f" % [feel_tol, tint_tol, tint_naive])
	_check(sfx._boost_db < 1.2, "  and the music barely moves (%.1f dB)" % sfx._boost_db)
	# Methadone has no lift at all.
	_fresh(gs, 20.0)
	gs.take_drug("methadone", 1.0, 0.0)
	gs.run_time += 10.0
	_check(gs.high_glow() == 0.0 and gs.high_felt == 0.0, "methadone: stops the sickness, no glow at all")
	# The thought, once a run.
	_fresh(gs, 20.0)
	var gfx_node := root.get_node("Graphics")
	hud = get_first_node_in_group("hud")
	hud.show_subtitle("", 0.1)
	await _frames(12)
	_check(not gs.flat_noted, "no thought yet in a fresh run")
	gs.tolerance["opioid"] = 1.0
	gs.take_drug("heroin", 1.0, 0.0)
	_check(not gs.flat_noted, "  a dose that still feels good (%.2f) doesn't bring it" % gs.high_felt)
	gs.tolerance["opioid"] = 9.0
	gs.craving = 20.0
	gs.take_drug("heroin", 1.0, 0.0)
	_check(gs.flat_noted, "  a flat one (%.2f) does" % gs.high_felt)
	await create_timer(3.4).timeout
	_check(gs.last_thought == gs.FLAT_THOUGHT and gs.FLAT_THOUGHT.contains("doesn't even feel good"), "  \"%s\"" % gs.last_thought)
	hud = get_first_node_in_group("hud")
	hud.show_subtitle(gs.FLAT_THOUGHT, 6.5, "thought")
	await _frames(40)
	_check(hud._sub.visible and hud._sub.text == gs.FLAT_THOUGHT and hud._sub.get_theme_font_size("font_size") >= 28 and hud._sub.anchor_top > 0.6,
		"  shown as an inner thought: %d px, %.0f%% down, lower-centre" % [hud._sub.get_theme_font_size("font_size"), hud._sub.anchor_top * 100.0])
	_check(not gs.FLAT_THOUGHT.contains("0.") and not gs.FLAT_THOUGHT.contains("%"), "  no numbers on the screen")
	gs.last_thought = ""
	gs.craving = 20.0
	gs.take_drug("heroin", 1.0, 0.0)
	await create_timer(3.4).timeout
	_check(gs.last_thought == "", "  and it isn't said twice")

	await _hearing_checks(gs)
	print("  (scene after the hearing checks: %s, player %s)" % [current_scene.name if current_scene else "none", _player()])
	await _burst_checks(gs, _player())
	await _grab_checks(gs, _player())

func _hearing_checks(gs: Node) -> void:
	await _section("Hearing: a guard turns to a noise")
	_fresh(gs)
	var stage := Node3D.new()
	stage.name = "HearingStage"
	current_scene.add_child(stage)
	var guard: Node3D = load("res://npc/Guard3D.tscn").instantiate()
	guard.role = "clerk_convenience"
	guard.vision_range = 6.0
	guard.base_facing_deg = 0.0
	guard.sweep_arc_deg = 0.0
	stage.add_child(guard)
	guard.global_position = Vector3(40.0, 0.0, 40.0)
	# A wall to the +Z side of the guard, 2 m off.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(8.0, 3.0, 0.2)
	wall.add_child(shape)
	stage.add_child(wall)
	wall.global_position = Vector3(40.0, 1.5, 42.0)
	await _frames(4)
	var heard: Array = []
	guard.heard_noise.connect(func(kind, strength): heard.append([kind, strength]))
	gs.clock = 14 * 60
	var s0: float = guard.suspicion
	# Outside the radius: nothing.
	gs.emit_noise(guard.global_position + Vector3(-9.0, 0.0, 0.0), 6.0, "cough")
	await _frames(2)
	_check(guard.suspicion == s0 and heard.is_empty() and guard._hear_t <= 0.0, "a noise outside its radius does nothing (9 m, loud 6 m)")
	# Inside, near then far.
	gs.emit_noise(guard.global_position + Vector3(-1.0, 0.0, 0.0), 6.0, "cough")
	await _frames(2)
	var near_bump: float = guard.suspicion - s0
	_check(near_bump > 0.1 and heard.size() == 1, "inside the radius: suspicion jumps (+%.2f at 1 m)" % near_bump)
	guard.reset_suspicion()
	guard._hear_t = 0.0
	guard._bark_cd = 0.0
	gs.emit_noise(guard.global_position + Vector3(-5.0, 0.0, 0.0), 6.0, "cough")
	await _frames(2)
	var far_bump: float = guard.suspicion
	_check(far_bump > 0.0 and far_bump < near_bump * 0.5, "  nearer is worse (+%.2f at 5 m against +%.2f at 1 m)" % [far_bump, near_bump])
	# It makes them look, not raise the alarm.
	guard.reset_suspicion()
	for i in 6:
		gs.emit_noise(guard.global_position + Vector3(-0.5, 0.0, 0.0), 9.0, "drop")
	await _frames(2)
	_check(guard.suspicion <= guard.NOISE_CAP + 0.001 and not guard._alarm_raised, "noise alone never raises the alarm (capped at %.2f)" % guard.suspicion)
	# Turn.
	guard.reset_suspicion()
	guard._hear_t = 0.0
	guard._hear_blend = 0.0
	guard.last_bark = ""
	guard._bark_cd = 0.0
	gs.emit_noise(guard.global_position + Vector3(0.0, 0.0, -3.0), 6.0, "cough")
	await _frames(25)
	_check(guard._hear_t > 0.0 and guard._hear_blend > 0.9, "the sweep is overridden: the head turns to it (blend %.2f)" % guard._hear_blend)
	_check(absf(angle_difference(deg_to_rad(guard._hear_deg), deg_to_rad(-90.0))) < 0.05, "  toward the sound, not the room (%.0f deg)" % guard._hear_deg)
	_check(guard.last_bark != "", "  with a bark: \"%s\"" % guard.last_bark)
	var shud := get_first_node_in_group("hud")
	_check(shud._sub.visible and shud._sub.text.contains(guard.last_bark), "  and a subtitle for it (%s)" % shud._sub.text)
	_check(guard._flinch_t >= 0.0 and absf(angle_difference(guard.body.rotation.y, deg_to_rad(90.0 - guard._hear_deg))) < 0.8, "  the shoulders came round with the head (body yaw %.0f deg, wanted %.0f)" % [rad_to_deg(guard.body.rotation.y), 90.0 - guard._hear_deg])
	var voice := root.get_node("Voice")
	_check(voice.bark_stream("Clerk", "Hm?") != null and voice.bark_stream("Security", "Who's there?") != null and voice.bark_stream("Clerk", "What was that?") != null,
		"  and the bark has a voice (baked Piper lines, not silence)")
	# The cone is the truth: it follows the turn.
	var verts: PackedVector3Array = (guard.vision_cone.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mid: Vector3 = verts[verts.size() / 2]
	_check(mid.z < -2.0 and absf(mid.x) < 4.0, "  the vision cone swings with it (centre of the cone at %s)" % mid)
	# And back.
	await _frames(int((guard.HEAR_TURN_TIME + 2.5) * 60.0))
	_check(guard._hear_blend < 0.05, "after a couple of seconds it eases back to the sweep (blend %.2f)" % guard._hear_blend)
	# A bark is not spammed.
	guard.last_bark = ""
	guard._hear_t = 0.0
	guard._bark_cd = 3.0
	gs.emit_noise(guard.global_position + Vector3(-1.0, 0.0, 0.0), 6.0, "cough")
	_check(guard.last_bark == "", "  no second bark inside its cooldown")
	# Walls halve it.
	guard._bark_cd = 0.0
	guard.reset_suspicion()
	guard._hear_t = 0.0
	heard.clear()
	var behind := guard.global_position + Vector3(0.0, 0.0, 4.5)
	gs.emit_noise(behind, 6.0, "cough")
	await _frames(2)
	_check(heard.is_empty(), "through the wall 6 m of noise carries 3: 4.5 m is out of earshot")
	gs.emit_noise(guard.global_position + Vector3(0.0, 0.0, 2.7), 6.0, "cough")
	await _frames(2)
	_check(heard.size() == 1, "  2.7 m, behind it, it is heard")
	var through_bump: float = guard.suspicion
	guard.reset_suspicion()
	guard._hear_t = 0.0
	heard.clear()
	gs.emit_noise(guard.global_position + Vector3(-2.7, 0.0, 0.0), 6.0, "cough")
	await _frames(2)
	_check(guard.suspicion > through_bump * 1.4, "  and less than the same distance in the open (+%.2f through, +%.2f open)" % [through_bump, guard.suspicion])
	# A shop that isn't active has its vision off: it is deaf too.
	guard.reset_suspicion()
	guard.vision_range = 0.0
	gs.emit_noise(guard.global_position + Vector3(-1.0, 0.0, 0.0), 6.0, "cough")
	await _frames(2)
	_check(guard.suspicion == 0.0, "a shop you are not in (vision off) hears nothing")
	guard.vision_range = 6.0
	# The hour scales it, as it scales sight.
	guard.reset_suspicion()
	guard._hear_t = 0.0
	gs.emit_noise(guard.global_position + Vector3(-1.0, 0.0, 0.0), 6.0, "cough")
	var base_bump: float = guard.suspicion
	guard.reset_suspicion()
	gs.clock = 3 * 60
	guard._hear_t = 0.0
	gs.emit_noise(guard.global_position + Vector3(-1.0, 0.0, 0.0), 6.0, "cough")
	_check(guard.suspicion < base_bump, "the small hours' tired clerk is less sharp than the day's (%.2f < %.2f): the existing alertness applies" % [guard.suspicion, base_bump])
	gs.clock = 14 * 60
	stage.queue_free()

func _burst_checks(gs: Node, p: Node3D) -> void:
	await _section("Withdrawal's bursts")
	_fresh(gs)
	p.dialogue_active = false
	var sb: Node = p.sick_bursts
	_check(sb != null, "the player has SickBursts")
	_noises.clear()
	gs.craving = 100.0
	sb._timer = 0.0
	_step(sb, 200.0)
	_check(sb.bursts == 0 and sb.state == sb.State.IDLE, "well: no bursts, however long (%d in 200 s)" % sb.bursts)
	gs.craving = 25.0
	sb._timer = 0.0
	_step(sb, 100.0)
	_check(sb.bursts == 0, "  a little sore (sickness %.2f, under %.2f): none" % [gs.sickness(), sb.SICK_FROM])
	# Interval and loudness by sickness.
	var spread := func(craving: float) -> Array:
		gs.craving = craving
		var lo := 1e9
		var hi := 0.0
		for i in 200:
			var v: float = sb._roll_interval()
			lo = minf(lo, v)
			hi = maxf(hi, v)
		return [lo, hi]
	var mild: Array = spread.call(35.0 * 0.69)
	var severe: Array = spread.call(0.0)
	_check(mild[0] >= 44.0 and mild[1] <= 91.0, "mild sickness: every 45-90 s (%.0f-%.0f)" % mild)
	_check(severe[0] >= 14.0 and severe[1] <= 31.0, "severe: every 15-30 s (%.0f-%.0f)" % severe)
	gs.craving = 35.0 * 0.7
	var loud_mild: float = sb.loudness_now()
	gs.craving = 0.0
	var loud_severe: float = sb.loudness_now()
	_check(absf(loud_mild - 4.0) < 0.3 and absf(loud_severe - 9.0) < 0.01, "louder with it: %.1f m mild, %.1f m severe" % [loud_mild, loud_severe])
	# A burst: tell, then it lets go and is heard.
	gs.craving = 3.0
	sb.stifle_override = 0
	_noises.clear()
	var hands = p.story_hands
	sb.begin_tell()
	_check(sb.state == sb.State.TELL and sb.warning(), "sick: a tell first")
	_step(sb, 0.3)
	_check(_noises.is_empty(), "  nothing heard during it")
	_check(hands != null and hands._cover_want, "  the hand goes to the mouth")
	_check(absf(p.fp_hitch) > 0.0, "  the view hitches (%.3f rad)" % p.fp_hitch)
	_step(sb, 0.8)
	_check(sb.state == sb.State.BURST and _noises.size() >= 1, "  then the burst, and it is heard (%s)" % [_noises.map(func(n): return n[2])])
	var n0: Array = _noises[0]
	var expected: float = sb.loudness_now() * float(sb.KINDS[sb.last_kind]["loud"])
	_check(absf(n0[1] - expected) < 0.01 and n0[1] >= 2.0 and n0[1] <= 10.0, "  %.1f m of %s" % [n0[1], n0[2]])
	_check(n0[0].distance_to(p.global_position) < 0.01, "  from where the player stands")
	_step(sb, 3.0)
	_check(sb.state == sb.State.IDLE and not hands._cover_want, "  and it passes: hand down, timer re-rolled")
	# Every kind has a real sound.
	var sounds_ok := true
	for k in ["cough", "cough_fit", "cough_stifled", "stifle_strain", "sniff", "breath_catch", "retch", "drop", "exhale_flat", "dose_swell"]:
		sounds_ok = sounds_ok and root.get_node("SFX").SICK.has(k) and (root.get_node("SFX").SICK[k] as Array).all(func(s): return s != null and s.get_length() > 0.3)
	_check(sounds_ok, "every kind has a recorded sound behind it")
	# Stifling.
	_noises.clear()
	gs.craving = 3.0
	sb.stifle_override = 1
	sb.begin_tell()
	_step(sb, 1.1)
	_check(sb.state == sb.State.HOLD, "holding the button at the end of the tell: held back")
	_step(sb, 2.0)
	_check(sb.state == sb.State.HOLD and _noises.is_empty(), "  still held 2 s on, and silent")
	_check(sb.tunnel > 0.3 and sb.speed_mult() < 0.8, "  the cost is felt: the view closes in (%.2f) and you move slower (x%.2f)" % [sb.tunnel, sb.speed_mult()])
	_check(sb.hold_left() > 1.5 and sb.hold_left() < 2.2, "  with the bar running down (%.1f s left)" % sb.hold_left())
	_step(sb, 2.0)
	_check(sb.state == sb.State.BURST and sb.last_broke_out, "  at four seconds it breaks out")
	var broke: float = sb.last_loudness
	var plain_expected: float = sb.loudness_now() * float(sb.KINDS[sb.last_kind]["loud"])
	_check(absf(broke - plain_expected * sb.BREAKOUT_LOUDER) < 0.01, "  louder: %.1f m against %.1f m (x%.1f)" % [broke, plain_expected, sb.BREAKOUT_LOUDER])
	_step(sb, 5.0)
	_check(sb.tunnel < 0.05 and sb.speed_mult() == 1.0, "  and the tunnel lifts once it is out")
	# Letting go early lets it out at its usual volume.
	_noises.clear()
	sb.stifle_override = 1
	sb.begin_tell()
	_step(sb, 2.0)
	sb.stifle_override = 0
	_step(sb, 0.1)
	_check(sb.state == sb.State.BURST and not sb.last_broke_out, "letting go early: it comes out at once, not louder")
	_step(sb, 5.0)
	# The prompt.
	var hint = get_first_node_in_group("hud").find_child("StifleHint", true, false)
	_check(hint != null, "the HUD has the stifle prompt")
	sb.stifle_override = 0
	sb.begin_tell()
	for i in 4:
		await process_frame
	_check(hint != null and hint.visible and hint.plain().begins_with("Q") and hint.plain().contains("Hold it in"), "  shown during the tell: \"%s\"" % (hint.plain() if hint else ""))
	_step(sb, 5.0)
	for i in 4:
		await process_frame
	_check(hint != null and not hint.visible, "  and gone when it's over (never claims what isn't happening) [state %d, hint bursts %s vs %s]" % [sb.state, hint._bursts, sb])
	_check(InputMap.has_action("stifle") and InputMap.action_get_events("stifle").any(func(e): return e is InputEventKey) and InputMap.action_get_events("stifle").any(func(e): return e is InputEventJoypadMotion or e is InputEventJoypadButton), "an input action 'stifle' on the keyboard and the pad")
	gs.using_pad = true
	_check(gs.control_name("stifle") == "L2", "  the pad's glyph is L2")
	gs.using_pad = false
	# Not while talking.
	sb._timer = 0.0
	p.dialogue_active = true
	var count: int = sb.bursts
	_step(sb, 5.0)
	_check(sb.bursts == count and sb.state == sb.State.IDLE, "no burst in the middle of a conversation")
	p.dialogue_active = false
	sb._timer = 100.0

func _grab_checks(gs: Node, p: Node3D) -> void:
	await _section("The grab: tremor, and fumbles")
	_fresh(gs)
	var well: float = p.play_pickup(p.global_position + Vector3(0, 0, -1))
	gs.craving = 0.0
	var sick: float = p.play_pickup(p.global_position + Vector3(0, 0, -1))
	_check(absf(sick / well - 1.6) < 0.02, "a grab takes %.2f s sick against %.2f s well: +%.0f%%" % [sick, well, (sick / well - 1.0) * 100.0])
	gs.craving = 35.0 * 0.5
	var mid: float = p.play_pickup(p.global_position + Vector3(0, 0, -1))
	_check(mid > well * 1.1 and mid < sick, "  and in between in between (%.2f s)" % mid)
	# Fumble odds.
	gs.craving = 35.0 * 0.45
	_check(p.fumble_chance() == 0.0, "sickness 0.55: no fumbles")
	gs.craving = 0.0
	_check(absf(p.fumble_chance() - p.FUMBLE_MAX) < 0.001, "sickness 1.0: a %.0f%% chance" % (p.fumble_chance() * 100.0))
	gs.craving = 100.0
	p.fumble_roll_override = 0.0
	_check(not p.roll_fumble(), "well: never, whatever the roll")
	p.fumble_roll_override = -1.0
	# The sprint is loud.
	_noises.clear()
	p._sprinting = true
	p._step_timer = 0.0
	p._update_footsteps(0.1, true, 1.0)
	p._sprinting = false
	_check(_noises.any(func(n): return n[2] == "sprint" and n[1] > 3.0), "sprinting makes a footfall noise (%s)" % [_noises.map(func(n): return [n[2], n[1]])])
	# In a shop: grab it, fumble it, grab it again.
	var store := await _load("res://world/StoreConvenience3D.tscn")
	await _frames(20)
	p = _player()
	_fresh(gs, 0.0)
	gs.clock = 14 * 60
	var item: Node3D = store.item_slots[0]
	p.global_position = Vector3(item.global_position.x, 0.0, item.global_position.z + 1.0)
	p.reset_physics_interpolation()
	p.dialogue_active = false
	var inv0: int = gs.inventory.size()
	var drops: Array = []
	gs.noise_made.connect(func(pos, loud, kind): if kind == "drop": drops.append([pos, loud]))
	p.fumble_roll_override = 0.0
	item.interact(p)
	await create_timer(2.5).timeout
	_check(gs.inventory.size() == inv0 and is_instance_valid(item), "a fumbled grab takes nothing: the item is still there to take")
	_check(drops.size() == 1 and drops[0][1] >= 6.0, "  and the drop is a noise event (%.0f m)" % (drops[0][1] if drops.size() else 0.0))
	_check(item.dropped and item.is_in_group("interactable") and item.global_position.y < 0.3, "  it lies on the floor and can be picked up again (y %.2f)" % item.global_position.y)
	var guards := get_nodes_in_group("guards").filter(func(g): return store.is_ancestor_of(g))
	if not guards.is_empty() and not drops.is_empty():
		var g: Node = guards[0]
		print("  (the clerk %.1f m from the drop: heard '%s', suspicion %.2f, said '%s')" % [g.global_position.distance_to(drops[0][0]), g.last_heard, g.suspicion, g.last_bark])
	p.fumble_roll_override = 1.0
	await _frames(30)
	item.interact(p)
	await create_timer(2.5).timeout
	_check(gs.inventory.size() == inv0 + 1, "picked up again with steady hands: it is taken")
	p.fumble_roll_override = -1.0
