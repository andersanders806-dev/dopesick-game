extends "res://dev-tools/smoke_test_3d.gd"
## RICHTER 8.0 (zombie mode, Z4c): the warning, the quake, the end, the reduced shake, the pools.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_quake.gd
func _run() -> void:
	await _zombie_quake_checks(_gs())

## What City3D says a light's energy is (its full one, by the hour and its cell's wake fade).
func _truth(e: Array, city: Node) -> float:
	return float(e[1]) * float(city._lamps_on) * float(e[3])

func _flush_pad(holder: Node) -> void:
	var pad := holder.get_node_or_null("PadRumble")
	if pad != null:
		pad.flush()

func _zombie_quake_checks(_gs_node: Node) -> void:
	await _section("Dead Block: RICHTER 8.0 -- warning, quake, end, reduced shake, pools")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gfx := root.get_node("Graphics")
	zm.leave()
	zm.begin(false)
	gfx.camera_motion = true
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
	gfx.set_first_person(true)
	player.global_position = Vector3(0, 0, -3)
	await _frames(4)
	var q = block.quake
	_check(q != null and q.is_inside_tree(), "  the block adds a Quake")
	q.auto = false
	block.tsunami.auto = false
	block.set_process(false)
	var holder: Node = player.get_node("WeaponHolder")
	holder.set_process(false)
	var feel: Node = holder.feel
	feel.auto = false
	feel.reset_state()
	var hud := get_first_node_in_group("zombie_hud")
	var seismo: Control = hud.seismo
	var lamps: Array = []
	for e in city._night_lights:
		var l := e[0] as Light3D
		if l.get_parent().name.begins_with("Streetlight") and l.is_visible_in_tree():
			lamps.append(e)
	_check(lamps.size() >= 6, "  street lights found (%d)" % lamps.size())
	var orphans0: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var kids0: int = q.get_child_count()

	# --- warning
	var rumble_calls := [0]
	var PadRumble := load("res://player/PadRumble.gd")
	PadRumble.calls.clear()
	PadRumble.sink = func(_w, _s, _d): rumble_calls[0] += 1
	zm.surge_warning.emit()
	_check(q.phase == q.Phase.WARNING and seismo.shown, "  the warning starts the phase and the seismograph")
	var min_ratio := 1.0
	var max_trauma_early := 0.0
	var trauma_mid := 0.0
	var dim_seen := 0
	var steps := 150
	for i in steps:
		q.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		seismo.advance(1.0 / 60.0)
		_flush_pad(holder)
		if i == 30:
			max_trauma_early = feel.trauma
		if i == 120:
			trauma_mid = feel.trauma
		for e in lamps:
			var r: float = (e[0] as Light3D).light_energy / float(e[1])
			min_ratio = minf(min_ratio, r)
			if r < 0.5:
				dim_seen += 1
	_check(trauma_mid > max_trauma_early + 0.05 and trauma_mid > 0.25, "  camera trauma ramps through the warning (%.2f at 0.5 s -> %.2f at 2 s)" % [max_trauma_early, trauma_mid])
	_check(q.alarms_playing() >= 3, "  car alarms ring on parked cars (%d)" % q.alarms_playing())
	_check(dim_seen > 20 and min_ratio < 0.4, "  street lights flicker (%d dim samples, lowest %.2f of full)" % [dim_seen, min_ratio])
	_check(q.dust_active() >= 1, "  dust falls from the buildings (%d sites)" % q.dust_active())
	_check(q.rumble_pulses >= 5 and PadRumble.calls.size() >= 5 and rumble_calls[0] >= 5, "  the pad rumble ramps (%d pulses, %d reached the pad)" % [q.rumble_pulses, rumble_calls[0]])
	_check(seismo.value > 1.5 and seismo.value < 4.0 and seismo.amplitude > 0.1, "  the readout has begun to climb (%.1f)" % seismo.value)
	hud._process(0.0)
	_check(not hud.double_label.visible, "  no Double Points in the warning")

	# --- quake
	zm.surge_started.emit()
	zm.surge_active = true  # the surge logic's own flag (npc/ZombieSurge.gd), not Quake's
	_check(q.phase == q.Phase.QUAKE, "  started: quake phase")
	var peak_trauma := 0.0
	var peak_value := 0.0
	for i in 60 * 5:
		q.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
		seismo.advance(1.0 / 60.0)
		peak_trauma = maxf(peak_trauma, feel.trauma)
		peak_value = maxf(peak_value, seismo.value)
		if i == 20:
			_check(q.stinger_plays == 0, "  the stinger waits for 8.0")
	_check(absf(peak_value - 8.0) < 0.01 and absf(seismo.value - 8.0) < 0.01 and seismo.readout() == "RICHTER 8.0", "  the seismograph reaches 8.0 (%s)" % seismo.readout())
	_check(q.stinger_plays == 1 and q._stinger_p.playing, "  the stinger plays once (%d)" % q.stinger_plays)
	_check(peak_trauma > 0.85, "  heavy shake (peak trauma %.2f)" % peak_trauma)
	_check(q.cracks_visible() >= 4 and q.chunks_visible() >= 3, "  ground cracks (%d) and rubble (%d)" % [q.cracks_visible(), q.chunks_visible()])
	_check(q.roars_playing() == 2 and q.roar_db() > -30.0, "  the horde roar is up and rising (%.1f dB)" % q.roar_db())
	_check(hud.double_label != null, "  the HUD has DOUBLE POINTS")
	hud._process(0.0)
	_check(hud.double_label.visible, "  DOUBLE POINTS shows on the HUD during the surge")
	_check(seismo.visible and seismo.modulate.a > 0.9, "  the seismograph is up")
	# keep going: the shake dies away on its own, aftershocks aside
	for i in 60 * 6:
		q.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
	_check(q.trauma_target < 0.2, "  the shake decays after the strong part (target %.2f)" % q.trauma_target)
	_check(q.stinger_plays == 1, "  still one stinger")

	# --- end
	var loud: float = q.roar_db()
	zm.surge_ended.emit()
	zm.surge_active = false
	_check(q.phase == q.Phase.ENDING, "  ended: fading")
	hud._process(0.0)
	_check(not hud.double_label.visible, "  DOUBLE POINTS is gone from the HUD with the surge")
	for i in 60 * 1:
		q.advance(1.0 / 60.0)
		seismo.advance(1.0 / 60.0)
	_check(q.roar_db() < loud - 8.0, "  the roar fades (%.1f -> %.1f dB)" % [loud, q.roar_db()])
	for i in 60 * 3:
		q.advance(1.0 / 60.0)
		seismo.advance(1.0 / 60.0)
		feel.advance(1.0 / 60.0)
	_check(q.phase == q.Phase.IDLE and q.roars_playing() == 0 and q.alarms_playing() == 0, "  idle again: roar and alarms stopped")
	var restored := true
	for e in lamps:
		if absf((e[0] as Light3D).light_energy - _truth(e, city)) > 0.001:
			restored = false
	if not restored:
		for e in lamps:
			var l := e[0] as Light3D
			if absf(l.light_energy - _truth(e, city)) > 0.001:
				print("   lamp ", l.get_path(), " energy ", l.light_energy, " base ", e[1], " on ", city._lamps_on, " wake ", e[3], " vis ", l.visible)
	_check(restored, "  every street light is back to its energy")
	_check(q.cracks_visible() == 0 and q.chunks_visible() == 0 and q.dust_active() == 0, "  cracks, rubble and dust cleared")
	_check(not seismo.visible, "  seismograph hidden")

	# --- reduced shake
	feel.reset_state()
	gfx.camera_motion = true
	zm.surge_warning.emit()
	zm.surge_started.emit()
	for i in 60:
		q.advance(1.0 / 60.0)
	var full: float = feel.trauma
	zm.surge_ended.emit()
	for i in 60 * 3:
		q.advance(1.0 / 60.0)
	feel.reset_state()
	gfx.camera_motion = false
	zm.surge_warning.emit()
	zm.surge_started.emit()
	for i in 60:
		q.advance(1.0 / 60.0)
	var reduced: float = feel.trauma
	zm.surge_ended.emit()
	for i in 60 * 3:
		q.advance(1.0 / 60.0)
	gfx.camera_motion = true
	_check(reduced < full * 0.4 and reduced > 0.0, "  Camera motion off lowers the shake (%.2f vs %.2f)" % [reduced, full])

	# --- third person: the camera is jolted through the player's kick
	gfx.set_first_person(false)
	await _frames(3)
	player._kick = 0.0
	zm.surge_warning.emit()
	zm.surge_started.emit()
	for i in 30:
		q.advance(1.0 / 60.0)
	var kick_full: float = player._kick
	player._kick = 0.0
	gfx.camera_motion = false
	q.advance(1.0 / 60.0)
	var kick_off: float = player._kick
	gfx.camera_motion = true
	zm.surge_ended.emit()
	for i in 60 * 3:
		q.advance(1.0 / 60.0)
	_check(kick_full > 0.4 and kick_off == 0.0, "  third person shakes through the player's kick (%.2f) and not with Camera motion off (%.2f)" % [kick_full, kick_off])
	gfx.set_first_person(true)
	await _frames(3)

	# --- the real surge logic reaches it: its warning starts the build-up, and a run that ends
	# mid-surge (it aborts without surge_ended) lets everything go
	_check(block.surge != null and block.surge.trigger(25), "  the real ZombieSurge starts a surge")
	_check(q.phase == q.Phase.WARNING, "  its warning signal starts Quake's warning")
	for i in 30:
		q.advance(1.0 / 60.0)
	zm.over = true
	q.advance(1.0 / 60.0)
	_check(q.phase == q.Phase.ENDING, "  the run ending mid-surge fades it out")
	zm.over = false
	block.surge._abort()
	for i in 60 * 3:
		q.advance(1.0 / 60.0)
	_check(q.phase == q.Phase.IDLE and q.alarms_playing() == 0, "  and it ends clean")

	# --- again and again: pools stay fixed, nothing leaks
	for n in 3:
		zm.surge_warning.emit()
		zm.surge_started.emit()
		for i in 60 * 9:
			q.advance(1.0 / 30.0)
		_check(q.cracks_visible() <= q.CRACKS and q.chunks_visible() <= q.CHUNKS and q.alarms_playing() <= q.ALARMS, "  round %d within the caps (%d cracks, %d chunks, %d alarms)" % [n + 1, q.cracks_visible(), q.chunks_visible(), q.alarms_playing()])
		zm.surge_ended.emit()
		for i in 60 * 3:
			q.advance(1.0 / 30.0)
	_check(q.get_child_count() == kids0, "  no node made by repeated surges (%d children)" % q.get_child_count())
	_check(q.cracks_made > 20, "  cracks were made and recycled (%d)" % q.cracks_made)
	# the signals also work with F10's helper and without a warning
	zm.surge_started.emit()
	q.advance(0.5)
	_check(q.phase == q.Phase.QUAKE and q.alarms_playing() >= 1, "  a surge with no warning still starts")
	zm.surge_ended.emit()
	for i in 60 * 3:
		q.advance(1.0 / 30.0)
	PadRumble.sink = Callable()
	# freeing it puts the lights back and leaves no orphans
	zm.surge_warning.emit()
	for i in 60:
		q.advance(1.0 / 60.0)
	block.quake = null
	q.free()
	var back := true
	for e in lamps:
		if absf((e[0] as Light3D).light_energy - _truth(e, city)) > 0.001:
			back = false
	_check(back, "  freeing the Quake mid-warning puts the lights back")
	await _frames(3)
	var orphans1: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_check(orphans1 <= orphans0, "  no orphan nodes (%d -> %d)" % [orphans0, orphans1])
	zm.leave()
