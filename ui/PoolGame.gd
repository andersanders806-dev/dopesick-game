extends CanvasLayer
## Eight-ball for money at the Dive Bar, seen from above the table.
##
## Proper bar rules: you break; the table stays open until someone pockets a
## ball on a legal shot, which gives them that group (solids 1-7 or stripes
## 9-15). Pocket one of yours and you keep shooting. Fouls -- scratching,
## hitting nothing, or hitting the wrong group first -- give the other side
## ball in hand. Clear your group and sink the 8 to win the pot; sink the 8
## early, or scratch on it, and you lose. The 8 going down on the break is
## spotted again.
##
## Aim with the mouse (arrow keys fine-tune, Shift slower), hold the left
## button or Space and let go to shoot -- the power meter swings up and back,
## so let go at the top. W/S put follow or draw on the cue ball, A/D side
## spin (it bites off the cushions), R centres it. Esc concedes the pot.
##
## Physics: 8 to 20 substeps a frame; balls roll with friction and drag,
## collide elastically, and bounce off cushions that stop at angled pocket
## jaws, so a ball rattles in the jaws the way it does on a real table.
## Follow and draw take effect after the cue ball's first contact and fade
## with how far it slid to get there. Balls are drawn by a sphere shader and
## really roll -- each carries its own orientation, so stripes turn over and
## numbers come and go.
##
## The regular plays the same physics: for each legal ball and pocket it
## finds the ghost-ball spot, keeps shots with a clear line both ways, a
## pocket it can actually get into and a sane cut, takes the cheapest, and
## misses by an amount set by its skill. With nothing on it plays safe. With
## ball in hand it tries spots until it likes the shot. You watch it line up.
##
## Written for this game after looking at the open-source Godot pool games
## on GitHub (danielKlmr/BreakoutShot, MIT, for its rules flow) -- none of
## their code or assets are used. Sounds are synthesized by
## dev-tools/gen_pool_sfx.py.

signal finished(won: bool)

static var _shown_howto := false
var _howto := false

## The cloth inside the cushion noses. A 9-foot table's 2:1 at about 3.5 px
## per centimetre, with the balls drawn a touch big so the numbers read.
const PLAY := Rect2(200, 170, 880, 440)
const CUSHION_W := 16.0
const RAIL_W := 40.0
const BALL_R := 11.0
## Pocket mouths: how far each cushion nose stops short of the corner, and
## half the side-pocket opening.
const CORNER_MOUTH := 27.0
const SIDE_MOUTH := 22.0
const POCKET_CAPTURE := 19.0
const FRICTION := 60.0  # px/s^2, rolling resistance
const DRAG := 0.32  # 1/s, speed-proportional loss
const BALL_RESTITUTION := 0.95
const CUSHION_RESTITUTION := 0.76
const MAX_POWER := 1500.0
const CHARGE_TIME := 1.15
const STOP_SPEED := 5.0
const CUE_LENGTH := 380.0

const WHITE := Color(0.94, 0.93, 0.87)
const BALL_COLORS := {
	1: Color(0.96, 0.76, 0.08), 2: Color(0.10, 0.25, 0.78), 3: Color(0.82, 0.10, 0.10),
	4: Color(0.38, 0.12, 0.55), 5: Color(0.95, 0.45, 0.06), 6: Color(0.05, 0.50, 0.24),
	7: Color(0.45, 0.10, 0.08), 8: Color(0.06, 0.06, 0.07),
}

const SOLIDS := 0
const STRIPES := 1

var opponent_name: String = "Regular"
## 0..1: how precise the opponent is.
var skill: float = 0.5
var bet: int = 5

var _balls: Array = []  # of Dictionary, index 0 is the cue ball
var _pockets: Array[Vector2] = []
## Each pocket's opening direction (into the table), to tell which angles a
## ball can actually drop from.
var _pocket_dirs: Array[Vector2] = []
var _segments: Array = []  # [a: Vector2, b: Vector2] cushion noses and jaws

var _aim: float = PI
var _charging: bool = false
var _charge_t: float = 0.0
var _charge: float = 0.0
var _follow: float = 0.0  # -1 draw .. +1 follow
var _side: float = 0.0  # -1 left .. +1 right

## 0 = you, 1 = the regular.
var _shooter: int = 0
var _groups := [-1, -1]
var _break_shot: bool = true
var _ball_in_hand: bool = false
var _moving: bool = false
var _over: bool = false
var _message: String = ""

# Per shot.
var _first_hit: int = -1
var _pocketed: Array = []
var _scratched: bool = false
var _cleared_at_start: bool = false
var _cue_slid: float = 0.0
var _cue_touched: bool = false

# The regular's turn, played out so you can watch it.
var _ai_phase: String = ""
var _ai_timer: float = 0.0
var _ai_target_aim: float = 0.0
var _ai_power: float = 0.0
var _ai_follow: float = 0.0

var _root: Control
var _overlay: Control
var _hud: CanvasLayer
var _ball_shader: Shader
var _sounds := {}
var _voices: Array = []

func start(opponent: String, opponent_skill: float, stake: int) -> void:
	opponent_name = opponent
	skill = opponent_skill
	bet = stake
	layer = 95
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false
	# A game takes minutes of real time; the day, the craving and closing
	# time wait for it, the way the world waits under a cutscene.
	GameState.set_process(false)
	_build_geometry()
	_build_scene()
	_load_sounds()
	_rack()
	_message = "%s racks them tight. $%d on the rail. Your break." % [opponent_name, bet]
	_howto = not _shown_howto
	_shown_howto = true

# --- Setup ----------------------------------------------------------------

func _build_geometry() -> void:
	var x0 := PLAY.position.x
	var y0 := PLAY.position.y
	var x1 := PLAY.end.x
	var y1 := PLAY.end.y
	var xm := PLAY.get_center().x
	var o := 10.0
	_pockets = [Vector2(x0 - o, y0 - o), Vector2(xm, y0 - 17), Vector2(x1 + o, y0 - o),
		Vector2(x0 - o, y1 + o), Vector2(xm, y1 + 17), Vector2(x1 + o, y1 + o)]
	_pocket_dirs = [Vector2(1, 1).normalized(), Vector2.DOWN, Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(), Vector2.UP, Vector2(-1, -1).normalized()]
	var jaw := CUSHION_W
	_segments.clear()
	# Long rails, each in two halves around the side pocket. Every nose
	# ends in a jaw angled back into its pocket.
	for top in [true, false]:
		var y: float = y0 if top else y1
		var s := -1.0 if top else 1.0
		var a := Vector2(x0 + CORNER_MOUTH, y)
		var b := Vector2(xm - SIDE_MOUTH, y)
		var c := Vector2(xm + SIDE_MOUTH, y)
		var d := Vector2(x1 - CORNER_MOUTH, y)
		_segments.append([a, b])
		_segments.append([c, d])
		_segments.append([a, a + Vector2(-jaw * 0.9, s * jaw)])
		_segments.append([d, d + Vector2(jaw * 0.9, s * jaw)])
		_segments.append([b, b + Vector2(jaw * 0.25, s * jaw)])
		_segments.append([c, c + Vector2(-jaw * 0.25, s * jaw)])
	for left in [true, false]:
		var x: float = x0 if left else x1
		var s := -1.0 if left else 1.0
		var a := Vector2(x, y0 + CORNER_MOUTH)
		var b := Vector2(x, y1 - CORNER_MOUTH)
		_segments.append([a, b])
		_segments.append([a, a + Vector2(s * jaw, -jaw * 0.9)])
		_segments.append([b, b + Vector2(s * jaw, jaw * 0.9)])

func _build_scene() -> void:
	_root = Control.new()
	_fill(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	var room := ColorRect.new()
	_fill(room)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.material = _material(ROOM_SHADER, {"table_centre": PLAY.get_center() / Vector2(1280, 720)})
	_root.add_child(room)

	var outer := PLAY.grow(CUSHION_W + RAIL_W)
	var wood := ColorRect.new()
	wood.position = outer.position
	wood.size = outer.size
	wood.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wood.material = _material(WOOD_SHADER, {"size": outer.size, "rail": RAIL_W})
	_root.add_child(wood)

	var cloth := PLAY.grow(CUSHION_W)
	var felt := ColorRect.new()
	felt.position = cloth.position
	felt.size = cloth.size
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	felt.material = _material(FELT_SHADER, {"size": cloth.size})
	_root.add_child(felt)

	# Cushions, pockets, diamonds and ball shadows sit under the balls;
	# the cue, guides and scoreboard over them.
	var under := Control.new()
	_fill(under)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.draw.connect(_draw_under.bind(under))
	_root.add_child(under)

	_ball_shader = Shader.new()
	_ball_shader.code = BALL_SHADER
	for n in 16:
		var rect := ColorRect.new()
		rect.size = Vector2.ONE * BALL_R * 2.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = _ball_shader
		var kind := 0 if n == 0 else (2 if n > 8 else 1)
		mat.set_shader_parameter("kind", kind)
		mat.set_shader_parameter("base_color", WHITE if n == 0 else BALL_COLORS[n if n <= 8 else n - 8])
		rect.material = mat
		_root.add_child(rect)
		var basis := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		# The cue ball starts with its red dots showing.
		if n == 0:
			basis = Basis(Vector3.RIGHT, 0.5)
		_balls.append({"n": n, "pos": Vector2.ZERO, "vel": Vector2.ZERO, "basis": basis,
			"sunk": false, "sink_t": 0.0, "sink_to": Vector2.ZERO, "rect": rect, "mat": mat,
			"pending": Vector2.ZERO, "side": 0.0})

	_overlay = Control.new()
	_fill(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_over)
	_root.add_child(_overlay)

func _material(code: String, params: Dictionary) -> ShaderMaterial:
	var s := Shader.new()
	s.code = code
	var m := ShaderMaterial.new()
	m.shader = s
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

func _fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

func _load_sounds() -> void:
	for id in ["clack", "cushion", "cue", "pocket"]:
		var path := "res://assets/sfx/pool_%s.wav" % id
		if ResourceLoader.exists(path):
			_sounds[id] = load(path)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(p)
		_voices.append(p)

func _sound(id: String, strength: float) -> void:
	if not _sounds.has(id) or strength <= 0.02:
		return
	for p in _voices:
		if not p.playing:
			p.stream = _sounds[id]
			p.volume_db = linear_to_db(clampf(strength, 0.05, 1.0)) - 3.0
			p.pitch_scale = randf_range(0.94, 1.06)
			p.play()
			return

## Standard eight-ball rack: the 8 in the middle of the third row, a solid
## and a stripe in the back corners, the rest shuffled.
func _rack() -> void:
	var foot := Vector2(PLAY.position.x + PLAY.size.x * 0.75, PLAY.get_center().y)
	var order := [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]
	order.shuffle()
	var solid_corner: int = order.filter(func(n): return n < 8)[0]
	var stripe_corner: int = order.filter(func(n): return n > 8)[0]
	order.erase(solid_corner)
	order.erase(stripe_corner)
	var slots := []
	for row in 5:
		for k in row + 1:
			slots.append(Vector2(row, k))
	var dx := BALL_R * sqrt(3.0) + 0.15
	for slot in slots:
		var row: int = int(slot.x)
		var k: int = int(slot.y)
		var n: int
		if row == 2 and k == 1:
			n = 8
		elif row == 4 and k == 0:
			n = solid_corner if randf() < 0.5 else stripe_corner
		elif row == 4 and k == 4:
			n = stripe_corner if solid_corner in _balls_placed() else solid_corner
		else:
			n = order.pop_front()
		var b: Dictionary = _balls[n]
		b["pos"] = foot + Vector2(row * dx, (k - row / 2.0) * (BALL_R * 2.0 + 0.2)) + Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
		b["placed"] = true
	var cue: Dictionary = _balls[0]
	cue["pos"] = Vector2(PLAY.position.x + PLAY.size.x * 0.25, PLAY.get_center().y + randf_range(-40, 40))
	_aim = (foot - cue["pos"]).angle()
	for b in _balls:
		b.erase("placed")

func _balls_placed() -> Array:
	return _balls.filter(func(b): return b.get("placed", false)).map(func(b): return b["n"])

# --- Frame loop -------------------------------------------------------------

func _process(delta: float) -> void:
	if _moving:
		var fastest := 0.0
		for b in _balls:
			if not b["sunk"]:
				fastest = maxf(fastest, (b["vel"] as Vector2).length())
		var steps := clampi(ceili(fastest * delta / (BALL_R * 0.4)), 8, 40)
		for i in steps:
			_step(delta / steps)
		if _balls.all(func(b): return b["sunk"] or ((b["vel"] as Vector2).length() < STOP_SPEED and (b["pending"] as Vector2).is_zero_approx())):
			for b in _balls:
				b["vel"] = Vector2.ZERO
			_end_shot()
	elif not _over and not _howto:
		if _shooter == 0 and not _ball_in_hand:
			_player_controls(delta)
		elif _shooter == 1:
			_ai_update(delta)
	_animate_sinking(delta)
	_sync_balls()
	_overlay.queue_redraw()
	_root.get_child(3).queue_redraw()  # the layer under the balls

func _player_controls(delta: float) -> void:
	if _charging:
		_charge_t += delta
		_charge = pingpong(_charge_t / CHARGE_TIME, 1.0)
	var fine := 0.25 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		_aim -= 0.9 * fine * delta
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_aim += 0.9 * fine * delta
	var spin_rate := 1.6 * delta
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		_follow = minf(1.0, _follow + spin_rate)
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		_follow = maxf(-1.0, _follow - spin_rate)
	if Input.is_physical_key_pressed(KEY_D):
		_side = minf(1.0, _side + spin_rate)
	if Input.is_physical_key_pressed(KEY_A):
		_side = maxf(-1.0, _side - spin_rate)
	# Keep the spin dot inside the ball.
	var v := Vector2(_side, -_follow)
	if v.length() > 1.0:
		v = v.normalized()
		_side = v.x
		_follow = -v.y

func _unhandled_input(event: InputEvent) -> void:
	if _howto and (event is InputEventKey or event is InputEventMouseButton) and event.pressed and not event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		_howto = false
		return
	if event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		if _over:
			_close()
			return
		_message = "You lay the cue on the table. %s takes the $%d." % [opponent_name, bet]
		_finish(false)
		return
	if _over and (event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_SPACE)):
		get_viewport().set_input_as_handled()
		_close()
		return
	if not (event is InputEventKey):
		return
	if event.physical_keycode == KEY_R and event.pressed:
		_follow = 0.0
		_side = 0.0
	if _shooter == 0 and not _moving and not _over and not _ball_in_hand and event.physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if event.pressed and not event.echo:
			_begin_charge()
		elif not event.pressed and _charging:
			_shoot(_aim, _charge, _follow, _side)

func _on_gui_input(event: InputEvent) -> void:
	if _howto:
		if event is InputEventMouseButton and event.pressed:
			_howto = false
		return
	if _over:
		if event is InputEventMouseButton and event.pressed:
			_close()
		return
	if _shooter != 0 or _moving:
		return
	if _ball_in_hand:
		if event is InputEventMouseMotion:
			_move_cue_in_hand(event.position)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _cue_spot_free(_balls[0]["pos"]):
				_ball_in_hand = false
				_balls[0]["sunk"] = false
				_message = "Cue ball's down. Your shot."
		return
	if event is InputEventMouseMotion and not _charging:
		_aim = (event.position - (_balls[0]["pos"] as Vector2)).angle()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_charge()
		elif _charging:
			_shoot(_aim, _charge, _follow, _side)

func _begin_charge() -> void:
	_charging = true
	_charge_t = 0.0
	_charge = 0.0

func _move_cue_in_hand(at: Vector2) -> void:
	var inner := PLAY.grow(-BALL_R - 1.0)
	_balls[0]["pos"] = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
	_balls[0]["vel"] = Vector2.ZERO

func _cue_spot_free(p: Vector2) -> bool:
	for b in _balls:
		if b["n"] != 0 and not b["sunk"] and p.distance_to(b["pos"]) < BALL_R * 2.05:
			return false
	return PLAY.grow(-BALL_R).has_point(p)

# --- Shooting and physics ---------------------------------------------------

func _shoot(angle: float, power: float, follow: float, side: float) -> void:
	_charging = false
	var cue: Dictionary = _balls[0]
	# Side spin pushes the cue ball a hair the other way ("squirt").
	var dir := Vector2.from_angle(angle - side * 0.012)
	var speed := MAX_POWER * clampf(power, 0.04, 1.0)
	cue["vel"] = dir * speed
	cue["follow"] = follow
	cue["side"] = side
	cue["pending"] = Vector2.ZERO
	_moving = true
	_first_hit = -1
	_pocketed.clear()
	_scratched = false
	_cue_touched = false
	_cue_slid = 0.0
	_cleared_at_start = _group_cleared(_shooter)
	_sound("cue", 0.3 + power * 0.7)

func _step(dt: float) -> void:
	for b in _balls:
		if b["sunk"]:
			continue
		var v: Vector2 = b["vel"]
		# Follow or draw paying out after the first contact.
		var pend: Vector2 = b["pending"]
		if not pend.is_zero_approx():
			var take := minf(pend.length(), 2200.0 * dt)
			v += pend.normalized() * take
			b["pending"] = pend - pend.normalized() * take
		var speed := v.length()
		if speed > 0.0:
			v = v / speed * maxf(0.0, speed - (FRICTION + speed * DRAG) * dt)
		var move := v * dt
		b["pos"] += move
		if b["n"] == 0 and not _cue_touched:
			_cue_slid += move.length()
		b["side"] = move_toward(b["side"], 0.0, 0.5 * dt)
		# Rolling: spin about the axis across the direction of travel.
		var dist := move.length()
		if dist > 0.0001:
			var axis := Vector3(-move.y, move.x, 0.0).normalized()
			b["basis"] = (Basis(axis, dist / BALL_R) * (b["basis"] as Basis)).orthonormalized()
		b["vel"] = v
		_collide_cushions(b)
		_check_pocket(b)
	for i in _balls.size():
		var a: Dictionary = _balls[i]
		if a["sunk"]:
			continue
		for j in range(i + 1, _balls.size()):
			var b: Dictionary = _balls[j]
			if b["sunk"]:
				continue
			var d: Vector2 = b["pos"] - a["pos"]
			var dist := d.length()
			if dist >= BALL_R * 2.0 or dist < 0.0001:
				continue
			var nrm := d / dist
			var overlap := BALL_R * 2.0 - dist
			a["pos"] -= nrm * overlap * 0.5
			b["pos"] += nrm * overlap * 0.5
			var rel: float = ((a["vel"] as Vector2) - (b["vel"] as Vector2)).dot(nrm)
			if rel <= 0.0:
				continue
			var impulse := nrm * rel * (1.0 + BALL_RESTITUTION) * 0.5
			a["vel"] -= impulse
			b["vel"] += impulse
			_sound("clack", rel / 900.0)
			for pair in [[a, b], [b, a]]:
				if pair[0]["n"] == 0:
					_cue_contact(pair[0], pair[1], rel)

## The cue ball's first contact: record what it hit (for fouls) and load
## the follow or draw, weaker the further it slid first.
func _cue_contact(cue: Dictionary, other: Dictionary, rel: float) -> void:
	if _first_hit == -1:
		_first_hit = other["n"]
	if _cue_touched:
		return
	_cue_touched = true
	var follow: float = cue.get("follow", 0.0)
	if absf(follow) > 0.01:
		var dir := ((other["pos"] as Vector2) - (cue["pos"] as Vector2)).normalized()
		var keep := exp(-_cue_slid / 700.0)
		cue["pending"] = dir * follow * rel * 0.7 * keep

func _collide_cushions(b: Dictionary) -> void:
	for seg in _segments:
		var a: Vector2 = seg[0]
		var e: Vector2 = seg[1]
		var p: Vector2 = b["pos"]
		var ab := e - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var closest := a + ab * t
		var d := p - closest
		var dist := d.length()
		if dist >= BALL_R or dist < 0.0001:
			continue
		var nrm := d / dist
		b["pos"] = closest + nrm * BALL_R
		var v: Vector2 = b["vel"]
		var vn := v.dot(nrm)
		if vn >= 0.0:
			continue
		var tangent := Vector2(-nrm.y, nrm.x)
		var vt := v.dot(tangent)
		# Side spin grabs the cloth on the cushion and throws the ball along it.
		vt += float(b["side"]) * -vn * 0.45
		b["side"] = b["side"] * 0.4
		v = tangent * vt * 0.97 - nrm * vn * CUSHION_RESTITUTION
		b["vel"] = v
		# A rail before the first contact kills most of the draw.
		if b["n"] == 0 and not _cue_touched:
			_cue_slid += 400.0
		_sound("cushion", -vn / 1100.0)

func _check_pocket(b: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	for i in _pockets.size():
		if p.distance_to(_pockets[i]) < POCKET_CAPTURE:
			_sink(b, _pockets[i])
			return
	# Anything that squeezes past the jaws goes in the nearest pocket.
	if not PLAY.grow(CUSHION_W * 0.8).has_point(p):
		var best := _pockets[0]
		for pk in _pockets:
			if pk.distance_to(p) < best.distance_to(p):
				best = pk
		_sink(b, best)

func _sink(b: Dictionary, pocket: Vector2) -> void:
	b["sunk"] = true
	b["sink_t"] = 1.0
	b["sink_to"] = pocket
	b["pending"] = Vector2.ZERO
	var speed := (b["vel"] as Vector2).length()
	b["vel"] = Vector2.ZERO
	_sound("pocket", 0.4 + speed / 1500.0)
	if b["n"] == 0:
		_scratched = true
	else:
		_pocketed.append(b["n"])

func _animate_sinking(delta: float) -> void:
	for b in _balls:
		if b["sunk"] and b["sink_t"] > 0.0:
			b["sink_t"] = maxf(0.0, b["sink_t"] - delta * 4.0)
			b["pos"] = (b["pos"] as Vector2).lerp(b["sink_to"], 0.35)

func _sync_balls() -> void:
	for b in _balls:
		var rect: ColorRect = b["rect"]
		var shown: bool = not b["sunk"] or b["sink_t"] > 0.0
		# In hand, the cue ball follows the mouse, faded until it's placed.
		if b["n"] == 0 and _ball_in_hand and _shooter == 0:
			shown = true
		rect.visible = shown
		if not shown:
			continue
		var k: float = 1.0 if not b["sunk"] else lerpf(0.55, 1.0, b["sink_t"])
		if b["n"] == 0 and _ball_in_hand:
			k = 1.0
		rect.size = Vector2.ONE * BALL_R * 2.0 * k
		rect.position = (b["pos"] as Vector2) - rect.size * 0.5
		rect.modulate.a = 0.55 if (b["n"] == 0 and _ball_in_hand and not _cue_spot_free(b["pos"])) else 1.0
		(b["mat"] as ShaderMaterial).set_shader_parameter("orient", b["basis"])

# --- Rules -----------------------------------------------------------------

func _group_of(n: int) -> int:
	if n >= 1 and n <= 7:
		return SOLIDS
	if n >= 9:
		return STRIPES
	return -1

func _remaining(group: int) -> int:
	return _balls.filter(func(b): return not b["sunk"] and b["n"] != 0 and _group_of(b["n"]) == group).size()

func _group_cleared(who: int) -> bool:
	return _groups[who] != -1 and _remaining(_groups[who]) == 0

func _legal_first(who: int, n: int) -> bool:
	if _groups[who] == -1:
		return n != 8
	if _group_cleared(who) or _cleared_at_start:
		return n == 8
	return _group_of(n) == _groups[who]

func _end_shot() -> void:
	_moving = false
	var who := "You" if _shooter == 0 else opponent_name
	var other := 1 - _shooter
	var foul := _scratched or _first_hit == -1 or not (_break_shot or _legal_first(_shooter, _first_hit))
	var eight := _pocketed.has(8)

	if eight:
		if _break_shot:
			_respot_eight()
			_message = "The 8 drops on the break -- spotted back up."
		elif _cleared_at_start and not foul:
			_end_game(_shooter == 0, "%s the 8 and %s it clean." % [who + (" call" if _shooter == 0 else " calls"), "drop" if _shooter == 0 else "drops"])
			return
		else:
			var why := "scratching on the 8" if _scratched else "sinking the 8 early"
			_end_game(_shooter == 1, "%s it %s." % [who + (" lose" if _shooter == 0 else " loses"), why])
			return

	var mine := _pocketed.filter(func(n): return n != 8 and (_groups[_shooter] == -1 or _group_of(n) == _groups[_shooter]))
	if _groups[_shooter] == -1 and not _break_shot and not foul and not mine.is_empty():
		_groups[_shooter] = _group_of(mine[0])
		_groups[other] = 1 - _groups[_shooter]
		_message = "%s %s on %s." % [who, "are" if _shooter == 0 else "is", "solids" if _groups[_shooter] == SOLIDS else "stripes"]
	elif not eight:
		_message = ""
	_break_shot = false

	if foul:
		var what := "scratched" if _scratched else ("hit nothing" if _first_hit == -1 else "hit the wrong ball first")
		_message = ("%s %s. Ball in hand for %s." % [who, what, "you" if other == 0 else opponent_name]).strip_edges()
		_give_ball_in_hand(other)
	elif not mine.is_empty():
		if _message == "":
			_message = "%s sank %s. Still %s shot." % [who, ", ".join(mine.map(func(n): return str(n))), "your" if _shooter == 0 else "their"]
		_start_turn(_shooter)
	else:
		if _message == "":
			_message = "%s missed." % who if _pocketed.is_empty() else "%s sank the wrong one. Turn over." % who
		_start_turn(other)

func _respot_eight() -> void:
	var b: Dictionary = _balls[8]
	var p := Vector2(PLAY.position.x + PLAY.size.x * 0.75, PLAY.get_center().y)
	while _balls.any(func(o): return o["n"] != 8 and not o["sunk"] and (o["pos"] as Vector2).distance_to(p) < BALL_R * 2.05):
		p.x += 2.0
	b["sunk"] = false
	b["sink_t"] = 0.0
	b["pos"] = p
	_pocketed.erase(8)

func _give_ball_in_hand(who: int) -> void:
	var cue: Dictionary = _balls[0]
	cue["sunk"] = true
	cue["sink_t"] = 0.0
	cue["vel"] = Vector2.ZERO
	_ball_in_hand = true
	_start_turn(who)
	if who == 0:
		_move_cue_in_hand(get_viewport().get_mouse_position())

func _start_turn(who: int) -> void:
	_shooter = who
	if who == 1:
		_ai_phase = "place" if _ball_in_hand else "think"
		_ai_timer = 0.9

func _end_game(won: bool, line: String) -> void:
	_message = line + ("  You take the $%d." % bet if won else "  %s holds out a hand. $%d, pal." % [opponent_name, bet])
	_finish(won)

func _finish(won: bool) -> void:
	_over = true
	GameState.log_event(("Won $%d at eight-ball off %s." if won else "Lost $%d at eight-ball to %s.") % [bet, opponent_name])
	_moving = false
	_charging = false
	if won:
		GameState.cash += bet
		GameState.cash_earned += bet
		GameState.cash_changed.emit(GameState.cash)
		SFX.play("cash")
	else:
		GameState.spend_cash(mini(bet, GameState.cash))
	finished.emit(won)

func _exit_tree() -> void:
	GameState.set_process(true)

func _close() -> void:
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

# --- The regular ------------------------------------------------------------

func _ai_update(delta: float) -> void:
	_ai_timer -= delta
	match _ai_phase:
		"place":
			if _ai_timer <= 0.0:
				_ai_place_cue()
				_ai_phase = "think"
				_ai_timer = 0.8
		"think":
			if _ai_timer <= 0.0:
				_ai_plan()
				_ai_phase = "aim"
				_ai_timer = 0.9
		"aim":
			_aim = lerp_angle(_aim, _ai_target_aim, minf(1.0, delta * 5.0))
			if _ai_timer <= 0.0:
				_aim = _ai_target_aim
				_ai_phase = "pull"
				_ai_timer = 0.55
				_charge = 0.0
				_charging = true
		"pull":
			_charge = lerpf(0.0, _ai_power, 1.0 - _ai_timer / 0.55)
			if _ai_timer <= 0.0:
				_ai_phase = ""
				_shoot(_aim, _ai_power, _ai_follow, 0.0)

## What the side at the table may legally hit first. The AI plays whoever's
## shooting, so the smoke test can run a whole game with it on both sides.
func _ai_legal_targets() -> Array:
	var g: int = _groups[_shooter]
	return _balls.filter(func(b):
		if b["sunk"] or b["n"] == 0:
			return false
		if g == -1:
			return b["n"] != 8
		if _remaining(g) == 0:
			return b["n"] == 8
		return _group_of(b["n"]) == g)

## Cheapest makeable shot from `cue`: {cost, angle, power} or {} if none.
func _ai_best_shot(cue: Vector2) -> Dictionary:
	var shots := _ai_shots(cue)
	return shots[0] if not shots.is_empty() else {}

## Every makeable shot from `cue`, easiest first.
func _ai_shots(cue: Vector2) -> Array:
	var found := []
	for b in _ai_legal_targets():
		var bp: Vector2 = b["pos"]
		for i in _pockets.size():
			var pocket: Vector2 = _pockets[i]
			var to_pocket := (pocket - bp).normalized()
			# Can the ball get into this pocket from here? Corners take a
			# wide range of angles, sides only a fairly square one.
			var window := 0.35 if i == 1 or i == 4 else -0.2
			if to_pocket.dot(-_pocket_dirs[i]) < window:
				continue
			var ghost := bp - to_pocket * BALL_R * 2.0
			var shot := ghost - cue
			var cut := absf(shot.normalized().angle_to(to_pocket))
			if cut > deg_to_rad(74.0):
				continue
			if not _path_clear(cue, ghost, [0, b["n"]]) or not _path_clear(bp, pocket, [0, b["n"]]):
				continue
			var cost: float = shot.length() * (1.0 + cut * 2.4) + bp.distance_to(pocket) * 0.8
			# Enough pace that the object ball still has some when it
			# reaches the pocket, carried back through the cut and the
			# cue ball's own roll to the contact point.
			var at_contact := _speed_to_arrive(bp.distance_to(pocket), 90.0) / maxf(cos(cut), 0.3) / (0.5 * (1.0 + BALL_RESTITUTION))
			var speed := _speed_to_arrive(shot.length(), at_contact)
			found.append({"cost": cost, "angle": shot.angle(), "power": clampf(speed / MAX_POWER, 0.08, 1.0)})
	found.sort_custom(func(a, b): return a["cost"] < b["cost"])
	return found

## Initial speed a ball needs to cover `dist` and still be doing `end_speed`,
## under the same friction and drag the table uses.
func _speed_to_arrive(dist: float, end_speed: float) -> float:
	# Run the deceleration backwards from the far end.
	var v := end_speed
	var covered := 0.0
	var dt := 1.0 / 240.0
	while covered < dist:
		v += (FRICTION + v * DRAG) * dt
		covered += v * dt
	return v

func _ai_plan() -> void:
	var cue: Vector2 = _balls[0]["pos"]
	if _break_shot:
		# Hard into the head ball, a hair off square.
		var head := Vector2(PLAY.position.x + PLAY.size.x * 0.75, PLAY.get_center().y)
		_ai_target_aim = (head - cue).angle() + randf_range(-0.01, 0.01)
		_ai_power = randf_range(0.9, 1.0)
		_ai_follow = 0.2
		return
	# A weak player doesn't always see the easy shot: they take one of the
	# first few they notice.
	var shots := _ai_shots(cue)
	var shot: Dictionary = {}
	if not shots.is_empty():
		var reach := clampi(int(round((1.0 - skill) * 3.0)), 0, shots.size() - 1)
		shot = shots[randi_range(0, reach)]
	if shot.is_empty():
		# Nothing on: roll up to the nearest legal ball and leave it there.
		var targets := _ai_legal_targets()
		targets.sort_custom(func(a, b): return cue.distance_to(a["pos"]) < cue.distance_to(b["pos"]))
		var t: Vector2 = targets[0]["pos"] if not targets.is_empty() else PLAY.get_center()
		shot = {"angle": (t - cue).angle(), "power": _speed_to_arrive(maxf(0.0, cue.distance_to(t) - BALL_R * 2.0), 120.0) / MAX_POWER}
		_message = "%s plays it safe." % opponent_name
	# Aim and pace both wobble by skill, and now and then a weaker player
	# just fluffs it.
	var error := deg_to_rad(lerpf(4.0, 0.35, skill)) * randfn(0.0, 1.0)
	if randf() < (1.0 - skill) * 0.25:
		error *= 3.0
	_ai_target_aim = shot["angle"] + error
	var pace := lerpf(0.3, 0.06, skill)
	_ai_power = clampf(shot["power"] * randf_range(1.0 - pace, 1.0 + pace), 0.15, 1.0)
	_ai_follow = randf_range(-0.3, 0.3) * skill

func _ai_place_cue() -> void:
	var best_pos := Vector2(PLAY.position.x + PLAY.size.x * 0.25, PLAY.get_center().y)
	var best_cost := INF
	var inner := PLAY.grow(-BALL_R * 2.0)
	for i in 70:
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		if not _cue_spot_free(p):
			continue
		var shot := _ai_best_shot(p)
		if not shot.is_empty() and shot["cost"] < best_cost:
			best_cost = shot["cost"]
			best_pos = p
	_balls[0]["pos"] = best_pos
	_balls[0]["sunk"] = false
	_ball_in_hand = false
	_message = "%s sets the cue ball down." % opponent_name

func _path_clear(from: Vector2, to: Vector2, ignore: Array) -> bool:
	var seg := to - from
	if seg.length_squared() < 0.01:
		return true
	for b in _balls:
		if b["sunk"] or ignore.has(b["n"]):
			continue
		var p: Vector2 = b["pos"]
		var t := clampf((p - from).dot(seg) / seg.length_squared(), 0.0, 1.0)
		if p.distance_to(from + seg * t) < BALL_R * 2.0:
			return false
	return true

## Where a ball rolled from `from` along `dir` first touches another ball:
## {t, ball} or {} if it reaches a cushion first.
func _sweep(from: Vector2, dir: Vector2) -> Dictionary:
	var hit := {}
	for b in _balls:
		if b["sunk"] or b["n"] == 0:
			continue
		var m: Vector2 = from - (b["pos"] as Vector2)
		var bq := m.dot(dir)
		var c := m.length_squared() - 4.0 * BALL_R * BALL_R
		var disc := bq * bq - c
		if disc < 0.0:
			continue
		var t := -bq - sqrt(disc)
		if t > 0.0 and (hit.is_empty() or t < hit["t"]):
			hit = {"t": t, "ball": b}
	return hit

func _cushion_distance(from: Vector2, dir: Vector2) -> float:
	var inner := PLAY.grow(-BALL_R)
	var ts := []
	if dir.x > 0.0001:
		ts.append((inner.end.x - from.x) / dir.x)
	elif dir.x < -0.0001:
		ts.append((inner.position.x - from.x) / dir.x)
	if dir.y > 0.0001:
		ts.append((inner.end.y - from.y) / dir.y)
	elif dir.y < -0.0001:
		ts.append((inner.position.y - from.y) / dir.y)
	return ts.min() if not ts.is_empty() else 0.0

# --- Drawing ------------------------------------------------------------------

func _draw_under(c: Control) -> void:
	# Cushions: rubber under cloth, lit along the nose.
	for seg_i in range(0, _segments.size()):
		var seg: Array = _segments[seg_i]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		if not _is_nose(a, b):
			continue
		var outward := _outward(a, b)
		var jaw_a := _jaw_end(a)
		var jaw_b := _jaw_end(b)
		var pts := PackedVector2Array([a, b, jaw_b, jaw_a])
		var lit := Color(0.07, 0.40, 0.34)
		var dark := Color(0.02, 0.17, 0.14)
		c.draw_polygon(pts, PackedColorArray([lit, lit, dark, dark]))
		c.draw_line(a + outward * 1.5, b + outward * 1.5, Color(0.10, 0.50, 0.42, 0.8), 1.5)
	# Diamonds on the rails.
	var rail_off := CUSHION_W + RAIL_W * 0.5
	for k in range(1, 8):
		if k == 4:
			continue
		var x := PLAY.position.x + PLAY.size.x * k / 8.0
		for y in [PLAY.position.y - rail_off, PLAY.end.y + rail_off]:
			_diamond(c, Vector2(x, y))
	for k in range(1, 4):
		var y := PLAY.position.y + PLAY.size.y * k / 4.0
		for x in [PLAY.position.x - rail_off, PLAY.end.x + rail_off]:
			_diamond(c, Vector2(x, y))
	# Pockets: a leather lip, then a drop into the dark.
	for i in _pockets.size():
		var p: Vector2 = _pockets[i]
		var r := 22.0 if i == 1 or i == 4 else 23.0
		c.draw_circle(p, r + 3.0, Color(0.09, 0.06, 0.05))
		c.draw_circle(p, r, Color(0.02, 0.018, 0.016))
		c.draw_circle(p + _pocket_dirs[i] * 3.0, r * 0.72, Color(0, 0, 0))
		c.draw_arc(p, r + 1.5, -2.6, -1.0, 12, Color(0.35, 0.25, 0.18, 0.5), 1.5)
	# Soft shadows, thrown away from the lamp over the middle of the table.
	var lamp := PLAY.get_center()
	for b in _balls:
		if b["sunk"] and b["sink_t"] <= 0.0:
			continue
		if b["n"] == 0 and _ball_in_hand:
			continue
		var p: Vector2 = b["pos"]
		var off := (p - lamp) * 0.025 + Vector2(1.5, 2.5)
		for k in 3:
			c.draw_circle(p + off, BALL_R * (1.05 + k * 0.12), Color(0, 0, 0, 0.16))

func _is_nose(a: Vector2, b: Vector2) -> bool:
	return is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)

func _outward(a: Vector2, b: Vector2) -> Vector2:
	var n := (b - a).orthogonal().normalized()
	return n if n.dot(PLAY.get_center() - a) > 0.0 else -n

## The outer end of the jaw that starts at nose point `p`.
func _jaw_end(p: Vector2) -> Vector2:
	for seg in _segments:
		if (seg[0] as Vector2).is_equal_approx(p) and not _is_nose(seg[0], seg[1]):
			return seg[1]
	return p

func _diamond(c: Control, p: Vector2) -> void:
	var s := 4.0
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.6, 0), p + Vector2(0, s), p + Vector2(-s * 0.6, 0)]), Color(0.86, 0.84, 0.76))
	c.draw_circle(p + Vector2(-0.8, -1.2), 1.0, Color(1, 1, 1, 0.7))

func _draw_over() -> void:
	var c := _overlay
	var font := ThemeDB.fallback_font
	_draw_numbers(c, font)
	var cue: Dictionary = _balls[0]
	var aiming: bool = not _moving and not _over and not _ball_in_hand
	if aiming:
		_draw_guides(c, cue["pos"])
		_draw_cue_stick(c, cue["pos"], _aim, _charge if (_charging or _ai_phase == "pull") else 0.0)
	_draw_scoreboard(c, font)
	_draw_power(c, font)
	_draw_spin(c, font)
	var hint := ""
	if _over:
		hint = "[E] / click to walk away from the table"
	elif _ball_in_hand and _shooter == 0:
		hint = "Ball in hand: move the cue ball and click to set it down"
	elif _shooter == 0 and not _moving:
		hint = "Mouse aim  -  hold click/Space, let go to shoot  -  W/S follow/draw  -  A/D side  -  R reset  -  Esc concede"
	elif _shooter == 1 and not _moving:
		hint = "%s is lining up..." % opponent_name
	_text(c, font, Vector2(PLAY.position.x - 56, 703), hint, 14, Color(0.78, 0.74, 0.62))
	if _howto:
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.75))
		var lines := [
			"EIGHT-BALL  -  first game? Here's the bar rules.",
			"",
			"You break. The first ball either of you pockets after that decides the",
			"groups: solids (1-7) or stripes (9-15). Pot one of yours to keep shooting.",
			"Clear your group, then sink the 8 to take the pot.",
			"Sink the 8 early, or scratch on it, and you lose.",
			"Fouls -- scratching, hitting nothing, hitting their ball first -- give the",
			"other side ball in hand.",
			"",
			"Mouse aims (arrows fine-tune, Shift slower). Hold click or Space and let go",
			"at the top of the swinging meter. W/S follow or draw, A/D side spin, R resets.",
			"The white line shows where the object ball goes.",
			"",
			"Click or press any key to rack up.",
		]
		for i in lines.size():
			_text(c, font, Vector2(250, 170 + i * 28), lines[i], 18, Color(0.95, 0.9, 0.78))

## The white number discs, drawn where each ball's rotation has them.
func _draw_numbers(c: Control, font: Font) -> void:
	for b in _balls:
		var n: int = b["n"]
		if n == 0 or (b["sunk"] and b["sink_t"] <= 0.0):
			continue
		var basis: Basis = b["basis"]
		for side in [1.0, -1.0]:
			var w: Vector3 = basis.z * side
			if w.z < 0.3:
				continue
			var p: Vector2 = (b["pos"] as Vector2) + Vector2(w.x, w.y) * BALL_R * 0.98
			var size := int(round(lerpf(6.0, 9.0, w.z)))
			var s := str(n)
			var width := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			c.draw_string(font, p + Vector2(-width * 0.5, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.05, 0.05, 0.05, smoothstep(0.3, 0.6, w.z)))

func _draw_guides(c: Control, cue: Vector2) -> void:
	var dir := Vector2.from_angle(_aim)
	var hit := _sweep(cue, dir)
	if hit.is_empty():
		var t := _cushion_distance(cue, dir)
		_dotted(c, cue + dir * BALL_R, cue + dir * t, Color(1, 1, 1, 0.35))
		c.draw_arc(cue + dir * t, BALL_R, 0, TAU, 24, Color(1, 1, 1, 0.3), 1.0)
		return
	var ghost: Vector2 = cue + dir * float(hit["t"])
	var target: Dictionary = hit["ball"]
	var legal := _shooter == 1 or _break_shot or _legal_first(0, target["n"])
	var col := Color(1, 1, 1, 0.45) if legal else Color(1, 0.35, 0.3, 0.55)
	_dotted(c, cue + dir * BALL_R, ghost, col)
	c.draw_arc(ghost, BALL_R, 0, TAU, 28, col, 1.2)
	if _shooter != 0:
		return
	# Where the object ball goes, and where the cue ball glances off to.
	var nrm := ((target["pos"] as Vector2) - ghost).normalized()
	var strength := absf(dir.dot(nrm))
	c.draw_line(target["pos"], (target["pos"] as Vector2) + nrm * (30.0 + 90.0 * strength), Color(1, 1, 1, 0.55), 1.5)
	var tangent := dir - nrm * dir.dot(nrm)
	if tangent.length() > 0.05:
		c.draw_line(ghost, ghost + tangent.normalized() * 40.0 * (1.0 - strength), Color(0.7, 0.85, 1.0, 0.4), 1.0)

func _dotted(c: Control, a: Vector2, b: Vector2, col: Color) -> void:
	c.draw_dashed_line(a, b, col, 1.5, 6.0)

## Tapered cue: blue chalk on the tip, white ferrule, maple shaft, a brass
## joint, and an ebony butt with a wrap -- pulled back with the power.
func _draw_cue_stick(c: Control, cue: Vector2, angle: float, pull_amt: float) -> void:
	var dir := Vector2.from_angle(angle)
	var perp := dir.orthogonal()
	var tip := cue - dir * (BALL_R + 5.0 + pull_amt * 90.0)
	var sections := [
		[0.0, 4.0, Color(0.25, 0.45, 0.75), Color(0.25, 0.45, 0.75)],
		[4.0, 14.0, Color(0.92, 0.9, 0.84), Color(0.92, 0.9, 0.84)],
		[14.0, 205.0, Color(0.93, 0.80, 0.58), Color(0.80, 0.62, 0.40)],
		[205.0, 212.0, Color(0.75, 0.62, 0.30), Color(0.55, 0.42, 0.18)],
		[212.0, 290.0, Color(0.20, 0.10, 0.06), Color(0.14, 0.07, 0.04)],
		[290.0, 350.0, Color(0.10, 0.10, 0.11), Color(0.10, 0.10, 0.11)],
		[350.0, CUE_LENGTH, Color(0.20, 0.10, 0.06), Color(0.08, 0.04, 0.02)],
	]
	var shadow_off := Vector2(5, 8)
	c.draw_line(tip + shadow_off, tip - dir * CUE_LENGTH + shadow_off, Color(0, 0, 0, 0.3), 7.0)
	for s in sections:
		var d0: float = s[0]
		var d1: float = s[1]
		var w0 := lerpf(2.6, 7.0, d0 / CUE_LENGTH)
		var w1 := lerpf(2.6, 7.0, d1 / CUE_LENGTH)
		var p0 := tip - dir * d0
		var p1 := tip - dir * d1
		var pts := PackedVector2Array([p0 + perp * w0, p1 + perp * w1, p1 - perp * w1, p0 - perp * w0])
		var hi: Color = s[2]
		var lo: Color = (s[3] as Color).darkened(0.35)
		c.draw_polygon(pts, PackedColorArray([hi, s[3], lo, lo]))
	# The wrap's diagonal lines.
	for k in 14:
		var d := 292.0 + k * 4.2
		var w := lerpf(2.6, 7.0, d / CUE_LENGTH)
		c.draw_line(tip - dir * d + perp * w, tip - dir * (d + 3.0) - perp * w, Color(0.28, 0.28, 0.3), 1.0)
	# A highlight down the shaft from the lamp.
	c.draw_line(tip - dir * 14.0 + perp * 0.8, tip - dir * 200.0 + perp * 2.5, Color(1, 1, 1, 0.25), 1.0)

func _draw_scoreboard(c: Control, font: Font) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 104), Color(0, 0, 0, 0.35))
	for who in 2:
		var x := 60.0 if who == 0 else 900.0
		var who_name := "You" if who == 0 else opponent_name
		var group: int = _groups[who]
		var label := who_name + ("" if group == -1 else ("  -  solids" if group == SOLIDS else "  -  stripes"))
		var active := _shooter == who and not _over
		_text(c, font, Vector2(x, 36), label, 20, Color(0.98, 0.88, 0.55) if active else Color(0.7, 0.68, 0.62))
		if active:
			c.draw_circle(Vector2(x - 16, 29), 5.0, Color(0.98, 0.75, 0.25))
		if group == -1:
			_text(c, font, Vector2(x, 70), "open table", 14, Color(0.55, 0.53, 0.5))
			continue
		var nums := range(1, 8) if group == SOLIDS else range(9, 16)
		for i in nums.size():
			var n: int = nums[i]
			var p := Vector2(x + 9 + i * 26, 66)
			var gone: bool = _balls[n]["sunk"]
			_mini_ball(c, p, n, 0.35 if gone else 1.0)
		if _remaining(group) == 0:
			_mini_ball(c, Vector2(x + 9 + 7 * 26 + 8, 66), 8, 1.0)
	var pot := "$%d on it" % bet
	var w := font.get_string_size(pot, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_text(c, font, Vector2(640 - w * 0.5, 38), pot, 22, Color(0.95, 0.85, 0.45))
	var mw := font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(c, font, Vector2(640 - mw * 0.5, 80), _message, 16, Color(0.9, 0.87, 0.8))

func _mini_ball(c: Control, p: Vector2, n: int, alpha: float) -> void:
	var col: Color = BALL_COLORS[n if n <= 8 else n - 8]
	col.a = alpha
	if n > 8:
		c.draw_circle(p, 9.0, Color(WHITE, alpha))
		c.draw_rect(Rect2(p.x - 9, p.y - 4.5, 18, 9), col)
	else:
		c.draw_circle(p, 9.0, col)
	c.draw_circle(p, 4.0, Color(WHITE, alpha))
	c.draw_circle(p + Vector2(-3, -3), 2.0, Color(1, 1, 1, 0.5 * alpha))

## Vertical power meter left of the table.
func _draw_power(c: Control, font: Font) -> void:
	var r := Rect2(70, PLAY.position.y + 20, 22, PLAY.size.y - 40)
	c.draw_rect(r.grow(3), Color(0, 0, 0, 0.6))
	c.draw_rect(r, Color(0.12, 0.12, 0.13))
	var h := r.size.y * _charge
	var steps := 24
	for i in steps:
		var f := float(i) / steps
		if f >= _charge:
			break
		var seg := Rect2(r.position.x, r.end.y - r.size.y * (f + 1.0 / steps), r.size.x, r.size.y / steps - 1.0)
		seg = seg.intersection(Rect2(r.position.x, r.end.y - h, r.size.x, h))
		c.draw_rect(seg, Color(0.3, 0.8, 0.35).lerp(Color(0.95, 0.25, 0.15), f))
	_text(c, font, Vector2(r.position.x - 12, r.end.y + 22), "POWER", 12, Color(0.6, 0.58, 0.54))

## The cue ball seen head-on, with a red dot where you're striking it.
func _draw_spin(c: Control, font: Font) -> void:
	var centre := Vector2(1208, PLAY.get_center().y)
	var r := 38.0
	c.draw_circle(centre + Vector2(2, 3), r, Color(0, 0, 0, 0.4))
	c.draw_circle(centre, r, WHITE.darkened(0.08))
	c.draw_circle(centre + Vector2(-10, -12), r * 0.45, Color(1, 1, 1, 0.35))
	c.draw_line(centre - Vector2(r, 0), centre + Vector2(r, 0), Color(0, 0, 0, 0.15), 1.0)
	c.draw_line(centre - Vector2(0, r), centre + Vector2(0, r), Color(0, 0, 0, 0.15), 1.0)
	var dot := centre + Vector2(_side, -_follow) * r * 0.7
	c.draw_circle(dot, 6.0, Color(0.8, 0.1, 0.1))
	_text(c, font, centre + Vector2(-19, r + 22), "SPIN", 12, Color(0.6, 0.58, 0.54))
	var what := "center"
	if absf(_follow) > 0.1 or absf(_side) > 0.1:
		what = ("follow" if _follow > 0.1 else ("draw" if _follow < -0.1 else "")) + (" " if absf(_follow) > 0.1 and absf(_side) > 0.1 else "") + ("right" if _side > 0.1 else ("left" if _side < -0.1 else ""))
	var w := font.get_string_size(what, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(c, font, centre + Vector2(-w * 0.5, r + 38), what, 12, Color(0.75, 0.72, 0.65))

func _text(c: Control, font: Font, p: Vector2, s: String, size: int, col: Color) -> void:
	c.draw_string(font, p + Vector2(1, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	c.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# --- Shaders -----------------------------------------------------------------

const NOISE := """
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; } return v; }
"""

## The bar around the table: dark panelling, the lamp's pool of light.
const ROOM_SHADER := """
shader_type canvas_item;
uniform vec2 table_centre;
""" + NOISE + """
void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	float boards = step(0.96, fract(px.x / 64.0)) * 0.25;
	vec3 wall = vec3(0.09, 0.055, 0.04) * (0.8 + fbm(px * vec2(0.01, 0.12)) * 0.4) * (1.0 - boards);
	vec2 d = (UV - table_centre) * vec2(1.0, 1.5);
	float lamp = exp(-dot(d, d) * 5.0);
	vec3 c = wall * (0.25 + lamp * 1.1) + vec3(0.10, 0.07, 0.03) * lamp * 0.4;
	COLOR = vec4(c, 1.0);
}
"""

## Worn felt, lit by the lamp over the middle, with the break area bleached
## and a few chalk smudges.
const FELT_SHADER := """
shader_type canvas_item;
uniform vec2 size;
""" + NOISE + """
void fragment() {
	vec2 px = UV * size;
	vec3 felt = vec3(0.045, 0.34, 0.29);
	float fibre = (hash(floor(px)) - 0.5) * 0.07 + (fbm(px * 0.02) - 0.5) * 0.16 + (fbm(px * 0.3) - 0.5) * 0.06;
	vec3 c = felt * (1.0 + fibre);
	float wear = smoothstep(0.32, 0.0, length((UV - vec2(0.74, 0.5)) * vec2(1.0, 1.7))) * 0.10
		+ smoothstep(0.35, 0.0, length((UV - vec2(0.25, 0.5)) * vec2(1.5, 1.2))) * 0.07;
	c = mix(c, vec3(0.20, 0.36, 0.32), wear);
	float chalk = smoothstep(0.70, 0.76, fbm(px * 0.035 + 17.0)) * 0.18;
	c = mix(c, vec3(0.35, 0.52, 0.72), chalk);
	vec2 d = (UV - 0.5) * vec2(1.0, 1.3);
	c *= 1.30 - smoothstep(0.08, 0.72, length(d)) * 0.80;
	COLOR = vec4(c, 1.0);
}
"""

## Varnished mahogany rails: grain running along each rail, a rounded edge
## catching the light, darker where hands and glasses wear it.
const WOOD_SHADER := """
shader_type canvas_item;
uniform vec2 size;
uniform float rail;
""" + NOISE + """
void fragment() {
	vec2 px = UV * size;
	float dx = min(px.x, size.x - px.x);
	float dy = min(px.y, size.y - px.y);
	bool vertical = dx < dy;
	vec2 g = vertical ? vec2(px.y, px.x) : px;
	float e = min(dx, dy);
	float grain = 0.5 + 0.5 * sin(g.y * 0.55 + fbm(vec2(g.x * 0.006, g.y * 0.12)) * 11.0);
	vec3 c = mix(vec3(0.16, 0.06, 0.025), vec3(0.38, 0.15, 0.06), grain * 0.8 + fbm(g * vec2(0.02, 0.4)) * 0.2);
	c *= 0.92 + (hash(floor(g * vec2(0.5, 2.0))) - 0.5) * 0.06;
	// Rounded outer edge and the step down to the cushion.
	c *= 0.6 + 0.4 * smoothstep(0.0, 7.0, e);
	c += vec3(0.9, 0.7, 0.5) * exp(-pow((e - 3.0) / 1.5, 2.0)) * 0.12;
	c *= 1.0 - smoothstep(rail - 6.0, rail, e) * 0.45;
	// Varnish sheen and the lamp.
	vec2 d = (UV - 0.5) * vec2(1.0, 1.3);
	c *= 1.15 - smoothstep(0.1, 0.8, length(d)) * 0.6;
	c += vec3(0.08, 0.06, 0.04) * smoothstep(0.55, 0.9, fbm(g * vec2(0.004, 0.05) + 3.0));
	COLOR = vec4(c, 1.0);
}
"""

## A ball as a lit sphere. `orient` turns the view-space normal into the
## ball's own frame, so the stripe and number discs roll with it.
const BALL_SHADER := """
shader_type canvas_item;
uniform vec3 base_color;
uniform int kind; // 0 cue, 1 solid, 2 stripe
uniform mat3 orient;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float alpha = 1.0 - smoothstep(0.90, 1.0, r);
	vec3 n = vec3(p.x, p.y, sqrt(max(0.0, 1.0 - r * r)));
	vec3 l = transpose(orient) * n;
	vec3 white = vec3(0.94, 0.93, 0.87);
	vec3 col = base_color;
	if (kind == 0) {
		col = white;
		// Two red dots, like a measle ball, so you can see it turn.
		if (abs(l.z) > 0.965) col = vec3(0.75, 0.08, 0.08);
	} else {
		if (kind == 2 && abs(l.y) > 0.52) col = white;
		if (abs(l.z) > 0.86) col = white;
	}
	vec3 L = normalize(vec3(-0.35, -0.45, 0.82));
	float diff = max(dot(n, L), 0.0);
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(n, H), 0.0), 70.0);
	float bounce = pow(1.0 - n.z, 2.5) * 0.35;
	vec3 c = col * (0.22 + diff * 0.9) + vec3(0.03, 0.22, 0.17) * bounce + vec3(1.0) * spec * 0.85;
	c *= 0.75 + 0.25 * smoothstep(-0.2, 0.6, dot(n.xy, -L.xy) + n.z);
	COLOR = vec4(c, alpha);
}
"""
