extends CanvasLayer
## The one-armed bandit by the Dive Bar's window: three reels, one payline,
## $1, $2 or $5 a pull. Pull the lever (drag it down, or Space / click SPIN)
## and the reels stop left to right; when the first two match, the third
## keeps turning a beat longer with a rising tone, the way real machines
## milk it.
##
## It's honest where real ones aren't: every reel stop is a straight random
## pick off the strip (REELS), so a near miss is exactly as likely as it
## looks and the next pull never "owes" you anything. Over time it keeps
## about 9 cents of every dollar (rtp() ~ 0.91) -- which is why the bar has
## it. The strips and paytable follow the classic three-reel layout: rarer
## symbols thin out toward the third reel, cherries pay on the first reel
## alone.
##
## Pulls take time: the clock is held while you're at the machine and moves
## on by MINUTES_PER_SPIN for every pull when you walk away.
##
## Art is drawn in code; Bungee (OFL) for the marquee, DSEG7 (OFL,
## github.com/keshikan/DSEG) for the LED meters; the reel motor, stops,
## lever and bells come from dev-tools/gen_slot_sfx.py and the coin rattle
## from Kenney's Casino Audio (CC0).

signal spun(win: int)

enum { CHERRY, LEMON, PLUM, BELL, BAR, SEVEN }
const SYMBOL_NAMES := ["Cherry", "Lemon", "Plum", "Bell", "BAR", "Seven"]
## Stops per symbol on each reel (22 a reel). The seven is 1 in 22 on the
## last two reels; cherries crowd the first.
const REEL_COUNTS := [
	{CHERRY: 5, LEMON: 6, PLUM: 4, BELL: 3, BAR: 2, SEVEN: 2},
	{CHERRY: 4, LEMON: 6, PLUM: 5, BELL: 3, BAR: 3, SEVEN: 1},
	{CHERRY: 2, LEMON: 7, PLUM: 6, BELL: 4, BAR: 2, SEVEN: 1},
]
## Three of a kind on the line, as multiples of the bet.
const PAY3 := {SEVEN: 150, BAR: 40, BELL: 18, PLUM: 12, CHERRY: 10, LEMON: 8}
const PAY_CHERRY2 := 6  # cherry, cherry, anything
const PAY_CHERRY1 := 1  # cherry on the first reel: your money back
const BETS := [1, 2, 5]
const BIG_WIN := 18  # x bet and up gets the big bells
const MINUTES_PER_SPIN := 1.5

# Layout (the 1280x720 canvas).
const REEL_X := [298.0, 468.0, 638.0]
const REEL_W := 150.0
const REEL_TOP := 196.0
const CELL := 88.0
const REEL_H := CELL * 3.0
const LINE_Y := REEL_TOP + CELL * 1.5
const LEVER_X := 868.0
const LEVER_TOP := 186.0
const LEVER_BOTTOM := 420.0
const SPIN_SPEED := 19.0  # symbols a second
const BRAKE := 3.2         # symbols it takes to ease to a stop
const OVERSHOOT := 0.14    # how far past it the reel kicks before the latch pulls it back

const GOLD := Color(1.0, 0.78, 0.25)
const RED := Color(0.86, 0.08, 0.1)
const CREAM := Color(0.97, 0.94, 0.86)

static var _strips: Array = []

var bet_index := 0
var fed := 0       # put in this visit
var paid := 0      # paid out this visit
var spins := 0
var last_win := 0
var _losses_in_a_row := 0
var _reels: Array = []  # {pos, state, start, end, t, dur, stop_at}
var _spinning := false
var _result: Array = [0, 0, 0]
var _time := 0.0
var _meter := 0.0      # the WIN meter counting up
var _win_flash := 0.0  # seconds of win lights left
var _big := false
var _jackpot := false
var _lever := 0.0      # 0 up .. 1 pulled
var _dragging := false
var _coins: Array = []  # {p, v, r}
var _message := ""
var _howto := false
var _anticipating := false
var _closed := false
var _hud: CanvasLayer
var _canvas: Control
var _reel_view: Control
var _font: Font
var _led: Font
var _players := {}
var _motor: AudioStreamPlayer
var _tick_acc := 0.0

static var _shown_howto := false

static func strips() -> Array:
	if _strips.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 1977
		for counts in REEL_COUNTS:
			var strip: Array = []
			for sym in counts:
				for i in counts[sym]:
					strip.append(sym)
			# A fixed shuffle, so the same symbols sit next to each other on
			# every visit, like a printed reel band.
			for i in range(strip.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var tmp = strip[i]
				strip[i] = strip[j]
				strip[j] = tmp
			_strips.append(strip)
	return _strips

## Multiple of the bet paid for this line.
static func payout(a: int, b: int, c: int) -> int:
	if a == b and b == c:
		return PAY3[a]
	if a == CHERRY and b == CHERRY:
		return PAY_CHERRY2
	if a == CHERRY:
		return PAY_CHERRY1
	return 0

## Return to player: the average fraction of a bet paid back, over every
## combination of stops.
static func rtp() -> float:
	var s := strips()
	var total := 0.0
	for a in s[0]:
		for b in s[1]:
			for c in s[2]:
				total += payout(a, b, c)
	return total / float(s[0].size() * s[1].size() * s[2].size())

func bet() -> int:
	return BETS[bet_index]

func start() -> void:
	layer = 95
	_hud = get_tree().get_first_node_in_group("hud") as CanvasLayer
	if _hud:
		_hud.visible = false
	GameState.set_process(false)
	_font = _load_font("res://assets/fonts/Bungee-Regular.ttf")
	_led = _load_font("res://assets/fonts/DSEG7Classic-Bold.ttf")
	var room := ColorRect.new()
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ShaderMaterial.new()
	bg.shader = Shader.new()
	bg.shader.code = ROOM_FX
	room.material = bg
	add_child(room)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw)
	_canvas.gui_input.connect(_on_gui_input)
	add_child(_canvas)
	# The reel bands, clipped to the window.
	_reel_view = Control.new()
	_reel_view.position = Vector2(REEL_X[0] - 14, REEL_TOP)
	_reel_view.size = Vector2(REEL_X[2] + REEL_W - REEL_X[0] + 28, REEL_H)
	_reel_view.clip_contents = true
	_reel_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel_view.draw.connect(_draw_reels)
	add_child(_reel_view)
	# Curved glass over the reels: shading toward the top and bottom of the
	# drum, and a glare streak.
	var glass := ColorRect.new()
	glass.position = Vector2(REEL_X[0] - 14, REEL_TOP - 10)
	glass.size = Vector2(REEL_X[2] + REEL_W - REEL_X[0] + 28, REEL_H + 20)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = GLASS_FX
	glass.material = gm
	add_child(glass)
	var over := Control.new()
	over.name = "Over"
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.draw.connect(_draw_over.bind(over))
	add_child(over)
	for n in ["reel_stop", "lever", "coin_in", "anticipation", "win_small", "win_big", "lose", "tick"]:
		_players[n] = _player("res://assets/sfx/slot_%s.wav" % n)
	_players["chips"] = _player("res://assets/sfx/kenney_casino/chips-collide-1.ogg")
	_players["stack"] = _player("res://assets/sfx/kenney_casino/chips-stack-3.ogg")
	_motor = _player("res://assets/sfx/slot_reel_loop.wav")
	if _motor.stream is AudioStreamWAV:
		var loop: AudioStreamWAV = _motor.stream.duplicate()
		loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop.loop_end = loop.get_length() * loop.mix_rate
		_motor.stream = loop
	var s := strips()
	for i in 3:
		# Start each reel somewhere different, at rest on a whole stop.
		_reels.append({"pos": float(randi() % s[i].size()), "state": "idle"})
		_result[i] = _sym_at(i, _reels[i]["pos"])
	_message = "The Lucky Devil hums to itself by the window. $%d a pull." % bet()
	_howto = not _shown_howto
	_shown_howto = true

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font

func _player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p

func _play(n: String, db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _players.get(n)
	if p and p.stream:
		p.volume_db = db
		p.pitch_scale = pitch
		p.play()

func _exit_tree() -> void:
	GameState.set_process(true)

# --- Spinning ---------------------------------------------------------------

func can_spin() -> bool:
	return not _spinning and not _closed and GameState.cash >= bet()

## Pulls. `forced` (three strip indices) is for tests.
func spin(forced: Array = []) -> bool:
	if _howto:
		_howto = false
	if not can_spin():
		if not _spinning and GameState.cash < bet():
			_message = "Not enough on you for a $%d pull." % bet() if GameState.cash >= BETS[0] else "Out of money. The machine doesn't say goodbye."
		return false
	GameState.spend_cash(bet())
	fed += bet()
	spins += 1
	last_win = 0
	_meter = 0.0
	_win_flash = 0.0
	_big = false
	_jackpot = false
	_spinning = true
	_message = ""
	_play("coin_in", -6.0)
	_play("lever", -4.0)
	if _motor.stream:
		_motor.volume_db = -10.0
		_motor.play()
	var s := strips()
	var stops: Array = forced if forced.size() == 3 else [randi() % s[0].size(), randi() % s[1].size(), randi() % s[2].size()]
	for i in 3:
		_result[i] = s[i][stops[i]]
	# Reels come to rest left to right; a match on the first two keeps the
	# third turning for the anticipation.
	var tease: bool = _result[0] == _result[1]
	for i in 3:
		var r: Dictionary = _reels[i]
		r["state"] = "spin"
		r.erase("end_at")
		r["stop_index"] = stops[i]
		r["stop_at"] = 0.75 + 0.42 * i + (1.5 if tease and i == 2 else 0.0)
		r["t"] = 0.0
	_anticipating = false
	return true

func _process(delta: float) -> void:
	_time += delta
	_lever = move_toward(_lever, 0.0, delta * 2.8) if not _dragging else _lever
	var any_moving := false
	for i in 3:
		var r: Dictionary = _reels[i]
		match r["state"]:
			"spin":
				any_moving = true
				r["t"] += delta
				# Spin up over a quarter second.
				var speed := SPIN_SPEED * minf(1.0, r["t"] / 0.25)
				r["pos"] += speed * delta
				if r["t"] >= r["stop_at"] and not r.has("end_at"):
					_begin_stop(i)
				# At full speed until the stop is a brake's length away.
				if r.has("end_at") and r["end_at"] - r["pos"] <= BRAKE:
					r["start"] = r["pos"]
					r["dur"] = 3.0 * (r["end_at"] - r["pos"]) / SPIN_SPEED
					r["t"] = 0.0
					r["state"] = "stopping"
					r["end"] = r["end_at"] - OVERSHOOT
					r.erase("end_at")
				if i == 2 and not _anticipating and _reels[1]["state"] == "idle" and _result[0] == _result[1]:
					_anticipating = true
					_play("anticipation", -8.0)
			"stopping":
				any_moving = true
				r["t"] += delta
				var k: float = clampf(r["t"] / r["dur"], 0.0, 1.0)
				if k < 1.0:
					# Cubic ease-out to a little past the stop (so the speed at
					# the hand-off matches the spin), then the latch pulls back.
					r["pos"] = lerpf(r["start"], r["end"] + OVERSHOOT, 1.0 - pow(1.0 - k, 3.0))
				else:
					var b: float = clampf((r["t"] - r["dur"]) / 0.16, 0.0, 1.0)
					r["pos"] = lerpf(r["end"] + OVERSHOOT, r["end"], sin(b * PI * 0.5))
					if b >= 1.0:
						r["state"] = "idle"
						r["pos"] = r["end"]
						_on_reel_stopped(i)
	if _spinning and not any_moving:
		_settle()
	# The WIN meter counts up with ticks.
	if _meter < last_win:
		var rate: float = maxf(6.0, last_win / 1.8)
		_meter = minf(float(last_win), _meter + rate * delta)
		_tick_acc += rate * delta
		if _tick_acc >= 1.0:
			_tick_acc = 0.0
			_play("tick", -14.0, randf_range(0.97, 1.05))
	_win_flash = maxf(0.0, _win_flash - delta)
	for c in _coins:
		c["v"].y += 1400.0 * delta
		c["p"] += c["v"] * delta
		c["r"] += delta * c["spin"]
		if c["p"].y > 676.0:
			c["p"].y = 676.0
			c["v"] = Vector2(c["v"].x * 0.5, -c["v"].y * 0.3)
	if _coins.size() > 80:
		_coins = _coins.slice(_coins.size() - 80)
	_canvas.queue_redraw()
	_reel_view.queue_redraw()
	get_node("Over").queue_redraw()

## Picks where the reel will come to rest: the next time the chosen stop
## comes round at least a brake's length on. The reel keeps full speed until
## it's BRAKE away, then eases in over exactly as long as keeps the speed
## continuous (x(t) = D(1-(1-t/T)^3) starts at 3D/T), so every reel brakes
## the same way however far round its stop was.
func _begin_stop(i: int) -> void:
	var r: Dictionary = _reels[i]
	var n: int = strips()[i].size()
	var end := ceilf(r["pos"] + BRAKE)
	while posmod(int(end), n) != r["stop_index"]:
		end += 1.0
	r["end_at"] = end + OVERSHOOT

func _on_reel_stopped(i: int) -> void:
	_play("reel_stop", -3.0, randf_range(0.96, 1.04))
	if i == 2:
		_players["anticipation"].stop()
		_motor.stop()

func _settle() -> void:
	_spinning = false
	_anticipating = false
	var mult := payout(_result[0], _result[1], _result[2])
	last_win = mult * bet()
	if last_win > 0:
		paid += last_win
		GameState.cash += last_win
		GameState.cash_earned += last_win
		GameState.cash_changed.emit(GameState.cash)
		_losses_in_a_row = 0
		_big = mult >= BIG_WIN
		_jackpot = _result[0] == SEVEN and _result[1] == SEVEN and _result[2] == SEVEN
		_win_flash = 4.0 if _big else 1.6
		_play("win_big" if _big else "win_small", -4.0)
		_play("stack" if _big else "chips", -6.0)
		_drop_coins(mini(60, 4 + mult * 2))
		_message = _win_line(mult)
		if _jackpot:
			MetaProgress.unlock("jackpot")
			GameState.log_event("Hit three sevens on the Dive Bar slot machine. $%d." % last_win)
	else:
		_losses_in_a_row += 1
		_play("lose", -12.0)
		_message = _loss_line()
	spun.emit(last_win)

func _win_line(mult: int) -> String:
	if _jackpot:
		return "SEVEN SEVEN SEVEN. $%d. The whole bar turns around. For a second you're somebody." % last_win
	if _big:
		return "$%d. Bells, lights, coins in the tray. It feels like it means something." % last_win
	if mult == PAY_CHERRY1:
		return "A cherry. Your dollar back, dressed up as a win."
	return "$%d. The lights go off like it means something." % last_win

func _loss_line() -> String:
	var down := fed - paid
	var near: bool = (_result[0] == _result[1] and _result[0] >= BELL)
	if near:
		return "Two %ss and a miss. Close isn't a thing, but it feels like one." % SYMBOL_NAMES[_result[0]].to_lower()
	if _losses_in_a_row == 6:
		return "It plays the same little tune every time it takes your money."
	if down >= 10 and _losses_in_a_row % 4 == 0:
		return "Down $%d. You tell yourself it's due. Every pull starts from zero." % down
	if GameState.cash < bet():
		return "That was the last of it." if GameState.cash < BETS[0] else "Not enough for another $%d pull." % bet()
	return ["Nothing.", "Nothing. The reels don't care.", "Lemon, plum, nothing.", "Nope."][spins % 4]

func _drop_coins(n: int) -> void:
	for k in n:
		_coins.append({"p": Vector2(randf_range(470, 600), randf_range(590, 610)), "v": Vector2(randf_range(-260, 260), randf_range(-520, -180)),
			"r": randf() * TAU, "spin": randf_range(-9, 9), "delay": 0.0})

func _sym_at(reel: int, pos: float) -> int:
	var s: Array = strips()[reel]
	return s[posmod(int(roundf(pos)), s.size())]

# --- Input ------------------------------------------------------------------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if event.pressed:
			if _howto:
				_howto = false
				return
			if p.distance_to(_knob()) < 34.0 and can_spin():
				_dragging = true
			elif _spin_rect().has_point(p):
				_pull()
			elif _bet_rect(-1).has_point(p):
				_change_bet(-1)
			elif _bet_rect(1).has_point(p):
				_change_bet(1)
			elif _leave_rect().has_point(p):
				_close()
		elif _dragging:
			_dragging = false
			if _lever > 0.75:
				spin()
	elif event is InputEventMouseMotion and _dragging:
		_lever = clampf((event.position.y - LEVER_TOP) / (LEVER_BOTTOM - LEVER_TOP - 60.0), 0.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("cancel_ui"):
		get_viewport().set_input_as_handled()
		_close()
	elif event.is_action_pressed("fire") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if _howto:
			_howto = false
		else:
			_pull()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("aim_left") or event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_change_bet(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("aim_right") or event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_change_bet(1)

## The lever, from a key or the SPIN button: it swings down on its own.
func _pull() -> void:
	if spin():
		_lever = 1.0

func _change_bet(d: int) -> void:
	if _spinning:
		return
	bet_index = clampi(bet_index + d, 0, BETS.size() - 1)
	_play("tick", -10.0, 0.8 + 0.1 * bet_index)

func _close() -> void:
	if _closed:
		return
	_closed = true
	if _spinning:
		# Walking off mid-spin still settles the pull.
		for i in 3:
			_reels[i]["state"] = "idle"
			_reels[i].erase("end_at")
		_settle()
	if spins > 0:
		var net := paid - fed
		if net >= 0:
			GameState.log_event("Played the slot machine at the Dive Bar: %d pulls, came out $%d up." % [spins, net])
		else:
			GameState.log_event("Played the slot machine at the Dive Bar: %d pulls, $%d gone." % [spins, -net])
		GameState.advance_clock(spins * MINUTES_PER_SPIN)
	if _hud and is_instance_valid(_hud):
		_hud.visible = true
	queue_free()

# --- Drawing ----------------------------------------------------------------

func _knob() -> Vector2:
	return Vector2(LEVER_X, LEVER_TOP + _lever * (LEVER_BOTTOM - LEVER_TOP - 60.0))

func _spin_rect() -> Rect2:
	return Rect2(590, 560, 200, 62)

func _bet_rect(d: int) -> Rect2:
	return Rect2(280, 560, 70, 62) if d < 0 else Rect2(470, 560, 70, 62)

func _leave_rect() -> Rect2:
	return Rect2(1060, 650, 180, 44)

## Withdrawal in your eyes: everything shivers a little.
func _shake() -> Vector2:
	var sick := GameState.sickness()
	if sick <= 0.25:
		return Vector2.ZERO
	return Vector2(sin(_time * 31.0), cos(_time * 27.0)) * 2.2 * sick

func _draw() -> void:
	var c := _canvas
	c.draw_set_transform(_shake())
	_draw_cabinet(c)
	_draw_marquee(c)
	_draw_lever(c)
	_draw_meters(c)
	_draw_buttons(c)
	_draw_tray(c)
	c.draw_set_transform(Vector2.ZERO)

func _draw_cabinet(c: Control) -> void:
	# Shadow on the wall, body, chrome trim, and a red side panel catching
	# the neon.
	_round_rect(c, Rect2(232, 26, 640, 690), 26, Color(0, 0, 0, 0.45))
	_round_rect(c, Rect2(220, 14, 640, 700), 26, Color(0.33, 0.04, 0.05))
	_round_rect(c, Rect2(228, 22, 624, 684), 22, Color(0.55, 0.07, 0.08))
	var grad := [Color(0.62, 0.1, 0.1), Color(0.42, 0.04, 0.05)]
	for k in 12:
		var y := 170.0 + k * 45.0
		c.draw_rect(Rect2(236, y, 608, 45), grad[0].lerp(grad[1], k / 11.0))
	# Chrome bezel round the reel window.
	_round_rect(c, Rect2(REEL_X[0] - 26, REEL_TOP - 22, REEL_X[2] + REEL_W - REEL_X[0] + 52, REEL_H + 44), 14, Color(0.78, 0.78, 0.8))
	_round_rect(c, Rect2(REEL_X[0] - 20, REEL_TOP - 16, REEL_X[2] + REEL_W - REEL_X[0] + 40, REEL_H + 32), 10, Color(0.38, 0.38, 0.42))
	_round_rect(c, Rect2(REEL_X[0] - 14, REEL_TOP - 10, REEL_X[2] + REEL_W - REEL_X[0] + 28, REEL_H + 20), 8, Color(0.05, 0.05, 0.06))
	# The lever's housing on the side.
	_round_rect(c, Rect2(846, 320, 44, 110), 10, Color(0.7, 0.7, 0.74))
	_round_rect(c, Rect2(852, 326, 32, 98), 8, Color(0.3, 0.3, 0.34))

func _draw_marquee(c: Control) -> void:
	var r := Rect2(250, 34, 580, 120)
	_round_rect(c, r, 18, Color(0.08, 0.02, 0.03))
	_round_rect(c, r.grow(-8), 14, Color(0.18, 0.02, 0.04))
	# Chasing bulbs round the edge; they race on a win.
	var speed := 14.0 if _win_flash > 0.0 else 5.0
	var n := 34
	var perim := 2.0 * (r.size.x + r.size.y)
	for k in n:
		var d := float(k) / n * perim
		var p := _perimeter_point(r.grow(-4), d / perim)
		var lit := int(_time * speed + k) % 3 == 0
		if _win_flash > 0.0 and int(_time * 8.0) % 2 == 0:
			lit = true
		var col := Color(1.0, 0.85, 0.4) if lit else Color(0.35, 0.22, 0.1)
		if lit:
			c.draw_circle(p, 9.0, Color(1.0, 0.7, 0.2, 0.25))
		c.draw_circle(p, 4.5, col)
	var title := "LUCKY DEVIL"
	var size := 58
	var w := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + 82)
	var glow := 0.5 + 0.5 * sin(_time * 3.0)
	c.draw_string_outline(_font, pos + Vector2(0, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10, Color(0, 0, 0, 0.6))
	c.draw_string_outline(_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(1.0, 0.25, 0.1, 0.35 + 0.25 * glow))
	c.draw_string(_font, pos, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, GOLD.lerp(CREAM, glow * 0.4))
	var sub := "★  ONE LINE  ·  ONE ARM  ·  NO MERCY  ★"
	var sw := ThemeDB.fallback_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	c.draw_string(ThemeDB.fallback_font, Vector2(r.position.x + (r.size.x - sw) * 0.5, r.position.y + 108), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.75, 0.5, 0.8))

func _perimeter_point(r: Rect2, f: float) -> Vector2:
	var perim := 2.0 * (r.size.x + r.size.y)
	var d := f * perim
	if d < r.size.x:
		return r.position + Vector2(d, 0)
	d -= r.size.x
	if d < r.size.y:
		return r.position + Vector2(r.size.x, d)
	d -= r.size.y
	if d < r.size.x:
		return r.position + Vector2(r.size.x - d, r.size.y)
	d -= r.size.x
	return r.position + Vector2(0, r.size.y - d)

func _draw_reels() -> void:
	var c := _reel_view
	c.draw_set_transform(_shake() - _reel_view.position)
	for i in 3:
		var x: float = REEL_X[i]
		# The paper band: cream, a touch darker at the edges.
		c.draw_rect(Rect2(x, REEL_TOP, REEL_W, REEL_H), CREAM)
		c.draw_rect(Rect2(x, REEL_TOP, 8, REEL_H), Color(0.85, 0.82, 0.74))
		c.draw_rect(Rect2(x + REEL_W - 8, REEL_TOP, 8, REEL_H), Color(0.85, 0.82, 0.74))
		var r: Dictionary = _reels[i]
		var pos: float = r["pos"]
		var speed := 0.0
		if r["state"] == "spin":
			speed = SPIN_SPEED * minf(1.0, r["t"] / 0.25)
		elif r["state"] == "stopping":
			speed = SPIN_SPEED * (1.0 - clampf(r["t"] / r["dur"], 0.0, 1.0)) * 1.0
		var s: Array = strips()[i]
		var base := int(floor(pos))
		for k in range(-2, 3):
			var idx := base + k
			var y := LINE_Y + (pos - idx) * CELL
			if y < REEL_TOP - CELL * 0.5 or y > REEL_TOP + REEL_H + CELL * 0.5:
				continue
			var sym: int = s[posmod(idx, s.size())]
			var centre := Vector2(x + REEL_W * 0.5, y)
			var on_line: bool = r["state"] == "idle" and absf(y - LINE_Y) < 1.0 and not _spinning
			var scale := 1.0
			if on_line and _win_flash > 0.0 and last_win > 0 and _counts_in_win(i):
				scale = 1.0 + 0.08 * sin(_time * 14.0)
				c.draw_rect(Rect2(x + 4, y - CELL * 0.5 + 3, REEL_W - 8, CELL - 6), Color(1.0, 0.85, 0.3, 0.35 + 0.25 * sin(_time * 14.0)))
			if speed > 7.0:
				# Motion blur: ghosts above and below.
				var smear := speed * 1.6
				_symbol(c, sym, centre + Vector2(0, -smear), scale, 0.28)
				_symbol(c, sym, centre + Vector2(0, smear), scale, 0.28)
				_symbol(c, sym, centre, scale, 0.5)
			else:
				_symbol(c, sym, centre, scale, 1.0)
		# The anticipation glow round the last reel.
		if i == 2 and _anticipating and r["state"] != "idle":
			var a := 0.5 + 0.5 * sin(_time * 18.0)
			c.draw_rect(Rect2(x - 5, REEL_TOP - 5, REEL_W + 10, REEL_H + 10), Color(1.0, 0.8, 0.2, 0.5 + 0.5 * a), false, 4.0)

func _counts_in_win(i: int) -> bool:
	var mult := payout(_result[0], _result[1], _result[2])
	if _result[0] == _result[1] and _result[1] == _result[2]:
		return true
	if mult == PAY_CHERRY2:
		return i < 2
	return i == 0

func _symbol(c: Control, sym: int, p: Vector2, k: float, a: float) -> void:
	var sh := Color(0, 0, 0, 0.18 * a)
	match sym:
		CHERRY:
			var stem := Color(0.2, 0.45, 0.12, a)
			c.draw_polyline(_curve(p + Vector2(-14, 4) * k, p + Vector2(-2, -22) * k, p + Vector2(6, -26) * k), stem, 3.5 * k)
			c.draw_polyline(_curve(p + Vector2(15, 8) * k, p + Vector2(12, -14) * k, p + Vector2(6, -26) * k), stem, 3.5 * k)
			c.draw_colored_polygon(_ellipse(p + Vector2(16, -26) * k, Vector2(13, 6) * k, -0.4), Color(0.25, 0.6, 0.15, a))
			for q in [Vector2(-14, 14), Vector2(15, 18)]:
				c.draw_circle(p + (q + Vector2(2, 3)) * k, 16 * k, sh)
				c.draw_circle(p + q * k, 16 * k, Color(0.62, 0.02, 0.06, a))
				c.draw_circle(p + (q + Vector2(-1, -1)) * k, 13 * k, Color(0.88, 0.07, 0.12, a))
				c.draw_circle(p + (q + Vector2(-6, -6)) * k, 4 * k, Color(1, 1, 1, 0.75 * a))
		LEMON:
			c.draw_colored_polygon(_lemon(p + Vector2(3, 4) * k, k), sh)
			c.draw_colored_polygon(_lemon(p, k), Color(0.85, 0.65, 0.0, a))
			c.draw_colored_polygon(_lemon(p + Vector2(-1, -1) * k, k * 0.9), Color(1.0, 0.88, 0.15, a))
			c.draw_colored_polygon(_ellipse(p + Vector2(-10, -8) * k, Vector2(8, 4) * k, -0.3), Color(1, 1, 0.85, 0.7 * a))
		PLUM:
			c.draw_circle(p + Vector2(3, 5) * k, 27 * k, sh)
			c.draw_circle(p + Vector2(0, 2) * k, 27 * k, Color(0.3, 0.06, 0.36, a))
			c.draw_circle(p + Vector2(-2, 0) * k, 23 * k, Color(0.5, 0.14, 0.6, a))
			c.draw_line(p + Vector2(0, -22) * k, p + Vector2(0, 20) * k, Color(0.3, 0.06, 0.36, 0.5 * a), 2.0 * k)
			c.draw_colored_polygon(_ellipse(p + Vector2(10, -26) * k, Vector2(12, 5) * k, -0.5), Color(0.25, 0.6, 0.15, a))
			c.draw_circle(p + Vector2(-10, -9) * k, 5 * k, Color(1, 1, 1, 0.55 * a))
		BELL:
			var pts := PackedVector2Array()
			for v in [Vector2(0, -30), Vector2(10, -26), Vector2(15, -14), Vector2(17, 4), Vector2(24, 16), Vector2(28, 22),
					Vector2(-28, 22), Vector2(-24, 16), Vector2(-17, 4), Vector2(-15, -14), Vector2(-10, -26)]:
				pts.append(p + v * k)
			var shadow := PackedVector2Array()
			for v in pts:
				shadow.append(v + Vector2(3, 4) * k)
			c.draw_colored_polygon(shadow, sh)
			c.draw_circle(p + Vector2(0, 26) * k, 7 * k, Color(0.6, 0.42, 0.05, a))
			c.draw_colored_polygon(pts, Color(0.85, 0.6, 0.05, a))
			c.draw_colored_polygon(_ellipse(p + Vector2(-6, -8) * k, Vector2(5, 14) * k, 0.15), Color(1, 0.95, 0.6, 0.6 * a))
			c.draw_line(p + Vector2(-27, 20) * k, p + Vector2(27, 20) * k, Color(0.6, 0.42, 0.05, a), 3.0 * k)
		BAR:
			var r := Rect2(p - Vector2(50, 18) * k, Vector2(100, 36) * k)
			_round_rect(c, Rect2(r.position + Vector2(3, 4) * k, r.size), 6 * k, sh)
			_round_rect(c, r, 6 * k, Color(0.06, 0.06, 0.07, a))
			_round_rect(c, r.grow(-3 * k), 4 * k, Color(0.95, 0.95, 0.92, a))
			_round_rect(c, r.grow(-6 * k), 3 * k, Color(0.08, 0.08, 0.09, a))
			var fs := int(26 * k)
			var tw := _font.get_string_size("BAR", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			c.draw_string(_font, p + Vector2(-tw * 0.5, 10 * k), "BAR", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.97, 0.94, 0.86, a))
		SEVEN:
			var fs := int(76 * k)
			var tw := _font.get_string_size("7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := p + Vector2(-tw * 0.5, 27 * k)
			c.draw_string(_font, at + Vector2(3, 4) * k, "7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
			c.draw_string_outline(_font, at, "7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8 * k), Color(0.7, 0.5, 0.05, a))
			c.draw_string(_font, at, "7", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.88, 0.06, 0.1, a))

func _curve(a: Vector2, ctrl: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts

func _ellipse(centre: Vector2, radii: Vector2, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rot))
	return pts

func _lemon(p: Vector2, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		# Pointed ends: stretch the radius toward a = 0 and PI.
		var r := 1.0 + 0.22 * pow(absf(cos(a)), 6.0)
		pts.append(p + Vector2(cos(a) * 30.0 * r, sin(a) * 21.0).rotated(-0.35) * k)
	return pts

func _draw_lever(c: Control) -> void:
	var knob := _knob()
	var pivot := Vector2(LEVER_X, 375)
	# The arm runs from the housing to the knob, foreshortening as it comes
	# down toward you.
	c.draw_line(pivot + Vector2(4, 4), knob + Vector2(4, 4), Color(0, 0, 0, 0.35), 12.0)
	c.draw_line(pivot, knob, Color(0.75, 0.75, 0.78), 11.0)
	c.draw_line(pivot + Vector2(-3, 0), knob + Vector2(-3, 0), Color(0.95, 0.95, 0.98), 3.0)
	var rad := lerpf(26.0, 30.0, _lever)
	c.draw_circle(knob + Vector2(4, 5), rad, Color(0, 0, 0, 0.4))
	c.draw_circle(knob, rad, Color(0.6, 0.02, 0.05))
	c.draw_circle(knob + Vector2(-3, -3), rad - 4, Color(0.9, 0.08, 0.12))
	c.draw_circle(knob + Vector2(-9, -10), rad * 0.28, Color(1, 1, 1, 0.7))
	c.draw_circle(pivot, 12.0, Color(0.55, 0.55, 0.6))

func _draw_meters(c: Control) -> void:
	var items := [["CREDIT", "$%d" % GameState.cash, 280.0], ["BET", "$%d" % bet(), 470.0], ["WIN", "$%d" % int(_meter), 640.0]]
	for it in items:
		var r := Rect2(it[2], 486, 150 if it[0] != "BET" else 150, 56)
		_round_rect(c, r, 6, Color(0.02, 0.02, 0.02))
		c.draw_string(ThemeDB.fallback_font, r.position + Vector2(8, 15), it[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.75, 0.4, 0.8))
		var digits: String = str(it[1]).trim_prefix("$")
		var ghost := "8".repeat(maxi(4, digits.length()))
		var dw := _led.get_string_size(ghost, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var at := r.position + Vector2(r.size.x - dw - 10, 48)
		c.draw_string(_led, at, ghost, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.25, 0.03, 0.02))
		var tw := _led.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var col := Color(1.0, 0.2, 0.1)
		if it[0] == "WIN" and _win_flash > 0.0 and int(_time * 10.0) % 2 == 0:
			col = Color(1.0, 0.85, 0.3)
		c.draw_string(_led, r.position + Vector2(r.size.x - tw - 10, 48), digits, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)

func _draw_buttons(c: Control) -> void:
	for d in [-1, 1]:
		var r := _bet_rect(d)
		var ok := not _spinning and (bet_index > 0 if d < 0 else bet_index < BETS.size() - 1)
		_button(c, r, "BET -" if d < 0 else "BET +", Color(0.95, 0.75, 0.15) if ok else Color(0.4, 0.35, 0.25), 18)
	var ready := can_spin()
	var pulse := 0.5 + 0.5 * sin(_time * 5.0) if ready else 0.0
	_button(c, _spin_rect(), "SPIN", Color(0.9, 0.12, 0.1).lerp(Color(1, 0.4, 0.3), pulse * 0.4) if ready else Color(0.35, 0.15, 0.14), 30)
	# Bet chips between the two bet buttons.
	for i in BETS.size():
		var p := Vector2(375 + i * 35, 591)
		var on := i == bet_index
		c.draw_circle(p, 14.0, Color(0.95, 0.8, 0.3) if on else Color(0.3, 0.25, 0.2))
		c.draw_circle(p, 10.0, Color(0.75, 0.1, 0.08) if on else Color(0.2, 0.16, 0.14))
		var s := str(BETS[i])
		var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		c.draw_string(ThemeDB.fallback_font, p + Vector2(-w * 0.5, 5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CREAM)

func _button(c: Control, r: Rect2, label: String, col: Color, size: int) -> void:
	_round_rect(c, Rect2(r.position + Vector2(0, 6), r.size), 12, col.darkened(0.6))
	_round_rect(c, r, 12, col)
	_round_rect(c, Rect2(r.position + Vector2(6, 4), Vector2(r.size.x - 12, r.size.y * 0.4)), 8, Color(1, 1, 1, 0.18))
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(_font, r.position + Vector2((r.size.x - w) * 0.5, r.size.y * 0.5 + size * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.12, 0.04, 0.02))

func _draw_tray(c: Control) -> void:
	_round_rect(c, Rect2(440, 640, 200, 52), 10, Color(0.7, 0.7, 0.74))
	_round_rect(c, Rect2(448, 646, 184, 40), 8, Color(0.12, 0.12, 0.14))
	for coin in _coins:
		var p: Vector2 = coin["p"]
		var squash := absf(cos(coin["r"]))
		c.draw_colored_polygon(_ellipse(p, Vector2(10.0 * maxf(squash, 0.15), 10.0), 0.0), Color(0.75, 0.55, 0.12))
		c.draw_colored_polygon(_ellipse(p + Vector2(-1, -1), Vector2(7.5 * maxf(squash, 0.1), 7.5), 0.0), Color(1.0, 0.82, 0.3))

func _draw_over(c: Control) -> void:
	var f := ThemeDB.fallback_font
	# Payline across the reels, over the glass.
	var lc := Color(1.0, 0.15, 0.1, 0.85)
	if _win_flash > 0.0 and last_win > 0:
		lc = Color(1.0, 0.85, 0.2, 0.6 + 0.4 * sin(_time * 14.0))
	c.draw_line(Vector2(REEL_X[0] - 8, LINE_Y), Vector2(REEL_X[2] + REEL_W + 8, LINE_Y), lc, 2.0)
	for side in [-1, 1]:
		var x: float = REEL_X[0] - 12 if side < 0 else REEL_X[2] + REEL_W + 12
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - 10 * side, LINE_Y - 9), Vector2(x, LINE_Y), Vector2(x - 10 * side, LINE_Y + 9)]), lc)
	_draw_panel(c, f)
	if _win_flash > 0.0 and _big:
		var a := clampf(_win_flash / 4.0, 0.0, 1.0)
		var label := "JACKPOT" if _jackpot else "BIG WIN"
		var size := 96
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var bob := sin(_time * 6.0) * 6.0
		var p := Vector2(540 - w * 0.5, 120 + bob)
		c.draw_string_outline(_font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, Color(0.4, 0.05, 0.02, a))
		c.draw_string(_font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1.0, 0.85, 0.3, a))
	if _howto:
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.75))
		var lines := [
			"THE LUCKY DEVIL  -  one line, three reels.",
			"",
			"Pull the lever (drag the red knob down), or press SPACE / click SPIN.",
			"Left / Right changes the bet: $1, $2 or $5 a pull.",
			"Three of a kind on the red line pays. A cherry on the first reel",
			"gives your bet back; two cherries pay six times it.",
			"",
			"Every pull is its own coin toss. It keeps about 9 cents on the dollar.",
			"Time passes while you play.",
			"",
			"Click to start.",
		]
		for i in lines.size():
			_text(c, f, Vector2(290, 200 + i * 30), lines[i], 19, Color(0.95, 0.9, 0.78), 760)

func _draw_panel(c: Control, f: Font) -> void:
	var x := 930.0
	_round_rect(c, Rect2(x - 20, 30, 350, 410), 14, Color(0.04, 0.02, 0.02, 0.85))
	c.draw_string(_font, Vector2(x, 70), "PAYS", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, GOLD)
	c.draw_string(f, Vector2(x + 210, 68), "x bet  ($%d)" % bet(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.7, 0.62))
	var rows := [[SEVEN, 3, PAY3[SEVEN]], [BAR, 3, PAY3[BAR]], [BELL, 3, PAY3[BELL]], [PLUM, 3, PAY3[PLUM]],
		[CHERRY, 3, PAY3[CHERRY]], [LEMON, 3, PAY3[LEMON]], [CHERRY, 2, PAY_CHERRY2], [CHERRY, 1, PAY_CHERRY1]]
	for i in rows.size():
		var y := 104.0 + i * 40.0
		var row: Array = rows[i]
		var hit: bool = last_win > 0 and _win_flash > 0.0 and payout(_result[0], _result[1], _result[2]) == row[2] and (row[1] == 3) == (_result[0] == _result[1] and _result[1] == _result[2])
		if hit:
			_round_rect(c, Rect2(x - 10, y - 18, 330, 36), 6, Color(1, 0.8, 0.2, 0.25 + 0.15 * sin(_time * 12.0)))
		for k in 3:
			var p := Vector2(x + 18 + k * 44, y)
			if k < row[1]:
				_symbol(c, row[0], p, 0.42, 1.0)
			else:
				c.draw_string(f, p + Vector2(-10, 6), "any", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.56, 0.5))
		var pays := str(row[2])
		c.draw_string(_led, Vector2(x + 220, y + 10), pays, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.3, 0.15))
		c.draw_string(f, Vector2(x + 275, y + 8), "$%d" % (row[2] * bet()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.7, 0.62))
	# Tonight's tally: the number the machine would rather you didn't see.
	var y0 := 470.0
	_text(c, f, Vector2(x - 10, y0), "Tonight: %d pull%s" % [spins, "" if spins == 1 else "s"], 16, Color(0.85, 0.8, 0.7), 340)
	_text(c, f, Vector2(x - 10, y0 + 24), "Fed in $%d   ·   Paid out $%d" % [fed, paid], 15, Color(0.72, 0.68, 0.6), 340)
	var net := paid - fed
	if spins > 0:
		_text(c, f, Vector2(x - 10, y0 + 48), ("Up $%d" % net) if net >= 0 else ("Down $%d" % -net), 18, Color(0.5, 0.9, 0.5) if net >= 0 else Color(0.95, 0.45, 0.4), 340)
	_text_wrapped(c, f, Rect2(x - 10, y0 + 76, 340, 90), _message, 15, Color(0.95, 0.9, 0.8))
	_button(c, _leave_rect(), "WALK AWAY", Color(0.75, 0.72, 0.65), 16)
	var hint := "Drag the knob / Space: pull  -  Left/Right: bet  -  Esc: walk away"
	if GameState.using_pad:
		hint = "Cross: pull  -  Left/Right: bet  -  Circle: walk away"
	_text(c, f, Vector2(30, 712), hint, 13, Color(0.6, 0.58, 0.54), 900)

func _text(c: Control, f: Font, p: Vector2, s: String, size: int, col: Color, width := 360.0) -> void:
	c.draw_string(f, p + Vector2(1, 2), s, HORIZONTAL_ALIGNMENT_LEFT, width, size, Color(0, 0, 0, 0.8))
	c.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)

func _text_wrapped(c: Control, f: Font, r: Rect2, s: String, size: int, col: Color) -> void:
	c.draw_multiline_string(f, r.position + Vector2(1, 2), s, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, size, 5, Color(0, 0, 0, 0.8))
	c.draw_multiline_string(f, r.position, s, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, size, 5, col)

func _round_rect(c: Control, r: Rect2, radius: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	c.draw_style_box(sb, r)

## The bar behind the machine: dark wood, a red neon wash from the left and
## smoke drifting through it.
const ROOM_FX := """
shader_type canvas_item;
uniform float time_scale = 0.05;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec2 uv = UV;
	vec3 wood = vec3(0.07, 0.04, 0.03) * (0.85 + 0.3 * noise(vec2(uv.x * 3.0, uv.y * 60.0)));
	vec3 neon = vec3(0.9, 0.1, 0.15) * 0.35 * smoothstep(0.9, 0.0, distance(uv, vec2(0.08, 0.3)));
	vec3 blue = vec3(0.15, 0.3, 0.9) * 0.25 * smoothstep(0.7, 0.0, distance(uv, vec2(0.95, 0.85)));
	float t = TIME * time_scale;
	float smoke = noise(uv * 4.0 + vec2(t * 3.0, -t)) * noise(uv * 7.0 - vec2(t, t * 2.0));
	vec3 c = wood + neon + blue + vec3(0.12, 0.1, 0.1) * smoke;
	c *= 1.0 - 0.55 * pow(distance(uv, vec2(0.45, 0.5)), 1.6);
	COLOR = vec4(c, 1.0);
}
"""

## Over the reel window: the drum curving away top and bottom, and a glare.
const GLASS_FX := """
shader_type canvas_item;
void fragment() {
	float curve = pow(abs(UV.y - 0.5) * 2.0, 2.2);
	float shade = curve * 0.78;
	float glare = smoothstep(0.06, 0.0, abs(UV.x * 0.6 + UV.y * 0.4 - 0.32)) * 0.16;
	glare += smoothstep(0.025, 0.0, abs(UV.x * 0.6 + UV.y * 0.4 - 0.42)) * 0.08;
	float top = smoothstep(0.12, 0.0, UV.y) * 0.1;
	COLOR = vec4(mix(vec3(0.0), vec3(1.0), glare + top), clamp(shade + glare + top, 0.0, 0.92));
}
"""
