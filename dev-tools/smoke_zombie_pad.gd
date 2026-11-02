extends "res://dev-tools/smoke_test_3d.gd"
## The PS5 controller checks of Dead Block's first person (zombie mode, task Z4b-pad): the right stick's
## deadzone, curve and turn acceleration, the aim assist (pull toward a zombie, friction, the ADS pull;
## not through a wall, not for the mouse, not for the dead), rumble, glyphs that switch with the device and
## menus the pad can walk.
##   flatpak run org.godotengine.Godot --headless --path . -s res://dev-tools/smoke_zombie_pad.gd
func _run() -> void:
	await _zombie_pad_checks(_gs())

## Loaded when the checks start, not preloaded: these scripts name autoloads, which a script run with
## -s has not got yet when it compiles.
var PadLook: GDScript
var PadRumble: GDScript
var PadGlyph: GDScript
var GlyphLabel: GDScript
var PadFocus: GDScript

## A pad axis or button, pushed in the way the engine would.
func _axis(axis: int, value: float) -> void:
	var e = InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _button(index: int, down: bool) -> void:
	var e = InputEventJoypadButton.new()
	e.device = 0
	e.button_index = index
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func _press(index: int) -> void:
	_button(index, true)
	_button(index, false)

## Degrees between where the camera looks and a point.
func _gap(cam: Camera3D, p: Vector3) -> float:
	return rad_to_deg((-cam.global_transform.basis.z).angle_to(p - cam.global_position))

## Looks at the zombie's torso, `dyaw` degrees to the left and `dpitch` up from it.
func _aim_at(player: Node, assist: Node, z: Node3D, dyaw := 0.0, dpitch := 0.0) -> void:
	var eye: Vector3 = (player.get("camera") as Camera3D).global_position
	var a: Vector2 = assist._angles(eye, assist._points(z).torso)
	player.set_look(a.x + deg_to_rad(dyaw), a.y + deg_to_rad(dpitch))
	player._update_fp_camera()

## A spot on the street with 30 m of clear line ahead at the height of a body: [origin, forward].
func _clear_line(player: Node) -> Array:
	var space = player.get_world_3d().direct_space_state
	for x in range(-60, 61, 10):
		for zc in [-3.0, 1.0, 4.0, -8.0]:
			for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				var o := Vector3(x, 0.0, zc)
				var ok := true
				for h in [0.4, 1.0, 1.62, 2.0]:
					for side in [-0.6, 0.0, 0.6]:
						var from: Vector3 = o + Vector3(0, h, 0) + d.cross(Vector3.UP) * side
						var q := PhysicsRayQueryParameters3D.create(from, from + d * 30.0)
						q.collision_mask = 0xFFFFFFFF & ~(512 | 64)
						if not space.intersect_ray(q).is_empty():
							ok = false
				if ok:
					return [o, d]
	return [Vector3(-30, 0, -3), Vector3.RIGHT]

func _frozen(sp: Node, at: Vector3) -> Node3D:
	var z: Node3D = sp.spawn_one("walker", at)
	z.set_physics_process(false)
	z._anim_player.pause()
	z.target = null
	return z

func _zombie_pad_checks(gs: Node) -> void:
	await _section("Dead Block: built for the PS5 controller -- look, aim assist, rumble, glyphs, menus")
	_close_menus()
	PadLook = load("res://player/PadLook.gd")
	PadRumble = load("res://player/PadRumble.gd")
	PadGlyph = load("res://ui/PadGlyph.gd")
	GlyphLabel = load("res://ui/GlyphLabel.gd")
	PadFocus = load("res://ui/PadFocus.gd")
	var zm = root.get_node("ZombieMode")
	var gfx = root.get_node("Graphics")
	# Settings as a fresh install has them, whatever the player's own file says.
	gfx.pad_sens_h = 1.0
	gfx.pad_sens_v = 1.0
	gfx.pad_ads_mult = 0.75
	gfx.pad_deadzone = 0.08
	gfx.aim_assist = gfx.ASSIST_STANDARD
	gfx.rumble = true
	gfx.invert_look = false

	# --- The right stick: radial deadzone, curve, turn acceleration, sensitivities.
	_check(PadLook.deadzoned(Vector2(0.06, 0.05), 0.08) == Vector2.ZERO and PadLook.deadzoned(Vector2(0.0, -0.079), 0.08) == Vector2.ZERO,
		"  inside the inner deadzone (a radius, not a square) the stick is at rest")
	var edge = PadLook.deadzoned(Vector2(0.98, 0.0), 0.08)
	var just = PadLook.deadzoned(Vector2(0.0801, 0.0), 0.08)
	var mid = PadLook.deadzoned(Vector2(0.53, 0.0), 0.08)
	_check(absf(edge.length() - 1.0) < 0.001 and just.length() < 0.01 and absf(mid.length() - 0.5) < 0.01,
		"  past it the stick is rescaled to 0..1 with no jump at the rim, full at 0.98 (%.3f, %.4f, %.3f)" % [edge.length(), just.length(), mid.length()])
	var diag = PadLook.deadzoned(Vector2(0.7, 0.7), 0.08)
	_check(absf(diag.x - diag.y) < 0.0001 and diag.length() > 0.99, "  a full diagonal is full tilt, not 1.4")
	_check(absf(PadLook.curve(0.5) - 0.25) < 0.001 and PadLook.curve(1.0) == 1.0 and PadLook.curve(0.0) == 0.0 and PadLook.curve(0.3) < PadLook.curve(0.6),
		"  the response curve is a square: half a push is a quarter of the speed (%.3f)" % PadLook.curve(0.5))
	var look = PadLook.new()
	_check(look.step(Vector2(0.06, 0.0), 1.0 / 60.0) == Vector2.ZERO, "  a stick rested at 0.06 turns nothing")
	var full = PadLook.new().step(Vector2(1.0, 0.0), 1.0 / 60.0)
	var half = PadLook.new().step(Vector2(0.53, 0.0), 1.0 / 60.0)
	_check(absf(full.x - PadLook.RATE_YAW / 60.0) < 0.0001 and absf(half.x / full.x - 0.25) < 0.01,
		"  full tilt is %.0f deg/s and half tilt a quarter of it (%.3f)" % [rad_to_deg(PadLook.RATE_YAW), half.x / full.x])
	# Turn acceleration: after 0.15 s at full tilt the yaw ramps up to 1.6x.
	var acc = PadLook.new()
	var rates = {}
	var t = 0.0
	for i in 150:
		var r = acc.step(Vector2(1.0, 0.0), 1.0 / 120.0)
		t += 1.0 / 120.0
		for mark in [0.1, 0.2, 0.3, 0.6, 1.2]:
			if absf(t - mark) < 0.5 / 120.0:
				rates[mark] = r.x * 120.0
	_check(absf(rates[0.1] - PadLook.RATE_YAW) < 0.01 and rates[0.2] > rates[0.1] * 1.03 and rates[0.3] > rates[0.2] and absf(rates[1.2] / PadLook.RATE_YAW - 1.6) < 0.02,
		"  held at full tilt it turns 1.0x until 0.15 s, then ramps to 1.6x (0.1 s %.2f, 0.2 s %.2f, 0.3 s %.2f, 1.2 s %.2f)" % [
			rates[0.1] / PadLook.RATE_YAW, rates[0.2] / PadLook.RATE_YAW, rates[0.3] / PadLook.RATE_YAW, rates[1.2] / PadLook.RATE_YAW])
	var held = PadLook.new()
	var half_boost = 1.0
	for i in 240:
		half_boost = held.step(Vector2(0.7, 0.0), 1.0 / 120.0).x * 120.0 / (PadLook.RATE_YAW * PadLook.curve(PadLook.deadzoned(Vector2(0.7, 0.0), 0.08).length()))
	_check(absf(half_boost - 1.0) < 0.001, "  the same stick held part-way never accelerates (%.3fx after 2 s)" % half_boost)
	acc.step(Vector2.ZERO, 1.0 / 60.0)
	_check(acc.boost >= 1.0 and acc.full_time == 0.0 and absf(acc.step(Vector2(1.0, 0.0), 1.0 / 120.0).x * 120.0 - PadLook.RATE_YAW) < 0.01,
		"  letting go of the stick starts the build-up over")
	# Frame-rate independence: the same second of the same push turns the same at 30, 60 and 144 fps.
	var totals = []
	for fps in [30.0, 60.0, 144.0]:
		var l = PadLook.new()
		var sum = 0.0
		for i in int(fps):
			sum += l.step(Vector2(0.6, 0.0), 1.0 / fps).x
		totals.append(sum)
	_check(absf(totals[0] - totals[2]) / totals[2] < 0.01 and absf(totals[1] - totals[2]) / totals[2] < 0.01,
		"  a second at half-push turns the same at 30, 60 and 144 fps (%.3f, %.3f, %.3f rad)" % [totals[0], totals[1], totals[2]])
	var fulls = []
	for fps in [30.0, 144.0]:
		var l2 = PadLook.new()
		var sum2 = 0.0
		for i in int(fps):
			sum2 += l2.step(Vector2(1.0, 0.0), 1.0 / fps).x
		fulls.append(sum2)
	_check(absf(fulls[0] - fulls[1]) / fulls[1] < 0.03, "  and with the acceleration, within 3 percent (%.3f, %.3f rad)" % [fulls[0], fulls[1]])
	# Separate sensitivities, ADS scale, invert.
	gfx.pad_sens_h = 2.0
	gfx.pad_sens_v = 0.5
	var sv = PadLook.new().step(Vector2(0.53, -0.53).normalized() * 0.53, 1.0 / 60.0)
	gfx.pad_sens_h = 1.0
	gfx.pad_sens_v = 1.0
	var sv1 = PadLook.new().step(Vector2(0.53, -0.53).normalized() * 0.53, 1.0 / 60.0)
	_check(absf(sv.x / sv1.x - 2.0) < 0.001 and absf(sv.y / sv1.y - 0.5) < 0.001 and sv1.y > 0.0,
		"  horizontal and vertical speed are separate (x%.2f, y%.2f); stick up is look up" % [sv.x / sv1.x, sv.y / sv1.y])
	var ads_half = PadLook.new().step(Vector2(0.53, 0.0), 1.0 / 60.0, 0.5)
	var inv = PadLook.new().step(Vector2(0.0, 0.53), 1.0 / 60.0, 1.0, true)
	var not_inv = PadLook.new().step(Vector2(0.0, 0.53), 1.0 / 60.0, 1.0, false)
	_check(absf(ads_half.x / half.x - 0.5) < 0.001 and inv.y > 0.0 and not_inv.y < 0.0, "  the aimed scale halves the turn; invert flips up and down")

	# --- Into the game: Player3D reads the raw stick through the actions, shapes it, turns.
	zm.leave()
	zm.begin(false)
	var city = await _load("res://world/City3D.tscn")
	var block: Node = city.get_node_or_null("ZombieBlock")
	for i in 90:
		if block != null and block.purchases_ready:
			break
		await physics_frame
	await _frames(5)
	block.spawner.enabled = false
	block.spawner.round_no = 1
	for old in get_nodes_in_group("zombies"):
		old.free()
	var player = _player()
	var holder: Node = player.get_node("WeaponHolder")
	var feel: Node = holder.feel
	var assist: Node = holder.get_node_or_null("AimAssist")
	var rumble: Node = holder.get_node_or_null("PadRumble")
	_check(assist != null and rumble != null and player.get("assist") == assist, "  the weapon holder has the aim assist and the rumble, and the player knows the assist")
	holder.set_process(false)
	player.set_process(false)
	feel.set_process(false)
	feel.auto = false
	holder.no_spread = true
	gfx.set_first_person(true)
	player.global_position = Vector3(-30, 0, -3)
	await _frames(6)
	player.set_look(-PI / 2.0, 0.0)
	player._update_fp_camera()
	var yaw0: float = player.get("_look_yaw")
	_axis(JOY_AXIS_RIGHT_X, 0.05)
	player.pad_look(1.0 / 60.0)
	_check(is_equal_approx(player.get("_look_yaw"), yaw0), "  a stick at 0.05 does not move the view (deadzone)")
	_axis(JOY_AXIS_RIGHT_X, 0.53)
	var raw = PadLook.raw_stick()
	for i in 60:
		player.pad_look(1.0 / 60.0)
	var turned: float = yaw0 - float(player.get("_look_yaw"))
	_check(absf(raw.x - 0.53) < 0.01 and absf(turned - PadLook.RATE_YAW * 0.25) < 0.02,
		"  Player3D turns right by the shaped stick: a second at 0.53 is %.2f rad (%.2f expected), raw read %.2f" % [turned, PadLook.RATE_YAW * 0.25, raw.x])
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_Y, -1.0)
	var pitch0: float = player.get("_look_pitch")
	for i in 30:
		player.pad_look(1.0 / 60.0)
	_check(float(player.get("_look_pitch")) > pitch0 + 0.2, "  stick up looks up")
	_axis(JOY_AXIS_RIGHT_Y, 0.0)

	# --- Aim assist.
	var line = _clear_line(player)
	var O: Vector3 = line[0]
	var D: Vector3 = line[1]
	var R: Vector3 = D.cross(Vector3.UP)
	var YAW: float = atan2(-D.x, -D.z)
	print("  (clear line from ", O, " along ", D, ")")
	var sp: Node = block.spawner
	var pistol: Resource = load("res://weapons/pistol.tres")
	holder.give(pistol)
	await _frames(2)
	holder._swap_left = 0.0
	player.global_position = O
	await _frames(2)
	_button(JOY_BUTTON_X, true)
	_button(JOY_BUTTON_X, false)
	_check(assist.source_pad and assist.enabled(), "  a pad button makes the assist the pad's")
	var z = _frozen(sp, (O + D * 8.0))
	await _frames(3)
	player.set_look(YAW, 0.0)
	player._update_fp_camera()
	_aim_at(player, assist, z)
	var cam: Camera3D = player.get("camera")
	cam.transform = Transform3D()
	# Slowdown over the zombie.
	var out: Vector2 = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(absf(out.x / 0.01 - 0.6) < 0.05 and assist.target == z,
		"  with the crosshair on a zombie the look slows to 0.6x (%.2f)" % (out.x / 0.01))
	_aim_at(player, assist, z, 12.0, 0.0)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(is_equal_approx(out.x, 0.01) and assist.target == null, "  12 degrees off, the look is untouched")
	gfx.aim_assist = gfx.ASSIST_PRECISION
	_aim_at(player, assist, z)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(out.x / 0.01 > 0.7 and out.x / 0.01 < 0.85, "  Precision slows less (%.2fx)" % (out.x / 0.01))
	gfx.aim_assist = gfx.ASSIST_OFF
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(is_equal_approx(out.x, 0.01), "  Off leaves the look alone")
	gfx.aim_assist = gfx.ASSIST_STANDARD

	# Not for the mouse, nor a key.
	var mm = InputEventMouseMotion.new()
	mm.relative = Vector2(4, 0)
	Input.parse_input_event(mm)
	Input.flush_buffered_events()
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(not assist.source_pad and is_equal_approx(out.x, 0.01), "  after the mouse moves, the assist does nothing")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_RIGHT_X, 0.6)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	var ks = InputEventKey.new()
	ks.physical_keycode = KEY_W
	ks.pressed = true
	Input.parse_input_event(ks)
	Input.flush_buffered_events()
	_check(not assist.source_pad, "  nor after a key (the pad's stick was last touched before it)")
	_axis(JOY_AXIS_RIGHT_X, 0.6)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check(assist.source_pad, "  and back on the pad's next push")
	# Rotation: the zombie walks across the crosshair while the player moves.
	_aim_at(player, assist, z)
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, true)
	var yaw_a: float = player.get("_look_yaw")
	var z_from: Vector3 = z.global_position
	var gap0 = _gap(cam, assist._points(z).torso)
	var follow_total = 0.0
	for i in 20:
		z.global_position += R / 60.0
		var r: Vector2 = assist.adjust(Vector2.ZERO, 1.0 / 60.0, true)
		player.set_look(float(player.get("_look_yaw")) - r.x, float(player.get("_look_pitch")) + r.y)
		player._update_fp_camera()
		follow_total += r.x
	var target_moved = rad_to_deg(atan2((z.global_position - z_from).dot(R), 8.0))
	var followed = rad_to_deg(yaw_a - float(player.get("_look_yaw")))
	_check(followed > 0.0 and absf(followed / target_moved - 0.4) < 0.12,
		"  a zombie walking across the crosshair drags the view along by 0.4 of its movement (%.2f of %.2f deg)" % [followed, target_moved])
	var lag = _gap(cam, assist._points(z).torso)
	_check(lag < target_moved * 0.75, "  so the crosshair ends nearer it than a still view would (%.2f deg off instead of %.2f)" % [lag, target_moved])
	var still = false
	_aim_at(player, assist, z)
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	z.global_position += R * 0.2
	out = assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	still = out == Vector2.ZERO
	_check(still, "  with nothing touched (no move, no look) the assist leaves the view alone")
	z.global_position = (O + D * 8.0)

	# The pull as the sights come up.
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	holder.aiming = false
	_aim_at(player, assist, z, 2.5, 1.0)
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	var before = _gap(cam, assist._points(z).torso)
	holder.aiming = true
	for i in 30:
		var r2: Vector2 = assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
		player.set_look(float(player.get("_look_yaw")) - r2.x, float(player.get("_look_pitch")) + r2.y)
		player._update_fp_camera()
	var after = _gap(cam, assist._points(z).torso)
	var near_share = 1.0 - after / before
	_check(before > 2.0 and near_share > 0.4 and after < before, "  going down the sights with a zombie 8 m away and %.1f deg off pulls the view onto it (%.1f -> %.1f deg)" % [before, before, after])
	for i in 30:
		var r3: Vector2 = assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
		player.set_look(float(player.get("_look_yaw")) - r3.x, float(player.get("_look_pitch")) + r3.y)
	_check(absf(_gap(cam, assist._points(z).torso) - after) < 0.05, "  only once, as the sights come up (stays at %.2f deg)" % after)
	holder.aiming = false
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	# Weaker the further away.
	z.global_position = (O + D * 16.0)
	await _frames(1)
	_aim_at(player, assist, z, 1.2, 0.6)
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	var before_far = _gap(cam, assist._points(z).torso)
	holder.aiming = true
	for i in 30:
		var r4: Vector2 = assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
		player.set_look(float(player.get("_look_yaw")) - r4.x, float(player.get("_look_pitch")) + r4.y)
		player._update_fp_camera()
	var far_share = 1.0 - _gap(cam, assist._points(z).torso) / before_far
	_check(far_share > 0.15 and far_share < near_share - 0.05, "  and weaker at 16 m (%.2f of the gap against %.2f at 8 m)" % [far_share, near_share])
	holder.aiming = false
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	# Out of the 6 degrees: no pull.
	_aim_at(player, assist, z, 9.0, 0.0)
	var wide = _gap(cam, assist._points(z).torso)
	holder.aiming = true
	for i in 20:
		var r5: Vector2 = assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
		player.set_look(float(player.get("_look_yaw")) - r5.x, float(player.get("_look_pitch")) + r5.y)
	_check(absf(_gap(cam, assist._points(z).torso) - wide) < 0.01, "  a zombie 9 deg off is not pulled to")
	holder.aiming = false
	assist.adjust(Vector2.ZERO, 1.0 / 60.0, false)
	# Out of the gun's reach.
	z.global_position = (O + D * 24.0)
	await _frames(1)
	_aim_at(player, assist, z, 1.0, 0.0)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	var ranged_out = is_equal_approx(out.x, 0.01) and assist.target == null
	z.global_position = (O + D * 8.0)
	await _frames(1)
	_aim_at(player, assist, z)
	holder.give(load("res://weapons/shotgun.tres"))
	await _frames(1)
	var shotgun_reach: float = assist.reach()
	z.global_position = (O + D * 11.0)
	await _frames(1)
	_aim_at(player, assist, z)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	var sg_out = is_equal_approx(out.x, 0.01)
	holder.give(pistol)
	await _frames(1)
	holder._swap_left = 0.0
	_check(ranged_out and sg_out and shotgun_reach < assist.reach(), "  past the gun's reach there is no assist (24 m for the pistol, 11 m for the shotgun, reach %.0f m against %.0f m)" % [shotgun_reach, assist.reach()])
	# Through a wall: none.
	z.global_position = (O + D * 8.0)
	await _frames(1)
	_aim_at(player, assist, z)
	var wall = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.global_transform = Transform3D(Basis.looking_at(D), O + D * 4.0 + Vector3(0, 2.0, 0))
	await _frames(3)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	var walled = is_equal_approx(out.x, 0.01) and assist.target == null
	wall.free()
	await _frames(2)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(walled and assist.target == z and out.x < 0.0099, "  no assist through a wall, and it is back once the wall is gone")
	# The dead are ignored.
	z.take_hit("torso", 99999.0, Vector3.RIGHT, null, false)
	await _frames(2)
	_aim_at(player, assist, z)
	out = assist.adjust(Vector2(0.01, 0.0), 1.0 / 60.0, true)
	_check(not z.is_in_group("zombies") and is_equal_approx(out.x, 0.01) and assist.target == null, "  a dead zombie is ignored")
	# The hit zones are read after sync_hitboxes: stale until it is called.
	var z2 = _frozen(sp, (O + D * 8.0))
	await _frames(3)
	z2.sync_hitboxes()
	var stale: Vector3 = assist._centre(z2.hitboxes["torso"])
	z2._skeleton.global_position += R * 0.4
	var untouched: Vector3 = assist._centre(z2.hitboxes["torso"])
	var read: Vector3 = assist._points(z2).torso
	z2.sync_hitboxes()
	_check(untouched.is_equal_approx(stale) and not read.is_equal_approx(stale) and read.is_equal_approx(assist._centre(z2.hitboxes["torso"])),
		"  the zones sit where they were until synced, and the assist reads them after sync_hitboxes (moved %.2f m)" % read.distance_to(stale))
	z2.queue_free()

	# --- Rumble.
	var seen = []
	PadRumble.sink = func(w: float, s: float, d: float): seen.append([w, s, d])
	PadRumble.calls.clear()
	var tz = _frozen(sp, O + D * 6.0)
	tz.health = 99999.0
	await _frames(3)
	holder.aim_source = func():
		tz.sync_hitboxes()
		var eye: Vector3 = cam.global_position
		return [eye, assist._centre(tz.hitboxes["torso"]) - eye]
	var shot = {}
	for id in ["pistol", "shotgun", "lmg", "sniper"]:
		holder.give(load("res://weapons/%s.tres" % id))
		await _frames(1)
		holder.refill_all()
		holder._swap_left = 0.0
		holder._cooldown = 0.0
		holder.aiming = false
		PadRumble.calls.clear()
		holder.fire()
		rumble.flush()
		shot[id] = PadRumble.calls.duplicate()
	var p1: Array = shot["pistol"]
	var s1: Array = shot["shotgun"]
	_check(p1.size() == 1 and s1.size() == 1 and s1[0].strong >= 0.9 and p1[0].strong <= 0.4 and s1[0].duration > p1[0].duration * 2.0,
		"  a shot is one pulse shaped by the gun, the hit merged into it (pistol %s, shotgun %s)" % [p1[0] if p1.size() > 0 else "-", s1[0] if s1.size() > 0 else "-"])
	_check(p1.size() == 1 and String(p1[0].why).contains("hit") and String(p1[0].why).contains("shot"), "  a hit on the body rides on the shot (%s)" % (p1[0].why if p1.size() > 0 else "-"))
	holder.give(load("res://weapons/lmg.tres"))
	await _frames(1)
	holder.refill_all()
	holder._swap_left = 0.0
	PadRumble.calls.clear()
	for i in 6:
		holder._cooldown = 0.0
		holder.fire()
		rumble.flush()
	var steady = PadRumble.calls.size() == 6
	var lo = 9.0
	var hi = 0.0
	for c in PadRumble.calls:
		lo = minf(lo, c.strong)
		hi = maxf(hi, c.strong)
	_check(steady and hi - lo < 0.05 and hi < 0.6, "  the LMG is a steady thrum: one pulse a round, all alike (%d pulses, %.2f..%.2f)" % [PadRumble.calls.size(), lo, hi])
	holder.give(pistol)
	await _frames(1)
	holder.refill_all()
	holder._swap_left = 0.0
	holder._cooldown = 0.0
	PadRumble.calls.clear()
	tz.health = 1.0
	holder.fire()
	rumble.flush()
	var kill_why: String = String(PadRumble.calls[0].why) if PadRumble.calls.size() > 0 else ""
	_check(kill_why.contains("kill") and PadRumble.calls[0].weak >= 0.7, "  a kill gives the firmest hit pulse (%s)" % kill_why)
	PadRumble.calls.clear()
	rumble.damaged(30.0)
	rumble.flush()
	_check(PadRumble.calls.size() == 1 and PadRumble.calls[0].strong >= 0.6 and PadRumble.calls[0].duration >= 0.25, "  taking a claw is a heavy, long pulse (%s)" % [PadRumble.calls[0] if PadRumble.calls.size() > 0 else "-"])
	PadRumble.calls.clear()
	holder._melee_cd = 0.0
	holder.melee()
	rumble.flush()
	_check(PadRumble.calls.size() == 1 and String(PadRumble.calls[0].why).contains("melee"), "  the knife has its own pulse")
	PadRumble.calls.clear()
	holder.reload_mult = 1.0
	holder.mag = 1
	holder.reload()
	rumble.flush()
	var click1 = PadRumble.calls.size() == 1 and String(PadRumble.calls[0].why).contains("reload")
	holder.advance(10.0)
	rumble.flush()
	_check(click1 and PadRumble.calls.size() == 2, "  a reload clicks when it starts and when it ends")
	gfx.rumble = false
	PadRumble.calls.clear()
	holder._cooldown = 0.0
	holder.mag = 5
	holder.fire()
	rumble.damaged(50.0)
	rumble.flush()
	_check(PadRumble.calls.is_empty(), "  with Rumble off nothing goes out")
	gfx.rumble = true
	_check(seen.size() > 0, "  the pulses reached the (test) motor call")
	PadRumble.sink = Callable()
	tz.queue_free()
	holder.aim_source = Callable()

	# --- Glyphs: PlayStation buttons on the pad, keys otherwise, live.
	var Hud = load("res://ui/ZombieHud.gd")
	var hud: CanvasLayer = block.hud
	_check(hud.prompt.get_script() == GlyphLabel, "  the HUD's prompt is a glyph label")
	gs.using_pad = false
	var area = Area3D.new()
	area.set_script(load("res://interactables/Interactable3D.gd"))
	area.set_meta("prompt", "Rebuild the barricade")
	root.add_child(area)
	var fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	area.global_position = player.global_position + fwd.normalized() * 1.2
	player.nearby = [area]
	hud._update_prompt()
	var kb_text: String = hud.prompt.text
	_check(kb_text == "E  Rebuild the barricade" and hud.prompt.glyphs.size() == 0, "  on the keyboard the prompt names the key, and a barricade has one (%s)" % kb_text)
	_button(JOY_BUTTON_X, true)
	_button(JOY_BUTTON_X, false)
	_check(gs.using_pad, "  a pad button flips the game to the pad")
	hud._update_prompt()
	var pad_glyph: Control = hud.prompt.glyphs[0] if hud.prompt.glyphs.size() == 1 else null
	_check(pad_glyph != null and pad_glyph.button == "Square" and hud.prompt.plain() == "Hold Square  Rebuild the barricade" and not hud.prompt.text.contains("E ") and hud.prompt.text.strip_edges().ends_with("Rebuild the barricade"),
		"  on the pad the same prompt is Hold + a drawn Square (%s)" % [hud.prompt.plain()])
	var k2 = InputEventKey.new()
	k2.physical_keycode = KEY_E
	k2.pressed = true
	Input.parse_input_event(k2)
	Input.flush_buffered_events()
	hud._update_prompt()
	_check(not gs.using_pad and hud.prompt.text == "E  Rebuild the barricade" and hud.prompt.glyphs.is_empty(), "  a key flips it back, live")
	area.free()
	player.nearby = []
	var each = true
	for a in ["fire", "aim", "reload", "interact", "swap_weapon", "melee", "sprint", "crouch", "inspect", "pause", "cancel_ui", "accept"]:
		var gname: String = load("res://ui/Glyphs.gd").pad_glyph(a)
		var gl: Control = PadGlyph.make(gname, 26.0)
		each = each and gname != "" and gl.size.x >= 26.0
		gl.free()
	_check(each, "  every zombie control has a PlayStation glyph")
	var buy: String = Hud.prompt_markup("Buy the SMG  [1000]", true)
	_check(buy == "Hold {interact}  Buy the SMG  [1000]" and Hud.prompt_markup("", true) == "" and Hud.prompt_markup("Buy the SMG", false) == "{interact}  Buy the SMG", "  the buy prompt is a hold on the pad, a press on the keyboard")

	# --- Menus the pad can walk.
	gs.using_pad = true
	var Pause = load("res://ui/PauseMenu.gd")
	var pm: CanvasLayer = Pause.new()
	root.add_child(pm)
	pm.open()
	await _frames(3)
	var all_ok = true
	var count = 0
	for b in pm.find_children("*", "BaseButton", true, false):
		count += 1
		all_ok = all_ok and (b as Control).focus_mode == Control.FOCUS_ALL and PadFocus.dressed(b)
	var owner = root.gui_get_focus_owner()
	_check(count >= 6 and all_ok and owner is Button and (owner as Button).text == "Resume",
		"  the pause menu opens with Resume focused and every one of its %d buttons focusable with a visible frame" % count)
	_check(pm.get_node_or_null("Paused") == null and pm.find_children("PadHint", "Label", true, false).size() == 1 and (pm.find_children("PadHint", "Label", true, false)[0].glyphs.size() >= 2),
		"  and shows Cross and Circle glyphs under it")
	_press(JOY_BUTTON_DPAD_DOWN)
	_press(JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	owner = root.gui_get_focus_owner()
	var gore_before: bool = zm.gore_enabled
	_check(owner is CheckButton and (owner as CheckButton).text == "Gore", "  the D-pad walks down to the Gore toggle (%s)" % (owner.get("text") if owner != null else "none"))
	_press(JOY_BUTTON_A)
	await _frames(1)
	_check(zm.gore_enabled != gore_before, "  Cross flips it")
	zm.gore_enabled = gore_before
	_press(JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	owner = root.gui_get_focus_owner()
	var dmg_before: bool = zm.damage_numbers
	_check(owner is CheckButton and (owner as CheckButton).text == "Damage numbers", "  and on to Damage numbers")
	_press(JOY_BUTTON_A)
	await _frames(1)
	_check(zm.damage_numbers != dmg_before, "  which Cross flips too")
	zm.damage_numbers = dmg_before
	# Settings from the pause menu: the controller section, reachable and remembered.
	var Settings = load("res://ui/SettingsMenu.gd")
	var sm: CanvasLayer = Settings.new()
	root.add_child(sm)
	sm.open()
	await _frames(3)
	var names = ["PadSensH", "PadSensV", "PadAdsMult", "PadDeadzone", "Rumble", "InvertLook", "AssistOff", "AssistPrecision", "AssistStandard"]
	var found = 0
	var reach_ok = true
	for n in names:
		var c: Control = sm.find_child(n, true, false)
		if c != null:
			found += 1
			reach_ok = reach_ok and c.focus_mode == Control.FOCUS_ALL and PadFocus.dressed(c)
	_check(found == names.size() and reach_ok, "  Settings has the controller rows -- sensitivity H and V, aimed multiplier, deadzone, aim assist, rumble, invert -- all focusable with a frame (%d of %d)" % [found, names.size()])
	(sm.find_child("PadSensH", true, false) as HSlider).value = 1.8
	(sm.find_child("PadSensV", true, false) as HSlider).value = 0.7
	(sm.find_child("PadAdsMult", true, false) as HSlider).value = 0.6
	(sm.find_child("PadDeadzone", true, false) as HSlider).value = 0.12
	(sm.find_child("AssistPrecision", true, false) as Button).pressed.emit()
	(sm.find_child("AssistPrecision", true, false) as Button).button_pressed = true
	(sm.find_child("Rumble", true, false) as CheckButton).button_pressed = false
	_check(is_equal_approx(gfx.pad_sens_h, 1.8) and is_equal_approx(gfx.pad_sens_v, 0.7) and is_equal_approx(gfx.pad_ads_mult, 0.6) and is_equal_approx(gfx.pad_deadzone, 0.12)
		and gfx.aim_assist == gfx.ASSIST_PRECISION and not gfx.rumble, "  the rows change the settings the look reads")
	var cfg_ok = true
	var src = FileAccess.get_file_as_string("res://autoload/Graphics.gd")
	for key in ["pad_sens_h", "pad_sens_v", "pad_ads_mult", "pad_deadzone", "aim_assist", "rumble"]:
		cfg_ok = cfg_ok and src.contains('cfg.set_value("controls", "%s"' % key) and src.contains('cfg.get_value("controls", "%s"' % key)
	_check(cfg_ok, "  and each is written to and read back from settings.cfg")
	gfx.pad_sens_h = 1.0
	gfx.pad_sens_v = 1.0
	gfx.pad_ads_mult = 0.75
	gfx.pad_deadzone = 0.08
	gfx.aim_assist = gfx.ASSIST_STANDARD
	gfx.rumble = true
	_press(JOY_BUTTON_B)
	await _frames(2)
	_check(not is_instance_valid(sm) or sm.is_queued_for_deletion(), "  Circle backs out of Settings")
	_press(JOY_BUTTON_B)
	await _frames(2)
	_check(not paused_tree() and (not is_instance_valid(pm) or pm.is_queued_for_deletion()), "  and out of the pause menu, back into the game")
	# Game over.
	var GameOver = load("res://ui/ZombieGameOver.gd")
	var go: CanvasLayer = GameOver.new()
	root.add_child(go)
	go.show_summary({"round": 7, "kills": 40, "headshots": 11, "time": 400.0, "best_round": 9, "new_best": false})
	await _frames(3)
	owner = root.gui_get_focus_owner()
	_check(owner == go.again_button and PadFocus.dressed(go.again_button) and PadFocus.dressed(go.title_button) and go.title_button.focus_mode == Control.FOCUS_ALL,
		"  the game over screen opens on Again, both buttons focusable with a frame")
	_press(JOY_BUTTON_DPAD_DOWN)
	await _frames(1)
	_check(root.gui_get_focus_owner() == go.title_button, "  the D-pad goes down to Title")
	go._close()
	await _frames(2)
	# The Zombies menu on the title screen.
	var title = await _load("res://ui/TitleScreen.tscn")
	await _frames(3)
	var zbtn: Button = null
	for b in title.find_children("*", "Button", true, false):
		if (b as Button).text == "Zombies":
			zbtn = b
	_check(zbtn != null and zbtn.focus_mode == Control.FOCUS_ALL,
		"  the Zombies button is reachable by pad (it starts the run straight in first person)")
	gs.using_pad = false
	zm.leave()

func paused_tree() -> bool:
	return paused
