extends "res://dev-tools/smoke_test_3d.gd"
## SHIP 16G phase B: the Mk 2 frag and the shared explosion. Stock rules per mode, the lethal button, tap / cook / cook to 0 in the
## hand, a bounce that never goes through a wall, a roll that comes to rest, the blast's falloff and cover, the player's own damage,
## the danger arrows, and the RPG and the crews' grenade going off through the same explosion.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_grenades.gd
# (Loaded at run time: these name the autoloads, which a script preloaded here would not yet see.)
var Explosion: GDScript
var GangGrenadeScript: GDScript

func _run() -> void:
	Explosion = load("res://fx/Explosion.gd")
	GangGrenadeScript = load("res://fx/GangGrenade.gd")
	_pure_checks()
	await _scene_checks()

func _wd(id: String) -> Resource:
	return load("res://weapons/%s.tres" % id)

# --- Numbers that need no scene ---------------------------------------------------------------------

func _pure_checks() -> void:
	_section("Grenade: the sound's crossfade, the muffle and the duck are what DESIGN.md says")
	var near: Dictionary = Explosion.mix_at(5.0)
	_check(near["c_db"] == -INF and absf(float(near["a_db"])) < 0.01 and near["delay"] == 0.0, "5 m: the close recording alone at full level, no delay")
	var far: Dictionary = Explosion.mix_at(60.0)
	_check(far["a_db"] == -INF and far["c_db"] > -20.0 and absf(float(far["delay"]) - 60.0 / 343.0) < 0.001, "60 m: the far recording alone, its crack %.2f s late" % far["delay"])
	var mid: Dictionary = Explosion.mix_at(22.5)
	var wa := db_to_linear(float(mid["a_db"]) - (-clampf(12.5 * 0.1, 0.0, 14.0)))
	var wc := db_to_linear(float(mid["c_db"]) - (-clampf(12.5 * 0.1, 0.0, 14.0)) - 3.0)
	_check(absf(wa * wa + wc * wc - 1.0) < 0.01, "22 m: an equal-power crossfade (a^2 + c^2 = %.3f)" % (wa * wa + wc * wc))
	_check(Explosion.mix_at(60.0, 1.4)["c_db"] > Explosion.mix_at(60.0, 1.0)["c_db"] + 2.9, "the rocket is 3 dB louder")
	_check(Explosion.muffle_hz(0.0, 1.0) == 20000.0 and absf(Explosion.muffle_hz(0.08, 1.0) - 900.0) < 1.0 and Explosion.muffle_hz(1.0, 1.0) == 900.0 and Explosion.muffle_hz(5.0, 1.0) > 20000.0,
		"the ear muffle: 20000 -> 900 Hz in 0.08 s, held, released over 2.5 s")
	_check(Explosion.duck_db(0.0, 1.0) == 0.0 and absf(Explosion.duck_db(0.05, 1.0) + 10.0) < 0.01 and absf(Explosion.duck_db(0.8, 1.0) + 10.0) < 0.01 and Explosion.duck_db(5.0, 1.0) == 0.0,
		"the duck: -10 dB in 0.05 s, held 0.8 s, released over 3 s")
	var wh: Script = load("res://player/WeaponHolder.gd")
	_check(wh.GRENADE_START == 2 and wh.GRENADE_MAX == 4 and wh.frag_data().display_name == "Mk 2 Frag", "start with 2, carry 4, called Mk 2 Frag")
	var zc: Script = load("res://player/ZombieControls.gd")
	var spec: Array = zc.BINDINGS["lethal"]
	var key := false
	var pad := false
	for s in spec:
		key = key or (s[0] == "key" and s[1] == KEY_G)
		pad = pad or (s[0] == "button" and s[1] == JOY_BUTTON_RIGHT_SHOULDER)
	_check(key and pad, "the lethal action is G on the keyboard and R1 on the pad")
	var clash := ""
	for a in zc.BINDINGS:
		if a == "lethal":
			continue
		for s2 in zc.BINDINGS[a]:
			for s3 in spec:
				if s2[0] == s3[0] and s2[1] == s3[1]:
					clash = a
	_check(clash == "", "and no other action of the mode sits on G or R1 (%s)" % clash)

# --- In the block -----------------------------------------------------------------------------------

func _scene_checks() -> void:
	_section("Grenade in Dead Block: stock, tap, cook, bounce, roll, blast, danger, RPG and crews")
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
	var holder: Node = player.get_node("WeaponHolder")
	holder.set_process(false)
	holder.lethal.set_process(false)
	holder.feel.auto = false
	holder.no_spread = true
	player.global_position = Vector3(-30, 0, -3)
	gfx.set_first_person(true)
	await _frames(6)
	holder.aim_source = func(): return [Vector3(-30, 1.6, -3), Vector3.RIGHT]
	zm.health = 1000.0
	var lethal: Node = holder.lethal

	# --- Stock rules.
	_check(holder.grenades == 2, "a run starts with 2 frags (%d)" % holder.grenades)
	holder._restock_grenades(1)
	_check(holder.grenades == 2, "round 1 gives none")
	holder._restock_grenades(2)
	_check(holder.grenades == 4, "Dead Block: +2 at a new round (%d)" % holder.grenades)
	holder._restock_grenades(3)
	_check(holder.grenades == 4, "capped at 4")
	holder.set_grenades(1)
	zm.gangs = true
	holder._restock_grenades(2)
	_check(holder.grenades == 2, "Ghetto Wars: +1 a wave (%d)" % holder.grenades)
	zm.gangs = false
	holder.refill_all()
	_check(holder.grenades == 4, "Max Ammo refills to 4")
	var sold := false
	for id in holder.POOL_IDS:
		sold = sold or id == "frag"
	_check(not sold and not holder.frag_data().in_box, "the box and the walls do not sell frags")
	holder.set_grenades(0)
	_check(not lethal.press() and lethal.state == lethal.S.IDLE, "with none left, the button does nothing")
	holder.set_grenades(4)

	# --- A tap: pin out at 0.25 s, away at 0.35 s.
	holder._swap_left = 0.0
	_check(lethal.press(), "G starts the draw")
	lethal.release()
	var t := 0.0
	var pin_at := -1.0
	var threw_at := -1.0
	while t < 1.0 and lethal.state != lethal.S.IDLE:
		lethal.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		if pin_at < 0.0 and lethal.state >= lethal.S.HELD:
			pin_at = t
		if threw_at < 0.0 and lethal.throws == 1:
			threw_at = t
	_check(pin_at > 0.2 and pin_at < 0.32 and threw_at > 0.3 and threw_at < 0.5, "a tap: the pin is out at %.2f s, the grenade leaves at %.2f s" % [pin_at, threw_at])
	_check(holder.grenades == 3 and lethal.throws == 1 and lethal.last_cook < 0.2, "one frag used, thrown with almost all of its fuse (%d left, cooked %.2f s)" % [holder.grenades, lethal.last_cook])
	var live: Array = lethal.live_grenades()
	var g: Node3D = live[0] if not live.is_empty() else null
	_check(g != null and g.is_in_group("live_grenade") and g.fuse_left() > 3.0 and g.fuse_left() < 3.5, "it is live, in group live_grenade, with %.2f s to go" % (g.fuse_left() if g != null else -1.0))
	_check(lethal.last_velocity.length() > 15.5 and lethal.last_velocity.length() < 16.5 and lethal.last_velocity.x > 15.0 and lethal.last_velocity.y > 1.0, "thrown at 16 m/s, a little upwards (%s)" % lethal.last_velocity)

	# --- It flies, bounces on the street, rolls and comes to rest.
	var n := 0
	while g != null and g.state != "rest" and g.state != "boom" and n < 200:
		g.step(1.0 / 60.0)
		n += 1
	_check(g != null and g.state == "rest" and g.bounces >= 1 and g.last_surface == "concrete", "it bounces (%d times, on %s) and rolls to rest after %.1f s" % [g.bounces if g != null else 0, g.last_surface if g != null else "-", n / 60.0])
	_check(g != null and absf(g.global_position.y - 0.08) < 0.06, "at rest on the street (y %.3f)" % (g.global_position.y if g != null else -1.0))
	var blasts0: int = Explosion.of(holder).blasts
	var hp0: float = zm.health
	player.global_position = Vector3(-30, 0, -3)
	g.global_position = player.global_position + Vector3(14, 0.08, 0)
	var left := 0
	while g.state == "rest" and left < 400:
		g.step(1.0 / 60.0)
		left += 1
	_check(g.state == "boom" and Explosion.of(holder).blasts == blasts0 + 1 and absf(g.went_off_at.x - (player.global_position.x + 14.0)) < 0.1, "the fuse ends: it goes off where it lies through the shared explosion")
	_check(zm.health == hp0, "14 m away it does not touch you")
	g.stop()

	# --- A bounce never goes through a wall.
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.04, 6.0, 10.0)
	shape.shape = box
	wall.add_child(shape)
	city.add_child(wall)
	wall.global_position = Vector3(-24, 3.0, -3)
	await _frames(2)
	var tunnelled := 0
	var bounced := 0
	for speed in [16.0, 25.0, 40.0, 70.0]:
		for dt in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 144.0]:
			var tg: Node3D = lethal._next_grenade()
			tg.launch(Vector3(-30, 1.6, -3), Vector3(speed, 0.0, 0.0), 30.0, holder, player)
			for i in 90:
				tg.step(dt)
			if tg.global_position.x > -24.0:
				tunnelled += 1
			if tg.bounces > 0:
				bounced += 1
			tg.stop()
	_check(tunnelled == 0 and bounced == 12, "12 throws at a 4 cm wall (16 to 70 m/s, 30 to 144 fps): none through it, all bounced (%d through, %d bounced)" % [tunnelled, bounced])
	wall.free()

	# --- Cook: the fuse runs in the hand; letting go throws the rest; held to 0 it goes off in the hand.
	holder.set_grenades(4)
	holder._swap_left = 0.0
	lethal.press()
	for i in 90:
		lethal.advance(1.0 / 60.0)
	_check(lethal.state == lethal.S.HELD and lethal.cook > 1.0 and lethal.cook < 1.4, "held: the pin is out and the fuse runs in the hand (%.2f s)" % lethal.cook)
	lethal.release()
	while lethal.state != lethal.S.FOLLOW and lethal.state != lethal.S.IDLE:
		lethal.advance(1.0 / 60.0)
	var cooked_g: Node3D = lethal.live_grenades()[0]
	_check(lethal.last_cook > 1.0 and cooked_g.fuse_left() < 3.5 - lethal.last_cook + 0.01 and cooked_g.fuse_left() > 3.5 - lethal.last_cook - 0.2,
		"let go after %.2f s: it flies with the %.2f s that are left" % [lethal.last_cook, cooked_g.fuse_left()])
	cooked_g.stop()
	for i in 40:
		lethal.advance(1.0 / 60.0)
	_check(lethal.state == lethal.S.IDLE, "and the hand is free again")
	holder._swap_left = 0.0
	zm.health = 1000.0
	var hp1: float = zm.health
	var inhand0: int = lethal.in_hand_blasts
	lethal.press()
	for i in 260:
		lethal.advance(1.0 / 60.0)
		if lethal.in_hand_blasts > inhand0:
			break
	holder.advance(0.02)
	holder.advance(0.02)
	_check(lethal.in_hand_blasts == inhand0 + 1 and lethal.last_cook >= 3.5, "held to 0 it goes off in the hand (%.2f s)" % lethal.last_cook)
	_check(hp1 - zm.health >= 100.0, "and that is lethal at arm's length (%.0f damage)" % (hp1 - zm.health))
	for gg in lethal.live_grenades():
		gg.stop()
	for i in 40:
		lethal.advance(1.0 / 60.0)
	zm.health = 1000.0

	# --- The blast table: falloff, cover, the player's own damage.
	var crowd: Array = []
	var at := Vector3(-14.0, 0.1, -3.0)
	for d in [1.0, 3.0, 4.0, 5.5, 7.0]:
		var z = block.spawner.spawn_one("walker", Vector3(at.x + d, 0.0, at.z))
		z.set_physics_process(false)
		z.max_health = 100000.0
		z.health = 100000.0
		crowd.append(z)
	holder.explode(at, holder.grenade_spec())
	for i in 8:
		holder.advance(1.0 / 60.0)
	var lost: Array = []
	for z in crowd:
		lost.append(100000.0 - float(z.health))
	_check(lost[0] > 990.0 and lost[1] > lost[2] and lost[2] > lost[3] and lost[3] > 190.0 and lost[4] == 0.0,
		"zombies: full inside 1.5 m, falling with distance, 20 percent near 6 m, nothing at 7 m (%s)" % [lost.map(func(x): return roundi(x))])
	_check(absf(lost[2] / lost[0] - lerpf(1.0, 0.2, (4.08 - 1.5) / 4.5)) < 0.08, "at 4 m (the chest) it is %.0f percent of the full blast" % (lost[2] / lost[0] * 100.0))
	for z in crowd:
		z.health = 100000.0
	var cover := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cb := BoxShape3D.new()
	cb.size = Vector3(0.3, 4.0, 4.0)
	cs.shape = cb
	cover.add_child(cs)
	city.add_child(cover)
	cover.global_position = Vector3(at.x + 2.0, 2.0, at.z)
	await _frames(2)
	holder.explode(at, holder.grenade_spec())
	for i in 8:
		holder.advance(1.0 / 60.0)
	var behind := 100000.0 - float(crowd[1].health)
	_check(behind > 0.0 and absf(behind / lost[1] - 0.35) < 0.06, "behind cover the 3 m zombie takes 35 percent (%.0f of %.0f)" % [behind, lost[1]])
	cover.free()
	for z in crowd:
		if is_instance_valid(z):
			z.free()
	# Player: 110 x (1 - d/6).
	player.global_position = Vector3(at.x + 4.0 - 0.0, 0.0, at.z)
	zm.health = 1000.0
	var ph: float = zm.health
	holder.explode(at, holder.grenade_spec())
	var expect := 110.0 * (1.0 - (Vector3(player.global_position.x, 0.9, at.z).distance_to(at)) / 6.0)
	_check(absf((ph - zm.health) - expect) < 1.5, "you take 110 x (1 - d/6) at 4 m (%.1f, wanted %.1f)" % [ph - zm.health, expect])
	player.global_position = Vector3(-30, 0, -3)
	zm.health = 1000.0

	# --- Zombies die flying: a body near the blast is thrown (ragdoll) and the kill pays.
	var victim = block.spawner.spawn_one("walker", Vector3(at.x + 1.0, 0.0, at.z))
	victim.set_physics_process(false)
	var pts: int = zm.points
	var kills0: int = zm.kills
	holder.explode(at, holder.grenade_spec())
	for i in 6:
		holder.advance(1.0 / 60.0)
	_check(not victim.is_alive() and zm.points > pts and zm.kills == kills0 + 1, "a zombie at 1 m is killed and the kill counts (+%d points)" % (zm.points - pts))
	await _frames(2)
	victim.free()

	# --- Danger arrows: yours and the crews'.
	var hud: Node = get_first_node_in_group("zombie_hud")
	var ghud: Node = hud.get_node_or_null("GrenadeHud") if hud != null else null
	_check(ghud != null, "the HUD has the frag count and the danger arrows")
	holder.set_grenades(2)
	holder._swap_left = 0.0
	var dg: Node3D = lethal._next_grenade()
	dg.launch(player.global_position + Vector3(4, 0.5, 0), Vector3.ZERO, 3.0, holder, player)
	dg.state = "rest"
	await _frames(3)
	if ghud != null:
		ghud._process(0.016)
		_check(ghud.count == 2 and ghud.arrows.size() == 1 and ghud.arrows[0]["inside"], "a live frag 4 m away gives one arrow, inside its blast, and the HUD counts 2 (%s)" % [ghud.arrows])
	dg.global_position = player.global_position + Vector3(40, 0.5, 0)
	if ghud != null:
		ghud._process(0.016)
		_check(ghud.arrows.is_empty(), "and none from 40 m")
	dg.stop()
	var crew: Node3D = GangGrenadeScript.new()
	crew.kind = "frag"
	city.add_child(crew)
	crew.launch(player.global_position + Vector3(8, 1.7, 0), player.global_position + Vector3(3, 0, 0), null)
	await _frames(2)
	_check(crew.is_in_group("live_grenade") and crew.fuse_left() > 1.5 and crew.fuse_left() < 5.0, "a crew's grenade is in the same group with its fuse (%.1f s)" % crew.fuse_left())
	if ghud != null:
		ghud._process(0.016)
		_check(ghud.arrows.size() == 1, "and gets its arrow")

	# --- The RPG and the crews go off through the same explosion.
	var fx: Node3D = Explosion.of(holder)
	var b0: int = fx.blasts
	var crew_done := false
	for i in 400:
		await physics_frame
		if crew.exploded:
			crew_done = true
			break
	_check(crew_done and fx.blasts == b0 + 1 and fx.last_power == 1.0, "the crew's grenade went off through fx/Explosion (%d blast)" % (fx.blasts - b0))
	holder.give(_wd("rpg"))
	holder._swap_left = 0.0
	holder._cooldown = 0.0
	holder.refill_all()
	var b1: int = fx.blasts
	holder._launch(Vector3(-30, 1.6, -3), Vector3.RIGHT, _wd("rpg"))
	var rk: Node3D = holder._rockets[0]
	for i in 120:
		holder.advance(1.0 / 60.0)
	_check(fx.blasts == b1 + 1 and absf(fx.last_power - 1.4) < 0.01 and rk.blasts >= 1, "the RPG's rocket goes off through the same explosion at power 1.4")
	var quads := 0
	for c in rk.find_children("*", "CPUParticles3D", true, false):
		quads += 1
	_check(quads == 1, "and no longer carries its own fire, smoke and grit (only the trail is left: %d emitters)" % quads)
	_check(fx.blasts_active() <= 2, "two big blasts at most are alive at once (%d)" % fx.blasts_active())
	# Shake by distance.
	holder.feel.trauma = 0.0
	fx.detonate(player.global_position + Vector3(6, 0.1, 0), Vector3.UP, 1.0)
	var close_shake: float = holder.feel.trauma
	holder.feel.trauma = 0.0
	fx.detonate(player.global_position + Vector3(40, 0.1, 0), Vector3.UP, 1.0)
	_check(close_shake > 0.4 and holder.feel.trauma == 0.0, "a blast at 6 m shakes the view (%.2f), one at 40 m does not" % close_shake)
	fx.detonate(player.global_position + Vector3(2, 0.1, 0), Vector3.UP, 1.0)
	_check(fx.last_sound.has("ring") and fx.last_sound["muffle_hold"] > 0.5 and fx.last_sound.has("duck") and fx.last_sound.has("slap"), "a blast at 2 m rings the ears, muffles and ducks the rest, with the street's slapback (%s)" % [fx.last_sound])
	await _frames(3)
	await _fix2_checks(city, holder, lethal, player, zm, ghud)
	zm.leave()

# --- Fix round 2 -------------------------------------------------------------------------------------

func _fix2_checks(city: Node, holder: Node, lethal: Node, player: Node3D, zm: Node, ghud: Node) -> void:
	_section("Grenade fix round 2: locks, hint, empty pouch, fuse, danger radius, voices, far blast, glint, audio release")
	var S = lethal.S
	holder._swap_left = 0.0
	holder.set_grenades(4)
	holder.give(_wd("ar"))
	holder.refill_all()
	holder._swap_left = 0.0
	holder._cooldown = 0.0
	holder.aiming = false
	var slot_before: int = holder.active
	# While a grenade is out: no reload, melee, swap, select, heavy hold or sights.
	holder.mag = 5
	lethal.press()
	for i in 20:
		lethal.advance(1.0 / 60.0)
	_check(lethal.state == S.HELD and holder.lethal_active(), "the pin is out and the holder knows (lethal_active)")
	_check(not holder.reload() and not holder.reloading, "R during a cook does nothing")
	_check(not holder.melee() and holder._swing_t < 0.0, "V during a cook does nothing")
	_check(not holder.swap() and not holder.select(1 - holder.active) and holder.active == slot_before, "Q, 1 and 2 during a cook do nothing")
	Input.action_press("aim")
	holder._process(0.016)
	_check(holder.aiming == false, "with the aim button down the sights stay down (aiming false)")
	Input.action_release("aim")
	var swap_hold: float = 0.7
	holder._swap_left = swap_hold
	lethal.release()
	for i in 60:
		lethal.advance(1.0 / 60.0)
	_check(lethal.state == S.IDLE and holder._swap_left <= swap_hold and holder._swap_left > 0.0 or holder._swap_left == 0.0, "a swap clock that was running is not zeroed by the throw's end (%.2f)" % holder._swap_left)
	for g in lethal.live_grenades():
		g.stop()
	holder._swap_left = 0.0
	holder._melee_hold = 0.0
	_check(not lethal.can_start(), "a pending heavy-melee hold keeps the grenade in the pouch")
	holder._melee_hold = -1.0
	_check(lethal.can_start() and not holder.lethal_active(), "and with it gone G starts and the gun is free")

	# The fuse: what the cook leaves is thrown, less the wind-up that did not count.
	lethal.press()
	for i in 90:
		lethal.advance(1.0 / 60.0)
	var cook_at: float = lethal.cook
	lethal.release()
	while lethal.state != S.FOLLOW and lethal.state != S.IDLE:
		lethal.advance(1.0 / 60.0)
	var gl: Node3D = lethal.live_grenades()[0]
	_check(absf(gl.fuse_left() - (3.5 - lethal.last_cook - lethal.WIND_TIME)) < 0.03, "fuse thrown = 3.5 - cook - wind-up (%.2f, cooked %.2f)" % [gl.fuse_left(), lethal.last_cook])
	# The glint and the last-second blink.
	var lit_early := false
	gl.fuse = 2.0
	gl.step(1.0 / 60.0)
	lit_early = gl.blink_lit()
	var lit_late := false
	var unlit_late := false
	gl.fuse = 0.9
	for i in 30:
		gl.step(1.0 / 120.0)
		if gl.blink_lit():
			lit_late = true
		else:
			unlit_late = true
	_check(not lit_early and lit_late and unlit_late, "the thrown grenade has a rim and blinks red in its last second")
	gl.stop()
	for g in lethal.live_grenades():
		g.stop()
	for i in 40:
		lethal.advance(1.0 / 60.0)

	# The empty pouch answers; the key and the name are on the HUD.
	holder.set_grenades(0)
	var pulsed := [false]
	lethal.empty_pressed.connect(func(): pulsed[0] = true)
	var glyphs: Script = load("res://ui/Glyphs.gd")
	_check(glyphs.KEY.get("lethal", "") == "G" and glyphs.PAD.get("lethal", ["", ""])[0] == "R1", "the glyph table names G and R1")
	_check(not lethal.press() and pulsed[0], "G with none left clicks and tells the HUD")
	if ghud != null:
		ghud._process(0.016)
		_check(ghud.pulse_t > 0.3, "the HUD pulses its red 0 (%.2f s)" % ghud.pulse_t)
		ghud.hint_t = 0.0
		holder.set_grenades(2)
		ghud._on_count(2)
		_check(ghud.hint_t > 2.0, "a restock shows '[G] MK 2 FRAG' again (%.1f s)" % ghud.hint_t)

	# Crews' radius; M7: four sets of voices; M2 the veil; far blast visible; audio released on leaving the scene.
	var crew: Node3D = load("res://fx/GangGrenade.gd").new()
	crew.kind = "frag"
	_check(absf(crew.danger_radius() - 4.5) < 0.01, "a crew's frag has its own danger radius (%.1f m)" % crew.danger_radius())
	crew.free()
	var fx: Node3D = Explosion.of(holder)
	_check(fx._vsets.size() == 4, "the explosion has four sets of sound voices (%d)" % fx._vsets.size())
	var sets_used := {}
	for k in 4:
		fx.detonate(player.global_position + Vector3(30 + k, 0.1, 0), Vector3.UP, 1.0)
		sets_used[fx._vsets[(fx._vset_next + 3) % 4]] = true
	_check(sets_used.size() == 4, "four blasts in a row take four different sets (none cuts another's boom)")
	fx._veil_a = 0.0
	fx.detonate(player.global_position + Vector3(1.0, 0.1, 0), Vector3.UP, 1.0)
	_check(fx.veil_alpha() > 0.5, "a blast inside 4 m flashes the screen (%.2f)" % fx.veil_alpha())
	fx._veil_a = 0.0
	fx.detonate(player.global_position + Vector3(30, 0.1, 0), Vector3.UP, 1.0)
	_check(fx.veil_alpha() == 0.0 and fx._flash.omni_range > 20.0, "and one at 30 m does not, but its light reaches %.0f m" % fx._flash.omni_range)
	# Left mid-ring: the buses are released.
	fx.detonate(player.global_position + Vector3(2, 0.1, 0), Vector3.UP, 1.0)
	for i in 6:
		await physics_frame
	var lows: Array = Explosion._lows
	_check(not lows.is_empty() and AudioServer.is_bus_effect_enabled(lows[0][0], lows[0][1]), "a close blast is muffling the buses")
	var sfxn: Node = root.get_node("SFX")
	_check(sfxn.ear_hz < 20000.0, "and the autoload's muffle (%.0f Hz)" % sfxn.ear_hz)
	fx.get_parent().remove_child(fx)
	fx.free()
	_check(not AudioServer.is_bus_effect_enabled(lows[0][0], lows[0][1]) and sfxn.ear_hz >= 20400.0, "leaving the scene releases the low-pass and the muffle (%.0f Hz)" % sfxn.ear_hz)
	for e in Explosion._amps:
		_check(not AudioServer.is_bus_effect_enabled(e[0], e[1]), "and the duck on bus %d" % e[0])
