extends "res://dev-tools/smoke_test_3d.gd"
## The gun systems of SHIP 16 phase B1, on today's guns: every gun's data (sound set, handling block, recoil
## pattern, fire mode, optic), burst fire, tactical vs empty reloads and their foley, a sprint (or a swap)
## cutting a reload short and the reload resuming, the sprint-to-fire delay, the recoil pattern and its
## return to centre, the room's tail or the street's, a far shot for the gangsters, and no per-shot allocation.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_guns.gd
const GunSounds := preload("res://weapons/GunSounds.gd")
const GUN_IDS := ["pistol", "magnum", "smg", "ar", "shotgun", "sniper", "lmg"]

func _run() -> void:
	_data_checks()
	await _scene_checks()

func _wd(id: String) -> Resource:
	return load("res://weapons/%s.tres" % id)

# --- The data of every gun ---------------------------------------------------------------------------

func _data_checks() -> void:
	_section("Gun data: sound set, handling block, recoil pattern, fire mode, optic for every gun")
	var ids: Array = GUN_IDS + ["wonder"]
	for id in ids:
		for suffix in ["", "_up"]:
			var d: Resource = _wd(id + suffix)
			var tag: String = id + suffix
			_check(d != null, "%s loads" % tag)
			if d == null:
				continue
			var gone: PackedStringArray = GunSounds.missing(d)
			if id == "wonder":
				_check(GunSounds.shot(d, 0) != null and GunSounds.dry(d) != null and not bool(GunSounds.set_of(d)["real"]), "%s: the synthesised shots stand in (nothing real fits an arc caster)" % tag)
			else:
				_check(gone.is_empty() and d.sound_set == id, "%s: the full recorded set (fire, fire_up, distant, both tails, mech, dry) (%s missing)" % [tag, gone])
				_check(GunSounds.tail(d, true) != GunSounds.tail(d, false) and GunSounds.distant(d, 0) != GunSounds.shot(d, 0), "%s: indoor and outdoor tails and far shots are different recordings" % tag)
			_check(not d.upgraded or GunSounds.shot(d, 0) == (GunSounds.set_of(d)["fire_up"] as Array)[0], "%s: the upgraded gun plays the ringing take" % tag)
			var foley_ok := true
			for cue in d.foley:
				for stem in d.foley[cue]:
					foley_ok = foley_ok and GunSounds.file(String(stem)) != null
			_check(foley_ok, "%s: every foley file is there" % tag)
			var cues_ok: bool = not d.reload_cues_empty.is_empty()
			for list in [d.reload_cues_tactical, d.reload_cues_empty]:
				var last := 0.0
				for c in list:
					cues_ok = cues_ok and float(c[0]) > last and float(c[0]) < 1.0 and GunSounds.foley(d, String(c[1])) != null
					last = float(c[0])
			_check(cues_ok, "%s: reload foley cues ascend inside the reload and each has a sound" % tag)
			_check(d.ads_time > 0.1 and d.ads_time <= 0.45 and d.sprint_fire_delay >= 0.15 and d.sprint_fire_delay <= 0.3 and d.swap_time > 0.1,
				"%s: handling block (ads %.2f, sprint-to-fire %.2f, swap %.2f)" % [tag, d.ads_time, d.sprint_fire_delay, d.swap_time])
			_check(d.reload_for(false) < d.reload_for(true), "%s: tactical reload %.2f s is faster than empty %.2f s" % [tag, d.reload_for(false), d.reload_for(true)])
			_check(d.recoil_pattern.size() >= 8 and d.recoil_recover > 0.0 and d.kick_back > 0.0 and d.kick_up > 0.0 and d.kick_roll > 0.0 and d.recoil_ads < 1.0,
				"%s: recoil pattern (%d shots), recovery %.0f, visual kick" % [tag, d.recoil_pattern.size(), d.recoil_recover])
			_check(d.fire_mode() in ["semi", "auto", "burst"] and d.optic in ["none", "red_dot", "scope"] and d.sight_zoom() >= 1.0,
				"%s: fire mode %s, optic %s x%.1f" % [tag, d.fire_mode(), d.optic, d.sight_zoom()])
	_check(_wd("sniper").optic == "scope" and _wd("ar").optic == "red_dot" and _wd("pistol").optic == "none", "optics carried over from the old families")
	_check(_wd("pistol").fire_mode() == "semi" and _wd("ar").fire_mode() == "auto" and _wd("shotgun").handling_family() == "shotgun", "fire modes and handling families carried over")
	# The old family scalar is the pattern's climb: the first shot is what it always was.
	var ar: Resource = _wd("ar")
	_check(absf(ar.kick_of(0).y - ar.recoil * 0.45) < 0.001, "the AR's first kick is the old 0.45 deg per point of recoil (%.3f)" % ar.kick_of(0).y)
	_check(ar.kick_of(200) == ar.kick_of(200 - 8), "past the pattern's end the last eight repeat")
	# The pad: a burst gun is its own trigger and its own taps.
	var DS := load("res://autoload/DualSense.gd")
	var PR := load("res://player/PadRumble.gd")
	var burst: Resource = ar.duplicate()
	burst.auto = false
	burst.burst_count = 3
	_check(burst.fire_mode() == "burst", "a burst_count above 1 makes a burst gun")
	_check(DS.right_for(burst, false, 1.0) != DS.right_for(ar, false, 1.0) and DS.right_for(burst, false, 1.0) != DS.right_for(_wd("pistol"), false, 1.0), "DualSense: a burst gun's R2 differs from auto and semi")
	_check(PR.shot_pulse(burst, false)[1] < PR.shot_pulse(ar, false)[1] and PR.shot_pulse(burst, false)[2] < PR.shot_pulse(ar, false)[2], "rumble: a round of a burst is a lighter, shorter tap")

# --- The systems in a scene ---------------------------------------------------------------------------

func _scene_checks() -> void:
	_section("Gun systems in Dead Block: burst, reloads, sprint, recoil, tails, far shots, no allocation")
	_close_menus()
	var zm := root.get_node("ZombieMode")
	var gfx := root.get_node("Graphics")
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
	if feel == null:
		_check(false, "the weapon holder makes the feel")
		zm.leave()
		return
	holder.set_process(false)
	feel.auto = false
	holder.no_spread = true
	player.global_position = Vector3(-30, 0, -3)
	gfx.set_first_person(true)
	await _frames(6)
	holder.aim_source = func(): return [Vector3(-20, 5, -3), Vector3.RIGHT]
	player.set("_sprinting", false)

	await _burst_checks(holder, feel)
	await _reload_checks(holder, feel)
	await _sprint_checks(holder, feel, player)
	await _input_checks(holder, feel, player)
	await _recoil_checks(holder, feel)
	await _sound_checks(holder, feel, city)
	await _alloc_checks(holder, feel)
	Input.action_release("fire")
	player.set("_sprinting", false)
	GunSounds.force_indoors = -1
	zm.leave()

func _ready_gun(holder: Node, feel: Node, d: Resource) -> void:
	holder.give(d)
	feel.reset_state()
	feel.swap_blend = 0.0
	holder._swap_left = 0.0
	holder._cooldown = 0.0
	holder._sprint_hold = 0.0
	holder._burst_left = 0
	holder._fire_queued = false
	holder._reload_resume = false
	holder.aiming = false
	holder.reload_mult = 1.0

func _burst_checks(holder: Node, feel: Node) -> void:
	_section("Burst fire")
	var b: Resource = _wd("ar").duplicate()
	b.auto = false
	b.burst_count = 3
	b.burst_delay = 0.2
	_ready_gun(holder, feel, b)
	var shots := [0]
	var on_fired := func(): shots[0] += 1
	holder.fired.connect(on_fired)
	var mag0: int = holder.mag
	_check(holder.fire() and shots[0] == 1 and holder.mag == mag0 - 1, "  one pull fires the first round at once")
	for i in 6:
		_fp_step(feel, holder, 1, 0.01)
	_check(shots[0] == 1, "  and the second waits for the gun's rate (%d after 0.06 s)" % shots[0])
	for i in 8:
		_fp_step(feel, holder, 1, 0.01)
	_check(shots[0] == 2, "  the second follows at 660 rpm (%d after 0.14 s)" % shots[0])
	for i in 6:
		_fp_step(feel, holder, 1, 0.01)
	_check(shots[0] == 3 and holder.mag == mag0 - 3, "  and the third; a burst is exactly three rounds (%d, mag %d)" % [shots[0], holder.mag])
	for i in 10:
		_fp_step(feel, holder, 1, 0.01)
	_check(not holder.fire() and shots[0] == 3, "  the trigger waits out the burst delay")
	for i in 30:
		_fp_step(feel, holder, 1, 0.01)
	_check(holder.fire() and shots[0] == 4, "  then answers: the next burst begins")
	for i in 40:
		_fp_step(feel, holder, 1, 0.01)
	_check(shots[0] == 6, "  a second full burst is three more (%d)" % shots[0])
	holder.advance(2.0)
	holder.mag = 2
	var before: int = shots[0]
	holder.fire()
	for i in 40:
		_fp_step(feel, holder, 1, 0.01)
	_check(shots[0] - before == 2 and holder.mag == 0, "  a burst runs out with the magazine (%d rounds)" % [shots[0] - before])
	holder.fired.disconnect(on_fired)

func _reload_checks(holder: Node, feel: Node) -> void:
	_section("Tactical and empty reloads, with the foley at the right times")
	for id in GUN_IDS:
		var d: Resource = _wd(id)
		_ready_gun(holder, feel, d)
		holder.mag = 1
		holder.reserve = 500
		holder.reload()
		var t_tac: float = holder.reload_left()
		var cap: int = d.mag_cap(true)
		holder.advance(t_tac + 0.01)
		var took := cap - 1
		_check(is_equal_approx(t_tac, d.reload_time) and holder.mag == cap and holder.reserve == 500 - took,
			"  %s: a tactical reload takes %.2f s and leaves %d in the gun (%d)" % [id, t_tac, cap, holder.mag])
		holder.mag = 0
		holder.reserve = 500
		holder.reload()
		var t_emp: float = holder.reload_left()
		holder.advance(t_emp + 0.01)
		_check(t_tac < t_emp and is_equal_approx(t_emp, d.reload_for(true)) and holder.mag == d.mag_cap(false),
			"  %s: an empty one takes %.2f s (slower) and fills only the magazine (%d)" % [id, t_emp, holder.mag])
	# The foley of an AR reload, timed against the reload.
	for empty in [false, true]:
		_ready_gun(holder, feel, _wd("ar"))
		holder.mag = 0 if empty else 5
		holder.reserve = 90
		var seen := {}
		var counts0 := {}
		for cue in ["mag_out", "mag_in", "bolt", "rack"]:
			counts0[cue] = int(feel.sound_counts.get(cue, 0))
		holder.reload()
		var total: float = holder.reload_left()
		var t := 0.0
		var dt := 1.0 / 240.0
		while holder.reloading and t < total + 1.0:
			_fp_step(feel, holder, 1, dt)
			t += dt
			for cue in counts0:
				if not seen.has(cue) and int(feel.sound_counts.get(cue, 0)) > counts0[cue]:
					seen[cue] = t / total
		var want := {"mag_out": 0.17 if empty else 0.20, "mag_in": 0.53 if empty else 0.64}
		if empty:
			want["bolt"] = 0.75
			want["rack"] = 0.80
		var ok := true
		for cue in want:
			ok = ok and seen.has(cue) and absf(float(seen[cue]) - want[cue]) < 0.04
		ok = ok and (seen.has("rack") == empty)
		_check(ok, "  ar %s reload: foley at %s of the reload (wanted %s)" % ["empty" if empty else "tactical", _fmt(seen), _fmt(want)])

func _fmt(d: Dictionary) -> String:
	var parts := []
	for k in d:
		parts.append("%s %.2f" % [k, float(d[k])])
	return ", ".join(parts)

func _sprint_checks(holder: Node, feel: Node, player: Node) -> void:
	_section("Sprint cancels a reload; sprint-to-fire delay; a swap cancels and resumes")
	var d: Resource = _wd("ar")
	_ready_gun(holder, feel, d)
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	_fp_step(feel, holder, 36, 1.0 / 120.0)
	_check(holder.reloading, "  a reload under way")
	player.set("_sprinting", true)
	_fp_step(feel, holder, 2, 1.0 / 120.0)
	_check(not holder.reloading and holder.mag == 5 and holder.reserve == 90, "  sprinting cuts it short: nothing loaded, nothing lost (mag %d, reserve %d)" % [holder.mag, holder.reserve])
	_check(not holder.fire(), "  and the trigger waits while sprinting")
	_fp_step(feel, holder, 60, 1.0 / 120.0)
	_check(not holder.reloading and not holder.fire(), "  a reload does not carry on at a run")
	player.set("_sprinting", false)
	_fp_step(feel, holder, 6, 1.0 / 120.0)
	_check(not holder.fire() and not holder.reloading, "  just after the sprint ends the trigger still waits (delay %.2f s)" % d.sprint_fire_delay)
	_fp_step(feel, holder, int(d.sprint_fire_delay * 120.0) + 4, 1.0 / 120.0)
	_check(holder.reloading, "  when the way is clear the cut reload begins again")
	holder.advance(10.0)
	_check(not holder.reloading and holder.mag == d.mag_cap(true) and holder.reserve == 90 - (d.mag_cap(true) - 5), "  and finishes: loaded (%d + %d)" % [holder.mag, holder.reserve])
	# Sprint-to-fire delay on a gun that is not reloading: the first shot after the sprint waits the gun's own time.
	for id in ["pistol", "sniper"]:
		var g: Resource = _wd(id)
		_ready_gun(holder, feel, g)
		player.set("_sprinting", true)
		holder.advance(0.05)
		player.set("_sprinting", false)
		var waited := 0.0
		while not holder.can_fire() and waited < 1.0:
			holder.advance(0.01)
			waited += 0.01
		_check(absf(waited - g.sprint_fire_delay) <= 0.03, "  %s: the trigger answers %.2f s after the sprint (%.2f)" % [id, g.sprint_fire_delay, waited])
	# A swap cuts a reload short, and it comes back when you are back on that gun.
	holder.slots = [null, null]
	holder.give(_wd("pistol"))
	holder.give(_wd("smg"))
	holder._swap_left = 0.0
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	holder.advance(0.3)
	_check(holder.reloading and holder.swap() and not holder.reloading, "  swapping away cuts the reload short")
	holder.advance(1.0)
	_check(not holder.reloading and holder.current.id == "pistol", "  and the other gun does not reload on its behalf")
	holder.swap()
	holder.advance(holder.current.swap_time + 0.05)
	_check(holder.current.id == "smg" and holder.reloading, "  back on the SMG the reload begins again")
	holder.advance(10.0)
	_check(holder.mag == _wd("smg").mag_cap(true), "  and loads it (%d)" % holder.mag)
	holder.slots = [null, null]
	holder.give(_wd("pistol"))

func _recoil_checks(holder: Node, feel: Node) -> void:
	_section("Recoil follows the gun's pattern and comes back to centre")
	for id in ["pistol", "ar", "lmg", "shotgun"]:
		var d: Resource = _wd(id)
		_ready_gun(holder, feel, d)
		holder.refill_current()
		var sum_up := 0.0
		var sum_side := 0.0
		var n := mini(12, d.mag_size) if d.pellets == 1 else 3
		for i in n:
			holder._cooldown = 0.0
			holder.fire()
			var k: Vector2 = d.kick_of(i)
			sum_up += k.y
			sum_side += k.x
		var got_up := rad_to_deg(feel.recoil.x)
		var got_side := -rad_to_deg(feel.recoil.y)
		_check(absf(got_up - sum_up) <= sum_up * 0.12 + 0.01, "  %s: %d shots climb %.2f deg as the pattern says (%.2f)" % [id, n, got_up, sum_up])
		_check(absf(got_side - sum_side) <= sum_up * 0.25 + 0.05, "  %s: and drift %.2f deg to the side as it says (%.2f)" % [id, got_side, sum_side])
		var peak: float = feel.recoil.length()
		_fp_step(feel, holder, 120)
		_check(feel.recoil.length() < deg_to_rad(0.05) and peak > deg_to_rad(0.3), "  %s: and the view is back at centre after a second (%.3f deg from %.2f)" % [id, rad_to_deg(feel.recoil.length()), rad_to_deg(peak)])
	# Aimed down the sights the kick is the gun's own smaller share.
	var ar: Resource = _wd("ar")
	_ready_gun(holder, feel, ar)
	holder.fire()
	var hip: float = feel.recoil.x
	_fp_step(feel, holder, 120)
	feel.reset_state()
	feel.ads = 1.0
	holder._cooldown = 0.0
	holder.fire()
	var aimed: float = feel.recoil.x
	_check(aimed < hip and absf(aimed / hip - ar.recoil_ads) < 0.2, "  aimed, the first kick is %.0f%% of the hip's (%.2f of %.2f deg)" % [aimed / hip * 100.0, rad_to_deg(aimed), rad_to_deg(hip)])
	feel.reset_state()
	# ADS time per gun.
	for id in GUN_IDS:
		var d: Resource = _wd(id)
		_ready_gun(holder, feel, d)
		holder.aiming = true
		var t := 0.0
		while feel.ads < 0.999 and t < 1.0:
			_fp_step(feel, holder, 1, 1.0 / 240.0)
			t += 1.0 / 240.0
		_check(absf(t - d.ads_time) <= 0.03 and is_equal_approx(feel.ads_time(), d.ads_time), "  %s: sights up in its own %.2f s (%.3f)" % [id, d.ads_time, t])
		holder.aiming = false
		feel.reset_state()

func _sound_checks(holder: Node, feel: Node, city: Node) -> void:
	_section("The place's tail, and the far shot")
	var d: Resource = _wd("smg")
	for indoors in [1, 0]:
		GunSounds.force_indoors = indoors
		_ready_gun(holder, feel, d)
		holder.refill_current()
		holder.fire()
		_fp_step(feel, holder, 90)
		var want: AudioStream = GunSounds.tail(d, indoors == 1)
		var heard := false
		for p in feel._tail_audio:
			heard = heard or (p.stream == want and p.playing)
		_check(heard and GunSounds.tail(d, true) != GunSounds.tail(d, false), "  a shot in a %s plays that place's tail" % ("room" if indoors == 1 else "street"))
	GunSounds.force_indoors = -1
	_check(not GunSounds.indoors(feel), "  the Dead Block street is outdoors")
	# Gangsters: near shots are the close recording, far ones the one made far away.
	var GangFX := load("res://fx/GangFX.gd")
	var fx: Node3D = GangFX.new()
	city.add_child(fx)
	var cam := root.get_camera_3d()
	if cam != null:
		fx.shot_sound(cam.global_position + Vector3(6, 0, 0), "ar")
		var near: String = fx.last_sound
		fx.shot_sound(cam.global_position + Vector3(0, 0, 130), "ar")
		var far: String = fx.last_sound
		_check(near == "fire_ar" and far == "distant_ar", "  a gangster's shot is %s near and %s far" % [near, far])
	else:
		_check(false, "  there is a camera to measure from")
	fx.queue_free()

func _alloc_checks(holder: Node, feel: Node) -> void:
	_section("No allocation per shot: pooled audio voices and nodes, an LMG burst")
	var d: Resource = _wd("lmg")
	_ready_gun(holder, feel, d)
	holder.refill_current()
	for i in 80:
		holder._cooldown = 0.0
		holder.fire()
		_fp_step(feel, holder, 1, 0.02)
	var players0 := 0
	for c in feel.get_children():
		players0 += 1 if c is AudioStreamPlayer else 0
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objs0 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	var fired := 0
	for i in 300:
		if holder.mag <= 1:
			holder.refill_current()
		holder._cooldown = 0.0
		if holder.fire():
			fired += 1
		_fp_step(feel, holder, 1, 0.02)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(float(fired), 1.0)
	# (the audio server lets go of the finished playbacks as frames pass)
	await _frames(40)
	var players1 := 0
	for c in feel.get_children():
		players1 += 1 if c is AudioStreamPlayer else 0
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objs1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_check(players1 == players0 and players0 == feel._audio.size() + feel._shot_audio.size() + feel._tail_audio.size(), "  the audio voices are the same %d after 300 rounds" % players1)
	_check(nodes1 - nodes0 <= 1 and objs1 - objs0 <= 24, "  and nothing is made by firing (%+d nodes, %+d objects over %d rounds)" % [nodes1 - nodes0, objs1 - objs0, fired])
	print("  info  %.3f ms per LMG round in the test loop (shot, feel, effects)" % ms)

## The real input path: holder._process reads the fire action (held with Input.action_press), as the game does each frame.
func _input_checks(holder: Node, feel: Node, player: Node) -> void:
	_section("The trigger on the run: sprint_blocked, a buffered semi shot, fire over a resumed reload, a late cut")
	var dt := 0.01
	Input.action_release("fire")
	holder._process(dt)
	# Pulling the trigger while sprinting ends the sprint; letting go gives it back.
	var pistol: Resource = _wd("pistol")
	_ready_gun(holder, feel, pistol)
	player.set("_sprinting", true)
	Input.action_press("fire")
	holder._process(dt)
	_check(player.get("sprint_blocked") == true, "  fire on the run holds the sprint back (sprint_blocked)")
	Input.action_release("fire")
	holder._process(dt)
	_check(player.get("sprint_blocked") == false, "  and the trigger up gives it back")
	player.set("_sprinting", false)
	# I1: a semi shot pulled while still sprinting is kept and fires when the delay is over.
	for id in ["pistol", "shotgun", "sniper"]:
		var g: Resource = _wd(id)
		_ready_gun(holder, feel, g)
		holder.refill_current()
		var shots := [0]
		var on_fired := func(): shots[0] += 1
		holder.fired.connect(on_fired)
		var mag0: int = holder.mag
		player.set("_sprinting", true)
		holder._process(dt)
		Input.action_press("fire")
		holder._process(dt)
		_check(shots[0] == 0 and holder._fire_queued, "  %s: the press on the run is kept, not fired, not lost" % id)
		player.set("_sprinting", false)
		var t := 0.0
		while shots[0] == 0 and t < 1.0:
			holder._process(dt)
			t += dt
		_check(shots[0] == 1 and holder.mag == mag0 - 1 and absf(t - g.sprint_fire_delay) <= 0.04, "  %s: and fires %.2f s after the sprint ends (%.2f s, %d round)" % [id, g.sprint_fire_delay, t, shots[0]])
		for i in 60:
			holder._process(dt)
		_check(shots[0] == 1, "  %s: holding on does not fire a second one" % id)
		Input.action_release("fire")
		holder._process(dt)
		_check(not holder._fire_queued, "  %s: nothing is left queued" % id)
		holder.fired.disconnect(on_fired)
	# I3: a reload a sprint cut short gives way to the trigger when there are rounds to fire.
	var ar: Resource = _wd("ar")
	_ready_gun(holder, feel, ar)
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	holder.advance(0.3)
	player.set("_sprinting", true)
	holder.advance(dt)
	_check(not holder.reloading and holder._reload_resume, "  the sprint cuts the reload and marks it to resume")
	Input.action_press("fire")
	player.set("_sprinting", false)
	for i in int((ar.sprint_fire_delay + 0.1) / dt):
		holder._process(dt)
	_check(not holder.reloading and not holder._reload_resume and holder.mag < 5, "  fire held after the sprint: the gun shoots, it does not reload (mag %d, reloading %s)" % [holder.mag, holder.reloading])
	Input.action_release("fire")
	holder._process(dt)
	# Without the trigger the same cut reload does resume.
	_ready_gun(holder, feel, ar)
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	holder.advance(0.3)
	player.set("_sprinting", true)
	holder.advance(dt)
	player.set("_sprinting", false)
	for i in int((ar.sprint_fire_delay + 0.1) / dt):
		holder._process(dt)
	_check(holder.reloading, "  and with the trigger up it resumes")
	# A reload cut after the new magazine is in counts as done; before that it does not.
	for late in [true, false]:
		_ready_gun(holder, feel, ar)
		holder.mag = 5
		holder.reserve = 90
		holder.reload()
		holder.advance(holder.reload_left() * (0.75 if late else 0.4))
		player.set("_sprinting", true)
		holder.advance(dt)
		player.set("_sprinting", false)
		if late:
			_check(not holder.reloading and not holder._reload_resume and holder.mag == ar.mag_cap(true) and holder.reserve == 90 - (ar.mag_cap(true) - 5), "  a sprint after the mag-in cue leaves the gun loaded (%d + %d), nothing to redo" % [holder.mag, holder.reserve])
		else:
			_check(not holder.reloading and holder._reload_resume and holder.mag == 5 and holder.reserve == 90, "  a sprint before it leaves the old magazine and a reload to resume (%d + %d)" % [holder.mag, holder.reserve])
	# A swap after the mag-in cue is the same.
	holder.slots = [null, null]
	holder.give(_wd("pistol"))
	holder.give(ar)
	holder._swap_left = 0.0
	holder.mag = 5
	holder.reserve = 90
	holder.reload()
	holder.advance(holder.reload_left() * 0.75)
	holder.swap()
	holder.advance(1.0)
	holder.swap()
	holder.advance(1.0)
	_check(holder.current.id == "ar" and not holder.reloading and holder.mag == ar.mag_cap(true), "  a late swap away leaves it loaded too (%d)" % holder.mag)
	# A refill keeps the chambered round.
	holder.mag = ar.mag_cap(true)
	holder.refill_current()
	_check(holder.mag == ar.mag_cap(true), "  a refill does not take the chambered round off a full gun (%d)" % holder.mag)
	holder.slots = [null, null]
	holder.give(_wd("pistol"))
	# The Ghetto Wars drive-by plays the recorded SMG, near and far.
	var Vehicles := load("res://world/ghetto/GhettoVehicles.gd")
	var veh: Node = Vehicles.new()
	root.add_child(veh)
	var cam := root.get_camera_3d()
	if cam != null:
		var near: String = veh._drive_by_shot(cam.global_position + Vector3(6, 0, 0))
		var far: String = veh._drive_by_shot(cam.global_position + Vector3(0, 0, 130))
		_check(near.contains("/smg/fire_") and far.contains("/smg/distant_") and ResourceLoader.exists(near) and ResourceLoader.exists(far), "  the drive-by's shots are the recorded SMG: %s near, %s far" % [near.get_file(), far.get_file()])
	veh.queue_free()
	player.set("_sprinting", false)
