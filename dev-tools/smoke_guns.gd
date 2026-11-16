extends "res://dev-tools/smoke_test_3d.gd"
## The gun systems of SHIP 16 phase B1, on today's guns: every gun's data (sound set, handling block, recoil
## pattern, fire mode, optic), burst fire, tactical vs empty reloads and their foley, a sprint (or a swap)
## cutting a reload short and the reload resuming, the sprint-to-fire delay, the recoil pattern and its
## return to centre, the room's tail or the street's, a far shot for the gangsters, and no per-shot allocation.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_guns.gd
const GunSounds := preload("res://weapons/GunSounds.gd")
const GunModel := preload("res://weapons/GunModel.gd")
const GunViews := preload("res://player/GunViews.gd")
const GUN_IDS := ["pistol", "magnum", "smg", "ar", "shotgun", "sniper", "lmg"]
## SHIP 16 B2: the sixteen new ones (two of them melee weapons).
const NEW_IDS := ["glock", "tec9", "uzi", "mp5", "vector", "ak", "m16", "sawnoff", "deagle", "aa12", "dmr", "amr", "saw", "rpg"]
const MELEE_IDS := ["bat", "machete"]

func _run() -> void:
	_data_checks()
	_b2_data_checks()
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
	await _b2_view_checks(holder, feel, player)
	await _b2_system_checks(holder, feel, player, block)
	await _b2_venue_checks(holder, block)
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
	else:
		# (Not skipped in silence: without a camera there is no near or far to tell.)
		_check(false, "  there is a camera for the drive-by's near and far shots")
	veh.queue_free()
	player.set("_sprinting", false)

# --- SHIP 16 B2: the sixteen new guns -----------------------------------------------------------------

const PRICES := {"glock": 500, "tec9": 750, "uzi": 800, "mp5": 1100, "ak": 1500, "m16": 1300, "sawnoff": 900, "dmr": 1800, "bat": 600, "machete": 600,
	"vector": 0, "deagle": 0, "aa12": 0, "amr": 0, "saw": 0, "rpg": 0}
const IN_BOX := ["mp5", "vector", "ak", "m16", "deagle", "aa12", "dmr", "amr", "saw", "rpg"]

func _b2_data_checks() -> void:
	_section("B2 data: the sixteen new guns and their upgrades -- model, sound set, foley, handling, modes, prices")
	for id in NEW_IDS + MELEE_IDS:
		for suffix in ["", "_up"]:
			var tag: String = id + suffix
			var d: Resource = _wd(tag)
			_check(d != null and d.display_name != "", "%s loads, named %s" % [tag, d.display_name if d != null else "-"])
			if d == null:
				continue
			if suffix == "":
				_check(d.upgrade != null and d.upgrade.id == id + "_up" and d.upgrade.base_id == id and d.upgrade.upgraded, "%s: the upgrade machine makes it the %s" % [tag, d.upgrade.display_name if d.upgrade != null else "-"])
				_check(d.price == int(PRICES[id]) and d.in_box == IN_BOX.has(id), "%s: wall price %d, in the box %s (as the 16A roster says)" % [tag, d.price, d.in_box])
			var gun := GunModel.build(d)
			var box := GunModel.bounds(gun.get_child(0) as Node3D, gun)
			_check(box.size.z > d.model_length * 0.95, "%s: the model loads, %.2f m long" % [tag, box.size.z])
			gun.free()
			if d.melee:
				var cues_ok := true
				for cue in ["swing", "swing_heavy", "hit", "hit_wall", "kill"]:
					cues_ok = cues_ok and d.foley.has(cue) and GunSounds.foley(d, cue) != null
				_check(cues_ok, "%s: swing, heavy swing, flesh hit, wall hit and kill sounds" % tag)
				_check(d.melee_range > 1.5 and d.melee_arc > 30.0 and d.melee_targets >= 2 and d.heavy_mult > 1.0 and d.lunge_range > d.melee_range and d.swing_time > 0.2,
					"%s: a %.0f deg swing reaching %.1f m, %d at most, heavy x%.1f, lunge from %.1f m" % [tag, d.melee_arc, d.melee_range, d.melee_targets, d.heavy_mult, d.lunge_range])
				continue
			var gone: PackedStringArray = GunSounds.missing(d)
			_check(gone.is_empty() and d.sound_set == id, "%s: its own recorded set in sfx/guns/%s (%s missing)" % [tag, d.sound_set, gone])
			var foley_ok := true
			for cue in d.foley:
				for stem in d.foley[cue]:
					foley_ok = foley_ok and GunSounds.file(String(stem)) != null
			var cues_ok2 := true
			for list in [d.reload_cues_tactical, d.reload_cues_empty]:
				var last := 0.0
				for c in list:
					cues_ok2 = cues_ok2 and float(c[0]) > last and float(c[0]) < 1.0 and GunSounds.foley(d, String(c[1])) != null
					last = float(c[0])
			_check(foley_ok and cues_ok2 and not d.reload_cues_empty.is_empty(), "%s: every foley file is there, the reload cues ascend and sound" % tag)
			_check(d.ads_time >= 0.15 and d.ads_time <= 0.55 and d.sprint_fire_delay >= 0.15 and d.sprint_fire_delay <= 0.36 and d.reload_for(false) <= d.reload_for(true),
				"%s: ADS %.2f s, sprint-to-fire %.2f s, tactical %.2f / empty %.2f s" % [tag, d.ads_time, d.sprint_fire_delay, d.reload_for(false), d.reload_for(true)])
			var modes_ok := true
			for m in d.fire_modes:
				modes_ok = modes_ok and m in ["auto", "burst", "semi"]
			_check(modes_ok and d.recoil_pattern.size() >= 8 and d.optic in ["none", "red_dot", "scope", "built_in"],
				"%s: modes %s (comes in %s), recoil %d shots, optic %s" % [tag, d.fire_modes, d.fire_mode(), d.recoil_pattern.size(), d.optic])
	_check(_wd("m16").fire_mode() == "burst" and _wd("m16").burst_of("burst") == 3 and _wd("m16").burst_of("semi") == 1, "the M16 is a three-round burst gun with a semi setting")
	_check(_wd("mp5").fire_modes.size() == 3 and _wd("vector").burst_of("burst") == 2, "the MP5 has auto, burst and semi; the Vector's burst is two")
	_check(_wd("glock").fire_mode() == "semi" and _wd("glock_up").fire_mode() == "auto" and _wd("glock_up").mag_size == 25, "the Switch (glock_up) is full auto with 25 rounds")
	_check(_wd("amr").pierce == 2 and _wd("rpg").projectile == "rocket" and _wd("rpg").splash_radius == 4.0 and _wd("rpg").self_damage > 0.0 and _wd("rpg").mag_size == 1 and _wd("rpg").reserve_max == 8,
		"the AMR pierces two; the RPG fires a rocket, 4 m splash, hurts its shooter, 1 + 8 rockets")
	_check(_wd("sawnoff").handling_family() == "break" and _wd("rpg").handling_family() == "launcher" and _wd("saw").handling_family() == "belt", "the sawn-off breaks open, the RPG loads at the muzzle, the M249 has its belt reload")
	var G: Script = load("res://npc/Gangster3D.gd")
	var guns: Dictionary = G.get_script_constant_map()["GUNS"]
	var have := true
	for g in ["glock", "tec9", "uzi", "ak", "sawnoff", "deagle"]:
		have = have and guns.has(g) and ResourceLoader.exists("res://weapons/%s.tres" % g)
	_check(have, "Ghetto Wars: the crews carry the glock, TEC-9, Uzi, AK, sawn-off and Desert Eagle")
	_check(G.crew_gun("Dock Boys", "smg", 0.1) == "uzi" and G.crew_gun("Eastside Kings", "smg", 0.1) == "tec9" and G.crew_gun("Eastside Kings", "ar", 0.2) == "ak"
		and G.crew_gun("Police", "ar", 0.0) == "ar" and G.crew_gun("Eastside Kings", "shotgun", 0.0, true) == "deagle",
		"each crew has its own guns (Dock Boys Uzis, Kings TEC-9s and AKs, the Kings' enforcer a Desert Eagle, the police their own)")

func _b2_view_checks(holder: Node, feel: Node, player: Node) -> void:
	_section("B2 in hand: the sight on centre at ADS, the gun's own magazine moving in the reload, the break-action, the rocket")
	var cam: Camera3D = player.get("camera")
	holder.aim_source = Callable()
	for id in NEW_IDS:
		var d: Resource = _wd(id)
		_ready_gun(holder, feel, d)
		feel._raise_seen[id] = true
		feel.raising = false
		var vm: Node3D = holder.viewmodel
		_check(vm != null and vm.box.size.z > 0.15, "%s: the gun in hand is built (%.2f m)" % [id, vm.box.size.z if vm != null else 0.0])
		if vm == null or cam == null:
			continue
		holder.aiming = true
		feel.ads = 1.0
		_fp_step(feel, holder, 2)
		feel.apply()
		var local: Vector3 = cam.global_transform.affine_inverse() * (vm.global_transform * vm.sight_point)
		var off := rad_to_deg(atan2(Vector2(local.x, local.y).length(), -local.z))
		_check(local.z < -0.05 and off < 0.6, "%s: aimed, the sight sits on the view's centre (%.2f deg off, %.2f m from the eye)" % [id, off, -local.z])
		holder.aiming = false
		feel.reset_state()
		feel.raising = false
		# An empty reload: the gun's own magazine (the RPG's rocket, the M249's box) leaves with the hand and is back at the end.
		holder.mag = 0
		holder.reserve = d.mag_size * 2
		holder.reload()
		var total: float = holder.reload_left()
		var t := 0.0
		var peak := 0.0
		var turned := 0.0
		var prop := false
		while holder.reloading and t < total + 0.5:
			_fp_step(feel, holder, 1, 1.0 / 60.0)
			feel.apply()
			t += 1.0 / 60.0
			if vm.parts.has("mag"):
				peak = maxf(peak, (vm.parts["mag"]["amount"] as Vector3).length())
			if vm.parts.has("barrels"):
				var n0 := vm.parts["barrels"]["nodes"][0] as Node3D
				turned = maxf(turned, rad_to_deg((vm.parts["barrels"]["rest_xf"][0] as Transform3D).basis.get_rotation_quaternion().angle_to(n0.transform.basis.get_rotation_quaternion())))
			prop = prop or (vm.mag_prop != null and vm.mag_prop.visible)
		_fp_step(feel, holder, 2, 1.0 / 60.0)
		feel.apply()
		if vm.parts.has("mag"):
			var back: float = (vm.parts["mag"]["amount"] as Vector3).length()
			_check(peak > 0.04 and back < 0.005 and holder.mag == d.mag_size, "%s: the gun's own magazine comes out with the hand (%.2f m) and is seated at the end (%.3f m, %d rounds)" % [id, peak, back, holder.mag])
		elif vm.parts.has("barrels"):
			_check(turned > 30.0 and holder.mag == d.mag_size, "%s: it breaks open (the barrels drop %.0f deg) and takes %d shells" % [id, turned, holder.mag])
		else:
			_check(prop and holder.mag == d.mag_size, "%s: a magazine comes in the hand (the model's own is one with the gun) and the gun is loaded (%d)" % [id, holder.mag])
	# The RPG's rocket is gone from the muzzle once fired and back after the reload.
	var rpg: Resource = _wd("rpg")
	_ready_gun(holder, feel, rpg)
	var rvm: Node3D = holder.viewmodel
	holder.aim_source = func(): return [Vector3(-30, 1.6, -3), Vector3(0, 0, -1)]
	var shown0: bool = (rvm.parts["mag"]["nodes"][0] as Node3D).visible
	holder.fire()
	_fp_step(feel, holder, 2)
	feel.apply()
	var gone: bool = not (rvm.parts["mag"]["nodes"][0] as Node3D).visible
	_check(shown0 and gone, "rpg: the rocket shows in the muzzle, and is gone once it is fired")
	holder.aim_source = func(): return [Vector3(-20, 5, -3), Vector3.RIGHT]
	for r in holder._rockets:
		r.flying = false

func _b2_system_checks(holder: Node, feel: Node, player: Node, block: Node) -> void:
	_section("B2 systems: the selector, a burst finished through a sprint, a kept press, pierce, the RPG's blast, melee")
	var zm := root.get_node("ZombieMode")
	# The selector: B / D-pad left steps through the gun's modes with a click; the mode decides what a pull does.
	var mp5: Resource = _wd("mp5")
	_ready_gun(holder, feel, mp5)
	holder.refill_current()
	var seen: Array = [holder.fire_mode()]
	var clicks0 := int(feel.sound_counts.get("mode", 0))
	for i in 3:
		holder.toggle_mode()
		seen.append(holder.fire_mode())
	_check(seen == ["auto", "burst", "semi", "auto"] and int(feel.sound_counts.get("mode", 0)) >= clicks0 + 3, "  mp5: the selector goes auto, burst, semi, back to auto, with a click each (%s)" % [seen])
	_check(InputMap.has_action("fire_mode") and InputMap.action_get_events("fire_mode").size() == 2, "  the selector is bound to B and D-pad left")
	holder.toggle_mode()
	var shots := [0]
	var on_fired := func(): shots[0] += 1
	holder.fired.connect(on_fired)
	holder._cooldown = 0.0
	holder.fire()
	_fp_step(feel, holder, 60)
	_check(shots[0] == 3, "  mp5 on burst: one pull is three rounds (%d)" % shots[0])
	holder.toggle_mode()
	shots[0] = 0
	holder.advance(1.0)
	holder.fire()
	_fp_step(feel, holder, 60)
	_check(shots[0] == 1 and not holder.is_auto(), "  on semi: one (%d)" % shots[0])
	var DS := load("res://autoload/DualSense.gd")
	var PR := load("res://player/PadRumble.gd")
	_check(DS.right_for(mp5, false, 1.0, "burst") != DS.right_for(mp5, false, 1.0, "auto") and PR.shot_pulse(mp5, false, "burst")[1] < PR.shot_pulse(mp5, false, "auto")[1],
		"  the pad's trigger and rumble follow the selector (burst feels like a burst gun)")
	_ready_gun(holder, feel, _wd("rpg"))
	_check(_wd("ak").fire_modes.size() > 1 and not holder.toggle_mode(), "  a gun with one mode (the RPG) has no selector; the AK has auto and semi")
	# M5: a burst once begun is finished even if a sprint comes in the middle of it.
	var m16: Resource = _wd("m16")
	_ready_gun(holder, feel, m16)
	holder.refill_current()
	shots[0] = 0
	holder.fire()
	player.set("_sprinting", true)
	_fp_step(feel, holder, 40)
	player.set("_sprinting", false)
	_check(shots[0] == 3, "  m16: a sprint in the middle of a burst does not cut it (%d rounds)" % shots[0])
	# A press while the gun can't answer (a swap, the cooldown) is kept while the trigger is held, not lost.
	var pistol: Resource = _wd("pistol")
	_ready_gun(holder, feel, pistol)
	holder.refill_current()
	shots[0] = 0
	holder._swap_left = 0.2
	Input.action_press("fire")
	holder._process(0.01)
	_check(shots[0] == 0 and holder._fire_queued, "  a press during the raise is kept")
	for i in 30:
		holder._process(0.01)
	_check(shots[0] == 1 and not holder._fire_queued, "  and fires when the gun is up (%d)" % shots[0])
	Input.action_release("fire")
	holder._process(0.01)
	holder.fired.disconnect(on_fired)
	# Zombies to hit.
	var spawner: Node = block.spawner
	spawner.round_no = 3
	var line: Array = []
	for k in 3:
		var z = spawner.spawn_one("walker", Vector3(-24.0 - k * 1.6, 0.0, -3.0))
		z.set_physics_process(false)
		line.append(z)
	await _frames(3)
	# The AMR's round goes on through: all three in a line are hit.
	var amr: Resource = _wd("amr")
	_ready_gun(holder, feel, amr)
	holder.aim_source = func(): return [Vector3(-21.0, 1.2, -3.0), Vector3(-1, 0, 0)]
	var hp0: Array = []
	for z in line:
		hp0.append(z.health)
	holder.fire()
	var hurt := 0
	for i in line.size():
		if not is_instance_valid(line[i]) or not line[i].is_alive() or line[i].health < hp0[i]:
			hurt += 1
	_check(hurt == 3, "  amr: one round through three zombies in a line (%d hit)" % hurt)
	for z in line:
		if is_instance_valid(z):
			z.free()
	# The RPG: a rocket flies, and its blast takes a crowd; its shooter, too close, is hurt.
	var crowd: Array = []
	for at in [Vector3(-8.0, 0.0, -3.0), Vector3(-7.0, 0.0, -3.9), Vector3(-7.0, 0.0, -2.1), Vector3(-6.0, 0.0, -3.0)]:
		var z2 = spawner.spawn_one("walker", at)
		z2.set_physics_process(false)
		crowd.append(z2)
	await _frames(3)
	var rpg: Resource = _wd("rpg")
	_ready_gun(holder, feel, rpg)
	player.global_position = Vector3(-20, 0, -3)
	holder.aim_source = func(): return [Vector3(-20.0, 1.5, -3.0), Vector3(1, 0, 0)]
	var pts0: int = zm.points
	var blasts0 := 0
	for x in holder._rockets:
		blasts0 += int(x.blasts)
	holder.fire()
	var r: Node = null
	for x in holder._rockets:
		if x.flying:
			r = x
	var tt := 0
	while r != null and r.flying and tt < 300:
		holder.advance(1.0 / 60.0)
		tt += 1
	# (The blast's hits land nearest first, two a frame.)
	for i in 4:
		holder.advance(1.0 / 60.0)
	var dead := 0
	for z in crowd:
		if not is_instance_valid(z) or not z.is_alive():
			dead += 1
	var blasts1 := 0
	for x in holder._rockets:
		blasts1 += int(x.blasts)
	_check(r != null and blasts1 == blasts0 + 1 and dead == crowd.size() and zm.points > pts0, "  rpg: the rocket flies %.1f s, goes off on %s at %s and its blast kills all %d (%d dead, +%d points)" % [tt / 60.0, r.last_struck if r != null else "-", r.last_blast if r != null else Vector3.INF, crowd.size(), dead, zm.points - pts0])
	_check(holder.mag == 0 and holder.reserve == 8, "  one rocket in the tube, eight to carry: one fired (%d + %d)" % [holder.mag, holder.reserve])
	var hp_before: float = zm.health
	holder.rocket_blast(player.global_position + Vector3(1.5, 0.9, 0.0), rpg, null)
	holder.advance(0.05)
	_check(zm.health < hp_before, "  a rocket going off 1.5 m away hurts you (%.0f -> %.0f)" % [hp_before, zm.health])
	zm.health = hp_before
	for z in crowd:
		if is_instance_valid(z):
			z.free()
	holder.aim_source = Callable()
	# Melee: the bat's swing lands a moment in and takes a zombie in front; the machete's arc takes two side by side;
	# a zombie a few metres off is lunged at; a heavy hit does more.
	player.global_position = Vector3(-20, 0, -3)
	player.set_look(-PI / 2.0, 0.0)
	await _frames(2)
	for id in MELEE_IDS:
		var md: Resource = _wd(id)
		holder.give_melee(md)
		var pair: Array = []
		for k in 2:
			var z3 = spawner.spawn_one("walker", Vector3(-18.6, 0.0, -3.0 + (k - 0.5) * 0.9))
			z3.set_physics_process(false)
			z3.max_health = 5000.0
			z3.health = 5000.0
			pair.append(z3)
		await _frames(2)
		var landed := [-1, false]
		var on_land := func(hits: int, killed: bool, _wall: bool): landed[0] = hits; landed[1] = killed
		holder.swing_landed.connect(on_land)
		holder._melee_cd = 0.0
		var hp_a: float = pair[0].health
		holder.melee(false)
		holder.advance(md.swing_time * md.swing_hit * 0.5)
		var early: int = landed[0]
		holder.advance(md.swing_time)
		var dmg_light: float = hp_a - pair[0].health
		_check(early == -1 and int(landed[0]) >= 1, "  %s: the blow lands %.2f s into the swing, not at once (%d hit)" % [id, md.swing_time * md.swing_hit, landed[0]])
		if id == "machete":
			_check(int(landed[0]) == 2, "  machete: its wide arc takes both zombies side by side (%d)" % landed[0])
		holder.advance(1.0)
		holder._melee_cd = 0.0
		var hp_b: float = pair[0].health
		holder.melee(true)
		holder.advance(md.swing_time * md.heavy_time + 0.1)
		var dmg_heavy: float = hp_b - pair[0].health
		_check(dmg_light > 0.0 and dmg_heavy > dmg_light * 1.4, "  %s: a heavy hit does more (%.0f against %.0f)" % [id, dmg_heavy, dmg_light])
		holder.swing_landed.disconnect(on_land)
		for z in pair:
			if is_instance_valid(z):
				z.free()
		# A lunge at a zombie out of reach.
		var far = spawner.spawn_one("walker", Vector3(-20.0 + md.lunge_range * 0.9, 0.0, -3.0))
		far.set_physics_process(false)
		await _frames(2)
		holder.advance(1.0)
		holder._melee_cd = 0.0
		holder.melee(false)
		_check(holder.lunging and holder.lunge_velocity(0.01).length() > 5.0, "  %s: a zombie %.1f m off is lunged at" % [id, md.lunge_range * 0.9])
		holder.advance(2.0)
		if is_instance_valid(far):
			far.free()
	holder.melee_data = load(holder.KNIFE)
	_check(not holder.lunging, "  the lunge ends")

func _b2_venue_checks(holder: Node, block: Node) -> void:
	_section("B2 venues: the new wall boards, the box, the upgrade machine and the melee weapons")
	var ids: Array = []
	for b in block.wall_buys:
		ids.append(b.data.id)
	var want := ["glock", "tec9", "uzi", "mp5", "ak", "m16", "sawnoff", "dmr", "bat", "machete"]
	var all_there := true
	for w in want:
		all_there = all_there and ids.has(w)
	_check(all_there, "  Dead Block has a board for each new wall gun and the two melee weapons (%d boards)" % ids.size())
	var spaced := true
	for a in block.wall_buys:
		for b in block.wall_buys:
			if a != b and a.global_position.distance_to(b.global_position) < 2.0:
				spaced = false
		spaced = spaced and a.global_position.distance_to(block.upgrade_machine.global_position) > 2.0
	_check(spaced, "  no two boards (or a board and the machine) on top of each other")
	var pool: Array = []
	for d in block.mystery_box.pool():
		pool.append(d.id)
	var box_ok := true
	for id in IN_BOX:
		box_ok = box_ok and pool.has(id)
	_check(box_ok and not pool.has("glock") and not pool.has("bat"), "  the box holds the new box guns (%d in all)" % pool.size())
	# Buying the bat puts it in the knife's place; the machine upgrades it when the gun in hand can't be.
	var zm := root.get_node("ZombieMode")
	var bat_buy: Node = null
	for b in block.wall_buys:
		if b.data.id == "bat":
			bat_buy = b
	zm.points = 20000
	_check(bat_buy != null and bat_buy.try_buy(holder) == "bought" and holder.melee_data.id == "bat", "  the bat off the wall takes the knife's place")
	_check(bat_buy.try_buy(holder) == "full", "  and is not sold twice")
	holder.slots = [null, null]
	holder.give(_wd("pistol_up"))
	_check(block.upgrade_machine.try_upgrade(holder) == "upgraded" and holder.melee_data.id == "bat_up", "  the machine upgrades the bat (the gun in hand already is)")
	# A wall refill keeps the chambered round (WallBuy.gd).
	holder.slots = [null, null]
	holder.give(_wd("ak"))
	var ak_buy: Node = null
	for b in block.wall_buys:
		if b.data.id == "ak":
			ak_buy = b
	holder.mag = _wd("ak").mag_cap(true)
	holder.reserve = 10
	_check(ak_buy.try_buy(holder) == "ammo" and holder.mag == _wd("ak").mag_cap(true) and holder.reserve == _wd("ak").reserve_max, "  ammo off the wall keeps the round in the chamber (%d + %d)" % [holder.mag, holder.reserve])
	holder.melee_data = load(holder.KNIFE)
	holder.slots = [null, null]
	holder.give(_wd("pistol"))
	zm.points = 500
